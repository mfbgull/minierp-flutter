# closed-period-immutability — Delta

## ADDED Requirements

### Requirement: Period guard is a property of the posting primitives
`AccountingService.assertPeriodNotClosed(db, date, what)` SHALL be called by the
primitives that mutate dated financial state, not only by their callers. At
minimum `voidJournalLinesByReference` and `postLegacyStockEntry` SHALL assert
before any write, so a call site that forgets the guard cannot un-post a closed
period. `models/Purchase.ts` and `models/Invoice.ts` SHALL enforce the guard at
the model layer; guarding only the HTTP controller is insufficient because any
internal caller reaches the mutating path unchecked.

#### Scenario: A caller that forgets the guard still cannot mutate a closed period
- **WHEN** `voidJournalLinesByReference` is invoked for a document dated inside a
  closed period, without the caller having checked first
- **THEN** the call throws before any write and no `journal_lines` row is marked
  `voided = 1`

#### Scenario: Model-layer void is guarded without the controller
- **WHEN** `Purchase.void` or `Invoice.cancel` is called directly from a
  non-HTTP code path for a document in a closed period
- **THEN** the call throws and stock, ledger, and GL remain untouched

### Requirement: Unguarded mutating paths are closed
Every mutating path that touches dated financial state SHALL assert the period is
open before its first write. The paths verified still missing this on
2026-10-07: `voidGoodsReceipt` (`controllers/purchaseOrderController.ts`, which
contains no period reference at all), supplier-refund void
(`controllers/supplierRefundController.ts`, `models/SupplierRefund.ts`), and
`createStockMovement` / `postLegacyStockEntry` (audit ACCT-005 sibling, which
posts into a closed period today).

#### Scenario: Goods receipt void in a closed period is refused
- **WHEN** a goods receipt dated inside closed period `2026-03` is voided
- **THEN** the server returns HTTP 409
- **AND** GL 1200, GL 2000, and the stock reversal are all unchanged

#### Scenario: Supplier refund void in a closed period is refused
- **WHEN** a supplier refund dated inside a closed period is voided
- **THEN** the server returns HTTP 409 and no supplier-ledger row changes

#### Scenario: Manual stock adjustment in a closed period is refused
- **WHEN** an adjustment dated inside closed period `2026-01` is submitted
- **THEN** the server returns HTTP 409
- **AND** GL 1200 and 7100 receive no lines

### Requirement: A document date selects a period, it never creates one
A document date later than today SHALL be rejected with HTTP 400 at the
controller. `AccountingService.postEntry` SHALL NOT auto-create an open
`accounting_periods` row from a document date. Opening a future period SHALL
require an explicit administrative action.

Rationale: today a goods receipt dated `2030-01-01` is accepted and silently
creates open period `2030-01`, and a sale dated `2099-12-31` creates `2099-12`.
Period-close discipline is bypassable by future-dating.

#### Scenario: Future-dated document is refused
- **WHEN** a purchase, receipt, invoice, or adjustment is submitted with a date
  later than today
- **THEN** the server returns HTTP 400 and no `accounting_periods` row is created

#### Scenario: Same operations in open period still succeed
- **WHEN** the same operations are performed on documents dated in an open period
- **THEN** they execute exactly as before

### Requirement: Closed periods are closed by status, not by naming convention
Closing a period SHALL set its `status`; no code path may infer closure from the
shape of the `period_name` string. Audit GL-004 records a bypass via non-calendar
period names.

#### Scenario: A period closed under any name is immutable
- **WHEN** a period whose name is not a calendar month is closed
- **THEN** every mutating path for documents dated in it returns HTTP 409

### Requirement: Invoice restore honours the closed period
`POST /api/invoices/:id/restore` SHALL assert the period is open before
un-voiding GL lines or re-consuming stock. It SHALL NOT re-consume stock at
today's FIFO layers while un-voiding the original COGS line, and SHALL re-post
COGS consistent with the batches it restores.

#### Scenario: Restoring into a closed period is refused
- **WHEN** an invoice dated inside a closed period is restored
- **THEN** the server returns HTTP 409 and no GL line or batch changes

### Requirement: Failed operations leave the database unchanged
Every guarded path SHALL call `assertPeriodNotClosed` **before** any write
(`UPDATE`, `DELETE`, `voidJournalLines`, `recordMovement`, ledger reversal).
Because better-sqlite3 is synchronous and single-connection, throwing before the
first write guarantees zero partial mutation.

#### Scenario: A refused operation writes nothing
- **WHEN** any guarded operation is refused for a closed period
- **THEN** the row count and every GL, ledger, and stock total are byte-identical
  to their pre-call values