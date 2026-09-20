# Transaction Reversal Rules (Implementation Specification)

**Status:** Phases 1–5 implemented and green. Phase 4 complete.
**Scope:** Every destructive, cancellation, void, correction, refund, settlement-reversal, and reversal path.

This document is the **single implementation specification** for all delete/cancel/void/reverse operations.

No destructive path may be added or changed without conforming to these rules.

The reference implementation is `Purchase.void` (server/src/models/Purchase.ts).

---

# 1. Non-negotiable rules

## 1.1 Financially-touched means never hard-delete

Once a transaction has affected **stock, AR/AP, subledger, GL, cash, payment allocations, refunds, settlements, or any other accounting/financial relationship**, destructive operations must void/reverse it and retain the original record.

Hard delete is allowed only for genuinely pre-financial drafts and master data that has never participated in a financial or operational transaction.

Examples of potentially hard-deletable pre-financial records:

* Draft quotations
* Draft sales orders
* Draft purchase orders
* Their pre-financial line items
* Pre-financial salary drafts
* Unused expense categories
* Other records explicitly proven to have no financial, stock, or transactional relationships

When in doubt, **soft-void/reverse; never hard-delete**.

---

## 1.2 One reversal primitive per document type

Every path that removes, cancels, voids, or reverses a document must consume the **same reversal primitive**.

This includes:

* Dedicated cancellation endpoints
* Parent cancellation
* Bulk cancellation
* Model-level deletion
* Administrative reversal
* Related workflow cancellation

There must be exactly one authoritative reversal implementation for each financial document type.

Example:

```text
Invoice cancellation
    ↓
InvoiceModel.cancelInvoiceInternal(...)
    ↑
cancelInvoice endpoint
SO.cancel
other approved callers
```

No caller may duplicate part of the reversal logic.

---

## 1.3 All-or-nothing reversal

A reversal must perform all required operations inside **one database transaction**.

Typical sequence:

```text
guards
↓
begin transaction
↓
reverse subledger
↓
void canonical GL
↓
void legacy GL references
↓
reverse/restore stock
↓
create reversal stock movements if required
↓
rebuild balances
↓
stamp reversal metadata
↓
activity log
↓
commit
```

Any failure must throw and roll back the entire operation.

**Warn-and-continue is forbidden** for required reversal steps.

A successful API response must mean the entire reversal committed successfully.

---

## 1.4 Paid/financially-linked documents lock

A document with an **active financial relationship** must not be cancelled or deleted until that relationship has been reversed through its own protected primitive.

This includes:

* Active payments
* Active payment allocations
* Active refunds
* Active settlements
* Active AR/AP allocations
* Other financial links that would become orphaned by cancellation

Cached fields such as `paid_amount` may be used as guards, but they are **not the ultimate source of truth**.

The authoritative test is whether active, non-voided financial relationships exist.

No destructive path may leave:

* An active payment whose invoice is cancelled
* A live allocation pointing to a cancelled/voided document
* Active payment GL while the related sale revenue GL is voided
* Active refund relationships against a voided payment/document
* Any orphaned financial relationship

Payments must be reversed through their own protected reversal primitive, or explicitly unallocated where the business workflow permits it.

---

## 1.5 Returned stock locks

A document with returned quantity must not independently reverse the original stock effect.

If:

```text
returned_amount > 0
```

the original document cannot be cancelled/voided until the associated return history has first been reversed through its own reversal primitive.

The return reversal must occur first so that stock can be attributed exactly.

A cancellation must never:

```text
restore original sold stock
+
ignore existing return
```

because that can duplicate stock.

---

## 1.6 Append-only subledgers

`customer_ledger` and `supplier_ledger` are append-only.

They must never be hard-deleted as part of a reversal.

A reversal appends an equal-and-opposite ledger row containing appropriate reversal attribution, such as:

```text
reversed_by
reference_type
reference_id
```

Running balances must then be rebuilt from the ledger chain.

Derived totals must be recomputed from the ledger chain and must never be manually patched merely to make the displayed balance correct.

---

## 1.7 GL voiding must cover both accounting stores

`journal_lines` is the **canonical accounting source of truth**.

`journal_entries` is the legacy/audit header store and must remain synchronized with the canonical accounting records.

Canonical GL must be voided using:

```text
voidJournalLinesByReference(
    db,
    refType,
    refId,
    attribution
)
```

