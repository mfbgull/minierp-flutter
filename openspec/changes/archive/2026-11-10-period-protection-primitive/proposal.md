# Closed Accounting Period Immutability — OpenSpec Proposal

## Purpose

Once an accounting period is closed, no server-side operation may silently
rewrite accounting history (GL, customer ledger, supplier ledger, payments,
invoices, expenses, returns, purchases, or owner transactions) belonging to
that period. The server must enforce this; UI hiding is insufficient.

## Current State (audit finding)

New postings are already blocked: `AccountingService.postEntry` auto-creates an
open period when needed, and if the entry date falls inside a closed period the
post succeeds because the closed period row is ignored by the open-period query.
However, **void, edit, cancel, reverse, and repost paths can still mutate closed
periods** because they lack period guards.

### Where `assertPeriodNotClosed` already exists

Verified by grep on the working tree (2026-10-07), not taken on trust from the
original snapshot. Fourteen files reference it:

| Operation | Guarded at |
|---|---|
| `OwnerCapital.update` / `.delete` | `models/OwnerCapital.ts` |
| `OwnerWithdrawal.update` / `.delete` | `models/OwnerWithdrawal.ts` |
| `Payment.update` | `models/Payment.ts`, `controllers/paymentsController.ts` |
| `Payment.delete` | `models/Payment.ts`, `controllers/paymentsController.ts` |
| `Invoice.update` | `controllers/invoiceController.ts` |
| `Invoice.delete` | `controllers/invoiceController.ts` |
| `Invoice.cancel` | `controllers/invoiceController.ts` |
| `Expense.update` | `models/Expense.ts`, `controllers/expenseController.ts` |
| `PurchaseReturn.voidReturn` | `models/PurchaseReturn.ts` |
| `InvoiceReturnService.voidReturn` | `services/invoiceReturnService.ts` |
| `InvoiceReturnService.voidSettlement` | `services/invoiceReturnService.ts` |
| Salary payment void | `controllers/employeeController.ts` |
| Loan repayment void | `controllers/employeeController.ts` |
| `voidPurchase` | `controllers/purchaseController.ts` |

**Most of the paths this proposal was written against are now guarded.** The
audit (finding CODE-001 / PUR-003) correctly identifies the *class* — protection
is a call-site convention rather than a property of the primitives — but the
table below is the residual gap as of this tree, not the original list.

### Residual gap — CLOSED (verified 2026-11-10)

Every path in the 2026-10-07 gap table below is now guarded, with a green
regression in `server/src/__tests__/closedPeriodImmutability.test.ts`
(24 cases, savepoint-isolated):

| Domain | Operation | Now guarded at | Regression case |
|---|---|---|---|
| Purchase Order | `voidGoodsReceipt` | `PurchaseOrderModel.voidGoodsReceipt` asserts on `receipt.receipt_date` inside its transaction; controller catch maps closed-period → 409 | `goods receipt void in a closed period returns 409 and changes nothing (PUR-003)` |
| Supplier Refund | refund void | `models/SupplierRefund.ts` asserts; `voidSupplierRefund` catch maps closed-period → 409 | case in this suite + `supplierRefund.test.ts` |
| Stock movement | adjustment GL | `postLegacyStockEntry` calls `assertPeriodNotClosed` before any insert; `createStockMovement` controller guard rejects future `movement_date` with 400 and maps closed-period → 409 | `a closed-period stock adjustment returns 409 and GL receives no lines (ACCT-005)` + `a future-dated stock adjustment is refused and creates no period` |
| Purchase (model layer) | `Purchase.void` | `models/Purchase.ts` asserts on `purchase_date` before the write transaction | `Purchase.void throws at the model layer for a closed-period purchase` |
| Invoice (model layer) | `Invoice.cancel` | `models/Invoice.ts` `cancelInvoiceInternal` asserts on `invoice_date` | `Invoice cancel throws at the model layer for a closed-period invoice` |
| Primitive | `voidJournalLinesByReference` | asserts every affected `entry_date` before the `UPDATE` | `voidJournalLinesByReference refuses a closed-period reference with no caller guard` |
| Future periods | `postEntry` auto-create | refuses a future `entry_date` with 400 unless an explicitly opened period covers it; admin-only `POST /api/accounting/periods` is the only creator | `postEntry with a future date throws`; five refusal cases cover purchase, invoice, invoice-update, receipt (dated `2030-01-01`), stock adjustment; `an explicitly opened future period accepts future-dated postings` keeps the admin path working |
| Period names | closure detection | reads `status` only; a non-calendar name closed works the same | `a period closed under a non-calendar name still refuses mutations` |

The two structural conclusions stand as the design record: (1) model-layer
 guards protect non-HTTP callers, and (2) the period check now lives in the
 primitive itself, so no caller has to remember. Known gap NOT folded in:
restore's re-consumed COGS is not batch-faithful when the returned stock was
consumed between delete and restore — recorded as BUG-010 in `docs/bugs.md`
(planned, deliberately separate work), not as a spec rewrite.

**Two structural conclusions, which were the real content of this change (as
written at audit time; both are now implemented — see the table above):**

1. **Controller-only guards are not guards.** `Purchase.void` and `Invoice.cancel`
   were protected at the HTTP layer and unprotected at the model layer, so any
   internal caller reached the mutating path unchecked.
