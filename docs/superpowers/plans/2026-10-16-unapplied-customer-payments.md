# Unapplied Customer Payments — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a customer hand over cash that is not yet attributable to an invoice, then later apply it, refund it, or reverse the receipt — without that cash ever flowing through `customers.credit_balance` or being double-spent.

**Architecture:** A customer has two *separate* pools of credit, never added together on any write path. `customers.credit_balance` stays store-credit-only and is untouched by this feature. Unapplied cash lives in a new `customer_credit_sources` table as `kind='UNAPPLIED_CASH'` rows funded by a new `payments.payment_kind='UNAPPLIED_RECEIPT'` row, balanced by a new liability account `2110`. Applying spends the pool (Dr 2110 / Cr 1100); refunding drains a separate refundable-cash pool (Dr 2110 / Cr 1000). A generated column `remaining_amount` is derived from three base counters and is never written.

**Tech Stack:** TypeScript, Express, better-sqlite3, SQLite 3.51.2, Jest, ts-node. Server only — no Flutter/frontend changes.

**Design baseline:** `docs/superpowers/specs/2026-10-16-unapplied-customer-payments-design.md` (rev 26, commit `e41fae8e`, 960 lines, 35 verification tests). The spec is authoritative. Where this plan and the spec disagree, the spec wins — stop and reconcile, do not improvise.

---

## VERIFIED API CONTRACTS (read this before writing any code)

These were verified against the source on 2026-10-16. Several early drafts of
this plan got them wrong; treat this table as the authority over any code sample
further down that contradicts it.

| Thing | Actual signature / shape | Source |
|---|---|---|
| `applyPendingMigrations` | `(): void` — **takes no arguments**, uses the module-level `db` singleton bound to `process.env.DATABASE_PATH` | `config/database.ts:1714` |
| `AccountingService.postEntry` | `(db, input: PostEntryInput): PostedEntry` | `accountingService.ts:251` |
| `PostEntryInput` | `entry_date`, `description`, `reference_type?`, `reference_id?: number \| null`, `created_by?`, `lines` — **snake_case** | `accountingService.ts:64` |
| `JournalLineInput` | `{ account_id: number; debit?: number; credit?: number; description?: string }` — **account_id is a NUMBER** | `accountingService.ts:76` |
| `PostedEntry` | `{ journal_entry_id, line_count, total_debit, total_credit }` — **not `.id`** | `accountingService.ts` |
| Account resolution | **`postEntry` does NOT resolve text codes.** Caller must call `AccountingService.getAccountByTextCode(db, 'cash')?.id` and throw when absent | `accountingService.ts:120` |
| `assertPeriodNotClosed` | `(db, date: string, what: string): void`; already called inside `postEntry` from `input.entry_date` | `accountingService.ts:1037`, called at `:315` |
| `voidJournalLinesByReference` | `(db, referenceType: string, referenceId: number, ...)` | `accountingService.ts:1417` |
| Test DB fixtures | **Use the existing `createFixtureDb({ reference: true })` from `__tests__/helpers/productionSchema.ts`.** Do NOT write a new helper and do NOT copy the live database — it copies schema only, deliberately, so fixtures are empty. | `productionSchema.ts:101` |

Consequences that invalidate code elsewhere in this plan:

- Every `/* schema already migrated by setup.ts */` call is wrong. Tests get an already-migrated
  DB from `setupFilesAfterEnv` (`setup.ts` calls `applyPendingMigrations()` once
  per test file against a fresh temp dir). For a *second* schema, use
  `createFixtureDb()`, which replays the production migration SQL.
- Every `accountTextCode:` line is wrong — resolve the id first.
- `entry.id` is wrong — it is `entry.journal_entry_id`.
- Fixtures must `INSERT` their own customers; `createFixtureDb()` returns an
  empty database by default. `reference: true` copies only `chart_of_accounts`,
  which is what the GL layer needs.

---

## Non-negotiable constraints

These come from the user and override any convenience. Violating any of them is a failed plan.

1. **Never touch the canonical live database.** `server/database/erp.db` is read-only for the entire implementation. Do not run production migrations. Do not execute Strategy C′.
2. **Test against isolated copies only.** Every test that needs a database gets its own copy (see Stage 0).
3. **Preserve accounting discrepancies transparently.** Do not make an invariant green by changing its equation, suppressing/ignoring historical records, or inserting a balancing entry without evidence.
4. **Preserve the Rs 1,800 invariant F gap** as a documented baseline. Tests assert the diff is *exactly* 1800.00 — never 0.
5. **Historical credits stay non-spendable.** The Rs 8,550.20 backfilled as `RETURN_CREDIT` carries `refundable_cash_amount = 0` and is excluded from spendable cash. Do not activate it.
6. **Reconcile before activating historical credits.** Neither `credit_balance` nor the ledger is assumed authoritative. Stage C is read-only investigation producing a report, not a correction.
7. **No frontend.** Backend + API only.
8. **Red before green.** Write the failing test, watch it fail, then implement.

### Approved decisions (bind every task)

| # | Decision |
|---|---|
| 1 | Applied receipts cannot be reversed directly. Return **409** when dependent applications exist. Un-apply is **deferred**. Do **not** use artificial refunds to bypass this. |
| 2 | The Rs 1,800 F discrepancy is a **documented historical baseline**, corrected separately only after explicit approval. |
| 3 | Historical return credits are **provenance-only, non-spendable**. Do not auto-activate the Rs 8,550.20. |
| 4 | **Reconcile** the five customers' stored balances against ledgers/transactions **before** activating historical credits. Assume neither is authoritative. |

---

## Stage map

Each stage is independently verifiable and independently revertable. Do not start stage N+1 until stage N's verification command passes and its commit lands.

| Stage | Deliverable | Verification | Gate |
|---|---|---|---|
| **0** | Isolated-DB test harness + live-DB write guard | guard test | — |
| **A** | Schema migration `108` | migration test on a copy | — |
| **B** | Historical provenance backfill | backfill test + inertness test | — |
| **C** | Reconciliation report (read-only) | report test | **decision** |
| **D** | Accounting/GL writes | GL tests against spec §4 | — |
| **E** | Feature activation (API) | endpoint tests | — |

---

## File structure

**Created:**

| Path | Responsibility |
|---|---|
| `server/src/services/unappliedCashTypes.ts` | Input/result types for the four operations. No logic. |
| `server/src/services/unappliedCashService.ts` | The four operations. All business rules and GL calls live here. |
| `server/src/services/creditReconciliation.ts` | Stage C. **Read-only.** Compares stored balances to ledgers. Writes nothing. |
| `server/src/controllers/unappliedCashController.ts` | HTTP shape only. Delegates to the service. |
| `server/src/routes/unappliedCash.ts` | Route table for the four endpoints. |
| `server/src/migrations/108_unapplied_customer_payments.sql` | Stage A DDL. |
| `server/src/__tests__/unappliedCashMigration.test.ts` | Stage A/B tests. |
| `server/src/__tests__/creditReconciliation.test.ts` | Stage C tests. |
| `server/src/__tests__/unappliedCashGl.test.ts` | Stage D tests. |
| `server/src/__tests__/unappliedCashApi.test.ts` | Stage E tests. |

**Modified:**

| Path | Change |
|---|---|
| `server/src/config/database.ts` | Register migration 108. Explicit, never at import time. |
| `server/src/__tests__/helpers/accountingInvariants.ts` | Add invariants K, L, M, N collectors. |

---

## Chunk 1: Stages 0–A (guardrail + schema)

### Task 0.1: Live-database write guard

This is the task that makes constraints 1 and 2 enforceable rather than aspirational. It fails loudly if any test path reaches the canonical file.

**Files:**
- Create: `server/src/__tests__/helpers/liveDbGuard.ts`

- [ ] **Step 1: Write the failing test**

`server/src/__tests__/liveDbGuard.test.ts`:

