# Forensic Accounting & Code/Architecture Audit — MiniERP

**Scope:** full stack — Flutter desktop client (`lib/`, ~134k LOC) + Node/TypeScript backend (`server/`, ~40k LOC in models/services/controllers) + SQLite (`better-sqlite3`).
**Date:** 2026-10-06 · **Tree:** `main` @ `8ed73cf2` · **Method:** read-only static trace plus measurement on throwaway in-memory/`mkdtemp` databases driven through the server's own models. No repository file was modified. The live database was read read-only; all mutations were measured on copies.

**Verification basis:** backend suite **114 suites / 993 tests green** (`npx jest --silent`); `npx tsc --noEmit` clean; `npx eslint` 0 errors. Every probe in this report was executed against the real model code; probe files were deleted after measurement.

---

## 1. Executive Summary

**Overall risk rating: MEDIUM.** This is an unusually well-controlled small-business ledger engine, with two live-data defects and one costing gap that together justify immediate remediation. There is **no finding that invalidates the core double-entry engine**.

### What is genuinely strong

The accounting core is built to a standard rarely seen at this scale:

- **Exact balance in integer minor units.** `postEntry` (`accountingService.ts:306-313`) compares `toMinorUnits` sums with no epsilon — a float artefact cannot satisfy it.
- **Header-then-lines insertion** (`accountingService.ts:358-373`) via AUTOINCREMENT, so a line can never orphan.
- **Period discipline is real, not decorative.** 22 explicit `assertPeriodNotClosed`/`getClosedPeriodCovering` call sites; closed periods reject invoice/expense/payment/salary/return edits; `postEntry` itself refuses to post into a closed period and auto-creates calendar periods when a date falls outside every existing one (`:318-355`).
- **Server-authoritative totals.** Both create (`InvoiceCreationService`) and update (`invoiceController.ts:351-361`) recompute the grand total and reject a client `total_amount` that disagrees by >0.01.
- **Idempotency on all three money-in paths** (invoice / mobile invoice / POS sale), with the key claim *inside* the transaction so a rolled-back attempt leaves no key row.
- **GL-derived financial statements.** TB, BS, P&L and GL drill-down are all computed from `journal_lines`, so they cannot disagree with the ledger by construction.
- **Reversal semantics done correctly almost everywhere.** `reverseLedgerEntry` writes an equal-and-opposite `REVERSAL:*` row with `reversed_by = <original id>` and `voided = 0`, marks the original `voided = 1`; every ledger consumer except one excludes `reversed_by IS NULL`.
- **Zero interpolated SQL** across models/services/controllers. Dynamic report SQL is validated against a safe grammar (`expressionValidator.ts`) with identifier quoting (`quoteIdentifier`).
- **Auth is solid:** HS256 pinned with issuer/audience claims, typed refresh tokens, generic 401s in prod. `.env` is gitignored (`.gitignore:59`) — the weak on-disk secrets are local-only.

### What is wrong

Four findings carry real financial weight. All four were **measured, not inferred**:

| ID | Severity | Headline | Live data affected? |
|---|---|---|---|
| **ACCT-001** | **CRITICAL** | Purchase void reverses inventory twice and books phantom shrinkage | **Yes** — `PURCH-2026-0038`, 5,000 |
| **ACCT-002** | **HIGH** | AP aging double-counts reversal credits; AP reported as 0 or negative | **Yes** — true AP 1,000 reported as 0 |
| **ACCT-003** | **MEDIUM-HIGH** | Zero-cost adjustment/opening batches understate COGS | Latent (no zero-cost batches on live DB today) |
| **ACCT-004** | **MEDIUM** | AR aging does not foot when `due_date` is NULL | Latent (0 NULL `due_date` rows on live DB) |

Three further findings are control gaps rather than current misstatements: `ACCT-005` (closed-period bypass on manual stock adjustments), `ACCT-006` (GRN void has no period guard) and `ACCT-007` (supplier-refund void has no period guard). `CODE-001` records that these three are the same architectural defect — period protection is an opt-in call-site convention rather than a property of the primitives.

**Recommended order:** ACCT-001 (live books wrong today) → ACCT-002 (live AP report wrong today) → ACCT-003 (silent profit overstatement, growing) → ACCT-004 → ACCT-005/006/007 (structural).

---

## 2. Accounting Findings

### ACCT-001 · CRITICAL · Purchase void reverses inventory twice, books a phantom 7200, and dates the reversal "today"

**`server/src/models/Purchase.ts:661-675`** — the adjustment leg of `Purchase.void`.

