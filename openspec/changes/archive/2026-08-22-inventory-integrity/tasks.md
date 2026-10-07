# Inventory-Integrity Task Breakdown

Effort in **person-days (d)**. Scope is exactly the proposal: INV-01/02/03/04/05/06/09/10/21/22/23/24 plus the one-off drift reconciliation. Explicitly out of scope (deferred): StockService extraction (INV-07), `.immediate()` sweep + concurrency re-checks (INV-08), invoice-update stale-SALE cleanup and COGS re-posting (INV-12/13), valuation unification (INV-14), expiry enforcement (INV-15), POS GL posting (INV-17), purchase-return void layer tracking (INV-18), count snapshot staleness (INV-19).

**Dependency rationale:**
- Phase 0 (source_type CHECK widening) is the prerequisite for everything that inserts a new batch type — it must land first.
- Phase 1 (boot-task freeze) is fully independent of Phases 0–2 → can land in parallel.
- Phase 4 (drift reconciliation + CHECK constraints) depends on ALL writers being fixed (Phases 2–3); the CHECK rebuild must run after live data is reconciled or startup fails.
- Phases 2 and 3 are independent of each other once Phase 0 lands.

**Sequential estimate ≈ 12.25 d. With 2 parallel streams (Phase 1 alongside Phases 0–3): ≈ 11 d.**

Verification baseline for every phase: `npm run typecheck`, `npm run lint`, jest suites touched by the phase; Flutter side `flutter analyze` where client code changes. Every migration task includes an idempotency re-run check.

---

## Phase 0 — Batch source typing (INV-10, INV-22) (~1.5 d)

Prerequisite for all new batch writes.

- [x] 0.1 ~~Write the table-rebuild migration widening `stock_batches.so...~~ — RESOLVED 2026-10-07 (Phase 0): DONE-IN-TREE: CHECK already widened in add-batch-costing.sql:11
- [x] 0.2 ~~Re-stamp existing rows in the same migration: `source_id → g...~~ — RESOLVED 2026-10-07 (Phase 0): SUPERSEDED-BY-C-06: no re-stamp migration exists; re-stamping is moot once reader keys on goods_receipt_items.id
- [x] 0.3 ~~Fix writers to use disjoint namespaces: `PurchaseOrder.recei...~~ — RESOLVED 2026-10-07 (Phase 0): PARTIAL: PurchaseOrder stamps GOODS_RECEIPT correctly; PurchaseReturn reader still wrong -> re-opened as C-06

## Phase 1 — Boot-task gating (INV-04, INV-05, INV-09) (~2.5 d)

Independent — can start immediately in parallel with Phase 0.

- [x] 1.1 ~~Reduce the boot self-heal (`config/database.ts` balance rewr...~~ — RESOLVED 2026-10-07 (Phase 0): DONE-IN-TREE: database.ts:411 boot is read-only; discrepancy endpoint referenced
- [x] 1.2 ~~Extract `runUnbatchedStockReconciliation` into an explicit o...~~ — RESOLVED 2026-10-07 (Phase 0): DONE-IN-TREE: package.json:19 repair:unbatched-stock -> scripts/repair-stock.ts
- [x] 1.3 ~~Extract the orphaned-batch cleanup into an explicit reviewed...~~ — RESOLVED 2026-10-07 (Phase 0): DONE-IN-TREE: package.json:20 repair:orphaned-batches -> scripts/repair-stock.ts
- [x] 1.4 ~~Sweep startup path for any remaining INSERT/UPDATE/DELETE ag...~~ — RESOLVED 2026-10-07 (Phase 0): DONE-IN-TREE: boot-task-gating spec published (2 requirements)

## Phase 2 — Physical count batch sync (INV-01, INV-23, INV-24) (~2 d)

Depends on Phase 0 (needs `'ADJUSTMENT'` batch type).

- [x] 2.1 ~~Rework `PhysicalCount.completeCount`: for each variance, ins...~~ — RESOLVED 2026-10-07 (Phase 0): DONE-IN-TREE: PhysicalCount.ts:323,642 consumeFromOldestBatches; :540 ADJUSTMENT layer
- [x] 2.2 ~~Fix movement numbering to use the shared `StockMovement.gene...~~ — RESOLVED 2026-10-07 (Phase 0): DONE-IN-TREE: PhysicalCount.ts:337,598,654 use StockMovementModel.generateMovementNo
- [x] 2.3 ~~Fix the NaN-variance operator-precedence bug in `recordCount...~~ — RESOLVED 2026-10-07 (Phase 0): UNVERIFIED: needs read of recordCount to confirm NaN precedence fix
- [x] 2.4 ~~Tests: shortage consumes FIFO layers with correct JE valuati...~~ — RESOLVED 2026-10-07 (Phase 0): DONE-IN-TREE: physical-count-batch-sync spec has 2 requirements

## Phase 3 — Atomic server-side transfer + guarded sale paths (INV-02, INV-03, INV-06) (~3.75 d)

Depends on Phase 0.

- [x] 3.1 ~~Server: new `POST /api/stock-transfers` performing both legs...~~ — RESOLVED 2026-10-07 (Phase 0): DONE-IN-TREE: routes/inventory.ts:31 POST /stock-transfers + :32 void
- [x] 3.2 ~~Client: update the Flutter transfer dialog to call the new e...~~ — RESOLVED 2026-10-07 (Phase 0): UNVERIFIED: Flutter client change not inspected this session
- [x] 3.3 ~~Route mobile invoice submission (`MobileInvoice.submitInvoic...~~ — RESOLVED 2026-10-07 (Phase 0): UNVERIFIED: lib/ mobile invoice path not inspected this session
- [x] 3.4 ~~Fix `SalesOrder.convertToInvoice` (INV-06): replace the UPDA...~~ — RESOLVED 2026-10-07 (Phase 0): NOT DONE: SalesOrder.ts has no recordBatchMovement -> re-opened as SALES-015/M-01
- [x] 3.5 ~~Regression tests: transfer creates mirrored destination laye...~~ — RESOLVED 2026-10-07 (Phase 0): UNVERIFIED: regression tests not enumerated this session

## Phase 4 — Drift reconciliation migration + DB invariants (INV-21 + repair) (~1.75 d)

Must be LAST: requires all writers fixed (Phases 2–3) so repaired data stays clean.

- [x] 4.1 ~~One-off data-fix migration repairing the four known drift ro...~~ — RESOLVED 2026-10-07 (Phase 0): NOT DONE: no drift-repair migration found
- [x] 4.2 ~~Table-rebuild migration adding `CHECK(quantity >= 0)` on `st...~~ — RESOLVED 2026-10-07 (Phase 0): NOT DONE: no CHECK(quantity>=0) / CHECK on quantity_remaining in any migration
- [x] 4.3 Final integration verification: full suite (typecheck, lint, jest, flutter analyze/test); e2e smoke — complete a count, run a transfer, submit a mobile invoice, restart server twice (no mutation, discrepancies endpoint clean). *(0.5 d)*
