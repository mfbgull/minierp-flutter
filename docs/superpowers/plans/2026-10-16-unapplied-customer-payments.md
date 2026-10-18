# Unapplied Customer Payments — Implementation Plan

Status: approved; Stages 0–E implemented and verified. Stage C evidence in
`audit/credit-reconciliation-2026-10-16.md` was reviewed by the user, who
authorized Stage D implementation. Stage D evidence is in
`audit/unapplied-cash-stage-d-2026-10-16.md`. Stage E evidence is in
`audit/unapplied-cash-stage-e-2026-10-16.md`; all 150 server suites / 1,372
tests passed, along with server typecheck and lint.

Design: [rev 28 spec](../specs/2026-10-16-unapplied-customer-payments-design.md).
The spec defines business behavior; this plan defines delivery order, fixtures,
integration points, and acceptance evidence. No agent delegation: review and
verification are performed directly, per the user's instruction.

## 1. Scope and binding decisions

Receive cash before an invoice exists, apply it later, refund it, or reverse an
unused receipt. Cash lives in `UNAPPLIED_CASH` sources and liability account
2110, separately from store credit in `customers.credit_balance`.

1. Applied receipts return 409 on reversal; un-apply remains deferred.
2. Preserve the historical Rs 1,800 invariant F discrepancy. A repair requires
   separate approval; never change an equation or hide rows to make it disappear.
3. Historical Rs 8,550.20 return credits are provenance-only and non-spendable.
4. Reconcile stored balances against history before any historical activation.
   Neither side is authoritative.
5. Backend and API only; no Flutter changes.
6. Never modify `server/database/erp.db`, run production migrations, or execute
   Strategy C′. All feature exercises use isolated databases.
7. Write a meaningful failing test before each implementation change. No skipped
   assertions, early-returning negative tests, or assertions on an empty fixture
   presented as evidence of a populated operation.

**Approval gates:** approve this plan before Stage 0. Stage C has a separate
review gate before Stage D. Historical activation remains outside this plan
even after either approval.

## 2. Verified repository contracts

| Contract | Source and consequence |
|---|---|
| `applyPendingMigrations(): void` | `server/src/config/database.ts`: module singleton; no database argument. `DATABASE_PATH` is a **directory**, not an SQLite filename. |
| Migration registration | Add `runLedgered('108_unapplied_customer_payments.sql')` in `applyPendingMigrations()`, after its dependencies. A `path.join(...)` expression alone does not register anything. |
| Migration lifecycle | The ledger records a filename/checksum. Finish the complete schema **and backfill** before first registration/commit. Never append SQL to a migration already recorded by a persistent database. |
| `createFixtureDb({ reference: true })` | `server/src/__tests__/helpers/productionSchema.ts`: clones the already-migrated schema into a new temp database and copies only chart-of-accounts reference rows. It does not copy historical records or rerun data migrations. |
| Jest initialization | `server/src/__tests__/setup.ts` assigns a unique temp `DATABASE_PATH`, then calls migrations in `beforeAll`. Guard installation must precede this module's imports. |
| GL posting | `AccountingService.postEntry(db, input)`: snake_case `entry_date`, `reference_type`, `reference_id`; numeric `account_id`; result `journal_entry_id`. |
| Account resolution | Caller resolves `cash`, `accounts_receivable`, and `unapplied_customer_payments` with `getAccountByTextCode`; missing accounts abort the transaction. |
| Period enforcement | `postEntry` checks its `entry_date`. `assertPeriodNotClosed(db, date, what)` throws a plain Error; map known closed-period failures to the domain's 409 response without exposing SQL/stacks. |
| Allocation reuse | Extract private `assertInvoiceAllocation` from `PaymentRecordingService` into `paymentValidation.ts`, preserving behavior for both callers. Do not reuse `allocateExistingPayment` for partial draws: it requires the entire remainder. |
| Existing invariant collectors | A–J read their existing test singleton. For integration baselines, inject that same isolated database into the new service; do not compare a different empty fixture against it. |

Read `CODING_STANDARDS.md`, `docs/REVERSAL-RULES.md`,
`audit/FINDINGS-STATUS.md`, `audit/DECISIONS.md`, and the applicable nested
`AGENTS.md` before implementation.

## 3. Stage map and ownership