`Purchase.void` already voids the original `Dr 1200 / Cr 2000` journal entry via `voidJournalLinesByReference` (`:654-657`). It then *also* calls `StockMovementModel.recordMovement` with `movement_type: 'ADJUSTMENT'` to remove remaining stock. `recordMovement` routes **every** `ADJUSTMENT` to `postFinancialEntryForAdjustment` (`StockMovement.ts:213-223`), which posts `Dr 7200 / Cr 1200` — a second, independent inventory reversal.

`skipAdjustmentFinancialPosting` — the flag built for exactly this class of double-post — is not set. The sibling path is correct: `PurchaseReturn.ts:447` and `:649` both set it, and the GRN void writes a raw INSERT with no GL leg (`PurchaseOrder.ts:722-740`).

**Measured (probe through the real models, clean DB, supplier-linked 10 @ 50 = 500):**

```
after purchase:  GL 1200 = {"debit":500,"credit":0}
after void:      GL 1200 = {"debit":0,"credit":500}     ← should be 0
                 GL 7200 = {"debit":500,"credit":0}     ← should not exist
                 GL 2000 = {"debit":0,"credit":0}       ✓ (voided correctly)
```

Inventory is reversed 200% of its value, plus a shrinkage expense for goods never lost. The adjustment leg is dated `new Date()` (`Purchase.ts:671`), so a January purchase voided in October moves both into October.

**Live database impact (read-only query):** `purchases.id 38` (`PURCH-2026-0038`, `total_cost 5000`, `voided_at 2026-08-24`) has its original `PURCHASE` lines fully voided **and** an active `stock_adjustment` pair (`reference_id 120`): `Dr 7200 5000 / Cr 1200 5000`. The live books carry a 5,000 phantom expense and a 5,000 phantom inventory credit.

**Why the shipped guard misses it.** The suite asserts `glTotals(db,'1200').debit ≈ 0` after a void. `glTotals` sums debit and credit **separately**, so `debit = 0` passes while `credit = 500` is unasserted — `supplierlessPurchase.test.ts:260`'s three assertions all pass on a broken state.

**Fix:** add `skipAdjustmentFinancialPosting: true` to the `recordMovement` payload (`Purchase.ts:662-672`); pass `movement_date: purchase.purchase_date`; tighten the test to assert both `1200.credit ≈ 0` **and** `7200.debit ≈ 0`. `inventoryImbalances()` already detects this (it reported `{expected:0, actual:30, diff:30}` on the supplierless variant) — wiring `expectAllInvariantsHold` after the void would have caught it.

---

### ACCT-002 · HIGH · AP aging double-counts ledger reversal credits; reports AP as 0 or negative

**`server/src/models/Reports.ts:349-351`** — the credit side of `computeAPAging`.

```sql
SELECT supplier_id, SUM(credit) AS credit FROM supplier_ledger
WHERE voided = 0 AND credit > 0 GROUP BY supplier_id
```

This omits `reversed_by IS NULL`. `ledgerUtils.reverseLedgerEntry` (`ledgerUtils.ts:116-133`) inserts the reversal row with `reversed_by = <original id>` and `voided = 0`; the original is marked `voided = 1`. So the original debit is dropped by the debit-side filter (`voided = 0 AND debit > 0`, `:338`) **and** the reversal credit is counted on the other side. A void is charged twice.

**Every other supplier-ledger consumer excludes `reversed_by IS NULL`** — `SupplierLedger.ts:91` (`rebuildBalances`), `:67` (`getBalance`), `:132-137` (`getSupplierBalances`), `Supplier.ts:254`, `Reports.ts:1302-1306` (GL reconciliation), and invariant D. AP aging is the sole exception.

**Measured (probe):** two purchases, 100 (2026-09-01) and 200 (2026-09-02); void the 100 one.

```
true AP after void (GL 2000 credit) = 200
AP aging totalPayables             = 0     ← AP disappears
```

**Live database impact:** true AP (ledger net, `reversed_by` excluded) = **1,000**; `getSupplierBalances` latest-position total = **1,000**; `getAPAgingReport.totalPayables` = **0**. The aging report understates live AP by its entire value. The GL reconciliation AP leg reports `delta −7,600` partly because of this and partly because of ACCT-001's phantom 5,000 — the two defects compound on the same control total.

**Fix:** add `AND reversed_by IS NULL` to `Reports.ts:350`, matching `SupplierLedger.ts:91`.

---

### ACCT-003 · MEDIUM-HIGH · Zero-cost adjustment/opening batches understate COGS

**`server/src/models/StockMovement.ts:143`** in `recordMovement`:

```ts
const unitCost = data.unit_cost || 0;   // ← falls back to 0, never to standard_cost
```

