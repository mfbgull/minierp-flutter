# Known issues — inventory / GL integrity

Open findings that are **not** guarded by any test. Each was established by
measurement; none has a fix. Do not rediscover these — they cost six
exchanges to characterise and the numbers are easy to mis-frame.

## 1. Invoice-return redundant adjustment leg — FIXED (forward only)

Resolved in two steps. Both are **code-only**: neither repairs historical
journal entries, and the dev-database gap is therefore unchanged.

### The duplicate COGS reversal was never a code defect

`postCOGSReversalEntry` (`accountingService.ts:1133`) has exactly **one**
caller — `invoiceReturnService.ts:403`, guarded by `if (cogsAmount > 0)`. The
current path cannot double-post. Measured: the only two `invoice_returns` rows
each have exactly one reversal, keyed to the return id.

The `je=186`/`je=192` pair is keyed to `reference_id = 45`, and **no return with
id 45 exists** — 45 is an `invoices.id`. Pre-rework rows. Same for
`je=200`/`je=206` at 49. **No code emits them; "dedupe" was the wrong
treatment.** The trap: return ids and invoice ids are independent sequences,
and void paths key by one while the posting path keys by the other — warned
about at `Invoice.ts:1028-1044` and `accountingService:1470-1486`.

### The real defect, and the fix

The invoice-side reversal posted inventory to GL **twice on fresh data**:
`postCOGSReversalEntry` (correct, at true FIFO cost) and then
`postFinancialEntryForAdjustment` (redundant, at `items.standard_cost` because
the return path sets `skipBatchCreation` so `batch_id` is null). 17 such legs
existed on the dev database, 3 misvalued (`je=156`, `je=163`, `je=184` posted
500 against reversals of 400/400/100).

`RecordMovementDTO.skipFinancialCostForwarding` (`3c1af576`) only picked the
leg's cost, so it still fired whenever `standard_cost != 0`. Replaced with
**`skipAdjustmentFinancialPosting`**, which suppresses the leg entirely.
`Invoice.ts:738` is the only setter. `unit_cost` stays on the movement for the
audit trail and `posted[]` consumers.

`posted[]` was checked and is **not** a fourth posting path: the return value
is discarded at all four call sites, and `invoiceReturnService.ts:365` uses it
only for `m.item_id` FK bookkeeping.

### Guard

`invoiceReturnAcceptance.test.ts` scenario 9 — a dedicated item with
`standard_cost = 999` (with `standard_cost = 0` the leg is dormant and the
assertion would pass without the fix). Asserts exactly one `INVOICE_RETURN`
1200 posting for that return, at the FIFO cost, and zero adjustment legs.
Scoped to its own return id: unscoped, it passes in isolation and fails in file
context, which is trap 1 below.

Verified red by reverting the source — the leg query returned **6** entries
where 0 were expected — and green after.

### What is NOT fixed

**Historical rows are unrepaired.** The dev database still holds 21 redundant
`stock_adjustment` legs from invoice-side movements, and its GL-vs-batch gap is
**−1533.20** — unchanged by either fix. Any earlier figure describing what
these commits "do to the gap" is a **projection of a replay, not a
measurement**. There is no repair script and none is planned; both databases are
untracked scratch (`.gitignore:51-61`).

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