| Stage | Deliverable | Gate |
|---|---|---|
| 0 | Constructor guard installed before database imports; deterministic fixture helpers; isolated baseline | Plan approval first |
| A | Complete account/table/index/payment-kind migration draft and schema tests | Schema behavior verified in isolation |
| B | FIFO provenance backfill and full immutable migration registration | A+B ship as **one migration commit** |
| C | Read-only historical reconciliation report | User reviews evidence before D |
| D | Shared validation, accounting service operations, K–N and dependent regression tests | Service and accounting tests |
| E | Mounted routes, authentication/authorization, error mapping and API tests | Full server suite and server static gates |

A and B are logical work units, not successive edits to a deployed migration.
The A+B commit contains the whole `108_unapplied_customer_payments.sql`, its
registration, and schema/backfill tests. Until B is complete, test draft SQL in
isolated databases rather than registering a partial migration.

No commit is performed by the agent unless the user authorizes commits.

## 4. Stage 0 — isolation and live-database protection

### 4.1 Guard the actual constructor

Planned files:

- `server/src/__tests__/helpers/liveDbGuard.ts`: path identity and constructor wrapper.
- `server/src/__tests__/helpers/installLiveDbGuard.ts`: install a Jest mock of
  `better-sqlite3` using `jest.requireActual` and the wrapper below.
- `server/jest.config.js`: put installation in `setupFiles`, which runs before
  `setupFilesAfterEnv` and database imports.
- `server/src/__tests__/liveDbGuard.test.ts`: exercise the intercepted import,
  rather than just calling a detached path checker.

The helper directory is **three** levels below `server/`. The test directory
is two levels below it. `path.resolve` normalizes paths; `fs.realpathSync`
resolves symlinks. Compare device/inode too, so a hardlink cannot bypass the
guard. The wrapper permits explicit read-only opens, isolated temp files, and
`:memory:`; it rejects writable canonical opens before calling SQLite.

Proposed helper (verified separately; not installed in application code yet):

```ts
import * as fs from 'fs';
import * as path from 'path';
import type Database from 'better-sqlite3';

export function resolveLiveDbPath(): string {
  return path.resolve(__dirname, '../../../database/erp.db');
}

function physicalPath(filename: string): string {
  const absolute = path.resolve(filename);
  if (fs.existsSync(absolute)) return fs.realpathSync(absolute);
  return path.join(fs.realpathSync(path.dirname(absolute)), path.basename(absolute));
}

export function protectDatabaseConstructor(Constructor: typeof Database): typeof Database {
  return new Proxy(Constructor, {
    construct(target, args, newTarget) {
      const filename = args[0];
      const readonly = args[1]?.readonly === true;
      if (typeof filename === 'string' && filename !== ':memory:' && !readonly) {
        const canonical = physicalPath(resolveLiveDbPath());
        const candidate = physicalPath(filename);
        const sameFile = fs.existsSync(candidate) && fs.existsSync(canonical)
          && fs.statSync(candidate).dev === fs.statSync(canonical).dev
          && fs.statSync(candidate).ino === fs.statSync(canonical).ino;
        if (candidate === canonical || sameFile) {
          throw new Error('refused to open the canonical live database for writing');
        }
      }
      return Reflect.construct(target, args, newTarget);
    },
  });
}
```

The installer uses a hoisted mock factory: obtain the real constructor with
`jest.requireActual('better-sqlite3')`, obtain the helper with
`jest.requireActual('./liveDbGuard')`, and return its protected constructor.
The helper has only a **type-only** database import, avoiding a circular runtime
load. Preserve the constructor's static members through the Proxy.

Acceptance tests, each observed through `new Database(...)` imported after the
installer:

1. Canonical path, relative spelling, symlinked file/parent, and hardlink refuse
   write access before SQLite sees the canonical filename.
2. `:memory:` and a unique temporary file can create, insert, and read data.
3. A read-only canonical open cannot write. Do not probe a writable native
   canonical connection even as a test of rejection.
4. The helper resolves exactly to the canonical server path; compare with
   `path.resolve(__dirname, '../../database/erp.db')` from the **test file**.
5. The existing fixture helper and test bootstrap still work with interception.

For feature-validation commands, use an outer runner that snapshots the main
database and any existing WAL/SHM bytes before spawning Jest, waits for child
exit, then compares the snapshot in a `finally` path even on test failure.
Pass through a nonzero child status; a changed snapshot is also a failure.
This observes the whole child run, rather than one hash assertion halfway
through a suite. It is a backstop, not a continuous filesystem write monitor.
Do not claim `scripts/check.sh` already implements this behavior.

Recorded main-file baseline:
`63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f`.
A mismatch is reported, never silently refreshed. An independently running
application can change WAL/SHM; investigate that before attributing a change to
tests or refreshing evidence.

