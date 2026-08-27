import db from '../config/database';
import AccountingService from '../services/accountingService';
import ItemModel from '../models/Item';
import StockMovementModel from '../models/StockMovement';
import Reports from '../models/Reports';
import OwnerCapitalModel, { generateCapitalNo } from '../models/OwnerCapital';
import OwnerWithdrawalModel, { generateWithdrawalNo } from '../models/OwnerWithdrawal';

const USER = 1;

function uniqueCode(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
}

function activeJournalTotals(referenceType: string, referenceId: number): { dr: number; cr: number; n: number } {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit), 0) AS dr, COALESCE(SUM(credit), 0) AS cr, COUNT(*) AS n
    FROM journal_lines WHERE reference_type = ? AND reference_id = ? AND voided = 0
  `).get(referenceType, referenceId) as { dr: number; cr: number; n: number };
  return { dr: row.dr, cr: row.cr, n: row.n };
}

function wholeLedgerImbalance(): number {
  const row = db.prepare(
    'SELECT COALESCE(SUM(debit), 0) AS dr, COALESCE(SUM(credit), 0) AS cr FROM journal_lines WHERE voided = 0'
  ).get() as { dr: number; cr: number };
  return Math.abs(row.dr - row.cr);
}

function cashAccountId(): number {
  const acct = AccountingService.getAccountByCode(db, '1000');
  if (!acct) throw new Error('Cash account missing');
  return acct.id;
}

function createItem(name: string, standardCost: number): number {
  return ItemModel.create({
    item_code: uniqueCode('OE-ITM'),
    item_name: name,
    category: 'OwnerEquityTests',
    unit_of_measure: 'Nos',
    standard_cost: standardCost,
    standard_selling_price: standardCost * 2,
  }, USER, db);
}

/** Insert a batch layer + matching inbound PURCHASE movement (no auto-GL). */
function createBatch(itemId: number, warehouseId: number, qty: number, unitCost: number, receivedDate: string): number {
  const res = db.prepare(`
    INSERT INTO stock_batches (
      batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date
    ) VALUES (?, ?, ?, 'PURCHASE', 0, ?, ?, ?, ?)
  `).run(uniqueCode('OE-BATCH'), itemId, warehouseId, qty, qty, unitCost, receivedDate);
  const batchId = res.lastInsertRowid as number;
  StockMovementModel.recordMovement({
    item_id: itemId,
    warehouse_id: warehouseId,
    movement_type: 'PURCHASE',
    quantity: qty,
    unit_cost: unitCost,
    movement_date: receivedDate,
    batch_id: batchId,
    remarks: 'owner-equity test fixture',
  }, USER, db);
  return batchId;
}

function batchRemaining(batchId: number): number {
  const row = db.prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?').get(batchId) as { quantity_remaining: number };
  return Number(row.quantity_remaining);
}

function anyWarehouseId(): number {
  const row = db.prepare('SELECT id FROM warehouses WHERE is_active = 1 ORDER BY id LIMIT 1').get() as { id: number } | undefined;
  if (row) return row.id;
  return db.prepare('INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES (?, ?)').run(uniqueCode('WH'), 'OE Test WH').lastInsertRowid as number;
}

describe('owner equity migration', () => {
  it('seeds exactly one equity child per text_code', () => {
    for (const [textCode, code] of [['owner_capital', '3200'], ['owner_drawings', '3300']] as const) {
      const rows = db.prepare(
        'SELECT code, name, type, normal_balance FROM chart_of_accounts WHERE text_code = ?'
      ).all(textCode) as Array<{ code: string; type: string; normal_balance: string }>;
      expect(rows).toHaveLength(1);
      expect(rows[0].code).toBe(code);
      expect(rows[0].type).toBe('equity');
      expect(rows[0].normal_balance).toBe(textCode === 'owner_drawings' ? 'debit' : 'credit');
    }
  });
});

describe('owner capital', () => {
  beforeAll(() => {
    // Deterministic cash headroom for every test in this file.
    db.transaction(() => {
      OwnerCapitalModel.create(db, {
        capital_no: generateCapitalNo(db, '2026-01-01'),
        capital_date: '2026-01-01',
        amount: 1_000_000,
        payment_method: 'Cash',
        created_by: USER,
      });
    })();
  });

  it('posts a balanced Dr Cash / Cr Owner Capital entry', () => {
    const id = OwnerCapitalModel.create(db, {
      capital_no: generateCapitalNo(db, '2026-02-01'),
      capital_date: '2026-02-01',
      amount: 5000,
      payment_method: 'Cash',
      created_by: USER,
    });
    const totals = activeJournalTotals('OWNER_CAPITAL', id);
    expect(totals.n).toBe(2);
    expect(totals.dr).toBeCloseTo(5000, 2);
    expect(totals.dr - totals.cr).toBeCloseTo(0, 2);

    const lines = db.prepare(`
      SELECT coa.code, jl.debit, jl.credit FROM journal_lines jl
      JOIN chart_of_accounts coa ON coa.id = jl.account_id
      WHERE jl.reference_type = 'OWNER_CAPITAL' AND jl.reference_id = ? AND jl.voided = 0
    `).all(id) as Array<{ code: string; debit: number; credit: number }>;
    expect(lines.find((l) => l.code === '1000')?.debit).toBeCloseTo(5000, 2);
    expect(lines.find((l) => l.code === '3200')?.credit).toBeCloseTo(5000, 2);
  });

  it('blocks cash withdrawals that overdraw the account', () => {
    const balanceBefore = AccountingService.getAccountBalance(db, cashAccountId(), '2099-01-01').balance;
    expect(() =>
      OwnerWithdrawalModel.create(db, {
        withdrawal_no: generateWithdrawalNo(db, '2099-01-01'),
        withdrawal_date: '2099-01-01',
        kind: 'cash',
        amount: Math.max(balanceBefore, 0) * 10 + 1000,
        payment_method: 'Cash',
        created_by: USER,
      })
    ).toThrow(/Insufficient funds/i);
  });

  it('keeps the whole ledger balanced after operations', () => {
    expect(wholeLedgerImbalance()).toBeLessThan(0.01);
  });

  it('soft-voids capital: GL voided with attribution, row kept', () => {
    const id = OwnerCapitalModel.create(db, {
      capital_no: generateCapitalNo(db, '2026-02-02'),
      capital_date: '2026-02-02',
      amount: 777,
      payment_method: 'Cash',
      created_by: USER,
    });
    OwnerCapitalModel.softVoid(db, id, { userId: USER, reason: 'test void' });

    expect(OwnerCapitalModel.getById(db, id)?.status).toBe('voided');

    const voided = db.prepare(`
      SELECT voided, void_reason FROM journal_lines
      WHERE reference_type = 'OWNER_CAPITAL' AND reference_id = ?
    `).all(id) as Array<{ voided: number; void_reason: string | null }>;
    expect(voided.length).toBeGreaterThan(0);
    voided.forEach((l) => {
      expect(l.voided).toBe(1);
      expect(l.void_reason).toContain('test void');
    });

    const list = OwnerCapitalModel.getAll(db, {}) as Array<{ id: number }>;
    expect(list.find((r) => r.id === id)).toBeUndefined();
  });

  it('enforces the duplicate-posting invariant', () => {
    const id = OwnerCapitalModel.create(db, {
      capital_no: generateCapitalNo(db, '2026-02-03'),
      capital_date: '2026-02-03',
      amount: 123,
      payment_method: 'Cash',
      created_by: USER,
    });
    // Retry-after-timeout simulation: a second posting for the same
    // business reference must be refused.
    expect(() =>
      AccountingService.assertNoActivePosting(db, 'OWNER_CAPITAL', id)
    ).toThrow(/refusing to double-post/i);
  });

  it('blocks edits/deletes dated inside a closed period', () => {
    const periodName = '2019-05';
    db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES (?, '2019-05-01', '2019-05-31', 'open')
      ON CONFLICT(period_name) DO NOTHING
    `).run(periodName);

    const id = OwnerCapitalModel.create(db, {
      capital_no: generateCapitalNo(db, '2019-05-10'),
      capital_date: '2019-05-10',
      amount: 50,
      payment_method: 'Cash',
      created_by: USER,
    });

    db.prepare(`UPDATE accounting_periods SET status = 'closed' WHERE period_name = ?`).run(periodName);
    try {
      expect(() =>
        OwnerCapitalModel.update(db, id, { note: 'nope' }, { userId: USER })
      ).toThrow(/closed accounting period/i);
      expect(() =>
        OwnerCapitalModel.softVoid(db, id, { userId: USER })
      ).toThrow(/closed accounting period/i);
    } finally {
      db.prepare(`UPDATE accounting_periods SET status = 'open' WHERE period_name = ?`).run(periodName);
    }
  });

  it('note-only edits do not touch the GL', () => {
    const id = OwnerCapitalModel.create(db, {
      capital_no: generateCapitalNo(db, '2026-02-04'),
      capital_date: '2026-02-04',
      amount: 250,
      payment_method: 'Cash',
      note: 'before',
      created_by: USER,
    });
    const before = activeJournalTotals('OWNER_CAPITAL', id);
    OwnerCapitalModel.update(db, id, { note: 'after' }, { userId: USER });
    const after = activeJournalTotals('OWNER_CAPITAL', id);
    expect(after.n).toBe(before.n);
    expect(OwnerCapitalModel.getById(db, id)?.note).toBe('after');
  });

  it('summary totals count posted rows only and net correctly', () => {
    const s = OwnerCapitalModel.getSummaryTotals(db);
    expect(s.total_capital_in).toBeGreaterThanOrEqual(1_000_000);
    expect(s.net_contributions)
      .toBeCloseTo(s.total_capital_in - s.total_withdrawn_cash - s.total_withdrawn_goods, 2);
  });
});

