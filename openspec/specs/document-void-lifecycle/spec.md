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