### 4.2 Fixtures

Reuse `createFixtureDb` and `cleanupFixtureDbs`; no `isolatedDb.ts`.
Add the two seed helpers below to the existing fixture helper **after approval**.
Each operates on a fresh empty fixture, uses explicit IDs, and runs atomically.
Call cleanup from `afterAll`.

Feature seed:

```ts
import type Database from 'better-sqlite3';

export function seedCustomers(db: Database.Database, count = 3): void {
  const insert = db.prepare(
    `INSERT INTO customers
       (id, customer_code, customer_name, current_balance, credit_balance)
     VALUES (?, ?, ?, 0, 0)`
  );
  db.transaction(() => {
    for (let index = 1; index <= count; index += 1) {
      insert.run(index, `SEED-${index}`, `Seed Customer ${index}`);
    }
  })();
}
```

Historical **synthetic test** seed:

```ts
import type Database from 'better-sqlite3';

export function seedHistoricalLedger(db: Database.Database): void {
  const customer = db.prepare(
    `INSERT INTO customers
       (id, customer_code, customer_name, current_balance, credit_balance)
     VALUES (?, ?, ?, 0, 0)`
  );
  const ledger = db.prepare(
    `INSERT INTO customer_ledger
       (customer_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  );
  const grants: Array<[number, number[]]> = [
    [1, [450.20, 1000]],
    [12, [1000, 900, 500]],
    [13, [700, 500]],
    [14, [600, 600]],
    [15, [600, 600, 550, 550]],
  ];
  const refunds = new Map<number, number>([[1, 1200], [12, 2300], [13, 400], [15, 550]]);
  db.transaction(() => {
    for (const [customerId, amounts] of grants) {
      customer.run(customerId, `HIST-${customerId}`, `Historical Customer ${customerId}`);
      let balance = 0;
      for (const [index, amount] of amounts.entries()) {
        balance = Math.round((balance - amount) * 100) / 100;
        const date = `2026-09-0${index + 1}`;
        ledger.run(customerId, date, 'RETURN', `RET-${customerId}-${index}`,
          0, amount, balance, `${date} 10:00:00`);
      }
      const refund = refunds.get(customerId);
      if (refund !== undefined) {
        balance = Math.round((balance + refund) * 100) / 100;
        ledger.run(customerId, '2026-09-12', 'REFUND', `PAY-SEED-${customerId}`,
          refund, 0, balance, '2026-09-12 10:00:00');
      }
      if (customerId === 15) {
        for (const [index, amount] of [1200, 600].entries()) {
          balance = Math.round((balance - amount) * 100) / 100;
          ledger.run(customerId, '2026-09-13', 'CREDIT_OFFSET', `OFF-15-${index}`,
            0, amount, balance, `2026-09-13 1${index}:00:00`);
        }
      }
    }
  })();
}
```

These are constructed rows reproducing the recorded aggregate figures, not a
claim to reproduce the original transaction IDs, chronology, or complete GL.
The required ledger `balance` is supplied; REFUND writes debit, not credit.
Historical IDs are explicitly 1, 12, 13, 14, 15. There are 13 RETURN rows and
two CREDIT_OFFSET rows. Do not use this partial fixture to assert historical
A–J baselines.

| Customer | RETURN credits | REFUND debits | CREDIT_OFFSET credits | Stored credit | Derived |
|---|---|---|---|---|---|
| 1 | 1450.20 | 1200 | 0 | 0 | 250.20 |
| 12 | 2400 | 2300 | 0 | 0 | 100 |
| 13 | 1200 | 400 | 0 | 0 | 800 |
| 14 | 1200 | 0 | 0 | 0 | 1200 |
| 15 | 2300 | 550 | 1800 | 0 | -50 |
| Total | 8550.20 | 4450 | 1800 | 0 | |

Separate fixture purposes:

- Schema tests: fresh isolated pre-108 schema; execute draft migration SQL.
- Post-migration feature tests: existing fixture helper plus `seedCustomers`.
- Backfill tests: schema plus `seedHistoricalLedger`, **then explicitly execute
  the backfill SQL** on that same connection. Cloning a migrated schema does
  not backfill subsequently inserted history.
- Reconciliation tests: schema plus `seedHistoricalLedger`; do not require a
  backfill just to read the existing ledger.
- Historical A–J evidence: an isolated, consistent SQLite backup of the
  historical database, opened separately. The five-customer synthetic fixture
  is not a substitute for that evidence. Existing collector baselines use the
  matching isolated singleton. Do not issue raw file copies of an active WAL
  database; use SQLite's backup API with a read-only source.

## 5. Stages A+B — one complete immutable migration

Files: `server/src/migrations/108_unapplied_customer_payments.sql`,
`server/src/config/database.ts`, `unappliedCashMigration.test.ts`, and
`unappliedCashBackfill.test.ts` under `server/src/__tests__/`.

Build the account insert below plus the three CREATE TABLE statements and the
payments ALTER in spec §§3.1–3.4. Preserve the spec's CHECK constraints and
generated column verbatim. Add indexes for source lookup by customer/kind/live
status/date, consumptions by source/live status and application, and the
client-key lookup. Enforce apply/refund key uniqueness scoped to
`(customer_id, operation, application_key)`; compare request identity on replay
so a different payload with the same key conflicts instead of spending twice.

Account SQL:

```sql
INSERT INTO chart_of_accounts (code, name, type, normal_balance, text_code)
VALUES ('2110', 'Unapplied Customer Payments', 'liability', 'credit',
        'unapplied_customer_payments')