describe('owner withdrawals — cash', () => {
  it('posts balanced Dr Drawings / Cr Cash and reduces cash', () => {
    const cashBefore = AccountingService.getAccountBalance(db, cashAccountId(), '2026-04-01').balance;
    const { id } = OwnerWithdrawalModel.create(db, {
      withdrawal_no: generateWithdrawalNo(db, '2026-04-01'),
      withdrawal_date: '2026-04-01',
      kind: 'cash',
      amount: 300,
      payment_method: 'Cash',
      created_by: USER,
    });
    const totals = activeJournalTotals('OWNER_WITHDRAWAL', id);
    expect(totals.n).toBe(2);
    expect(totals.dr).toBeCloseTo(300, 2);
    expect(totals.dr - totals.cr).toBeCloseTo(0, 2);

    const drawingsLine = db.prepare(`
      SELECT coa.code FROM journal_lines jl JOIN chart_of_accounts coa ON coa.id = jl.account_id
      WHERE jl.reference_type='OWNER_WITHDRAWAL' AND jl.reference_id=? AND jl.voided=0 AND jl.debit > 0
    `).get(id) as { code: string };
    expect(drawingsLine.code).toBe('3300');

    const cashAfter = AccountingService.getAccountBalance(db, cashAccountId(), '2026-04-01').balance;
    expect(cashAfter).toBeCloseTo(cashBefore - 300, 2);
  });
});