Legacy GL rows linked to the document must also be voided in the same transaction using the appropriate mechanism, such as:

```text
StockMovementModel.voidJournalEntry
```

Legacy links may originate from:

* `journal_entry_id` on stock movements
* `reference_type/reference_id`
* Other explicitly supported historical links

A reversal that voids only one accounting store is incomplete.

### Accounting source-of-truth rule

All accounting balances and reports must ultimately derive from `journal_lines`.

Code must not treat `journal_entries` as an independent accounting ledger or calculate balances directly from its rows.

---

## 1.8 Reversal neutrality

A reversal must economically negate the original transaction.

It must not create additional:

* Revenue
* Expense
* COGS
* Profit/loss
* AR
* AP
* Cash
* Inventory
* Equity

merely because the reversal implementation uses stock adjustments, journal entries, or other technical mechanisms.

For example:

```text
Original sale:

Dr AR             100
Cr Revenue        100

Dr COGS            60
Cr Inventory       60
```

Cancellation must economically produce:

```text
Dr Revenue         100
Cr AR              100

Dr Inventory        60
Cr COGS             60
```

If a reversal creates an intermediate stock movement that posts GL, the resulting accounting must still be economically neutral.

---

## 1.9 Server-side idempotency

Idempotency is a server-side requirement.

Every destructive endpoint must re-check the document's current state **inside the transaction**.

UI hiding is never a guard.

Already reversed/voided/cancelled records must not be reversed a second time.

A second destructive request must return a **4xx response**, not perform a second reversal and not produce a 500 error.

---

## 1.10 Balance rebuilds must throw

The following operations are mandatory parts of the reversal:

```text
rebuildLedgerBalances
recalcCustomerBalanceFromLedger
SupplierLedgerModel.rebuildBalances
invoice balance/status rebuild
other authoritative balance rebuilds
```

If any required rebuild fails, the transaction must throw and roll back.

Warn-only rebuilds are forbidden.

If a rebuild is currently implemented as:

```text
try {
    rebuild()
} catch {
    console.warn(...)
}
```

that path is non-compliant and must be changed to throw.

---

## 1.11 Reporting filters follow the actual doctype/reference

Reports must identify reversal entries using the **actual reference metadata written by the reversal**.

Do not infer reversal type solely from document status.

For example, COGS reversal recognition must include every supported historical/current reversal reference type, including:

```text
INVOICE_CANCEL
SO_CANCEL
```

where applicable.

Reports reading source tables must exclude voided/cancelled records exactly as the corresponding active grid/listing does.

Payment, salary, allocation, refund, stock, and accounting reports must apply the same active/voided semantics as their source screens.

---

## 1.12 Refunds are capped by collected cash

A customer cash refund may never exceed the amount the customer actually paid and that remains refundable.

Use the authoritative refundable amount:

```text
refundAmount =
    min(
        netReturn,
        PaymentModel.refundableOnInvoice(invoiceId)
    )
```

`refundableOnInvoice` must account for prior negative refund allocations so repeated partial returns cannot refund the same cash twice.

The outstanding-AR portion of a return is **not cash**.

For an unpaid or partially unpaid invoice:

```text
return
↓
reduce/clear AR through RETURN ledger + Cr AR
↓
remaining customer credit stays on account
↓
cash refund cannot exceed collected cash
```

It must never create a cash refund merely because the returned goods have a monetary value.

Supplier-side behavior follows the equivalent rule:

```text
SupplierRefundModel.create
```

must reject refunds exceeding the currently refundable supplier credit.

---

## 1.13 Reversal audit lineage is mandatory

Every reversal must preserve an unambiguous relationship between the original transaction and its reversal.

The reversal must identify, where applicable:

* Original document
* Original transaction/reference ID
* Reversal type
* Reversal user
* Reversal timestamp
* Reversal reason
* Reversal movement/reference
* Original GL reference
* Related ledger reversal

Reversal records must remain auditable after the original transaction is cancelled.

---

## 1.14 Active records must never reference voided records

The following invariant must always hold:

> No active financial or operational relationship may reference a voided/cancelled source.

Examples:

```text
active payment
    → cannot reference voided invoice

active allocation
    → cannot reference voided payment

active allocation
    → cannot reference cancelled invoice

active GL line
    → cannot remain associated with a fully voided financial transaction

active return
    → cannot reference a voided source transaction

active stock relationship
    → cannot depend on a voided movement
```

