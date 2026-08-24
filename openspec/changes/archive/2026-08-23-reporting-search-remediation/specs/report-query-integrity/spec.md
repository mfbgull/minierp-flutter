## ADDED Requirements

### Requirement: One revenue definition across all report sites
Every routed revenue figure SHALL use a single shared SQL fragment (`netRevenueExpr`): `SUM(total_amount − COALESCE(returned_amount,0)) − SUM(return_fee)` over invoices with `status != 'Cancelled'`. Daily sales, monthly sales, DSO credit-sales, customer statements and any remaining raw `SUM(total_amount)` report site SHALL consume it. A fully-returned invoice SHALL contribute zero to every routed revenue figure.

#### Scenario: Returned invoice excluded everywhere
- **WHEN** an invoice is fully returned in the period
- **THEN** daily sales, monthly sales and the DSO credit-sales denominator all match P&L revenue for that period

#### Scenario: Cancelled invoices never count
- **WHEN** a cancelled invoice exists in the range
- **THEN** no routed sales report includes its total

### Requirement: Tax computed on a tax-exclusive base
`invoice_items` SHALL carry `tax_amount` and `net_amount` columns written at line creation; `getTaxSummary` SHALL sum the stored `tax_amount` instead of re-deriving tax from the possibly tax-inclusive `amount`. A migration SHALL backfill both columns for existing lines using each line's own discount/tax semantics.

#### Scenario: Quotation-sourced line taxed once
- **WHEN** a tax summary covers a quotation-sourced invoice whose stored `amount` includes tax
- **THEN** the reported tax equals the line's stored `tax_amount` (no tax-on-tax inflation)

### Requirement: One COGS definition shared by all statements
A single `cogsForPeriod(db, from, to)` helper SHALL be the only source of COGS for the P&L, gross-profit, income-statement, balance-sheet YTD and dashboard figures; the balance-sheet variant's extra `movement_type='OUT'` term is removed or reconciled into the helper. All statements in one session SHALL report identical COGS.

#### Scenario: P&L equals balance sheet on COGS
- **WHEN** any movement set exists in a period
- **THEN** P&L COGS and balance-sheet YTD COGS are byte-equal

### Requirement: General ledger reports the GL
`getGeneralLedger` SHALL return entries from `journal_lines JOIN chart_of_accounts` (`voided = 0`) with account code, account name, debit, credit and running balance. The former customer-subledger query survives renamed as `getCustomerLedgerReport`; the Flutter general-ledger screen consumes the GL endpoint unchanged.

#### Scenario: Accountant sees expenses and purchases
- **WHEN** purchases and expenses exist in the period
- **THEN** the general ledger response contains journal lines for their accounts (2000/6000), not only AR transactions

### Requirement: Customer statements foot and preserve empty customers
The customer-statement query SHALL keep its LEFT JOIN semantics when a specific customer is selected (date filters land in the ON clause or an outer query, never a WHERE that annihilates childless customers). `closing_balance` SHALL equal `opening_balance + debits − credits` within 0.01, with opening carried forward from `customer_ledger` before the period start.

#### Scenario: Customer with no in-range invoices still listed
- **WHEN** a specific customer has no invoices in the date range but a prior balance
- **THEN** the statement shows that customer with opening = closing and zero period activity

#### Scenario: Statement footing holds
- **WHEN** any statement is rendered
- **THEN** opening_balance + total_debits − total_credits equals closing_balance within 0.01

### Requirement: Local-date period defaults
All report/dashboard controller default date ranges SHALL resolve "today" via one shared local-time helper (`todayLocal(db)`, `date('now','localtime')` semantics); ledger-written `transaction_date` values use the same calendar. No default may shift a UTC+5 user to yesterday between 00:00 and 05:00 local.

#### Scenario: Early-morning aging includes today
- **WHEN** a UTC+5 user opens AR/AP aging at 01:00 local
- **THEN** the default end date is today's local date and documents dated today are included

### Requirement: Ledger running balances stay date-monotonic
Customer/supplier statement opening-balance lookups SHALL order by `transaction_date ASC/DESC` with `, id ASC` as tiebreaker, matching the already-fixed rebuild ordering, so printed running balances never jump non-monotonically for same-day or back-dated entries.

#### Scenario: Back-dated document lands correctly
- **WHEN** a document is entered today but dated last week and balances are rebuilt
- **THEN** the statement running balance around that date remains monotonic in date order

### Requirement: Declared client endpoints exist server-side
Every report/dashboard endpoint declared in the Flutter client SHALL resolve: `/reports/expiry` and `/dashboard/expiry-alerts` SHALL be implemented over `stock_batches.expiry_date` (batch-level expiry list / alert feed) — or the client declarations and screens removed by explicit product decision.

#### Scenario: Expiry screen loads
- **WHEN** the user opens the expiry report or dashboard expiry alerts
- **THEN** the request returns 200 with batch rows (or an explicit empty state), never 404

### Requirement: Unrouted report functions do not ship
Report model functions not exposed by any route AND not imported outside `routes/`/`controllers/` SHALL be deleted from `Reports.ts`, so divergent duplicate formulas cannot be resurrected by adding a route. Any function retained without a route requires an explicit note in this change.

#### Scenario: Dead formula cannot resurface
- **WHEN** a developer adds a new route pointing at a previously deleted function name
- **THEN** compilation fails (function gone) forcing a deliberate re-implementation against the shared helpers