ON CONFLICT(code) DO NOTHING;
```

Reject a pre-existing incompatible 2110 account or conflicting text code;
`DO NOTHING` alone is not verification of its type, normal balance, or identity.

Historical capacity query (any returned row must abort the migration):

```sql
SELECT customer_id,
       SUM(CASE WHEN transaction_type='RETURN' AND credit>0
                THEN credit ELSE 0 END) AS granted_credit,
       SUM(CASE WHEN transaction_type='CREDIT_OFFSET' AND credit>0
                THEN credit ELSE 0 END) AS consumed_credit
FROM customer_ledger
WHERE COALESCE(voided,0)=0 AND reversed_by IS NULL
GROUP BY customer_id
HAVING ROUND(consumed_credit*100) > ROUND(granted_credit*100);
```

Backfill SQL (one source per live RETURN credit; FIFO consumes at most each
source's grant):

```sql
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

Before insertion, check **per customer** that live CREDIT_OFFSET credit does
not exceed live RETURN credit, including customers with consumption but no
RETURN rows. Abort the transaction on any excess; the FIFO clamp must not
silently discard unsupported consumption. Do not consult `credit_balance` to
validate this historical reconstruction.

Migration tests must prove:

- The real schema accepts the account, resolves its text code, and rejects a
  missing normal balance. An incompatible pre-existing 2110 aborts.
- Generated remaining is read-only; all spec CHECKs are present and reject
  violating writes. Exercise full refund and apply-then-refund examples.
- 13 historical sources total 8550.20 credited, 1800 consumed, 6750.20 remaining,
  zero refundable cash, and no UNAPPLIED_CASH. Customer 15 is a **sum across four
  sources**: 2300 credited, 1800 consumed, 500 remaining, not one 2300 source.
- Voided/reversed RETURN and CREDIT_OFFSET rows are excluded; an overdrawn
  historical customer aborts with no partial inserts.
- Backfilled rows contribute nothing to the cash spendable/refundable pool.
- Foreign-key checks pass. A second **migration runner** invocation skips the
  ledgered file and duplicates neither columns nor historical sources.
- A failed migration rolls back its schema/data and is not marked applied.

Do not execute raw CREATE/ALTER/backfill SQL twice to simulate runner
idempotency. Test the actual ledger skip on a disposable migrated bootstrap,
and separately test draft SQL against an isolated pre-feature schema.

## 6. Stage C — read-only reconciliation

Files: `server/src/services/creditReconciliation.ts`,
`server/src/__tests__/creditReconciliation.test.ts`,
`audit/credit-reconciliation-2026-10-16.md`.

Proposed report query/function:

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
  /** sum of non-voided REFUND debit */
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
    ) gr ON gr.customer_id = c.id
    -- Refunds are their OWN transaction_type, not RETURN rows with a debit.
    -- Filtering 'RETURN AND debit > 0' matches nothing: every RETURN row is a
    -- credit, and the six refunds are transaction_type='REFUND'. That mistake
    -- makes this column silently read 0 for every customer.
    LEFT JOIN (
      SELECT customer_id, SUM(debit) refunded FROM customer_ledger
      WHERE transaction_type='REFUND' AND debit > 0
        AND COALESCE(voided,0)=0 AND reversed_by IS NULL
      GROUP BY customer_id
    ) rf ON rf.customer_id = c.id
    LEFT JOIN (
      SELECT customer_id, SUM(credit) consumed FROM customer_ledger
      WHERE transaction_type='CREDIT_OFFSET' AND credit > 0
        AND COALESCE(voided,0)=0 AND reversed_by IS NULL
      GROUP BY customer_id
    ) co ON co.customer_id = c.id
    WHERE gr.customer_id IS NOT NULL
       OR rf.customer_id IS NOT NULL
       OR co.customer_id IS NOT NULL
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