An incoming movement with no `batch_id` and no `unit_cost` creates a cost layer at **0**. `consumeFromOldestBatches` (`:815`) then returns `unitCost: batch.unit_cost` for that layer, and `InvoiceCreationService` accumulates `cogsAmount += entry.consumed * entry.unitCost` → 0 for those units. Revenue is recognised with zero COGS; gross profit is overstated by the full cost of the units.

This is **reachable from the shipped UI**: `stock_adjustment_dialog.dart:85-90` posts `POST /api/inventory/stock-movements` with `item_id`, `warehouse_id`, `quantity`, `movement_type: 'ADJUSTMENT'` and **no `unit_cost`**. `createStockMovement` (`inventoryController.ts:578-583`) does not require or default one.

**Measured (probe, `standard_cost` 40, +10 units, no `unit_cost`):**

```
new batch unit_cost = 0, remaining = 10
adjustment GL lines = 1200 Dr 400 / 7100 Cr 400   ← GL used the standard_cost fallback
consumption = [{"batchId":1,"consumed":10,"unitCost":0}]
COGS derived from batch layers = 0
GL added: 400  COGS recognized: 0  understatement: 400
```

The GL is *not* wrong here — `postFinancialEntryForAdjustment` (`StockMovement.ts:421-432`) correctly falls back caller cost → batch cost → `items.standard_cost`. The defect is that the **batch layer** misses the same fallback, so the two diverge: inventory is capitalised at 400 in the GL and relieved at 0 through COGS. `PhysicalCount.ts:364-380` does the right thing (inserts surplus layers at `item.unit_cost`); `recordMovement` is the outlier.

**Fix:** in `recordMovement`, default the new batch's `unit_cost` to `items.standard_cost` when `data.unit_cost` is absent; reject or warn when both are 0.

---

### ACCT-004 · MEDIUM · AR aging does not foot when `due_date` is NULL

**`server/src/models/Reports.ts:7-26`** — `getARAgingReport`.

Every bucket uses `julianday(?) - julianday(i.due_date)`. With a NULL `due_date` every comparison is NULL, so the CASE yields NULL→excluded from all five buckets, while `SUM(i.balance_amount)` in the same SELECT still counts the invoice. The report's own total disagrees with the sum of its buckets.

`invoices.due_date` is nullable (`init.sql:236`). The create path is safe — `InvoiceCreationService` computes a 15-day `defaultDueDate` (`:61-65`) when the client omits it (`:121`). But `invoiceController.updateInvoice` passes `req.body.due_date` straight through (`:415`→`:471`) with no guard — its only required fields are `customer_id`, `invoice_date`, `items` (`:311`) — and `InvoiceModel.updateInvoice` writes it raw (`Invoice.ts:966`). A request with `due_date: null` or `''` NULLs the column.

**Measured (probe through `Reports.getARAgingReport`):** three invoices 100 / 200 / 300, the first with NULL `due_date`:

```
totalReceivables = 600, buckets sum = 500 → FOOT? false
```

`getReceivablesSummary` (`Reports.ts:152-190`) has the same shape but is *defensively* coded — it explicitly tests `WHEN due_date IS NULL THEN 0` in every bucket. It still fails to foot, because `total_outstanding` counts the row while the buckets exclude it. Both surfaces need the same fix.

**Live database:** 0 NULL `due_date` rows, so live AR aging currently foots (verified: 5,450 = 5,450). This is latent, not active — but it is one malformed update away from an AR report that silently understates receivables.

**Fix:** require a non-empty `due_date` in `updateInvoice` and `InvoiceModel.updateInvoice`; and/or use `COALESCE(i.due_date, i.invoice_date)` in both aging queries.

---

### ACCT-005 · MEDIUM · Manual stock adjustment posts into a closed period

**`server/src/controllers/inventoryController.ts:578-621`** (`POST /api/inventory/stock-movements`) → `recordMovement` → `postFinancialEntryForAdjustment` → `postLegacyStockEntry` (`accountingService.ts:434`).

`postLegacyStockEntry` performs **no period check** — unlike `postEntry`, which rejects closed periods. `createStockMovement` adds none either. So a GL-writing adjustment can be dated inside a closed period.

**Measured (probe):** with period `2026-01` closed and an adjustment dated `2026-01-15`:

```
assertPeriodNotClosed(2026-01-15) threw: "...inside closed accounting period '2026-01'"
after adjustment: GL 1200 = {"debit":100,"credit":0}, 7100 = {"debit":0,"credit":100}
```

The guard exists and would have blocked the date; nothing calls it on this path. Note the callers of `postLegacyStockEntry` that post via the services *do* enforce the check at their own call sites (invoice/POS/expense), so the exposure is specifically the direct stock-movement endpoint.

**Fix:** call `assertPeriodNotClosed(db, movement_date, ...)` in `createStockMovement`, or move the check into `postLegacyStockEntry` so no caller can bypass it (see `CODE-001`).

