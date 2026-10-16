# Unapplied Customer Payments — Technical Specification

**Revision 7** · 2026-10-16 · Backend + API only

Supersedes revisions 1–6. Three blockers have been found by *executing* this
document rather than reading it, and each was invisible to careful review:

- **rev 5** — executing the DDL showed §3.1's
  `CHECK (refunded_amount <= refundable_cash_amount)` is unsatisfiable against
  §5.3, which moves both in opposite directions. The schema refused the most
  ordinary refund in the feature.
- **rev 6** — running the §8 backfill arithmetic showed
  `customers.credit_balance` is not a historical record (customer 12: 2400
  returned, 2300 refunded, balance 0). The fail-closed guard would have blocked
  the migration permanently.
- **rev 7** — reproducing the collector's own arithmetic showed invariant F
  **already fails by exactly 1800.00**, independent of this feature. §12's tests
  must therefore assert *no new* violations against a captured baseline, never
  absolute green, which is now specified in §12.1.

Every factual claim below was verified against `server/database/erp.db`, the
current source tree, by executing the proposed DDL against SQLite 3.51.2, by
running the §8 backfill arithmetic against live data, by reproducing
`arImbalances()` verbatim, and by executing migration 108 end-to-end against a
replica of the live `payments` / `chart_of_accounts` shape.

That last run is clean: `ALTER TABLE payments ADD COLUMN` accepts
`NOT NULL DEFAULT 'RECEIPT' CHECK (...)` on a populated table, preserves every
row, enforces the CHECK on both INSERT and UPDATE, and — the one that matters
for compatibility — still accepts legacy `INSERT`s that omit the column, which
existing code will do. `2110` inserts without collision. The three new tables
create and roll back cleanly inside one transaction.

---

## 1. Measured facts

All figures from `server/database/erp.db`, read-only, `user_version=107`,
`integrity_check=ok`.

| Ref | Fact | Value |
|---|---|---|
| E1 | For 5/5 customers, sum of non-voided `customer_ledger` (debit−credit) equals `customers.current_balance` | exact |
| E2 | `total_amount − paid_amount − credit_offset = balance_amount` fails on 13/35 invoices | **advisory only** — not a hard invariant |
| E3 | Invariant F (`arImbalances`) currently fails | GL side 3499.80 vs customer side 1699.80, gap **1800.00** |
| E4 | `credit_balance` is zero for every customer, while store credit exists | `SUM(credit_balance) = 0`; non-voided `RETURN` credits total **8550.20** across 13 rows; 2 `CREDIT_OFFSET` ledger rows exist |
| E5 | `credit_balance` writers | `invoiceReturnService.ts:1044` (+), `:1281` (−), `InvoiceCreationService.ts:295` (−). Store-credit paths only |
| E6 | `payments.payment_method` distinct values | `Cash`, `Easypaisa`. **Zero** `Credit` rows |
| E7 | Negative-amount payments | 6 rows, all genuine refunds |
| E8 | Triggers on `payment_allocations` | none |
| E9 | `journal_lines.reference_id` | `INTEGER` |
| E10 | `payment_allocations.invoice_id` | `NOT NULL` |
| E11 | Accounts | `2100` = Tax Payable; `2110` free; `1100`, `1110`, `1120` exist |

---

## 2. The blocking correction

`customers.credit_balance` is **store credit and nothing else**. It is created by
returns, reduced by return-refunds, and reduced by the invoice-creation
credit-offset path. It is not a general "available credit" cache.

Revision 2 wrongly proposed to repurpose it as the cache for all customer credit.
That was wrong twice over:

1. It breaks invariant F. The real collector asserts
   `abs(GL(1100) + GL(1110)) == abs(Σ current_balance − Σ credit_balance)`
   (`accountingInvariants.ts:223-233`). Adding unapplied cash to `credit_balance`
   lowers F's right-hand side while leaving the GL side untouched, so every
   unapplied receipt turns F red.
