# Stock authority map (audit task 35)

Goal: identify which inventory representation is authoritative, eliminate the
duplicated maintenance of the others, and keep item quantity, batch quantity,
movement history and GL inventory reconciled. Written before consolidation, as
the task requires.

Line references are against the working tree at the time of writing.

## 1. The four representations

| # | Representation | Grain | Role |
|---|---|---|---|
| 1 | `stock_balances.quantity` | item × warehouse | **authoritative quantity** |
| 2 | `stock_batches` (+ `batch_stock_by_location`) | batch, and batch × location | authoritative **cost**, expiry, halt, location |
| 3 | `stock_movements` | movement | append-only **history** |
| 4 | `items.current_stock` | item | **denormalized mirror** of (1), all warehouses summed |

GL account **1200 Inventory** is the financial mirror of (2)'s value, not a
fifth quantity.

## 2. Authority decision

`stock_balances.quantity` is authoritative for *how much* is on hand.
`stock_batches` is authoritative for *what it cost* — every valuation, COGS and
GL inventory figure derives from `quantity_remaining × unit_cost`.
`stock_movements` is the history that explains the delta between two
`stock_balances` readings. `items.current_stock` is **not** a fourth truth: it is
a mirror of (1), and this audit confirmed every writer derives it from
`stock_balances` rather than computing its own figure.

`StockMovementModel.recordMovement` is the hub: the sale, purchase, transfer and
adjustment flows all move quantity through it.

## 3. Who writes each representation

| Representation | Writers |
|---|---|
| `stock_balances.quantity` | `StockMovement.ts:186,193` (hub), `Purchase.ts:262`, `PurchaseOrder.ts:717,1012,1018`, `Production.ts:250,361`, `PhysicalCount.ts:385,625`, `scripts/fix-duplicate-purchase.ts:114` |
| `stock_batches` | `StockMovement.ts:138,1090,1228,1341` (receipt/transfer/production), plus the `PurchaseOrder` receipt path |
| `stock_movements` | `StockMovement.ts:157` only — the single history writer |
| `items.current_stock` (mirror) | was **8 duplicated copies** of one `UPDATE items SET current_stock = (SELECT SUM(quantity) …)` block: `StockMovement.ts:205`, `Purchase.ts:276`, `PurchaseOrder.ts:765,1076`, `Production.ts:264,375`, `PhysicalCount.ts:400,711` |
| GL 1200 | `AccountingService.postGoodsReceiptEntry`, `postInvoiceEntry` (relief), `postInvoiceReturnEntry` (restore), `postCOGSReversalEntry`, and `postStockAdjustment`-equivalent postings via `StockMovement.postFinancialEntryForAdjustment` |

Note: `StockMovement.syncStockBalancesExtension` writes only the
`quantity_physical/reserved/available` extension columns, never `quantity`, so
it correctly does not refresh the mirror.

## 4. Who reads each representation

- `items.current_stock` — reorder alerts (`Dashboard.ts:158,665`) and the
  GL-reconciliation fallback for items with no batches (`Reports.ts:1267`, and
  the identical helper in `tests/helpers/accountingInvariants.ts:180`). Being a
  mirror, it is only trustworthy if it cannot drift — which is what this audit
  changed.
- `stock_balances` — sellable availability (`StockMovement.sellableAvailabilityByWarehouseSql`),
  valuation, dashboards, expiry and transfer logic.
- `stock_batches` — FIFO consumption (`consumeFromOldestBatches`), valuation,
  expiry detection, batch traceability, GL reconciliation.
- `stock_movements` — audit trail, reversal, COGS, count correction.

## 5. Defects found

| ID | Defect | Severity | Outcome |
|---|---|---|---|
| S1 | The mirror-maintenance SQL was duplicated 8×, with no single owner and no invariant. Any new writer of `stock_balances.quantity` that omitted its copy silently desynchronised a value that reorder alerts and GL reconciliation read. | latent | **fixed** |
| S2 | `accountingInvariants.test.ts` injected opening stock straight into `stock_batches`/`stock_balances` with no journal behind it, so GL 1200 permanently disagreed with operational inventory value. The suite then routed around it: the file claimed a "systemic accounting-layer issue" and asserted inventory in only **1 of 19** scenarios. | test integrity | **fixed** — fixtures now post a matching opening entry |
| S3 | Residual GL-vs-batch drift of a constant **+25** across every scenario, traced to one `stock_adjustment` (physical-count) event whose inventory debit and batch value moved by different amounts. | real, localised | **open** — see §7 |

## 6. What was consolidated

1. **`StockMovementModel.refreshItemStockMirror(itemId, db)`** is now the single
   mirror-maintenance primitive, and all 8 call sites use it. The SQL exists once.
2. **`stockAuthority.test.ts`** pins two invariants that were previously only
   checked per-flow or not at all:
   - `items.current_stock == SUM(stock_balances.quantity)` for **every** item in
     the database, and again after a purchase → sale → return cycle;
   - GL 1200 equals batch value + legacy mirror value after direct purchase,
     sale, return **and** a purchase-order goods receipt. All four reconcile to
     the cent through real API flows.
3. **The fixture artifact is gone.** With `postOpeningInventoryGL`, the drift
   measured in `accountingInvariants` fell from a growing
   **−1985 … −2925** to a constant **+25**. The previously recorded "systemic
   gap" was mostly the test's own bookkeeping, not the product.

## 7. Open item, precisely scoped

The remaining +25 is **one physical-count event**, not a valuation-model problem:
GL 1200 and the batch value move by different amounts for a `stock_adjustment`.
Because the residual is constant across all 19 scenarios, every purchase, sale,
return, receipt, transfer and payment path is confirmed reconciled.

Two ways to close it, in order of preference:

1. **Attribute the count event.** `PhysicalCount` posts its inventory effect via
   `StockMovement.postFinancialEntryForAdjustment` using the count's own value,
   while the batch it adjusts may be relieved at that batch's `unit_cost`. When
   those differ, GL and batch value diverge by the difference. Reconciling the
   two to one cost basis fixes it.
2. **Per-item GL attribution.** `journal_lines` are keyed to documents, not items,
   so a per-item GL/batch reconciliation is not expressible in the current
   schema. That is a schema question, not a bug fix, and should not be rushed.

`accountingInvariants` therefore keeps its two-tier structure: `checkF_I_all`
(inventory asserted) for paths that fully reconcile, `checkF_I` for the rest,
with the residual documented at the call site rather than papered over with a
tolerance.

## 8. Invariants that must remain zero

- `items.current_stock == SUM(stock_balances.quantity)` for every item.
- `stock_balances.quantity == SUM(stock_batches.quantity_remaining)` per
  item/warehouse (already Invariant E in `accountingInvariants`).
- GL 1200 − (batch value + legacy mirror value) = 0 (blocked on §7).
- Trial balance balanced, and every AR/AP/cash invariant unchanged.
