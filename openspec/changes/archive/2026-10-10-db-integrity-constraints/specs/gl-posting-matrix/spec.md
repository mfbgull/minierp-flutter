# gl-posting-matrix (Delta)

## ADDED Requirements

### Requirement: A GL backfill never re-posts a voided document
The `backfillGlPreposting` purchases query SHALL exclude rows whose `voided_at`
is set, mirroring the receipts leg, and SHALL tolerate the column being absent on
a legacy database.

Without the filter, voiding a purchase and then running the backfill posted a
fresh `Dr 1200 / Cr 2000` for goods never received, with no matching stock or
supplier-ledger row.

#### Scenario: A voided purchase is skipped
- **WHEN** the backfill runs over a database containing a voided purchase
- **THEN** no journal group is posted for it

#### Scenario: A database predating `voided_at` still runs
- **WHEN** `purchases` has no `voided_at` column
- **THEN** the backfill applies without the filter and does not error

### Requirement: A backfilled GL posting also writes its subledger leg
Each goods receipt the backfill posts to the GL SHALL also write the matching
`supplier_ledger` entry, DEBIT-normal, and SHALL not duplicate an entry that
already exists.

The GL AP credit without its supplier-ledger counterpart leaves GL permanently
above the AP subledger.

#### Scenario: A receipt backfill writes both ledgers
- **WHEN** the backfill posts a goods receipt
- **THEN** a `GOODS_RECEIPT` row is written to `supplier_ledger` with a debit

#### Scenario: An existing ledger row is not duplicated
- **WHEN** a `GOODS_RECEIPT` row already exists for that receipt number
- **THEN** no second row is written
