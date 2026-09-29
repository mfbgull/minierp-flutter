# Expenses on credit — technical specification

**Status:** design only. No product code, no migration, no test has been written for this
change. Accounting semantics require sign-off before any implementation (§9).

**Scope:** make an expense payable at the moment it is recorded, settle it later, age it,
cancel it safely, and keep every closed period and every cash invariant intact.

---

## Contents

1. [Verified current state](#1-verified-current-state)
2. [The blocking finding](#2-the-blocking-finding)
3. [The central design decision](#3-the-central-design-decision)
4. [Data model (proposed — not created)](#4-data-model-proposed--not-created)
5. [GL postings](#5-gl-postings)
6. [Business rules](#6-business-rules)
7. [Reporting impact](#7-reporting-impact)
8. [UI specification](#8-ui-specification)
9. [Regression matrix](#9-regression-matrix)
10. [Open decisions requiring sign-off](#10-open-decisions-requiring-sign-off)
11. [Suggested implementation order](#11-suggested-implementation-order)

---

## 1. Verified current state

| Fact | Evidence |
|---|---|
| Expense columns: `expense_no, expense_category, description, amount, expense_date, payment_method, reference_no, vendor_name, project, status, created_by` | `add-expenses-table.sql:4-20` |
| `vendor_name` is **free text `VARCHAR(200)` — no FK to `suppliers`** | `add-expenses-table.sql:16` |
| The column comment advertises `Credit` as a legal payment method | `add-expenses-table.sql:11` |
| But `normalizeCashMethod('credit')` returns **`null`** ("credit adjustment — not money in/out") | `cashService.ts:72` |
| …and `isValidPaymentMethod` returns `false` for `null`, so `Credit` is **rejected with 400** | `cashService.ts:78-82`, `expenseController.ts:155-162` |
| Rejection message promises only `Cash, Bank, Easypaisa, JazzCash or Upaisa` | `expenseController.ts:157` |
| Status machine: `Draft → [Recorded, Cancelled]`, `Recorded → [Cancelled]`, `Cancelled → []` | `expenseController.ts:146-150` |
| Create always starts the row as `Draft` | `expenseController.ts:57` |
| `Recorded` requires admin or the `expenses:approve` permission | `expenseController.ts:185-197` |
| `Recorded`/`Cancelled` rows reject all field edits (immutability) | `expenseController.ts:199-210` |
| GL-worthiness = `status NOT IN ('Draft','Cancelled')` | `reportSql.ts:52-58` |
| Recording posts **Dr `6000` / Cr cash-per-method**, `entry_date = expense_date`, `reference_type='EXPENSE'` | `accountingService.ts:736-762`, called from `Expense.ts:224` |
| `_cashOrBankAccountCode`: cash→`1000`, easypaisa→`1020`, jazzcash→`1030`, upaisa→`1040`, **anything else→`1010` Bank** | `accountingService.ts:804-814` |
| Before posting, `assertSufficientFunds` runs against that cash account | `Expense.ts:218-223` |
| Leaving GL-worthiness voids the lines (`voidJournalLinesByReference('EXPENSE', id)`) | `Expense.ts:184-190` |
| Every edit while GL-worthy voids then re-posts | `Expense.ts:191-200`, `Expense.ts:225-240` |
| Closed-period guard runs **unconditionally on `existing.expense_date`** in `update()` | `Expense.ts:156`, `expenseController.ts:169` |
| **Create does not run a period guard** — safe only because `Draft` posts nothing | `expenseController.ts:48-62` |
| H6: *"a closed period must not gain new money movements, only lose them"* | `paymentWriterCore.ts:29-30` |
| Cash-flow treats **every** active expense as `-amount` money out | `Reports.ts:976-987` (`getCashMovements`) |
| Cash reconciliation invariant: cash GL == `collectFlows` | `Reports.ts:1318` |
| AP reconciliation invariant: `AP(2000) == Σ supplier_ledger` | `Reports.ts:1297` |
| AP aging is built **entirely on `supplier_ledger`** debits FIFO-netted against credits | `Reports.ts:313-330`, `Reports.ts:330-391` |
| `supplier_ledger.supplier_id` is `NOT NULL`; `transaction_type` has **no CHECK** | `create-supplier-ledger.sql:6-8` |
| Expenses are **absent** from AP aging; they appear in P&L, cash flow and dashboard | `Reports.ts:439`, `Dashboard.ts:378,602,626` |
| `payments` enforces `((customer_id IS NULL) <> (supplier_id IS NULL))` | `add-payments-counterparty-check.sql:29` |
| Supplier settlement path exists: `SupplierPaymentService.recordSupplierPayment` → `purchase_allocations` / `po_allocations` | `SupplierPaymentService.ts:21-53` |
| No `document_references` table exists in any migration | grep across `src/migrations/` = 0 hits |
| Existing `2xxx` accounts are **only** `2000` and `2100` | grep across `src/migrations/*.sql` |
| `2110` (reserved, task 44) and `2120` (reserved, task 43) are untouched | 0 hits each in `src/` |
| `2105`, `2115`, `2130`, `2140`, `2150` are **free** | 0 hits each in `src/` |

---

## 2. The blocking finding

The schema advertises `Credit`, the controller refuses it, and the GL layer would
mis-post it even if the controller were opened up. Three independent defects:

1. **`Credit` is unreachable.** `expenseController.ts:155-162` rejects it before the row
   is written, despite `add-expenses-table.sql:11` listing it.
2. **`_cashOrBankAccountCode` has no credit branch.** Every unmatched method falls
   through to `1010 Bank` (`accountingService.ts:804-814`). If the whitelist were simply
   widened, a credit expense would silently credit the bank account — inventing money.
3. **`assertSufficientFunds` would block it anyway.** `Expense.ts:218` demands the cash
   account hold the amount before posting. A credit expense moves no cash, so the check
   is both wrong in principle and fatal in practice.

And one invariant defect downstream:

4. **Cash flow would understate cash.** `getCashMovements` pushes every active expense
   as `-amount` (`Reports.ts:976-987`). Credit expenses would leave the cash report, and
   `Reports.ts:1318` (`cash GL == collectFlows`) would stop reconciling.

This is why the task is design-only: opening the whitelist alone breaks the books.

---

## 3. The central design decision

A credit expense is **an expense incurred but not yet paid**. It must

- hit the P&L when recorded (the expense happened), and
- hit a **liability**, not a cash account, until settled.

### 3.1 The two candidate routes

| | **A — dedicated `2115 Expense Payables`** (recommended) | **B — reuse `2000 AP` + `supplier_ledger`** |
|---|---|---|
| GL | Dr `6000` / Cr `2115` | Dr `6000` / Cr `2000` |
| Aging | new, computed from `expenses` | free — `computeAPAging` already works |
| Settlement | new `expense_payments` writer | existing `SupplierPaymentService` |
| Invariant `AP(2000) == Σ supplier_ledger` (`Reports.ts:1297`) | **untouched** | **breaks** unless every credit expense also writes a `supplier_ledger` row |
| `supplier_ledger.supplier_id NOT NULL` | not involved | forces a real supplier row for every free-text payee |
| `payments` XOR check (`customer_id`/`supplier_id`) | not involved | forces `supplier_id`, which `vendor_name` cannot supply |
| Reachable for "Electricity Dept", "Landlord" | yes | no, without creating fake suppliers |

**Recommendation: Route A.** Route B silently breaks a reconciliation the codebase
already depends on (`Reports.ts:1297`), and it cannot represent the ordinary credit
expense whose payee is a free-text vendor, not a supplier record. It also drags the
expense into supplier payments, where `payments` requires exactly one counterparty
(`add-payments-counterparty-check.sql:29`).

Route A keeps `2000` and `supplier_ledger` byte-for-byte unchanged and gives expense
payables their own, smaller lifecycle.

### 3.2 Why this mirrors tasks 43 and 44 — and where it diverges

Same shape as both: a reserved liability account, a dedicated table for the lifecycle,
and settlement that must never re-enter the cash report twice. It diverges in that the
source document (`expenses`) already exists and is already GL-posted — only the credit
branch is missing. No new document type is introduced.

---

## 4. Data model (proposed — not created)

### 4.1 New account

| Code | Name | Type | Note |
|---|---|---|---|
| `2115` | Expense Payables | liability (credit) | free — 0 hits in `src/`; does not collide with `2110` (task 44) or `2120` (task 43) |

Seeded by a migration, matching how `1110 Customer Credit` was added
(`add-customer-credit-account.sql`).

### 4.2 Changes to `expenses`

```sql
ALTER TABLE expenses ADD COLUMN supplier_id INTEGER REFERENCES suppliers(id);
ALTER TABLE expenses ADD COLUMN due_date    DATE;
ALTER TABLE expenses ADD COLUMN paid_amount DECIMAL(15,2) NOT NULL DEFAULT 0;
```

- `supplier_id` **nullable** — identity of the payee when it *is* a known supplier;
  `vendor_name` stays authoritative for display and for free-text payees.
- `due_date` nullable — manual due date; no term engine in scope.
- `paid_amount` is the settlement accumulator. `outstanding = amount - paid_amount`.
- CHECK (proposed, added at migration time):
  `paid_amount >= 0 AND paid_amount <= amount`.

### 4.3 New table `expense_payments`

```sql
CREATE TABLE expense_payments (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  expense_id     INTEGER NOT NULL REFERENCES expenses(id),
  payment_date   DATE NOT NULL,
  amount         DECIMAL(15,2) NOT NULL CHECK (amount > 0),
  payment_method TEXT NOT NULL,          -- same whitelist as cash payments
  reference_no   TEXT,
  notes          TEXT,
  created_by     INTEGER REFERENCES users(id),
  created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_expense_payments_expense ON expense_payments(expense_id);
CREATE INDEX idx_expense_payments_date    ON expense_payments(payment_date);
```

A dedicated table rather than the `payments` table because `payments` **requires**
exactly one of `customer_id`/`supplier_id` (`add-payments-counterparty-check.sql:29`)
and an expense payee may be neither.

### 4.4 `payment_method` accepts `Credit`

- `normalizeCashMethod('credit')` continues to return `null` — credit is not money, and
  `cashService.ts:72` says so explicitly. **Do not change it**: cash-flow grouping and
  `collectFlows` depend on that `null`.
- The expense whitelist gains `Credit` as an explicit, separate branch in
  `expenseController.ts`, so `isValidPaymentMethod` (used by cash reports) stays intact.

---

## 5. GL postings

### 5.1 Record a credit expense (`Draft → Recorded`, `payment_method = 'Credit'`)

| | Account | Amount |
|---|---|---|
| Dr | `6000` Operating Expenses | `amount` |
| Cr | `2115` Expense Payables | `amount` |

- `entry_date = expense_date`, `reference_type = 'EXPENSE'` (unchanged).
- **Skips** `_cashOrBankAccountCode` and **skips** `assertSufficientFunds` — no cash moves.

### 5.2 Record a cash/bank expense — unchanged

| | Account | Amount |
|---|---|---|
| Dr | `6000` | `amount` |
| Cr | `1000` / `1010` / `1020` / `1030` / `1040` | `amount` |

`assertSufficientFunds` still runs. Existing behaviour, byte-for-byte.

### 5.3 Settle a credit expense (partial or full)

| | Account | Amount |
|---|---|---|
| Dr | `2115` | `paid amount` |
| Cr | cash-per-method | `paid amount` |

- `entry_date = payment_date`, `reference_type = 'EXPENSE_PAYMENT'` (new).
- `assertPeriodOpen(payment_date)` + `assertSufficientFunds(cash, paid amount)`.
- Cumulative ceiling: `Σ expense_payments ≤ expenses.amount`.

### 5.4 Cancel an unpaid credit expense

Original `EXPENSE` lines are voided by the existing
`voidJournalLinesByReference(db, 'EXPENSE', id, …)` (`Expense.ts:184-190`).

| | Account | Amount |
|---|---|---|
| (reversal) | void `6000` / void `2115` | `amount` |

`2115` returns to zero for that document; nothing else moves.

### 5.5 Cancel a settled or partially settled credit expense — **rejected**

`paid_amount > 0` ⇒ cancel is refused. The operator must void the settlement rows first
(§10.4). Mirrors task 43's "void only when `applied_amount = 0`".

### 5.6 Void a cash expense — unchanged

Existing void-and-repost logic at `Expense.ts:184-240` is untouched.

---

## 6. Business rules

| Rule | Enforcement |
|---|---|
| `payment_method = 'Credit'` accepted on expense create/update only | explicit branch in `expenseController.ts` whitelist |
| `normalizeCashMethod` still returns `null` for `credit` | no change to `cashService.ts:72` |
| Credit recording performs **no** funds check | branch around `Expense.ts:218` |
| Cash recording still performs `assertSufficientFunds` | unchanged path |
| `outstanding = amount - paid_amount ≥ 0` | DB `CHECK` + service validation |
| Settlement amount `> 0` | DB `CHECK` |
| Settlement only against `status = 'Recorded'` | service check |
| `Σ expense_payments ≤ amount` | service check inside the transaction |
| Cancel requires `paid_amount = 0` | service check |
| Cancel from `Recorded`/`Draft` only, never from `Cancelled` | existing matrix, `expenseController.ts:146-150` |
| `Recorded` still requires `expenses:approve` | unchanged, `expenseController.ts:185-197` |
| `Recorded`/`Cancelled` rows still reject field edits | unchanged, `expenseController.ts:199-210` |
| Idempotency-Key required on settlement writes | P11 `normalizeIdempotencyKey` + `claimIdempotencyKey` inside the transaction |
| Cash invariants after every row | `Reports.ts:1318`, `Reports.ts:1297` |

### 6.1 Closed-period policy — the subtle one

H6 (*"a closed period must not gain new money movements, only lose them"*,
`paymentWriterCore.ts:29`) resolves as follows.

| Action | Date used for the guard | Verdict |
|---|---|---|
| Record a **cash** expense in a closed period | `expense_date` | **blocked** — gains a cash movement (existing, `Expense.ts:156`) |
| Record a **credit** expense in a closed period | `expense_date` | **blocked** — gains a liability on a closed balance sheet (same guard, same reason) |
| Settle in a closed period | `payment_date` | **blocked** via `assertPeriodOpen` — gains a cash movement |
| Cancel whose `expense_date` sits in an **open** period | `expense_date` | allowed — loses a movement, H6 permits it |
| Cancel whose `expense_date` sits in a **closed** period | `expense_date` | **currently blocked** by the unconditional guard at `Expense.ts:156` |

The last row is the asymmetry: H6 permits *losing* a movement from a closed period, but
the guard is unconditional and therefore forbids it. See §10.5 — this is pre-existing
behaviour for cash expenses too, and is raised here rather than changed silently.

Create remains unguarded (`expenseController.ts:48-62`) because a `Draft` posts nothing;
the guard fires at the transition to `Recorded`, which is the first GL-bearing moment.

---

## 7. Reporting impact

| Report | Required change |
|---|---|
| `getCashMovements` / cash-flow (`Reports.ts:976-987`) | **Critical.** Exclude credit expenses from the `-amount` money-out rows; emit `expense_payments` rows as money-out instead. Without this, `Reports.ts:1318` breaks. |
| Cash reconciliation (`Reports.ts:1318`) | No code change — this is the invariant the row above must keep true. |
| P&L / expense summary (`Reports.ts:439`) | **None.** The expense is incurred at `Recorded` regardless of settlement. |
| Dashboard (`Dashboard.ts:378,602,626`) | Expense totals unchanged. Any cash-out widget needs the same credit filter as cash-flow. |
| AP aging (`Reports.ts:393`) | **None** — `2115` is not `2000` and not in `supplier_ledger`. |
| **New: expense-payable aging** | Bucket `outstanding` by `expense_date` (or `due_date` when set) using the same buckets as `computeAPAging` (`Reports.ts:330-391`). |
| Balance sheet | Surface `2115` as a current liability alongside `2000`/`2100`. |
| Trial balance / general ledger | Automatic once the account exists. |
| Reports listing consumers (`routes/reports.ts:12-30`) | Register the new aging report alongside `ap-aging`. |

---

## 8. UI specification

**Expense form**

- Payment-method selector gains **Credit**, alongside Cash / Bank / Easypaisa / JazzCash /
  Upaisa (removes the mismatch with `add-expenses-table.sql:11`).
- Selecting Credit reveals: optional **Payee supplier** (searchable, may be left empty),
  **Vendor name**, and **Due date**.
- Cash-account hint and the sufficient-funds warning are hidden while Credit is selected.

**Expense list**

- Credit rows carry a `Payable` badge with `outstanding` and a progress indicator
  (`paid_amount / amount`).
- Cash rows render exactly as today.

**Detail / actions**

- `Settle payment` — modal with amount (≤ outstanding), payment method, date, reference,
  notes. Partial settlements permitted; repeated until `outstanding = 0`, then the badge
  becomes `Paid`.
- `Cancel` — disabled with tooltip `Settled expenses cannot be cancelled; void the
  payment first` whenever `paid_amount > 0`.
- Settlement history listed under the expense (date, method, amount, reference).

**Aging screen**

- New `Expense payables` view reusing the AP-aging bucket layout: current, 1–30, 31–60,
  61–90, over 90.

---

## 9. Regression matrix

| # | Scenario | GL | Invariants |
|---|---|---|---|
| R1 | Record cash expense 500 | Dr 6000 500 / Cr 1000 500 | cash out 500; `Reports.ts:1318` holds |
| R2 | Record credit expense 500 | Dr 6000 500 / Cr 2115 500 | no cash movement; `2115` = 500 |
| R3 | Credit expense: no `assertSufficientFunds` | no cash leg | recording succeeds with cash balance 0 |
| R4 | Cash expense with insufficient funds | **rejected** | unchanged behaviour |
| R5 | Settle 200 of a 500 credit expense | Dr 2115 200 / Cr 1000 200 | `2115` = 300; `paid_amount` = 200 |
| R6 | Settle remaining 300 | Dr 2115 300 / Cr 1000 300 | `2115` = 0; badge `Paid` |
| R7 | Settle 600 against a 500 expense | **rejected** | `paid_amount ≤ amount` |
| R8 | Settle 0 or negative | **rejected** | DB `CHECK` |
| R9 | Settle against a `Draft` expense | **rejected** | only `Recorded` settles |
| R10 | Settle in a closed period | **rejected** | H6 — `assertPeriodOpen(payment_date)` |
| R11 | Record credit expense dated in a closed period | **rejected** | H6 — no new liability in a closed period |
| R12 | Cancel an unpaid credit expense | void `6000`/`2115` | `2115` → 0; cash untouched |
| R13 | Cancel a partly settled credit expense | **rejected** | `paid_amount = 0` required |
| R14 | Cancel an unpaid cash expense | void `6000`/`1000` | unchanged |
| R15 | Edit amount on a recorded cash expense | void + re-post | unchanged, `Expense.ts:191-240` |
| R16 | Edit amount on a recorded credit expense | void + re-post `6000`/`2115` | no funds check on the credit leg |
| R17 | Field edit on a `Recorded` row | **rejected** | immutability, `expenseController.ts:199-210` |
| R18 | Non-admin records without `expenses:approve` | **rejected** | unchanged |
| R19 | Cash-flow report with mixed cash + credit expenses | credit row absent; settlement row present | `Reports.ts:1318` holds |
| R20 | P&L with a settled and an unsettled credit expense | both counted | expense recognised at `Recorded` |
| R21 | Expense-payable aging across bucket boundaries | n/a | buckets match `computeAPAging` |
| R22 | `AP(2000) == Σ supplier_ledger` after any credit expense | **unchanged** | `Reports.ts:1297` still holds — `2115` never enters `2000` |
| R23 | Duplicate settlement POST (same Idempotency-Key) | one entry | no double debit of `2115` |
| R24 | Credit expense whose payee is a free-text vendor | posts normally | no supplier row required |
| R25 | `normalizeCashMethod('Credit')` still `null` | n/a | cash-flow grouping for cash methods unchanged |

---

## 10. Open decisions requiring sign-off

1. **Account code `2115`.** Recommended (free, `2xxx` block, no collision with `2110`/
   `2120`). Alternative: a sub-code under `2000` — rejected, see §3.1.
2. **Route A vs Route B** (§3.1). Recommendation: **Route A**. Route B breaks
   `Reports.ts:1297` unless `supplier_ledger` rows are written for expenses, and cannot
   represent free-text payees.
3. **`expense_payments` vs reusing `payments`.** Recommendation: the dedicated table —
   `payments` mandates exactly one counterparty (`add-payments-counterparty-check.sql:29`).
4. **Cancel of a settled expense.** Recommendation: reject outright and require voiding
   settlements first (§5.5), mirroring task 43. Alternative: allow a reversal pair.
5. **Closed-period cancel asymmetry (§6.1).** The guard at `Expense.ts:156` is
   unconditional, so a cancel whose `expense_date` is in a closed period is refused even
   though H6 permits *losing* a movement. This pre-dates this design and affects cash
   expenses identically. Options: (a) leave as-is, (b) allow cancel when it only voids,
   (c) require admin override. **Needs an explicit ruling — not changed by this spec.**
6. **Due date source.** Recommendation: manual `due_date` column, no term engine.
   Alternative: derive from an optional supplier payment term (out of scope here).
7. **Aging date basis.** `expense_date` (recommended, always populated) vs `due_date`
   (more accurate, nullable).
8. **Whether credit expenses appear in cash-flow at all.** Recommendation: they do not;
   their settlements do (§7).

---

## 11. Suggested implementation order

Only once §10 is approved.

1. **Migration** — seed `2115`; add `expenses.supplier_id`, `expenses.due_date`,
   `expenses.paid_amount` + `CHECK`; create `expense_payments`.
2. **Accounting** — `postCreditExpenseEntry`, `postExpenseSettlementEntry`; branch in the
   expense posting path that skips `_cashOrBankAccountCode` and `assertSufficientFunds`
   for `Credit`.
3. **Validation** — expense-level `Credit` branch in the whitelist; settlement ceiling and
   status checks; cancel guard on `paid_amount`.
4. **Settlement service** — transactional writer with `assertPeriodOpen`,
   `assertSufficientFunds`, idempotency (mirror `SupplierPaymentService.ts:21-53`).
5. **Reports** — credit filter + settlement rows in `getCashMovements`
   (`Reports.ts:976-987`); expense-payable aging; register in `routes/reports.ts`.
6. **UI** — form, list badge, settle modal, cancel disable, aging view.
7. **Tests** — one per row of §9, run against a fresh DB
   (`DATABASE_PATH=$(mktemp -d) NODE_ENV=test npx jest`), plus `npm run typecheck`.