This invariant must be enforced both by reversal logic and by reporting/query filters.

---

# 2. Reference pattern (`Purchase.void` shape)

A typical financially-touched reversal follows this structure:

```text
guards
  - exists?
  - already voided?
  - active payments?
  - active allocations?
  - returns?
  - sold/consumed stock?
  - other document-specific dependencies?

db.transaction:

  reverse supplier_ledger row(s)
      -> append-only
      -> reversed_by/reference attribution

  void canonical GL journal_lines
      -> reference = PURCHASE

  void legacy journal_entries links
      -> journal_entry_id on movements
      -> reference links where applicable

  exact-batch stock restore
      -> stock_batches.quantity_remaining

  reversal stock movements
      -> ADJUSTMENT where required
      -> ensure resulting GL is economically neutral

  rebuild balances
      -> throw on failure

  stamp void attribution
      -> voided_at
      -> voided_by
      -> void_reason

  activity log

commit
```

The exact sequence may differ by document type, but all required effects must remain atomic.

---

# 3. Phase 1 fixes (C1–C4)

## C1 — Invoice cancellation (CRITICAL)

**Where:**

`invoiceController.cancelInvoice`

`POST /api/invoices/:id/cancel`

### Requirements

* Block when active payments/allocations exist.
* `paid_amount > 0` may be used as an additional guard, but active payment/allocation state is authoritative.
* Block when `returned_amount > 0`.
* Returns must be voided first through their own reversal primitive.
* Reverse stock inside the transaction via:

```text
InvoiceModel.reverseStockForItems(
    db,
    items,
    invoice_no,
    userId,
    INVOICE_CANCEL
)
```

* Void `INVOICE` and `INVOICE_RETURN` journal lines by reference.
* Use a must-void guard when the expected accounting total is greater than zero.
* Append `CANCELLATION` credit to `customer_ledger`.
* Rebuild customer balances.
* Rebuild must throw on failure.
* Keep the existing already-Cancelled guard.
* Preserve full reversal audit lineage.

---

# 4. C4 — Sales Order cancellation (CRITICAL)

**Where:**

`SalesOrder.cancel`

`POST /api/sales/:id/cancel`

### Requirements

Extract the C1 cancellation logic into:

```text
InvoiceModel.cancelInvoiceInternal(
    db,
    invoice,
    userId
)
```

The shared primitive owns:

* Guards
* Active payment/allocation checks
* Return checks
* Stock reversal
* Canonical GL void
* Legacy GL void
* Customer ledger cancellation
* Balance rebuild
* Reversal attribution

Both:

```text
cancelInvoice
SO.cancel
```

must use the same primitive.

`SO.cancel` keeps its own sales-order guards but must not:

* Raw-update invoice status
* Reverse invoice stock independently
* Duplicate GL reversal
* Duplicate ledger reversal

`SO_CANCEL` must be supported wherever historical COGS/reversal reporting requires it.

---

# 5. C3 — Purchase Order cancellation (CRITICAL)

**Where:**

`PurchaseOrder.updateStatus`

`POST /api/purchase-orders/:id/status`

When transitioning to `Cancelled` from `Submitted` or `Partially Received`:

* Append an equal-and-opposite supplier ledger entry.
* Rebuild supplier balances.
* Perform the operation inside the transaction.
* Rebuild failures must throw.

The existing valid-transition matrix must prevent:

```text
Cancelled → Submitted
Cancelled → Partially Received
```

or any other transition that could repost financial effects.

No cancellation path may double-post the supplier reversal.

---

# 6. C2 — Production deletion (CRITICAL)

**Where:**

`Production.delete`

`DELETE /api/production/:id`

Production records that have financial/stock effects must not be hard-deleted without first reversing those effects.

Inside the transaction:

* Find the production output stock movement.
* Match using:

```text
movement_type = 'PRODUCTION'
reference_docno = production_no
quantity > 0
```

* Read `journal_entry_id`.
* Void the associated legacy `journal_entries` row through:

```text
StockMovementModel.voidJournalEntry
```

* Void canonical `journal_lines` using the production output movement reference.
* Preserve audit lineage.

The `movement_type` must be used rather than assuming `reference_doctype` contains the enum. The doctype column contains the human label (`Production`).

### Missing GL guard