2. **`voidJournalLinesByReference` was a bare `UPDATE journal_lines SET voided = 1`**
   with no period logic. Every caller had to remember to check first, and audit
   PUR-003 proved one forgot. The check belongs in the primitive — and it now is.

## Requirements

### Requirement: Centralized period guard
A single helper `AccountingService.assertPeriodNotClosed(db, date, what)` already
exists. Every mutating path that touches accounting history MUST call it before
any write, using the **document date** (not today) as the period reference.

#### Scenario: Payment edit in closed period
- **WHEN** a user edits `payment_date` or `payment_method` of a payment dated
  inside a closed period
- **THEN** the server returns HTTP 409 with message
  `"Accounting period <name> is closed."`
- **AND** the database is unchanged

#### Scenario: Payment void in closed period
- **WHEN** a user voids a payment dated inside a closed period
- **THEN** the server returns HTTP 409
- **AND** no GL lines are voided, no allocations are touched

#### Scenario: Invoice cancellation in closed period
- **WHEN** a user cancels an invoice dated inside a closed period
- **THEN** the server returns HTTP 409
- **AND** the invoice, its GL lines, and its stock remain untouched

#### Scenario: Expense edit in closed period
- **WHEN** a user edits amount/date/method of an expense dated inside a closed
  period
- **THEN** the server returns HTTP 409
- **AND** the original EXPENSE GL lines remain active

#### Scenario: Expense delete in closed period
- **WHEN** a user deletes an expense dated inside a closed period
- **THEN** the server returns HTTP 409
- **AND** the expense row and its GL lines remain

#### Scenario: Purchase void in closed period
- **WHEN** a user voids a purchase dated inside a closed period
- **THEN** the server returns HTTP 409
- **AND** stock, AP ledger, and PURCHASE GL remain untouched

#### Scenario: Sales return void in closed period
- **WHEN** a user voids a sales return dated inside a closed period
- **THEN** the server returns HTTP 409
- **AND** restock, customer ledger, and INVOICE_RETURN GL remain untouched

#### Scenario: Same operations in open period still succeed
- **WHEN** the same operations are performed on documents dated in an open
  period
- **THEN** they execute exactly as before (void, edit, cancel succeed)

### Requirement: No bypass of existing reversal rules
The period guard is a pre-check, not a replacement for any existing reversal
logic. If the period is open, the operation proceeds through its normal
transaction and existing void/reverse rules still apply.

### Requirement: Failed operations leave DB unchanged
All guarded paths must call `assertPeriodNotClosed` **before** any write
(`UPDATE`, `DELETE`, `voidJournalLines`, `recordMovement`, ledger reversal,
etc.). Because better-sqlite3 is synchronous and single-connection, a thrown
error before the first write guarantees zero partial mutation.

## Implementation Plan

### Step 1 — Add period guard to Payment model
- `Payment.update`: guard on `existing.payment_date`
- `Payment.delete`: guard on `existing.payment_date`

### Step 2 — Add period guard to Invoice controller / model
- `updateInvoice`: guard on `originalInvoice.invoice_date`
- `deleteInvoice`: guard on `originalInvoice.invoice_date`
- `cancelInvoice`: guard on `invoice.invoice_date`

### Step 3 — Add period guard to Expense model
- `Expense.update`: guard on `existing.expense_date`
- `Expense.delete`: guard on `existing.expense_date`

### Step 4 — Add period guard to Purchase model
- `Purchase.void`: guard on `purchase.purchase_date`

### Step 5 — Add period guard to PurchaseReturn model
- `PurchaseReturn.voidReturn`: guard on `header.return_date` (or purchase date)

### Step 6 — Add period guard to InvoiceReturnService
- `voidReturn`: guard on `ret.return_date`
- `voidSettlement`: guard on `ret.return_date`

### Step 7 — Add period guard to Employee controller
- Salary payment void: guard on `payment.payment_date`
- Loan repayment void: guard on `repayment.repayment_date`

### Step 8 — Regression tests
Create `server/src/__tests__/closedPeriodImmutability.test.ts` covering:
1. Payment void in closed period → 409, DB unchanged
2. Payment date edit in closed period → 409, DB unchanged
3. Payment method edit in closed period → 409, DB unchanged
4. Invoice cancellation in closed period → 409, DB unchanged
5. Expense edit in closed period → 409, DB unchanged
6. Expense delete in closed period → 409, DB unchanged
7. Purchase void in closed period → 409, DB unchanged
8. Sales return void in closed period → 409, DB unchanged
9. Same operations in open period → succeed

### Step 9 — Run full server test suite
Verify 0 regressions across all 72+ suites.

## Files to modify
- `server/src/services/accountingService.ts` (no change needed — helper exists)
- `server/src/models/Payment.ts`
- `server/src/controllers/invoiceController.ts`
- `server/src/models/Invoice.ts`
- `server/src/models/Expense.ts`
- `server/src/models/Purchase.ts`
- `server/src/models/PurchaseReturn.ts`
- `server/src/services/invoiceReturnService.ts`
- `server/src/controllers/employeeController.ts`
- `server/src/__tests__/closedPeriodImmutability.test.ts` (new)

## Non-goals
- Reopening closed periods via API (out of scope; admin DB edit only)
- Period-level audit log (existing activity log covers who/when)
- UI changes (server enforcement is the goal)
