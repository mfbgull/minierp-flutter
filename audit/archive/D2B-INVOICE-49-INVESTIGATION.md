# D2b — Invoice 49 Sales Return, Inventory and Accounting Investigation

**Invoice:** `INV-0926-00007` (id 49), customer 15, dated 2026-09-16
**Status:** Investigation complete. **Nothing applied to the live database.**
**Live SHA-256 before and after:** `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f` (unchanged)

## Headline

The premise of the blocking question — *"is the second return spurious, making the
customer-15 correction Rs 2,400?"* — is **resolved: both returns are genuine and the
correction stays Rs 1,800.** The financial/inventory mismatch is **not** a missing or
duplicate return. It is a **spurious inventory revaluation leg (`je#198`) plus a
systematic legacy pattern that dropped the second restock movement.**

Resolving invoice 49 does **not** by itself fix customer 15, and it does not change
Strategy C′.

---

## A. Return evidence table

| Event | Source evidence | Financial effect | Quantity effect | GL effect | Verdict |
|---|---|---|---|---|---|
| Invoice 49 raised, 3 units @ 600 | `invoices#49`, `invoice_items#68`, `journal_entries#195/196` | Rs 1,800 receivable; COGS 300 | −3 from batch 51 | Dr 1100 1800 / Cr 4000 1800; Dr 5000 300 / Cr 1200 300 | Verified |
| Paid in full, 2026-09-16 | `payments#47` (PAY047), `payment_allocations#41` | Cash 1800 | — | Dr 1000 1800 / Cr 1100 1800 | Verified |
| Return 1, 2026-09-16 | `journal_entries#199/200`, `customer_ledger#102`, `stock_movements#197` | Credit 600; COGS reversal 100 | **+1 restocked** (`mv#197`, `batch_id=NULL`) | Dr 4100 600 / Cr 1100 600; Dr 1200 100 / Cr 5000 100 | **Genuine** |
| Return 2, 2026-09-17 | `journal_entries#205/206`, `customer_ledger#106` | Credit 600; COGS reversal 100 | **No movement** | Dr 4100 600 / Cr 1100 600; Dr 1200 100 / Cr 5000 100 | **Genuine financially; restock missing** |
| **Spurious leg, 2026-09-16** | `journal_entries#198`, from `stock_movements#197` | **Valued at `items.standard_cost` 500 instead of FIFO `unit_cost` 100** | none | **Dr 1200 500 / Cr 7100 500** | **DEFECT** |
| Credits consumed | `journal_entries#203/209`, `customer_ledger#104/108` | Credit offsets 600 + 1200 | — | Dr 1110 / Cr 1100 | Valid at the time; superseded later |

**Return documents:** `invoice_returns` contains **no row for invoice 49**. This is not
data loss — the table was created by commit `47d16a73` on **2026-09-19**, two days *after*
both returns (09-16, 09-17). The document feature did not exist when these returns were
processed. Its only two rows are for invoice 52 (created 09-18 and 09-20, i.e. after the
feature landed). **Never created — the feature postdates the returns.**

---

## B. Chronological reconstruction

**2026-09-16** — Invoice 49 raised: 3 units of item 1 @ 600 = Rs 1,800. FIFO source batch
51 at unit cost 100. COGS 300. Paid in full (`PAY047`).

**2026-09-16 17:44:17** — Return 1. Revenue reversed 600 (`je#199`), COGS reversed 100 at
FIFO (`je#200`), ledger credit 600 (`#102`), restock movement `mv#197` (+1, `batch_id=NULL`).

*In the same second*, the legacy adjustment leg fired for `mv#197` and posted `je#198`:
Dr 1200 **500** / Cr 7100 500. `StockMovement.ts` computes `Math.abs(quantity) *
unitCost`, but this path fell back to `items.standard_cost` (500) instead of the movement's
own FIFO `unit_cost` (100). This leg is both **wrongly valued** (500 vs 100) and a
**duplicate** of the inventory credit `je#200` had already posted.

**2026-09-17 06:25:17** — Return 2. Revenue reversed 600 (`je#205`), COGS reversed 100
(`je#206`), ledger credit 600 (`#106`) — **but no restock movement was created.**

**2026-09-17** — The two Rs 600 credits were applied to invoices 50 and 51 via
`CREDIT_OFFSET` (`je#203`, `je#209`; ledger `#104`, `#108`). Correct at the time.

