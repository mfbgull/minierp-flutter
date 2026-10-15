# FINDING — Invoice 49 return reconciliation and the customer-15 October cash event

**Status:** Investigation complete. **Documentation only. No live financial data modified.**
**Date:** 2026-10-15
**Subject:** Invoice 49 (`INV-0926-00007`, customer 15) — one or two genuine returns, and the
inventory/GL divergence it creates.
**Related:** `CUSTOMER-15-FINAL-REVIEW.md` (§9 blocked the Strategy C′ correction on this
question), `FINDINGS-STATUS.md` D2b, `server/docs/known-issues.md` item 1,
`docs/REVERSAL-RULES.md`.

---

## 0. Protection of the live database

All inspection was read-only or against isolated copies. Nothing below was written to live.

| Item | Value |
|---|---|
| Canonical live path | `server/database/erp.db` (resolved via `src/utils/serverRoot.ts`) |
| sha256, main file (before and after investigation) | `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f` |
| sha256, WAL-checkpointed logical state | `adef6c7a25a6246ca25cab359096eef1a4f346db847b9c67010e37f99611f83b` |
| Size / mtime | `1966080` / `2026-10-15 20:01:20` (unchanged) |
| `user_version` | `107` |
| `integrity_check` | `ok` |
| Live logical spot-check | `batch#51.quantity_remaining=0`, `je198.voided=0`, `movement#197.batch_id=null` |
| Working copies | `/tmp/d2b/baseline_clean.db` (read-only), `/tmp/d2b/sim_clean.db` (writable) |

No return document was deleted or fabricated. No journal adjustment was posted to live. The
existing decision to defer historical repair (§5) is preserved, not reversed.

---

## 1. Verdict

**Invoice 49 had TWO genuine sales returns.** The financial records (two GL revenue reversals,
two COGS reversals, two subledger `RETURN` rows, two `activity_log` events) are correct for two
returns. The mismatch is real but is **not** a fabricated or double-counted return:

- The **second return was never restocked** into physical stock — a historical defect in the
  stock-reversal guard, fixed forward-only on 2026-09-20 (§4.2).