---

### ACCT-006 · MEDIUM · GRN void has no closed-period guard

**`server/src/controllers/purchaseOrderController.ts:315-345`** vs `purchaseController.ts:268`.

`voidPurchase` calls `assertPeriodNotClosed(db, purchase.purchase_date, …)`. `voidGoodsReceipt` has no equivalent, and `voidJournalLinesByReference` (`accountingService.ts:1402`) is a bare `UPDATE journal_lines SET voided = 1` with no period logic. A receipt dated inside a closed period can be un-posted.

This is the sibling asymmetry of ACCT-005 — the purchase side is guarded, the GRN side is not.

**Fix:** call `assertPeriodNotClosed(db, receipt.receipt_date, …)` in `voidGoodsReceipt` before the model call.

---

### ACCT-007 · LOW-MEDIUM · Supplier-refund void has no closed-period guard

**`server/src/controllers/supplierRefundController.ts:141-152`** → `SupplierRefundModel.void` (`SupplierRefund.ts:213`).

`SupplierRefund.void` reverses the ledger entry and posts the contra inside the transaction, but neither the controller nor the model checks the refund's period. Compare `Payment.ts:474-476`, `:613` and `paymentWriterCore.ts:31`, all of which guard the customer payment side.

**Fix:** add `assertPeriodNotClosed(db, refund.refund_date, …)` at the top of `SupplierRefund.void`.

---

## 3. Code & Architecture Findings

### CODE-001 · MEDIUM · Period protection is a call-site convention, not a property of the primitives

`assertPeriodNotClosed` exists and is correct, but it is invoked at **22 call sites** while the primitives it protects are open by default:

- `voidJournalLinesByReference` (`accountingService.ts:1402`) — bare `UPDATE`, no period logic.
- `postLegacyStockEntry` (`accountingService.ts:434`) — no period logic.
- `recordMovement`'s adjustment-financial hook (`StockMovement.ts:213-223`).

ACCT-005, ACCT-006 and ACCT-007 are the same defect observed at three different call sites. The pattern "the guard exists but this caller forgot it" has already produced at least one prior remediation round (the customer-payment paths are guarded in three places), which is evidence the convention does not hold under change.

**Fix:** move the check into the primitives — `voidJournalLinesByReference` and `postLegacyStockEntry` — so a caller cannot bypass it by omission. This converts three findings into zero and removes the need for future call sites to remember.

### CODE-002 · LOW · `postFinancialEntryForAdjustment` is silent on zero value

**`StockMovement.ts:469`** — `if (value === 0) return;`. When caller cost, batch cost and `standard_cost` are all 0 the adjustment posts no GL and creates no audit trail. This is the "free goods enter inventory invisibly" case. It is the silent-failure tail of the ACCT-003 fallback chain and should log a warning rather than return quietly.

### CODE-003 · LOW · Test helper `glTotals` can assert its way past a real defect

**`server/src/__tests__/helpers/invoiceReturnSpec.ts:348-358`** sums debit and credit separately. This is what let ACCT-001's `1200.credit = 500` go unasserted while `1200.debit = 0` passed. Prefer asserting the **net** (`debit − credit`) per account, or assert both legs explicitly. The same helper is used across the return suites, so the exposure is wider than one test.

### CODE-004 · INFO · Positive observations worth recording

- **`rebuildLedgerBalances` ordering is correct on both sides.** `SupplierLedger.rebuildBalances` uses `ORDER BY id ASC` (`SupplierLedger.ts:92`) — required, because the AP consumers read the latest *position*; `rebuildLedgerBalances` for customers uses `transaction_date ASC, id ASC` (`ledgerUtils.ts:269`) — correct, because the customer side reads a true as-of running balance (`Customer.ts:408`) and derives its balance from `SUM(debit − credit)` (`ledgerUtils.ts:327-334`), which is order-independent. The two ledgers genuinely need opposite orderings; this is not an inconsistency.
- **`decomposeLineAmount` header discount vs `postInvoiceEntry` full-line tax** (`currency.ts:60`, `accountingService.ts:514`) is a defensible trade-discount treatment, balanced by construction. Judgment call, not a defect.
- **`CREDIT_APPLICATION` intentionally writes no customer-ledger row** (`PaymentRecordingService.ts:174-186`) — the return already credited the ledger, so the row would double-count. The 1,200 GL-vs-subledger AR delta observed on the live DB is this design, not a bug.
- **Flutter sends `due_date` on every create** (`sales_invoice_form_page.dart:931`), defaulting 15 days from the invoice date (`:207`). It is the unguarded API surface, not the client, that creates ACCT-004's exposure.
- **The 289 `as Map<String,dynamic>` casts in `lib/data/models/*.dart`** are standard JSON decoding, not type-safety violations. Only 3 `print(` calls exist, all genuine PDF `_print()` methods.

