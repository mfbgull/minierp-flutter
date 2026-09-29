# Supplier prepayments — technical specification

Status: **DESIGN ONLY — NOT IMPLEMENTED.**

Audit task 44 requires a specification before implementation. Nothing here has
been built. Current-behaviour claims were verified against the code.

---

## 1. Verified current state

| Fact | Evidence |
|---|---|
| Accounts payable is `2000` (liability/credit) | `add-gl-foundation.sql` |
| `supplier_ledger` mirrors `customer_ledger`: `transaction_type VARCHAR(50)`, **no CHECK constraint** | `create-supplier-ledger.sql:8` |
| Ledger types in use: `PURCHASE_ORDER, RECEIPT, PAYMENT, SUPPLIER_REFUND, SUPPLIER_REFUND_VOID` | grep across `src/` |
| Supplier payment GL: **Dr 2000 AP / Cr cash**, ACC-03, with `assertSufficientFunds` | `SupplierPaymentService.ts:74-92` |
| Supplier payments are stored **positive** and read as outflows via a `supplier_id IS NOT NULL` filter | `cashService.ts:216-224` |
| `payments` enforces `CHECK ((customer_id IS NULL) <> (supplier_id IS NULL))` | `add-payments-counterparty-check.sql:29` |
| Supplier payments may allocate against a **purchase order** *or* a purchase | `SupplierPaymentService.ts` `documentReferences` |
| `SupplierRefund` is the *opposite* flow: a supplier returning cash to us, Dr Cash / Cr 2000, sourced from a separate `supplier_refunds` table | `models/SupplierRefund.ts:14-19` |
| Supplier refunds already have a void lifecycle (`voidJournalLinesByReference`) | `models/SupplierRefund.ts:228-237` |
| **GL reconciliation asserts `AP (2000) == Σ latest supplier_ledger running balance`** | `models/Reports.ts:1297-1315` |
| **AP aging is rebuilt on `supplier_ledger`** (`basis: 'supplier_ledger'`) | `models/Reports.ts:332-403` |
| **Cash reconciliation asserts GL cash == `collectFlows` derivation, which reads the `payments` table** | `models/Reports.ts:1318-1336`, `cashService.ts` |
| `suppliers` has **no** `credit_balance` column — store credit is customer-only | `add-credit-balance.sql` |
| **Supplier prepayments do not exist** (no `prepaid`/`prepayment`/`supplier_advance` anywhere) | grep across `src/` |

---

## 2. A blocking bug found during this design

The cash reconciliation above is derived from the `payments` table. While
verifying how a prepayment would have to be recorded, `collectFlows` turned out
to have a live defect.

`collectFlows` splits every payment into a bounded in-window scan and a
pre-floor fold (default 90 days) that keeps balances exact for older rows. The
in-window queries are counterparty-aware:

- customer payments (`customer_id IS NOT NULL`): positive → inflow, negative → outflow
- supplier payments (`supplier_id IS NOT NULL`, always positive): → **outflow**

The pre-floor fold was **not**. It classified *every* positive `payments` row as
an inflow, so **a supplier payment older than 90 days counted as money coming
in**. The till was overstated by twice the payment, and the GL cash
reconciliation showed a permanent phantom delta. Every other pre-floor fold
(owner equity, employee loans, supplier refunds) is source-specific; this one was
the only sign-only fold.

Fixed in `cashService.ts` and pinned by a regression test in `cashTruth.test.ts`
("a supplier payment older than the 90-day fold floor stays an outflow"). This
is fixed here rather than merely documented because task 44 is unimplementable
safely on top of it — a prepayment is cash leaving the business, and backdating
one past the floor is entirely normal.

---

## 3. The mirror of task 43, and where it diverges

Task 43 specifies customer advances against a new liability account `2120`. A
supplier prepayment is the same idea seen from the other side, but the GL
treatment is **not** a mirror — it differs in account type, and that difference
is the whole design.