2. It double-spends. `InvoiceCreationService.ts:170-178` computes
   `available = credit_balance + abs(min(0, current_balance))` and `:292-295`
   decrements `credit_balance`, writing a `CREDIT` ledger row and **no**
   `credit_source_consumptions` row. Cash parked there would be auto-applied at
   invoice creation with no consumption recorded and no `remaining_amount`
   reduction, leaving it spendable a second time through the apply endpoint.

**Resolution.** `credit_balance` is untouched by this feature. Unapplied cash
exists only in `customer_credit_sources` with `kind='UNAPPLIED_CASH'`. Customer
available credit becomes a derived view, never a stored pool:

```
availableCredit(customer) = credit_balance
                          + Σ remaining_amount  (sources where kind='UNAPPLIED_CASH' AND live)
```

Customer-facing balance owed by the customer:

```
netBalance(customer) = current_balance − credit_balance − Σ remaining_amount (UNAPPLIED_CASH)
```

Invariant F is therefore genuinely untouched: this feature writes neither
`current_balance` nor `credit_balance` for receipts, and applies write
`current_balance` in lockstep with the GL entry it mirrors.

---

## 3. Data model

### 3.1 `customer_credit_sources`

One row per grant of customer credit. `kind` is either `RETURN_CREDIT` (existing
return flow, backfilled) or `UNAPPLIED_CASH` (this feature).

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | also the `journal_lines.reference_id` for the apply/refund groups |
| `customer_id` | INTEGER NOT NULL | FK → `customers` |
| `kind` | TEXT NOT NULL CHECK (`RETURN_CREDIT`, `UNAPPLIED_CASH`) | |
| `origin_payment_id` | INTEGER | receipt that funded it. NULL for RETURN_CREDIT |
| `origin_invoice_id` | INTEGER | invoice the return was against. NULL for UNAPPLIED_CASH |
| `credited_amount` | DECIMAL(15,2) NOT NULL | **base column**, never mutated after insert |
| `consumed_amount` | DECIMAL(15,2) NOT NULL DEFAULT 0 | **base column** |
| `refunded_amount` | DECIMAL(15,2) NOT NULL DEFAULT 0 | **base column** |
| `remaining_amount` | DECIMAL(15,2) GENERATED ALWAYS AS (`credited_amount − consumed_amount − refunded_amount`) VIRTUAL | **derived**, read-only |
| `refundable_cash_amount` | DECIMAL(15,2) NOT NULL | cash still refundable. For `RETURN_CASH` provenance this can be less than `remaining_amount`; for cash-backed sources it tracks `remaining_amount` |
| `credited_at` | TIMESTAMP NOT NULL | oldest-first refund ordering key |
| `voided_at` | TIMESTAMP NULL | |

`remaining_amount` is generated **from** the three base counters. It is never the
source of truth and never written. The constraints therefore validate whatever
the base counters say — if a writer corrupts `consumed_amount` without recording
a consumption, they still pass and only invariant L catches it. That is why L is
asserted in code (§6), not delegated to the schema.

The constraints belong **inside** the `CREATE TABLE`, not in a trailing block.
A separate block is easy to drop during implementation and fails silently — no
error, just no enforcement:

```sql
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
```

Note what the refund constraint is **not**. It is not
`refunded_amount <= refundable_cash_amount`. `refunded_amount` is a monotonic
accumulator while `refundable_cash_amount` is a draining pool, and §5.3 moves
them in opposite directions. Comparing an accumulator to a pool that has just
been drained by the same operation makes the constraint unsatisfiable: refunding
the last 100 of a 500 source sets `refunded = 100, refundable = 0`, and
`100 <= 0` fails. Verified — that schema rejects the single most ordinary refund
in the feature. The correct bound is against the total credited.

Whether a *particular* source may be refunded from is not a schema question.
`refundable_cash_amount = 0` is ambiguous between "non-cash store credit" and
"cash already drained", so the non-cash restriction is enforced by §5.3's
service-side `WHERE refundable_cash_amount >= :drawn`, not by a constraint.

### 3.2 `credit_source_consumptions`