**2026-10-10** — `PAY-1026-00060` (1,400) and `PAY-1026-00061` (600) were received and
misallocated to already-settled invoices 50/51, creating an Rs 1,800 spurious credit that
was then consumed as `credit_offset=1800` on invoice 59. **This is the actual customer-15
defect, and it is unrelated to invoice 49.**

---

## C. Root cause

**Historical production defect** (not a current one, not a migration issue).

1. **Spurious revaluation leg.** The legacy stock-adjustment posting path valued the return
   restock at `items.standard_cost` rather than the movement's FIFO `unit_cost`. On invoice
   49 that is 500 vs 100, and it double-counted the inventory credit `je#200` had already
   posted. **Inventory is over-stated by Rs 500; 7100 Inventory Correction carries a
   spurious 500 credit.**

2. **Second restock dropped.** Return 2 created no `stock_movements` row while still posting
   its COGS reversal. This is **systematic, not a one-off** — invoice 52 shows the identical
   pattern: `invoice_return_items` row 1 has `stock_movement_id=202`, row 2 has
   `stock_movement_id=NULL`, while both return *documents* exist.

3. **Current code is correct.** `invoiceReturnService.computeReturnCogs` computes the
   reversal from the actual sale movements' `unit_cost` (FIFO). No production change is
   warranted or authorised.

**Divergence dating:** invoice 49's records are **byte-identical across all four backups**
from 2026-09-30 onward; the 2026-09-12 backup predates the invoice. The defect was present
at creation (09-16) and has never been mutated since.

---

## D. Simulation comparison

All scenarios ran on isolated copies. Every run: `integrity_check=ok`, **0 unbalanced GL
reference groups**. Invariants A–J were **identical in all four** — A, D, E, J pass;
B/C, F, G, H, I fail (pre-existing, untouched).

| Scenario | Invoice 49 GL 1200 | Invoice 49 GL 5000 | Customer 15 | Invariants | Accounting valid? |
|---|---|---|---|---|---|
| Baseline | **+400** (should be −100) | 100 ✓ | 0 (gap 1800) | unchanged | **No** — inventory over-stated 500 |
| **A1** void `je#198` only | **−100** ✓ | 100 ✓ | 0 (gap 1800) | unchanged | **Yes** — GL exactly correct |
| **A2** A1 + restore return-2 restock into batch 51 | **−100** ✓ | 100 ✓ | 0 (gap 1800) | unchanged | **Yes** — GL + stock both correct |
| **B** second return spurious | −200 | 200 | ledger +600 (**gap 1800 → 2400**) | unchanged | **No** — worsens F; contradicts 4 independent record families |
| **C** second return genuine but disposed | −200 | 100 | 0 (gap 1800) | unchanged | **Partly** — needs disposal evidence that does not exist |

**Scenario B is rejected on the numbers**, not merely on judgement: reversing a genuine
return credit pushes customer 15's liability to +600 and inflates invariant F from 1,800 to
2,400. It would make the customer-15 correction worse, not better.

---

## E. Recommended correction

### E1 — Invoice 49 GL (recommended, evidence-complete, no business input required)

Void the spurious leg `je#198` (the only pair of `journal_lines` for
`('stock_adjustment', 197)`), via the production primitive:

```ts
AccountingService.voidJournalLinesByReference(db, 'stock_adjustment', 197, {
  voidedBy: null,
  voidReason: 'D2b: spurious standard-cost duplicate of the FIFO COGS reversal',
});
```

- **Accounting justification:** inventory is over-stated by exactly 500; 7100 carries a
  spurious 500 credit. COGS at 100 is already correct and is untouched.
- **Stock / valuation effects:** none.
- **Customer balance effects:** none.
- **Verification achieved in simulation:** inventory 400 → **−100** (the arithmetically
  correct value), 7100 −9,366.8 → −8,866.8, all unrelated rows byte-identical, rollback exact.
- **Risks:** low. Single reference group, symmetric, reversible.

### E2 — Invoice 49 stock (**requires a business decision — do not apply unilaterally**)

Return 2 has a financial record but no physical stock movement. Two readings, both simulated:

- **If the unit physically arrived and was mis-shelved (recommended reading):** apply A2 —
  create the missing restock attributed to batch 51. Item 1 stock 19 → 20 and
  `items.current_stock`, `stock_balances` and `SUM(batch.quantity_remaining)` **all agree at 20**.
- **If the unit did not arrive:** apply A1 only and treat it as shrinkage via the existing
  damaged-stock write-off flow (decision D7), which requires a reason code.

