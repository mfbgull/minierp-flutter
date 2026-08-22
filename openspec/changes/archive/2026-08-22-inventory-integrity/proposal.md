# Proposal: inventory-integrity

## Why

The inventory audit (`opus5-audit-report/inventory.md`) proved that 100% of the live stock drift is caused by exactly two code defects — `PhysicalCount.completeCount` never touching `stock_batches` (INV-01) and the warehouse transfer being two independent client-orchestrated HTTP calls that create no destination batch (INV-02) — while three boot-time jobs silently mint cost layers at provably wrong costs (INV-04), hard-delete live batches and sever historical audit links (INV-05), and overwrite balances in ways that mask every balance-side bug (INV-09). Two further sale paths (mobile invoice INV-03, SO→invoice INV-06) deduct stock without batch consumption or guards and will manufacture fresh drift on every use. The schema has no CHECK invariants (INV-21), so none of these failures can abort a transaction — they accumulate silently.

## What Changes

- Freeze the three boot-time stock mutators: `runUnbatchedStockReconciliation` (INV-04), the orphaned-batch cleanup (INV-05) become one-time, explicitly-run, logged scripts behind settings flags; the boot self-heal that rewrites `stock_balances`/`items.current_stock` (INV-09) becomes detect-and-log with an admin health endpoint.
- Widen the `stock_batches.source_type` CHECK to include `GOODS_RECEIPT`, `RECON`, `RETURN`, `ADJUSTMENT`, `OPENING`, `TRANSFER` (INV-22) and re-stamp existing rows into disjoint namespaces so `source_id` stops meaning two things at once (INV-10).
- Make physical-count completion adjust all three tables — movements, balances, **batches** (FIFO-consume negative variance; insert an `ADJUSTMENT`-sourced batch for positive variance) plus its journal entry; fix the epoch-timestamp movement number (INV-23) and the NaN-variance operator-precedence bug (INV-24).
- Add a server-side `POST /api/stock-transfers` performing both legs inside one `.immediate()` transaction with FIFO consumption at source and a mirror batch at destination; update the Flutter transfer dialog to call it once instead of two movements.
- Route mobile invoice submission through the same guarded, batched, GL-posted path as desktop invoices (INV-03); make SO→invoice conversion use `recordBatchMovement` instead of its UPDATE-only balance write (INV-06).
- Run a one-off reconciliation migration repairing the four known drift rows (item 15 −5, item 1 +2, item 2/WH1 −3.722, item 2/WH2 +10 mirror batch), each with a balancing journal entry; then add `CHECK(quantity >= 0)` / `CHECK(quantity_remaining <= quantity_original)` via table rebuild (INV-21).
- Out of scope (deferred to follow-up changes): StockService extraction across all writers (INV-07), `.immediate()` sweep + concurrency re-checks (INV-08), invoice-update stale-SALE cleanup and COGS re-posting (INV-12/13), valuation unification (INV-14), expiry enforcement (INV-15), POS GL posting (INV-17 — owned by the accounting change), purchase-return void layer tracking (INV-18), count snapshot staleness (INV-19).

## Capabilities

### New Capabilities
- `boot-task-gating`: No boot process writes to stock tables; reconciliation/cleanup run only as explicit reviewed scripts gated by settings flags; discrepancies are detected, logged and exposed read-only.
- `batch-source-typing`: `stock_batches.source_type` is a disjoint namespace per origin table; every existing row is re-stamped correctly.
- `physical-count-batch-sync`: Completing a physical count reconciles movements, balances and cost layers together, with clean movement numbering and null-safe variance math.
- `server-side-stock-transfer`: A warehouse transfer is one atomic server operation producing mirrored cost layers at the destination.
- `guarded-sale-paths`: Every sale path checks availability cleanly, consumes/creates batches, references documents consistently and posts to the GL.
- `stock-invariant-checks`: Database-level CHECK constraints make negative or over-covered stock unrepresentable, applied after live data is reconciled.

### Modified Capabilities
<!-- None: existing specs (activity-log-grid, invoice-returns, purchase-returns) have no requirement changes. -->

## Impact

- **Server code:** `server/src/config/database.ts` (boot gating), `server/src/models/PhysicalCount.ts`, `server/src/models/SalesOrder.ts`, `server/src/models/MobileInvoice.ts`, new `server/src/controllers/stockTransferController.ts` (+ route), `server/src/routes/inventory.ts`; shared helper extracted from `invoiceController.createInvoice`.
- **Migrations:** widen `source_type` CHECK + re-stamp rows (table rebuild); add CHECK constraints (table rebuild ×2); one-off data reconciliation with journal entries. All flagged/idempotent.
- **Flutter client:** `lib/features/inventory/stock_transfer_dialog.dart` + repository/API client — single call to the new endpoint; no other UI changes.
- **Sequencing dependency:** the backup capability from `audit-p0-critical-fixes` MUST be applied first; the reconciliation migration writes to live business data and requires a restorable snapshot behind it.
- **Tests:** extend FIFO/batch test suite; per-direction drift verification via extended read-only `reconcile-stock-cash.ts`.