Records every draw against a source: an apply (APPLY) or a refund (REFUND).

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `source_id` | INTEGER NOT NULL | FK → `customer_credit_sources` |
| `application_id` | INTEGER NOT NULL | FK → `credit_applications`. Groups one apply call |
| `kind` | TEXT NOT NULL CHECK (`APPLY`, `REFUND`) | |
| `invoice_id` | INTEGER NULL | set only for `APPLY`. Lives here, **not** in `payment_allocations`, whose `invoice_id` is `NOT NULL` (E10) |
| `payment_id` | INTEGER | the receipt this draw credits, for apply |
| `amount` | DECIMAL(15,2) NOT NULL CHECK (`amount > 0`) | |
| `created_at` | TIMESTAMP NOT NULL | |

### 3.3 `credit_applications`

Header row per apply or refund call. Its integer `id` is the journal
`reference_id`; the TEXT `application_key` is the client-facing grouping id.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | `journal_lines.reference_id` |
| `application_key` | TEXT NOT NULL | client-generated group key |
| `customer_id` | INTEGER NOT NULL | |
| `operation` | TEXT NOT NULL CHECK (`APPLY`, `REFUND`) | |
| `total_amount` | DECIMAL(15,2) NOT NULL | |
| `created_at` | TIMESTAMP NOT NULL | |

Reversal keys on `(reference_type, reference_id)`, and `reference_id` is
`INTEGER` (E9). The TEXT key therefore **cannot** be the journal reference; the
numeric `credit_applications.id` is.

### 3.4 `payments.payment_kind`

```sql
ALTER TABLE payments ADD COLUMN payment_kind TEXT
  NOT NULL DEFAULT 'RECEIPT'
  CHECK (payment_kind IN ('RECEIPT','UNAPPLIED_RECEIPT','REFUND','CREDIT_APPLICATION'));
```

---

## 4. GL treatment

New liability account **`2110 Unapplied Customer Payments`** (E11: `2110` is
free; `2100` is already Tax Payable). Credit-normal.

| Reference type | Entry |
|---|---|
| `UNAPPLIED_RECEIPT` | Dr `1000` Cash / Cr `2110` Unapplied — the receipt |
| `UNAPPLIED_APPLY` | Dr `2110` Unapplied / Cr `1100` AR — settling an invoice |
| `UNAPPLIED_REFUND` | Dr `2110` Unapplied / Cr `1000` Cash — paying cash back |
| `CREDIT_OFFSET` | existing, unchanged — store credit applied at invoice creation |

The existing `PAYMENT` reference type is **not** reused: it means
Dr Cash / Cr AR, which is the wrong counter-account for unapplied cash. Storing
the receipt under a distinct type keeps each reversal scoped to one group and
leaves `Payment.delete`'s PAYMENT void logic untouched.

---

## 5. Operations

All four run inside one `db.transaction(...)` and open with
`AccountingService.assertPeriodNotClosed` (§7).

### 5.1 Receive unapplied cash — `POST /api/customers/:id/unapplied-cash`

1. Reject if `kind` would create a source for a customer with a negative
   `current_balance` (credit already exists; apply it first).
2. Insert `payments` row: `payment_kind='UNAPPLIED_RECEIPT'`, `customer_id` set,
   amount = request amount.
3. Insert `customer_credit_sources` row: `kind='UNAPPLIED_CASH'`,
   `origin_payment_id`, `credited_amount` = amount, `refundable_cash_amount` =
   amount.
4. Post `UNAPPLIED_RECEIPT` GL entry.
5. **No `customer_ledger` row.** Customer money has not moved — it is still
   theirs, merely unallocated. Writing a ledger row would imply a balance change
   that did not happen and would break E1.

Touches neither `current_balance` nor `credit_balance`, so F is unaffected.

### 5.2 Apply — `POST /api/unapplied-cash/apply`

Applies held cash to one or more invoices. Reuses the original receipt's
`payment_allocations` — **no second receipt and no second cash posting**.

