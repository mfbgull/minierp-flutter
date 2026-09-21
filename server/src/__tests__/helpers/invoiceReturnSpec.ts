/**
 * Invoice Return — shared test helpers
 * (invoice-return-spec.md §8 — scaffolding drafted BEFORE implementation.
 *
 * These helpers encode the SPEC's expected behaviour. They are written to
 * be run against the reworked implementation:
 *   - `invoice_returns` / `invoice_return_items` / `return_settlements`
 *     tables (migration add-invoice-returns.sql)
 *   - `POST /api/invoices/:id/return` with the new payload
 *     (`return_date`, `fee_type`, `fee_value`, `settlements[]`)
 *   - `POST /api/invoice-returns/:id/settle`
 *   - `POST /api/return-settlements/:id/void`
 *   - `POST /api/invoice-returns/:id/void`
 *   - `GET /api/invoices/:id/position`
 *
 * Every helper throws if the expected shape is missing so failures are
 * loud and point at the spec section, not just a wrong number.
 */
import request from 'supertest';
import app from '../../app';
import db from '../../config/database';

export const FEE_INCOME_ACCOUNT_CODE = '4150'; // Restocking Fee Income (add-gl-foundation.sql)
export const EPSILON = 0.01; // currency rounding tolerance (parseCurrency convention)

export interface Position {
  originalTotal: number;
  totalReturned: number;
  currentInvoiceValue: number;
  totalPaid: number;
  totalFees: number;
  refundCreditDue: number;
  settledAmount: number;
  remainingRefundDue: number;
  balanceDue: number;
}

// ────────────────────────────────────────────────────────────────────
// Auth
// ────────────────────────────────────────────────────────────────────

export async function getAuthCookie(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: process.env.TEST_ADMIN_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

// ────────────────────────────────────────────────────────────────────
// Fixtures — item / customer / invoice builders
// ────────────────────────────────────────────────────────────────────

let fixtureSeq = 0;

export async function createItem(name: string, authCookie: string): Promise<number> {
  fixtureSeq += 1;
  const res = await request(app).post('/api/inventory/items')
    .set('Cookie', authCookie)
    .send({ item_code: `RET-FIX-${Date.now()}-${fixtureSeq}`, item_name: name });
  if (res.status !== 201) throw new Error(`createItem failed: ${res.status} ${JSON.stringify(res.body)}`);
  return res.body.id;
}

/**
 * Seed sellable stock. Stock is bought on CREDIT from a fixture supplier
 * (Cr 2000 AP), never with cash — these suites exercise cash refunds, so a
 * cash purchase would drain the Cash account and trip the (correct) cash
 * funds guard on every refund. A supplier-linked purchase is the ordinary
 * way a shop acquires resale stock (see H12: no supplier → immediate
 * purchase on Cash).
 */
let stockSupplierId: number | undefined;

export async function purchaseStock(
  itemId: number, warehouseId: number, quantity: number, unitCost: number, authCookie: string,
): Promise<void> {
  if (stockSupplierId === undefined) {
    const existing = db.prepare(
      `SELECT id FROM suppliers WHERE supplier_code = 'RET-FIX-SUPPLIER' LIMIT 1`
    ).get() as { id: number } | undefined;
    stockSupplierId = existing?.id ?? (
      await request(app).post('/api/suppliers')
        .set('Cookie', authCookie)
        .send({ supplier_code: 'RET-FIX-SUPPLIER', supplier_name: 'Return Spec Supplier' })
    ).body?.data?.id;
  }
  const res = await request(app).post('/api/purchases')
    .set('Cookie', authCookie)
    .send({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity,
      unit_cost: unitCost,
      purchase_date: '2026-09-01',
      supplier_id: stockSupplierId,
    });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`purchaseStock failed: ${res.status} ${JSON.stringify(res.body)}`);
  }
}

export async function createCustomer(name: string, authCookie: string): Promise<number> {
  const res = await request(app).post('/api/customers')
    .set('Cookie', authCookie)
    .send({ customer_name: name, phone: '555-0177' });
  const id = res.body.data?.id ?? res.body.id;
  if (!id) throw new Error(`createCustomer failed: ${res.status} ${JSON.stringify(res.body)}`);
  return id as number;
}

