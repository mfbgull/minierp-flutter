/**
 * Inventory authority invariants (audit task 35).
 *
 * Four representations describe the same stock:
 *   1. stock_balances.quantity  — authoritative quantity per item x warehouse
 *   2. stock_batches            — authoritative cost / expiry / location
 *   3. stock_movements          — append-only history
 *   4. items.current_stock      — DENORMALIZED MIRROR of (1), read by the
 *                                 reorder alerts and the GL reconciliation
 *                                 fallback for batch-less items
 *
 * Two invariants are pinned here:
 *   A. the mirror equals the authoritative quantity for EVERY item — this was
 *      previously only asserted per-flow, while the mirror-maintenance SQL was
 *      duplicated across seven write sites with no single owner;
 *   B. GL account 1200 equals batch value + legacy mirror value across a
 *      lifecycle. accountingInvariants documents this as a pre-existing gap
 *      and asserts it in only 1 of its 17 scenarios; this suite measures it.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createCustomer, createItem, purchaseStock, createInvoice, processReturn } from './helpers/invoiceReturnSpec';

type MirrorRow = { id: number; current_stock: number; authoritative: number };

describe('inventory authority (audit task 35)', () => {
  let authCookie = '';
  let customerId = 0;
  let itemId = 0;
  let warehouseId = 0;
  let supplierId = 0;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    customerId = await createCustomer('Stock Authority Customer', authCookie);
    itemId = await createItem('Stock Authority Item', authCookie);
    await purchaseStock(itemId, warehouseId, 10, 20, authCookie);

    const supplier = await request(app).post('/api/suppliers')
      .set('Cookie', authCookie)
      .send({ supplier_code: `STK-AUTH-${Date.now()}`, supplier_name: 'Stock Authority Supplier' });
    supplierId = supplier.body.data?.id ?? supplier.body.id;
    expect(supplierId).toBeGreaterThan(0);
  });

  function mirrorMismatches(): MirrorRow[] {
    return db.prepare(`
      SELECT i.id AS id,
             i.current_stock AS current_stock,
             COALESCE((SELECT SUM(sb.quantity) FROM stock_balances sb WHERE sb.item_id = i.id), 0) AS authoritative
      FROM items i
    `).all() as MirrorRow[];
  }

  function glInventoryBalance(): number {
    const account = db.prepare("SELECT id FROM chart_of_accounts WHERE code = '1200'").get() as { id: number };
    const row = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS net
      FROM journal_lines WHERE account_id = ? AND voided = 0
    `).get(account.id) as { net: number };
    return Number(row.net);
  }

  function operationalInventoryValue(): number {
    const batch = db.prepare(`
      SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) AS v
      FROM stock_batches WHERE quantity_remaining > 0
    `).get() as { v: number };
    const legacy = db.prepare(`
      SELECT COALESCE(SUM(i.current_stock * i.standard_cost), 0) AS v
      FROM items i
      WHERE i.is_active = 1 AND i.current_stock > 0
        AND NOT EXISTS (SELECT 1 FROM stock_batches sb WHERE sb.item_id = i.id AND sb.quantity_remaining > 0)
    `).get() as { v: number };
    return Number(batch.v) + Number(legacy.v);
  }

  it('keeps items.current_stock equal to the authoritative stock_balances quantity for every item', () => {
    const mismatches = mirrorMismatches().filter(
      (row) => Math.abs(Number(row.current_stock) - Number(row.authoritative)) > 0.005,
    );
    expect(mismatches).toEqual([]);
  });

  it('keeps the mirror correct through purchase, sale and return', async () => {
    const sold = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }], payment: 'full' },
      authCookie,
    );
    const returned = await processReturn(sold.invoiceId, {
      invoiceItemIds: sold.invoiceItemIds,
      quantities: [1],
    }, authCookie);
    expect([200, 201]).toContain(returned.status);

    const row = db.prepare(`
      SELECT i.current_stock AS current_stock,
             COALESCE((SELECT SUM(sb.quantity) FROM stock_balances sb WHERE sb.item_id = i.id), 0) AS authoritative
      FROM items i WHERE i.id = ?
    `).get(itemId) as { current_stock: number; authoritative: number };

    expect(Number(row.current_stock)).toBeCloseTo(Number(row.authoritative), 2);
  });

  it('reconciles GL inventory 1200 with batch value plus legacy mirror value', () => {
    const gl = glInventoryBalance();
    const operational = operationalInventoryValue();
    expect(gl).toBeCloseTo(operational, 2);
  });

  it('reconciles GL inventory after a purchase-order goods receipt', async () => {
    const po = await request(app).post('/api/purchase-orders')
      .set('Cookie', authCookie)
      .send({
        supplier_id: supplierId,
        po_date: '2026-09-15',
        items: [{ item_id: itemId, quantity: 5, unit_price: 30 }],
      });
    expect(po.status).toBe(201);
    const poId = po.body.id as number;

    const submit = await request(app).post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie)
      .send({ status: 'Submitted' });
    expect(submit.status).toBe(200);

    const poItem = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?').get(poId) as { id: number };
    const receipt = await request(app).post(`/api/purchase-orders/${poId}/receipts`)
      .set('Cookie', authCookie)
      .send({
        receipt_date: '2026-09-16',
        warehouse_id: warehouseId,
        items: [{ po_item_id: poItem.id, received_quantity: 5 }],
      });
    expect([200, 201]).toContain(receipt.status);

    expect(glInventoryBalance()).toBeCloseTo(operationalInventoryValue(), 2);
  });
});