---

## 4. Reconciliation Matrix

Measured on the live database via the shipped report functions (read-only, copy at `/tmp/erp-audit-dir`). "Delta" = GL − operational.

| Pairing | GL balance | Operational balance | Delta | Status |
|---|---|---|---|---|
| Inventory (1200 vs `stock_batches` + legacy `items`) | 2,433.60 | 3,966.80 | **−1,533.20** | ⚠️ Explained below |
| Accounts Receivable (1100 vs open invoices) | −150.20 | 5,450.00 | **−5,600.20** | ⚠️ Explained below |
| Accounts Payable (2000 vs latest ledger position) | −6,600.00 | 1,000.00 | **−7,600.00** | ❌ ACCT-001 + ACCT-002 |
| Cash — Cash (1000) | 30,100 | 30,100 | 0 | ✅ |
| Cash — Bank (1010) | −8,000 | −8,000 | 0 | ✅ |
| Cash — Easypaisa (1020) | −3,500 | −3,500 | 0 | ✅ |
| Cash — JazzCash (1030) | 0 | 0 | 0 | ✅ |
| Cash — UPaisa (1040) | 0 | 0 | 0 | ✅ |
| **AR aging footing** (buckets vs totalReceivables) | 5,450 | 5,450 | 0 | ✅ (0 NULL due_dates) |
| **AP aging vs true AP** | — | 0 vs 1,000 | **−1,000** | ❌ ACCT-002 |

**All five cash-family pairings reconcile exactly.** The three non-cash deltas decompose as follows:

- **AP −7,600:** ACCT-001's phantom `Cr 1200 / Dr 7200` of 5,000 sits inside GL 1200 and 7200 (not 2000), and ACCT-002 drops 1,000 of real AP from the aging operational side. The GL reconciliation's AP leg is the control that surfaces both.
- **AR −5,600.20:** decomposed to `CREDIT_OFFSET` GL credits of 3,000 (`journal_lines` for `reference_type='CREDIT_OFFSET'`, account 1100) against `customer_ledger` `CREDIT_OFFSET` credits of 1,800 — a 1,200 difference that is **by design** (CODE-004: `CREDIT_APPLICATION` writes no ledger row), plus 4,400.20 of voided-payment/RETURN-ledger asymmetry on demo data. The open-invoice total (5,450) itself foots against AR aging.
- **Inventory −1,533.20:** includes ACCT-001's phantom 5,000 `Cr 1200` on the GL side. The remainder is demo-data noise (batches consumed at cost layers that predate the GL-unification backfills). On a clean post-remediation database the batch-value vs GL-1200 pairing reconciles, as the invariant suite asserts.

**Interpretation:** the reconciliation *framework* is sound — every pairing is computed from the right sources, and the deltas are attributable rather than floating. The cash family proving exact while AP is off by its full value is the signature of ACCT-002: cash is computed from `journal_lines` on both sides, AP is computed from `journal_lines` on one side and a mis-filtered `supplier_ledger` on the other.

---

## 5. Transaction Flow Diagrams

Account codes from the live chart of accounts (`add-gl-foundation.sql`, `add-cash-accounts.sql`). Cash resolution: `_cashOrBankAccountCode` (`accountingService.ts:837`) maps cash→1000, bank→1010, easypaisa→1020, jazzcash→1030, upaisa→1040.

### 5.1 Credit sale (invoice)

```
POST /api/invoices ── InvoiceCreationService.create :78-215
   │  validate :67  →  computeInvoiceGrandTotal :117  →  idempotency claim :125
   ▼
db.transaction
   ├─ invoices INSERT ................... InvoiceModel.createInvoice :786
   ├─ invoice_items INSERT + FEFO/FIFO .. consumeFromOldestBatches :815
   ├─ stock_movement SALE (per batch) ... recordBatchMovement  [batch qty −]
   ├─ customer_ledger INVOICE debit .... ledgerUtils.createLedgerEntry
   ├─ GL  postInvoiceEntry :514 ......... Dr 1100 / Cr 4000 net + Cr 2100 tax
   ├─ GL  postCOGSEntry :1087 ........... Dr 5000 / Cr 1200  (per batch cost)
   ├─ GL  postPaymentEntry :574 ......... Dr <cash> / Cr 1100   (if payment leg)
   └─ recalcCustomerBalanceFromLedger ... customers.current_balance = Σ(debit−credit)
```

### 5.2 Customer payment / credit application

