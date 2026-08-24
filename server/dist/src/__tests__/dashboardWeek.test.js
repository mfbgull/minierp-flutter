"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const Dashboard_1 = __importDefault(require("../models/Dashboard"));
const weekMath_1 = require("../utils/weekMath");
let db;
beforeEach(() => {
    db = new better_sqlite3_1.default(':memory:');
    db.exec(`
    CREATE TABLE user_preferences (
      user_id       INTEGER PRIMARY KEY,
      week_start    TEXT NOT NULL DEFAULT 'monday',
      default_range TEXT,
      presets       TEXT NOT NULL DEFAULT '[]',
      updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE invoices (
      id            INTEGER PRIMARY KEY,
      invoice_no    TEXT,
      customer_id   INTEGER,
      invoice_date  TEXT,
      status        TEXT,
      total_amount  REAL DEFAULT 0,
      paid_amount   REAL DEFAULT 0,
      balance_amount REAL DEFAULT 0
    );
    CREATE TABLE expenses (
      id           INTEGER PRIMARY KEY,
      expense_no   TEXT,
      expense_date TEXT,
      status       TEXT,
      amount       REAL DEFAULT 0
    );
  `);
});
afterEach(() => {
    db.close();
});
/** SQLite's notion of today — the same anchor the model uses
 * (`date('now', 'localtime')`; see Dashboard.todayISO). Must match, or
 * seeds land around the wrong day whenever the local date differs from
 * the UTC date (e.g. UTC+5 after midnight). */
function todayISO() {
    return db.prepare(`SELECT date('now', 'localtime') as d`).get().d;
}
function addDaysISO(iso, n) {
    const [y, m, d] = iso.split('-').map(Number);
    const dt = new Date(Date.UTC(y, m - 1, d + n));
    return [
        dt.getUTCFullYear(),
        String(dt.getUTCMonth() + 1).padStart(2, '0'),
        String(dt.getUTCDate()).padStart(2, '0'),
    ].join('-');
}
function seedInvoice(date, amount) {
    db.prepare(`INSERT INTO invoices (invoice_no, customer_id, invoice_date, status, total_amount, paid_amount, balance_amount)
     VALUES (?, 1, ?, 'Paid', ?, ?, 0)`).run(`INV-${Date.now()}-${Math.floor(Math.random() * 1e6)}`, date, amount, amount);
}
function seedExpense(date, amount) {
    db.prepare(`INSERT INTO expenses (expense_no, expense_date, status, amount)
     VALUES (?, ?, 'Approved', ?)`).run(`EXP-${Date.now()}-${Math.floor(Math.random() * 1e6)}`, date, amount);
}
describe('week-aware period=week dashboard summaries', () => {
    for (const weekStart of ['monday', 'saturday', 'sunday']) {
        it(`sales summary bounds the ${weekStart}-first calendar week`, () => {
            db.prepare(`INSERT INTO user_preferences (user_id, week_start) VALUES (1, ?)`).run(weekStart);
            const { from, to } = (0, weekMath_1.weekBounds)(todayISO(), weekStart);
            // Inside the week, just before it, and just after it.
            seedInvoice(from, 100);
            seedInvoice(addDaysISO(from, -1), 200);
            seedInvoice(addDaysISO(to, 1), 300);
            const result = Dashboard_1.default.getSalesSummary(db, 'week', 1);
            expect(result).toEqual({ period_total: 100, count: 1 });
        });
    }
    it('expense summary bounds the saturday-first calendar week', () => {
        db.prepare(`INSERT INTO user_preferences (user_id, week_start) VALUES (1, 'saturday')`).run();
        const { from } = (0, weekMath_1.weekBounds)(todayISO(), 'saturday');
        seedExpense(from, 50);
        seedExpense(addDaysISO(from, -1), 70);
        const result = Dashboard_1.default.getExpenseSummary(db, 'week', 1);
        expect(result).toEqual({ period_total: 50, count: 1 });
    });
    it('falls back to the rolling 7-day window when no user id is given', () => {
        seedInvoice(addDaysISO(todayISO(), -3), 100);
        seedInvoice(addDaysISO(todayISO(), -10), 200);
        const result = Dashboard_1.default.getSalesSummary(db, 'week');
        expect(result).toEqual({ period_total: 100, count: 1 });
    });
    it('uses the monday-first week when a user id has no preference row', () => {
        // User 99 has no row in user_preferences — getForUser backfills the
        // server default (monday), so the week bounds must align to Monday.
        const { from } = (0, weekMath_1.weekBounds)(todayISO(), 'monday');
        seedInvoice(from, 100);
        seedInvoice(addDaysISO(from, -1), 200);
        const result = Dashboard_1.default.getSalesSummary(db, 'week', 99);
        expect(result).toEqual({ period_total: 100, count: 1 });
    });
    it('today and month periods keep their existing rolling semantics', () => {
        seedInvoice(todayISO(), 100);
        seedInvoice(addDaysISO(todayISO(), -40), 200);
        expect(Dashboard_1.default.getSalesSummary(db, 'today', 1)).toEqual({ period_total: 100, count: 1 });
        expect(Dashboard_1.default.getSalesSummary(db, 'month', 1)).toEqual({ period_total: 100, count: 1 });
        expect(Dashboard_1.default.getSalesSummary(db, 'month', 1)).toEqual({ period_total: 100, count: 1 });
    });
    it('a cancelled invoice never counts towards the week total', () => {
        db.prepare(`INSERT INTO user_preferences (user_id, week_start) VALUES (1, 'monday')`).run();
        const { from } = (0, weekMath_1.weekBounds)(todayISO(), 'monday');
        db.prepare(`INSERT INTO invoices (invoice_no, customer_id, invoice_date, status, total_amount)
       VALUES (?, 1, ?, 'Cancelled', ?)`).run(`INV-C-${Date.now()}`, from, 100);
        const result = Dashboard_1.default.getSalesSummary(db, 'week', 1);
        expect(result).toEqual({ period_total: 0, count: 0 });
    });
});
//# sourceMappingURL=dashboardWeek.test.js.map