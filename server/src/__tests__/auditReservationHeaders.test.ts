import request from 'supertest';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import { createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';
import { setFeatureEnabled } from '../utils/featureFlags';

describe('reservation and journal audit invariants', () => {
  let cookie: string;
  let item: number;
  let warehouse: number;
  let batch: number;
  let location: number;
  beforeAll(async () => {
    cookie = await getAuthCookie();
    warehouse = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    item = await createItem('Reservation audit', cookie);
    await purchaseStock(item, warehouse, 10, 10, cookie);
    setFeatureEnabled(db, 'feature_batch_locations', true);
    db.prepare("INSERT OR IGNORE INTO locations(warehouse_id,location_code,location_name) VALUES(?,'DEFAULT','Audit bin')").run(warehouse);
    location = (db.prepare("SELECT id FROM locations WHERE warehouse_id=? AND location_code='DEFAULT'").get(warehouse) as { id: number }).id;
    batch = (db.prepare('SELECT id FROM stock_batches WHERE item_id=?').get(item) as { id: number }).id;
    db.prepare('INSERT INTO batch_stock_by_location(batch_id,location_id,quantity_physical,quantity_reserved,quantity_available) VALUES(?,?,10,0,10)').run(batch, location);
  });
  it.each([1, undefined])('F-071/F-072 reserve replay and release apply one location delta (line=%s)', async line => {
    const body = { item_id: item, warehouse_id: warehouse, batch_id: batch, location_id: location, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: `AUDIT-${line ?? 'NULL'}`, reference_line_id: line };
    const post = () => request(app).post('/api/inventory/reservations').set('Cookie', cookie).send(body);
    const first = await post();
    expect(first.status).toBe(201);
    const replay = await post();
    expect(replay.status).toBe(201);
    expect(replay.body.id).toBe(first.body.id);
    expect(db.prepare('SELECT quantity_reserved,quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch, location))
      .toEqual({ quantity_reserved: 3, quantity_available: 7 });
    expect((await request(app).delete(`/api/inventory/reservations/${first.body.id}/release`).set('Cookie', cookie)).status).toBe(200);
    expect(db.prepare('SELECT quantity_reserved,quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch, location))
      .toEqual({ quantity_reserved: 0, quantity_available: 10 });
    expect((await post()).body.id).toBe(first.body.id);
    const conflict = await request(app).post('/api/inventory/reservations').set('Cookie', cookie).send({ ...body, quantity_reserved: 4 });
    expect(conflict.status).toBe(409);
    expect((await request(app).delete(`/api/inventory/reservations/${first.body.id}/release`).set('Cookie', cookie)).status).toBe(200);
    expect((await request(app).delete(`/api/inventory/reservations/${first.body.id}/release`).set('Cookie', cookie)).status).toBe(400);
    expect(db.prepare('SELECT quantity_reserved,quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch, location))
      .toEqual({ quantity_reserved: 0, quantity_available: 10 });
  });
  it('F-060 voids header only after all its children are void and preserves attribution', async () => {
    const bank = AccountingService.getAccountByCode(db, '1010');
    const equity = AccountingService.getAccountByCode(db, '3200');
    if (!bank || !equity) throw new Error('Missing fixture accounts');
    const entry = AccountingService.postEntry(db, { entry_date: '2026-09-01', reference_type: 'AUDIT_HEADER', reference_id: 73,
      description: 'Header lineage', created_by: 1, lines: [{ account_id: bank.id, debit: 10 }, { account_id: equity.id, credit: 10 }] });
    AccountingService.voidJournalLinesByReference(db, 'AUDIT_HEADER', 73, { voidedBy: 1, voidReason: 'Audit void' });
    expect(db.prepare('SELECT voided FROM journal_entries WHERE id=?').get(entry.journal_entry_id)).toEqual({ voided: 1 });
    expect(db.prepare('SELECT voided,voided_by,void_reason FROM journal_entries WHERE id=?').get(entry.journal_entry_id))
      .toEqual({ voided: 1, voided_by: 1, void_reason: 'Audit void' });
    // Mounted cash-capital void must reach the same shared invariant.
    const created = await request(app).post('/api/owner-equity/capital').set('Cookie', cookie)
      .send({ amount: 50, capital_date: '2026-09-01', payment_method: 'Bank' });
    expect(created.status).toBe(201);
    const id = created.body.data.id;
    const reversed = await request(app).delete(`/api/owner-equity/capital/${id}`).set('Cookie', cookie).send({ reason: 'Audit reversal' });
    expect(reversed.status).toBe(200);
    expect(db.prepare(`SELECT e.id FROM journal_entries e JOIN journal_lines l ON l.journal_entry_id=e.id
      GROUP BY e.id HAVING e.voided=0 AND SUM(CASE WHEN l.voided=0 THEN 1 ELSE 0 END)=0`).all()).toEqual([]);
  });
  it('unsupported supplier return-credit allocation rejects as a client error without new cash', async () => {
    const supplier = db.prepare('SELECT supplier_id FROM purchases WHERE item_id=? LIMIT 1').get(item) as { supplier_id: number };
    const before = db.prepare('SELECT * FROM payments ORDER BY id').all();
    const res = await request(app).post('/api/payments').set('Cookie', cookie).send({ supplier_id: supplier.supplier_id,
      payment_date: '2026-09-15', amount: 10, payment_method: 'credit', credit_note_id: 1, purchase_allocations: [] });
    expect(res.status).toBe(400);
    expect(db.prepare('SELECT * FROM payments ORDER BY id').all()).toEqual(before);
  });
  it('F-060 preserves a mixed header until its last active balanced leg is voided', () => {
    const bank = AccountingService.getAccountByCode(db, '1010');
    const equity = AccountingService.getAccountByCode(db, '3200');
    if (!bank || !equity) throw new Error('Missing fixture accounts');
    const entry = AccountingService.postEntry(db, { entry_date: '2026-09-01', reference_type: 'MIXED_A', reference_id: 1,
      description: 'Mixed source header', created_by: 1, lines: [
        { account_id: bank.id, debit: 10 }, { account_id: equity.id, credit: 10 },
        { account_id: bank.id, debit: 20 }, { account_id: equity.id, credit: 20 },
      ] });
    db.prepare("UPDATE journal_lines SET reference_type='MIXED_B' WHERE journal_entry_id=? AND (debit=20 OR credit=20)").run(entry.journal_entry_id);
    AccountingService.voidJournalLinesByReference(db, 'MIXED_A', 1, { voidedBy: 1, voidReason: 'A void' });
    expect(db.prepare('SELECT voided FROM journal_entries WHERE id=?').get(entry.journal_entry_id)).toEqual({ voided: 0 });
    expect(db.prepare("SELECT voided FROM journal_lines WHERE journal_entry_id=? AND reference_type='MIXED_B'").all(entry.journal_entry_id)).toEqual([{ voided: 0 }, { voided: 0 }]);
    AccountingService.voidJournalLinesByReference(db, 'MIXED_B', 1, { voidedBy: 1, voidReason: 'B void' });
    expect(db.prepare('SELECT voided,void_reason FROM journal_entries WHERE id=?').get(entry.journal_entry_id)).toEqual({ voided: 1, void_reason: 'B void' });
    AccountingService.restoreJournalLinesByReference(db, 'MIXED_A', 1);
    expect(db.prepare('SELECT voided,voided_at FROM journal_entries WHERE id=?').get(entry.journal_entry_id)).toEqual({ voided: 0, voided_at: null });
  });
  it('F-060 legacy return void synchronizes its owning header', () => {
    const bank = AccountingService.getAccountByCode(db, '1010');
    const equity = AccountingService.getAccountByCode(db, '3200');
    if (!bank || !equity) throw new Error('Missing fixture accounts');
    const entry = AccountingService.postEntry(db, { entry_date: '2026-09-01', reference_type: 'INVOICE_RETURN', reference_id: 90000,
      description: 'Legacy return fixture', created_by: 1, lines: [{ account_id: bank.id, debit: 5 }, { account_id: equity.id, credit: 5 }] });
    AccountingService.voidOwnInvoiceReturnLines(db, 90000, { voidedBy: 1, voidReason: 'Legacy source void' });
    expect(db.prepare('SELECT voided,void_reason FROM journal_entries WHERE id=?').get(entry.journal_entry_id)).toEqual({ voided: 1, void_reason: 'Legacy source void' });
  });
});
