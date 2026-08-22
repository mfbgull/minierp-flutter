# Spec: ledger-append-only (Delta)

## ADDED Requirements

### Requirement: Ledger rows are never deleted
`customer_ledger` and `supplier_ledger` rows SHALL NOT be deleted by any application code path. Corrections SHALL be made by inserting an equal-and-opposite reversing row that references the original (`reversed_by`) and marking the original `voided = 1`. All ledger reads used for balances and statements SHALL exclude voided rows.

#### Scenario: Invoice update no longer destroys history
- **WHEN** an invoice update replaces its customer_ledger INVOICE row
- **THEN** the original row remains with voided = 1
- **AND** a new row carries the corrected amounts and reversed_by pointing at the original id

#### Scenario: Payment deletion reverses instead of deletes
- **WHEN** a payment with subledger rows is deleted
- **THEN** the payment's subledger rows still exist, voided = 1, with reversal rows present

### Requirement: Reversals and deletions are counterparty-scoped
Any ledger reversal or cleanup operation referencing a document number SHALL be scoped to the counterparty (customer_id or supplier_id) in addition to the reference number, so a colliding reference cannot touch another party's rows.

#### Scenario: Reference collision cannot cross customers
- **WHEN** two customers' ledgers both contain reference_no 'REF-001' and one invoice is updated
- **THEN** only that invoice owner's rows are voided/reversed

### Requirement: Running balances chain in transaction-date order
New ledger inserts SHALL store the caller-supplied document date (not the server's current date) and compute the stored balance from the latest row ordered by (transaction_date, id). Balance rebuilds SHALL use the same ordering and exclude voided rows. Historical rows missing their document date SHALL be backfilled from their source documents where recoverable, then rebalanced once.

#### Scenario: Backdated return keeps the chain sane
- **WHEN** a return dated before a later payment is inserted
- **THEN** its running balance reflects position between earlier rows by transaction_date, not after them

#### Scenario: Statement footing matches stored balance
- **WHEN** a customer statement lists non-voided rows in transaction-date order
- **THEN** each displayed running balance equals the stored balance column for that row

### Requirement: One authoritative customer balance derivation
A single function SHALL derive `customers.current_balance` as SUM(debit) − SUM(credit) over non-voided customer_ledger rows, and all writers currently using open-invoice sums, credit-balance columns, or payment-arithmetic bases SHALL be migrated to it. No second writer may update the column.

#### Scenario: One customer, one balance
- **WHEN** any invoice, payment, or return mutates a customer's position
- **THEN** customers.current_balance equals the ledger-derived figure exactly
