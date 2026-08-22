# Spec: balance-truth-sources (Delta)

## ADDED Requirements

### Requirement: Server computes invoice money authoritatively
The server SHALL compute each invoice line amount as quantity × unit_price minus discount, plus tax, rounded at the line boundary; the header total SHALL be the sum of server-computed lines. A client-supplied `total_amount` differing from the computed total by more than 0.01 SHALL be rejected with 400 and no document shall be created or updated. POS sales and mobile invoices SHALL enforce the same rule.

#### Scenario: Client-inflated total is rejected
- **WHEN** a create/update request supplies total_amount 1 for line items summing to 100,000
- **THEN** the request fails with 400 and no invoice, stock movement, ledger, or GL row is written

#### Scenario: Legitimate client totals pass unchanged
- **WHEN** the Flutter form posts a total equal to its own line sum within 0.01
- **THEN** the request succeeds and stored line amounts include discount and tax

### Requirement: GL reconciliation report
An authenticated endpoint (`GET /api/accounting/reconciliation`, accounting:read) SHALL return, per account pairing, the GL balance from journal_lines alongside an operational derivation (Inventory ← stock_batches cost value; AR ← open invoice balances; AP ← supplier ledger positions; Cash family ← payment-method sums), with the delta between them. The report is read-only and SHALL NOT mutate data.

#### Scenario: Reconciliation exposes known drift
- **WHEN** purchases have never been posted to the GL but inventory has been sold
- **THEN** the Inventory row shows materially different GL vs operational figures rather than two plausible-looking numbers

#### Scenario: Clean books reconcile
- **WHEN** all posting paths are active on seeded test data with no historical backlog
- **THEN** every account pair's delta is within 0.01

### Requirement: Journal voids carry attribution metadata
`journal_lines` SHALL have voided_at, voided_by, and void_reason columns populated by application void operations, so previously-filed trial balances remain explainable.

#### Scenario: Void audit question answerable
- **WHEN** a trial balance discrepancy is traced to voided lines
- **THEN** the acting user, timestamp, and reason are queryable on those lines