export interface InvoiceLineSpec {
  quantity: number;
  unitPrice: number;
  taxRate?: number;
  discountType?: 'none' | 'percentage' | 'flat';
  discountValue?: number;
}

export interface CreateInvoiceOptions {
  customerId: number;
  itemId: number;
  lines: InvoiceLineSpec[];
  /** Payment to record at creation: 'full' | { partial amount } | null (none) */
  payment?: 'full' | { amount: number } | null;
  invoiceDate?: string;
}

export async function createInvoice(
  opts: CreateInvoiceOptions, authCookie: string,
): Promise<{ invoiceId: number; invoiceNo: string; invoiceItemIds: number[] }> {
  // The recorded payment must cover the invoice's STORED total, which for
  // additive tax is the tax-inclusive sum (spec §3.5). Server-side
  // validation only rejects a payment that exceeds the stored total.
  const grossTotal = opts.lines.reduce(
    (sum, l) => sum + l.quantity * l.unitPrice * (1 + (l.taxRate ?? 0) / 100),
    0,
  );

  const paymentBlock =
    opts.payment === 'full'
      ? { payment_date: opts.invoiceDate ?? '2026-09-15', amount: grossTotal, payment_method: 'Cash' }
      : opts.payment && typeof opts.payment === 'object'
        ? { payment_date: opts.invoiceDate ?? '2026-09-15', amount: opts.payment.amount, payment_method: 'Cash' }
        : undefined;

  const res = await request(app).post('/api/invoices')
    .set('Cookie', authCookie)
    .send({
      customer_id: opts.customerId,
      invoice_date: opts.invoiceDate ?? '2026-09-15',
      due_date: '2026-09-30',
      items: opts.lines.map((l) => ({
        item_id: opts.itemId,
        quantity: l.quantity,
        unit_price: l.unitPrice,
        tax_rate: l.taxRate ?? 0,
        discount_type: l.discountType ?? 'none',
        discount_value: l.discountValue ?? 0,
      })),
      // The server computes the authoritative total (ACC-18: the stored
      // total is always the server-computed one; a client `total_amount`
      // is only validated when present, and it must match — additive tax
      // is not part of the client-side arithmetic here). Omit it.
      record_payment: paymentBlock !== undefined,
      payment: paymentBlock,
    });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`createInvoice failed: ${res.status} ${JSON.stringify(res.body)}`);
  }
  const invoiceId: number = res.body.id;
  const invoice = db.prepare('SELECT invoice_no FROM invoices WHERE id = ?').get(invoiceId) as { invoice_no: string };
  const itemRows = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id').all(invoiceId) as Array<{ id: number }>;
  return { invoiceId, invoiceNo: invoice.invoice_no, invoiceItemIds: itemRows.map((r) => r.id) };
}

// ────────────────────────────────────────────────────────────────────
// Return / settle / void calls
// ────────────────────────────────────────────────────────────────────

export interface SettlementSpec {
  type: 'refund' | 'credit' | 'adjust';
  amount: number;
  method?: string;            // refund only
  target_invoice_id?: number; // adjust only
}

export interface ReturnSpec {
  invoiceItemIds: number[];
  quantities: number[];       // parallel to invoiceItemIds
  feeType?: 'none' | 'fixed' | 'percentage';
  feeValue?: number;
  returnDate?: string;
  warehouseId?: number;
  settlements?: SettlementSpec[]; // omit → leave Unsettled
  reason?: string;
}

export async function processReturn(
  invoiceId: number, spec: ReturnSpec, authCookie: string,
): Promise<{ status: number; body: Record<string, unknown>; returnId?: number }> {
  const res = await request(app)
    .post(`/api/invoices/${invoiceId}/return`)
    .set('Cookie', authCookie)
    .send({
      items: spec.invoiceItemIds.map((id, i) => ({ invoice_item_id: id, return_quantity: spec.quantities[i] })),
      fee_type: spec.feeType ?? 'none',
      fee_value: spec.feeValue ?? 0,
      return_date: spec.returnDate,
      warehouse_id: spec.warehouseId,
      reason: spec.reason ?? 'Spec test return',
      settlements: spec.settlements,
    });
  return {
    status: res.status,
    body: res.body as Record<string, unknown>,
    returnId: (res.body?.data as { returnId?: number } | undefined)?.returnId
      ?? (res.body?.data as { id?: number } | undefined)?.id,
  };
}

