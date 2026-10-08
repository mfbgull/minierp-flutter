# document-void-lifecycle Specification

## Purpose

See the archived change `financial-audit-p0-remediation` (proposal.md) for the
motivating forensic audit findings (PAY-07, CASH-01..04, EXP-03..05, PUR-03,
PRET-01..06, PAY-04/09/10/11).
## Requirements
### Requirement: Purchases are voided, never hard-deleted
Deleting a purchase SHALL be impossible. The purchase void operation SHALL stamp `voided_at`, `voided_by`, `void_reason` and SHALL refuse when: a non-void purchase return references the purchase, `returned_quantity > 0`, or remaining batch quantity is less than original quantity minus tolerance (stock already sold). Voiding reverses the supplier-ledger PURCHASE row (append-only), voids the GL journal entry by reference, writes an ADJUSTMENT movement for the genuinely remaining quantity only, zeroes that batch, and records an activity_log entry including the reason.

#### Scenario: Sold stock blocks void
- **WHEN** a purchase of 50 units has 45 sold from its batch
- **THEN** void is refused with an error naming sold quantity, and no ledger, GL, or stock row changes

#### Scenario: Clean void reverses everything in balance
- **WHEN** an unsold, unreturned, unpaid purchase of 500 is voided with a reason
- **THEN** supplier ledger shows the PURCHASE debit reversed append-only, the GL PURCHASE entry's lines are voided, an ADJUSTMENT movement removes the remaining units, and the purchase row remains queryable with void attribution

#### Scenario: Hard delete route is gone
- **WHEN** DELETE /api/purchases/:id is called
- **THEN** the response is 404/405 (route removed), not a silent delete

### Requirement: Purchase batches are identified by insert identity
Direct-purchase batch identity SHALL come from the INSERT result (`lastInsertRowid`), never from re-querying `(source_type='PURCHASE', source_id)` after insert.

#### Scenario: Id-space collision cannot misattribute a batch
- **WHEN** a goods-receipt item and a new purchase share the same numeric id
- **THEN** the purchase's own newly inserted batch id is used for its movements and header link, not any other row's

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

