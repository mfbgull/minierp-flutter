import db from '../config/database';
import PurchaseModel from '../models/Purchase';
import SupplierModel from '../models/Supplier';
import AccountingService from '../services/accountingService';

let sequence = 0;
let purchaseId: number;

beforeEach(() => {
  sequence++;
  const supplier = SupplierModel.create({ supplier_code: `PVH-S${sequence}`, supplier_name: 'Header fixture' }, db);
  const item = db.prepare("INSERT INTO items(item_code,item_name,unit_of_measure,standard_cost) VALUES(?,'Header fixture','pcs',10)")
    .run(`PVH-I${sequence}`);
  purchaseId = PurchaseModel.recordPurchase({ item_id: Number(item.lastInsertRowid), warehouse_id: 1,
    quantity: 5, unit_cost: 10, supplier_id: supplier, purchase_date: '2026-08-01' }, 1, db).id;
});

function legacyHeader(): number {
  return Number(db.prepare(`INSERT INTO journal_entries(reference_type,reference_id,entry_date,description,
    debit_account,credit_account,amount,voided) VALUES('PURCHASE',?,'2026-08-01','Legacy header','1200','2000',50,0)`)
    .run(purchaseId).lastInsertRowid);
}

function extraGroup(mixed: boolean): number {
  const inventory = AccountingService.getAccountByCode(db, '1200');
  const payable = AccountingService.getAccountByCode(db, '2000');
  if (!inventory || !payable) throw new Error('Fixture accounts missing');
  const posting = AccountingService.postEntry(db, {
    entry_date: '2026-08-01', description: 'Linked header fixture', reference_type: 'OTHER', reference_id: purchaseId,
    created_by: 1,
    lines: [
      { account_id: inventory.id, debit: 10 }, { account_id: payable.id, credit: 10 },
      ...(mixed ? [{ account_id: inventory.id, debit: 20 }, { account_id: payable.id, credit: 20 }] : []),
    ],
  });
  db.prepare(`UPDATE journal_lines SET reference_type='PURCHASE' WHERE id IN
    (SELECT id FROM journal_lines WHERE journal_entry_id=? ORDER BY id LIMIT 2)`).run(posting.journal_entry_id);
  return posting.journal_entry_id;
}

test('canonical void retires owned direct/linked headers and preserves mixed active groups', () => {
  const legacyId = legacyHeader();
  const linkedId = extraGroup(false);
  const mixedId = extraGroup(true);
  const unrelatedId = Number(db.prepare(`INSERT INTO journal_entries(reference_type,reference_id,entry_date,description,
    debit_account,credit_account,amount,voided) VALUES('OTHER',?,'2026-08-01','Unrelated','1200','2000',50,0)`)
    .run(purchaseId).lastInsertRowid);
  PurchaseModel.void(purchaseId, 1, 'Header synchronization', db);
  expect(db.prepare("SELECT voided FROM journal_entries WHERE reference_type='PURCHASE' AND reference_id=? ORDER BY id").all(purchaseId))
    .toEqual([{ voided: 1 }, { voided: 1 }]);
  expect(db.prepare('SELECT id,voided FROM journal_entries WHERE id IN (?,?,?,?) ORDER BY id').all(legacyId, linkedId, mixedId, unrelatedId))
    .toEqual([{ id: legacyId, voided: 1 }, { id: linkedId, voided: 1 }, { id: mixedId, voided: 0 }, { id: unrelatedId, voided: 0 }]);
  const lines = db.prepare("SELECT voided,voided_by,void_reason FROM journal_lines WHERE reference_type='PURCHASE' AND reference_id=?").all(purchaseId);
  expect(lines).toHaveLength(6);
  expect(lines).toEqual(Array.from({ length: 6 }, () => ({ voided: 1, voided_by: 1, void_reason: 'Header synchronization' })));
  expect(db.prepare('SELECT voided_by,void_reason FROM purchases WHERE id=?').get(purchaseId))
    .toEqual({ voided_by: 1, void_reason: 'Header synchronization' });
  expect(() => PurchaseModel.void(purchaseId, 1, 'repeat', db)).toThrow('already voided');
});

test('header retirement failure rolls back the purchase, supplier ledger and canonical lines', () => {
  const legacyId = legacyHeader();
  db.exec(`CREATE TEMP TRIGGER reject_purchase_header_void BEFORE UPDATE OF voided ON journal_entries
    WHEN OLD.description='Legacy header' BEGIN SELECT RAISE(ABORT,'header retirement rejected'); END;`);
  const ledger = db.prepare('SELECT * FROM supplier_ledger ORDER BY id').all();
  try {
    expect(() => PurchaseModel.void(purchaseId, 1, 'Rollback check', db)).toThrow('header retirement rejected');
    expect(db.prepare('SELECT voided_at FROM purchases WHERE id=?').get(purchaseId)).toEqual({ voided_at: null });
    expect(db.prepare('SELECT voided FROM journal_entries WHERE id=?').get(legacyId)).toEqual({ voided: 0 });
    expect(db.prepare("SELECT voided FROM journal_lines WHERE reference_type='PURCHASE' AND reference_id=?").all(purchaseId))
      .toEqual([{ voided: 0 }, { voided: 0 }]);
    expect(db.prepare('SELECT * FROM supplier_ledger ORDER BY id').all()).toEqual(ledger);
  } finally {
    db.exec('DROP TRIGGER reject_purchase_header_void');
  }
});