export async function settleReturn(
  returnId: number, allocations: SettlementSpec[], authCookie: string,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const res = await request(app)
    .post(`/api/invoice-returns/${returnId}/settle`)
    .set('Cookie', authCookie)
    .send({ allocations });
  return { status: res.status, body: res.body as Record<string, unknown> };
}

export async function voidReturn(returnId: number, authCookie: string): Promise<number> {
  const res = await request(app)
    .post(`/api/invoice-returns/${returnId}/void`)
    .set('Cookie', authCookie);
  return res.status;
}

export async function voidSettlement(settlementId: number, authCookie: string): Promise<number> {
  const res = await request(app)
    .post(`/api/return-settlements/${settlementId}/void`)
    .set('Cookie', authCookie);
  return res.status;
}

// ────────────────────────────────────────────────────────────────────
// Position reader — GET /invoices/:id/position (or detail-folded)
// ────────────────────────────────────────────────────────────────────

export async function fetchPosition(invoiceId: number, authCookie: string): Promise<Position> {
  // Primary: the dedicated endpoint; fallback: invoice detail carrying position.
  let body: Record<string, unknown> | undefined;
  const res = await request(app).get(`/api/invoices/${invoiceId}/position`).set('Cookie', authCookie);
  if (res.status === 200) {
    body = (res.body.data ?? res.body) as Record<string, unknown>;
  } else {
    const detail = await request(app).get(`/api/invoices/${invoiceId}`).set('Cookie', authCookie);
    body = (detail.body?.data?.position ?? detail.body?.position) as Record<string, unknown> | undefined;
  }
  if (!body) throw new Error(`No position object returned for invoice ${invoiceId} — spec §4.2 requires one`);
  return {
    originalTotal: Number(body.originalTotal),
    totalReturned: Number(body.totalReturned),
    currentInvoiceValue: Number(body.currentInvoiceValue),
    totalPaid: Number(body.totalPaid),
    totalFees: Number(body.totalFees),
    refundCreditDue: Number(body.refundCreditDue),
    settledAmount: Number(body.settledAmount),
    remainingRefundDue: Number(body.remainingRefundDue),
    balanceDue: Number(body.balanceDue),
  };
}

// ────────────────────────────────────────────────────────────────────
// Assertions
// ────────────────────────────────────────────────────────────────────

/** Assert a Position against the spec §3.2 worked-example fields. */
export function expectPosition(actual: Position, expected: Partial<Position>): void {
  for (const [key, value] of Object.entries(expected)) {
    expect(actual[key as keyof Position]).toBeCloseTo(value as number, 2);
  }
}

/** Fetch the computed position and assert it in one call. */
export async function expectPositionOf(
  invoiceId: number, authCookie: string, expected: Partial<Position>,
): Promise<Position> {
  const pos = await fetchPosition(invoiceId, authCookie);
  expectPosition(pos, expected);
  return pos;
}

/** Balance Due must NEVER be negative, on the row or in the position. */
export function expectNoNegativeBalance(invoiceId: number): void {
  const row = db.prepare('SELECT balance_amount FROM invoices WHERE id = ?').get(invoiceId) as { balance_amount: number };
  expect(row.balance_amount).toBeGreaterThanOrEqual(-EPSILON);
}

export function getInvoiceRow(invoiceId: number): {
  total_amount: number; paid_amount: number; balance_amount: number;
  returned_amount: number; return_fee: number; status: string;
} {
  return db.prepare(
    'SELECT total_amount, paid_amount, balance_amount, returned_amount, return_fee, status FROM invoices WHERE id = ?'
  ).get(invoiceId) as {
    total_amount: number; paid_amount: number; balance_amount: number;
    returned_amount: number; return_fee: number; status: string;
  };
}

// ── Original-history preservation (spec rules 1, 2, 8) ───────────────