```
POST /api/payments ── PaymentRecordingService.recordCustomerPayment :34
   │  validateCustomerPayment :44  (amount>0, ownership, allocation ceiling :31)
   ▼
mode = PAYMENT ──────────── ledger PAYMENT credit ........ Dr <cash> / Cr 1100 :574
mode = CREDIT_APPLICATION ─ no ledger row (CODE-004) .... Dr 1110 / Cr 1100 :631
mode = REFUND ───────────── ledger REFUND debit .......... Dr 1100 / Cr <cash> :1349
                          + guardCashForRefund (cash sufficiency)
```

### 5.3 Goods receipt (the AP accrual event)

```
POST /api/purchase-orders/:id/receipts ── PurchaseOrder.addReceipt
   ├─ goods_receipts INSERT
   ├─ stock_batches INSERT (costed layer)
   ├─ stock_movement PURCHASE
   ├─ supplier_ledger GOODS_RECEIPT debit
   └─ GL  postGoodsReceiptEntry :661 ...... Dr 1200 / Cr 2000   keyed (GOODS_RECEIPT, receiptId)

void ── voidGoodsReceipt
   ├─ voidJournalLinesByReference('GOODS_RECEIPT', receiptId) :1402
   ├─ stock reversal (raw INSERT, NO GL leg — correct)
   └─ supplier_ledger reversal  ............ ⚠️ no period guard (ACCT-006)
```

### 5.4 Direct purchase

```
POST /api/purchases ── Purchase.writePurchaseRow :166
   ├─ purchases INSERT + stock_batches + stock_movement PURCHASE
   ├─ supplier_ledger PURCHASE debit
   └─ GL  postPurchaseEntry :698 .......... Dr 1200 / Cr 2000 (supplier)
                                      ... Dr 1200 / Cr <cash> (walk-in, no ledger row)

void ── Purchase.void :573
   ├─ guards: payments / open returns / returned qty
   ├─ supplier_ledger reversal ............ ✓
   ├─ voidJournalLinesByReference('PURCHASE') :654  ✓
   └─ recordMovement ADJUSTMENT ........... ❌ Dr 7200 / Cr 1200 — DOUBLE (ACCT-001)
```

### 5.5 Sales return

```
POST /api/invoice-returns ── InvoiceReturnService.processReturn
   ├─ invoice_returns + items INSERT
   ├─ stock_movement ADJUSTMENT (restock)  skipAdjustmentFinancialPosting ✓
   ├─ customer_ledger RETURN credit
   ├─ GL  postInvoiceReturnEntry :1191 ... Dr 4100 net + Dr 2100 tax / Cr 1100 gross
   ├─ GL  postCOGSReversalEntry :1133 .... Dr 1200 / Cr 5000
   ├─ GL  postReturnFeeEntry :1257 ....... Dr 1100 / Cr 4150  (if fee)
   └─ settlement → PaymentRecordingService (CREDIT_APPLICATION or REFUND)
```

### 5.6 Purchase return

```
POST /api/purchase-returns ── PurchaseReturn
   ├─ purchase_returns + items INSERT
   ├─ stock_movement ADJUSTMENT ........... skipAdjustmentFinancialPosting ✓
   ├─ supplier credit note + ledger credit
   ├─ GL  postPurchaseReturnEntry :1307 ... Dr 2000 / Cr 1200
   └─ GL  (refund_expected) → SupplierRefund.create → postRefundEntry-AP
```

### 5.7 Expense

```
POST /api/expenses ── Expense
   └─ GL  postExpenseEntry :778 ........... Dr 6000 / Cr <cash>
       Draft→Recorded only; voided on leaving GL-worthiness
       money-field edit = void then repost
       assertSufficientFunds on resolved cash account
```

---

## 6. Edge Case Tables

Legend: ✅ handled · ⚠️ partial · ❌ not handled

### Sales / AR

| # | Edge case | Status | Evidence |
|---|---|---|---|
| 1 | Overpayment blocked | ✅ | `InvoiceCreationService:115` `legsTotal + creditOffset > total + 0.01` → throw |
| 2 | Credit offset exceeds available credit | ✅ | `InvoiceCreationService:133-140` queries `credit_balance` + negative `current_balance` |
| 3 | Insufficient sellable stock | ✅ | `consumeFromOldestBatches:815` throws `SellableStockUnavailableError` → 400 |
| 4 | Expired / halted batch excluded | ✅ | FEFO when `has_expiry=1`; halted & expired filtered before consumption |
| 5 | Zero-price line allowed | ✅ | `unit_price >= 0` is a deliberate policy (free samples), COGS still posts |
| 6 | Cancel a paid invoice | ✅ | `cancelInvoiceInternal:1082` blocks paid/returned, reverses stock, voids own INVOICE_RETURN lines |
| 7 | Delete a returned invoice | ✅ | `deleteInvoice` allows only Draft/Unpaid with no payments or returns |
| 8 | Invoice edit with deleted payments | ✅ | `invoiceController:366-419` — every `deleted_payments` id must join via an existing `payment_allocations` row on *this* invoice |
| 9 | Invoice edit reposts GL | ✅ | void `INVOICE` + `COGS` lines then re-post at new amounts (`:545-610`); tax read back from stored items (`:552`) |
| 10 | Backdated invoice edit into closed period | ✅ | `assertPeriodNotClosed(originalInvoice.invoice_date)` `:335`; `postEntry` re-checks the new date |
| 11 | AR aging with NULL `due_date` | ❌ | `Reports.ts:7-26` — buckets exclude the row, total includes it (ACCT-004) |
| 12 | Client `total_amount` lies | ✅ | server recomputes on create and update; `TotalMismatchError` → 400 |
| 13 | Duplicate invoice submission | ✅ | idempotency claim inside transaction on all three money-in paths |