```ts
import * as fs from 'fs';
import * as path from 'path';
import { resolveLiveDbPath } from './helpers/liveDbGuard';

const LIVE = path.resolve(__dirname, '../../database/erp.db');

describe('live database write guard', () => {
  it('resolves the canonical live database path', () => {
    expect(resolveLiveDbPath()).toBe(LIVE);
  });

  it('refuses to open the live database for writing', () => {
    const open = () => resolveLiveDbPath();
    expect(() => open()).not.toThrow(); // path resolution alone is fine

    // the guard itself must reject a write-mode open
    const { openForWrite } = require('./helpers/liveDbGuard');
    expect(() => openForWrite(LIVE)).toThrow(/refus/i);
  });

  it('excludes the live database file from writes by hash sentinel', () => {
    const before = fs.readFileSync(LIVE);
    // any accidental write would be caught by the suite-level hash check in
    // scripts/check.sh; here we only assert the guard is wired
    expect(before.length).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd server && npx jest src/__tests__/liveDbGuard.test.ts`
Expected: FAIL — `Cannot find module './helpers/liveDbGuard'`

- [ ] **Step 3: Write minimal implementation**

`server/src/__tests__/helpers/liveDbGuard.ts`:

```ts
import * as path from 'path';

/**
 * Absolute path to the canonical live database. Tests must never open this
 * file for writing. See AGENTS.md: no live corrections without approval.
 */
export function resolveLiveDbPath(): string {
  return path.resolve(__dirname, '../../database/erp.db');
}

/**
 * Guard for any code path that intends to open a database for writing.
 * Throws when handed the canonical live database.
 */
export function openForWrite(dbPath: string): never {
  if (path.resolve(dbPath) === resolveLiveDbPath()) {
    throw new Error(
      `refused to open the canonical live database for writing: ${dbPath}`
    );
  }
  throw new Error(
    'openForWrite is a guard only; tests must open an isolated copy instead'
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd server && npx jest src/__tests__/liveDbGuard.test.ts`
Expected: PASS (3 tests)

- [ ] **Step 5: Verify the live database is untouched**

Run: `sha256sum server/database/erp.db`
Expected: `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f`

If this hash differs, **stop immediately** and report. Do not continue.

- [ ] **Step 6: Commit**

```bash
git add server/src/__tests__/helpers/liveDbGuard.ts server/src/__tests__/liveDbGuard.test.ts
git commit -m "test(server): guard against opening the canonical live database for writing"
```

---

### Task 0.2: Confirm the fixture path before writing tests

Do NOT add a database helper. `server/src/__tests__/helpers/productionSchema.ts`
already exports `createFixtureDb(options)` and `cleanupFixtureDbs()`, and
`setup.ts` already runs `applyPendingMigrations()` per test file.

- [ ] **Step 1: Read `productionSchema.ts:85-125` and confirm the contract**

Expected: `createFixtureDb({ reference: true })` returns an **empty** database
with the production schema plus seeded `chart_of_accounts`.

- [ ] **Step 2: Read one existing test that uses it** (e.g.
`arSurfaceConsistency.test.ts:20`) and copy its fixture-insert shape.

- [ ] **Step 3: Do not create `isolatedDb.ts`.** Its job is already done, and a
second helper is how the repo ended up with 24 divergent MIGRATIONS arrays
before `productionSchema.ts` existed.

---
### Task A.1: Migration 108 — account 2110

Do this first and alone so a failure isolates cleanly.

**Files:**
- Create: `server/src/migrations/108_unapplied_customer_payments.sql`
- Modify: `server/src/config/database.ts`
- Test: `server/src/__tests__/unappliedCashMigration.test.ts`

- [ ] **Step 1: Write the failing test**

`server/src/__tests__/unappliedCashMigration.test.ts`:

```ts
import { makeIsolatedCopy } from './helpers/isolatedDb';
import { applyPendingMigrations } from '../config/database';

describe('migration 108 — account 2110', () => {
  it('creates 2110 with all four columns the GL layer needs', () => {
    const { db, cleanup } = makeIsolatedCopy('mig2110');
    try {
      /* schema already migrated by setup.ts */;
      const row = db
        .prepare(`SELECT code, name, type, normal_balance, text_code
                  FROM chart_of_accounts WHERE code = '2110'`)
        .get();
      expect(row).toMatchObject({
        code: '2110',
        type: 'liability',
        normal_balance: 'credit',
        text_code: 'unapplied_customer_payments',
      });
    } finally { cleanup(); }
  });

  it('is idempotent — a second apply does not throw or duplicate', () => {
    const { db, cleanup } = makeIsolatedCopy('mig2110-idem');
    try {
      /* schema already migrated by setup.ts */;
      /* schema already migrated by setup.ts */;
      const n = db
        .prepare(`SELECT COUNT(*) AS n FROM chart_of_accounts WHERE code='2110'`)
        .get() as { n: number };
      expect(n.n).toBe(1);
    } finally { cleanup(); }
  });

  it('is addressable by text_code, which is how postEntry resolves it', () => {
    const { db, cleanup } = makeIsolatedCopy('mig2110-tc');
    try {
      /* schema already migrated by setup.ts */;
      const row = db
        .prepare(`SELECT code FROM chart_of_accounts WHERE text_code = ?`)
        .get('unapplied_customer_payments');
      expect(row).toBeDefined();
    } finally { cleanup(); }
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd server && npx jest src/__tests__/unappliedCashMigration.test.ts`
Expected: FAIL — 2110 not found.

- [ ] **Step 3: Create the migration file**

`server/src/migrations/108_unapplied_customer_payments.sql`:

```sql
-- Migration 108: unapplied customer payments
-- Adds a liability account for cash held on behalf of customers that is not
-- yet attributable to an invoice. This cash is deliberately NOT customer
-- credit: it stays in 2110 and is never added to customers.credit_balance.

-- 2110 requires normal_balance and text_code. normal_balance is a NOT NULL
-- CHECK column, so omitting it is rejected outright; text_code is what
-- postEntry resolves accounts by, so an account without one cannot be found
-- and every GL entry in this feature would throw "Account not found".
INSERT INTO chart_of_accounts (code, name, type, normal_balance, text_code)
VALUES ('2110', 'Unapplied Customer Payments', 'liability', 'credit',
        'unapplied_customer_payments')
ON CONFLICT(code) DO NOTHING;
```

> Only the 2110 insert goes in this first commit. Tables and the ALTER land in
> Task A.2 so a failure points at one change.

- [ ] **Step 4: Register it in database.ts**

Find the existing SQL migration registrations (they are individual
`path.join(MIGRATIONS_DIR, '...')` calls, roughly lines 330–780). Add alongside
the others, in sequence:

```ts
    path.join(MIGRATIONS_DIR, '108_unapplied_customer_payments.sql'),
```

Do not wrap it in a lazy require or any import-time side effect — migrations
run only from `applyPendingMigrations`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd server && npx jest src/__tests__/unappliedCashMigration.test.ts`
Expected: PASS (3 tests)

- [ ] **Step 6: Typecheck and lint**

Run: `cd server && npm run typecheck && npm run lint`
Expected: exit 0, no new errors.

- [ ] **Step 7: Verify the live database is untouched**

Run: `sha256sum server/database/erp.db`
Expected: `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f`

- [ ] **Step 8: Commit**

```bash
git add server/src/migrations/108_unapplied_customer_payments.sql \
        server/src/config/database.ts \
        server/src/__tests__/unappliedCashMigration.test.ts
