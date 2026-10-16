# Unapplied Customer Payments — Design

**Date:** 2026-10-16
**Status:** Draft for review
**Author:** implementation agent
**Supersedes:** nothing. Adds capability that does not exist today.

---

## 1. Problem

MiniERP prohibits paying more than an invoice's outstanding balance. That guard is
**correct and stays**. But it means there is nowhere to put excess customer money:
the only way to hold customer credit today is `customers.credit_balance`, and that
is fed *exclusively* by sales returns (`invoiceReturnService.ts:1044`).

The consequence is visible in live data. Customer 15 received Rs 1,800 of genuine
cash on 2026-10-10 (`PAY-1026-00060`, `PAY-1026-00061`) with no valid invoice to
apply it to. The cash had to be allocated to invoices 50 and 51, which were
**already settled** on 2026-09-17. That over-credit was then consumed as
`credit_offset = 1800` on invoice 59 — a settlement with no economic basis — and is
the entire Rs 1,800 divergence in accounting invariant F.

This design adds the missing capability. It does **not** retro-fit the historical
records; that is a separate decision.

## 2. Goals

1. Receive excess customer money and hold it as a recognised liability.
2. Apply held cash to a future invoice using existing settlement machinery.
3. Refund held cash, bounded by what was actually collected.
4. Reverse any of the above without deleting history.
5. Preserve cash, GL, customer-ledger and invoice-settlement integrity throughout.
6. Keep the existing overpayment guard intact.
7. Keep a single customer-facing credit balance, while tracking each credit's
   **origin and remaining refundable amount** at source level.

## 3. Non-goals

- No Flutter client changes. Deferred until backend semantics are proven.
- No change to `docs/REVERSAL-RULES.md` or to invariant equations' existing meaning.
- No reclassification of account `1110` (see §4.2).
- No historical data repair. Strategy C′ is reassessed *after* this ships.

## 4. Design decisions

### 4.1 Account: `2110` Unapplied Customer Payments (liability)

The request specified `2100`. **`2100` is already "Tax Payable"` in the live chart.**
Proposing **`2110`**: free, liability-typed, adjacent to `2100`.

| Account | Type | Meaning here |
|---|---|---|
| `1000` | asset | Cash |
| `1100` | asset | Accounts Receivable |
| `1110` | asset *(see 4.2)* | Customer Credit — return credit only |
| `2110` | **liability** | **Unapplied Customer Payments (new)** |

`1120` was rejected: it falls inside the asset range.

### 4.2 Account `1110` classification — deferred, documented

`1110 Customer Credit` is typed `asset` but is economically a liability (we owe the
customer). This design does **not** reclassify it; doing so mid-flight would change
every existing report and invariant. Recorded for a separate accounting-model review.

### 4.3 One balance, source-level tracking

The customer sees one number: `customers.credit_balance` — total available credit.
Internally every credit retains a source row.

| Credit source | Available for invoices | Refundable as cash |
|---|---|---|
| `RETURN_CREDIT` | yes | only per §6.3 |
| `UNAPPLIED_CASH` | yes | yes |
| Credit already applied | no | no |

**No assumption that return credit is inherently non-refundable.** A return against
an originally cash-paid sale may qualify, per §6.3.

### 4.4 `payment_kind` vs a separate allocation table

Held cash reuses `payment_allocations`. Applying held cash inserts ordinary allocation
rows, so existing settlement, status and recalculation code applies unchanged.

Rejected: a parallel allocation table, because it would duplicate settlement logic and
create a second thing to keep in sync.

## 5. Schema

All three are additive migrations. No existing table is altered except adding one
column with a backfill.

### 5.1 `customer_credit_sources`

The source ledger. One row per credit **origin**, never merged.

```
id                  INTEGER PK
customer_id         INTEGER NOT NULL REFERENCES customers(id)
source_type         TEXT NOT NULL CHECK (source_type IN ('RETURN_CREDIT','UNAPPLIED_CASH'))
origin_payment_id   INTEGER REFERENCES payments(id)      -- UNAPPLIED_CASH
origin_return_id    INTEGER REFERENCES invoice_returns(id) -- RETURN_CREDIT
origin_invoice_id   INTEGER REFERENCES invoices(id)      -- the original sale
credited_amount     DECIMAL(15,2) NOT NULL
consumed_amount     DECIMAL(15,2) NOT NULL DEFAULT 0
refunded_amount     DECIMAL(15,2) NOT NULL DEFAULT 0
remaining_amount    DECIMAL(15,2) NOT NULL   -- GENERATED: credited - consumed - refunded
voided              BOOLEAN NOT NULL DEFAULT 0
created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
CHECK (origin_payment_id IS NOT NULL OR origin_return_id IS NOT NULL)
CHECK (remaining_amount >= 0)
CHECK (consumed_amount >= 0 AND refunded_amount >= 0)
```

`remaining_amount` is **generated**, never hand-written. This is what makes
"non-cash-backed credit cannot become cash-backed" structurally impossible rather
than a rule a future contributor must remember.

### 5.2 `payments.payment_kind`

New column. Today the mode is inferred at write time; making it explicit is what makes
unapplied cash *a transaction type* rather than a way around invoice validation.

```
payment_kind TEXT NOT NULL DEFAULT 'RECEIPT'
  CHECK (payment_kind IN ('RECEIPT','INVOICE_SETTLEMENT','REFUND',
                          'CREDIT_APPLICATION','UNAPPLIED_RECEIPT'))