describe('owner withdrawals — goods', () => {
  let warehouseId: number;
  let itemA: number;
  let batchOld: number;
  let batchNew: number;
  let batchTop: number;

  beforeAll(() => {
    warehouseId = anyWarehouseId();
    itemA = createItem('OE Goods Item A', 999);
    batchOld = createBatch(itemA, warehouseId, 2, 100, '2020-01-01'); // FIFO-first
    batchNew = createBatch(itemA, warehouseId, 5, 120, '2021-01-01');
  });

  it('consumes FIFO layers at actual cost; Dr Drawings == Σ Cr Inventory', () => {
    const result = OwnerWithdrawalModel.create(db, {
      withdrawal_no: generateWithdrawalNo(db, '2026-05-01'),
      withdrawal_date: '2026-05-01',
      kind: 'goods',
      items: [{ item_id: itemA, warehouse_id: warehouseId, quantity: 4 }],
      created_by: USER,
    });

    // 2 × 100 (old batch) + 2 × 120 (new batch) = 440
    expect(result.amount).toBeCloseTo(440, 2);
    expect(activeJournalTotals('OWNER_WITHDRAWAL', result.id).dr).toBeCloseTo(440, 2);
    expect(batchRemaining(batchOld)).toBe(0);
    expect(batchRemaining(batchNew)).toBe(3);
  });

  it('quote matches costs without persisting anything', () => {
    const q = OwnerWithdrawalModel.quote(db, [{ item_id: itemA, warehouse_id: warehouseId, quantity: 2 }]);
    expect(q.totalCost).toBeCloseTo(240, 2); // 2 × 120 from the remaining layer
    expect(q.lines[0].batches[0].unitCost).toBe(120);
    expect(batchRemaining(batchNew)).toBe(3); // quote rolled back its decrements
  });

  it('blocks insufficient stock atomically', () => {
    const balBefore = Number((db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemA, warehouseId) as { quantity: number }).quantity);

    expect(() =>
      OwnerWithdrawalModel.create(db, {
        withdrawal_no: generateWithdrawalNo(db, '2026-05-02'),
        withdrawal_date: '2026-05-02',
        kind: 'goods',
        items: [{ item_id: itemA, warehouse_id: warehouseId, quantity: balBefore + 999 }],
        created_by: USER,
      })
    ).toThrow(/Insufficient stock/i);

    const balAfter = Number((db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemA, warehouseId) as { quantity: number }).quantity);
    expect(balAfter).toBe(balBefore);
  });

  it('multi-item withdrawal sums costs across items into one balanced entry', () => {
    const itemB = createItem('OE Goods Item B', 40);
    createBatch(itemB, warehouseId, 3, 40, '2022-01-01');

    const result = OwnerWithdrawalModel.create(db, {
      withdrawal_no: generateWithdrawalNo(db, '2026-05-03'),
      withdrawal_date: '2026-05-03',
      kind: 'goods',
      items: [
        { item_id: itemA, warehouse_id: warehouseId, quantity: 1 },
        { item_id: itemB, warehouse_id: warehouseId, quantity: 2 },
      ],
      created_by: USER,
    });

    // 1 × 120 + 2 × 40
    expect(result.amount).toBeCloseTo(200, 2);
    const totals = activeJournalTotals('OWNER_WITHDRAWAL', result.id);
    expect(totals.dr).toBeCloseTo(200, 2);
    expect(totals.dr - totals.cr).toBeCloseTo(0, 2);
    expect(batchRemaining(batchNew)).toBe(2);
  });

  it('edit re-consumes through compensating movements (-5 +5 -7 = -7)', () => {
    // Top up a third FIFO layer FIRST so 5 units are available.
    batchTop = createBatch(itemA, warehouseId, 10, 130, '2023-01-01');

    const created = OwnerWithdrawalModel.create(db, {
      withdrawal_no: generateWithdrawalNo(db, '2026-06-01'),
      withdrawal_date: '2026-06-01',
      kind: 'goods',
      items: [{ item_id: itemA, warehouse_id: warehouseId, quantity: 5 }],
      created_by: USER,
    });
    // Layers: batchNew has 2 left ⇒ 2 × 120 + 3 × 130 = 630
    expect(created.amount).toBeCloseTo(630, 2);
    const remNewAfterCreate = batchRemaining(batchNew);
    expect(remNewAfterCreate).toBe(0);

    const updated = OwnerWithdrawalModel.update(db, created.id, {
      items: [{ item_id: itemA, warehouse_id: warehouseId, quantity: 7 }],
    }, { userId: USER });
    // Restore (+2 @120, +3 @130) then re-consume 7: 2 × 120 + 5 × 130 = 890
    expect(updated.amount).toBeCloseTo(890, 2);
    expect(batchRemaining(batchNew)).toBe(0);
    expect(batchRemaining(batchTop)).toBe(5);

    // Original outbound rows preserved; reversals added; net effect −7 units.
    const docNo = (db.prepare('SELECT withdrawal_no FROM owner_withdrawals WHERE id = ?').get(created.id) as { withdrawal_no: string }).withdrawal_no;
    const movements = db.prepare(`
      SELECT movement_type, quantity FROM stock_movements
      WHERE reference_doctype IN ('OWNER_WITHDRAWAL','OWNER_WITHDRAWAL_REVERSAL')
        AND reference_docno = ? ORDER BY id ASC
    `).all(docNo) as Array<{ movement_type: string; quantity: number }>;

    const outQty = movements.filter((m) => m.movement_type === 'OWNER_WITHDRAWAL')
      .reduce((s, m) => s + Math.abs(m.quantity), 0);
    const inQty = movements.filter((m) => m.movement_type === 'OWNER_WITHDRAWAL_REVERSAL')
      .reduce((s, m) => s + m.quantity, 0);
    expect(outQty - inQty).toBe(7);
    expect(movements.some((m) => m.movement_type === 'OWNER_WITHDRAWAL_REVERSAL')).toBe(true);

    const totals = activeJournalTotals('OWNER_WITHDRAWAL', created.id);
    expect(totals.dr).toBeCloseTo(890, 2);
    expect(totals.dr - totals.cr).toBeCloseTo(0, 2);
  });

  it('delete returns stock exactly and voids the posting', () => {
    const created = OwnerWithdrawalModel.create(db, {
      withdrawal_no: generateWithdrawalNo(db, '2026-06-02'),
      withdrawal_date: '2026-06-02',
      kind: 'goods',
      items: [{ item_id: itemA, warehouse_id: warehouseId, quantity: 2 }],
      created_by: USER,
    });
    const remBefore = batchRemaining(batchTop);

    OwnerWithdrawalModel.softVoid(db, created.id, { userId: USER, reason: 'test delete' });

    expect(batchRemaining(batchTop)).toBe(remBefore + 2);
    expect(OwnerWithdrawalModel.getById(db, created.id)?.status).toBe('voided');
    expect(activeJournalTotals('OWNER_WITHDRAWAL', created.id).n).toBe(0);
  });
});