| | Customer advance (task 43) | Supplier prepayment (this task) |
|---|---|---|
| Who is owed | We owe the customer | The supplier is owed / we are owed back |
| Account type | **liability** (credit) | **asset** (debit) — cash paid ahead |
| New account | `2120 Customer Advances (Unearned)` | `2110 Supplier Prepayments` |
| Receipt | Dr Cash / Cr 2120 | Dr 2110 / Cr Cash |
| Application | Dr 2120 / Cr 1100 AR | Dr 2000 AP / Cr 2110 |
| Return of cash | Refund: Dr 2120 / Cr Cash | Supplier refund: **already exists** as `SupplierRefund` |

Reusing `2120` for both is rejected: a customer advance is a liability, a
supplier prepayment is an asset, and co-mingling them makes the balance sheet
meaningless in both directions.

**Symmetry that does hold:** neither may touch its respective ledger table.
`supplier_ledger` is the AP subledger behind AP aging and the `AP == Σ
supplier_ledger` reconciliation, exactly as `customer_ledger` is behind AR
aging. Writing a prepayment into `supplier_ledger` would break that invariant
and distort aging — a receivable we have already paid for is not a payable.

`2110` is free (verified: the live chart uses `1000, 1010, 1020, 1030, 1040,
1100, 1110, 1200, 1300, 2000, 2100, 3000, 3100, 3200, 3300, 4000, 4100, 4150,
5000, 6000, 6100, 6300, 7000, 7100, 7200–7204`; liabilities are `2000`/`2100`).

---

## 4. Data model (proposed — not created)

```sql
CREATE TABLE supplier_prepayments (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  prepayment_no   VARCHAR(50) NOT NULL UNIQUE,
  supplier_id     INTEGER NOT NULL REFERENCES suppliers(id),
  prepay_date     DATE NOT NULL,
  amount          DECIMAL(15,2) NOT NULL CHECK (amount > 0),
  applied_amount  DECIMAL(15,2) NOT NULL DEFAULT 0,
  payment_method  VARCHAR(50) NOT NULL,
  reference_no    VARCHAR(100),
  notes           TEXT,
  status          VARCHAR(20) NOT NULL DEFAULT 'OPEN',  -- OPEN | APPLIED | VOID
  voided_at       TIMESTAMP,
  voided_by       INTEGER,
  created_by      INTEGER,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CHECK (applied_amount <= amount)
);

CREATE TABLE supplier_prepayment_allocations (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  prepay_id    INTEGER NOT NULL REFERENCES supplier_prepayments(id),
  target_kind  VARCHAR(20) NOT NULL CHECK (target_kind IN ('purchase_order','purchase')),
  target_id    INTEGER NOT NULL,
  amount       DECIMAL(15,2) NOT NULL CHECK (amount > 0),
  applied_at   DATE NOT NULL,
  created_by   INTEGER
);

CREATE INDEX idx_prepay_supplier ON supplier_prepayments(supplier_id);
CREATE INDEX idx_prepay_date     ON supplier_prepayments(prepay_date);
CREATE INDEX idx_prepay_alloc    ON supplier_prepayment_allocations(prepay_id);
```

`target_kind` is required because the existing `documentReferences` already
allocates supplier payments against either a purchase order or a purchase, and a
prepayment must be able to follow the same path.

`supplier_prepayment_allocations` is an **event log, not current state** —
deliberately not unique on `(prepay_id, target_id)`, matching the decision in
task 43. A second tranche against an already-partially-settled document is
routine; cumulative ceilings are enforced in the transaction instead.

`payments` is **not** given a new column. The prepayment itself is written as a
`payments` row with `customer_id = NULL, supplier_id = <supplier>` and a
positive amount, which the existing `collectFlows` already classifies as an
outflow. That is what keeps the cash reconciliation intact.

---

## 5. GL postings

### 5.1 Prepayment (cash paid to a supplier in advance)

    Dr  2110   Supplier Prepayments
    Cr  <cash code>   (1010 / 1020 / 1030 / 1040)
    entry_date = prepay_date       reference_type = 'PREPAYMENT'

Must call `assertSufficientFunds` exactly as `SupplierPaymentService` does
(ACC-03): the till must actually hold the money leaving the business. This is a
genuine asymmetry with the customer side, where receipts add cash and no such
check applies.

