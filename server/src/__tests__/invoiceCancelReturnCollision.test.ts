/**
 * REGRESSION: invoice cancellation must never void ANOTHER invoice's
 * sales-return GL.
 *
 * Root cause this suite pins: sales-return postings are keyed to the
 * RETURN document — journal_lines(reference_type = 'INVOICE_RETURN',
 * reference_id = invoice_returns.id) — and invoice_returns.id is an
 * AUTOINCREMENT sequence that is completely independent of invoices.id.
 * Cancelling invoice N used to void INVOICE_RETURN lines by the bare
 * invoice id N, so it reversed the AR / Sales Returns / Tax Payable /
 * COGS of whichever return happened to carry the numeric id N — even a
 * return raised against a different invoice.
 *
 * The suite deliberately engineers the numeric collision, then proves
 * the other invoice's return GL, stock, invoice aggregates and customer
 * ledger are byte-for-byte untouched while the cancellation itself still
 * reverses exactly its own postings.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie,
  createItem,
  purchaseStock,
  createCustomer,
  createInvoice,
  processReturn,
  fetchPosition,
  glTotalsFor,
  customerLedgerNet,
} from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

async function cancel(invoiceId: number, cookie: string): Promise<request.Response> {
  return request(app).put(`/api/invoices/${invoiceId}/cancel`).set('Cookie', cookie);
}

function stockQty(itemId: number, warehouseId: number): number {
  return Number(
    (db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(itemId, warehouseId) as { quantity: number }).quantity,
  );
}

function maxId(table: string): number {
  return Number((db.prepare(`SELECT COALESCE(MAX(id), 0) AS n FROM ${table}`).get() as { n: number }).n);
}

/** Active (unvoided) journal lines of one GL group, with their account codes. */
function activeLines(referenceType: string, referenceId: number): Array<{
  id: number; account_code: string; debit: number; credit: number; void_reason: string | null;
}> {
  return db.prepare(`
    SELECT jl.id, coa.code AS account_code, jl.debit, jl.credit, jl.void_reason
    FROM journal_lines jl
    JOIN chart_of_accounts coa ON coa.id = jl.account_id
    WHERE jl.reference_type = ? AND jl.reference_id = ? AND jl.voided = 0
    ORDER BY jl.id
  `).all(referenceType, referenceId) as Array<{
    id: number; account_code: string; debit: number; credit: number; void_reason: string | null;
  }>;
}

/** Σ debit/credit over one GL group, voided rows excluded. */
function accountTotals(referenceType: string, referenceId: number, accountCode: string): { debit: number; credit: number } {
  const row = db.prepare(`
    SELECT COALESCE(SUM(jl.debit), 0) AS debit, COALESCE(SUM(jl.credit), 0) AS credit
    FROM journal_lines jl
    JOIN chart_of_accounts coa ON coa.id = jl.account_id
    WHERE jl.reference_type = ? AND jl.reference_id = ? AND jl.voided = 0 AND coa.code = ?
  `).get(referenceType, referenceId, accountCode) as { debit: number; credit: number };
  return { debit: Number(row.debit), credit: Number(row.credit) };
}