Test the five expected IDs and figures against the synthetic seed, then insert
voided/reversed distractors and prove they are excluded. Run the reporter on
an isolated historical backup with `PRAGMA query_only = ON`. Compare logical
table contents before/after; row counts alone cannot detect UPDATEs.

Record the actual historical output, input snapshot identity, and disagreements.
Customer 15's -50 is evidence, not a repair request. **Stop for user review
before Stage D.** Do not make choosing an authoritative historical balance a
prerequisite for writing Stage 0 or for producing this report.

## 7. Stage D — operations and accounting checks

Files: `server/src/services/unappliedCashService.ts`,
`unappliedCashTypes.ts`, `paymentValidation.ts`, `PaymentRecordingService.ts`,
`server/src/__tests__/helpers/accountingInvariants.ts`, and
`server/src/__tests__/unappliedCashGl.test.ts`.

Use a database-injected service consistent with `PaymentRecordingService`.
Implement spec §5 in transactions. Domain failures carry stable codes and
status; unexpected errors remain server-side. Require finite, positive,
currency-normalized amounts and valid operation dates at the boundary.

### 7.1 Receive

Resolve one receipt date from the validated request or the server's date
policy. Use that **same date** for `payments.payment_date`,
`postEntry.entry_date`, and the period guard. Reject a customer already in
credit and a missing customer using deterministic seeded examples.

Create the receipt payment and cash source; post Dr cash / Cr 2110 with the
**receipt payment ID**. Neither balance column nor customer ledger changes.
Rollback all writes when account lookup, period validation, or posting fails.
No negative test may return early because its fixture omitted the bad state.

### 7.2 Apply

Follow spec §5.2, including the shared invoice validation extraction. Retain
the existing payment service's full-remainder behavior while reusing the
per-invoice validation primitive.

Check source remaining, refundable pool, invoice ownership/ceiling, and the
origin receipt's aggregate allocation ceiling within the write transaction.
Normalize duplicate invoice entries before capacity checks so splitting one
invoice across request items cannot bypass its ceiling. For multiple sources,
track draws per receipt and allocate oldest-first.

Create the application header and consumption/allocation rows, increment
consumed, decrement refundable, update invoice/customer balances and write the
matching customer-ledger movement. One Dr 2110 / Cr AR group uses the
**application integer ID**. No second cash receipt.

### 7.3 Refund

Enforce the available refundable pool, not just historical credited amount.
Insert a negative REFUND payment, consumption/header rows, move refunded and
refundable counters together, and post Dr 2110 / Cr cash keyed by the
**refund payment ID**. Test both a full refund and the final 100 after applying
400 of 500. Backfilled RETURN_CREDIT cannot fund a payout.

### 7.4 Reverse and existing void consumers

Read `docs/REVERSAL-RULES.md` first. Reject applied/refunded dependencies with
409; do not fabricate a refund to bypass this decision. Validate the original
receipt date, void its GL group and payment, and retire the source atomically.

Trace existing payment/invoice void paths before implementation. Source
consumptions and base counters must change together when an existing void path
reaches this feature. Spec test 12 verifies restoration of those counters;
this does not introduce a public un-apply workflow. If existing void routing
would bypass the approved dependency rejection, return 409 at the shared
service boundary.

### 7.5 K–N and A–J

- K: compare absolute GL 2110 with live UNAPPLIED_CASH remaining, to cents.
  Missing account 2110 is an error, not an assumed zero.
- L: compare **each source**, not aggregate totals: credited less live APPLY
  and REFUND consumption equals remaining. Detect missing counter updates,
  missing draw records, and offsetting corruption across two sources.
  Historical provenance has reconstructed counters but no original draw rows;
  report that baseline explicitly rather than claiming all historical L rows
  are green or inventing consumption records.
- M: enforce all spec bounds: refunded <= credited and
  0 <= refundable <= remaining, per source.
- N: per **receipt**, live allocation sum <= payment amount. Scope to RECEIPT
  and UNAPPLIED_RECEIPT payments; a negative REFUND is not a receipt and cannot
  be compared as `0 <= -refundAmount`.
