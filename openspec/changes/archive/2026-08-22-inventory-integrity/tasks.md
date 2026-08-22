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

- [ ] 0.1 Write the table-rebuild migration widening `stock_batches.source_type` CHECK to `('PRODUCTION','PURCHASE','GOODS_RECEIPT','RETURN','ADJUSTMENT','OPENING','TRANSFER','RECON')`; preserve all rows, quantities, costs and indexes across the rebuild; verify idempotency (second run = no-op). *(0.5 d)*
- [ ] 0.2 Re-stamp existing rows in the same migration: `source_id → goods_receipt_items.id` resolves ⇒ `'GOODS_RECEIPT'`; synthetic reconciliation rows (`source_id = 0`) ⇒ `'RECON'`; direct-purchase rows stay `'PURCHASE'`. Add a post-migration assertion that no row has an unresolvable namespace. *(0.5 d)*
- [ ] 0.3 Fix writers to use disjoint namespaces: `PurchaseOrder.receiveGoods` stamps `GOODS_RECEIPT`; confirm `Purchase.recordPurchase` stays `PURCHASE`; update `Purchase.delete`'s batch lookup so it can never cross namespaces; add a regression test (delete a purchase when large `goods_receipt_items` ids exist). *(0.5 d)*

## Phase 1 — Boot-task gating (INV-04, INV-05, INV-09) (~2.5 d)

Independent — can start immediately in parallel with Phase 0.

- [ ] 1.1 Reduce the boot self-heal (`config/database.ts` balance rewrite from `SUM(stock_movements)`) to a read-only comparison that logs discrepancies (item id, warehouse id, both values) at startup; add admin-only `GET /api/admin/health/stock-discrepancies`. Test: restart against a DB with known gaps → row counts and `quantity_remaining` byte-identical before/after. *(0.75 d)*
- [ ] 1.2 Extract `runUnbatchedStockReconciliation` into an explicit opt-in script (`npm run repair:unbatched-stock`): scope cost average to `(item_id, warehouse_id)` inbound `PURCHASE`/`PRODUCTION` movements only; post a balancing JE per capitalised amount; settings-flag idempotency ("nothing to do" on second run); trim over-covered batches instead of ignoring them. *(0.75 d)*
- [ ] 1.3 Extract the orphaned-batch cleanup into an explicit reviewed script (`npm run repair:orphaned-batches`): refuse any batch with `quantity_remaining > 0.0005` (report as "needs manual review"); NEVER set `stock_movements.batch_id = NULL` — tombstone or retain links so every movement reference still resolves. *(0.5 d)*
- [ ] 1.4 Sweep startup path for any remaining INSERT/UPDATE/DELETE against `stock_movements`, `stock_balances`, `stock_batches`, `items.current_stock`; add a test asserting boot leaves those tables untouched (no `BATCH-*-RECON-*` rows created). *(0.5 d)*

## Phase 2 — Physical count batch sync (INV-01, INV-23, INV-24) (~2 d)

Depends on Phase 0 (needs `'ADJUSTMENT'` batch type).

- [ ] 2.1 Rework `PhysicalCount.completeCount`: for each variance, inside one `.immediate()` transaction write the ADJUSTMENT movement, update `stock_balances` + `items.current_stock`, and update `stock_batches` — FIFO-consume oldest layers on negative variance (JE valued at consumed layers' actual costs), insert a `source_type='ADJUSTMENT'` batch at `item.unit_cost` on positive variance. Post-completion invariant: `SUM(quantity_remaining)` per (item, warehouse) equals balance. *(1 d)*
- [ ] 2.2 Fix movement numbering to use the shared `StockMovement.generateMovementNo(db)` generator (kill epoch-suffixed ad-hoc numbers — INV-23); test sequential `STK-yyyy-nnnn` across a multi-item count. *(0.25 d)*
- [ ] 2.3 Fix the NaN-variance operator-precedence bug in `recordCount` (INV-24) and make a missing `physical_count_items` snapshot row abort with a validation error instead of writing zero variance. *(0.25 d)*
- [ ] 2.4 Tests: shortage consumes FIFO layers with correct JE valuation; surplus creates the cost layer and raises valuation by `variance × unit_cost`; batch coverage equals new balance exactly. *(0.5 d)*

## Phase 3 — Atomic server-side transfer + guarded sale paths (INV-02, INV-03, INV-06) (~3.75 d)

Depends on Phase 0.

- [ ] 3.1 Server: new `POST /api/stock-transfers` performing both legs inside one `.immediate()` transaction — FIFO consumption at source warehouse, mirror batch at destination (`source_type='TRANSFER'`, linked to the source batch), both movements written server-side; input validation (qty > 0, sufficient availability inside the transaction). *(1 d)*
- [ ] 3.2 Client: update the Flutter transfer dialog to call the new endpoint once (remove the two-call orchestration); toast feedback on success/failure; keep offline error handling per ERROR_HANDLING rules. *(0.5 d)*
- [ ] 3.3 Route mobile invoice submission (`MobileInvoice.submitInvoice`) through the same guarded, batched, GL-posted path as desktop invoices (availability check inside transaction, batch consumption via shared consumer, GL posting, document-number `reference_docno`). *(1 d)*
- [ ] 3.4 Fix `SalesOrder.convertToInvoice` (INV-06): replace the UPDATE-only balance write with `recordBatchMovement` so batches are consumed and a missing `stock_balances` row cannot silently skip deduction; test SO→invoice with no pre-existing balance row. *(0.75 d)*
- [ ] 3.5 Regression tests: transfer creates mirrored destination layers at same unit cost; mobile invoice and SO→invoice both leave batch coverage == balances == SUM(movements). *(0.5 d)*

## Phase 4 — Drift reconciliation migration + DB invariants (INV-21 + repair) (~1.75 d)

Must be LAST: requires all writers fixed (Phases 2–3) so repaired data stays clean.

- [ ] 4.1 One-off data-fix migration repairing the four known drift rows — item 15 −5, item 1 +2, item 2/WH1 −3.722, item 2/WH2 +10 mirror batch — each with its balancing journal entry; backup-first; assert post-state: batches == balances == movements for every (item, warehouse). *(0.75 d)*
- [ ] 4.2 Table-rebuild migration adding `CHECK(quantity >= 0)` on `stock_balances` and `CHECK(quantity_remaining <= quantity_original AND quantity_remaining >= 0)` on `stock_batches` (INV-21); runs only after 4.1 verified clean; verify existing rows pass and a violating write fails loudly. *(0.5 d)*
- [x] 4.3 Final integration verification: full suite (typecheck, lint, jest, flutter analyze/test); e2e smoke — complete a count, run a transfer, submit a mobile invoice, restart server twice (no mutation, discrepancies endpoint clean). *(0.5 d)*
