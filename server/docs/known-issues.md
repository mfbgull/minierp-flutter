# Known issues — inventory / GL integrity

Open findings that are **not** guarded by any test. Each was established by
measurement; none has a fix. Do not rediscover these — they cost six
exchanges to characterise and the numbers are easy to mis-frame.

## 1. Invoice-return triple-posting (HIGH, undiagnosed)

One sales return posts inventory to GL 1200 **three times** on live data.
Measured on `server/database/erp.db`, invoice `INV-0926-00003`:

| entry | reference_type | 1200 leg |
|---|---|---|
| `je=182` | INVOICE | Cr 200 (COGS) |
| `je=186` | INVOICE_RETURN | Dr 100 (COGS reversal) |
| `je=192` | INVOICE_RETURN | Dr 100 (COGS reversal) — **identical to 186** |
| `je=184` | stock_adjustment | Dr 500 ("Stock addition: 1 units @ 500") |

Two independent defects underneath:

- **Duplicate COGS reversal** — `je=186` and `je=192` carry byte-identical
  descriptions. Survives any cost-basis work. Separate bug.
- **Overvalued adjustment leg** — `je=184` posts `items.standard_cost` (500)
  where the cost actually reversed is 100.

Blocking question before any fix: **which poster is authoritative on the
return path?** `Invoice.ts` ~:661-700 restores the layer, the return service
posts the COGS reversal, and `postFinancialEntryForAdjustment` posts a third
entry. Suppressing the wrong one makes things worse. Until that is answered,
neither suppression nor cost-forwarding is correct here.

### The second `avgUnitCost` site — checked, and NOT a second posting path

`Invoice.ts:737` is the only `recordMovement` call that passes `avgUnitCost`.
`Invoice.ts:752` is the same call's cost echoed into the `posted[]` result
array, not a separate GL posting. So there is one reversal call site to exclude,
not two, and the exclusion comment at `Invoice.ts:730` is complete as to call
sites.

**Open question that remains:** `posted[]` is consumed by callers
(`invoiceController.ts:545` and `:823` both consume from batches). Whether any
caller posts GL inventory from `posted[].unit_cost` — making it a fourth
potential inventory poster alongside the return service and the adjustment leg
— has **not** been verified. Check this before concluding item 1 accounts for
every posting on the return path, and keep `posted[].unit_cost` consistent with
whatever the authoritative poster turns out to be.

Related: in a fresh fixture with `standard_cost = 0` the adjustment leg is
dormant (`financial_posted=0`) because `postFinancialEntryForAdjustment`
early-returns on `value === 0`. Forwarding a caller cost would **wake it** and
add a fourth posting. That is why the invoice-return caller must be excluded
from any cost-forwarding change.

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

## 4. Cost-basis forwarding for three callers — authorized, not started

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

The invoice-return caller (`Invoice.ts:722`) is **excluded by design** pending
item 1 — this asymmetry is intentional, not an oversight.

Note the residual **−833.20** is unexplained, and item 1's corrections push GL
*downward*, so the two interact. Re-measure the gap after any of these lands.
