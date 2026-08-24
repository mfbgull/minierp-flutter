## ADDED Requirements

### Requirement: Pre-posting documents are backfilled into the GL
A one-time, idempotent, ledgered migration SHALL post balanced journal entries for financial documents created before live posting was enabled: direct purchases (debit 1200 / credit 2000), supplier payments (debit 2000 / credit method cash account), customer payments lacking GL lines (debit method cash account / credit 1100), expenses (debit 6000 / credit method cash account), and an opening-equity entry reconciling the residual to the operational opening balances. Backfill entries SHALL be marked (e.g. `reference_type = 'BACKFILL'`) so they are identifiable and never re-applied.

#### Scenario: Migration is idempotent
- **WHEN** the backfill migration runs twice
- **THEN** the second run inserts no journal lines and leaves balances unchanged

#### Scenario: Historical trial balance becomes sane
- **WHEN** the backfill completes on the audited live data
- **THEN** Inventory Asset (1200) and Accounts Payable (2000) carry positive, plausible balances instead of −69,015 / zero activity, and debits still equal credits

#### Scenario: Opening equity closes the residual
- **WHEN** all document backfills are posted and a residual difference remains against operational cash/opening balances
- **THEN** a single Owner's Equity (3000) entry absorbs it exactly once, and the balance sheet balances within 0.01

### Requirement: Cash service reads expected balances from the GL
`cashService` SHALL derive each method family's expected balance from its GL cash account (1000–1040) instead of independently re-aggregating payments/expenses/salary payments; its transaction classification remains for flow breakdowns only. Dashboard cash, cash-flow report, cash reconciliation and the balance sheet SHALL therefore agree by construction.

#### Scenario: One cash number everywhere
- **WHEN** any user compares the dashboard cash card, cash-flow report, reconciliation report and balance sheet in one session
- **THEN** all show the same per-method and total cash figures