- Record A–J signatures before exercising operations on the matching isolated
  database and compare after each step, using spec §11.1's collector shapes.
  Preserve both violation labels **and amounts**; a label-only comparison
  would miss F moving from 1800 to 1900.
- On a historical backup F stays exactly 1800.00. Empty synthetic fixtures do
  not prove that historical amount. Never change the invariant equation.

Every positive test has relevant non-empty records. Include rollback injection,
closed periods, replay/conflicting keys, two sources, duplicate invoice
allocations, overdraw attempts, and reversal followed by attempted spending.

## 8. Stage E — mounted API surface

Files: `server/src/controllers/unappliedCashController.ts`,
`server/src/routes/unappliedCash.ts`, the existing router mount discovered
through the graph, `server/src/__tests__/unappliedCashApi.test.ts`, and
`docs/API.md`.

| Method | Path | Operation |
|---|---|---|
| POST | `/api/customers/:id/unapplied-cash` | receive |
| POST | `/api/unapplied-cash/apply` | apply |
| POST | `/api/unapplied-cash/refund` | refund |
| POST | `/api/payments/:id/reverse` | reverse |

Preserve existing route behavior if a reverse route already exists; route
UNAPPLIED_RECEIPT through the shared dependency-safe service. Reuse existing
authentication, permissions, body validation, idempotency and error middleware.

All source/receipt/invoice capacity failures and forbidden reversals in the
spec return **409**, not the old draft's 422. Closed period is 409
`PERIOD_CLOSED`; missing resources 404; malformed input 400. Responses expose
stable domain codes and no SQL, stacks, secrets, or internal paths.

Use real POST bodies against the mounted app. Cover authorization denial,
happy paths, replay/conflict, cross-customer references, closed periods and
over-allocation; assert both responses and persisted transaction/GL effects.

## 9. Required coverage map

Every spec §11 test must have a named implementation test; the following is
the minimum traceability matrix, not a replacement for the spec assertions.

| Spec tests | Stage | Required evidence |
|---|---|---|
| 1, 2, 27 | 0/D | Receive preserves balances and A–J baseline, including F's historical 1800 |
| 3, 18 | D | Partial apply reduces invoice/customer/AR by the same amount |
| 4, 5, 16, 17 | D/E | Receipt/source/refundable capacity and repeat-draw rejection |
| 6 | D | Existing invoice auto-credit uses only store credit |
| 7, 8, 33 | D/E | Dependency rejection; fresh reversal retires source and preserves K |
| 9, 10, 11, 20, 21, 25 | B/D/E | Refund limits, inert history, full drain and apply-then-refund |
| 12, 13 | D | Existing void integration and non-vacuous per-source L corruption tests |
| 14 | D/E | Key replay returns same result; no repeated GL or draw |
| 15 | D/E | Each operation checks its specified date and returns 409 on closure |
| 19, 35 | D | Two-source application; all three GL reference-ID contracts and grouped voids |
| 22, 23, 28 | A/B | Real DDL/account resolution/CHECK enforcement |
| 24, 26 | B | Historical backfill is inert and validates per-customer ledger capacity |
| 29, 31 | D | Real shared accounting service posts balanced receipt; K through lifecycle |
| 30 | D | Both allocation consumers use the shared primitive and enforce capacity |
| 32 | D | Populated receipt allocation N, including a rejected excess |
| 34 | D | Refund payment is negative and GL reference uses that payment's ID |

## 10. Verification and approval

Plan-stage evidence: `audit/unapplied-cash-plan-verification-2026-10-16.md`.
The plan snippets are proposals; passing document exercises does not mean the
feature is implemented, its routes mounted, or its migration registered.

After implementation of each stage, run directly affected tests plus callers
and dependent accounting/payment/invoice/void regressions. For accounting
writes, run the relevant A–J invariants and K–N. Run server typecheck and lint
at checkpoints. Do not substitute `--quick` static checks for affected tests.

At completion of the authorized backend implementation, run from `server/`:

```bash
npm run typecheck
npm run lint
npm test -- --runInBand
```

The unchanged Flutter side does not require its full suite for this backend
feature. Use `scripts/check.sh` if work expands across both sides or shared
contracts affecting Flutter, or for a separately requested final CI/release
verification. Keep CI gates unchanged.

Before presenting this plan, verify the path identity, seed SQL, schema,
backfill arithmetic, reconciliation and coverage map. Report the commands and
limitations. Then request plan approval; do not start Stages 0–E in the same
turn merely because this document is corrected.