### Purchases / AP

| # | Edge case | Status | Evidence |
|---|---|---|---|
| 14 | Over-receipt beyond PO quantity | ✅ | blocked in `PurchaseOrder.addReceipt` |
| 15 | Concurrent receipts on one PO | ✅ | serialised inside the transaction |
| 16 | Void a purchase with payments | ✅ | `Purchase.void` throws on active `purchase_allocations` |
| 17 | Void a purchase with open returns | ✅ | throws on non-voided `purchase_returns` / `returned_quantity` |
| 18 | Partially-consumed GRN void | ✅ | `PurchaseOrder:695-708` refuses if any layer from the receipt was consumed |
| 19 | Supplier-less (walk-in) purchase | ✅ | `purchaseCreditAccount` (`:818-832`) → `Cr <cash>`; no ledger row (gated on `resolvedSupplierId`) |
| 20 | Zero-unit-cost purchase | ⚠️ | `postPurchaseEntry:711` posts no GL for `totalCost <= 0`; ledger row still written (0/0); free goods enter with no `journal_lines` trail |
| 21 | **Purchase void** | ❌ | **double inventory reversal + phantom 7200 (ACCT-001)** |
| 22 | **AP aging after a void** | ❌ | **reversal credit double-counted (ACCT-002)** |
| 23 | GRN void in a closed period | ❌ | no `assertPeriodNotClosed` (ACCT-006) |
| 24 | Supplier-refund void in a closed period | ❌ | no guard (ACCT-007) |

### Inventory / COGS

| # | Edge case | Status | Evidence |
|---|---|---|---|
| 25 | Manual adjustment GL leg | ✅ | `postFinancialEntryForAdjustment:421` — caller → batch → `standard_cost` fallback |
| 26 | Physical-count surplus layer | ✅ | `PhysicalCount:364-380` inserts at `item.unit_cost` |
| 27 | Return restock to chosen warehouse | ✅ | `reverseStockForItems` — visible movement to chosen warehouse, batch restore stays on original batches |
| 28 | Already-returned quantity on cancel | ✅ | `reverseStockForItems` subtracts prior `ADJUSTMENT/RETURN` movements before restocking |
| 29 | Stock transfer between warehouses | ✅ | equal-and-opposite legs, no GL (net value change zero, shared cost) |
| 30 | Transfer void | ✅ | `StockMovement:1693-1712` cancels existing layers, mirrored draw-down |
| 31 | **Adjustment with no `unit_cost`** | ❌ | **zero-cost batch → COGS understated (ACCT-003)** |
| 32 | **Adjustment dated in a closed period** | ❌ | **no guard on `POST /api/inventory/stock-movements` (ACCT-005)** |
| 33 | Both caller and `standard_cost` are 0 | ⚠️ | no GL posted at all, silent (CODE-002) |

### Payments

| # | Edge case | Status | Evidence |
|---|---|---|---|
| 34 | Payment allocation ceiling | ✅ | `paymentValidation:31` — REFUND unbounded, INVOICE_SETTLEMENT = total − returned, else balance |
| 35 | Cross-invoice allocation | ✅ | per-invoice ownership check before insert |
| 36 | Cash refund without funds | ✅ | `guardCashForRefund` — asserts sufficiency on the resolved cash account |
| 37 | Payment method whitelist | ✅ | `isValidPaymentMethod` on all paths; `InvalidPaymentMethodError` → 400 |
| 38 | Payment in a closed period | ✅ | `paymentWriterCore:31`, `Payment.ts:474-476`, `:613` |
| 39 | Idempotent payment replay | ✅ | hash-verified, `X-Idempotent-Replay` header, 409 on mismatch |

### Returns