If the output movement is missing or has no `journal_entry_id`:

* If `total_batch_cost = 0`, it may be skipped where no accounting effect exists.
* If `total_batch_cost > 0`, throw.

Never silently ignore a missing accounting link when an accounting effect should exist.

---

# 7. Phase 2 fixes (C5–C7)

## C5 — Employee loan deletion / repayment void (HIGH)

**Where:**

```text
employeeController.deleteLoan
employeeController.voidLoanRepayment
```

### deleteLoan

* Never hard-delete a financially-touched loan.
* Void `LOAN_DISBURSEMENT` journal lines by reference.
* This must work even for pre-link-backfill loans with `journal_entry_id = NULL`.
* Soft-void the loan:

```text
voided_at
voided_by
void_reason
```

* Keep the repayment-history guard.
* Return 409 when repayments exist and the business rule requires repayments to be reversed first.
* Add already-voided guard.

### voidLoanRepayment

* Void `LOAN_REPAYMENT` GL by reference.
* Restore the loan balance.
* Soft-void the repayment.
* Never hard-delete the repayment.
* Preserve audit lineage.

Written-off restoration remains as currently implemented where no GL effect exists.

### Migration

```text
add-employee-loan-void-columns.sql
```

---

# 8. C6 — Payment.delete and deleteSalaryPayment hard-delete (HIGH)

## Payment.delete

`Payment.delete` must never hard-delete a financially-touched payment.

It must:

* Soft-void the payment.
* Soft-void its allocations.
* Append the required subledger reversal.
* Void canonical GL by reference.
* Void legacy GL where applicable.
* Rebuild invoice balance/status.
* Rebuild customer balance.
* Rebuild ledger chain.
* Rebuild supplier balances where applicable.
* Throw on every required rebuild failure.
* Commit only when all steps succeed.

### Supplier-side allocations

The following must be soft-voided:

```text
payment_allocations
purchase_allocations
po_allocations
```

using:

```text
voided_at
voided_by
void_reason
```

They must never be deleted merely because the payment was voided.

All paid-amount reads must exclude voided allocations:

```text
AND voided_at IS NULL
```

This includes:

* PurchaseOrder
* Purchase
* PurchaseReturn
* Payment receipt allocation lists
* Supplier-payment validation
* Other allocation-based financial calculations

`Purchase.void` must count only active allocations when determining whether recorded payments still exist.

---

## deleteSalaryPayment

Salary payments are financially touched because they affect:

* GL
* Cash
* Salary/payment history

Therefore they must never be hard-deleted.

`deleteSalaryPayment` must:

```text
db.transaction:

  void GL
  ↓
  soft-void salary_payments
  ↓
  stamp void metadata
  ↓
  activity log
```

Any failure rolls back the entire operation.

### Migration

```text
add-payment-salary-void-columns.sql
```

### Reporting

Reports reading:

* payments
* salary payments
* cash flow
* till/walk cash

must exclude voided records using the same active/void semantics as their corresponding listings.

---

# 9. C7 — paySalary auto-advance silent GL failure (HIGH)

**Where:**

`employeeController.paySalary`

The auto-advance block must not catch and suppress GL failures.

The following must occur in one transaction:

```text
advance row insert
↓
GL posting
↓
journal_entry_id link
```

If GL posting fails:

```text
throw
↓
rollback advance row
↓
rollback salary payment
```

No successful response may be returned when the corresponding GL posting failed.

---

# 10. Phase 3 — GL unification

`journal_lines` is the canonical GL.

`journal_entries` remains the legacy/audit header store.

Rule 7 applies to both.

`backfillGlUnification`, registered after `fn.backfillGlPreposting` in `config/database.ts`, must remain idempotent.

It performs two passes inside one transaction:

1. Re-link orphaned/mis-linked `journal_lines` groups to fresh `journal_entries` headers.
2. Migrate line-less legacy `journal_entries` rows into balanced canonical `journal_lines`.

Post-conditions must throw on:

* Orphaned journal lines
* Mis-linked journal lines
* Unbalanced journal groups

`AccountingService.postEntry` must create the `journal_entries` header first and use its AUTOINCREMENT ID so every new posting has both:

```text
journal_entries
journal_lines
```

New stock postings must use:

```text
AccountingService.postLegacyStockEntry
```

including:

* StockMovement adjustments
* Production output
* PhysicalCount.completeCount

