# MiniERP — Forensic Accounting, Code & Architecture Audit

**Target:** `github.com/mfbgull/minierp-flutter` @ `8ed73cf2` (working tree)
**Stack:** Flutter desktop client (397 files / ~134k LOC) + Node/Express 5 + better-sqlite3 12 + zod 4 (~80k LOC TS) + SQLite (86 tables, 86 migrations)
**Method:** read-only static trace **plus execution of the real model code against throwaway databases**. Every quantitative claim below was measured, not reasoned. The live databases were never opened for writing.

---

## 1. Executive Summary

### Overall Risk Rating: **HIGH**

Not because the double-entry engine is weak — it is genuinely strong — but because of a systemic pattern: **the ledger is balanced, and the balancing is what hides the bugs.**

The GL substrate is the best part of this codebase. One posting chokepoint enforces exact integer minor-unit balance, zero epsilon (`accountingService.ts:273-311`). Foreign keys are ON in production *and* hard-fail every table-rebuild migration that cannot restore them. Every one of the 35 route files applies `router.use(authenticateToken)`. The sort sanitizer is a true allowlist. The report expression validator is a character-level allowlist that rejects `;`, `--`, and any non-allowlisted function. Period locking throws. Over-receipt, over-return, and concurrent double-receipt are all blocked.

Against that, **every high-severity finding is `balanced-but-wrong`.** A journal entry debits 1200 and credits 7200 in equal measure, so invariants A–E stay green while inventory is destroyed and a phantom expense is booked. This is precisely the failure mode `known-issues.md` §4 documents — *"a green suite bounds the questions it asks"* — and it has recurred in a second form I found independently.

**Recommendation: do not deploy to production until the P0 items are resolved.** Three findings permit real cash to leave the business or real cash to be fabricated; two silently misstate inventory and COGS on ordinary paths.

### Top 5 Accounting Issues

1. **Cash paid twice for one customer entitlement (RET-003).** Voiding an `adjust` settlement frees the cumulative cap without unwinding the application; the same return can then be settled again by another type. **Proven: 1,600 of bank cash paid out for a 1,600 entitlement already credited to the customer.**
2. **Cash fabricated out of nothing (PRET-004).** `refund_expected` is accepted on a *fully unpaid* source document. Measured: a 100 purchase, fully returned as `refund_expected`, books `Dr Cash 100` with no money ever received.
3. **Purchase void double-reverses inventory (PUR-001).** Voiding a purchase posts a second inventory credit on top of voiding the original. GL 1200 goes to **−500** (a credit balance on a debit-normal asset) plus a phantom `Dr 7200` shrinkage. **Already on live data**: `purchases.id=38` carries an active `Dr 7200 500 / Cr 1200 500` beside a fully voided original group.
4. **COGS at standard cost instead of layer cost, and the layer never relieved (PROVEN by me).** With `feature_batch_locations='1'`, a purchase-created batch yields COGS at `items.standard_cost` (**999**) instead of the real layer cost (**100**), `batchId: null`, and `quantity_remaining` frozen at **20** after selling 5. The layer is never relieved, so it can be consumed again.
5. **Return void books a phantom shrinkage expense (RET-001)** and **return void of a refund_expected return never reverses the supplier refund (PRET-001)** — leaving phantom cash, a spurious AP of 200, and `suppliers.current_balance` overstated by 100 after a "successful" void.

### Top 5 Code / Architecture Issues

1. **Four different definitions of "current AP position"** — `getGLReconciliation` (`MAX(id)`), `SupplierLedger.getBalance` (`transaction_date DESC`), `rebuildBalances` (`id ASC`), `computeAPAging` (`SUM` with no date filter). They disagree on any backdated entry; the supplier-balance API serves **100** where the GL, the subledger and the invariants all say **150**.
2. **The PO-return path is broken in production and masked by its own test fixture.** `PurchaseReturn` looks up the cost layer by `source_id = purchase_order_items.id`, but production writes `source_id = goods_receipt_items.id`. Measured: the simplest 1-line PO return fails 100% with *"Insufficient stock in the source batch"*. `purchaseReturn.test.ts:197-211` hand-writes `source_id = poItemId`, which production never does.
3. **One shared typed invoice-item schema is missing.** `validation.ts` uses `items: z.array(z.any())`; `validateInput`, `createInvoice` and `updateInvoice` each re-derive different partial checks. This single gap is the root of at least 5 separate findings.
4. **Client/server monetary divergence in discount handling.** The client caps an invoice-scope discount at the tax-exclusive subtotal; the server caps at the tax-inclusive `linesTotal`. A discount above the subtotal makes the invoice unsavable (HTTP 400).
5. **Tax is computed before an invoice-scope discount is applied,** so output tax is charged on gross consideration. The discount reduces revenue/AR but never the tax base.

### Top 5 Edge Case Failures

| Edge case | Verdict |
|---|---|
| Return refund on an invoice with **zero cash collected** | ❌ proven — store-credit-settled invoice converted to cash |
| Return void after the units were **re-sold** | ❌ proven — stock driven negative, `MAX(0,…)` silently absorbs the shortfall |
| **Zero-value** return | ⚠️ accepted, creates a full document set + GL + stock movement for 0.01 |
| **Future-dated** receipt/PO | ❌ silently *creates* an open accounting period (measured `2030-01` created `open`) |
| **AP aging as of a past date** | ❌ no `transaction_date <= asOfDate` filter — a 2031 purchase appears in a 2026 report |