1. Load the source; reject if voided or `remaining_amount <= 0`.
2. **Capacity guard (the primitive).** This endpoint may not reuse
   `PaymentRecordingService.allocateExistingPayment`: that method throws unless
   `allocated` equals the *entire* unallocated remainder
   (`PaymentRecordingService.ts:115`), so it cannot express a partial draw. The
   new `UnappliedCashService.apply` enforces instead:

   ```
   requested = Σ allocations in this call
   assert requested <= source.remaining_amount          -- per-source ceiling
   assert requested <= source.refundable_cash_amount    -- cash still held
   alreadyDrawn = Σ payment_allocations.amount
                    WHERE payment_id = source.origin_payment_id
                      AND voided_at IS NULL
   assert alreadyDrawn + requested <= payment.amount   -- receipt ceiling
   ```

   The third assertion is the one that closes the over-application hole. Neither
   `paymentValidation.validateCustomerPayment` (per-invoice ceiling and ownership
   only) nor the schema (no trigger, E8) constrains this today, so it is asserted
   explicitly here and in a CHECK-backed invariant.
3. For each allocation, run the existing `assertInvoiceAllocation` per-invoice
   ceiling and ownership checks unchanged.
4. Insert one `credit_applications` row (`operation='APPLY'`), then one
   `credit_source_consumptions` row per source drawn.
5. **Move the source counters — mandatory, same transaction.** For each source
   drawn:

   ```sql
   UPDATE customer_credit_sources
      SET consumed_amount       = consumed_amount + :drawn,
          refundable_cash_amount = refundable_cash_amount - :drawn
    WHERE id = :source_id
      AND consumed_amount + :drawn <= credited_amount
      AND refundable_cash_amount >= :drawn
   ```

   Zero affected rows → throw and roll the whole transaction back.
   `remaining_amount` is generated from these counters, so **omitting this step
   leaves the full original amount apparently available forever** — the first
   capacity assertion would never bite again and the same cash could be applied
   repeatedly. `refundable_cash_amount` moves down here too, because cash
   converted into invoice settlement is no longer refundable.
6. Insert `payment_allocations` rows against `source.origin_payment_id`.
7. Post one `UNAPPLIED_APPLY` GL entry for the total:
   Dr `2110` / Cr `1100`.
8. Recompute the target invoices' `balance_amount`, and **decrease** each target
   customer's `current_balance` by the amount settled on their invoices.

   Sign convention, verified against live data: `current_balance` is **positive
   when the customer owes** (customers 1, 12 and 13 each equal their unpaid
   invoice balance exactly). Settling an invoice therefore reduces what is owed,
   so the balance goes **down**. The `Cr 1100` leg moves `GL(1100)` — computed
   as `SUM(debit) − SUM(credit)` — down by the same amount, and that matched
   movement is precisely what keeps invariant F balanced.
9. Rebuild the customer ledger for each affected customer.

Idempotency: scope `unapplied_cash.apply`, `resource_id` = the numeric
`credit_applications.id`, replay returns the stored application row. The TEXT
`application_key` is stored on that row but is **not** the idempotency
`resource_id`, because the machinery replays by numeric resource id.

### 5.3 Refund — `POST /api/unapplied-cash/refund`

Returns cash to the customer.

1. **Source selection is deterministic and server-side.** The request body does
   not name sources. The service draws only from sources where
   `refundable_cash_amount > 0` **and** `remaining_amount > 0`, ordered
   `credited_at ASC, id ASC` (oldest first), capping each source's contribution
   at `min(refundable_cash_amount, remaining_amount)`.

   Both conditions are required. `refundable_cash_amount` alone would let a
   refund draw cash that apply has already converted into invoice settlement,
   because §5.2 step 5 reduces both counters together and a source whose
   `remaining_amount` has been consumed must contribute nothing.
2. Assert `total <= Σ refundable_cash_amount` over the sources actually drawn.
3. Assert `total <= Σ` cash originally collected from this customer
   (`origin_payment_id` receipts, refunds excluded).
4. Insert `credit_applications` (`operation='REFUND'`), one
   `credit_source_consumptions` row per source drawn (`invoice_id` NULL).
5. Increment `refunded_amount` and decrement `refundable_cash_amount` on each
   drawn source.
6. Post `UNAPPLIED_REFUND` GL entry: Dr `2110` / Cr `1000`.

