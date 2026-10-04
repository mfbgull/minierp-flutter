# Known issues — inventory / GL integrity

Open findings that are **not** guarded by any test. Each was established by
measurement; none has a fix. Do not rediscover these — they cost six
exchanges to characterise and the numbers are easy to mis-frame.

## 1. Invoice-return redundant adjustment leg (CORRECTED 2026-10-04)

**Correction.** This was first pinned as "triple-posting" with a *duplicate
COGS reversal*. That was wrong, and the error was mine: I inferred a code
defect from two journal entries that turned out to be legacy data.

### The duplicate COGS reversal is NOT a code defect

`postCOGSReversalEntry` (`accountingService.ts:1133`) has exactly **one**
caller — `invoiceReturnService.ts:403`, guarded by `if (cogsAmount > 0)`. The
current path cannot double-post.

Measured on the dev database: the only two rows in `invoice_returns` each have
**exactly one** COGS reversal, correctly keyed to the return id
(`return 1 → je=218`, `return 2 → je=223`).

The `je=186`/`je=192` pair is keyed to `reference_id = 45`, and **no
`invoice_returns` row with id 45 exists** — 45 is an `invoices.id`. Those rows
were written before the rework that re-keyed return GL to the return document
(`reference_id = invoice_returns.id`). They are historical rows, not live
emissions. **No code change is warranted, and "dedupe" was the wrong
treatment.** Same for the `je=200`/`je=206` pair at `reference_id = 49`.

The reason this was easy to get wrong: return ids and invoice ids are separate
AUTONCINCREMENT sequences, and several void paths key by one while posting keys
by the other. See the warnings at `Invoice.ts:1028-1044` and
`accountingService:1470-1486`.

### The real live defect: a redundant, misvalued adjustment leg

The invoice-side stock reversal posts inventory to GL **twice** on fresh data:

1. `postCOGSReversalEntry` — Dr 1200 at the true FIFO cost. **Correct.**
2. `postFinancialEntryForAdjustment`, fired from `recordMovement` — a
   `stock_adjustment` entry at `items.standard_cost`, because the return path
   passes `skipBatchCreation` so `batch_id` is null and the poster falls back to
   standard cost.

17 such entries exist on the dev database, and **3 are misvalued**:

| entry | movement | qty | movement cost | standard_cost | posted at |
|---|---|---|---|---|---|
| `je=156` | RETURN | 1 | 400 | 500 | 500 |
| `je=163` | RETURN | 1 | 400 | 500 | 500 |
| `je=184` | RETURN | 1 | 100 | 500 | 500 |

`je=184`'s COGS reversal was 100 while the adjustment leg posted 500 — the
overvaluation measured earlier.

`skipFinancialCostForwarding` (landed in `3c1af576`) does **not** fix this: it
only controls which cost the leg derives, so the leg still fires whenever
`standard_cost != 0`. What is needed is suppression of the leg entirely on the
invoice-return path, because `postCOGSReversalEntry` already posts the inventory
effect. `Invoice.ts:738` is the only setter of the flag, so repurposing it to
suppress rather than re-cost is safe.

**Still open before that change:** whether `posted[]` — the result array from
`reverseStockForItems`, consumed at `invoiceController.ts:545` and `:823` — is a
fourth posting path. Not traced.

## 2. Which stock table is authoritative — undocumented

`stock_batches.quantity_remaining` is what `Dashboard.ts:103-106` and `:460`
value inventory from, ungated by `feature_batch_locations`. The location table
(`batch_stock_by_location`) answers a different question — availability at a
location — and every one of its reads is flag-gated. So master is
authoritative for valuation *today*.

But `add-batch-location-model.sql` never states an intent, and seeds the flag
`'0'`. If a migration was meant to flip authority, it is unfinished and
undocumented. Data-model decision, not a bug.

## 3. Flag-on consumption falls back to legacy (migration incomplete)

With `feature_batch_locations` ON, `consumeFromOldestBatches`
(`StockMovement.ts` ~:900) takes the "no per-location coverage" fallback when a
batch has no `batch_stock_by_location` rows, and returns **`batchId: null`**.
The sale movement then carries no `batch_id`, so `Invoice.ts` ~:663 skips the
restore loop entirely.