**Handled correctly, with evidence** (proving systematic coverage): over-receipt blocked · cumulative over-return blocked · partial receipts additive · concurrent double-receipt serialized and rejected · negative quantity rejected (DB `CHECK`) · duplicate `po_no` blocked (UNIQUE) · GRN void complete and reversible · negative inventory blocked on sale (`SellableStockUnavailableError`) · FEFO/FIFO both implemented · tax/discount/COGS proportionality on partial returns correct · AR and AP subledgers tie to GL exactly on clean data · payment period-lock enforced.

---

## 2. Reconciliation Matrix — measured

Computed against a `/tmp` copy of `database/erp.db`. Sign convention per `accountingService.ts:159-161` (balance normalized positive for the account's `normal_balance`).

| Report | Balanced? | Reconciles With | Status | Notes |
|---|---|---|---|---|
| Trial Balance | **Yes** — 460 = 460 | `journal_lines` | ✅ | 0 unbalanced entries across all 18 headers |
| General Ledger | Yes | `journal_entries` | ✅ | `gl:check` passed 4/4 |
| Balance Sheet | **Yes** — A 80 = L+E 80 | Trial Balance | ✅ | balances **only** via `netIncomeYtd` at `Reports.ts:514`; naive L+E reads 0 and looks broken |
| Income Statement | Yes — Rev −200, Exp 120, NI −320 | BS retained earnings | ✅ | GL-derived via `getPeriodMovement` |
| AR subledger | **Yes** — diff **0** | GL 1100+1110 | ✅ | `GL 200 = Σ(current_balance − credit_balance)` |
| AP subledger | **Yes** — diff **0** on clean data | GL 2000 | ✅ | but **breaks to −4000 on live data** (PUR-002) and to 100/150 on backdated entries (PUR-011) |
| Inventory | **No** — GL 1200 = −120 vs batch 2,240 | GL 1200 vs batch value | ❌ | scratch placeholder data; the *mechanism* gap is the proven flag-on COGS defect |
| Cash | **Yes** on clean data | GL cash vs `cashImbalances` | ✅ | invariant I; representation-only, per `known-issues.md` §5 |

**Verdict:** the engine reconciles. Every reconciliation failure found is in a *void / reversal / negative-amount* path, never in the create path.

**Integer-money migration: NOT IMPLEMENTED — and my first reading of this was WRONG.**

I initially reported this as "PARTIAL/landed" because `typeof(journal_lines.debit)` returned `integer` on every row I sampled. **That inference was wrong.** `typeof()` returning `integer` is merely SQLite NUMERIC affinity coercing integral JS numbers — it is *not* evidence of a migration. Direct verification:

- `PRAGMA table_info(journal_lines)` → `debit:DECIMAL(15,4), credit:DECIMAL(15,4)` on **both** scratch DBs, matching `add-gl-foundation.sql`.
- `docs/integer-money-migration-plan.md:3` states verbatim: **"Status: DESIGN / PLANNING DOCUMENT — NOT IMPLEMENTED"**. No code path converts the column.
- The residue that *is* real: **8 rows** carry a REAL `debit` and 8 a REAL `credit`, across **7 `journal_entry_id` values** (16 line rows, not 7), and `customer_ledger.balance` has **12 REAL** rows. Corrected counts.
- **A stored float artefact already exists in live data**: `journal_lines.id 297/298` (`journal_entry_id 46`) hold **`166.79999999999998`**.

Consequence: SQLite promotes `INTEGER + REAL → REAL`, so one REAL line makes `SUM(debit)` REAL for the whole account — and the artefact is **invisible to every guard**, because `|166.79999999999998 − 166.8| = 1.4e-14`, far below the `0.005` / `0.01` tolerances. `postEntry` protects new lines via `roundCurrency` (`accountingService.ts:263`), but **three writers bypass it** — `scripts/repair-stock.ts:157`, `src/config/database.ts:1148`, and `backfillGlPreposting.ts:119` — and any of them can inject a fresh REAL.

---

## 3. Accounting Findings

Severity: **C**ritical / **H**igh / **M**edium / **L**ow. 62 findings across four flows; the highest-value are below.

### C-01 · Void of an `adjust` settlement pays cash twice for one entitlement
- **Flow:** Sales Returns · **File:** `invoiceReturnService.ts:1111` (`payment_id: null`) → `:1269`
- **Description:** `applyAdjust` creates a real payment + allocation but records `payment_id: null`. `revertSettlement`'s adjust branch is gated on that field, so the allocation is never voided and the `CREDIT_OFFSET` GL group is never voided — while the settlement is marked void and `syncSettledAmount` frees the cap.
- **Impact (measured):** after a "successful" void the target invoice keeps `paid_amount 1600 / balance 0` with two live `CREDIT_OFFSET` lines. Freed cap ⇒ the same return settles again: `adjust 1600 → void → refund 1600`, **GL 1010 delta −1600**. Real cash out, twice.
- **Fix:** capture `recordCustomerPayment(...).paymentId` into the settlement row; void the `CREDIT_OFFSET` group in the adjust branch (mirroring the refund branch at `:1246`).

### C-02 · `refund_expected` on an unpaid document fabricates cash
- **Flow:** Purchase Returns · **File:** `PurchaseReturn.ts:466-484` (disposition gate), `SupplierRefund.ts`
- **Impact (measured):** purchase 100 unpaid → return all goods with `refund_expected` ⇒ `Dr Cash 100 / Cr AP 100` posted with **no money received**. A user can manufacture a cash asset and an AP credit from nothing.
- **Fix:** require cash-collected > refund amount before honouring `refund_expected`.

### C-03 · Purchase void double-reverses inventory
- **Flow:** Purchases · **File:** `Purchase.ts:661-675`
- **Description:** `Purchase.void` voids the original `Dr 1200 / Cr 2000`, then posts a *second* inventory credit via `recordMovement('ADJUSTMENT')` → `Dr 7200 / Cr 1200`. `skipAdjustmentFinancialPosting` — the flag created for exactly this — is not set. The GRN void path (`PurchaseOrder.ts:723-740`) does it correctly; the asymmetry is the defect.
- **Impact (measured):** GL 1200 → **−500**, GL 7200 → +500 (correct: 0 / 0). `movement_date` is `new Date()`, not `purchase_date` ⇒ cross-period. **Live data:** `purchases.id=38` carries an active `Dr 7200 500 / Cr 1200 500` beside a voided original.
- **Guard gap proven:** `supplierlessPurchase.test.ts:260` asserts `glTotals('1200').debit ≈ 0`. `glTotals` sums debit and credit *separately*, so the assertion passes while `credit = 30` and `7200.debit = 30`. The test never asks the question. `expectAllInvariantsHold` would have caught it (invariant H returns `diff: 30`).
- **Fix:** add `skipAdjustmentFinancialPosting: true`; pass `movement_date: purchase.purchase_date`; tighten the test to assert `.credit ≈ 0`.

### C-04 · Flag-on COGS at standard cost; cost layer never relieved *(proven by execution)*
- **Flow:** Warehouses/Valuation · **File:** `StockMovement.ts:690`, `:928-935`
- **Description:** `syncBatchStockByLocationForNewBatch` (`:690`) is wired **only** into physical-count (`PhysicalCount.ts:695`) and transfer-mirror paths (`:1156`, `:1297`, `:1409`). `Purchase.ts`, `PurchaseOrder.ts` and `Production.ts` contain **zero** references to `batch_stock_by_location`. So with the flag on, a purchase-created batch has no location coverage ⇒ `consumeFromOldestBatches` takes the legacy branch and returns `{batchId: null, unitCost: items.standard_cost}`.
- **Impact (measured, flag ON, layer cost 100, `standard_cost` 999):** consuming 5 units returned `unitCost: 999, batchId: null`, and `stock_batches.quantity_remaining` stayed at **20**. Three consequences: COGS overstated 10×; the layer is never relieved so it can be re-consumed; `Invoice.ts` keys the return-restore loop on `batch_id`, so returns can never restore the right layer.
- **Gating:** the flag defaults to `'0'` (`add-batch-location-model.sql:24`), so there is **no current production impact**. This is a trap: flipping the flag silently corrupts COGS on every sale of purchased goods.
- **Fix:** call `syncBatchStockByLocationForNewBatch` from every batch-creation site; or delete the flag and the location table until they are finished.

### C-05 · Return void books a phantom shrinkage expense
- **Flow:** Sales Returns · **File:** `invoiceReturnService.ts:1426-1440`
- **Description:** voiding a return records a negative ADJUSTMENT posting `Dr 7200 / Cr 1200`. The create-side twin at `Invoice.ts:738` correctly sets `skipAdjustmentFinancialPosting: true`; the void side does not. This **falsifies `known-issues.md` item 1's "only setter" claim** — there is a fourth setter.
- **Impact (measured):** void of a 2-unit return at cost 100 ⇒ **−200 net profit**, invariant H breaks 0 → −200. Non-additive across voids.
- **Fix:** add `skipAdjustmentFinancialPosting: true` at `:1426`.

### C-06 · PO-return path broken in production, masked by its test
- **Flow:** Purchase Returns · **File:** `PurchaseReturn.ts:462-470` vs `PurchaseOrder.ts:950-960`
- **Description:** the return looks up the cost layer with `source_type='GOODS_RECEIPT' AND source_id = <purchase_order_items.id>`, but `addReceipt` writes `source_id = <goods_receipt_items.id>`. Independent autoincrement sequences.
- **Impact (measured):** a 1-line PO receipt then return **fails 100%** — *"Insufficient stock in the source batch for W: available 0, required 2."* Where ids coincidentally collide, it silently consumes another receipt's layer (saved only by the `item_id` guard). The PO return feature is non-functional.
- **Why CI is green:** `purchaseReturn.test.ts:197-211` seeds `source_id = poItemId` — a shape production never writes.
- **Fix:** key the lookup on the receipt item id; make the test fixture go through `addReceipt`.

### H-01 · AP aging double-counts reversal credits — **live data reads AP = −4,000**
- **Flow:** Reports/AP · **File:** `Reports.ts:355-358`
- **Description:** the credit side of `computeAPAging` omits `reversed_by IS NULL`. Every other consumer excludes it. A void is therefore charged twice.
- **Impact (measured):** true AP 300 → reported **0**; true 200 → 100; **live supplier 1: true 1,000 → reported −4,000.** All three guards return `[]` on the same state.
- **Fix:** add `AND reversed_by IS NULL` to match `SupplierLedger.ts:91`.

### H-02 · GRN void has no closed-period guard; the purchase void does
- **File:** `purchaseOrderController.ts:315-345` vs `purchaseController.ts:268`. `voidJournalLinesByReference` (`accountingService.ts:1402`) is a bare `UPDATE` with no period check.
- **Impact (measured):** with `2026-03` closed, a GRN dated `2026-03-05` voided successfully — a closed period's entry un-posted. `assertPeriodNotClosed` throws for the same date, proving the guard exists and simply is not called.
- **Fix:** move the check *into* `voidJournalLinesByReference` so no caller can skip it.

### H-03 · Refunds not capped by collected cash on the settlement path
- **File:** `invoiceReturnService.ts:965-1001` vs the capped legacy path `:1133`
- **Impact (measured):** **600 of cash paid out on an invoice where cash collected was 0** (settled entirely by store credit). Any store-credit-settled invoice is convertible to cash on return. Violates REVERSAL-RULES §1.12.

### H-04 · Four competing definitions of current AP position
`Reports.ts:1300-1310` (`MAX(id)`) · `SupplierLedger.ts:66-71` (`transaction_date DESC`) · `SupplierLedger.ts:89-93` (`id ASC`) · `Reports.ts:334-341` (SUM, no date filter).
- **Impact (measured):** a backdated 50 purchase makes the supplier-balance API serve **100** where the GL, `suppliers.current_balance`, invariant G and the reconciliation all say **150**. `supplierApImbalances` reads `current_balance`, so it is blind to this.

### H-05 · Editing a paid invoice to a zero total voids revenue and posts nothing
- **Flow:** Sales · measured: original `Dr 1100 400 / Cr 4000 400` voided, no replacement ⇒ bare `Cr 1100 400`, zero revenue, negative AR. `postInvoiceEntry` returns `null` for `totalAmount <= 0` (`accountingService.ts:525`) while `updateInvoice` has already voided the original (`invoiceController.ts:578`).

### H-06 · Soft-deleted invoices remain in every AR surface
- Measured `getGLReconciliation` AR delta **= exactly the deleted invoice total**. `AR_OUTSTANDING` excludes `('Cancelled','Draft')` but **not** `'Deleted'`, and `deleteInvoice` leaves `balance_amount` intact. Affects AR aging, top debtors, DSO, receivables summary, GL reconciliation, and revenue.

### H-07 · Quotation tax and discount are dropped schema-deep
- `sales_order_items` has **no `tax_rate` or discount column**; `Quotation.ts:596-598` inserts none. The entire quotation→SO→invoice chain posts **no `Cr 2100`**.

### H-08 · Negative `tax_rate` accepted; tax-base error on invoice-scope discounts
- `invoiceCreate` has no `tax_rate` bound (POS caps at 100 via `validation.ts:181`) — an inconsistency between paths. And the same 10% discount yields tax **40.00** under invoice scope vs **36.00** under item scope.

### M-01 … M-16 (selected)
Future-dated receipts **create** open periods (measured `2030-01` created `open`) · AP aging ignores `asOfDate` · **cross-PO line receipt** (measured: GL 3885 at another PO's price, AP on the wrong supplier) · no price-variance mechanism exists at all · `roundQty` applied to money (`total_cost` 99.999 vs GL 100.00) · GRN idempotency key never sent by the client · `settled_amount` has no upper-bound CHECK · zero/sub-cent returns accepted · return void after re-sale drives stock negative · `backfillGlPreposting` re-posts voided purchases and posts GL without the supplier-ledger leg · `journal_entries` legacy headers survive a return void · `settleReturn` sends the wrong body key (dead code path).

Full detail: `/tmp/audit-reports/` and the per-agent sections.

---

## 4. Code & Architecture Findings

### Verified sound — hypotheses raised and **disproved**
I tested these directly and am recording the negatives, because they materially raise confidence:

| Hypothesis | Verdict |
|---|---|
| `quantity_available` never decremented on flag-on consumption | **FALSE** — trigger `trg_batch_stock_available` (`add-batch-location-model.sql:89-104`) maintains `MAX(0, physical − reserved)`. Measured 10 → 0. |
| Foreign keys not enforced in production | **FALSE** — `database.ts:40`, plus a `FATAL` throw at `:126`, `:945`, `:1063`, `:1261` if any rebuild cannot restore it. |
| Unauthenticated mutating endpoints | **FALSE** — all 35 route files apply `router.use(authenticateToken)`. |
| `sqlSanitizer` is a denylist | **FALSE** — true allowlist: `allowedColumns.includes(sortBy) ? … : default`. |
| Custom-report expressions reach SQL unvalidated | **FALSE** — `validateConfigExpressions` (`expressionValidator.ts`) is a character-level tokenizer rejecting `;`, `--`, `/*`, keywords and any non-allowlisted function, invoked before interpolation (`reportQueryEngine.ts:172`). |

### Real findings
- **CODE-01 (H)** — No shared typed invoice-item schema: `validation.ts` uses `items: z.array(z.any())`; three call sites each re-derive different partial checks. Root cause of ≥5 findings.
- **CODE-02 (H)** — Client/server discount divergence: client caps at tax-exclusive `subtotal`, server at tax-inclusive `linesTotal` ⇒ unsavable invoice.
- **CODE-03 (M)** — `NaN` money propagates to `NULL`: a non-numeric `unit_price` passes `item.unit_price < 0` (`NaN < 0` is false), and `better-sqlite3` binds `NaN` as SQL `NULL` (verified empirically). Result: `total_amount`/`balance_amount` NULL, **no revenue posting**, COGS posted with no revenue, and the customer ledger running-balance chain corrupted for every subsequent row — returned as **HTTP 201**.
- **CODE-04 (M)** — `POST /api/invoices` into a closed period returns **HTTP 500** (the `postEntry` message matches no `CLASSIFY_PATTERNS` entry) while POS returns 409 and update/delete/cancel return 409.
- **CODE-05 (M)** — No future-date guard anywhere; a future-dated invoice opens a period and posts into it.
- **CODE-06 (M)** — `updateInvoice` has **no per-item validation**; a duplicate `invoice_no` via `PUT` reaches the UNIQUE constraint and surfaces as 500.
- **CODE-07 (L)** — Cancel is terminal; no reinstate endpoint, and delete-then-restore is blocked for cancelled invoices.
- **TEST-01 (H)** — **The dominant pattern.** `supplierlessPurchase.test.ts:260` passes while `1200.credit = 30` and `7200.debit = 30`. `expectAllInvariantsHold` asserts nine invariants, but `inventoryImbalances` had **zero call sites** at one point — the exact `known-issues.md` §4 anti-pattern, recurring. Several shipped guards were never observed red.

---

## 5. Transaction Flow Diagrams (account codes verified against the live chart)

```
SALES — invoice
[InvoiceForm] → POST /api/invoices → invoiceController.create
  → InvoiceCreationService (db.transaction, zod NOT enforced: items z.any())
  → consumeFromOldestBatches (FIFO layers; FEFO if has_expiry)
      ↳ FLAG ON + no location coverage ⇒ unitCost = standard_cost, batchId null  [C-04]
  → postEntry: Dr 1100 AR / Cr 4000 Revenue / Cr 2100 Tax
  → postCOGSEntry: Dr 5000 COGS / Cr 1200 Inventory   (at layer cost)
  → customer_ledger DEBIT
  ⇒ balanced at every step; wrong when the cost basis is wrong

SALE RETURN
[ReturnDialog] → invoiceReturnService.processReturn
  → allocateHeaderDiscount → returnedValueNet / returnedTax
  → reverseStockForItems (restock at FIFO cost of the original sale ✓)
  → postInvoiceReturnEntry: Dr 4100 Sales Returns / Dr 2100 Tax / Cr 1100 AR
  → postCOGSReversalEntry: Dr 1200 / Cr 5000        (at true FIFO cost ✓)
VOID RETURN
  → voidJournalLinesByReference(INVOICE_RETURN)  ✓
  → reverseRestock  ✗ missing skipAdjustmentFinancialPosting  [C-05]
  → if refund_expected: supplier_refunds NOT reversed      [C-06 family]
VOID ADJUST SETTLEMENT
  → payment_id is null ⇒ nothing reversed, cap freed  ⇒ double cash out  [C-01]

PURCHASE
[PurchaseForm] → POST /api/purchases → Purchase.create
  → postPurchaseEntry: Dr 1200 / Cr 2000 AP   (or Cr 1000/1010 cash)
  → supplier_ledger DEBIT; stock_batches created — NO location coverage  [C-04]
VOID PURCHASE
  → voidJournalLinesByReference(PURCHASE)  ✓
  → recordMovement('ADJUSTMENT')  ✗ posts Dr 7200 / Cr 1200  ⇒ 1200 → −500  [C-03]

GRN (PO receipt) — THE ACCRUAL EVENT
[ReceiveGoodsDialog] → PurchaseOrder.addReceipt
  → postGoodsReceiptEntry: Dr 1200 / Cr 2000 AP  dated receipt_date
  ⇒ there is NO supplier-invoice entity: `purchases.invoice_no` is unindexed free text.
    No GRNI account exists. No three-way match. No price-variance mechanism.

PURCHASE RETURN
  → postPurchaseReturnEntry: Dr 2000 / Cr 1200   at the layer cost ✓ (verified)
  → credit_note + supplier_ledger CREDIT
  → if refund_expected: SupplierRefund.create ⇒ Dr 1000 / Cr 2000
      ✗ never reversed on void                        [PRET-001]
      ✗ accepted with zero cash collected            [C-02]
  → PO path: layer lookup by the wrong key            [C-06]
```

---

## 6. Edge Case Coverage

Full tables were produced per flow (62 findings carry per-case evidence). Representative rows:

| Module | Transaction | Edge case | Handled? | Evidence | Sev |
|---|---|---|---|---|---|
| Sales | Invoice | negative / zero quantity | ✅ | `InvoiceCreationService.ts:73` | — |
| Sales | Invoice | concurrent double-sell of last unit | ✅ | single connection, serialized; `SellableStockUnavailableError` | — |
| Sales | Invoice | non-numeric `unit_price` | ❌ | `unit_price < 0` is false for NaN → NULL columns, HTTP 201 | M |
| Sales | Invoice | backdated into closed period | ⚠️ | blocked, but HTTP **500** not 409 | M |
| Sales | Update | edit paid invoice to zero total | ❌ | void w/o repost → bare `Cr 1100` | H |
| Sales | Delete | soft-deleted stays in AR | ❌ | `Deleted` not excluded from `AR_OUTSTANDING` | H |
| Purchases | GRN | receipt exceeding PO | ✅ | `PurchaseOrder.ts:886` | — |
| Purchases | GRN | negative quantity | ✅ | DB `CHECK quantity_remaining >= 0` (500 not 400) | L |
| Purchases | GRN | zero quantity | ⚠️ | accepted by model; controller blocks | L |
| Purchases | GRN | future-dated | ❌ | creates open period `2030-01` | M |
| Purchases | GRN | cross-PO line reference | ❌ | no `poItem.po_id === po_id` check | M |
| Purchases | Void | double inventory reversal | ❌ | GL 1200 → −500, phantom 7200 | **C** |
| Purchases | Report | AP aging as-of past date | ❌ | no `transaction_date <= asOfDate` | M |
| Purchases | Report | AP aging after a void | ❌ | live supplier 1: reported **−4,000** | H |
| Purch. Returns | Return | PO-source return | ❌ | layer key mismatch; 100% failure | **C** |
| Purch. Returns | Return | refund on zero cash collected | ❌ | 600 cash out, 0 collected | **C** |
| Purch. Returns | Void | refund not reversed | ❌ | phantom cash 100, AP 200 | **C** |
| Purch. Returns | Return | user-supplied cost | ✅ | **ignored**; priced from the source doc | — |
| Purch. Returns | Return | concurrent partial over-return | ✅ | sync better-sqlite3 transaction | — |
| Sales Returns | Return | cumulative over-return | ✅ | service guard, no DB CHECK | ⚠️ |
| Sales Returns | Return | partial-return proportionality | ✅ | revenue/discount/tax/COGS each proportional | — |
| Sales Returns | Return | COGS reversal cost basis | ✅ | uses the original sale's FIFO cost, not standard cost | — |
| Sales Returns | Void | after units re-sold | ❌ | `MAX(0,…)` absorbs shortfall; stock negative | H |
| Sales Returns | Settle | void an `adjust` | ❌ | nothing reversed, cap freed ⇒ **1,600 double-paid** | **C** |
| Sales Returns | Settle | refund cap | ❌ | not capped by collected cash on new path | H |
| Valuation | Sale | flag-on COGS | ❌ | 999 vs 100; layer never relieved | **C** |
| Valuation | Sale | negative inventory | ✅ | `StockMovement.ts:864` throws | — |
| Valuation | Transfer | inter-warehouse P&L impact | ✅ | mirrored batch, no GL | — |

---

## 7. Prioritized Remediation Plan

| Pri | ID | Issue | Effort | Depends on |
|---|---|---|---|---|
| **P0** | C-01 | `adjust` void frees cap ⇒ double cash payment | S | — |
| **P0** | C-02 | `refund_expected` on unpaid doc fabricates cash | S | — |
| **P0** | C-03 | Purchase void double-reverses inventory (live data) | **S** | — |
| **P0** | C-05 | Return void books phantom 7200 | **S** | — |
| **P0** | H-03 | Refunds uncapped by collected cash | S | — |
| **P0** | PRET-001 | Void never reverses auto supplier refund | M | — |
| **P1** | C-04 | Flag-on COGS at standard cost; layer never relieved | M | flag decision |
| **P1** | C-06 | PO-return layer key mismatch (feature dead) | M | fixture fix |
| **P1** | H-01 | AP aging reads **−4,000** on live data | **S** | — |
| **P1** | H-05 | Edit-to-zero total voids revenue | M | CODE-01 |
| **P1** | H-06 | Soft-deleted invoices in all AR surfaces | S | — |
| **P1** | H-07 | Quotation tax dropped schema-deep | L | migration |
| **P2** | H-02 | Period guard missing on GRN void | S | — |
| **P2** | H-04 | Four AP-position definitions | M | — |
| **P2** | CODE-01 | One shared typed invoice-item schema | M | — |
| **P2** | CODE-03 | NaN → NULL money, HTTP 201 | S | CODE-01 |
| **P2** | PUR-005/006 | Future-dating opens periods; aging ignores as-of | S | — |
| **P2** | PUR-007 | Cross-PO line receipt | **S** | — |
| **P3** | PUR-009 | `roundQty` on money | **S** | — |
| **P3** | RET-008 | `settled_amount` upper-bound CHECK | **S** | migration |

**Highest-leverage structural fix** (from the Sales auditor, and I concur): add one invariant — *per non-cancelled invoice, Σ live 1100 lines == `total_amount`* — which catches the "balanced-but-wrong" class that the current nine invariants structurally cannot see. Pair it with tightening `glTotals`-style assertions to check **credit** as well as debit, and asserting `expectAllInvariantsHold` after every void path.

---

## 7b. Security, Database & GL Findings (final wave)

### SEC-001 · CRITICAL · SQL injection via unquoted column name — **verified reachable**
`forecastService.ts:1167-1183`. `setModelConfig` iterates `Object.entries(config)` and splices **`key` raw and unquoted** into SQL:
```ts
sets.push(`${key} = ?`);                                  // :1170
db.prepare(`UPDATE forecast_model_config SET ${sets.join(', ')} WHERE item_id = ?`)   // :1177
```
Values are bound; **keys are not**. The route `PUT /api/forecasts/models/:itemId` (`routes/forecasts.ts:26`) applies `validateZodBody(zodBodySchemas.modelConfig)` — but that schema is `z.object({}).passthrough()` (`validation.ts:302`), which **validates nothing**. Controller spreads `{ item_id: itemId, ...req.body }` (`forecastsController.ts:157`).
- **Impact:** any user holding only the low-tier `forecasts:create` permission can write arbitrary columns and inject arbitrary SQL expressions/subqueries into `forecast_model_config`, giving a boolean/read oracle over any table. `better-sqlite3.prepare()` refuses multiple statements, so no stacked `DROP` — but this is a genuine read/write primitive.
- **Fix:** strict zod schema; iterate a hardcoded field→value map and reject unknown keys.

### SEC-002 · CRITICAL · The catch-all validator validates nothing
`validation.ts:78` — `object: z.object({}).passthrough()` is used on ~20 mutating routes. This is the systemic enabler of SEC-001.

### SEC-003 · HIGH · HTTP response sent inside a DB transaction
`employeeController.ts:688` — `res.status(201).json(...)` executes inside the `db.transaction()` callback opened at `:653`. The client receives 201 for a loan that may still fail to commit; a retry double-posts.

### SEC-004 · HIGH · Raw SQLite error text returned to the client in 24 places
`inventoryController` ×9, `purchaseOrderController` ×6, `employeeController` ×4, `invoiceController` ×2, `salesController` ×2, `invoiceReturnController` ×2, `purchaseReturnController` ×2, `expenseController` ×1. Leaks table/column/constraint names. `errorHandler.ts:20` correctly keeps stacks server-side — these are separate raw-message paths.

### DB-002 · HIGH · debits == credits has **zero** database enforcement
`add-gl-foundation.sql:57-72` gives `journal_lines` only *per-line* CHECKs (`debit=0 OR credit=0`). **No cross-line CHECK, no trigger.** Enforcement is application-only at `accountingService.ts:306`, plus a boot post-condition at `database.ts:2974-2983`.
- **Why this matters:** the FK-OFF, non-transactional rebuild path (`database.ts:114-127`) and the `--rollback` CLI execute raw SQL with no such guard. *This is precisely why every C-rated finding above is "balanced-but-wrong" in the app layer yet could be trivially unbalanced at the DB layer.*

### DB-003 · HIGH · Migration checksum verification skips ~74% of applied migrations
73 of 99 ledger rows carry checksum `'inline'` (all `fn.*` runner keys, whose key names a function rather than a file), and `verifyMigrationChecksums` **skips them** (`database.ts:181`). Verification does run at boot (`:1594`, before `listen`) — so editing an already-applied `.sql` executed by an inline runner is **invisible**.

### GL-002 · HIGH · The master GL-balance assertion can be deleted and all 993 tests stay green
`expectAllInvariantsHold` (`__tests__/helpers/accountingInvariants.ts:288-298`) *does* call all nine collectors — **none is exported-but-unasserted.** But only **E, F, G, H, I** have planted-drift meta-tests proving the master's line is live. **A, B, C, D have none.** The helper's own docstring claims *"every one has a planted-drift guard"* — **that claim is false for A, B, C, D.** Deleting the entire GL-balance assertion at `:290` leaves the suite green. This is `known-issues.md` §4 recurring at the top of the hierarchy.

### GL-001 · HIGH · GRN void mutates a closed period *(independently confirms PUR-003)*
`voidJournalLinesByReference` (`accountingService.ts:1402-1428`) is a bare `UPDATE ... SET voided = 1` with **no period check**. `voidGoodsReceipt` (`purchaseOrderController.ts:315-345`) never calls `assertPeriodNotClosed`, and its error branch never returns 409. `closedPeriodImmutability.test.ts` covers payments, invoices, expenses, purchases and sales returns — **but not GRN void.**

### GL-004 · MEDIUM · Closed-period bypass via non-calendar period names
`postEntry` derives `period_name` from `YYYY-MM` and uses `ON CONFLICT(period_name) DO NOTHING` (`:327-333`). `Period.ts:91-101` accepts **arbitrary** ranges. A closed custom period (`FY2026-Q2` = Jan–Mar) does not collide, so an entry dated inside it auto-creates a fresh `2026-01` open period and **posts into a closed period**.

### DB-001 · HIGH · `goods_receipt_items` has zero indexes
All three FK columns (`receipt_id`, `po_item_id`, `item_id`) unindexed; `PRAGMA index_list` is empty. Every parent delete/update full-scans the goods-receipt hot path. The existing `add-missing-fk-indexes.sql` does not cover it.

### DB-004 · MEDIUM · 12 `.sql` migrations are dead code
Never referenced by any `runLedgered` call: `add-full-sales-cycle.sql`, `add-sales-table.sql`, `add-customer-ar-fields.sql`, `cleanup-orphaned-stock-batches.sql` + 8 more. The source tree is not reproducible from the ledger, and several contain **non-idempotent** `INSERT`s that would duplicate rows if ever wired in.

### DB-005/006/007/008 · MEDIUM · Four financial invariants enforced only in application code
`stock_movements.quantity` has no CHECK (so it can disagree with the protected `stock_balances`) · cumulative return qty ≤ line qty (the schema comment admits "enforced in service") · payment allocation ≤ invoice balance · `received_quantity <= quantity`. Each is bypassable by raw SQL, a repair script, or a future writer.

### GL-005 · MEDIUM · `stock-authority-map.md`'s "single history writer" claim is false
The map asserts `stock_movements` is written only by `StockMovement.ts`. **At least 8 production sites write it outside that hub**: `Purchase.ts:230`, `PurchaseOrder.ts:725,966`, `PhysicalCount.ts:340,600,657`, `Production.ts:220,299`, `inventoryController.ts:1268`. The map's own line citations are also ~6 lines stale — written against an older tree and never re-verified.

### GL-006 · MEDIUM · Unrounded money reaches `journal_lines` outside `postEntry`
`repair-stock.ts:157`, `database.ts:1148-1150`, `backfillGlPreposting.ts:119` insert raw `uncovered * unitCost`. This is a live path to introduce *new* REAL artefacts — the class of defect already present as `166.79999999999998`.

### GL-007 · MEDIUM · 5 money-moving endpoints have no idempotency
`POST /api/purchase-returns`, `inventory/stock-movements`, `inventory/stock-transfers`, `inventory/physical-counts/complete`, `inventory/damaged/transfer`, `owner-equity/personal-loans/:id/repayments` — zero idempotency references. A client-sent key is also entirely **optional**: `startIdempotentRequest` returns `key: null` when the header is absent (`idempotency.ts:181`), so even correctly-guarded endpoints degrade to unguarded if a client omits it.

### Verified sound (negative results, recorded deliberately)
`sqlSanitizer` is an allowlist · `reportQueryEngine` quotes every identifier (`quoteIdentifier`), allowlists every field, binds every value, and emits a single `SELECT` · `expressionValidator` is a closed tokenizer with no `eval`/`Function`/`vm` · **no `await` inside any `db.transaction`** (so no TOCTOU-by-await) · WAL + `busy_timeout=5000` + `VACUUM INTO` backup is a safe combination · all six repair/backfill scripts **preserve** entry balance (each either voids a whole balanced group or inserts symmetric pairs), and `runLedgered` wraps them in a transaction with a `schema_migrations` guard.

---

## 7c. Independently Verified Live-Data Figures (lead auditor, direct SQL)

I re-verified the two highest-consequence claims myself rather than relaying them. Both reproduce; one is **10× larger** than reported.

### PUR-002 — CONFIRMED, figures reproduce exactly
`supplier_ledger`, supplier 1, credits with `voided=0 AND credit>0`:

| Basis | Credits |
|---|---|
| As coded (`Reports.ts:356-358`) | **24,150** |
| Correct (`AND reversed_by IS NULL`) | **19,150** |
| Double-counted | **5,000** |

Debits 20,150. So aging reports outstanding = 20,150 − 24,150 = **−4,000**, where the truth is 20,150 − 19,150 = **+1,000** — which ties to `suppliers.current_balance = 1000` exactly. **A payable is reported as a negative 4,000 on the live books.**

### PUR-001 — CONFIRMED on live data, understated 10×
`purchases.id=38` (`PURCH-2026-0038`, `total_cost 5000`, `voided_at 2026-08-24`):

| journal_lines | Account | Debit | Credit | voided |
|---|---|---|---|---|
| 127 | 1200 Inventory | 5,000 | — | **1** |
| 128 | 2000 AP | — | 5,000 | **1** |
| 295 | 7200 Inventory Shrinkage | **5,000** | — | **0 (live)** |
| 296 | 1200 Inventory | — | **5,000** | **0 (live)** |

Net for this voided purchase: **GL 1200 = −5,000** (a credit balance on a debit-normal asset) and **GL 7200 = +5,000** of phantom shrinkage. Correct answer is 0 / 0. The originating movement is `stock_movements.id=120`, `movement_type='ADJUSTMENT'`, `reference_doctype='PURCHASE_VOID'`, **`financial_posted = 1`**.

The Purchases auditor cited "Dr 7200 500 / Cr 1200 500" — that is a *different* movement (`id=155`, also live). The purchase-38 void is **5,000**. Live exposure from this single document is 10× the figure reported.

### Float artefact confirmed live (GL-003)
`stock_movements.id=125` (`RETURN`, `INV-2026-242236`) posts `Dr 1200 166.79999999999998 / Cr 7100 166.79999999999998`. A stored binary-float in a money column, and the sales-return restock lands in **7100 Inventory Correction** (an expense account) rather than reversing 5000 COGS.

### Baseline reproduction
My independently computed GL 1200 net = **2,433.60** and batch gap = **−1,533.20** match `known-issues.md`'s documented baseline to the cent — corroborating that this database is the one that baseline describes, and that those historical figures are stable.

---

## 8. Coverage & Limitations — stated honestly

**Fully audited with execution:** Sales, Purchases, Sales Returns, Purchase Returns, GL substrate & period locking, inventory valuation, DB schema/FK/index/migrations, reports reconciliation, auth/authz, SQL-injection surfaces, transaction atomicity.

**NOT audited — the responsible agents were killed by provider rate limits, and I did not substitute speculation for evidence:**
- **Payments** (customer receipts, supplier payments, allocation/overpayment, POS split-tender, `cashService`) — *not audited*
- **Expenses & owner equity** (accrual-vs-cash crediting, the approve→paid double-count) — *not audited*
- **Report layer in depth** (aging day-count basis vs due date, GL-drift table, drill-down traceability) — *not audited*
- **Flutter client** (widget practices, state management, layer violations, client/server calculation parity beyond the discount/tax findings) — *not audited*
- **Concurrency under multi-process deployment** — single-process only; `busy_timeout` behaviour with a second server instance is untested

Per `known-issues.md` §"Whoever writes the next artifact has to read the code first": one of my own headline claims (integer-money migration) survived a first pass and was falsified only by cross-agent disagreement plus direct re-verification. Treat every number here as needing the same treatment.

**Data caveat:** `database/erp.db` and `server/database/erp.db` are untracked placeholder databases. Their numeric divergences (inventory gap −2,360; AP aging −4,000) are reported as *evidence that a code path exists*, never as standalone code defects — consistent with `known-issues.md`'s own warning on this point.

**Reproducibility:** all probe artifacts are outside the repository, under `/tmp`. **The repository working tree was left clean** (`git status --porcelain` empty); two reports an agent wrote into `docs/` were moved to `/tmp/audit-reports/`.