These must write the legacy header and canonical lines atomically.

Production deletion must:

* Void canonical lines by reference.
* Void the legacy header where linked.
* Preserve reversal lineage.

`getAccountBalance` and `getAllAccountBalances`, and every report using them, must read `journal_lines` only.

No new code may introduce accounting calculations directly from `journal_entries`.

---

# 11. Phase 4 — Stock and workflow reversals

## Stock-transfer reversal primitive

`StockMovementModel.voidTransfer`

`POST /api/inventory/stock-transfers/:movementNo/void`

Transfers have no GL effect.

The reversal must:

* Restore the source batch consumed by the OUT leg.
* Match using `movement_no`, because the OUT leg's `reference_docno` is NULL.
* Draw down the mirrored TRANSFER batch at the destination.
* Refuse reversal if transferred units were already consumed at destination.
* Append a `TRANSFER_VOID` adjustment pair referencing the original movement.
* Stamp void metadata.

Guards must execute inside the transaction:

* Not found → 400
* Already voided → 400
* Destination quantity already consumed → 400

The reversal must never drive stock negative.

---

## Status-machine validation

Sales Orders and Quotations must enforce transition matrices.

Direct status edits must not bypass workflow transitions.

Terminal states cannot be revived.

Any invalid transition must return **400**, not 500.

---

## Goods-receipt void primitive

`PurchaseOrderModel.voidGoodsReceipt`

`POST /api/purchase-orders/:id/receipts/:receiptId/void`

A goods receipt cannot be voided if any of its FIFO batch layers have already been consumed.

If safe to reverse:

* Draw down receipt stock.
* Zero the receipt's stock batch layers.
* Retain the layers for audit.
* Append `GOODS_RECEIPT_VOID` / `PURCHASE_RETURN` movement as implemented.
* Roll back `purchase_order_items.received_quantity`.
* Recompute PO status.
* Rebuild `items.current_stock`.
* Stamp:

```text
voided_at
voided_by
void_reason
```

GL reversal: each receipt posts its own financial GL at receipt time (Dr 1200 Inventory / Cr 2000 AP for the received value, reference_type `GOODS_RECEIPT`), and the void reverses exactly that group via `voidJournalLinesByReference`. Receipts created before that posting existed have no `GOODS_RECEIPT` GL group, so the void is a no-op there.

Migration:

```text
add-goods-receipt-void-columns.sql
```

---

## Master-data FK deletion guards

Master-data deletion must fail cleanly before the database attempts an invalid FK delete.

Supplier deletion must check:

* Purchases
* Non-voided payments
* Supplier ledger
* Supplier refunds
* Purchase returns through source purchases

Warehouse deletion must check:

* In-stock balances
* Stock movements
* Live stock batches
* Purchases
* Physical counts
* Goods receipts
* Productions

Customer/item deletion remains guarded by existing transaction/soft-delete rules.

FK/state violations must return a human-readable **400**, not an opaque 500.

---

## Count-correction workflow

`PhysicalCountModel.correctCount`

`POST /api/inventory/physical-counts/:id/correct`

Posted counts are immutable.

Counted quantities must never be edited in place.

A correction must:

1. Verify the count is Completed.
2. Require a snapshot row for every corrected item.
3. Void the original completion's GL.
4. Restore the original stock/batch effects.
5. Append equal-and-opposite correction movements.
6. Re-apply the corrected quantities.
7. Rebuild stock balances.
8. Rebuild accounting effects.
9. Stamp correction attribution.

Shortage correction must consume FIFO-oldest layers at actual cost.

Surplus correction must add an `ADJUSTMENT_CORRECTION` cost layer.

A correction must refuse with 400 if the original surplus stock was already consumed in a way that makes reversal unsafe.

Correction is single-shot:

```text
already corrected → 400
```

The consumed FIFO layer provenance must be preserved so reversing a shortage restores the exact layer consumed by the original count.

---

# 12. Phase 5 — Regression and invariant enforcement

## Accounting invariant regression suite

`accountingInvariants.test.ts` must drive real lifecycle operations through actual endpoints.

After every significant operation, assert:

### A — GL balance

Every journal reference group must satisfy:

```text
SUM(debit) == SUM(credit)
```

### B — Customer balance

```text
customers.current_balance
==
authoritative customer_ledger balance
```

### C — Invoice payment balance