Consequence: the flag-on restore branch is unreachable through the normal
purchase → sale → return sequence, and only via direct-insert fixtures like
`batchLocationIntegration.test.ts` 7.6. That is why this class of defect never
showed up in ordinary flows or on the scratch databases.

## 4. Cost-basis forwarding for three callers — LANDED

`postFinancialEntryForAdjustment` re-derived cost from `items.standard_cost`
and ignored the cost the caller recorded and relieved the layer at. For
`PurchaseReturn.ts:443`, `PurchaseReturn.ts:638` and `Production.ts:627` the
adjustment leg *is* the GL posting, so forwarding is correct.

**Landed.** `RecordMovementDTO` gained `skipFinancialCostForwarding`;
`Invoice.ts:738` is the only setter, so the invoice-return exclusion is
explicit rather than an omission.

Measured effect on LIVE: GL 1200 rises by **700.00**, moving the GL-vs-batch
gap from **−1533.20** to **−833.20**.

```
id   doctype          qty  mv_cost  std  fin_val  1200 leg   delta
150  PO_RETURN        -2   300      500  1000     CREDIT   +400.00
152  PO_RETURN        -1   300      500  500      CREDIT   +200.00
153  PURCHASE_RETURN  -1   500      500  500      CREDIT     +0.00
155  PURCHASE_RETURN  -1   400      500  500      CREDIT   +100.00
```

Guarded by `purchaseReturn.test.ts` — seeds a purchase whose batch cost (10)
diverges from `items.standard_cost` (40) and asserts the adjustment leg
credits 40, not 160.

**Do not read −833.20 as the remaining bug.** Item 1's corrections push GL
*downward* — the overvalued adjustment legs and the duplicate COGS reversal
both overstate 1200 — so the two changes move the same number in opposite
directions. Re-measure the gap after item 1 lands.

Historical note:

`postFinancialEntryForAdjustment` re-derives cost from `items.standard_cost`
and ignores the cost the caller recorded and relieved the layer at. For
`PurchaseReturn.ts:443`, `PurchaseReturn.ts:638` and `Production.ts:627` the
adjustment leg *is* the GL posting, so forwarding is correct.

Measured effect on LIVE: GL 1200 rises by **700.00**, moving the GL-vs-batch
gap from **−1533.20** to **−833.20**.

```
id   doctype          qty  mv_cost  std  fin_val  1200 leg   delta
150  PO_RETURN        -2   300      500  1000     CREDIT   +400.00
152  PO_RETURN        -1   300      500  500      CREDIT   +200.00
153  PURCHASE_RETURN  -1   500      500  500      CREDIT     +0.00
155  PURCHASE_RETURN  -1   400      500  500      CREDIT   +100.00
```

The invoice-return caller (`Invoice.ts:737`) is **excluded by design** pending
item 1 — this asymmetry is intentional, not an oversight, and is enforced by
`skipFinancialCostForwarding` rather than left to chance.

---

# Validating a guard before trusting it

Two failure modes caught in the session that produced this file. Both are
checks that *felt* sufficient and were not.

## 1. Run guards in file context, not just targeted

The item-4 guard passed when run with `-t` and failed in the full file. It
hardcoded `item_id = 1`, but `seedPurchase` allocates item ids from a
module-level counter, so the id is only 1 when that test runs first. Every
other assertion still held; only the fixture's premise was wrong.

**Run the guard (a) targeted, (b) with the whole file, and (c) against the
unfixed source.** A targeted green is the weakest of the three. A guard that
only passes in isolation is worse than no guard, because it reads as coverage.

## 2. Ask what the number measures before asking whether the conclusion is nice

`−1700` was `ABS(quantity) × (unit_cost − standard_cost)` — the signed change
in a posted GL amount. It was reported as a divergence contribution, and on its
own would have justified a commit. The actual GL-vs-batch gap on that database
was **−1533.20**, a different quantity with a different sign.

Before a number supports a conclusion, confirm the query computes the thing the
conclusion is about. This is read-only and takes one query.

## 3. Prove the guard can fail

Every landed fix here was checked by reverting the source and confirming the
guard goes red with the *right* number (`Expected 10, Received 6`;
`Expected 40, Received 160`). A guard never observed red has not been shown to
guard anything — the pre-audit `cashImbalances` helper and the stale
scenario-10 skip were both accepted in the earlier report on the strength of
passing tests.