**No documentary evidence distinguishes these.** The invoice-52 parallel (both return
documents present, second still has no movement) points strongly to a code defect — the unit
arrived and the movement was dropped. That is inference, not proof.

### E3 — Strategy C′ (unchanged, still recommended, still not authorised)

The correction amount **stays Rs 1,800.** Composed with E1, it still resolves F:

| | Baseline | C′ alone | E1 + C′ composed |
|---|---|---|---|
| Invariant F | FAIL (1,800) | **PASS** | **PASS** |
| Customer 15 balance | 0 | 1,800 receivable | 1,800 receivable |
| Invoice 49 GL 1200 | +400 | +400 | **−100 ✓** |

The two economic events are independent and both genuine:

1. **Rs 1,200** September return credit — correctly earned, correctly consumed by the
   September credit offsets. Only its *double-counted* ledger rows are contested.
2. **Rs 1,800** cash received 2026-10-10 — genuinely received, but misallocated to
   already-settled invoices 50/51. **This is the real receivable.**

### Not recommended

- Reversing the second return (Scenario B) — rejected above.
- Fabricating `invoice_returns` documents — the feature did not exist; they would be fiction.
- Any arbitrary journal adjustment — the defect is a specific, identified, voidable group.

---

## F. Verification

| Check | Result |
|---|---|
| Canonical DB path | `server/database/erp.db` via `serverRoot.defaultDbDir()` |
| Schema version | `user_version = 107` |
| Live SHA-256 before | `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f` |
| Live SHA-256 after | `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f` — **unchanged** |
| Live `integrity_check` | `ok` |
| Migrations safe on import | `applyPendingMigrations()` is **not** invoked at import time (DB-INIT-001 fix verified in source) |
| Simulations run on | isolated copies only (`/tmp/opencode/d2b/sim-*`) |
| Backup integrity | all 4 backups + live: `integrity_check=ok`; invoice 49 identical from 2026-09-30 onward |
| Invariants A–J | baseline and all scenarios: A, D, E, J PASS; B/C, F, G, H, I FAIL (pre-existing) |
| Per-customer reconciliation | 0 customers where `current_balance ≠ ledger` |
| Unrelated rows | other customers, other invoices, other ledger rows, payments, allocations, items, stock_balances, stock_batches, stock_movements, return docs — **all IDENTICAL** |
| Only intended change | the 2 `journal_lines` of `je#198`; every other `journal_line` sum unchanged (276,604.15 both sides) |
| Rollback | **exact** — inventory returns to 400, 7100 to −9,366.8, `integrity_check=ok` |
| Files changed | none committed; investigation script removed after use |
| Git status | clean |

---

## Corrections to prior work

- `audit/CUSTOMER-15-FINAL-REVIEW.md` Q3 states `PAY-1026-00060` is **2,000**; it is
  **1,400** (verified: `payments#60`, allocated 200→inv 57 and 1,200→inv 51).
- Invoice 59 is settled by `credit_offset=1800` with **no** cash allocation, and its header
  is internally inconsistent: `status='Unpaid'` but `payment_status='Paid'` with
  `balance_amount=0`.
- The earlier hypothesis that invoice 49's gap implied **Rs 2,400** is withdrawn. Both
  returns are genuine; the correction remains **Rs 1,800**.

## Open decisions for the user

1. **Did return 2's unit physically arrive?** Determines A2 (restock) vs A1 + write-off.
   Evidence gap: no return paperwork exists for September (the feature postdates it).
2. **Invoice 59 presentation** — it needs an unapplied-cash concept that does not yet exist.
3. **Invoice 59 status inconsistency** — `Unpaid` vs `Paid`.
4. **FIFO vs standard-cost policy** for returns — the decision that caused `je#198`.
5. **Strategy C′ application** — proven on isolated copies, still requires explicit approval.

## Restrictions honoured

No live financial modification. No live stock modification. No return documents deleted or
fabricated. No invariant definitions changed. No production-code changes. No customer-15
correction applied. Existing backups and audit history preserved.
---

# Addendum — Final Verification and Correction Readiness (2026-10-16)

Added after the Case 1/Case 2 simulation and the correction-script safety review. Live
database unchanged throughout (`63e61c6a…`, `integrity_check=ok`, `user_version=107`).

## Batch-51 correction (supersedes the earlier A2 target)

Batch 51's true remaining is `quantity_original(10) − sold(12) = −2`, **stored as 0 because the
update floors at zero**. Crediting both returned units therefore yields **0**, not 2.