```

Backfill: rows whose allocations touch an invoice and whose method is `Credit` →
`CREDIT_APPLICATION`; negative amount → `REFUND`; else `RECEIPT`. The backfill is
derived from existing behaviour and is verified against the known historical rows
before the migration is considered done.

### 5.3 `unapplied_cash_positions`

```
id              INTEGER PK
payment_id      INTEGER NOT NULL REFERENCES payments(id)
customer_id     INTEGER NOT NULL REFERENCES customers(id)
amount          DECIMAL(15,2) NOT NULL
held_amount     DECIMAL(15,2) NOT NULL
refundable_amount DECIMAL(15,2) NOT NULL
status          TEXT NOT NULL DEFAULT 'HELD'
                  CHECK (status IN ('HELD','PARTIALLY_APPLIED','APPLIED','REFUNDED','REVERSED'))
voided          BOOLEAN NOT NULL DEFAULT 0
created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
CHECK (held_amount >= 0 AND refundable_amount >= 0)
CHECK (refundable_amount <= held_amount)
```

`refundable_amount <= held_amount` is enforced by the database, so a refund can never
be authorised against credit that is not physically held.

### 5.4 `credit_source_consumptions`

Which source an invoice application consumed. Required so an application can be
reversed to the *original* source.

```
id            INTEGER PK
source_id     INTEGER NOT NULL REFERENCES customer_credit_sources(id)
payment_id    INTEGER REFERENCES payments(id)   -- apply or refund
invoice_id    INTEGER REFERENCES invoices(id)   -- set only when applied to an invoice
amount        DECIMAL(15,2) NOT NULL
kind          TEXT NOT NULL CHECK (kind IN ('APPLY','REFUND'))
voided        BOOLEAN NOT NULL DEFAULT 0
created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
```

## 6. Operations

All four run in **one transaction** (REVERSAL-RULES §1.3). None deletes history.

### 6.1 Receive — `POST /api/customers/:id/unapplied-cash`

Creates a `payments` row with `payment_kind='UNAPPLIED_RECEIPT'`, **zero**
`payment_allocations`, an `unapplied_cash_positions` row, and a
`customer_credit_sources` row of type `UNAPPLIED_CASH`.

- GL: `Dr 1000 Cash / Cr 2110`
- Customer ledger: **no row.** The customer has not been credited; they still owe
  whatever they owed. Recording a ledger credit here would wrongly extinguish their
  receivable.
- `customers.credit_balance` increases by the amount.
- Overpayment guard: **not engaged** — there is no invoice to overpay. Validation
  instead requires `amount > 0` and a real payment method.

### 6.2 Apply — `POST /api/unapplied-cash/:id/apply`

Consumes held cash against one or more invoices.

- Precondition: each target invoice's remaining balance (existing
  `paymentValidation` ceiling) must cover the allocation. **The overpayment guard is
  unchanged and still applies here.**
- GL: `Dr 2110 / Cr 1100` per application group.
- Inserts ordinary `payment_allocations` rows → existing settlement/status/recalc
  machinery runs unchanged.
- Consumption order (§7): `refundable_amount` reduces first, then `held_amount`.
- Records `credit_source_consumptions` rows so reversal is exact.

### 6.3 Refund — `POST /api/unapplied-cash/:id/refund`

- Precondition A: amount ≤ source `refundable_amount`.
- Precondition B (§1.12): amount ≤ the cash actually collected on the originating
  transaction. **Both must hold.**
- GL: `Dr 2110 / Cr 1000`
- `refunded_amount` rises; `refundable_amount` and `held_amount` fall.

Refundability of `RETURN_CREDIT` is **not** assumed either way: a return source
carries refundable capacity only if its `origin_invoice_id` was settled by cash, and
even then only up to that cash less any already refunded. This is computed from the
origin, never asserted.

### 6.4 Reverse — `POST /api/payments/:id/reverse`

Symmetric with whatever it reverses:

| Reversing | Restores |
|---|---|
| a receipt | voids the GL group; `held_amount`/`refundable_amount` restored; consumption rows voided; source row restored **verbatim** |
| an application | voids the allocation and the `Dr 2110/Cr 1100` group; releases the consumed amounts to the **original** source row |
| a refund | voids `Dr 2110/Cr 1000`; `refunded_amount` restored to the source row |

**A reversal never converts a `RETURN_CREDIT` source into cash-backed credit.** The
source row is restored by identity, not recreated from a balance.

### 6.5 Consumption order (§7) — the core rule

When applying credit, reduce in this order:

1. `refundable_amount` (cash-backed portion) — this is what makes later refunds smaller
2. `held_amount`
3. `consumed_amount` (derived)

Applying against `RETURN_CREDIT` reduces `held_amount` only; it never creates
refundable capacity.

## 7. Invariants

**F is extended, never weakened.** `GL 1100 + 1110` reconciles against customer
balances exactly as today. `2110` is deliberately excluded from F, because it is not
receivable.

New **K — GL to positions**: `GL 2110 == Σ unapplied_cash_positions.held_amount` for
all non-voided rows.

New **L — source conservation**: for every non-voided source,
`remaining + consumed + refunded == credited`. This is what makes credit-conversion
bugs impossible to hide.

New **M — per position**: `0 ≤ refundable_amount ≤ held_amount ≤ amount`.

Each is a separate collector alongside A–J, reusing the same helper module
(`src/__tests__/helpers/accountingInvariants.ts`) so the suite cannot drift.

## 8. API

| Method | Route | Auth |
|---|---|---|
| POST | `/api/customers/:id/unapplied-cash` | `payments:create` |
| GET | `/api/customers/:id/credit-sources` | `customers:read` |
| POST | `/api/unapplied-cash/:id/apply` | `payments:create` |
| POST | `/api/unapplied-cash/:id/refund` | `payments:create` |
| POST | `/api/payments/:id/reverse` | `payments:delete` |

All routes return the structured `{ error: string }` shape on failure. No stack traces.
Every write validates period-open state before posting.

## 9. Testing

**Service level** — per operation, on isolated copies:
- receive creates exactly one balanced GL group and **no** ledger row
- apply reduces refundable before held; applies to `RETURN_CREDIT` never create
  refundable capacity
- refund refuses when either §6.3 precondition fails
- refund against a return-credit source created from a cash sale succeeds; from a
  credit sale, refuses
- reversal restores the **original** source identity, not a rebuilt row
- an operation inside a transaction that throws leaves **zero** changes

**API level** — validation, authorization (each route's permission, including the
non-admin cannot-grant rule), not-found, and structured-error shape.

**Invariant level** — K, L, M added to the collector suite; A–J unchanged.

**Regression** — full server suite green; existing payment, return and credit-offset
suites unchanged.

## 10. Migration and rollback

One migration, forward-only, registered in `server/src/config/database.ts` per
`CODING_STANDARDS.md` §2. The backfill of `payment_kind` (§5.2) is verified against
known rows before it is considered correct.

Rollback is a separate down-migration dropping the three tables and the column.
Because no historical row is rewritten, rollback is total — this is the main practical
advantage over the historical corrections.

## 11. Open items for the reviewer

1. **Should `2110` be the code**, given `2100` is Tax Payable?
2. Is *no* customer-ledger row on receipt correct, or should held cash appear on the
   ledger as a memo? (Chosen: no row — it would wrongly credit the customer.)
3. Is the consumption order in §7 right, or should invoice application draw on return
   credit first, preserving cash for refunds?