```text
invoices.paid_amount
==
SUM(active/non-voided allocations)
```

### D — Supplier balance

```text
suppliers.current_balance
==
authoritative supplier_ledger balance
```

### E — Stock balance

```text
stock_balances.quantity
==
SUM(stock_batches.quantity_remaining)
```

### F — No active allocation references a voided source

Examples:

```text
active allocation
→ voided payment

active allocation
→ cancelled invoice

active allocation
→ voided purchase
```

must never exist.

### G — No active GL remains for a fully voided financial transaction

When a transaction's accounting effect has been completely reversed, there must be no active canonical GL lines representing the original economic effect.

---

# 13. Concurrency / double-fire testing

Every destructive endpoint must be tested with two immediate requests.

Examples:

```text
invoice cancel
payment delete
PO cancel
GRN void
stock-transfer void
count correction
loan void
salary-payment void
return void
```

Expected behavior:

```text
first request → successful reversal

second request → 4xx
```

The second request must not:

* Add another ledger reversal
* Add another GL reversal
* Restore stock twice
* Drain stock twice
* Change balances
* Modify the original reversal metadata

All accounting, ledger, and stock invariants must still hold after the second request.

State-machine violations must also return 400 rather than 500.

---

# 14. Verification script

`npm run verify:reversal-rules`

must remain a required regression gate.

It must cover all implemented reversal primitives and their important invariants.

Current verification includes the Phase 4/5 cases for:

* Goods-receipt void
* Stock-transfer void
* Physical-count correction
* Stock/batch consistency
* GL/reference consistency
* Double-void/correction rejection
* Costing preservation

The verification gate currently contains **81 cases**.

New destructive/reversal functionality must add regression coverage rather than relying solely on manual verification.

---

# 15. New destructive endpoint requirements

Every new destructive endpoint must ship with all of the following:

### A. Server-side state guard

The endpoint must validate current state inside the transaction.

### B. Single reversal primitive

The endpoint must call the document's existing authoritative reversal primitive.

If none exists, create one before implementing the endpoint.

### C. Atomic transaction

All financial, stock, ledger, GL, allocation, and status changes must commit or roll back together.

### D. No warn-only required steps

Required reversal failures must throw.

### E. 4xx for invalid/double-fire requests

Expected state conflicts must return 4xx, never 500.

### F. Audit lineage

The reversal must preserve:

```text
original reference
reversal reference/type
user
timestamp
reason
```

where applicable.

### G. Reporting consistency

Reports must exclude voided/cancelled records consistently with operational listings.

### H. Regression test

At least one automated test must exercise the new destructive path and verify the relevant accounting/stock invariants.

---

# 16. Final accounting and stock invariants

At all times after a successful committed reversal:

```text
GL:
Every journal reference group is balanced.

Customer:
Customer balance equals the authoritative customer ledger.

Supplier:
Supplier balance equals the authoritative supplier ledger.

Invoice:
Paid amount equals active/non-voided allocations.

Payments:
Voided payments and allocations no longer contribute to balances.

Stock:
stock_balances == sum(stock_batches.quantity_remaining)

Allocations:
No active allocation references a voided/cancelled source.

GL:
No active accounting effect remains for a fully reversed transaction.

Audit:
Every reversal remains traceable to its original transaction.

Idempotency:
A second destructive request cannot create another economic effect.
```

These invariants are more important than the implementation details of any individual controller/model.

---

# 17. Audit completion status

Phases 1–5 are implemented and green.

Phase 4 is complete.

Remaining work is maintenance and regression protection.

Every future destructive endpoint must comply with this document before being considered complete.

The authoritative principles are:

1. **Financially touched → never hard-delete.**
2. **One reversal primitive per document type.**
3. **Atomic all-or-nothing reversal.**
4. **Active financial relationships block destructive operations.**
5. **Returned stock must be reversed through its own primitive first.**
6. **Subledgers are append-only.**
7. **`journal_lines` is the canonical accounting source of truth.**
8. **Both canonical and legacy GL references must be handled where applicable.**
9. **Reversals must be economically neutral.**
10. **All required balance rebuilds must throw on failure.**
11. **Refunds cannot exceed collected refundable cash.**
12. **Active records cannot reference voided/cancelled sources.**
13. **Every reversal must preserve audit lineage.**
14. **Server-side idempotency is mandatory.**
15. **Every new destructive path requires regression coverage.**