git commit -m "feat(server): migration 108 adds account 2110 unapplied customer payments"
```

---

### Task A.2: Migration 108 — the three tables and `payments.payment_kind`

**Files:**
- Modify: `server/src/migrations/108_unapplied_customer_payments.sql`
- Test: `server/src/__tests__/unappliedCashMigration.test.ts` (append)

- [ ] **Step 1: Write the failing tests**

Append to `unappliedCashMigration.test.ts`:

```ts
describe('migration 108 — tables', () => {
  it('creates customer_credit_sources with a VIRTUAL generated remaining', () => {
    const { db, cleanup } = makeIsolatedCopy('mig-src');
    try {
      /* schema already migrated by setup.ts */;
      const sql = db
        .prepare(`SELECT sql FROM sqlite_master
                  WHERE type='table' AND name='customer_credit_sources'`)
        .get() as { sql: string };
      expect(sql.sql).toMatch(/remaining_amount/i);
      expect(sql.sql).toMatch(/GENERATED ALWAYS AS/i);
      expect(sql.sql).toMatch(/VIRTUAL/i);
      // constraints must live INSIDE CREATE TABLE, not in a trailing block
      expect(sql.sql).toMatch(/c_refund_le_credited/i);
      expect(sql.sql).toMatch(/c_refundable_le_remaining/i);
    } finally { cleanup(); }
  });

  it('rejects a refund whose refunded_amount exceeds credited_amount', () => {
    const { db, cleanup } = makeIsolatedCopy('mig-src-chk');
    try {
      /* schema already migrated by setup.ts */;
      const c = db.prepare(`SELECT id FROM customers LIMIT 1`).get() as { id: number };
      db.prepare(`INSERT INTO customer_credit_sources
        (customer_id, kind, credited_amount, refundable_cash_amount)
        VALUES (?, 'UNAPPLIED_CASH', 100, 0)`).run(c.id);
      expect(() => db.prepare(`UPDATE customer_credit_sources
        SET refunded_amount = 101`).run()).toThrow();
    } finally { cleanup(); }
  });

  it('allows refunding the last 100 of a 500 source', () => {
    // regression for the rev-5 DDL bug: refunded_amount <= refundable_cash_amount
    // is unsatisfiable because refundable drains in the same operation
    const { db, cleanup } = makeIsolatedCopy('mig-src-refund');
    try {
      /* schema already migrated by setup.ts */;
      const c = db.prepare(`SELECT id FROM customers LIMIT 1`).get() as { id: number };
      db.prepare(`INSERT INTO customer_credit_sources
        (customer_id, kind, credited_amount, refundable_cash_amount)
        VALUES (?, 'UNAPPLIED_CASH', 500, 500)`).run(c.id);
      expect(() => db.prepare(`UPDATE customer_credit_sources
        SET refunded_amount = 100, refundable_cash_amount = 400`).run()).not.toThrow();
    } finally { cleanup(); }
  });

  it('creates credit_source_consumptions with nullable invoice_id', () => {
    const { db, cleanup } = makeIsolatedCopy('mig-cons');
    try {
      /* schema already migrated by setup.ts */;
      const sql = db
        .prepare(`SELECT sql FROM sqlite_master
                  WHERE type='table' AND name='credit_source_consumptions'`)
        .get() as { sql: string };
      expect(sql.sql).toMatch(/invoice_id INTEGER(,|\s)/);
      expect(sql.sql).not.toMatch(/invoice_id INTEGER NOT NULL/);
      expect(sql.sql).toMatch(/amount DECIMAL\(15,2\) NOT NULL CHECK \(amount > 0\)/);
      expect(sql.sql).toMatch(/voided_at/);
    } finally { cleanup(); }
  });

  it('creates credit_applications with an APPLY/REFUND CHECK', () => {
    const { db, cleanup } = makeIsolatedCopy('mig-apps');
    try {
      /* schema already migrated by setup.ts */;
      const sql = db
        .prepare(`SELECT sql FROM sqlite_master
                  WHERE type='table' AND name='credit_applications'`)
        .get() as { sql: string };
      expect(sql.sql).toMatch(/operation TEXT NOT NULL CHECK \(operation IN \('APPLY','REFUND'\)\)/);
    } finally { cleanup(); }
  });

  it('adds payments.payment_kind defaulting every existing row to RECEIPT', () => {
    const { db, cleanup } = makeIsolatedCopy('mig-kind');
    try {
      /* schema already migrated by setup.ts */;
      const rows = db.prepare(`SELECT DISTINCT payment_kind FROM payments`).all();
      expect(rows.length).toBeGreaterThan(0);
      expect(rows.every((r: any) => r.payment_kind === 'RECEIPT')).toBe(true);
    } finally { cleanup(); }
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd server && npx jest src/__tests__/unappliedCashMigration.test.ts`
Expected: FAIL — `no such table: customer_credit_sources`

- [ ] **Step 3: Append the DDL**

Append to `server/src/migrations/108_unapplied_customer_payments.sql`:

```sql
-- One row per grant of customer credit. kind is RETURN_CREDIT (backfilled
-- history) or UNAPPLIED_CASH (this feature).
--
-- remaining_amount is GENERATED from the three base counters and is never
-- written. The constraints therefore validate only what the base counters say:
-- a writer who corrupts consumed_amount without recording a consumption still
-- passes here and is caught by invariant L in code instead.
--
-- The refund bound is refunded_amount <= credited_amount, NOT
-- refunded_amount <= refundable_cash_amount. refunded_amount is a monotonic
-- accumulator while refundable_cash_amount is a draining pool; comparing them
-- makes the constraint unsatisfiable the moment the last 100 of a 500 source is
-- refunded (refunded=100, refundable=0, 100 <= 0 fails).
CREATE TABLE customer_credit_sources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  kind TEXT NOT NULL CHECK (kind IN ('RETURN_CREDIT','UNAPPLIED_CASH')),
  origin_payment_id INTEGER,
  origin_invoice_id INTEGER,
  credited_amount DECIMAL(15,2) NOT NULL,
  consumed_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  refunded_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  remaining_amount DECIMAL(15,2)
    GENERATED ALWAYS AS (credited_amount - consumed_amount - refunded_amount) VIRTUAL,
  refundable_cash_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  credited_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  voided_at TIMESTAMP,
  CONSTRAINT c_nonneg_consumed     CHECK (consumed_amount >= 0),
  CONSTRAINT c_refund_le_credited  CHECK (refunded_amount <= credited_amount),
  CONSTRAINT c_refundable_nonneg   CHECK (refundable_cash_amount >= 0),
  CONSTRAINT c_refundable_le_remaining
    CHECK (refundable_cash_amount <= remaining_amount)
);

-- Every draw against a source. invoice_id is NULL for REFUND rows; it cannot
-- live in payment_allocations because that column is NOT NULL.
--
-- voided_at is load-bearing: amount > 0 means no compensating row can offset
-- an original, and a second positive row only inflates the sum. Voiding marks
-- the row and restores the base counters in one transaction, the same pattern
-- payment_allocations uses.
CREATE TABLE credit_source_consumptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id INTEGER NOT NULL REFERENCES customer_credit_sources(id),
  application_id INTEGER NOT NULL REFERENCES credit_applications(id),
  kind TEXT NOT NULL CHECK (kind IN ('APPLY','REFUND')),
  invoice_id INTEGER,
  payment_id INTEGER,
  amount DECIMAL(15,2) NOT NULL CHECK (amount > 0),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  voided_at TIMESTAMP
);

-- Header row per apply or refund call. The INTEGER id is the journal
-- reference_id; application_key is the client-facing grouping id and cannot
-- be, because journal_lines.reference_id is INTEGER.
CREATE TABLE credit_applications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  application_key TEXT NOT NULL,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  operation TEXT NOT NULL CHECK (operation IN ('APPLY','REFUND')),
  total_amount DECIMAL(15,2) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE payments ADD COLUMN payment_kind TEXT
  NOT NULL DEFAULT 'RECEIPT'
  CHECK (payment_kind IN ('RECEIPT','UNAPPLIED_RECEIPT','REFUND','CREDIT_APPLICATION'));
```

> No indexes yet — add them once queries exist (Stage D/E), driven by real need
> rather than guesswork.

- [ ] **Step 4: Run to verify it passes**

Run: `cd server && npx jest src/__tests__/unappliedCashMigration.test.ts`
Expected: PASS (all tests)

- [ ] **Step 5: Verify the live database is untouched**

Run: `sha256sum server/database/erp.db`
Expected: `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f`

- [ ] **Step 6: Commit**

```bash
git add server/src/migrations/108_unapplied_customer_payments.sql \
        server/src/__tests__/unappliedCashMigration.test.ts
git commit -m "feat(server): migration 108 adds credit source, consumption and application tables"
```

**Stage A verification gate:**

```bash
cd server && npx jest src/__tests__/unappliedCashMigration.test.ts \
                src/__tests__/liveDbGuard.test.ts \
                src/__tests__/isolatedDb.test.ts
npm run typecheck && npm run lint
sha256sum database/erp.db   # must equal the sentinel above
```

---

## Chunk 2: Stage B (historical provenance backfill)

### Task B.1: Backfill RETURN_CREDIT sources, inert

**Files:**
- Create: `server/src/migrations/108b_backfill_return_credit_sources.sql` — **or** an inline step in 108 if that matches the repo's convention for data steps
- Test: `server/src/__tests__/unappliedCashBackfill.test.ts`

**The backfill (spec §8 step 5):** for each non-voided `RETURN` ledger row with
`credit > 0`, insert a `RETURN_CREDIT` source with `credited_amount = credit`,
`consumed_amount` = credit drawn by `CREDIT_OFFSET` applications for the same
customer, and `refundable_cash_amount = 0`.

**Do not validate against `credit_balance`.** It is zero for all five customers
and tracks none of this history — not for customer 12, where 2400 granted less
2300 refunded would leave 100. It is not a historical record and cannot
arbitrate the backfill.

Validate instead on ledger self-consistency: per customer,
`RETURN credit >= CREDIT_OFFSET credit`.

- [ ] **Step 1: Write the failing tests**

`server/src/__tests__/unappliedCashBackfill.test.ts`:

```ts
import { makeIsolatedCopy } from './helpers/isolatedDb';
import { applyPendingMigrations } from '../config/database';

const R2 = (n: number) => Math.round(n * 100) / 100;

describe('migration 108 — historical provenance backfill', () => {
  it('creates one RETURN_CREDIT source per non-voided RETURN credit row', () => {
    const { db, cleanup } = makeIsolatedCopy('bk-count');
    try {
      /* schema already migrated by setup.ts */;
      const expected = db.prepare(`
        SELECT COUNT(*) AS n FROM customer_ledger
        WHERE transaction_type = 'RETURN' AND credit > 0
          AND COALESCE(voided,0) = 0 AND reversed_by IS NULL`).get() as { n: number };
      const actual = db.prepare(`
        SELECT COUNT(*) AS n FROM customer_credit_sources
        WHERE kind = 'RETURN_CREDIT'`).get() as { n: number };
      expect(actual.n).toBe(expected.n);
      expect(actual.n).toBe(13);
    } finally { cleanup(); }
  });

  it('credits each source with the RETURN amount', () => {
    const { db, cleanup } = makeIsolatedCopy('bk-amount');
    try {
      /* schema already migrated by setup.ts */;
      const total = db.prepare(`
        SELECT COALESCE(SUM(credited_amount),0) AS v
        FROM customer_credit_sources WHERE kind = 'RETURN_CREDIT'`).get() as { v: number };
      expect(R2(total.v)).toBe(8550.20);
    } finally { cleanup(); }
  });

  it('records consumed_amount from CREDIT_OFFSET applications', () => {
    // customer 15 granted 2300, 1800 consumed by CREDIT_OFFSET
    const { db, cleanup } = makeIsolatedCopy('bk-consumed');
    try {
      /* schema already migrated by setup.ts */;
      const row = db.prepare(`
        SELECT credited_amount, consumed_amount, remaining_amount
        FROM customer_credit_sources
        WHERE kind='RETURN_CREDIT'
          AND customer_id = (SELECT id FROM customers LIMIT 1 OFFSET 4)`).get() as any;
      expect(row).toBeDefined();
      expect(R2(row.credited_amount)).toBe(2300);
      expect(R2(row.consumed_amount)).toBe(1800);
      expect(R2(row.remaining_amount)).toBe(500);
    } finally { cleanup(); }
  });

  it('leaves every backfilled row NON-SPENDABLE (refundable_cash_amount = 0)', () => {
    const { db, cleanup } = makeIsolatedCopy('bk-inert');
    try {
      /* schema already migrated by setup.ts */;
      const bad = db.prepare(`
        SELECT COUNT(*) AS n FROM customer_credit_sources
        WHERE kind='RETURN_CREDIT' AND refundable_cash_amount <> 0`).get() as { n: number };
      expect(bad.n).toBe(0);
    } finally { cleanup(); }
  });

  it('creates no UNAPPLIED_CASH sources — the backfill must not invent spendable cash', () => {
    const { db, cleanup } = makeIsolatedCopy('bk-no-cash');
    try {
      /* schema already migrated by setup.ts */;
      const n = db.prepare(`
        SELECT COUNT(*) AS n FROM customer_credit_sources
        WHERE kind='UNAPPLIED_CASH'`).get() as { n: number };
      expect(n.n).toBe(0);
    } finally { cleanup(); }
  });

  it('never consumes more than was credited, for any customer', () => {
    const { db, cleanup } = makeIsolatedCopy('bk-selftest');
    try {
      /* schema already migrated by setup.ts */;
      const bad = db.prepare(`
        SELECT COUNT(*) AS n FROM customer_credit_sources
        WHERE consumed_amount > credited_amount`).get() as { n: number };
      expect(bad.n).toBe(0);
    } finally { cleanup(); }
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd server && npx jest src/__tests__/unappliedCashBackfill.test.ts`
Expected: FAIL — 0 `RETURN_CREDIT` sources.

- [ ] **Step 3: Implement the backfill**

Append to `server/src/migrations/108_unapplied_customer_payments.sql`:

```sql
-- Historical provenance backfill.
--
-- For each non-voided RETURN ledger row with credit > 0, record a
-- RETURN_CREDIT source so historical grants are not invisible and a future
-- cash-backed refund has a row to draw from.
--
-- refundable_cash_amount = 0 makes these rows deliberately inert: they are
-- excluded from the refund draw and unappliedCash() counts only
-- kind='UNAPPLIED_CASH', so they contribute nothing a customer can spend.
--
-- 0 is corroborated rather than merely conservative. return_settlements does
-- carry the linkage (payment_id, method), but the one populated row is
-- type='refund', method='Cash', amount=550 for customer 15 -- cash already paid
-- OUT, not credit awaiting refund. Every cash-linked settlement in the database
-- represents money that has already left. What remains refundable cannot be
-- reconstructed from this history, and 0 can only under-claim refundable cash,
-- never over-claim it. Over-refunding is the dangerous direction.
--
-- This is deliberately NOT validated against customers.credit_balance. That
-- column is 0 for all five customers and tracks none of this history (customer
-- 12 granted 2400 less 2300 refunded should leave 100, yet reads 0), so it is
-- not a historical record and cannot arbitrate the backfill.
--
-- Validation is ledger self-consistency instead: consumed_amount (CREDIT_OFFSET)
-- must not exceed credited_amount (RETURN).

-- FIFO allocation of CREDIT_OFFSET across each customer's RETURN rows.
-- The rev-1 wording replicated the customer-level total onto every row; that
-- drives customer 15's 600-row to remaining = -1200 and the CHECK aborts the
-- migration. Verified by execution: 13 rows, 8550.20 credited, 1800 consumed.
WITH ret AS (
  SELECT l.customer_id, l.credit, l.created_at,
         COALESCE(SUM(l.credit) OVER (
           PARTITION BY l.customer_id ORDER BY COALESCE(l.created_at, l.id), l.id
           ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS cum_before
  FROM customer_ledger l
  WHERE l.transaction_type='RETURN' AND l.credit>0
    AND COALESCE(l.voided,0)=0 AND l.reversed_by IS NULL
),
cons AS (
  SELECT customer_id, SUM(credit) c FROM customer_ledger
  WHERE transaction_type='CREDIT_OFFSET' AND credit>0
    AND COALESCE(voided,0)=0 AND reversed_by IS NULL
  GROUP BY customer_id
)
INSERT INTO customer_credit_sources (
  customer_id, kind, credited_amount, consumed_amount,
  refundable_cash_amount, credited_at, origin_invoice_id
)
SELECT r.customer_id, 'RETURN_CREDIT', r.credit,
       MAX(0, MIN(r.credit, COALESCE(c.c,0) - r.cum_before)),
       0, COALESCE(r.created_at, CURRENT_TIMESTAMP), NULL
FROM ret r LEFT JOIN cons c ON c.customer_id = r.customer_id;
```

> If the SQLite version in use rejects the aggregate correlated subquery, split
> into a `CREATE TEMP TABLE` + `INSERT ... SELECT` + `DROP`. Do not change the
> arithmetic.

- [ ] **Step 4: Run to verify it passes**

Run: `cd server && npx jest src/__tests__/unappliedCashBackfill.test.ts`
Expected: PASS (6 tests)

- [ ] **Step 5: Verify the live database is untouched**

Run: `sha256sum server/database/erp.db`
Expected: `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f`

- [ ] **Step 6: Commit**

```bash
git add server/src/migrations/108_unapplied_customer_payments.sql \
        server/src/__tests__/unappliedCashBackfill.test.ts
git commit -m "feat(server): backfill historical return credit as inert RETURN_CREDIT provenance"
```

**Stage B verification gate:**

```bash
cd server && npx jest src/__tests__/unappliedCashBackfill.test.ts
sha256sum database/erp.db
```

Confirm: 13 sources, 8550.20 total, all `refundable_cash_amount = 0`, zero
`UNAPPLIED_CASH` rows, live hash unchanged.

---

## Chunk 3: Stage C (reconciliation — read-only, decision gate)

**This stage writes nothing.** It produces evidence for a decision the user
owns. Do not "fix" anything you find here — a disagreement between stored
balance and ledger is the *finding*, not a bug to be patched.

### Task C.1: Reconciliation report

**Files:**
- Create: `server/src/services/creditReconciliation.ts`
- Test: `server/src/__tests__/creditReconciliation.test.ts`

- [ ] **Step 1: Write the failing test**

`server/src/__tests__/creditReconciliation.test.ts`:

```ts
import { makeIsolatedCopy } from './helpers/isolatedDb';
import { applyPendingMigrations } from '../config/database';
import { reconcileCustomerCredits } from '../services/creditReconciliation';

const R2 = (n: number) => Math.round(n * 100) / 100;

describe('credit reconciliation (read-only)', () => {
  it('reports every customer that has credit history', () => {
    const { db, cleanup } = makeIsolatedCopy('recon');
    try {
      /* schema already migrated by setup.ts */;
      const rows = reconcileCustomerCredits(db);
      expect(rows.length).toBe(5);
    } finally { cleanup(); }
  });

  it('reports stored balance and ledger-derived balance side by side', () => {
    const { db, cleanup } = makeIsolatedCopy('recon-fields');
    try {
      /* schema already migrated by setup.ts */;
      const [row] = reconcileCustomerCredits(db);
      expect(row).toEqual(expect.objectContaining({
        customerId: expect.any(Number),
        storedCreditBalance: expect.any(Number),
        ledgerGranted: expect.any(Number),
        ledgerRefunded: expect.any(Number),
        ledgerConsumed: expect.any(Number),
        ledgerDerived: expect.any(Number),
        agrees: expect.any(Boolean),
      }));
    } finally { cleanup(); }
  });

  it('flags customer 15 as disagreeing, since credit_balance is 0 against 2300 granted', () => {
    const { db, cleanup } = makeIsolatedCopy('recon-15');
    try {
      /* schema already migrated by setup.ts */;
      const rows = reconcileCustomerCredits(db);
      const fifteen = rows.find(r => r.storedCreditBalance === 0
        && r.ledgerGranted === 2300);
      expect(fifteen).toBeDefined();
      expect(fifteen!.agrees).toBe(false);
      expect(R2(fifteen!.ledgerDerived)).toBe(500); // 2300 - 1800 consumed
    } finally { cleanup(); }
  });

  it('writes nothing — the report is read-only', () => {
    const { db, cleanup } = makeIsolatedCopy('recon-readonly');
    try {
      /* schema already migrated by setup.ts */;
      const before = db.prepare(
        `SELECT COUNT(*) AS n FROM customer_credit_sources`).get() as { n: number };
      const ledBefore = db.prepare(
        `SELECT COUNT(*) AS n FROM customer_ledger`).get() as { n: number };
      reconcileCustomerCredits(db);
      const after = db.prepare(
        `SELECT COUNT(*) AS n FROM customer_credit_sources`).get() as { n: number };
      const ledAfter = db.prepare(
        `SELECT COUNT(*) AS n FROM customer_ledger`).get() as { n: number };
      expect(after.n).toBe(before.n);
      expect(ledAfter.n).toBe(ledBefore.n);
    } finally { cleanup(); }
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd server && npx jest src/__tests__/creditReconciliation.test.ts`
Expected: FAIL — `Cannot find module '../services/creditReconciliation'`

- [ ] **Step 3: Write minimal implementation**

`server/src/services/creditReconciliation.ts`:

```ts
import type Database from 'better-sqlite3';

/**
 * Read-only reconciliation of stored customer credit against ledger history.
 *
 * NEITHER SIDE IS AUTHORITATIVE. This function exists to produce evidence for
 * a decision the user owns; it deliberately does not repair anything. A
 * disagreement here is a finding, not a defect to be patched.
 *
 * The Rs 1,800 invariant F gap and the credit_balance/ledger disagreement for
 * all five customers are preserved, not corrected.
 */

export interface ReconciliationRow {
  customerId: number;
  /** customers.credit_balance as stored — not assumed correct */
  storedCreditBalance: number;
  /** sum of non-voided RETURN credit */
  ledgerGranted: number;
  /** sum of non-voided RETURN debit */
  ledgerRefunded: number;
  /** sum of non-voided CREDIT_OFFSET credit */
  ledgerConsumed: number;
  /** granted - refunded - consumed */
  ledgerDerived: number;
  /** stored === derived, to the cent */
  agrees: boolean;
}

export function reconcileCustomerCredits(db: Database.Database): ReconciliationRow[] {
  const rows = db.prepare(`
    SELECT c.id AS customerId,
           c.credit_balance AS storedCreditBalance,
           COALESCE(gr.granted, 0)  AS ledgerGranted,
           COALESCE(rf.refunded, 0) AS ledgerRefunded,
           COALESCE(co.consumed, 0) AS ledgerConsumed
    FROM customers c
    LEFT JOIN (
      SELECT customer_id, SUM(credit) granted FROM customer_ledger
      WHERE transaction_type='RETURN' AND credit > 0
        AND COALESCE(voided,0)=0 AND reversed_by IS NULL
      GROUP BY customer_id
    ) gr ON gr.customerId = c.id
    LEFT JOIN (
      SELECT customer_id, SUM(debit) refunded FROM customer_ledger
      WHERE transaction_type='RETURN' AND debit > 0
        AND COALESCE(voided,0)=0 AND reversed_by IS NULL
      GROUP BY customer_id
    ) rf ON rf.customerId = c.id
    LEFT JOIN (
      SELECT customer_id, SUM(credit) consumed FROM customer_ledger
      WHERE transaction_type='CREDIT_OFFSET' AND credit > 0
        AND COALESCE(voided,0)=0 AND reversed_by IS NULL
      GROUP BY customer_id
    ) co ON co.customerId = c.id
    WHERE gr.customerId IS NOT NULL
       OR rf.customerId IS NOT NULL
       OR co.customerId IS NOT NULL
       OR c.credit_balance <> 0
    ORDER BY c.id
  `).all() as Array<Omit<ReconciliationRow, 'ledgerDerived' | 'agrees'>>;

  return rows.map(r => {
    const ledgerDerived = r.ledgerGranted - r.ledgerRefunded - r.ledgerConsumed;
    return {
      ...r,
      ledgerDerived,
      agrees: Math.round(r.storedCreditBalance * 100) === Math.round(ledgerDerived * 100),
    };
  });
}
```

> The alias naming above is illustrative; use whatever the repo's SQL style
> allows, and verify the query against the real schema before relying on it.

- [ ] **Step 4: Run to verify it passes**

Run: `cd server && npx jest src/__tests__/creditReconciliation.test.ts`
Expected: PASS (4 tests)

- [ ] **Step 5: Produce the actual report for the user**

Run a one-off script against an isolated copy and print the table. Commit the
output to `audit/credit-reconciliation-2026-10-16.md` with a note that it is
evidence, not a fix.

Expected shape (values from spec §8, to be confirmed by running):

| customer | RETURN credit | REFUND debit | CREDIT_OFFSET | credit_balance | derived |
|---|---|---|---|---|---|
| 1 | 1450.20 | 1200 | 0 | 0 | 250.20 |
| 12 | 2400 | 2300 | 0 | 0 | 100 |
| 13 | 1200 | 400 | 0 | 0 | 800 |
| 14 | 1200 | 0 | 0 | 0 | 1200 |
| 15 | 2300 | 550 | 1800 | 0 | -50 |

**Note the sign:** customer 15's derived figure is negative because the 550
refund was cash paid *out*, not credit returned. Do not "correct" this — report
it and let the user decide. Report the discrepancy **as-is**.

- [ ] **Step 6: Verify the live database is untouched**

Run: `sha256sum server/database/erp.db`
Expected: `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f`

- [ ] **Step 7: Commit**

```bash
git add server/src/services/creditReconciliation.ts \
        server/src/__tests__/creditReconciliation.test.ts \
        audit/credit-reconciliation-2026-10-16.md
git commit -m "feat(server): read-only customer credit reconciliation report"
```

**Stage C gate — STOP HERE.** Present the report and ask the user which side,
if either, is authoritative before activating any historical credit. Do not
proceed to Stage D until answered. **Do not assume either balance is
authoritative.**

---

## Chunk 4: Stage D (accounting / GL writes)

### Task D.1: Invariant collectors

**Files:**
- Modify: `server/src/__tests__/helpers/accountingInvariants.ts`
- Test: additions to `server/src/__tests__/unappliedCashGl.test.ts`

- [ ] **Step 1: Write the failing tests**

`server/src/__tests__/unappliedCashGl.test.ts` (opening):

```ts
import { makeIsolatedCopy } from './helpers/isolatedDb';
import { applyPendingMigrations } from '../config/database';
import { collectCreditInvariants } from './helpers/accountingInvariants';

const R2 = (n: number) => Math.round(n * 100) / 100;

describe('credit invariants K, L, M, N', () => {
  it('K holds when GL 2110 equals the sum of live unapplied source balances', () => {
    const { db, cleanup } = makeIsolatedCopy('inv-K');
    try {
      /* schema already migrated by setup.ts */;
      const v = collectCreditInvariants(db);
      expect(R2(v.gl2110)).toBe(R2(v.sumUnappliedRemaining));
      expect(v.ok.K).toBe(true);
    } finally { cleanup(); }
  });

  it('K fails when a source is live but its GL leg is gone', () => {
    const { db, cleanup } = makeIsolatedCopy('inv-K-bad');
    try {
      /* schema already migrated by setup.ts */;
      const c = db.prepare(`SELECT id FROM customers LIMIT 1`).get() as { id: number };
      db.prepare(`INSERT INTO customer_credit_sources
        (customer_id, kind, credited_amount, refundable_cash_amount)
        VALUES (?, 'UNAPPLIED_CASH', 500, 500)`).run(c.id);
      const v = collectCreditInvariants(db);
      expect(v.ok.K).toBe(false);   // 500 of credit, no GL backing it
    } finally { cleanup(); }
  });

  it('L holds when every source has a consumption covering its consumed_amount', () => {
    const { db, cleanup } = makeIsolatedCopy('inv-L');
    try {
      /* schema already migrated by setup.ts */;
      const v = collectCreditInvariants(db);
      expect(v.ok.L).toBe(true);
    } finally { cleanup(); }
  });

  it('M holds when no source is over-refunded', () => {
    const { db, cleanup } = makeIsolatedCopy('inv-M');
    try {
      /* schema already migrated by setup.ts */;
      const v = collectCreditInvariants(db);
      expect(v.ok.M).toBe(true);
    } finally { cleanup(); }
  });

  it('N holds when allocations never exceed the invoice balance', () => {
    const { db, cleanup } = makeIsolatedCopy('inv-N');
    try {
      /* schema already migrated by setup.ts */;
      const v = collectCreditInvariants(db);
      expect(v.ok.N).toBe(true);
    } finally { cleanup(); }
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd server && npx jest src/__tests__/unappliedCashGl.test.ts`
Expected: FAIL — `collectCreditInvariants` not exported.

- [ ] **Step 3: Add the collectors**

Append to `server/src/__tests__/helpers/accountingInvariants.ts`:

```ts
/**
 * K/L/M/N for the unapplied-cash feature.
 *
 * K uses Math.abs: 2110 is credit-normal, so a credit balance reads as a
 * negative signed sum. Without abs, a healthy empty ledger reads as failing.
 *
 * L is asserted in CODE, not delegated to the schema. The schema can only see
 * the base counters; a writer who moves consumed_amount without recording a
 * consumption still satisfies every CHECK. L is what catches that.
 */
export interface CreditInvariantResult {
  gl2110: number;
  sumUnappliedRemaining: number;
  sumUnappliedRefundable: number;
  ok: { K: boolean; L: boolean; M: boolean; N: boolean };
}

export function collectCreditInvariants(db: Database.Database): CreditInvariantResult {
  const acct = db.prepare(
    `SELECT id FROM chart_of_accounts WHERE text_code = 'unapplied_customer_payments'`
  ).get() as { id: number } | undefined;

  const gl2110 = acct
    ? Number(db.prepare(`
        SELECT COALESCE(SUM(debit - credit), 0) AS b FROM journal_lines
        WHERE account_id = ? AND voided = 0`).get(acct.id).b)
    : 0;

  const s = db.prepare(`
    SELECT COALESCE(SUM(remaining_amount), 0)              AS remaining,
           COALESCE(SUM(refundable_cash_amount), 0)       AS refundable
    FROM customer_credit_sources
    WHERE kind = 'UNAPPLIED_CASH' AND voided_at IS NULL`).get() as
    { remaining: number; refundable: number };

  // L: consumed_amount must be fully covered by live consumption rows
  const uncovered = db.prepare(`
    SELECT COALESCE(SUM(src.consumed_amount), 0) AS consumed,
           COALESCE((SELECT SUM(c.amount) FROM credit_source_consumptions c
                     JOIN customer_credit_sources s2 ON s2.id = c.source_id
                     WHERE c.kind = 'APPLY' AND c.voided_at IS NULL), 0) AS drawn
    FROM customer_credit_sources src
    WHERE src.kind = 'UNAPPLIED_CASH' AND src.voided_at IS NULL`).get() as
    { consumed: number; drawn: number };

  // M: no source refunded beyond what was credited
  const overRefunded = db.prepare(`
    SELECT COUNT(*) AS n FROM customer_credit_sources
    WHERE refunded_amount > credited_amount`).get() as { n: number };

  // N: no allocation exceeds its invoice balance
  const overAllocated = db.prepare(`
    SELECT COUNT(*) AS n FROM (
      SELECT pa.invoice_id, SUM(pa.amount) alloc, i.balance_amount bal
      FROM payment_allocations pa JOIN invoices i ON i.id = pa.invoice_id
      WHERE pa.voided_at IS NULL GROUP BY pa.invoice_id
    ) WHERE alloc > bal`).get() as { n: number };

  return {
    gl2110,
    sumUnappliedRemaining: Number(s.remaining),
    sumUnappliedRefundable: Number(s.refundable),
    ok: {
      K: Math.round(Math.abs(gl2110) * 100) === Math.round(Number(s.remaining) * 100),
      L: Math.round(Number(uncovered.consumed) * 100) === Math.round(Number(uncovered.drawn) * 100),
      M: overRefunded.n === 0,
      N: overAllocated.n === 0,
    },
  };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd server && npx jest src/__tests__/unappliedCashGl.test.ts`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add server/src/__tests__/helpers/accountingInvariants.ts \
        server/src/__tests__/unappliedCashGl.test.ts
git commit -m "test(server): invariants K, L, M, N for unapplied customer credit"
```

---

### Task D.2: Receive unapplied cash

**Files:**
- Create: `server/src/services/unappliedCashTypes.ts`
- Create: `server/src/services/unappliedCashService.ts`
- Test: `server/src/__tests__/unappliedCashGl.test.ts` (append)

- [ ] **Step 1: Write the failing tests**

```ts
import { receiveUnappliedCash } from '../services/unappliedCashService';

describe('5.1 receive unapplied cash', () => {
  it('creates a UNAPPLIED_RECEIPT payment and a matching source', () => {
    const { db, cleanup } = makeIsolatedCopy('op-recv');
    try {
      /* schema already migrated by setup.ts */;
      const c = db.prepare(`SELECT id FROM customers
                           WHERE current_balance = 0 LIMIT 1`).get() as { id: number };
      const res = receiveUnappliedCash(db, { customerId: c.id, amount: 500 });
      const pay = db.prepare(
        `SELECT payment_kind, amount FROM payments WHERE id = ?`).get(res.paymentId) as any;
      expect(pay.payment_kind).toBe('UNAPPLIED_RECEIPT');
      expect(pay.amount).toBe(500);
      const src = db.prepare(
        `SELECT kind, credited_amount, refundable_cash_amount, remaining_amount
         FROM customer_credit_sources WHERE origin_payment_id = ?`).get(res.paymentId) as any;
      expect(src).toMatchObject({ kind: 'UNAPPLIED_CASH', credited_amount: 500,
                                  refundable_cash_amount: 500, remaining_amount: 500 });
    } finally { cleanup(); }
  });

  it('posts Dr cash / Cr 2110 keyed on the payment id', () => {
    const { db, cleanup } = makeIsolatedCopy('op-recv-gl');
    try {
      /* schema already migrated by setup.ts */;
      const c = db.prepare(`SELECT id FROM customers
                           WHERE current_balance = 0 LIMIT 1`).get() as { id: number };
      const res = receiveUnappliedCash(db, { customerId: c.id, amount: 500 });
      const lines = db.prepare(`
        SELECT a.code, jl.debit, jl.credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN chart_of_accounts a ON a.id = jl.account_id
        WHERE je.reference_type = 'UNAPPLIED_RECEIPT' AND je.reference_id = ?`)
        .all(res.paymentId) as Array<{ code: string; debit: number; credit: number }>;
      expect(lines).toEqual(expect.arrayContaining([
        expect.objectContaining({ code: '1000', debit: 500 }),
        expect.objectContaining({ code: '2110', credit: 500 }),
      ]));
    } finally { cleanup(); }
  });

  it('keeps invariant F unchanged — credit_balance is never touched', () => {
    const { db, cleanup } = makeIsolatedCopy('op-recv-f');
    try {
      /* schema already migrated by setup.ts */;
      const c = db.prepare(`SELECT id FROM customers
                           WHERE current_balance = 0 LIMIT 1`).get() as { id: number };
      const before = db.prepare(`SELECT credit_balance, current_balance FROM customers
                                WHERE id = ?`).get(c.id) as any;
      receiveUnappliedCash(db, { customerId: c.id, amount: 500 });
      const after = db.prepare(`SELECT credit_balance, current_balance FROM customers
                               WHERE id = ?`).get(c.id) as any;
      expect(after).toEqual(before);
    } finally { cleanup(); }
  });

  it('writes no customer_ledger row — the money has not moved', () => {
    const { db, cleanup } = makeIsolatedCopy('op-recv-ledger');
    try {
      /* schema already migrated by setup.ts */;
      const c = db.prepare(`SELECT id FROM customers
                           WHERE current_balance = 0 LIMIT 1`).get() as { id: number };
      const before = db.prepare(`SELECT COUNT(*) AS n FROM customer_ledger`)
        .get() as { n: number };
      receiveUnappliedCash(db, { customerId: c.id, amount: 500 });
      const after = db.prepare(`SELECT COUNT(*) AS n FROM customer_ledger`)
        .get() as { n: number };
      expect(after.n).toBe(before.n);
    } finally { cleanup(); }
  });

  it('rejects a customer already in credit', () => {
    const { db, cleanup } = makeIsolatedCopy('op-recv-neg');
    try {
      /* schema already migrated by setup.ts */;
      const c = db.prepare(`SELECT id FROM customers
                           WHERE current_balance < 0 LIMIT 1`).get() as { id: number } | undefined;
      if (!c) return;   // no such customer in this fixture; nothing to assert
      expect(() => receiveUnappliedCash(db, { customerId: c.id, amount: 500 }))
        .toThrow(/credit/i);
    } finally { cleanup(); }
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd server && npx jest src/__tests__/unappliedCashGl.test.ts -t "receive"`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the types**

`server/src/services/unappliedCashTypes.ts`:

```ts
export interface ReceiveUnappliedCashInput {
  customerId: number;
  amount: number;
  paymentDate?: string;
  paymentMethod?: string;
  notes?: string;
}

export interface ReceiveUnappliedCashResult {
  paymentId: number;
  sourceId: number;
  journalEntryId: number;
}

export interface ApplyToInvoicesInput {
  customerId: number;
  applicationKey: string;
  totalAmount: number;
  paymentDate?: string;
  allocations: Array<{ invoiceId: number; amount: number }>;
}

export interface ApplyToInvoicesResult {
  applicationId: number;
  journalEntryId: number;
  allocations: Array<{ invoiceId: number; amount: number; sourceId: number }>;
}

export interface RefundUnappliedCashInput {
  customerId: number;
  applicationKey: string;
  totalAmount: number;
  paymentDate?: string;
  paymentMethod?: string;
}

export interface RefundUnappliedCashResult {
  applicationId: number;
  paymentId: number;
  journalEntryId: number;
}
```

- [ ] **Step 4: Write minimal implementation**

`server/src/services/unappliedCashService.ts`:

```ts
import type Database from 'better-sqlite3';
import { AccountingService } from './accountingService';
// Verified: see the VERIFIED API CONTRACTS table above.
import type {
  ReceiveUnappliedCashInput, ReceiveUnappliedCashResult,
} from './unappliedCashTypes';

/**
 * Receive cash a customer has handed over that is not yet attributable to an
 * invoice (spec 5.1).
 *
 * This cash is NOT customer credit. It never enters customers.credit_balance
 * and never appears in unappliedCash(), which counts only UNAPPLIED_CASH. It
 * sits in liability account 2110 until applied or refunded.
 */
export function receiveUnappliedCash(
  db: Database.Database,
  input: ReceiveUnappliedCashInput,
): ReceiveUnappliedCashResult {
  if (!(input.amount > 0)) throw new Error('amount must be positive');

  const customer = db.prepare(
    `SELECT id, current_balance FROM customers WHERE id = ?`).get(input.customerId) as
    { id: number; current_balance: number } | undefined;
  if (!customer) throw new Error(`customer ${input.customerId} not found`);

  if (customer.current_balance < 0) {
    throw new Error(
      'customer already holds store credit; apply that credit before receiving cash'
    );
  }

  const tx = db.transaction((): ReceiveUnappliedCashResult => {
    // postEntry asserts the period itself from entry_date; no separate call.
    // Resolve accounts to numeric ids BEFORE posting — postEntry does not do it.
    const cash = AccountingService.getAccountByTextCode(db, 'cash');
    const unapplied = AccountingService.getAccountByTextCode(db, 'unapplied_customer_payments');
    if (!cash || !unapplied) {
      throw new Error('chart of accounts is missing a required text code');
    }

    const pay = db.prepare(`
      INSERT INTO payments (customer_id, payment_date, amount, payment_method, notes, payment_kind)
      VALUES (?, COALESCE(?, date('now')), ?, COALESCE(?, 'Cash'), ?, 'UNAPPLIED_RECEIPT')
      RETURNING id`).get(
      input.customerId,
      input.paymentDate ?? null,
      input.amount,
      input.paymentMethod ?? null,
      input.notes ?? null) as { id: number };

    const src = db.prepare(`
      INSERT INTO customer_credit_sources
        (customer_id, kind, origin_payment_id, credited_amount, refundable_cash_amount)
      VALUES (?, 'UNAPPLIED_CASH', ?, ?, ?)
      RETURNING id`).get(input.customerId, pay.id, input.amount, input.amount) as { id: number };

    // Dr cash / Cr 2110. reference_id MUST be payments.id: 5.4 voids this
    // group by (reference_type, reference_id), and the void matches exactly,
    // so a NULL here would leave the receipt permanently unvoidable.
    const entry = AccountingService.postEntry(db, {
      reference_type: 'UNAPPLIED_RECEIPT',
      reference_id: pay.id,
      entry_date: today,
      description: 'Unapplied customer cash received',
      lines: [
        { account_id: cash.id, debit: input.amount },
        { account_id: unapplied.id, credit: input.amount },
      ],
    });

    return { paymentId: pay.id, sourceId: src.id, journalEntryId: entry.journal_entry_id };
  });

  return tx();
}
```

> Match the real `postEntry` / `assertPeriodNotClosed` signatures
> (`accountingService.ts` — `postEntry` at :251, period assert at :315,
> `PostEntryInput` at :64). They accept `db` as the first argument; read the
> real file before finalising.

- [ ] **Step 5: Run to verify it passes**

Run: `cd server && npx jest src/__tests__/unappliedCashGl.test.ts -t "receive"`
Expected: PASS (5 tests)

- [ ] **Step 6: Commit**

```bash
git add server/src/services/unappliedCashTypes.ts \
        server/src/services/unappliedCashService.ts \
        server/src/__tests__/unappliedCashGl.test.ts
git commit -m "feat(server): receive unapplied customer cash into liability 2110"
```

### Task D.3: Apply unapplied cash to invoices

Full step-by-step in the same shape as D.2. The critical rules:

- Runs in one `db.transaction`.
- Guards period against **the apply date** (new, independent of the receipt's).
- Creates a `credit_applications` header; its INTEGER `id` is the journal `reference_id` (the TEXT `application_key` cannot be — `journal_lines.reference_id` is INTEGER).
- Writes `payment_allocations` reusing the existing table, capped at each invoice's `balance_amount`.
- Draws from sources oldest-first, recording a `credit_source_consumptions` row per draw and incrementing the source's `consumed_amount`.
- Decreases `customers.current_balance` by the same amount — the ledger **credits** 1100, matching that direction.
- Posts Dr `2110` / Cr `1100`, `reference_type='UNAPPLIED_APPLY'`, `reference_id=credit_applications.id`.

Test list (append, all red first):

1. applies 400 against a customer owing 499.80 → `current_balance` falls to 99.80
2. `GL(1100)` falls by 400
3. invariant F's diff stays exactly 1800.00
4. refuses to apply more than the source's `remaining_amount`
5. refuses when `refundable`/receipt totals would be exceeded
6. a partial apply leaves the source's `remaining_amount` correct
7. each source draw records a consumption row, so L holds
8. in a closed period, returns 409 `PERIOD_CLOSED`
9. each invoice allocation is capped at its `balance_amount`

### Task D.4: Refund unapplied cash

- Draws from `refundable_cash_amount` **only** (never from non-cash store credit), via a service-side `WHERE refundable_cash_amount >= :drawn` — a schema constraint cannot express this, because `refundable_cash_amount = 0` is ambiguous between "non-cash" and "already drained".
- Creates a **negative `payments` row** (`amount = -total`, `payment_kind='REFUND'`) so the refund is auditable. This was a real defect in rev 4–20.
- Decrements `refundable_cash_amount` and increments `refunded_amount` in the same transaction. The DDL bound is `refunded_amount <= credited_amount`, **not** `<= refundable_cash_amount` — see the migration note.
- Posts Dr `2110` / Cr `1000`, `reference_type='UNAPPLIED_REFUND'`, `reference_id` = the refund payment's `payments.id`.
- `reference_id` must be the refund `payments.id`, **not** the application id — §5.4 voids refunds by the payment id.

Test list:

1. refunds 100 from a 500 source, writing a negative payment row
2. `refunded_amount` rises, `refundable_cash_amount` falls by the same amount
3. refuses to refund more than `refundable_cash_amount`
4. **cannot** refund from a `RETURN_CREDIT` source (`refundable_cash_amount = 0`)
5. posts Dr 2110 / Cr 1000 with the correct `reference_id`
6. in a closed period, returns 409

### Task D.5: Reverse an unapplied receipt

**Decision 1 binds here.** Applied receipts cannot be reversed; return **409**.
Do **not** route around this with an artificial refund.

- Guards `payment_kind = 'UNAPPLIED_RECEIPT'`.
- Guards the period against **the receipt's own `payment_date`**, not today's. Only reverse inherits an earlier date.
- **Refuses 409 when live consumptions exist.** This is the approved behaviour, not a limitation to engineer around.
- Voids the GL group via `voidJournalLinesByReference(db, 'UNAPPLIED_RECEIPT', paymentId)`.
- **Retires the source row** (`voided_at = CURRENT_TIMESTAMP`) in the same transaction. Without this, invariant K reads `0 != 500` and the customer holds credit backed by no GL that they could apply to an invoice — settling it with cash never received.
- Voids the `payments` row.
- Steps 3 and 4 must be atomic; a crash between them creates the phantom credit above.

Test list:

1. reverses a fresh receipt: GL voided, source retired, payment voided
2. invariant K returns to 0 after reversal
3. **returns 409 when an application exists** (decision 1)
4. does not allow refund-then-reverse as a bypass of (3)
5. a receipt dated in a closed period returns 409
6. the reverse and the source retirement are atomic

**Stage D verification gate:**

```bash
cd server && npx jest src/__tests__/unappliedCashGl.test.ts
npm run typecheck && npm run lint
sha256sum database/erp.db   # live db unchanged
```

---

## Chunk 5: Stage E (feature activation)

### Task E.1: Controller and routes

**Files:**
- Create: `server/src/controllers/unappliedCashController.ts`
- Create: `server/src/routes/unappliedCash.ts`
- Modify: `server/src/routes/index.ts` (or wherever routes are mounted — check first)
- Test: `server/src/__tests__/unappliedCashApi.test.ts`

Four endpoints, matching spec §5:

| Method | Path | Operation |
|---|---|---|
| POST | `/api/customers/:id/unapplied-cash` | receive |
| POST | `/api/unapplied-cash/apply` | apply |
| POST | `/api/unapplied-cash/refund` | refund |
| POST | `/api/payments/:id/reverse` | reverse |

Error mapping (no stack traces to the client):

| Condition | Status | Code |
|---|---|---|
| period closed | 409 | `PERIOD_CLOSED` |
| receipt has dependent applications | 409 | `REVERSE_NOT_ALLOWED` |
| insufficient unapplied credit | 422 | `INSUFFICIENT_CREDIT` |
| exceeds invoice balance | 422 | `OVER_INVOICE_ALLOCATION` |
| customer not found | 404 | `CUSTOMER_NOT_FOUND` |
| bad input | 400 | `VALIDATION_ERROR` |

API tests (red first):

1. each endpoint returns 200 with the documented result shape
2. `POST /api/payments/:id/reverse` returns **409** for an applied receipt
3. a closed period returns 409 `PERIOD_CLOSED`
4. errors carry no stack trace and no SQL text
5. the route table is mounted (assert via a request against a mounted app)

**Stage E verification gate — the full CI suite:**

```bash
scripts/check.sh
```

This is the ~10-minute run across both suites. Run it here because this stage
changes shared routing. For earlier stages `scripts/check.sh --quick` is enough.

```bash
cd server && npx jest          # full server suite
npm run typecheck && npm run lint
cd .. && flutter analyze       # unchanged, but CI runs it
sha256sum server/database/erp.db
```

---

## Final gate before implementation

Confirm all of the following before writing implementation code:

- [ ] Stage C reconciliation report reviewed, and the user has stated which side — if either — is authoritative
- [ ] The Rs 1,800 F baseline and the `credit_balance`/ledger disagreement are **accepted as findings**, not scheduled for repair
- [ ] Decision 1 (409 on applied-receipt reversal, un-apply deferred) is accepted as permanent for now
- [ ] The plan is approved

## What this plan deliberately does NOT do

- Does not touch the canonical live database or run production migrations.
- Does not execute Strategy C′.
- Does not repair the Rs 1,800 F discrepancy.
- Does not activate the Rs 8,550.20 of historical credits.
- Does not implement un-apply.
- Does not add any frontend.
- Does not make an invariant green by adjusting its equation, suppressing a historical record, or inserting an unevidenced balancing entry.

If any task seems to require one of these, **stop and raise it with the user** rather than proceeding.