A return-credit source has `refundable_cash_amount = 0` unless its provenance is
cash, so refunds can never be funded from non-cash store credit.

### 5.4 Reverse — `POST /api/payments/:id/reverse`

Reversal is **refused whenever the receipt has already been applied**. This is a
deliberate restriction, not a limitation to be engineered around.

```
POST /api/payments/:id/reverse
  → 409 UNAPPLIED_ALREADY_APPLIED
    { blockedBy: [ { sourceId, consumed, invoices: [invoiceIds] } ] }
```

A receipt whose cash has been applied to invoices can no longer be returned as
cash without first un-applying, and un-applying would leave the customer holding
an invoice they did not ask to hold. Rather than reconstruct cross-source funding
order — which the consumption table cannot express, since it records the
source's origin payment and not which receipt each invoice drew on first — the
reverse path refuses and names exactly what is blocking it.

The single reversal primitive is **`UnappliedCashService.reverse(paymentId, attribution)`**.
It is the only code path permitted to void an `UNAPPLIED_RECEIPT`, and it:

1. guards on `payment_kind = 'UNAPPLIED_RECEIPT'`;
2. refuses with the 409 above when live consumptions exist;
3. voids the receipt's GL group via
   `AccountingService.voidJournalLinesByReference(db, 'UNAPPLIED_RECEIPT', paymentId)`
   — `reference_id` is the payment id, because a receipt's GL group hangs off
   the payment itself rather than off an application row;
4. voids the `payments` row; and
5. rebuilds the customer ledger.

`Payment.delete` is left unchanged and is never routed to for an
`UNAPPLIED_RECEIPT`, precisely because it knows nothing about
`credit_source_consumptions` and would leave consumption rows live against a
voided source.

Un-apply is out of scope for this change.

---

## 6. Invariants

| ID | Assertion |
|---|---|
| **F** | `abs(GL(1100)+GL(1110)) == abs(Σ current_balance − Σ credit_balance)` — **unchanged**. This feature writes neither column on receipt |
| **K** | `GL(2110) == Σ remaining_amount` over live `UNAPPLIED_CASH` sources, credit-normal |
| **L** | For every source, `remaining_amount == credited_amount − Σ active consumption amounts`. Computed from `credit_source_consumptions` in code, since the generated column alone cannot detect a missing base-counter update |
| **M** | For every source, `refunded_amount <= credited_amount` **and** `0 <= refundable_cash_amount <= remaining_amount` |
| **N** | Per receipt: `Σ payment_allocations (voided_at IS NULL) <= payment.amount` |

**F's pre-existing 1800.00 gap is untouched by this change.** It is a separate
data-repair decision and out of scope.

---

## 7. Period close

| Operation | Rule | Status on violation |
|---|---|---|
| Receive | `assertPeriodNotClosed(receiptDate)` | 409 `PERIOD_CLOSED` |
| Apply | `assertPeriodNotClosed(applyDate)` — new date, independent of the receipt's date | 409 `PERIOD_CLOSED` |
| Refund | `assertPeriodNotClosed(refundDate)` — new date | 409 `PERIOD_CLOSED` |
| Reverse | the receipt's own `payment_date` must be open | 409 `PERIOD_CLOSED` |

`AccountingService.assertPeriodNotClosed` throws a **plain `Error` carrying only
a message string**, not a typed error with a status code. Mapping it onto the
409s above is new work inside `UnappliedCashService`, called out here as
outstanding rather than presented as existing behaviour.

`getClosedPeriodCovering` blocks only a genuinely closed period. A date falling
outside every existing period auto-creates an open one (ACC-11), which is why a
receipt dated in a period that is later closed can still be applied or refunded:
both post on a new date. Only reversal is blocked, because it must void the
original dated entry.

Cash received in a period that later closes may still be applied or refunded,
because both post on a new date. It may **not** be reversed, because reversal
must void the original dated entry.

---

## 8. Migration

`108_unapplied_customer_payments.sql`, registered in `config/database.ts`.