- The **one restock that did happen** (return 1's `#197`) was never attached to its batch, and a
  **separate spurious journal leg** (`je198`) posted +500 at standard cost instead of the FIFO
  100 that the return actually carried (§4.3).

The GL is **already correct** for two returned units (`je200` +100 and `je206` +100). The defect
is therefore not a missing GL entry but (a) missing *physical* stock and (b) one *extra* GL entry.

The customer-15 October cash event (§3, Event 2) is a **separate defect** and must be reconciled
independently. It does **not** change the invoice-49 return amount.

---

## 2. Chronological timeline — exact records

Invoice header: `total_amount=1800`, `paid_amount=1800`, `returned_amount=1200`, `return_fee=0`,
`credit_offset=0`, `balance_amount=-1200`, `created_at=updated_at=2026-09-16 17:43:53` (the header
was never rewritten after the returns). Item row `invoice_items.id=68`: item 1 ("Widget A",
`WIDGET-A`), `quantity=3`, `unit_price=600`, `amount=1800`, `returned_qty=2`.

| When | Records | Event |
|---|---|---|
| 2026-09-16 17:43:53 | invoice 49; `je195`; `je196`; `stock_movements#196`; `payments#47`/`payment_allocations#41` | Sale: Dr AR 1800 / Cr Revenue 1800. COGS Dr 5000 300 / Cr 1200 300. SALE −3 @ `unit_cost`100, `batch_id=51`. Cash 1800 (PAY047) → fully paid. |
| 2026-09-16 17:44:18 | `activity_log#431`; **`je199`**; **`je200`**; **`stock_movements#197`**; **`je198`**; `customer_ledger#102` | **Return 1** (1 unit, disposition "Customer credit"): Dr 4100 Sales Returns 600 / Cr 1100 AR 600; Dr 1200 Inventory 100 / Cr 5000 COGS 100; restock `ADJUSTMENT` +1 @100 with **`batch_id=null`**; **spurious** `je198` Dr 1200 Inventory 500 / Cr 7100 Inv Correction 500 (standard cost). |
| 2026-09-17 05:38:08 | `invoice#50`; `je203`; `payments#48` | Invoice 50 (1200); CREDIT_OFFSET 600 consumes return-1 credit. |
| 2026-09-17 06:25:17 | `activity_log#436`; **`je205`**; **`je206`**; `customer_ledger#106` | **Return 2** (1 unit, disposition "Customer credit"): Dr 4100 600 / Cr 1100 600; Dr 1200 100 / Cr 5000 100. **No stock movement of any kind.** |
| 2026-09-17 06:28:10 | `invoice#51`; `je209`; `payments#49` | Invoice 51 (1800); CREDIT_OFFSET 1200 consumes return-2 credit + residual. |

Both returns are independently attested by three separate stores — GL (`je199`/`je200` and
`je205`/`je206`), subledger (`customer_ledger#102` and `#106`, each credit 600), and audit
(`activity_log#431` and `#436`, each "Return processed for 1 item(s)… Disposition: Customer
credit"). They occurred on different days, in different seconds, with different activity rows.
There is no duplicate-keying pattern.

**Net GL inventory (account 1200) effect for invoice 49:** −300 (sale `je196`) + 500 (spurious
`je198`) + 100 (`je200`) + 100 (`je206`) = **+400**. The return legs (`je200` + `je206`) are
already correct at +200 for two returned units; the sole GL defect is the extra +500 spurious
leg. Correct invoice-49 inventory effect = −300 + 200 = **−100**.

---

## 3. Two independent economic events (not one)

The user's instruction is explicit: reconcile these separately and **do not** assume the
correction moves from 1,800 to 1,200. They are distinct in time, cause, and accounting effect.

### Event 1 — Rs 1,200 legitimate return credit (September)

Two genuine 600-unit returns on invoice 49 (timeline above). Recorded as:

- `customer_ledger#102` (2026-09-16 17:44:17, RETURN, credit 600) and `#106` (2026-09-17, RETURN,
  credit 600) — total Rs 1,200 of genuine customer credit.
- Consumed by `CREDIT_OFFSET` entries on invoices 50 (`je203`, 600) and 51 (`je209`, 1200;
  600 from return-2 plus 600 residual).

**Treatment:** the Rs 1,200 is correctly earned and correctly posted. The *events* are sound.
What is contested is the **subledger rows** `#104` (600) and `#108` (1200) that recorded the
offsets: per `CUSTOMER-15-FINAL-REVIEW.md` §3 Q2, those rows reduce the balance a second time
(the credit was already created by `#102`/`#106`). That is the D2b double-count, independent of
invoice 49's stock state.

### Event 2 — Rs 1,800 cash received 2026-10-10, misallocated (October)

Reconstructed exactly from the records:

| Time | Records | What happened |
|---|---|---|
| 09:15:05 | `invoice#57` (600); `payments#58` 400; `payment_allocations#51`; `je247`–`je249`; `customer_ledger#125`,`#126` | Invoice 57 opened; PAY-00058 (400) applied → Rs 200 outstanding. |
| 10:52:36 | `payments#60` **Rs 1,400 Easypaisa**; `payment_allocations#53` (200→inv 57), **`#54` (1,200→inv 51)**; `je253` Dr 1020 / Cr 1100; `customer_ledger#129` | Clears inv 57 (200) and **misallocates Rs 1,200 to invoice 51, already Paid since 17 Sep** → ledger balance −1,200. |
| 10:54:41 | `payments#61` **Rs 600 Cash**; **`payment_allocations#55` (600→inv 50)**; `je254` Dr 1000 / Cr 1100; `customer_ledger#130` | **Misallocates Rs 600 to invoice 50, already Paid since 17 Sep** → ledger balance −1,800. |
| 10:56:12 | `invoice#59` (1800); `je255`; `je256`; **`je257` CREDIT_OFFSET 1,800**; `customer_ledger#131` | Invoice 59 created and settled by the accumulated −1,800 "credit". |

**Rs 1,800 of real cash landed on invoices 50 and 51 that were already fully settled**
(`payment_allocations#54` = 1,200 → inv 51; `#55` = 600 → inv 50). That over-payment produced a
−1,800 ledger balance, which `CREDIT_OFFSET je257` then applied to the new invoice 59.

**Two factual corrections to the prior review, established here:**

1. `CUSTOMER-15-FINAL-REVIEW.md` §3 Q3 states `PAY-1026-00060` is **2,000**. The actual amount is
   **Rs 1,400** (Easypaisa). The Rs 1,800 assigned to settled invoices is
   **1,200 (alloc#54 → inv 51) + 600 (alloc#55 → inv 50)**, which is unaffected by the typo but
   must not be re-derived from the wrong payment total.
2. Invoice 59 has **no payment allocation at all** (`payments/allocs touching inv 59: []`) yet
   `paid_amount=1800` via `credit_offset=1800`, and its status is internally inconsistent —
   `status="Unpaid"` while `payment_status="Paid"`, `balance_amount=0`. This is a third,
   independent state-machine defect.

**Independent treatment:**

- **Event 2 is not a customer liability, and it is not a new receivable.** It is Rs 1,800 of cash
  whose *assignment* was wrong. The cash is real (Dr 1000/1020); the AR reduction it caused was
  not earned, because the target invoices were already at zero.
- **The correct economic reading:** invoice 59 (Rs 1,800, created 10:56:12) was effectively paid
  by this October cash. The ledger *presents* it as a credit offset because the misallocation
  created a spurious credit first. Removing the spurious credit (Strategy C′ step 1) without
  recognising where the cash actually belongs is what leaves the Rs 1,800 as an open receivable.
- **Therefore the Rs 1,800 is genuinely owed by customer 15** — but for the reason that invoice 59
  was delivered and its cash was booked against the wrong invoices, **not** because of anything in
  invoice 49.

### Why the two events must not be collapsed

| | Event 1 (return credit) | Event 2 (October cash) |
|---|---|---|
| Amount | Rs 1,200 | Rs 1,800 |
| Date | 2026-09-16/17 | 2026-10-10 |
| Cause | Two genuine returns | Cash misallocated to settled invoices 50/51 |
| Correct effect | AR/revenue reduced by 1,200 | AR reduced on the **invoices the cash was for**, not on 50/51 |
| Invoice 49 relevance | Direct (it is invoice 49's return) | None (invoice 49 was settled in September) |

The Strategy C′ headline figure of **Rs 1,800** does **not** change to Rs 1,200. Invoice 49's
Rs 1,200 return credit is a *different* amount answering a *different* question. Invoice 49's
stored `balance_amount = -1200` is stale and floors to 0 under `calculateInvoiceBalance`; it is
not a recoverable receivable. The Rs 1,800 receivable stands on the October cash defect, and
this investigation removes the **only** obstacle the prior review placed in front of it (the
"unverified assumption" about whether the second return was genuine — now verified genuine).

**Unresolved here:** whether invoice 59's settlement should be re-expressed as a genuine cash
receipt rather than a credit offset. That is a presentation/model question requiring an
unapplied-cash concept (`CUSTOMER-15-FINAL-REVIEW.md` §3 Q4/Q8: no such account exists). It is
flagged in §7, not decided.

---

## 4. Why two units belong to batch 51 — and the GL reconciliation

### 4.1 Physical reconciliation

Batch 51 (`BATCH-0926-PUR-00001`, source `GOODS_RECEIPT`/5, warehouse 1, item 1, warehouse 1):
`quantity_original=10`, `unit_cost=100`, `quantity_remaining=0`, received 2026-09-16.

Movements against batch 51 (verified from `stock_movements WHERE batch_id=51`):

| Movement | Doc | Qty |
|---|---|---:|
| `#189` PURCHASE (GR-0926-0001) | receipt | +10 |
| `#190` SALE | (null docno) | −1 |
| `#191` SALE | INV-0926-00003 | −2 |
| `#193` SALE | INV-0926-00004 | −1 |
| `#194` SALE | INV-0926-00005 | −1 |
| `#195` SALE | INV-0926-00006 | −1 |
| **`#196` SALE** | **INV-0926-00007 (invoice 49)** | **−3** |
| `#198` SALE | INV-0926-00008 | −2 |
| `#199` SALE | INV-0926-00009 | −1 |
| **Total sold** | | **−12** |

Purchased 10, sold 12 → **batch 51 is over-consumed by 2**. `quantity_remaining` is stored
as `0`, not `−2`, because the balance update floors at zero.

Why 2 is exactly the invoice-49 return shortfall:

- Both returns drew their units **out of batch 51** (sale `#196` took 3 units from it). Under
  FIFO both returned units must be credited back to batch 51.
- Return 1 restocked `stock_movements#197` (+1 @100) but with **`batch_id=null`**, so batch 51 was
  never credited. `feature_batch_locations = 0`, so the historical writer took the item-level
  fallback path (the same path used by *every* item-1 return adjustment — `#156`, `#162`, `#165`,
  `#183`, `#185`, `#192`, `#197` all have `batch_id=null`).
- Return 2 produced **no movement at all** (§4.2).

So the two returned units were each restocked at the *item* level (return 1) or not at all
(return 2), and **neither was ever credited to batch 51**. The correct `quantity_remaining` for
batch 51 is `0 + 2 = 2`.

The item-level books are self-consistent and hide the defect: `items#1.current_stock = 19`,
`stock_balances(item 1, wh 1) = 19`, and `SUM(stock_batches.quantity_remaining WHERE item_id=1)
= 19` all agree. Invariant E compares those three values, so it passes and cannot see the
batch-level shortfall. This is why no invariant flags it.

Both facts are separate and both are needed:

1. **Unit 1** was restocked into the item but never attached to batch 51 (missing reference).
2. **Unit 2** was not restocked at all (skipped guard, §4.2).

**Batch 51 is short by 2 units** — not 1.

### 4.2 Why the second restock was skipped — historical code evidence

At the time of the returns (Sep 16–17), the live return writer was
`InvoiceModel.reverseStockForItems` in `server/src/models/Invoice.ts` (HEAD `d54b62c1`, 2026-09-12).
Its guard computed:

```
remainingToReturn = Math.max(0, totalToReturn - alreadyReturnedQty)
```

where `alreadyReturnedQty` was derived from prior `movement_type='ADJUSTMENT' AND
reference_doctype='RETURN'` rows, and `totalToReturn` was the qty of the **current request**.
After return 1, `alreadyReturnedQty = 1`. For return 2, `totalToReturn = 1`, so
`remainingToReturn = 0` and the restock was skipped — while the GL had already posted the full
return value. The guard conflated a per-request quantity with a cumulative one.

**Fixed forward-only** on 2026-09-20 (`6d82f9d5`, "Step 5 — H3"):

```ts
const effectiveRemaining = referenceDoctype === 'RETURN' ? totalToReturn : remainingToReturn;
```

with the comment *"otherwise subsequent partial returns under-restock physical stock while the
GL already posted the full return value."* The current code would have restocked return 2. The
defect is historical; the code path no longer exists.

### 4.3 Why the restock was misvalued — second historical defect

`StockMovementModel.recordMovement` posted `postFinancialEntryForAdjustment` using
`items.standard_cost`. For Widget A `standard_cost = 500`, so `je198` posted Dr 1200 Inventory
500 / Cr 7100 Inventory Correction 500 — but the units physically came from batch 51 at FIFO
**100**. Fixed forward-only via `skipAdjustmentFinancialPosting: true`, with a comment naming
"je=156, je=163, je=184 posted 500 against reversals of 400/400/100."

`server/docs/known-issues.md` item 1 names this directly: *"je=200/je=206 at 49. No code emits
them; 'dedupe' was the wrong treatment."* Both returns genuine; the redundant standard-cost leg
is the third-posting defect.

### 4.4 GL reconciliation — simulated repair vs original entries

**This is the load-bearing reconciliation of the finding.** The GL is *already correct* for two
returned units: `je200` (+100) and `je206` (+100) both exist and net to +200. What invoice 49
lacks is **physical** stock, not a GL return leg. The GL defect is entirely separate — the
spurious `je198` adds +500 that no cost basis justifies.

Verified per-account effect of `je198`: Dr 1200 Inventory 500 / Cr 7100 Inventory Correction 500
(the movement `#197` it references is `reference_id=197`, not 49).

| Entry | Account 1200 effect | Nature |
|---|---:|---|
| `je196` SALE | −300 | Correct (3 units × FIFO 100) |
| `je198` `stock_adjustment` | **+500** | **Spurious — standard cost, no FIFO basis** |
| `je200` RETURN 1 | +100 | Correct (1 unit × FIFO 100) |
| `je206` RETURN 2 | +100 | Correct (1 unit × FIFO 100) |
| **Invoice-49 total** | **+400** | Correct total is **−100** |

Simulated on the isolated copy `/tmp/d2b/baseline_clean.db` → `/tmp/d2b/sim_clean.db` (not live):
credit batch 51 +2; attach `stock_movements#197.batch_id = 51`; **void `je198` only** — no new
journal leg is added, because both return legs already exist.

| Measure | Before | After | Delta |
|---|---:|---:|---:|
| `stock_batches#51.quantity_remaining` | 0 | 2 | **+2** |
| Invoice-49 account 1200 effect | −100 | −100 | **0** (already correct) |
| GL account 1200 Inventory (all refs) | 7029.65 | 6529.65 | **−500** |
| GL account 7100 Inventory Correction | −9366.80 | −8866.80 | **+500** |
| Invariant A (GL balanced per entry) | PASS | PASS | unchanged (0 unbalanced groups) |

**Why these numbers, reconciled with the original journal entries:**

- The **+2 batch units** and the **void of `je198`** are two *independent* repairs to two
  independent defects. The batch repair fixes physical stock (invisible to Invariant E, because
  `items.current_stock`, `stock_balances` and `SUM(batch.quantity_remaining)` all read 19 and
  therefore agree). The `je198` void fixes GL valuation.
- The invoice-49 account-1200 effect **does not change** under the repair, because it was never
  wrong: `je200` + `je206` already carry the two returned units at FIFO 100. Removing the
  spurious +500 leg moves the *total* GL account 1200 by −500 and account 7100 by +500, leaving
  invoice 49 at its correct −100.
- Account 7100 (+500) simply cancels the spurious standard-cost credit. No inventory-correction
  was ever warranted for a FIFO-costed return, so 7100 returns to carrying no invoice-49 effect.

> **An earlier pass of this investigation mis-stated the invoice-49 account-1200 totals as +300
> and simulated an extra +100 FIFO leg.** Both were wrong: the correct pre-repair total is +400,
> and adding a third return leg would have *over*-corrected the GL by +100 while double-counting
> a leg that `je206` already provides. The corrected figures above are re-derived from the
> per-account journal lines and a rebuilt clean baseline. This is recorded because it is exactly
> the kind of double-count that `known-issues.md` warns about with "'dedupe' was the wrong
> treatment."

The simulated repair is **quantitatively illustrative**, not a proposed executable migration —
see §5.

---

## 5. The deferral decision is preserved

`server/docs/known-issues.md` item 1 records the historical rows as **deliberately left broken**:
> *"The historical rows stay broken. This is a deliberate decision … do not write a repair script
> for it without revisiting that decision."*

This finding does **not** revisit or reverse that decision. No historical repair migration is
drafted, no GL adjustment is authorized, and the simulation in §4.4 exists only to quantify the
divergence so a future decision has a measured basis. The frozen baseline gap it contributes to
is the documented **−1533.20** for the scratch database (Invariant H).

**What is authorized:** documentation only.
**What remains deferred:** any live correction of invoice 49's inventory, GL, or batch 51.

---

## 6. Backup evidence

Every available backup was read read-only and compared:

| Backup | `user_version` | Invoice 49 | Invoice-49 GL entries | Invoice-49 movements | `invoice_returns` |
|---|---:|---|---:|---:|---|
| 2026-09-12 | 77 | absent | — | — | table absent |
| 2026-09-30 | 98 | present | 4 | 2 | 0 rows |
| 2026-10-14 | 103 | present | 4 | 2 | 0 rows |
| 2026-10-15 | 107 (live) | present | 4 | 2 | 0 rows |

`stock_movements#197` has `batch_id=null`, `financial_value=500` in **all** post-return backups —
identical to live. The `invoice_returns` table and its writer were introduced 2026-09-19
(`47d16a73`), two days *after* invoice 49's returns, and `add-invoice-returns.sql` states
*"No legacy backfill (spec D11): rows only exist for returns processed after this change"*
(confirmed at `config/database.ts` ~line 1991). The absence of an `invoice_returns` row for
invoice 49 is **by design, not lost or deleted evidence**. This is confirmed in every backup,
including the pre-rework Sep-12 one.

---

## 7. Remaining unresolved accounting decisions

1. **Invoice 59 settlement presentation.** It is settled by `credit_offset = 1,800` with no cash
   allocation and no subledger row, while its ledger row `#131` shows it open. Whether its
   settlement should be re-expressed as a genuine cash receipt requires an unapplied-cash /
   customer-deposit account, which does not exist
   (`CUSTOMER-15-FINAL-REVIEW.md` §3 Q4/Q8). **OPEN — product call.**
2. **Invoice 59 status inconsistency.** `status="Unpaid"` but `payment_status="Paid"`,
   `balance_amount=0`. The reconciliation formula and the status column disagree. Not repaired
   here; the status value is part of the non-reproducible state the rollback snapshot preserves.
3. **`item 1` (Widget A) FIFO vs standard cost.** Invoice 59's COGS (`je256`, 1,500 for 3 units =
   500/unit, from batch 52) uses a different cost basis than invoice 49's returns (FIFO 100 from
   batch 51). Whether the standard-cost fallback remains the policy for items without an active
   FIFO batch is a product call.
4. **Strategy C′ headline figure — reaffirmed at Rs 1,800, not Rs 1,200.** Event 1 and Event 2
   are independent. The prior review's blocker (§11: the second return was an "unverified
   assumption") is now **resolved in favour of the correction** — both returns are genuine — but
   the correction is still **not authorized** by this finding. Re-simulating Strategy C′ against
   the verified figures is a separate step requiring approval.
5. **`CUSTOMER-15-FINAL-REVIEW.md` §3 Q3 correction.** The `PAY-1026-00060` amount is 1,400, not
   2,000. The review document itself is **not edited** by this finding (documentation of a
   separate investigation); the correction is recorded here for anyone re-deriving the figure.

---

## 8. What was not done

- No live financial or stock modification (digest unchanged, §0).
- No deletion or fabrication of return documents.
- No arbitrary journal adjustment.
- No customer-15 correction applied or authorized.
- No automated historical repair, and no executable repair migration drafted.
- No production-code change.

The one actionable output of this investigation is negative evidence removal: the Strategy C′
correction is no longer blocked by an unverified assumption about invoice 49's second return.
Applying it remains a separate, unauthorized decision.
