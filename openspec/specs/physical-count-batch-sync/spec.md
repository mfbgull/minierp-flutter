# physical-count-batch-sync Specification

## Purpose
TBD - created by archiving change inventory-integrity. Update Purpose after archive.
## Requirements
### Requirement: Count completion reconciles all three tables
Completing a physical count SHALL, for every variance, inside one `.immediate()` transaction: write the ADJUSTMENT movement; update `stock_balances` and `items.current_stock`; and update `stock_batches` — consuming FIFO-oldest layers for negative variance and inserting a `source_type='ADJUSTMENT'` batch at `item.unit_cost` for positive variance — plus post its journal entry. After completion, `SUM(stock_batches.quantity_remaining)` per (item, warehouse) MUST equal `stock_balances.quantity`.

#### Scenario: Shortage consumes cost layers
- **WHEN** a count completes with a −5 variance on an item whose batches hold 50 units at known layer costs
- **THEN** 5 units are consumed from the FIFO-oldest layers with their costs
- **AND** the journal entry values the write-off at the consumed layers' actual costs
- **AND** batch coverage equals the new balance exactly

#### Scenario: Surplus creates a cost layer
- **WHEN** a count completes with a +2 variance
- **THEN** a new batch with `source_type='ADJUSTMENT'`, `unit_cost = item.unit_cost` is inserted in that warehouse
- **AND** balance-sheet valuation rises by 2 × unit_cost through the batch table

### Requirement: Clean movement numbering and null-safe variance
Count adjustments SHALL number movements via the shared `StockMovement.generateMovementNo(db)` generator (no epoch-suffixed ad-hoc numbers). The recorded-count variance computation SHALL treat a missing `physical_count_items` row as an error (abort), not as zero variance.

#### Scenario: Movement numbers stay in sequence
- **WHEN** a count posts three item adjustments
- **THEN** each movement receives the next sequential `STK-yyyy-nnnn` number from the shared generator

#### Scenario: Missing count row aborts instead of zeroing
- **WHEN** `recordCount` is called for an item with no snapshot row in `physical_count_items`
- **THEN** the request fails with a validation error and no variance of 0 is silently written

