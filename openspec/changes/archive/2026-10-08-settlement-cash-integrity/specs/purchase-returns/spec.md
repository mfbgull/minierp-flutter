# purchase-returns (Delta)

## ADDED Requirements

### Requirement: A purchase return settled in cash is capped by the cash collected on the source document
A purchase return with `disposition: 'refund_expected'` SHALL NOT pay out more
cash than was collected against the source purchase or purchase order. When
nothing has been collected, the disposition SHALL be refused.

`refund_expected` promises money to the supplier, so it may only promise money
that arrived. Refunding the full return value regardless of collections posts
`Dr Cash / Cr AP` and manufactures both a cash asset and an AP credit out of an
unpaid purchase — a balanced entry, so every ledger invariant stays green.

The caller-facing remedy is `credit_on_account`, which records the credit note
without moving cash.

#### Scenario: Refunding an unpaid purchase is refused
- **WHEN** a purchase of 900 has no allocation against it and a return of value 300 carries `disposition: 'refund_expected'`
- **THEN** the request returns an error of 400 or greater
- **AND** the response explains that nothing has been collected and names `credit_on_account`
- **AND** net cash is unchanged

#### Scenario: A partially paid purchase refunds at most the collected amount
- **WHEN** a purchase of 500 has 100 collected and a return of value 250 carries `disposition: 'refund_expected'`
- **THEN** the return is accepted
- **AND** the refund moves no more than the 100 collected
- **AND** the trial balance still foots

#### Scenario: Credit on account remains available on an unpaid purchase
- **WHEN** a return against a fully unpaid purchase carries `disposition: 'credit_on_account'`
- **THEN** the return is accepted
- **AND** no cash moves

### Requirement: The collected amount is read from live allocations
The collected amount SHALL be the sum of `purchase_allocations` (or
`po_allocations`) whose `voided_at IS NULL`, and SHALL exclude voided rows.

A voided allocation is money that was taken back, so counting it would permit a
refund of cash that no longer exists.

#### Scenario: A voided allocation does not count as collected
- **WHEN** a purchase has one live allocation of 100 and one voided allocation of 400
- **THEN** the collected amount is 100
- **AND** a refund of more than 100 is refused

#### Scenario: An allocation for a different document is not counted
- **WHEN** the only allocation against a purchase belongs to another purchase
- **THEN** the collected amount for this purchase is 0
