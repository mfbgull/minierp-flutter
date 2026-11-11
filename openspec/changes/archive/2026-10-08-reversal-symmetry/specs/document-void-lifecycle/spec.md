# document-void-lifecycle (Delta)

## ADDED Requirements

### Requirement: A reversal voids the original entry and posts nothing new
Voiding a document SHALL remove that document's own journal group by marking
its lines `voided = 1`. It SHALL NOT post a second journal entry to achieve the
reversal. Where a reversal must also move stock, the movement SHALL be written
with `skipAdjustmentFinancialPosting: true` so it carries no financial leg.

Every ADJUSTMENT movement routes to `postFinancialEntryForAdjustment`, which
posts `Dr 7200 / Cr 1200` for a removal and `Dr 1200 / Cr 7100` for an addition.
A reversal path that omits the flag therefore credits inventory a second time and
books a shrinkage or correction expense for a document that was merely cancelled.

#### Scenario: Voiding a purchase leaves inventory at zero, not at a credit
- **WHEN** a purchase is voided and its stock was still on hand
- **THEN** GL 1200 has zero debit and zero credit
- **AND** GL 2000 has zero debit and zero credit
- **AND** GL 7200 has zero debit, because nothing was lost

#### Scenario: Voiding a sales return books no shrinkage
- **WHEN** a sales return is voided
- **THEN** GL 7200 carries no entry created by that void
- **AND** the inventory credit the return posted is removed by voiding its
  `INVOICE_RETURN` group, not by a second adjustment posting

#### Scenario: The reversal movement is unposted
- **WHEN** a reversal movement is recorded
- **THEN** its `financial_posted` flag is false, its `journal_entry_id` is null
  and its `financial_value` is zero

### Requirement: A reversal is dated with the document it reverses
The movement written by a void SHALL carry the **source document's** date, not the
date the void was performed. A reversal belongs to the period being reversed;
dating it "today" moves the effect into a different period and can post into one
that is already closed.

#### Scenario: Voiding a January purchase writes a January movement
- **WHEN** a purchase dated `2026-01-15` is voided
- **THEN** the `PURCHASE_VOID` movement carries `movement_date = '2026-01-15'`

#### Scenario: Voiding into a closed period is refused
- **WHEN** a document dated inside a closed accounting period is voided
- **THEN** the operation is refused before any write

### Requirement: Every ADJUSTMENT call site declares its posting intent
Every call to `recordMovement` with `movement_type: 'ADJUSTMENT'` SHALL state
`skipAdjustmentFinancialPosting` explicitly, as `true` or `false`. Silence SHALL
not mean "post a leg".

At the time this requirement was written, `Purchase.void` and
`InvoiceReturnService.voidReturn` were the two call sites relying on the default
while performing reversals. Their create-side twins in `Invoice.ts` and
`PurchaseReturn.ts` already passed the flag.

#### Scenario: The set is enumerable
- **WHEN** a reviewer lists every `movement_type: 'ADJUSTMENT'` call to
  `recordMovement`
- **THEN** each one either sets `skipAdjustmentFinancialPosting: true` or
  documents why a financial leg is correct there