## ADDED Requirements

### Requirement: Balance sheet sections are GL-derived
The balance sheet SHALL derive assets, liabilities and equity from `AccountingService.getAllAccountBalances` grouped by `chart_of_accounts.type` (with the legacy `journal_entries` UNION the service already performs) — not from independent aggregations over stock_batches, invoice balances, supplier_ledger or expenses. Inventory, AR, AP, cash and equity in the balance sheet SHALL come from the same source as the trial balance, so both statements report identical account balances as of the same date.

Cash on the balance sheet SHALL be the sum of the five per-method GL cash accounts (1000/1010/1020/1030/1040), not only `text_code = 'cash'`. Until this requirement is satisfied, the Flutter balance-sheet screen SHALL render a "provisional — do not file" banner.

#### Scenario: Balance sheet agrees with trial balance
- **WHEN** any ledger state exists and a user opens the balance sheet and trial balance for the same date
- **THEN** every shared account (cash, inventory, AR, AP, revenue, COGS, expenses) shows the identical balance on both screens

#### Scenario: Sheet balances
- **WHEN** all posting paths are live (post-backfill) and no unposted documents exist
- **THEN** total assets equal total liabilities + equity within 0.01 and the out-of-balance badge does not render

#### Scenario: Cash matches the dashboard
- **WHEN** the dashboard shows expected cash for a method family
- **THEN** the balance sheet's combined cash line reflects the same five-account total rather than a second, conflicting figure