1. Create `2110` if absent.
2. Create the three new tables (§3).
3. Add `payments.payment_kind` (§3.4).
4. Backfill `payment_kind`:
   - `amount < 0` → `REFUND` — matches the 6 historical rows (E7).
   - `payment_method = 'Credit'` → `CREDIT_APPLICATION` — matches **zero**
     rows today (E6). Kept for completeness; it is not load-bearing.
   - everything else → `RECEIPT`.
5. Backfill `customer_credit_sources` for existing return credit:
   for each non-voided `RETURN` ledger row with `credit > 0`, insert a
   `RETURN_CREDIT` source with `credited_amount = credit`,
   `consumed_amount` = credit drawn by `CREDIT_OFFSET` applications against the
   same customer, and `refundable_cash_amount = 0`.

   **Do not validate this against `credit_balance`.** Revision 5 proposed
   failing closed if the two disagreed. Measured, they disagree for all five
   customers, so that guard would block the migration permanently:

   | customer | RETURN credit | REFUND debit | CREDIT_OFFSET | credit_balance |
   |---|---|---|---|---|
   | 1 | 1450.20 | 1200 | 0 | 0 |
   | 12 | 2400 | 2300 | 0 | 0 |
   | 13 | 1200 | 400 | 0 | 0 |
   | 14 | 1200 | 0 | 0 | 0 |
   | 15 | 2300 | 550 | 1800 | 0 |

   `credit_balance` is zero everywhere and tracks none of this history — not for
   customer 12, where 2400 granted less 2300 refunded would leave 100. Customers
   1, 12, 13 and 14 have no invoice offsets at all and still read 0, so this is
   not consumption: the column never accumulated for these rows. It is not a
   historical record and cannot arbitrate the backfill.

   The backfilled rows are **provenance only** and are deliberately inert:
   `refundable_cash_amount = 0` keeps them out of §5.3's refund draw, and §2's
   `availableCredit` counts only `kind='UNAPPLIED_CASH'`, so they contribute
   nothing to what a customer may spend or apply. They exist solely so that a
   future refund of genuinely-cash-backed store credit has a row to draw from,
   and so historical grants are not invisible.

   Validate instead on ledger self-consistency: per customer,
   `RETURN credit >= CREDIT_OFFSET credit` (so `consumed_amount` never exceeds
   `credited_amount`), which holds for all five.

## 9. Backfill of historical `CREDIT_OFFSET` applications

Historical credit applications created **no `payments` row** at all — invoices 52,
54 and 59 carry `credit_offset` values, and two `CREDIT_OFFSET` ledger rows exist
(E4). There is therefore nothing to classify in `payments`: no row, no
`payment_kind`. The `CREDIT_OFFSET` reference type stays as-is and the existing
invoice-creation path keeps consuming `credit_balance` unchanged.

This is safe precisely because §2 keeps `credit_balance` store-credit-only.

## 10. Out of scope

- Invoice 49's `je#198` correction and the physical-receipt question
- The pre-existing 1800.00 invariant F gap
- Account `1110` classification
- Strategy C′
- Frontend
- Historical GL or inventory repair
- Un-apply

---

## 11. Verification plan