describe('invoice cancel vs return id collision', () => {
  let authCookie: string;
  let warehouseId: number;
  let customerA: number;
  let customerB: number;
  let customerC: number;
  let customerD: number;
  let itemA: number;
  let itemB: number;
  let itemD: number;
  let burnerItem: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;

    customerA = await createCustomer('Collision Customer A', authCookie);
    customerB = await createCustomer('Collision Customer B', authCookie);
    customerC = await createCustomer('Collision Customer C', authCookie);

    itemA = await createItem('Collision Widget A', authCookie);
    await purchaseStock(itemA, warehouseId, 10, 50, authCookie);
    itemB = await createItem('Collision Widget B', authCookie);
    await purchaseStock(itemB, warehouseId, 10, 100, authCookie);

    customerD = await createCustomer('Collision Customer D', authCookie);
    itemD = await createItem('Collision Widget D', authCookie);
    await purchaseStock(itemD, warehouseId, 10, 60, authCookie);
    // A separate item for the id-alignment burners so the invoices
    burnerItem = await createItem('Collision Burner Widget', authCookie);
    await purchaseStock(burnerItem, warehouseId, 40, 10, authCookie);
  });

  /**
   * Advance the invoice_returns AUTOINCREMENT sequence so the NEXT return
   * takes `targetReturnId`. Each burner raises + settles one throwaway
   * invoice/return pair, which consumes exactly one return id and leaves
   * the accounting invariants intact (fully paid, fully returned, net 0).
   * The target is fixed up-front, so this always terminates.
   */
  async function alignNextReturnIdTo(targetReturnId: number): Promise<void> {
    for (;;) {

      if (maxId('invoice_returns') >= targetReturnId - 1) return;
      const burner = await createInvoice(
        {
          customerId: customerB, itemId: burnerItem,
          lines: [{ quantity: 1, unitPrice: 10 }], payment: 'full',
        },
        authCookie,
      );
      const ret = await processReturn(
        burner.invoiceId,
        {
          invoiceItemIds: burner.invoiceItemIds,
          quantities: [1],
          feeType: 'none',
          warehouseId,
          settlements: [{ type: 'credit', amount: 10 }],
        },
        authCookie,
      );
      if (ret.status !== 200 || !ret.returnId) {
        throw new Error(`could not align return ids: ${ret.status} ${JSON.stringify(ret.body)}`);
      }
    }
  }

  // ───────────────────────────────────────────────────────────────
  // The exact collision from the audit finding.
  // ───────────────────────────────────────────────────────────────
  it('COLLISION: cancelling Invoice A leaves Invoice B return GL fully intact', async () => {
    // Invoice A's id is the number the return GL group will collide on.
    const invoiceAId = maxId('invoices') + 1;

    const invA = await createInvoice(
      { customerId: customerA, itemId: itemA, lines: [{ quantity: 2, unitPrice: 100 }], invoiceDate: '2026-09-10' },
      authCookie,
    );
    expect(invA.invoiceId).toBe(invoiceAId);

    const invB = await createInvoice(
      {
        customerId: customerB, itemId: itemB, lines: [{ quantity: 2, unitPrice: 100 }],
        payment: 'full', invoiceDate: '2026-09-11',
      },
      authCookie,
    );

    // Engineer the numeric collision: Invoice B's return must take the
    // id that Invoice A already holds.
    await alignNextReturnIdTo(invoiceAId);
    const retB = await processReturn(
      invB.invoiceId,
      {
        invoiceItemIds: invB.invoiceItemIds,
        quantities: [1],
        feeType: 'fixed',
        feeValue: 20,
        warehouseId,
        settlements: [{ type: 'credit', amount: 80 }],
      },
      authCookie,
    );
    expect(retB.status).toBe(200);
    expect(retB.returnId).toBe(invoiceAId);
    const returnId = retB.returnId as number;

    // ── Snapshot Invoice B's return state BEFORE the cancellation ──
    const goodsBefore = glTotalsFor('INVOICE_RETURN', returnId);
    const feeBefore = glTotalsFor('RETURN_FEE', returnId);
    const goodsLinesBefore = activeLines('INVOICE_RETURN', returnId);
    const feeLinesBefore = activeLines('RETURN_FEE', returnId);
    // The goods group carries BOTH the sales-return entry and the COGS
    // reversal (they share the return-keyed group by construction), so
    // assert the legs by account rather than by group total.
    expect(goodsLinesBefore.length).toBeGreaterThan(0);
    expect(feeLinesBefore.length).toBeGreaterThan(0);
    expect(accountTotals('INVOICE_RETURN', returnId, '1100').credit).toBeCloseTo(100, 2); // AR
    expect(accountTotals('INVOICE_RETURN', returnId, '4100').debit).toBeCloseTo(100, 2);  // Sales Returns
    expect(accountTotals('INVOICE_RETURN', returnId, '1200').debit).toBeCloseTo(100, 2);  // Inventory restored
    expect(accountTotals('INVOICE_RETURN', returnId, '5000').credit).toBeCloseTo(100, 2); // COGS reversed
    expect(accountTotals('RETURN_FEE', returnId, '1100').debit).toBeCloseTo(20, 2);
    expect(accountTotals('RETURN_FEE', returnId, '4150').credit).toBeCloseTo(20, 2);

    const ledgerBBefore = customerLedgerNet(customerB);
    const stockBBefore = stockQty(itemB, warehouseId);
    expect(stockBBefore).toBe(9);
    // Invoice A already consumed 2 units of its own item; its stock is
    // restored only by the cancellation below.
    expect(stockQty(itemA, warehouseId)).toBe(8);

    // ── The act under test ──
    const res = await cancel(invoiceAId, authCookie);
    expect(res.status).toBe(200);

    const invARow = db.prepare('SELECT status FROM invoices WHERE id = ?').get(invoiceAId) as { status: string };
    expect(invARow.status).toBe('Cancelled');

    // ── (1) Invoice B's return GL is UNTOUCHED — group totals, every
    //        individual line, and every account leg all survive intact. ──
    expect(glTotalsFor('INVOICE_RETURN', returnId)).toEqual(goodsBefore);
    expect(glTotalsFor('RETURN_FEE', returnId)).toEqual(feeBefore);
    expect(activeLines('INVOICE_RETURN', returnId)).toEqual(goodsLinesBefore);
    expect(activeLines('RETURN_FEE', returnId)).toEqual(feeLinesBefore);
    expect(accountTotals('INVOICE_RETURN', returnId, '1100').credit).toBeCloseTo(100, 2);
    expect(accountTotals('INVOICE_RETURN', returnId, '4100').debit).toBeCloseTo(100, 2);
    expect(accountTotals('INVOICE_RETURN', returnId, '1200').debit).toBeCloseTo(100, 2);
    expect(accountTotals('INVOICE_RETURN', returnId, '5000').credit).toBeCloseTo(100, 2);
    expect(accountTotals('RETURN_FEE', returnId, '1100').debit).toBeCloseTo(20, 2);
    expect(accountTotals('RETURN_FEE', returnId, '4150').credit).toBeCloseTo(20, 2);
    const strays = db.prepare(
      `SELECT COUNT(*) AS c FROM journal_lines
       WHERE reference_type IN ('INVOICE_RETURN', 'RETURN_FEE')
         AND reference_id = ? AND voided = 1
         AND (void_reason LIKE '%cancelled%' OR void_reason LIKE '%deleted%')`,
    ).get(returnId) as { c: number };
    expect(strays.c).toBe(0);

    // ── (2) Invoice B's document state is UNTOUCHED ──
    const retRow = db.prepare(
      'SELECT status, voided_at, returned_amount, net_amount, settled_amount FROM invoice_returns WHERE id = ?',
    ).get(returnId) as {
      status: string; voided_at: string | null; returned_amount: number;
      net_amount: number; settled_amount: number;
    };
    expect(retRow.voided_at).toBeNull();
    expect(retRow.status).toBe('Settled');
    expect(Number(retRow.returned_amount)).toBeCloseTo(100, 2);
    expect(Number(retRow.net_amount)).toBeCloseTo(80, 2);
    expect(Number(retRow.settled_amount)).toBeCloseTo(80, 2);

    const invBRow = db.prepare(
      'SELECT status, paid_amount, balance_amount FROM invoices WHERE id = ?',
    ).get(invB.invoiceId) as { status: string; paid_amount: number; balance_amount: number };
    expect(invBRow.status).not.toBe('Cancelled');
    // paid_amount is the gross collected base (spec §3.2/scenario 10:
    // a return never shrinks it), and the invoice is fully paid, so it
    // is unchanged by A's cancellation and still exactly 200.
    expect(Number(invBRow.paid_amount)).toBeCloseTo(200, 2);

    // The authoritative position computed for Invoice B: paid 200,
    // returned 100 gross, 20 retained as a restocking fee, net 120 due.
    const posB = await fetchPosition(invB.invoiceId, authCookie);
    expect(posB.totalPaid).toBeCloseTo(200, 2);
    expect(posB.totalReturned).toBeCloseTo(100, 2);
    expect(posB.totalFees).toBeCloseTo(20, 2);
    expect(posB.settledAmount).toBeCloseTo(80, 2);


    expect(customerLedgerNet(customerB)).toBeCloseTo(ledgerBBefore, 2);
    expect(stockQty(itemB, warehouseId)).toBeCloseTo(stockBBefore, 2);

    // ── (3) Invoice A's own cancellation entries ARE correct ──
    expect(glTotalsFor('INVOICE', invoiceAId)).toEqual({ debit: 0, credit: 0 });
    const aVoided = db.prepare(
      `SELECT COUNT(*) AS c, void_reason AS reason
       FROM journal_lines
       WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 1
       GROUP BY void_reason`,
    ).all(invoiceAId) as Array<{ c: number; reason: string }>;
    expect(aVoided.length).toBe(1);
    expect(aVoided[0].reason).toBe(`Invoice ${invA.invoiceNo} cancelled`);
    expect(aVoided[0].c).toBeGreaterThan(0);
    // The reversal restored A's stock and netted A's AR.
    expect(stockQty(itemA, warehouseId)).toBeCloseTo(10, 2);

    const ledgerA = db.prepare(
      'SELECT debit, credit FROM customer_ledger WHERE reference_no = ? AND voided = 0',
    ).all(invA.invoiceNo) as Array<{ debit: number; credit: number }>;
    const debitA = ledgerA.filter((r) => r.debit > 0).reduce((s, r) => s + Number(r.debit), 0);
    const creditA = ledgerA.filter((r) => r.credit > 0).reduce((s, r) => s + Number(r.credit), 0);
    expect(debitA).toBeCloseTo(200, 2);
    expect(creditA).toBeCloseTo(200, 2);
    expect(customerLedgerNet(customerA)).toBeCloseTo(0, 2);

    // ── (4) The whole book still reconciles ──
    expectAllInvariantsHold('collision: invoice A cancelled, invoice B return intact');
  });

  // ───────────────────────────────────────────────────────────────
  // Control: with no collision, cancellation still reverses exactly
  // its own GL and nothing else.
  // ───────────────────────────────────────────────────────────────
  it('NORMAL: cancelling an invoice with no returns voids only its own GL', async () => {
    const inv = await createInvoice(
      { customerId: customerC, itemId: itemA, lines: [{ quantity: 1, unitPrice: 150 }], invoiceDate: '2026-09-12' },
      authCookie,
    );
    const invoiceId = inv.invoiceId;
    expect(glTotalsFor('INVOICE', invoiceId).debit).toBeGreaterThan(0);
    expect(activeLines('INVOICE', invoiceId).length).toBeGreaterThan(0);
    const ownLinesBefore = activeLines('INVOICE', invoiceId);

    const stockBefore = stockQty(itemA, warehouseId);
    const ledgerBefore = customerLedgerNet(customerC);

    const res = await cancel(invoiceId, authCookie);
    expect(res.status).toBe(200);

    const row = db.prepare('SELECT status FROM invoices WHERE id = ?').get(invoiceId) as { status: string };
    expect(row.status).toBe('Cancelled');

    // A's own group is fully voided, with the same lines and the same
    // attribution reason — nothing was silently added or dropped.
    expect(glTotalsFor('INVOICE', invoiceId)).toEqual({ debit: 0, credit: 0 });
    const ownLinesAfter = db.prepare(
      `SELECT jl.id, coa.code AS account_code, jl.debit, jl.credit
       FROM journal_lines jl JOIN chart_of_accounts coa ON coa.id = jl.account_id
       WHERE jl.reference_type = 'INVOICE' AND jl.reference_id = ? AND jl.voided = 1
       ORDER BY jl.id`,
    ).all(invoiceId) as Array<{ id: number; account_code: string; debit: number; credit: number }>;
    expect(ownLinesAfter.map((l) => l.id)).toEqual(ownLinesBefore.map((l) => l.id));

    // The stock the sale removed is restored, and nothing else moved.
    expect(stockQty(itemA, warehouseId) - stockBefore).toBeCloseTo(1, 2);
    // customerLedgerNet is Σdebit − Σcredit, so an unpaid invoice reads
    // +150 (the customer owes us) and the cancellation contra brings
    // the net back to 0.
    expect(customerLedgerNet(customerC)).toBeCloseTo(ledgerBefore - 150, 2);


    const ledgerRows = db.prepare(
      'SELECT debit, credit FROM customer_ledger WHERE reference_no = ? AND voided = 0',
    ).all(inv.invoiceNo) as Array<{ debit: number; credit: number }>;
    const debit = ledgerRows.filter((r) => r.debit > 0).reduce((s, r) => s + Number(r.debit), 0);
    const credit = ledgerRows.filter((r) => r.credit > 0).reduce((s, r) => s + Number(r.credit), 0);
    expect(debit).toBeCloseTo(150, 2);
    expect(credit).toBeCloseTo(150, 2);

    expectAllInvariantsHold('normal cancellation with no returns');
  });

  // ───────────────────────────────────────────────────────────────
  // The same defect lived in the soft-delete path: DELETE
  // /api/invoices/:id voided INVOICE_RETURN by the bare invoice id.
  // Only unpaid/returned-free invoices are deletable, so the return
  // under attack necessarily belongs to a DIFFERENT invoice.
  // ───────────────────────────────────────────────────────────────
  it('COLLISION-DELETE: soft-deleting Invoice A leaves Invoice B return GL fully intact', async () => {
    const invoiceDId = maxId('invoices') + 1;

    const invD = await createInvoice(
      { customerId: customerD, itemId: itemD, lines: [{ quantity: 1, unitPrice: 120 }], invoiceDate: '2026-09-13' },
      authCookie,
    );
    expect(invD.invoiceId).toBe(invoiceDId);

    const invB = await createInvoice(
      {
        customerId: customerB, itemId: itemB, lines: [{ quantity: 2, unitPrice: 100 }],
        payment: 'full', invoiceDate: '2026-09-14',
      },
      authCookie,
    );

    await alignNextReturnIdTo(invoiceDId);
    const retB = await processReturn(
      invB.invoiceId,
      {
        invoiceItemIds: invB.invoiceItemIds,
        quantities: [1],
        feeType: 'none',
        warehouseId,
        settlements: [{ type: 'credit', amount: 100 }],
      },
      authCookie,
    );
    expect(retB.status).toBe(200);
    expect(retB.returnId).toBe(invoiceDId);
    const returnId = retB.returnId as number;

    const goodsBefore = glTotalsFor('INVOICE_RETURN', returnId);
    const goodsLinesBefore = activeLines('INVOICE_RETURN', returnId);
    expect(goodsLinesBefore.length).toBeGreaterThan(0);
    expect(accountTotals('INVOICE_RETURN', returnId, '1100').credit).toBeCloseTo(100, 2);
    expect(accountTotals('INVOICE_RETURN', returnId, '4100').debit).toBeCloseTo(100, 2);

    const res = await request(app)
      .delete(`/api/invoices/${invoiceDId}`)
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);

    const dRow = db.prepare('SELECT deleted_at FROM invoices WHERE id = ?')
      .get(invoiceDId) as { deleted_at: string | null };
    expect(dRow.deleted_at).not.toBeNull();

    // Invoice B's return GL survived the deletion untouched.
    expect(glTotalsFor('INVOICE_RETURN', returnId)).toEqual(goodsBefore);
    expect(activeLines('INVOICE_RETURN', returnId)).toEqual(goodsLinesBefore);
    expect(accountTotals('INVOICE_RETURN', returnId, '1100').credit).toBeCloseTo(100, 2);
    expect(accountTotals('INVOICE_RETURN', returnId, '4100').debit).toBeCloseTo(100, 2);
    const strays = db.prepare(
      `SELECT COUNT(*) AS c FROM journal_lines
       WHERE reference_type IN ('INVOICE_RETURN', 'RETURN_FEE')
         AND reference_id = ? AND voided = 1`,
    ).get(returnId) as { c: number };
    expect(strays.c).toBe(0);

    // The deleted invoice's own GL is voided with the delete attribution.
    expect(glTotalsFor('INVOICE', invoiceDId)).toEqual({ debit: 0, credit: 0 });
    const dVoided = db.prepare(
      `SELECT void_reason AS reason FROM journal_lines
       WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 1`,
    ).get(invoiceDId) as { reason: string };
    expect(dVoided.reason).toBe(`Invoice ${invD.invoiceNo} deleted`);
    expect(stockQty(itemD, warehouseId)).toBeCloseTo(10, 2);
    expect(customerLedgerNet(customerD)).toBeCloseTo(0, 2);

    expectAllInvariantsHold('collision: invoice D soft-deleted, invoice B return intact');
  });
});
