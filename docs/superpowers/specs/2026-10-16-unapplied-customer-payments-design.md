# Unapplied Customer Payments — Technical Specification

**Date:** 2026-10-16
**Status:** Revision 2, for review
**Scope:** Backend model + API. No Flutter. No historical data repair. No Strategy C′ execution.

---

## 1. Derived reconciliation equations

Measured read-only against live `server/database/erp.db` (v107, `integrity_check=ok`).
These are **measured facts**, not assumptions, and they constrain what the design may assert.

| # | Equation | Live result | Usable as invariant? |
|---|---|---|---|
| E1 | `Σ(debit − credit)` over active ledger rows `== customers.current_balance` | **5/5 customers tie exactly** | **YES** — the trustworthy spine |
| E2 | `invoices.total_amount − paid_amount − credit_offset == balance_amount` | **13 of 35 invoices violate** | **NO** — not maintained today |
| E3 | `GL(1100) + GL(1110) == Σ customers.current_balance` | fails by **1,800** | Existing invariant F — known open |
| E4 | `Σ(customers.credit_balance)` vs ledger `RETURN` credits | `credit_balance = 0` for every customer, despite **2,300** of RETURN credits | `credit_balance` is a **separate, currently-empty pool** |

Two consequences:

- **E2 must not be asserted.** 13 invoices — including invoice 59, where
  `1800 − 1800 − 1800 = −1800` but `balance_amount = 0` — already violate it. That
  corruption is itself a symptom of the missing capability. The design therefore
  reconciles through the **ledger and credit-source spine (E1)**, not through invoice
  header arithmetic.
- **E4 means `credit_balance` is not a mirror of the ledger.** It must be *derived
  from* `customer_credit_sources`, never the other way round.

## 2. Design decisions (approved)

**Account `2110` Unapplied Customer Payments — liability.** The originally requested
`2100` is already **"Tax Payable"**. `1120` falls inside the asset range. `2110` is
free, liability-typed, adjacent to `2100`.

**Reuse `payment_allocations`.** No separate allocation table.

**Account `1110`** stays untouched. Its misclassification (typed `asset`, economically a
liability) is documented for a separate review, not fixed here.

---

## 3. Schema

`customer_credit_sources` is the **single authoritative balance**. No other table stores
a mutable balance for the same quantity.

### 3.1 `customer_credit_sources`

One row per credit **origin**, never merged.

```
id                   INTEGER PRIMARY KEY
customer_id          INTEGER NOT NULL REFERENCES customers(id)
source_type          TEXT NOT NULL CHECK (source_type IN ('RETURN_CREDIT','UNAPPLIED_CASH'))
origin_payment_id    INTEGER REFERENCES payments(id)
origin_return_id     INTEGER REFERENCES invoice_returns(id)
origin_invoice_id    INTEGER REFERENCES invoices(id)
credited_amount      DECIMAL(15,2) NOT NULL
consumed_amount      DECIMAL(15,2) NOT NULL DEFAULT 0
refunded_amount      DECIMAL(15,2) NOT NULL DEFAULT 0
refundable_cash_amount DECIMAL(15,2) NOT NULL DEFAULT 0
remaining_amount     DECIMAL(15,2) NOT NULL   -- GENERATED below
voided               BOOLEAN NOT NULL DEFAULT 0
created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
```

- `remaining_amount` **GENERATED** as `credited − consumed − refunded`.
- `refundable_cash_amount` is the maximum still refundable **as cash**, established at
  creation from origin eligibility (§5.3) and decremented by refunds. Never derived at
  refund time from a live join, so a refund cannot be authorised by a number that
  quietly changed underneath it.
- `CHECK (refundable_cash_amount <= remaining_amount)` — enforced by the database, so a
  return credit can never become cash-backed.
- `CHECK (origin_payment_id IS NOT NULL OR origin_return_id IS NOT NULL)`.

### 3.2 `credit_source_consumptions`

Append-only. Every debit against a source is one row, never an in-place balance edit.

```
id           INTEGER PRIMARY KEY
source_id    INTEGER NOT NULL REFERENCES customer_credit_sources(id)
kind         TEXT NOT NULL CHECK (kind IN ('APPLY','REFUND'))
amount       DECIMAL(15,2) NOT NULL CHECK (amount > 0)
payment_id   INTEGER NOT NULL REFERENCES payments(id)  -- the originating receipt
invoice_id   INTEGER REFERENCES invoices(id)          -- set only when kind='APPLY'
application_id TEXT                                       -- groups one apply call
reverses_consumption_id INTEGER REFERENCES credit_source_consumptions(id)
voided       BOOLEAN NOT NULL DEFAULT 0
created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
```

Voiding a consumption **reverses the source's counters** via an inserted compensating
row, never by deleting. This is what makes reversal append-only and exact.

### 3.3 `payments.payment_kind`