The batch-level defect is **attribution, not quantity**: `stock_movements#197.batch_id` is null
and return 2 has no movement at all. Setting `quantity_remaining = 2` would push
`SUM(batch.quantity_remaining WHERE item_id=1)` to 21 while `items.current_stock` and
`stock_balances` stay at 19 — **breaking Invariant E**. The corrected item-level target is
**19 → 20**, because only one restock movement is missing at item level, not two.

This corrects `audit/FINDING-invoice-49-return-reconciliation.md` §4.1/§4.4, which states the
target as `0 → 2`. The §4.4 GL conclusion is unaffected and still stands.

## Physical inventory — Scenario C

| Evidence source | Result |
|---|---|
| `physical_counts` / `physical_count_items` | **zero rows** — no stock count has ever been run |
| Damaged / disposal / write-off for item 1 | none (only `mv#180`, expired batch 49) |
| Warehouse transfer records | none for this unit |
| `activity_log` | no corroborating entry |
| Backups | identical from 2026-09-30 onward; 2026-09-12 predates the invoice |

**Physical receipt cannot be established from the database.** A missing movement is not proof of
non-receipt; a financial return is not proof of receipt. Recorded as unresolved — the existing
decision to defer historical inventory repair is preserved.

## October Rs 1,800 — measured disposition

| Transaction | Received | Valid allocation | Invalid allocation | Treatment |
|---|---:|---:|---:|---|
| `PAY-1026-00060` | 1,400 | 200 → inv 57 | **1,200 → inv 51** | genuine receipt |
| `PAY-1026-00061` | 600 | — | **600 → inv 50** | genuine receipt |

The Rs 1,800 was genuinely received and its cash debit stands. Allocations to invoices 50/51
were invalid — both were settled 2026-09-17. The resulting spurious credit was consumed by
invoice 59's `credit_offset=1800`. **Customer intent is not provable from accounting records.**

## Strategy C′ — Case 1 vs Case 2, measured

| Case | Inv 59 balance | Cust 15 receivable | GL 1100 / 1110 | Invariant F | Evidence |
|---|---:|---:|---|---:|---|
| **Case 1** — October cash applied to inv 59 | 0 | 0 | −1,850.20 / 5,350 | **1,800 (FAIL)** | No |
| **Case 2** — cash unapplied (C′) | 1,800 | 1,800 | reconciled | **0 (PASS)** | Yes |

**Case 1 cannot repair invariant F**, and this was measured rather than assumed: re-pointing
the payment allocations changes neither the GL nor the sub-ledger, so
`GL_AR − Σ customer balances` is unchanged at 1,800. The gap originates in the **September
CREDIT_OFFSET mechanism**, not in the October allocation error.

Case 2 is preferred on **evidence** — the allocations were provably invalid — not because it
makes F pass. Both cases were run on isolated copies with `integrity_check=ok` and zero
unbalanced GL groups.

**Product gap:** MiniERP has no unapplied-cash concept, so Case 2 must be represented as an
outstanding invoice balance rather than a customer credit. That is a separate product
requirement, not an accounting fix.

## Correction-script safety (`c1d0c120` → `92d89486`)

`c1d0c120` shipped both correction scripts with **no safety surface at all**: no authorization
gate, no database identity check, no preconditions, no idempotency guard. Both resolve their
database through `config/database`, which falls back to the live `server/database/erp.db`.

`92d89486` adds `scripts/lib/correctionSafety.ts` — four fail-closed gates (exact authorization
token, explicit `DATABASE_PATH`, live exclusion bound to a measured SHA-256, `--apply` flag) —
plus ten preconditions that also make a repeat run a no-op. **Accounting logic unchanged.**

Verified on isolated copies: 7 refusal paths, authorized happy path, idempotency refusal, exact
logical rollback of all 7 financial tables (`activity_log` append-only by design).

**Coverage gap:** `eslint` does not lint `scripts/`, so these files are covered by typecheck and
behavioural tests only.

## Status

**Invariant F and H remain OPEN.** Nothing above marks them resolved; every result is from
isolated simulation. Three decisions remain outstanding and are deliberately not bundled:

1. Physical disposition of invoice 49's second returned unit.
2. Allocation or retention of the October Rs 1,800.
3. Approval of any specific historical correction (invoice 49's `je#198` void is
   evidence-complete and independent of 1 and 2; Strategy C′ requires 2 first).