### 5.2 Application to a purchase / purchase order

    Dr  2000   Accounts Payable
    Cr  2110   Supplier Prepayments
    entry_date = target document date      reference_type = 'PREPAYMENT_APPLICATION'

Dated at the **target document's** date so it lands in the same period as the
payable it settles — mirroring `postCreditOffsetEntry`, and required so the
`AP == Σ supplier_ledger` reconciliation is unaffected (the ledger is untouched
by the application; only the GL moves, and the document it nets against is the
one being settled).

### 5.3 Return of cash to us (supplier refunds it)

**No new posting.** `SupplierRefund` already implements this: Dr Cash / Cr 2000,
with a `supplier_refunds` row, `refund_expected` on the purchase return driving
it, and a working void lifecycle. A prepayment becomes refundable once consumed;
that transition is driven by the existing credit-note flow, not a new one.

### 5.4 Void

Void is a **reversal, never a delete**:

    Dr  <cash code>
    Cr  2110
    entry_date = void_date       reference_type = 'PREPAYMENT_VOID'

Only legal when `applied_amount = 0`. A partially applied prepayment cannot be
voided — reversing it would leave allocations posted against a dead document.

---

## 6. Business rules

| Rule | Enforcement |
|---|---|
| Amount > 0 | DB `CHECK` + service validation |
| Cash sufficiency | `assertSufficientFunds` (ACC-03), as `SupplierPaymentService` |
| Cash method whitelist | `assertPaymentMethod` (shared write primitive) |
| Application ceiling | open payable of the target document |
| Per-prepayment ceiling | `amount - applied_amount` |
| Application only to `OPEN` prepayments | service check |
| Target must belong to the same supplier | service check (PO and purchase) |
| Target must be unpaid and not cancelled | reuse existing checks |
| Void only when `applied_amount = 0` | service check |
| Closed period (H6) | `assertPeriodOpen` on every posting date |
| Idempotency-Key on all writes | P11 `normalizeIdempotencyKey` + `claimIdempotencyKey` inside the transaction |

### 6.1 Closed-period policy

Identical in structure to task 43. The application credits AP, so the guard
applies to the **target document's** period, not the date of application: H6
("a closed period must not gain new money movements, only lose them") means a
closed payable period cannot gain an AP credit retroactively. Prepayment and void
are dated when they occur and require only their own period to be open.

---

## 7. Reporting impact

| Report | Required change |
|---|---|
| **GL reconciliation — cash family** | Holds *only* if the prepayment is written to `payments`. This is the constraint that dictates the data model. |
| **GL reconciliation — AP (`2000`)** | Must be untouched. Requires that prepayments never enter `supplier_ledger`. |
| **AP aging** | Must exclude prepayments — cash already paid is not a payable. |
| **Balance sheet** | `2110` appears as a current asset, not netted into AP. |
| **Trial balance / general ledger** | Automatic from `journal_lines`. |
| **Cash flow / cash reconciliation** | Outflow at payment, correctly included. |
| **Supplier statement** | New section for prepayments, separate from the AP ledger. |
| **New: prepayments outstanding** | Aging by prepay date, per supplier and in total. |

Reconciliation check, as in task 43: `sum(open supplier_prepayments remaining)
== 2110 control-account balance`.

---

## 8. UI specification

1. **Supplier detail → Prepayments tab** — list with date, amount, applied,
   remaining, status; actions: apply, void.
2. **Record prepayment** — amount, date, method, reference, notes. Method
   selector must show only whitelisted cash methods.
3. **Apply to PO / purchase** — pick prepayment, pick target documents, enter
   partial amounts, show remaining capacity live.
4. **Void** — available only while nothing is applied.
5. **Refund path** — deliberately *not* built here. It is the existing
   supplier-refund flow; the UI should deep-link into it rather than duplicate it.
6. **Guard parity** — client-side ceilings are convenience only; the server stays
   authoritative, as in task 41.
7. **Separation from AP** — a prepayment must not be presented as a payable, for
   the same reason task 43 keeps advances out of the credit pool.

---

## 9. Regression matrix

