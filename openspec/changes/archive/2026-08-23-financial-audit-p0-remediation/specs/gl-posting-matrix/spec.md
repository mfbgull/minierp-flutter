## MODIFIED Requirements

### Requirement: Payment amount changes are prohibited on existing payments
`Payment.update` SHALL reject any request changing `amount` with 400, instructing void-and-reissue. Date, method, reference, and notes edits remain permitted; method changes keep void+repost of the GL entry at the unchanged amount. The previous proportional allocation-rescaling behavior is removed.

#### Scenario: Amount edit refused on customer payment
- **WHEN** PATCH /api/payments/:id supplies a different amount for a fully allocated payment
- **THEN** the response is 400 explaining void-and-reissue, allocations and invoice paid_amount are untouched

#### Scenario: Amount edit refused on supplier payment
- **WHEN** an amount change is requested for a payment holding po_allocations
- **THEN** it fails 400; po_allocations amounts, supplier_ledger credit, and suppliers.current_balance all remain consistent

#### Scenario: Metadata edit still works
- **WHEN** only notes or reference_no change
- **THEN** the update succeeds and activity_log records it

### Requirement: Receipt previous balance reflects payment-time state
A receipt's "previous balance" SHALL be derived from the payment's own ledger row (stored running balance net of that row's movement), not from today's counterparty balance. Fallback to current-balance arithmetic only when no ledger row exists.

#### Scenario: Reprinting an old receipt shows its era
- **WHEN** a receipt printed weeks ago is reprinted after many later transactions
- **THEN** its previous balance equals the counterparty balance just before that payment posted

### Requirement: Manual allocation endpoint exists
`POST /api/payments/:id/allocate` SHALL accept additional invoice allocations for a partially allocated payment, validating total equality within tolerance, invoice ownership by the payment's customer, per-invoice cap at balance_amount, gated by `payments:update`, applied transactionally with invoice balance recalculation.

#### Scenario: Legacy partially-allocated payment can be finished
- **WHEN** a valid allocation set covering the unallocated remainder is posted
- **THEN** payment_allocations rows appear, affected invoices' balances update, and over-cap requests fail 400
