import Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';
import { getNextSequenceNumber } from '../utils/sequence';

export interface OwnerCapitalFilters {
  status?: string;
  from_date?: string;
  to_date?: string;
  search?: string;
  page?: number;
  limit?: number;
  sortBy?: string;
  sortOrder?: string;
}

export interface CreateOwnerCapitalDTO {
  capital_no: string;
  capital_date: string;
  amount: number;
  payment_method?: string;
  note?: string;
  created_by: number;
}

export interface UpdateOwnerCapitalDTO {
  capital_date?: string;
  amount?: number;
  payment_method?: string | null;
  note?: string | null;
}

interface OwnerCapitalRow {
  id: number;
  capital_no: string;
  capital_date: string;
  amount: number;
  payment_method: string | null;
  note: string | null;
  status: string;
}

export function generateCapitalNo(db: Database.Database, capitalDate: string): string {
  const date = new Date(capitalDate);
  const year = date.getFullYear().toString().slice(-2);
  const month = String(date.getMonth() + 1).padStart(2, '0');

  // Shared atomic counter, allocated inside the same transaction as the
  // INSERT (EXP-05 pattern); UNIQUE(capital_no) backstops it.
  const nextNo = getNextSequenceNumber(db, `CAP_last_no_${year}${month}`);
  return `CAP-${year}${month}-${String(nextNo).padStart(4, '0')}`;
}

function create(db: Database.Database, data: CreateOwnerCapitalDTO): number {
  return db.transaction(() => {
    const result = db.prepare(`
      INSERT INTO owner_capital (
        capital_no, capital_date, amount, payment_method, note, status, created_by
      ) VALUES (?, ?, ?, ?, ?, 'posted', ?)
    `).run(
      data.capital_no, data.capital_date, data.amount,
      data.payment_method || null, data.note || null, data.created_by
    );
    const newId = result.lastInsertRowid as number;

    // Duplicate-posting invariant, then GL posting:
    // Dr cash-per-method / Cr 3200 Owner Capital. Any throw rolls the
    // whole transaction (row + GL) back. Capital is an inflow — the
    // funds guard does not apply.
    AccountingService.assertNoActivePosting(db, 'OWNER_CAPITAL', newId);

    AccountingService.postOwnerCapitalEntry(db, {
      capitalId: newId,
      capitalNo: data.capital_no,
      amount: data.amount,
      capitalDate: data.capital_date,
      paymentMethod: data.payment_method,
      userId: data.created_by,
    });

    return newId;
  })();
}

function getAll(db: Database.Database, filters: OwnerCapitalFilters = {}) {
  const pageNum = filters.page || 1;
  const limitNum = filters.limit || 10;
  const offset = (pageNum - 1) * limitNum;

  let query = `
    SELECT oc.id, oc.capital_no, oc.capital_date, oc.amount, oc.payment_method,
           oc.note, oc.status, oc.created_at, u.full_name as created_by_name
    FROM owner_capital oc LEFT JOIN users u ON oc.created_by = u.id WHERE 1=1
  `;
  const params: (string | number)[] = [];

  // Voided rows are excluded by default; pass status='all' or a specific
  // status to widen.
  if (filters.status && filters.status !== 'all') {
    query += ' AND oc.status = ?';
    params.push(filters.status);
  } else if (!filters.status) {
    query += " AND oc.status = 'posted'";
  }
  if (filters.from_date) { query += ' AND oc.capital_date >= ?'; params.push(filters.from_date); }
  if (filters.to_date) { query += ' AND oc.capital_date <= ?'; params.push(filters.to_date); }
  if (filters.search) {
    const term = `%${filters.search}%`;
    query += ' AND (oc.capital_no LIKE ? OR oc.note LIKE ? OR oc.payment_method LIKE ?)';
    params.push(term, term, term);
  }

  query += ` ORDER BY ${filters.sortBy || 'oc.capital_date'} ${filters.sortOrder || 'DESC'} LIMIT ? OFFSET ?`;
  params.push(limitNum, offset);

  return db.prepare(query).all(...params);
}

function getCount(db: Database.Database, filters: OwnerCapitalFilters = {}): number {
  let query = 'SELECT COUNT(*) as count FROM owner_capital oc WHERE 1=1';
  const params: (string | number)[] = [];

  if (filters.status && filters.status !== 'all') {
    query += ' AND oc.status = ?';
    params.push(filters.status);
  } else if (!filters.status) {
    query += " AND oc.status = 'posted'";
  }
  if (filters.from_date) { query += ' AND oc.capital_date >= ?'; params.push(filters.from_date); }
  if (filters.to_date) { query += ' AND oc.capital_date <= ?'; params.push(filters.to_date); }
  if (filters.search) {
    const term = `%${filters.search}%`;
    query += ' AND (oc.capital_no LIKE ? OR oc.note LIKE ? OR oc.payment_method LIKE ?)';
    params.push(term, term, term);
  }

  return (db.prepare(query).get(...params) as { count: number }).count;
}