export function assertOriginalLinesUntouched(invoiceId: number, lines: Array<{ quantity: number; unitPrice: number }>): void {
  const rows = db.prepare('SELECT quantity, unit_price FROM invoice_items WHERE invoice_id = ? ORDER BY id')
    .all(invoiceId) as Array<{ quantity: number; unit_price: number }>;
  expect(rows).toHaveLength(lines.length);
  rows.forEach((row, i) => {
    expect(row.quantity).toBeCloseTo(lines[i].quantity, 4);
    expect(row.unit_price).toBeCloseTo(lines[i].unitPrice, 4);
  });
}

export function assertPaymentsUnchanged(invoiceId: number, expectedTotal: number): void {
  const sum = db.prepare(`
    SELECT COALESCE(SUM(a.amount), 0) AS s
    FROM payment_allocations a
    WHERE a.invoice_id = ? AND a.voided_at IS NULL AND a.amount > 0
  `).get(invoiceId) as { s: number };
  expect(sum.s).toBeCloseTo(expectedTotal, 2);
}

// ── GL / ledger assertions ──────────────────────────────────────────

export interface LineTotals { debit: number; credit: number }

export function glTotalsFor(referenceType: string, referenceId: number): LineTotals {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit), 0) AS debit, COALESCE(SUM(credit), 0) AS credit
    FROM journal_lines WHERE reference_type = ? AND reference_id = ? AND voided = 0
  `).get(referenceType, referenceId) as { debit: number; credit: number };
  return { debit: Number(row.debit), credit: Number(row.credit) };
}

/** Every journal group for the invoice's return documents balances Dr == Cr. */
export function assertGlBalanced(referenceType: string, referenceId: number): void {
  const t = glTotalsFor(referenceType, referenceId);
  expect(t.debit).toBeCloseTo(t.credit, 2);
}

/** The restocking fee entry: Dr AR / Cr 4150, as its OWN group (spec D20). */
export function assertFeeEntrySeparate(invoiceId: number, feeAmount: number): void {
  const feeAccount = db.prepare('SELECT id FROM chart_of_accounts WHERE code = ?')
    .get(FEE_INCOME_ACCOUNT_CODE) as { id: number } | undefined;
  if (!feeAccount) throw new Error('Chart of accounts is missing 4150 Restocking Fee Income — spec D20');

  const feeRows = db.prepare(`
    SELECT jl.debit, jl.credit, jl.reference_type, jl.reference_id
    FROM journal_lines jl
    JOIN chart_of_accounts c ON c.id = jl.account_id
    WHERE c.code = ? AND jl.voided = 0 AND jl.reference_type = 'RETURN_FEE'
      AND jl.reference_id IN (SELECT id FROM invoice_returns WHERE invoice_id = ?)
  `).all(FEE_INCOME_ACCOUNT_CODE, invoiceId) as Array<{ debit: number; credit: number; reference_type: string; reference_id: number }>;

  const feeCredits = feeRows.filter((r) => r.credit > 0);
  expect(feeCredits.length).toBeGreaterThan(0);
  expect(feeCredits.reduce((s, r) => s + r.credit, 0)).toBeCloseTo(feeAmount, 2);
}

export function customerLedgerNet(customerId: number): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net
    FROM customer_ledger WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL
  `).get(customerId) as { net: number };
  return Number(row.net);
}

export function returnRow(returnId: number): {
  return_no: string; status: string; returned_amount: number;
  fee_amount: number; net_amount: number; settled_amount: number; voided_at: string | null;
} {
  const row = db.prepare(
    'SELECT return_no, status, returned_amount, fee_amount, net_amount, settled_amount, voided_at FROM invoice_returns WHERE id = ?'
  ).get(returnId) as {
    return_no: string; status: string; returned_amount: number;
    fee_amount: number; net_amount: number; settled_amount: number; voided_at: string | null;
  };
  if (!row) throw new Error(`invoice_returns row ${returnId} not found — new tables missing?`);
  return row;
}

export function settlementsFor(returnId: number): Array<{
  id: number; type: string; amount: number; method: string | null;
  target_invoice_id: number | null; payment_id: number | null; voided_at: string | null;
}> {
  return db.prepare(
    'SELECT id, type, amount, method, target_invoice_id, payment_id, voided_at FROM return_settlements WHERE return_id = ? ORDER BY id'
  ).all(returnId) as Array<{
    id: number; type: string; amount: number; method: string | null;
    target_invoice_id: number | null; payment_id: number | null; voided_at: string | null;
  }>;
}