```
payment_kind TEXT NOT NULL DEFAULT 'RECEIPT'
  CHECK (payment_kind IN ('RECEIPT','INVOICE_SETTLEMENT','REFUND',
                          'CREDIT_APPLICATION','UNAPPLIED_RECEIPT'))
```

Explicit, not inferred. **The `unapplied_cash_positions` table from revision 1 is
removed entirely** — it duplicated balances that `customer_credit_sources` already owns,
and two mutable copies of one number is how they drift.

### 3.4 Account seed

`2110`, `text_code='unapplied_customer_payments'`, `type='liability'`, parent = the
liability group.

---

## 4. Reconciliation — authoritative definitions

Every customer-facing number is **derived** from `customer_credit_sources`.

| Quantity | Definition |
|---|---|
| Available credit (customer) | `Σ remaining_amount` over non-voided sources |
| Refundable cash (customer) | `Σ refundable_cash_amount` over non-voided sources |
| Held unapplied cash (customer) | `Σ remaining_amount` where `source_type='UNAPPLIED_CASH'` |
| `GL 2110` balance | credit-normal: `Σ(credit − debit)` over non-voided 2110 lines |

`customers.credit_balance` is retained as a **denormalised cache** of *available credit*
and is rebuilt from the source table; a test asserts it never diverges. It is not an
independent input.

---

## 5. Operations

All four run in **one transaction** (REVERSAL-RULES §1.3). None deletes history.

### 5.1 Receive — `POST /api/customers/:id/unapplied-cash`

- Creates a `payments` row, `payment_kind='UNAPPLIED_RECEIPT'`, with **zero**
  `payment_allocations`. This is what makes it a distinct transaction type rather than
  a bypass: an unapplied receipt *cannot* have evaded invoice validation, because it
  never named an invoice.
- Creates one `customer_credit_sources` row: `UNAPPLIED_CASH`, `credited_amount = amount`,
  `refundable_cash_amount = amount`, `origin_payment_id` set.
- GL: `Dr 1000 Cash / Cr 2110`.
- **No customer-ledger row.** The customer has not been credited — recording one would
  wrongly extinguish their receivable (E1).
- The overpayment guard is **not engaged**: there is no invoice to overpay. Validation
  instead requires `amount > 0`, a valid payment method, and an open accounting period.

### 5.2 Apply — `POST /api/unapplied-cash/apply`

**Creates an invoice allocation. Never a second receipt, never a second cash movement.**

- No new `payments` row. The *original* unapplied receipt is the payment — it simply
  gains allocations, which is precisely what "was unapplied, now is applied" means.
- Inserts `payment_allocations(payment_id = <original receipt>, invoice_id, amount)`.
  Existing settlement, status and recalculation machinery then runs **unchanged**.
- GL: **one** group `Dr 2110 / Cr 1100`, keyed `reference_type='UNAPPLIED_APPLY'`,
  `reference_id = application_id`. No cash line is ever posted by an application.
- Consumes source capacity (§7) and appends `credit_source_consumptions` rows carrying
  both `payment_id` and `invoice_id`, so reversal knows exactly where the credit went.
- **Overpayment guard unchanged and still enforced** on each target invoice via the
  existing `paymentValidation` ceiling.
- **Idempotent**: reuses the existing `IdempotentClaim {scope, key, hash}` pattern —
  the key is claimed inside the write transaction, so a retry after a lost response
  replays the original `application_id` instead of applying twice.

### 5.3 Refund — `POST /api/unapplied-cash/refund`

Two independent preconditions, **both** required:

- **A.** `amount <= Σ refundable_cash_amount` over the sources being drawn.
- **B.** `amount <= original cash collected on the originating transaction`, net of
  prior refunds of that transaction (REVERSAL-RULES §1.12).

Precondition B is evaluated against the **origin**, not against this source alone, so a
return credit created from a cash-paid sale can legitimately be refunded while one
created from a credit sale cannot.

GL: `Dr 2110 / Cr 1000`. Appends a `kind='REFUND'` consumption and reduces
`refundable_cash_amount`.

### 5.4 Reverse — `POST /api/payments/:id/reverse`

**Dependency-aware.** An operation may only be reversed if every operation that depends
on it has already been reversed. Enforced by walking `credit_source_consumptions`
(`reverses_consumption_id`) and `payment_allocations`; a dependency still live produces
a 409 naming the blocking document.

| Reversing | Effect |
|---|---|
| a receipt | voids the receipt's GL group; **releases** every consumption it funded, back to the *original* source row; voided consumption rows are compensated, not deleted |
| an application | voids its allocations and its single `Dr 2110 / Cr 1100` group; restores consumed capacity to the **original** source row |
| a refund | voids `Dr 2110 / Cr 1000`; restores `refundable_cash_amount` on the original source row |

**Provenance is restored by identity.** The source row is the same row, carrying the same
`origin_payment_id` / `origin_return_id` / `origin_invoice_id`. A reversal can never
convert a `RETURN_CREDIT` source into cash-backed credit, because `refundable_cash_amount`
returns to the value it held before, which was itself derived from origin eligibility.

