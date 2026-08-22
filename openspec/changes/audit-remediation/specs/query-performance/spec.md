# Spec: query-performance (Delta)

## ADDED Requirements

### Requirement: Hot-path indexes exist
The schema SHALL include covering indexes for the measured hot paths: `invoice_items(invoice_id)` and `invoice_items(item_id)`, `customers(customer_name)`, `suppliers(supplier_name)`, `settings(key)`, `invoices(due_date)`, `invoices(status, invoice_date)`, `customer_ledger(customer_id, transaction_date, id)`, `customer_ledger(customer_id, id)`, `stock_movements(item_id, warehouse_id, movement_date)`; invoice-detail and sales-by-item lookups SHALL be index searches, not full scans.

#### Scenario: Invoice detail uses an index
- **WHEN** EXPLAIN QUERY PLAN runs for invoice_items filtered by invoice_id
- **THEN** the plan searches an index and does not SCAN invoice_items

### Requirement: Redundant indexes are pruned
The 12 provably redundant indexes (10 exact duplicates plus 2 prefix-redundant on activity_log) SHALL be dropped via migration, and `PRAGMA optimize` (or ANALYZE) SHALL run on a schedule so planner statistics stay current.

#### Scenario: No duplicate index definitions
- **WHEN** the live schema is inspected after the migration
- **THEN** no two indexes share an identical table and column list

### Requirement: Ledger balance updates are incremental
Saving, editing, deleting or paying an invoice SHALL update affected customer_ledger balances incrementally from the first changed row forward — not rewrite the customer's entire history per row.

#### Scenario: Save is independent of history depth
- **WHEN** an invoice is created for a customer with 100k ledger rows
- **THEN** the write performs a bounded number of statements unrelated to the customer's row count, and all running balances remain correct

### Requirement: Dashboards are bounded and batched
Dashboard endpoints SHALL apply date lower bounds to cash-flow aggregation, compute per-account cash position in set-based SQL rather than five unbounded JS-filtered scans, skip stock valuation for metrics that do not need it, and expose a batched KPI fetch so a dashboard load performs a small fixed number of requests; the client SHALL stop calling the two nonexistent expiry endpoints.

#### Scenario: Dashboard request count is fixed
- **WHEN** the dashboard loads with all KPI cards visible
- **THEN** the client issues a bounded batch of requests (not one per card), and no request targets a nonexistent route

#### Scenario: Cash position has a date floor
- **WHEN** cash position is computed for a date range
- **THEN** underlying queries scan only rows within the configured lookback window

### Requirement: Search permission checks are hoisted
Global search SHALL resolve the user's permission set once per request and reuse it across all result rows, and every search query SHALL bind all parameters (fixing the unbound role-permission query).

#### Scenario: Statement count is independent of result rows
- **WHEN** a search returns N rows per entity
- **THEN** permission evaluation executes a constant number of statements per request, not per row

### Requirement: Reports and ledgers are paginated and date-bounded
All /reports/* endpoints, customer/supplier ledger and statement endpoints, /stock-batches, account balances and custom-report runs SHALL support pagination (LIMIT/OFFSET + count) and SHALL enforce a default date window where the query is unbounded without one; aging reports SHALL not apply functions to indexed date columns in a way that forces full scans.

#### Scenario: Ledger statement is bounded by default
- **WHEN** a customer statement is requested without explicit dates
- **THEN** the response is limited to the default window/page size and includes pagination metadata
