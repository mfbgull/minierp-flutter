# boot-task-gating Specification

## Purpose
TBD - created by archiving change inventory-integrity. Update Purpose after archive.
## Requirements
### Requirement: No boot process writes to stock tables
Server startup MUST NOT execute any INSERT, UPDATE or DELETE against `stock_movements`, `stock_balances`, `stock_batches` or `items.current_stock`. The former self-heal (rewrite of balances from `SUM(stock_movements)`) MUST be reduced to a read-only comparison that logs discrepancies and exposes them on an admin-only health endpoint.

#### Scenario: Server restart leaves stock tables untouched
- **WHEN** the server starts against a database with known batch/balance gaps
- **THEN** row counts, `quantity_remaining` values and `batch_id` links are byte-identical before and after startup
- **AND** no `BATCH-*-RECON-*` rows are created

#### Scenario: Discrepancies are visible, not repaired
- **WHEN** `stock_balances.quantity` differs from `SUM(stock_movements)` for any (item, warehouse)
- **THEN** the discrepancy is logged at startup with item id, warehouse id, and both values
- **AND** `GET /api/admin/health/stock-discrepancies` returns the full list for admins only

### Requirement: Reconciliation runs only as an explicit gated script
The unbatched-stock reconciliation logic MUST NOT run at boot. It exists as an explicitly invoked script which: scopes its cost average to `(item_id, warehouse_id)` and to inbound `PURCHASE`/`PRODUCTION` movements only; posts a balancing journal entry for every value it capitalises; refuses to run twice for the same gap (idempotency via a settings flag); and handles over-covered batches (batches exceeding balances) by trimming instead of ignoring them.

#### Scenario: Script mints correct-cost layers once
- **WHEN** an operator runs the reconciliation script where item 1/WH1 has a +2 gap
- **THEN** one batch is created at that warehouse's true weighted cost from valid purchase/production layers
- **AND** a journal entry debits inventory asset / credits adjustment for the exact capitalised amount
- **AND** re-running the script reports "nothing to do"

### Requirement: Batch cleanup never destroys live quantity or audit links
Any orphaned-batch cleanup MUST run only as an explicit reviewed script, MUST refuse to delete any batch holding `quantity_remaining > 0.0005`, and MUST NEVER set `stock_movements.batch_id = NULL`.

#### Scenario: Cleanup skips covered batches
- **WHEN** the cleanup script encounters an orphaned-source batch whose `quantity_remaining > 0`
- **THEN** the batch is kept and reported as "needs manual review", not deleted

#### Scenario: Historical movement links preserved
- **WHEN** the cleanup removes any genuinely empty orphaned batch
- **THEN** every `stock_movements.batch_id` referencing it still resolves (rows retained, batch tombstoned or link kept)