---

## 6. Invariants

**F is untouched.** `GL(1100) + GL(1110) == Σ customers.current_balance` keeps its exact
current meaning. `2110` is excluded from F because it is not receivable.

**K — 2110 credit-normal to credit sources (global + per customer).**

```
K_global : SUM(credit − debit) over non-voided 2110 lines
        == SUM(remaining_amount) over non-voided UNAPPLIED_CASH sources

K_per_customer : for customer C,
        Σ(remaining_amount) over C's non-voided UNAPPLIED_CASH sources
        == C's held unapplied cash
```

The GL carries no customer dimension on `journal_lines`, so the **per-customer** leg of
K is reconciled against the source ledger — which is authoritative — and the GL leg is
global. This is stated rather than papered over.

**L — source conservation.** For every non-voided source:
`remaining_amount + consumed_amount + refunded_amount == credited_amount`.

**M — refund capacity.** For every non-voided source:
`0 <= refundable_cash_amount <= remaining_amount <= credited_amount`.

**N — provenance.** Every source resolves to a live `origin_payment_id` or
`origin_return_id`; every non-voided `credit_source_consumptions` row resolves to a live
source.

**O — invoice header (NOT asserted on legacy data).** E2 fails on 13 existing invoices.
It is introduced as a collector but starts **reporting-only**, and is not part of the
pass/fail gate until the historical invoices are cleaned. Asserting it today would fail
the suite for pre-existing data unrelated to this feature.

All of K, L, M, N are hard invariants. O is advisory until data cleanup.

---

## 7. Consumption order

When applying credit:

1. reduce `refundable_cash_amount` first — this is what makes any later refund smaller;
2. then reduce `remaining_amount`;
3. `consumed_amount` follows from the generated column.

Applying against a `RETURN_CREDIT` source reduces `remaining_amount` only. It never
creates refundable capacity, because `refundable_cash_amount` for such a source was fixed
at creation from origin eligibility.

---

## 8. API

| Method | Route | Permission |
|---|---|---|
| POST | `/api/customers/:id/unapplied-cash` | `payments:create` |
| GET | `/api/customers/:id/credit-sources` | `customers:read` |
| POST | `/api/unapplied-cash/apply` | `payments:create` |
| POST | `/api/unapplied-cash/refund` | `payments:create` |
| POST | `/api/payments/:id/reverse` | `payments:delete` |

All failures return `{ error: string }`; no stack traces. Every write checks
accounting-period state before posting.

---

## 9. Testing

**Derived-equation tests first.** Before feature code, lock the §1 measurements as
regression tests: E1 holds per customer; E2's 13 legacy violations are captured as an
explicit expected-failure list so a *new* violation is detectable; E4 is captured before
the migration changes it.

**Service level** — per operation, on isolated copies:
- receive creates one balanced GL group, one source row, **zero** ledger rows, **zero**
  allocations;
- apply creates **no** new `payments` row and **no** cash GL line; the original receipt
  gains allocations; `Dr 2110 / Cr 1100` only;
- apply is idempotent under a replayed `IdempotentClaim`;
- apply reduces refundable capacity before held capacity;
- applying a `RETURN_CREDIT` source never creates refundable capacity;
- refund refuses when **either** precondition fails, and the failure message names which;
- a refund against a cash-origin return source succeeds; a credit-origin one refuses;
- reversal refuses while a dependent operation is live, naming the blocker;
- reversal restores the **original** source row identity and its provenance;
- a reversal cannot raise `refundable_cash_amount` above `remaining_amount`;
- an operation that throws mid-transaction leaves **zero** changes.

**API level** — validation, per-route authorisation (including the non-admin cannot-grant
rule), 404s, and the structured-error shape.

**Invariant level** — K, L, M, N asserted; O reported; A–J unchanged.

**Regression** — full server suite green; existing payment, return and credit-offset
suites unchanged.

## 10. Migration and rollback

One forward migration registered in `server/src/config/database.ts`
(`CODING_STANDARDS.md` §2), plus the `2110` seed. `payment_kind` backfill derives from
existing behaviour and is verified against known historical rows.

Because no historical row is rewritten, the down-migration is total.

## 11. Explicitly out of scope

- Flutter client.
- Reclassifying `1110`.
- Repairing the 13 invoices that violate E2.
- Any live correction, Strategy C′ execution, or invoice-49 work.

## 12. Open questions for the reviewer

1. `2110` accepted as the code, given `2100` is Tax Payable?
2. **O is advisory, not gating.** Acceptable, or should the suite go red on E2 until the
   legacy invoices are cleaned?
3. Consuming refundable capacity first (§7) — agreed, or should invoice application draw
   on return credit first to preserve cash for refunds?
4. No customer-ledger row on receipt (§5.1) — agreed, or should held cash appear as a
   memo line that is excluded from E1?
5. GL `2110` has no customer dimension (§6 K) — acceptable, or should journal lines gain
   a customer reference so K reconciles per customer in the GL too?