function getById(db: Database.Database, id: number): OwnerCapitalRow | undefined {
  return db.prepare(`
    SELECT oc.id, oc.capital_no, oc.capital_date, oc.amount, oc.payment_method,
           oc.note, oc.status, oc.created_at, oc.updated_at,
           u.full_name as created_by_name
    FROM owner_capital oc LEFT JOIN users u ON oc.created_by = u.id WHERE oc.id = ?
  `).get(id) as OwnerCapitalRow | undefined;
}

/**
 * Diff-based edit. Note-only changes touch metadata only; any change to
 * date/amount/method re-posts: void old lines → funds-check against the
 * NEW effective state → post replacement — one atomic transaction.
 */
function update(
  db: Database.Database,
  id: number,
  data: UpdateOwnerCapitalDTO,
  opts: { userId: number }
): void {
  const existing = getById(db, id);
  if (!existing) throw new Error('Owner capital entry not found');
  if (existing.status === 'voided') throw new Error('A voided owner capital entry cannot be edited');
  AccountingService.assertPeriodNotClosed(db, existing.capital_date, `Owner capital ${existing.capital_no}`);

  const newDate = data.capital_date ?? existing.capital_date;
  const newAmount = data.amount !== undefined ? data.amount : existing.amount;
  const newMethod = data.payment_method !== undefined ? data.payment_method : existing.payment_method;
  const moneyChanged =
    String(newDate) !== String(existing.capital_date) ||
    Number(newAmount) !== Number(existing.amount) ||
    String(newMethod ?? '') !== String(existing.payment_method ?? '');

  db.transaction(() => {
    if (moneyChanged) {
      if (!(Number(newAmount) > 0)) throw new Error('Amount must be a positive number');

      AccountingService.voidJournalLinesByReference(db, 'OWNER_CAPITAL', id, {
        voidedBy: opts.userId ?? null,
        voidReason: 'Re-posted after edit',
      });

      db.prepare(`
        UPDATE owner_capital SET capital_date = ?, amount = ?, payment_method = ?,
          note = COALESCE(?, note), updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(newDate, newAmount, newMethod, data.note ?? null, id);

      AccountingService.postOwnerCapitalEntry(db, {
        capitalId: id,
        capitalNo: existing.capital_no,
        amount: newAmount,
        capitalDate: newDate,
        paymentMethod: newMethod ?? undefined,
        userId: opts.userId,
      });
    } else {
      db.prepare(`
        UPDATE owner_capital SET note = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
      `).run(data.note !== undefined ? data.note : existing.note, id);
    }
  })();
}

/**
 * Soft delete: void GL lines (kept with attribution) and mark the row
 * voided. Nothing is physically removed.
 */
function softVoid(
  db: Database.Database,
  id: number,
  opts: { userId: number; reason?: string }
): void {
  const existing = getById(db, id);
  if (!existing) throw new Error('Owner capital entry not found');
  if (existing.status === 'voided') throw new Error('Owner capital entry is already voided');
  AccountingService.assertPeriodNotClosed(db, existing.capital_date, `Owner capital ${existing.capital_no}`);

  db.transaction(() => {
    AccountingService.voidJournalLinesByReference(db, 'OWNER_CAPITAL', id, {
      voidedBy: opts.userId ?? null,
      voidReason: opts.reason || 'Owner capital voided',
    });
    db.prepare(`
      UPDATE owner_capital SET status = 'voided', voided_at = CURRENT_TIMESTAMP,
        voided_by = ?, void_reason = ?, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(opts.userId ?? null, opts.reason || 'Owner capital voided', id);
  })();
}

/** Card totals over posted rows only. */
function getSummaryTotals(db: Database.Database): {
  total_capital_in: number;
  total_withdrawn_cash: number;
  total_withdrawn_goods: number;
  net_contributions: number;
} {
  const capital = db.prepare(
    `SELECT COALESCE(SUM(amount), 0) AS t FROM owner_capital WHERE status = 'posted'`
  ).get() as { t: number };
  const withdrawn = db.prepare(`
    SELECT
      COALESCE(SUM(CASE WHEN kind = 'cash' THEN amount ELSE 0 END), 0) AS cash,
      COALESCE(SUM(CASE WHEN kind = 'goods' THEN amount ELSE 0 END), 0) AS goods
    FROM owner_withdrawals WHERE status = 'posted'
  `).get() as { cash: number; goods: number };

  const totalCapitalIn = parseFloat(String(capital.t)) || 0;
  const totalWithdrawnCash = parseFloat(String(withdrawn.cash)) || 0;
  const totalWithdrawnGoods = parseFloat(String(withdrawn.goods)) || 0;
  return {
    total_capital_in: totalCapitalIn,
    total_withdrawn_cash: totalWithdrawnCash,
    total_withdrawn_goods: totalWithdrawnGoods,
    net_contributions: parseFloat((totalCapitalIn - totalWithdrawnCash - totalWithdrawnGoods).toFixed(2)),
  };
}

export default {
  generateCapitalNo,
  create,
  getAll,
  getCount,
  getById,
  update,
  softVoid,
  getSummaryTotals,
};