`GL` = expected journal lines. `REM` = `amount - applied_amount`.

| # | Scenario | GL | Invariants |
|---|---|---|---|
| S1 | Prepay 1000 to supplier, cash | Dr 2110 1000 / Cr cash 1000 | `payments` row present, `customer_id` NULL; REM=1000 |
| S2 | Apply 400 to a purchase of 900 | Dr 2000 400 / Cr 2110 400 | REM=600; purchase balance 900→500 |
| S3 | Apply 1000 to a PO of 3000 | Dr 2000 1000 / Cr 2110 1000 | PO partially prepaid |
| S4 | Two prepayments applied to one document | separate allocations | never over-settles |
| S5 | Same prepayment applied twice to one document | two allocation rows | legitimate second tranche |
| S6 | Over-apply beyond document payable | **rejected** | unchanged |
| S7 | Over-apply beyond `REM` | **rejected** | unchanged |
| S8 | Apply to a document of a different supplier | **rejected** | supplier isolation |
| S9 | Apply to a cancelled purchase | **rejected** | unchanged |
| S10 | Apply to an unpaid-in-full purchase | **rejected** | no negative payable |
| S11 | Void an unapplied prepayment | Dr cash / Cr 2110 | status VOID; `2110` → 0 |
| S12 | Void a partially applied prepayment | **rejected** | GL would disagree |
| S13 | Prepay exceeding available cash | **rejected** | ACC-03 holds |
| S14 | Prepay in a closed period | **rejected** | H6 holds |
| S15 | Application to a document in a closed period | **rejected** | H6 holds |
| S16 | Prepayment, then goods received, then apply | sequence valid | ordering independent |
| S17 | Prepayment fully consumed, supplier refunds the rest | existing `SupplierRefund` flow | no new posting |
| S18 | Duplicate request, same key + payload | replayed, **one row** | one GL entry |
| S19 | Same key, different payload | **409** | unchanged |
| S20 | `sum(REM) == 2110 balance` | — | **control reconciliation** |
| S21 | `AP(2000)` GL still equals `Σ supplier_ledger` | — | **pre-existing invariant preserved** |
| S22 | Cash GL still equals `collectFlows` derivation | — | **pre-existing invariant preserved** |
| S23 | Prepayment dated > 90 days ago still counts as cash out | — | **the section-2 bug, guarded** |
| S24 | Prepayment never appears in AP aging | — | not a payable |
| S25 | Supplier prepayment does not affect customer AR/credit | — | no cross-contamination |

---

## 10. Open decisions requiring sign-off

1. **Applying against a purchase order vs a purchase.** The existing supplier
   payment path allows either. Applying a prepayment to a PO commits before
   goods are received, so a cancelled or short-received PO would leave the
   prepayment partly stranded. Recommend allowing it (it is how real purchase
   orders are paid) but requiring a reconciliation view for unapplied balances
   on closed POs.
2. **Interaction with supplier credit notes.** If a purchase return leaves the
   supplier owing us (`refund_expected`) while a prepayment is still open, the
   two could be netted. Recommend keeping them separate and requiring an explicit
   refund, matching current `SupplierRefund` behaviour; automatic netting would
   make the cash position surprising.
3. **Document numbering** for `prepayment_no`.
4. **Whether a prepayment may be applied across suppliers** (group payment).
   Recommend no.

## 11. Suggested implementation order (only once approved)

1. Migration: account `2110` + `supplier_prepayments` + allocations (idempotent).
2. `postPrepaymentEntry` / `postPrepaymentApplication` / `postPrepaymentVoid` in
   `accountingService.ts`, mirroring `postCreditOffsetEntry`.
3. Service with the section-6 rules inside one transaction, key claimed inside it,
   reusing `assertSufficientFunds`, `assertPaymentMethod`, `assertPeriodOpen`.
4. Routes + permissions + rate limiting consistent with `payments.ts`.
5. Server tests driven directly from S1–S25, including explicit assertions that
   the two pre-existing reconciliations (S21, S22) still hold.
6. Report changes (section 7) plus the section-7 reconciliation check.
7. UI.