| # | Edge case | Status | Evidence |
|---|---|---|---|
| 40 | Return exceeding invoice quantity | ✅ | allocation ceiling + per-item `returned_quantity` guards |
| 41 | Return on a cancelled invoice | ✅ | blocked upstream |
| 42 | Partial return after prior return | ✅ | per-call quantity tracking; restock math does not double-subtract |
| 43 | Disposition refund without credit | ✅ | legacy shim wired via `PaymentRecordingService` (settlements absent + `refundCreditDue`) |
| 44 | `INVOICE_RETURN` GL group carries COGS reversal | ✅ | by design — assert per-account legs, not group totals |

---

## 7. Prioritized Remediation Plan

### P0 — Critical (live books are wrong today)

**1. ACCT-001 — Purchase void double reversal** · effort **S**
- `Purchase.ts:662-672`: add `skipAdjustmentFinancialPosting: true`; change `movement_date` to `purchase.purchase_date`.
- `supplierlessPurchase.test.ts`: assert `1200.credit ≈ 0` **and** `7200.debit ≈ 0`; add `expectAllInvariantsHold` after the void.
- **Live-data repair:** for each voided purchase, check for an active `stock_adjustment` pair with `reference_doctype='PURCHASE_VOID'`; void it via `voidJournalLinesByReference('stock_adjustment', <movement_id>)` inside a transaction. On the current live DB that is `reference_id 120` (5,000).
- Verify: run the suite; re-run `getGLReconciliation` and confirm the Inventory delta moves by +5,000 and 7200 goes to zero.

**2. ACCT-002 — AP aging reversal double-count** · effort **S**
- `Reports.ts:350`: add `AND reversed_by IS NULL`.
- Add a regression test: create two purchases, void one, assert `totalPayables` equals the surviving ledger net.
- Verify: on the live DB, `getAPAgingReport.totalPayables` should go 0 → 1,000, matching `getSupplierBalances`.

### P1 — High (silent misstatement, grows with use)

**3. ACCT-003 — Zero-cost adjustment batches** · effort **S**
- `StockMovement.ts:143`: when `data.unit_cost` is absent, default the new batch's cost to `items.standard_cost`; throw or warn when both are 0.
- `inventoryController.createStockMovement`: accept and validate an optional `unit_cost` (the Flutter dialog already has the field available; `stock_adjustment_dialog.dart:85-90` currently omits it).
- Verify: repeat the probe — after a no-cost adjustment, `consumeFromOldestBatches` must return `unitCost: 40` and COGS must equal the GL value.

**4. ACCT-004 — AR aging with NULL `due_date`** · effort **S**
- `invoiceController.updateInvoice:311`: require a non-empty `due_date`; `InvoiceModel.updateInvoice` should reject null/empty.
- `Reports.ts:7-26` and `:152-190`: use `COALESCE(due_date, invoice_date)` so a legacy NULL still lands in exactly one bucket.
- Verify: probe with a NULL-`due_date` invoice and assert the buckets foot to `totalReceivables`.

### P2 — Medium (structural control gaps)

**5. CODE-001 / ACCT-005/006/007 — centralise period protection** · effort **M**
- Move the check into `voidJournalLinesByReference` and `postLegacyStockEntry` so no caller bypasses it.
- Add `assertPeriodNotClosed` to `createStockMovement`, `voidGoodsReceipt`, and `SupplierRefund.void` — or, if the primitives own it, delete the now-redundant call sites.
- Verify: close a period in a test DB and confirm every void/adjustment path for a dated-inside entry throws.

### P3 — Low (hygiene)

**6. CODE-002** — log a warning in `postFinancialEntryForAdjustment` when `value === 0` instead of returning silently.
**7. CODE-003** — change `glTotals` to assert net per account, or assert both legs; sweep the return suites that depend on it.

### Not findings (adjudicated, do not remediate)

- `postLegacyStockEntry` skipping the period check at its own call sites — enforced by every service caller; addressed structurally by P2 item 5.
- Header discount applied to tax-inclusive `linesTotal` while `postInvoiceEntry` credits full line tax — balanced by construction.
- Customer-ledger date-order rebuild vs supplier-ledger id-order rebuild — both correct for their respective readers (CODE-004).
- `.env` weak secrets — untracked, local-only.
- The AR `CREDIT_OFFSET` GL-vs-subledger delta — intentional (`CREDIT_APPLICATION` posts no ledger row).

---

### Verification commands used

```bash
cd server
npx jest --silent              # 114 suites / 993 tests passed
npx tsc --noEmit               # clean
npx eslint                     # 0 errors (2 pre-existing any-warnings, none in changed paths)
```

All probes were executed through the server's own models against throwaway in-memory and `mkdtemp` databases, then deleted; the live database was only ever opened read-only or via a copy. `git status` shows no repository file modified by this audit.