describe('zero-profit boundary', () => {
  it('owner transactions never touch P&L and keep assets == liabilities + equity', () => {
    const plBefore = Reports.getProfitLossReport('2026-01-01', '2099-12-31', db);

    const capId = OwnerCapitalModel.create(db, {
      capital_no: generateCapitalNo(db, '2026-07-01'),
      capital_date: '2026-07-01',
      amount: 10000,
      payment_method: 'Cash',
      created_by: USER,
    });
    const wd = OwnerWithdrawalModel.create(db, {
      withdrawal_no: generateWithdrawalNo(db, '2026-07-02'),
      withdrawal_date: '2026-07-02',
      kind: 'cash',
      amount: 4000,
      payment_method: 'Cash',
      created_by: USER,
    });

    const plAfter = Reports.getProfitLossReport('2026-01-01', '2099-12-31', db);
    expect(plAfter.totalRevenue).toBeCloseTo(Number(plBefore.totalRevenue), 2);
    expect(plAfter.totalExpenses).toBeCloseTo(Number(plBefore.totalExpenses), 2);

    const bs = Reports.getBalanceSheet('2099-12-31', db);
    expect(bs.equity.owner_capital).toBeGreaterThan(0);
    expect(bs.equity.owner_drawings).toBeLessThanOrEqual(0);
    expect(bs.totals.balanced).toBe(true);

    expect(activeJournalTotals('OWNER_CAPITAL', capId).dr)
      .toBeCloseTo(activeJournalTotals('OWNER_CAPITAL', capId).cr, 2);
    expect(activeJournalTotals('OWNER_WITHDRAWAL', wd.id).dr)
      .toBeCloseTo(activeJournalTotals('OWNER_WITHDRAWAL', wd.id).cr, 2);
  });
});
