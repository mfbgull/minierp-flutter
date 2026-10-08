/**
 * SALES-007 / ACCT-004 — AR surfaces must agree with GL 1100.
 *
 * `deleteInvoice` is an AUD-06 soft delete: the row survives with
 * `status = 'Deleted'` and `balance_amount` intact. `AR_OUTSTANDING` filtered
 * on status only, so a deleted invoice counted as live AR and the AR/GL
 * reconciliation diverged by exactly the deleted invoice's total.
 *
 * A second, quieter defect: AR aging assigned a NULL `due_date` to no bucket,
 * so the buckets failed to foot to `total_outstanding` by exactly that
 * balance.
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import ReportsModel from '../models/Reports';
import { AR_OUTSTANDING } from '../utils/reportSql';
import { resolveDueDate } from '../services/InvoiceCreationService';

const MIGRATIONS = [
  'init.sql',
  'add-invoice-discount-tax-fields.sql',
  'add-gl-foundation.sql',
  'create-customer-ledger.sql',
  'create-supplier-ledger.sql',
  'create-payment-allocations.sql',
  'add-supplier-payment-support.sql',
  'add-purchases-table.sql',
  'add-purchase-return-fields.sql',
  'add-batch-costing.sql',
  'add-purchase-supplier-payment.sql',
  'add-gl-void-attribution.sql',
  'add-salary-payments.sql',
  'add-cash-accounts.sql',
  'add-payment-salary-void-columns.sql',
  'add-invoice-soft-delete.sql',
  'add-audit-trail-fields.sql',
];

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  const applied: string[] = [];
  for (const f of MIGRATIONS) {
    try {
      db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
      applied.push(f);
    } catch (e) {
      throw new Error(
        `migration ${f} failed after [${applied.join(', ')}]: ${(e as Error).message}`,
      );
    }
  }
  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  db.prepare(`INSERT INTO customers (customer_code,customer_name,is_active)
              VALUES ('C1','Acme Co',1)`).run();
  return db;
}

let n = 0;
function invoice(
  db: Database.Database,
  o: { balance: number; due?: string | null; deleted?: boolean; status?: string },
): number {
  n += 1;
  const id = db.prepare(`
    INSERT INTO invoices (invoice_no, customer_id, invoice_date, due_date, status,
      total_amount, paid_amount, balance_amount, created_by)
    VALUES (?, 1, '2026-03-01', ?, ?, ?, 0, ?, 1)
  `).run(
    `INV-${n}`,
    o.due === undefined ? '2026-04-01' : o.due,
    o.status ?? 'Issued',
    o.balance,
    o.balance,
  ).lastInsertRowid as number;

  if (o.deleted) {
    db.prepare(`UPDATE invoices SET status = 'Deleted', deleted_at = CURRENT_TIMESTAMP WHERE id = ?`).run(id);
  }
  return id;
}

const arOutstanding = (db: Database.Database): number => {
  const row = db.prepare(
    `SELECT COALESCE(SUM(balance_amount),0) AS t FROM invoices i WHERE ${AR_OUTSTANDING('i')}`,
  ).get() as { t: number };
  return Number(row.t);
};

describe('SALES-007 — a soft-deleted invoice is not outstanding AR', () => {
  it('the shared predicate excludes deleted rows', () => {
    const db = createFixture();
    invoice(db, { balance: 400, deleted: true });
    invoice(db, { balance: 100 });

    expect(arOutstanding(db)).toBe(100);
    db.close();
  });

  it('the predicate still admits live invoices', () => {
    expect(AR_OUTSTANDING('i')).toContain('deleted_at IS NULL');
    expect(AR_OUTSTANDING('i')).toContain('balance_amount > 0');
    expect(AR_OUTSTANDING('i')).toContain("NOT IN ('Cancelled', 'Draft')");
  });

  it('AR aging excludes a deleted invoice', () => {
    const db = createFixture();
    invoice(db, { balance: 400, deleted: true });
    invoice(db, { balance: 260 });

    const r = ReportsModel.getARAgingReport('2026-06-01', db) as unknown as {
      summary: { totalReceivables: number };
    };
    expect(r.summary.totalReceivables).toBe(260);
    db.close();
  });

  it('top debtors excludes a deleted invoice', () => {
    const db = createFixture();
    invoice(db, { balance: 900, deleted: true });
    invoice(db, { balance: 120 });

    const rows = ReportsModel.getTopDebtors(db, 10, '2026-06-01') as unknown as Array<{
      total_outstanding: number;
    }>;
    expect(rows.reduce((s, r) => s + Number(r.total_outstanding), 0)).toBe(120);
    db.close();
  });
});

describe('ACCT-004 — AR aging buckets foot to the total outstanding', () => {
  it('a balance with no due_date still lands in a bucket', () => {
    const db = createFixture();
    invoice(db, { balance: 175, due: null });

    const r = ReportsModel.getARAgingReport('2026-06-01', db) as unknown as {
      summary: {
        totalReceivables: number; current_amount: number;
        total_1_30: number; total_31_60: number; total_61_90: number; total_over_90: number;
      };
    };
    const s = r.summary;
    expect(s.totalReceivables).toBe(175);

    // The defect: the 175 appeared in the total but in no bucket, so the
    // report did not foot.
    expect(
      s.current_amount + s.total_1_30 + s.total_31_60 + s.total_61_90 + s.total_over_90,
    ).toBeCloseTo(s.totalReceivables, 2);
    db.close();
  });

  it('mixed dated and undated invoices still foot', () => {
    const db = createFixture();
    invoice(db, { balance: 100, due: '2026-03-05' });   // ~88 days -> 61-90
    invoice(db, { balance: 220, due: '2026-05-30' });   // not yet due
    invoice(db, { balance: 175, due: null });            // unknown maturity

    const r = ReportsModel.getARAgingReport('2026-06-01', db) as unknown as {
      summary: {
        totalReceivables: number; current_amount: number;
        total_1_30: number; total_31_60: number; total_61_90: number; total_over_90: number;
      };
    };
    const s = r.summary;
    expect(s.totalReceivables).toBeCloseTo(495, 2);
    expect(
      s.current_amount + s.total_1_30 + s.total_31_60 + s.total_61_90 + s.total_over_90,
    ).toBeCloseTo(s.totalReceivables, 2);
    db.close();
  });
});
describe('SALES-017 — a due date is derived from the customer payment terms', () => {
  function fixture(): Database.Database {
    const db = new Database(':memory:');
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', 'init.sql'), 'utf8'));
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', 'add-customer-ar-fields.sql'), 'utf8'));
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', 'add-mobile-invoice-tables.sql'), 'utf8'));
    db.prepare(`INSERT INTO customers (customer_code, customer_name, is_active)
                VALUES ('C1','Acme',1)`).run();
    db.prepare(`INSERT INTO customers (customer_code, customer_name, is_active, payment_terms_days)
                VALUES ('C30','Net30 Co',1,30)`).run();
    db.prepare(`INSERT INTO customers (customer_code, customer_name, is_active, payment_terms_days)
                VALUES ('C0','NoTerms Co',1,NULL)`).run();
    return db;
  }

  it('uses the customer\'s own term', () => {
    const db = fixture();
    // Default seeded term is 14 days.
    expect(resolveDueDate(db, 1, '2026-03-01')).toBe('2026-03-15');
    expect(resolveDueDate(db, 2, '2026-03-01')).toBe('2026-03-31');
    db.close();
  });

  it('falls back to the default payment_terms row when the customer has none', () => {
    const db = fixture();
    // payment_terms seeds 'Due on Receipt' as is_default => 0 days.
    expect(resolveDueDate(db, 3, '2026-03-01')).toBe('2026-03-01');
    db.close();
  });

  it('no longer applies the hardcoded 15 days that contradicted the 14-day default', () => {
    const db = fixture();
    const derived = resolveDueDate(db, 1, '2026-03-01');
    const fifteen = new Date('2026-03-01T00:00:00.000Z');
    fifteen.setUTCDate(fifteen.getUTCDate() + 15);
    expect(derived).not.toBe(fifteen.toISOString().slice(0, 10));
    db.close();
  });
});