| # | Test | Expectation |
|---|---|---|
| 1 | Receive 500 unapplied for a customer with zero balances | source created, `credit_balance` unchanged, F still passes |
| 2 | Receive, then `expectAllInvariantsHold` | no new violation |
| 3 | Apply 400 of a 500 source | Dr `2110` / Cr `1100`; `remaining_amount` 100; invoice balance down 400 |
| 4 | Apply 1500 against a 500 receipt | **409**, receipt-ceiling assertion (§5.2) fires |
| 5 | Apply 600 of a 500 source | **409**, per-source ceiling fires |
| 6 | Invoice created while an unapplied source exists | auto-offset draws **only** `credit_balance`, never cash (BLOCKER 2 regression) |
| 7 | Reverse a receipt with live consumptions | 409 naming source and invoices |
| 8 | Reverse a fully unapplied receipt | succeeds; `UNAPPLIED_RECEIPT` group voided |
| 9 | Refund draining `Σ refundable_cash_amount` exactly | succeeds; `refundable_cash_amount` 0 |
| 10 | Refund exceeding refundable cash | 409; M holds |
| 11 | Return-credit source refunded | 409 — `refundable_cash_amount` is 0 |
| 12 | Void an apply | base counters restored **and** compensating row inserted in one transaction; `remaining_amount` returns to pre-apply; L holds |
| 13 | Corrupt `consumed_amount` without a consumption row | L fails, proving L is not delegated to the generated column |
| 14 | Apply replayed with the same key | returns the same `credit_applications` row; no second GL entry |
| 15 | Apply, refund, reverse in a closed period | each returns the §7 status |
| 16 | Apply 400, then attempt a second apply of 400 against the same 500 source | **409** — proves §5.2 step 5 moved `consumed_amount`, so `remaining_amount` fell to 100 |
| 17 | Apply 400, then refund 400 | **409** — refundable cash fell with `consumed_amount`; the receipt holds no refundable cash once applied |
| 18 | Apply 400 against a customer owing 499.80 | `current_balance` falls to 99.80; `GL(1100)` falls by 400; F still passes |
| 19 | Apply spanning two sources in one call | both counters move; one `UNAPPLIED_APPLY` group; a single void by `credit_applications.id` clears every line |
| 20 | Receive 500, apply 400, then refund the remaining 100 | **succeeds**, leaving `remaining=0, refunded=100, refundable=0`. This is the case revision 4's schema rejected outright (`100 <= 0`) |
| 21 | Receive 300, refund 300 in full without applying | **succeeds**, leaving `remaining=0, refunded=300, refundable=0` |
| 22 | Attempt to refund beyond `credited_amount` | rejected by `c_refund_le_credited` |
| 23 | Migration executes the §3.1 `CREATE TABLE` verbatim | CHECKs present in `sqlite_master`; dropping them fails a test |
| 24 | Run §8's backfill, then assert each customer's spendable credit | **unchanged** by the migration — backfilled `RETURN_CREDIT` rows are `refundable_cash_amount = 0` and `kind != 'UNAPPLIED_CASH'`, so §2's `availableCredit` ignores them. Customer 12 gains no visible 2400 |
| 25 | Attempt to refund against a backfilled `RETURN_CREDIT` source | 409 — §5.3's `refundable_cash_amount >= :drawn` guard |
| 26 | Migration validation | asserts per-customer `RETURN credit >= CREDIT_OFFSET credit`; must **not** read `credit_balance`, whose divergence is expected and benign |
| 27 | Baseline the invariant suite before writing any feature test | record which invariants are **already** failing. F fails by exactly 1800.00 today, independent of this feature |

### 12.1 Assert no *new* violations, never absolute green

Reproduced the collector's own arithmetic against live data: `arImbalances()`
returns a violation today, with `glBalance = 3499.80` against
`custBalance = 1699.80` — a gap of 1800.00. E1 ties for all five customers, so
the gap is not a ledger-drift symptom; it is simply pre-existing.

The suite therefore **cannot** be green before this feature, and a test written
as `expect(expectAllInvariantsHold()).toBe(true)` would fail on a condition this
change did not cause. Tests must instead assert that the violation set is
**unchanged** relative to a baseline captured at the start:

```
const before = expectAllInvariantsHoldViolations();   // recorded per test file
... run the feature ...
expect(after.filter(v => !before.some(b => b.label === v.label))).toEqual([]);
```

Specifically: no new violation labels may appear, and F's diff must remain
exactly 1800.00 — not merely "not worse". Asserting the exact figure catches a
feature that perturbs the gap by a coincidentally offsetting amount.

Two things are forbidden here: weakening a check to force it green, and deleting
a failing assertion to clear the suite. Both turn a real pre-existing defect into
an invisible one. The 1800.00 gap is a data-repair decision recorded in §10, and
this feature neither causes nor fixes it.

---

## 12. Open decisions for the user

1. **Un-apply.** Currently unreachable once applied. If operators will need it,
   it is a separate change with its own reversal-ordering rules.
2. **Account 1110.** Left as-is per instruction; it remains a documented
   asset/liability mismatch.
3. **The 1800.00 F gap.** Repair or accept as a known baseline?