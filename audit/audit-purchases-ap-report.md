# Forensic Audit — Purchases & Accounts Payable
**Scope:** PO → GRN → supplier invoice, direct purchase, purchase void, GRN void, AP derivation.
**Date:** 2026-10-06 · **Tree:** working tree @ `main` · **Method:** read-only static trace + measurement on throwaway `mkdtemp` databases driven through the server's own models. No repository file was modified (`git status` shows only one pre-existing throwaway probe belonging to another agent, `server/src/__tests__/zzProbeZeroCostBatch.test.ts`, not mine and not in this scope). All artifacts live in `/tmp/opencode/paudit/`. The live database was never opened for writing — only a `/tmp` copy was read.

---

## Chart of accounts (live, `is_active = 1`)

| Code | Name | Type | Normal balance |
|---|---|---|---|
| 1000 | Cash | asset | debit |
| 1010 | Bank | asset | debit |
| 1020 | Easypaisa / Mobile Wallet | asset | debit |
| 1030 | JazzCash | asset | debit |
| 1040 | UPaisa | asset | debit |
| 1100 | Accounts Receivable | asset | debit |
| 1110 | Customer Credit | asset | credit |
| **1200** | **Inventory Asset** | asset | debit |
| 1300 | Employee Loan Receivable | asset | debit |
| **2000** | **Accounts Payable** | liability | credit |
| 2100 | Tax Payable | liability | credit |
| 3000 / 3100 / 3200 / 3300 | Owner's Equity / Retained Earnings / Owner Capital / Owner Drawings | equity | — |
| 4000 / 4100 / 4150 | Sales Revenue / Sales Returns / Restocking Fee Income | revenue | — |
| 5000 / 6000 / 6100 / 6300 | COGS / Operating Expenses / Wages / Loan Write-off | expense | debit |
| 7000 | Production Clearing | expense | debit |
| 7100 | Inventory Correction | expense | debit |
| **7200** | **Inventory Shrinkage** | expense | debit |
| 7201–7204 | Expired / Damaged / Shortage / Obsolete Goods Loss | expense | debit |

Seeded at `server/src/migrations/add-gl-foundation.sql:36-52`, extended by `add-cash-accounts.sql`. **There is no goods-received-not-invoiced account.** See §GRNI.

---

# 1. FLOW TRACE

## 1.1 Event chain

```
Flutter UI                         HTTP                       Controller                        Model                              GL / subledger
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

purchase_order_form_dialog.dart
  → POST /api/purchase-orders      purchaseOrders.ts:11       createPurchaseOrder              PurchaseOrder.create              NONE
                                    → :23 status               updatePurchaseOrder              PurchaseOrder.updateStatus        NONE   (ACC-16)

receive_goods_dialog.dart:145-156
  → POST /api/purchase-orders/
      :id/receipts                 purchaseOrders.ts:31       createGoodsReceipt               PurchaseOrder.addReceipt          GOODS_RECEIPT
                                                                                                :1026-1035                       Dr 1200 / Cr 2000
                                                                                                :1042-1057                       supplier_ledger GOODS_RECEIPT debit

purchase_form_dialog.dart:216-240
  → POST /api/purchases            purchases.ts:11            recordPurchase                   Purchase.writePurchaseRow        PURCHASE
                                                                                                :299-306                         Dr 1200 / Cr 2000 (or Cr 1000)
                                                                                                :280-291                         supplier_ledger PURCHASE debit

void_purchase_dialog.dart
  → POST /api/purchases/:id/void   purchases.ts:15            voidPurchase :252-281           Purchase.void :573-703            VOIDS PURCHASE + POSTS
                                     (assertPeriodNotClosed                                 :654-657  voidJournal…          Dr 7200 / Cr 1200   ← PUR-001
                                      :268)                      @ :661-675  recordMovement

  → POST …/receipts/:receiptId/
      void                          purchaseOrders.ts:33       voidGoodsReceipt :315-345      voidGoodsReceipt :656-815         VOIDS GOODS_RECEIPT only
                                    (NO period check)                                      :723-740 raw INSERT            supplier_ledger GOODS_RECEIPT
                                                                                          :771-774  voidJournal…         → voided = 1
                                                                                          :780-791                        supplier_ledger → voided = 1
```

## 1.2 Event 1 — Create PO (Draft)

`POST /api/purchase-orders` · `purchaseOrders.ts:11` → `purchaseOrderController.ts:16-67` → `PurchaseOrder.ts:125-198`

- Validation: `supplier_id`, `po_date` present (`:26-32`); each item `item_id`, `quantity`, `unit_price` present (`:40-44`), `quantity > 0` (`:46-49`), `unit_price > 0` (`:51-54`). Zod `poCreate` (`middleware/validation.ts:149-154`) types only the header — `items: z.array(z.any()).min(1)`.
- Document number: `generateDocNo(db, 'PO')` (`PurchaseOrder.ts:200-202`) → e.g. `PO-1026-0001`. DB `UNIQUE` enforced (`migrations/init.sql:121`, implicit `sqlite_autoindex_purchase_orders_1`).
- Money: header `total_amount = Σ round(qty × price)` via `addCurrency`/`multiplyCurrency` (`PurchaseOrder.ts:138-141`); line `amount = multiplyCurrency(...)` (`:173`). **Correct 2-dp rounding.**
- **GL: none.** **supplier_ledger: none.** Documented at `PurchaseOrder.ts:177-180`.
- **No idempotency key** — `createPurchaseOrder` never reads the header (`purchaseOrderController.ts:16-67`).

## 1.3 Event 2 — Submit PO (Draft → Submitted)

`POST /api/purchase-orders/:id/status` · `purchaseOrders.ts:23` → `PurchaseOrder.updateStatus` (`PurchaseOrder.ts:550-605`)

- Transition table `:557-563`: Draft→{Submitted, Cancelled}; Submitted→{Partially Received, Cancelled}; Partially Received→{Completed, Cancelled}; Completed, Cancelled terminal.
- **GL: none. supplier_ledger: none.** Explicit at `:576-588` (`void status;`) — the ACC-16 removal.
- **No period check. No idempotency key.**

## 1.4 Event 3 — Goods receipt (GRN) — *the accrual event*

`POST /api/purchase-orders/:id/receipts` · `purchaseOrders.ts:31` → `purchaseOrderController.ts:347-426` → `PurchaseOrder.addReceipt` (`PurchaseOrder.ts:857-1104`)

Validation, in order:
| Layer | Check | file:line |
|---|---|---|
| Zod | `receipt_date`, `warehouse_id` present; `items` array min 1 — **no item typing** | `validation.ts:159-164` |
| Controller | `po_item_id` + `received_quantity` truthy; `received_quantity > 0` | `purchaseOrderController.ts:373-385` |
| Controller | idempotency (`PURCHASE_ORDER_RECEIPT`) — **never exercised by this client** | `purchaseOrderController.ts:391-401` |
| Model | PO exists; not `Draft` / `Cancelled` | `PurchaseOrder.ts:864-872` |
| Model | `po_item_id` exists; `received_quantity ≤ pending` | `PurchaseOrder.ts:876-889` |
| Model | *(missing)* lower bound on `received_quantity` | → PUR-012 |
| Model | *(missing)* `poItem.po_id === po_id` | → PUR-007 |

Writes, all inside one `db.transaction` (`:874`):
1. `goods_receipts` header, `receipt_no = GR-1026-0001` — `:891-910`
2. `goods_receipt_items` — `:913-926`
3. `purchase_order_items.received_quantity += ` — `:929-935`
4. **`stock_batches`** `source_type='GOODS_RECEIPT'`, `source_id = goods_receipt_items.id`, `unit_cost = poItem.unit_price` (the **PO price**, no landed cost) — `:943-961`
5. `stock_movements` `movement_type='PURCHASE'`, `reference_doctype='GOODS_RECEIPT'`, `unit_cost = poItem.unit_price`, `batch_id` set — `:964-985`
6. `stock_movements.financial_posted = 1`, `financial_value = roundCurrency(qty × price)` — `:987-994`
7. `stock_balances += qty` at the **receipt's** warehouse (not the PO's) — `:996-1013` → PUR-013
8. **GL** `postGoodsReceiptEntry` — `:1026-1035`
9. **`supplier_ledger`** `GOODS_RECEIPT` debit + `rebuildBalances` — `:1042-1057`
10. `items.current_stock` refresh — `:1060-1067`
11. PO status via `calculateStatus` — `:1069-1077`, `:1110-1127`

**Exact journal lines** (`accountingService.ts:565-601`, sole caller `PurchaseOrder.ts:1028`):

```
Dr 1200  Inventory Asset     postedAmount      line_date = receipt_date
Cr 2000  Accounts Payable    postedAmount      line_date = receipt_date
   reference_type = 'GOODS_RECEIPT'   reference_id = goods_receipts.id
   description = "Goods receipt GR-… (PO …) — <amount>"

postedAmount = roundCurrency( Σ_i roundQty(received_quantity_i × po_unit_price_i) )   PurchaseOrder.ts:1026
```

Measured (PO 10 @ 100, GRN 6 @ 100, `receipt_date` 2026-01-10):
```
GOODS_RECEIPT GL = [{"code":"1200","debit":600,"credit":0,"line_date":"2026-01-10"},
                    {"code":"2000","debit":0,"credit":600,"line_date":"2026-01-10"}]
supplier_ledger  = [{"transaction_type":"GOODS_RECEIPT","reference_no":"GR-1026-0001","debit":600,"balance":600}]
stock_batches    = [{"source_type":"GOODS_RECEIPT","unit_cost":100,"quantity_original":6}]
```

**Direction is correct:** inventory (asset) debited, payable (liability) credited. `getAccountBalance` (`accountingService.ts:122-164`) signs by `normal_balance`, so GL 2000 net reads **−600** for a 600 payable.

## 1.5 Event 4 — Direct purchase ("Record Purchase")

`POST /api/purchases` · `purchases.ts:11` → `purchaseController.ts:20-124` → `Purchase.writePurchaseRow` (`Purchase.ts:166-327`)

- Validation: `purchaseController.ts:61-68` (multi-item: qty > 0, cost ≥ 0), `:97-105` (single); `Purchase.validateCreateDTO` `:131-137`.
- **Idempotency: present and exercised.** Scope `PURCHASE_RECORD` (`purchaseController.ts:34`, `:74`, `:110`); client sends a payload-derived key (`purchase_form_dialog.dart:216-240`).
- `total_cost = roundQty(quantity × unit_cost)` — `Purchase.ts:185` → **3-dp**, see PUR-009.
- `stock_batches` `source_type='PURCHASE'`, `source_id = purchases.id`, `unit_cost = unit_cost` — `:208-224`.
- `stock_movements` `'PURCHASE'`, then `financial_posted = 1` — `:229-248`, `:310-313`.
- `stock_balances +=` (`:256-273`), `items.current_stock` refresh (`:275`).
- `supplier_ledger` `PURCHASE` debit = `totalCost` + `rebuildBalances` — `:280-291`.
- **GL** `postPurchaseEntry` — `:299-306` → `accountingService.ts:700-732`. Credit account chosen by `purchaseCreditAccount` (`:818-832`): `supplier_id` present → `'credit'` → **2000**; absent → `'cash'` → **1000**.

```
Supplier-linked:                          Supplier-less (walk-in):
Dr 1200  Inventory Asset     <T>          Dr 1200  Inventory Asset     <T>
Cr 2000  Accounts Payable    <T>          Cr 1000  Cash                <T>
```
Measured (supplier-less, 3 @ 10): `1200 {dr:30,cr:0}`, `1000 {dr:0,cr:30}` — matches `__tests__/supplierlessPurchase.test.ts:140`.

## 1.6 Event 5 — Purchase void

`POST /api/purchases/:id/void` · `purchases.ts:15` → `purchaseController.ts:252-281` → `Purchase.void` (`Purchase.ts:573-703`)

- Reason required (`purchaseController.ts:257`; `Purchase.ts:574-576`).
- **`assertPeriodNotClosed(db, purchase.purchase_date, …)`** — `purchaseController.ts:268`. Correct.
- Guards: not already voided (`:586`); no payment allocations (`:593-600`); no open purchase returns (`:602-612`); `returned_quantity == 0` (`:614-620`); batch not consumed (`:629-639`).
- `supplier_ledger`: `ledgerUtils.reverseLedgerEntry` → equal-and-opposite `REVERSAL:PURCHASE` row + original `voided = 1` + `rebuildBalances` (`:643-651`).
- **GL:** `voidJournalLinesByReference('PURCHASE', id)` → both lines `voided = 1` (`:654-657`).
- **Stock:** `StockMovementModel.recordMovement({movement_type:'ADJUSTMENT', quantity: −batch.quantity_remaining, unit_cost: batch.unit_cost, movement_date: TODAY})` (`:661-675`), then `quantity_remaining = 0` (`:678`).

That `recordMovement` call is the defect. `recordMovement` routes every `ADJUSTMENT` to `postFinancialEntryForAdjustment` (`StockMovement.ts:213-223`) because `skipAdjustmentFinancialPosting` is **not** set, and that function posts (`StockMovement.ts:455-470`):

```
Dr 7200  Inventory Shrinkage    |qty| × unit_cost
Cr 1200  Inventory Asset        |qty| × unit_cost
```

Measured, supplier-linked purchase 10 @ 50 = 500:
```
after create:  1200 {dr:500, cr:0}    2000 {dr:0, cr:500}    7200 {dr:0,cr:0}
after void  :  1200 {dr:0, cr:500}    2000 {dr:0, cr:0}      7200 {dr:500,cr:0}
net 1200 = -500   (correct answer: 0)          7200 = +500   (correct answer: 0)
adjustment movement: movement_date 2026-10-06 (today), purchase_date was 2026-01-15
```

**The live database already carries this.** `purchases.id = 38` / `PURCH-2026-0038` / `total_cost 5000` / `voided_at 2026-08-24 14:46:55`:
```
PURCHASE          ref 38  voided=1   Dr 1200 5000 / Cr 2000 5000
stock_adjustment  ref 155 voided=0   Dr 7200  500 / Cr 1200  500   ← spurious
```
Neither `known-issues.md` nor `gl-authority-map.md` mentions `7200`, `PURCHASE_VOID`, or the purchase void (grep count **0** in both). → **PUR-001, NEW.**

## 1.7 Event 6 — GRN void — the *correct* counterpart

`POST /api/purchase-orders/:id/receipts/:receiptId/void` · `purchaseOrders.ts:33` → `purchaseOrderController.ts:315-345` → `PurchaseOrder.voidGoodsReceipt` (`PurchaseOrder.ts:656-815`)

- **No `assertPeriodNotClosed`** → PUR-003.
- Guards: exists; not already voided (`:672-674`); has items (`:687-689`); **no batch layer from this receipt consumed** (`:695-708`).
- `stock_batches.quantity_remaining = 0`, retained for audit (`:710-713`).
- `stock_balances −= qty` at the receipt warehouse (`:715-720`).
- Stock movement by **raw INSERT** with `movement_type='PURCHASE_RETURN'`, `reference_doctype='GOODS_RECEIPT_VOID'` (`:722-740`) — **bypasses `postFinancialEntryForAdjustment`, so no second GL leg.** This is the pattern PUR-001 should copy.
- `purchase_order_items.received_quantity −= qty` (`:742-747`); PO status recomputed (`:753-759`).
- `voidJournalLinesByReference('GOODS_RECEIPT', receiptId)` (`:766-774`).
- `supplier_ledger` `GOODS_RECEIPT` row → `voided = 1` + `rebuildBalances` (`:780-791`). **Pure void, no reversal row** — inconsistent with `Purchase.void`'s `reverseLedgerEntry`, but both land on the same net.
- Stamp `voided_at/_by/_reason` (`:793-798`); second attempt rejected.

Measured (PO 10 @ 100, GRN 5, then void):
```
before: 1200 500 → 200   AP 200 → 200   current_balance 500 → 500
after : 1200 500 → 0     AP 200 → 0     current_balance 500 → 0
        stock_balances → 0   PO status → 'Submitted'   received_quantity → 0
second void → "Goods receipt GR-… is already voided"
```
**The GRN void path is complete and correct. The purchase void path is not.** That asymmetry is the whole of PUR-001.

---

# 2. GRNI ACCRUAL ANALYSIS — the highest-risk question

## 2.1 Does receiving goods create the inventory/AP accrual, or does the supplier invoice?

**Receiving goods creates it. There is no supplier-invoice posting path.**

- `grep -rn postGoodsReceiptEntry server/src` → exactly two hits: the definition (`accountingService.ts:565`) and the single call site `PurchaseOrder.ts:1028`, inside `addReceipt`. No invoice handler reaches it.
- **There is no supplier-invoice entity in this codebase.** `grep -rn "supplier_invoice|supplierInvoice|vendor_invoice" server/src` → **0 hits**. There is no `supplier_invoices` table, no route, no controller, no model, no `reference_type = 'SUPPLIER_INVOICE'` journal group.
- `purchases.invoice_no VARCHAR(100)` (`migrations/add-purchases-table.sql:14`, `init.sql`) is a free-text field holding the *supplier's paper* invoice number. It carries no index, no uniqueness, no validation and no foreign key. Measured on the live database: no index on `invoice_no` and no duplicate values — it has never been used as a key.

**Therefore the PO → GRN → supplier-invoice flow the brief describes terminates at the GRN.** The flow is:

```
PO (no entry)  →  GRN (Dr 1200 / Cr 2000)  →  supplier payment (Dr 2000 / Cr cash)
```

## 2.2 What happens when a GRN arrives without an invoice?

**Nothing further happens, and that is by construction.** There is no later event that re-keys, re-prices or clears the liability. The GRN creates a permanent AP balance that a supplier payment settles. An uninvoiced receipt is not a distinct state the system can represent, because the system has no concept of "invoiced".

## 2.3 Is there a goods-received-not-invoiced liability account? Does inventory get debited with no credit?

**No GRNI account exists. Inventory is *not* debited with no credit — the entry is balanced and self-funding, but it is mislabelled.**

- `grep -rn "GRNI|goods.received.not.invoiced|2050|Accrued|accrued" server/src lib/` → **0 hits**. The chart of accounts (`add-gl-foundation.sql:36-52` plus the live seed) contains no accrual-invoice code.
- The GRN credits **2000 Accounts Payable** directly (`PurchaseOrder.ts:1028-1035` → `accountingService.ts:596-597`).
- The GRNI concept is therefore *unmodelled in substance*, not just in naming: because PO submission posts nothing (§1.3), 2000 never contains a commitment, and it never needs to be reclassified out of one.

### What that costs

| Consequence | Evidence |
|---|---|
| **2000 conflates three economically distinct populations** — received-and-invoiced, received-not-invoiced, and legacy rows — with no dimension to separate them. | No `reference_type` other than `GOODS_RECEIPT`/`PURCHASE` writes 2000 on the purchase side (`accountingService.ts:596-597`, `:727-729`); no clearing mechanism exists. |
| **Uninvoiced receipts cannot be aged or chased.** AP aging (`Reports.ts:333-392`) buckets by `supplier_ledger` debit date only. A receipt sitting uninvoiced for 6 months is indistinguishable from an unpaid invoice 6 months overdue. | Measured: `agingBuckets` has no invoice dimension. |
| **No three-way match exists at all.** Matching requires three legs (PO, receipt, invoice). Only two exist. | PUR-008. |
| **A supplier invoice recorded as a direct purchase double-recognises.** If the same delivery was also received via a GRN, recording the invoice as a `purchases` row posts a second, independent `Dr 1200 / Cr 2000` against the same goods. | `Purchase.writePurchaseRow` has no link to any PO or GRN (`:166-327`); `purchases` has no `po_id`/`receipt_id` column. |
| **There is no GRNI clearing journal to write,** because there is no accrual-invoice event. A correct GRNI design would credit a 2xxx accrual account at receipt and reclassify to 2000 on invoice; the reclassifying entry has nowhere to live. | Confirmed absent. |

### Recommendation (not applied — audit only)

Introduce a `2xxx Goods Received Not Invoiced` liability account; credit it (not 2000) at `PurchaseOrder.ts:1028`; add a `supplier_invoices` table + `SUPPLIER_INVOICE` reference type; post the reclassifying entry `Dr GRNI / Cr 2000` on invoice receipt; keep PO submission at zero, as it correctly is today. Only then does "accrued/uninvoiced receipts" become a reportable, ageing quantity.

---

# 3. JOURNAL ENTRIES PER EVENT

Signs below are as stored in `journal_lines`. `getAccountBalance` re-signs by `normal_balance`, so a 2000 credit reads as a **negative** net.

| # | Event | Debit | Credit | ref_type / ref_id | Date source | file:line |
|---|---|---|---|---|---|---|
| 1 | Create PO (Draft) | — | — | — | — | `PurchaseOrder.ts:177-180` |
| 2 | Submit PO | — | — | — | — | `PurchaseOrder.ts:576-588` |
| 3 | **Goods receipt** | `1200` Inventory Asset — `roundCurrency(Σ roundQty(qty × po_unit_price))` | `2000` Accounts Payable — same | `GOODS_RECEIPT` / `goods_receipts.id` | `receipt_date` | `PurchaseOrder.ts:1026-1035`; `accountingService.ts:583-600` |
| 3b | ↳ subledger | `supplier_ledger` GOODS_RECEIPT `debit` = same amount | — | — | `receipt_date` | `PurchaseOrder.ts:1042-1057` |
| 4 | **Direct purchase, supplier-linked** | `1200` — `total_cost` | `2000` — `total_cost` | `PURCHASE` / `purchases.id` | `purchase_date` | `Purchase.ts:299-306`; `accountingService.ts:721-731` |
| 5 | **Direct purchase, supplier-less** | `1200` — `total_cost` | `1000` Cash — `total_cost` | `PURCHASE` / `purchases.id` | `purchase_date` | `Purchase.ts:304`; `accountingService.ts:715`, `:818-832` |
| 5b | ↳ subledger | `supplier_ledger` PURCHASE `debit` = `total_cost` | — | — | `purchase_date` | `Purchase.ts:280-291` |
| 6 | **Purchase void** | `1200` ← *intended* | `1200` ← **actual, spurious** | — | — | see below |
| 6a | ↳ original group | — | — | `PURCHASE` / id → `voided = 1` | `purchase_date` | `Purchase.ts:654-657` |
| 6b | ↳ **spurious leg** | **`7200` Inventory Shrinkage** — `|qty| × unit_cost` | **`1200` Inventory Asset** — same | `stock_adjustment` / movement id | **`new Date()` — today** | `Purchase.ts:661-675` → `StockMovement.ts:213-223`, `:455-470` |
| 6c | ↳ subledger | — | `supplier_ledger` `REVERSAL:PURCHASE` `credit` = `total_cost` | `reversed_by` → original id | original `purchase_date` | `Purchase.ts:643-651`; `ledgerUtils.ts:104-137` |
| 7 | **GRN void** | — | — | `GOODS_RECEIPT` / id → `voided = 1` | `receipt_date` | `PurchaseOrder.ts:766-774` |
| 7b | ↳ stock | — | — | raw `stock_movements` INSERT, `PURCHASE_RETURN`, `−qty` | **today** | `PurchaseOrder.ts:722-740` (no GL leg — correct) |
| 7c | ↳ subledger | — | — | `supplier_ledger` GOODS_RECEIPT → `voided = 1` + rebuild | — | `PurchaseOrder.ts:780-791` |
| 8 | Supplier payment (settlement) | `2000` AP | `1000`/`1010`/`1020`/`1030`/`1040` per method | `PAYMENT` | `payment_date` | `accountingService.ts:761-771`, `:846-856` |

**Row 6 is the only entry in the purchase flow with the wrong debit/credit shape.** Rows 3–5 and 7–8 all satisfy the brief's requirement: *Debit Inventory/Expense, Credit AP/Cash.* No path in the purchase flow debits 2000 on receipt.

---

# 4. FINDINGS

Severity: **CRITICAL** (live books wrong / silent misstatement) · **HIGH** (material reporting or control failure) · **MEDIUM** (real defect, bounded or conditional) · **LOW** (hygiene / latent) · **INFO** (assessment).

---

### **PUR-001 · CRITICAL · NEW — Purchase void reverses inventory twice, books phantom shrinkage, and posts the reversal into the wrong period**
**`server/src/models/Purchase.ts:661-675`** (and `:654-657`); mechanism `server/src/models/StockMovement.ts:213-223` and `:455-470`

`Purchase.void` voids the original `Dr 1200 / Cr 2000` group, then requests a *second* inventory effect through `recordMovement` with `movement_type: 'ADJUSTMENT'`. `recordMovement` routes every ADJUSTMENT to `postFinancialEntryForAdjustment`, posting `Dr 7200 / Cr 1200`. `skipAdjustmentFinancialPosting` — the flag introduced for precisely this class (`known-issues.md` item 1) — is not set. The GRN void path does the equivalent with a raw INSERT and is correct (`PurchaseOrder.ts:722-740`); the asymmetry is the defect.

**Financial impact (measured)**
- Clean DB, supplier-linked 10 @ 50 = 500: after create `1200 = +500`; after void **`1200 = −500`**, `7200 = +500`. Correct: `0` and `0`. Inventory reversed 200% of its value, plus an expense for goods never lost.
- Supplier-less 3 @ 10 = 30: `1200 {dr:0, cr:30}`, `7200 {dr:30, cr:0}` — a credit balance on a debit-normal asset account.
- **Live database:** `purchases.id 38` (`PURCH-2026-0038`, `total_cost 5000`, `voided_at 2026-08-24 14:46:55`) has both original lines `voided = 1` **and** an active `stock_adjustment` pair `reference_id 155`: `Dr 7200 500 / Cr 1200 500`. The live books carry a 500 phantom expense and a 500 phantom inventory credit. Live `GL 1200` net = `+2433.60` (matching the `known-issues.md` item-1 baseline), of which this 500 is an **unattributed** contributor not described there.
- The reversal leg is dated `new Date()` (`Purchase.ts:671`), so a January purchase voided in October moves inventory and books shrinkage into October. Measured: purchase 2026-01-15, leg 2026-10-06.
- `inventoryImbalances()` reports `{expected: 0, actual: 30, diff: 30}` on this path — so invariant **H** already detects it; nothing calls it here.

**Guard gap — `known-issues.md` §4 recurring.** `server/src/__tests__/supplierlessPurchase.test.ts:260` asserts `glTotals(db,'1200').debit ≈ 0` after a void. `glTotals` (`:94-104`) sums debit and credit **separately**, so `debit = 0` is satisfied while `credit = 30`. Measured: all three shipped assertions pass (`1000.credit=0`, `2000.credit=0`, `1200.debit=0`) while the unasserted `1200.credit = 30` and `7200.debit = 30`.

**Fix**
1. Add `skipAdjustmentFinancialPosting: true` to the `recordMovement` payload (`Purchase.ts:662-672`).
2. Pass `movement_date: purchase.purchase_date` instead of `new Date()`.
3. Tighten the test to assert `glTotals(db,'1200').credit ≈ 0` **and** `glTotals(db,'7200').debit ≈ 0`, and add `expectAllInvariantsHold` after the void — one call would have caught it.

**Standard.** Reversing a document voids the original entry; it never posts a second one. Where a stock reversal is also required, write the movement without a financial leg — the `voidGoodsReceipt` pattern.

---

### **PUR-002 · HIGH · NEW — AP aging double-counts ledger reversal credits; reports AP as 0 or negative**
**`server/src/models/Reports.ts:355-358`** (credit side of `computeAPAging`)

`SELECT supplier_id, SUM(credit) FROM supplier_ledger WHERE voided = 0 AND credit > 0` omits `reversed_by IS NULL`. `ledgerUtils.reverseLedgerEntry` (`server/src/utils/ledgerUtils.ts:104-137`) inserts an equal-and-opposite `REVERSAL:*` row with `reversed_by = <original id>` and `voided = 0`, and marks the original `voided = 1`. **Every** other consumer excludes `reversed_by` — `rebuildBalances` (`SupplierLedger.ts:91`), `getBalance` (`:68`), `getGLReconciliation` (`Reports.ts:1302`, `:1306`), invariant D (`__tests__/helpers/accountingInvariants.ts:132`, `:136`), `getSupplierBalances` (`SupplierLedger.ts:136`). AP aging alone counts it, so a void is charged twice: the original debit is dropped **and** the reversal credit is applied against a different, still-live debit.

**Financial impact (measured)**
- Purchases 100 (2026-01-05) + 200 (2026-01-06); void the 100 one. True AP = **200** (GL 2000 credit 200, `suppliers.current_balance` 200, `getBalance()` 200). `getAPAgingReport` → **`totalPayables = 100`**.
- Purchases 100/200/300; void the 300 one. True AP = **300**. `getAPAgingReport` → **`totalPayables = 0`**. AP disappears entirely.
- **Live database, supplier 1:** `suppliers.current_balance = 1000`; aging gross debits 20150; aging credits counted 24150; aging reported AP = **−4000** — a negative payable. Under-report = **5000**.

**Guards blind to it.** Measured on the same state: `apImbalances() = []`, `supplierApImbalances() = []`, `getGLReconciliation` AP `delta: 0`.

**Fix.** Add `AND reversed_by IS NULL` to `Reports.ts:356-358`, matching `SupplierLedger.ts:91`.

**Standard.** A reversal row is the correction half of a voided pair; counting it while also excluding the original double-counts the correction. One ledger, one exclusion rule.

---

### **PUR-003 · HIGH · NEW — GRN void has no closed-period guard; the purchase void has one**
**`server/src/controllers/purchaseOrderController.ts:315-345`** vs **`server/src/controllers/purchaseController.ts:268`**

`voidPurchase` calls `AccountingService.assertPeriodNotClosed(db, purchase.purchase_date, …)`. `voidGoodsReceipt` has no equivalent, and `AccountingService.voidJournalLinesByReference` (`accountingService.ts:1402-1428`) is a bare `UPDATE journal_lines SET voided = 1` with no period logic. Period protection exists only where a caller remembers to add it — an open-by-default primitive.

**Financial impact (measured).** With period `2026-03` closed, a GRN dated 2026-03-05 voided **successfully**: `GL 1200 1600 → 1100`, `GL 2000 1600 → 1100`. A closed period's journal entry was un-posted and the stock/AP reversal applied inside it. `assertPeriodNotClosed` throws correctly for the same date (`"GRN is dated 2026-03-05 inside closed accounting period '2026-03'"`), proving the guard exists and simply is not called.

**Fix.** Call `AccountingService.assertPeriodNotClosed(db, receipt.receipt_date, …)` in `voidGoodsReceipt` before the model call, and move the check into `voidJournalLinesByReference` so no caller can bypass it.

**Standard.** A closed period is immutable; any mutation of a dated financial line — including an un-void — is blocked at the primitive, not at the call site.

---

### **PUR-004 · HIGH · NEW — `getGLReconciliation`'s AP side reads a running-balance column that no writer maintains after a void**
**`server/src/models/Reports.ts:1300-1310`**

The AP reconciliation takes each supplier's `MAX(id)` row among `voided = 0` rows and sums that row's stored `balance`. After any `reverseLedgerEntry` the highest-id non-voided row **is** the reversal row — and `SupplierLedger.rebuildBalances` (`SupplierLedger.ts:88-104`) updates only rows matching `voided = 0 AND reversed_by IS NULL`. Reversal rows therefore keep the one-off value `reverseLedgerEntry` computed against a pre-void read (`ledgerUtils.ts:113-119`) and are never refreshed.

**Financial impact (measured).** Purchases 100/200/300, void the 300 one: reconciliation row `{gl_balance: 300, operational_balance: 300, delta: 0}` — correct *only* because the two errors cancel. On a two-purchase variant the same read returned `operational_balance` off the true net. The column is undefined after a void, so correctness here is accidental.

**Fix.** Compute the AP side as `SUM(debit) - SUM(credit)` over `voided = 0 AND reversed_by IS NULL` grouped by supplier — the expression invariant D already uses (`__tests__/helpers/accountingInvariants.ts:132-136`) — instead of reading a stored running balance.

**Standard.** A reconciliation aggregates the ledger. It does not trust a denormalised running column whose maintenance rules differ from the ledger's own.

---

### **PUR-005 · MEDIUM · NEW — Future-dated documents are accepted and silently open future accounting periods**
**`server/src/models/PurchaseOrder.ts:1028-1035`** → **`server/src/services/accountingService.ts:313-347`**

No upper bound on `po_date`, `receipt_date` or `purchase_date` anywhere in the purchase path. `postEntry` reads "no open period covers the entry date" as an instruction to create one: it inserts the calendar-month period as `open` and logs a warning.

**Financial impact (measured).** A GRN dated `2030-01-01` was accepted and created `accounting_periods {period_name: '2030-01', status: 'open'}`. That period then accepts postings, so period-close discipline is bypassable by future-dating. Feed-forward into PUR-006.

**Fix.** Reject a document date later than today at the controller; require an explicit "open period" action rather than auto-creating one from a document date.

**Standard.** A document date *selects* a period; it never *creates* one.

---

### **PUR-006 · MEDIUM · NEW — AP aging ignores `asOfDate`**
**`server/src/models/Reports.ts:334-341`** (`debitRows`): `WHERE sl.voided = 0 AND sl.debit > 0` — no `transaction_date <= asOfDate`. The credit query at `:352-354` likewise.

**Financial impact (measured).** With a purchase dated `2031-01-01` of 500 on the books, `getAPAgingReport('2026-01-01')` returned `totalPayables = 600`, including the 2031 purchase — and bucketed it `current_amount`, because `Reports.ts:379-381` treats `ageDays <= 0` as current. Every historical AP aging figure is overstated by all future-dated purchases.

**Fix.** Add `AND sl.transaction_date <= ?` to both queries in `computeAPAging`, bound to `asOfDate`.

**Standard.** An as-of report filters on the as-of date on **both** sides of the net.

---

### **PUR-007 · MEDIUM · NEW — A goods receipt can be booked against a line item belonging to a different purchase order**
**`server/src/models/PurchaseOrder.ts:876-889`** and **`:921-926`**

The `po_item_id` lookup is `SELECT * FROM purchase_order_items WHERE id = ?`. **`poItem.po_id` is never compared to the route's `po_id`** — in either the validation loop or the write loop.

**Financial impact (measured).** PO-A (supplier SUP-A, line price 100) and PO-B (supplier SUP-B, line price 777), both Submitted. A receipt posted on **PO-A** with **PO-B's** `po_item_id`, qty 5, was accepted:
```
GOODS_RECEIPT GL = Dr 1200 3885 / Cr 2000 3885     ← 5 × 777 (PO-B's price)
supA ledger       = GOODS_RECEIPT debit 3885        ← PO-A's supplier
poA/poB received  = PO-B advanced by 5               ← PO that does not own the goods
```
Inventory valued at another PO's price, payable raised against the wrong supplier, receipt progress booked to the wrong PO.

**Fix.** Assert `poItem.po_id === po_id` in both loops; also validate in the controller.

**Standard.** A child document validates that every referenced parent key belongs to the document being written.

---

### **PUR-008 · MEDIUM · NEW — No price-variance or landed-cost mechanism exists: a receipt can only ever be valued at the PO price**
**`server/src/models/PurchaseOrder.ts:957`, `:977`, `:1016`**; client `lib/features/purchase_orders/receive_goods_dialog.dart:150-156`; schema `server/src/middleware/validation.ts:159-164`

Batch `unit_cost = poItem.unit_price` (`:957`); movement `unit_cost = poItem.unit_price` (`:977`); `totalAmount += roundQty(received_qty × poItem.unit_price)` (`:1016`). The receipt payload carries only `{po_item_id, received_quantity}` and the Zod schema is `items: z.array(z.any()).min(1)` — **no cost field exists anywhere in the flow**.

**Financial impact.** Price variance is not mis-posted, it is *unrepresentable*. The system has no way to record what the supplier actually billed. The variance can only be forced by editing the PO (Draft only — `PurchaseOrder.ts:364-366`, `:425-427`, `:475-477`) or by re-keying the delivery as a direct purchase, which posts a **second, independent** `Dr 1200 / Cr 2000` for the same goods. Inventory and AP are permanently at PO price; landed cost never reaches 1200; there is no variance account (receipts touch only 1200 and 2000).

**Fix.** Add an optional per-line `unit_cost`/`landed_cost` to the receipt; post the receipt at the received cost; route `(received_cost − po_price) × qty` to a purchase-price-variance P&L account; add a guard that forbids recording a supplier invoice as a direct purchase for goods already received via a GRN.

**Standard.** The three-way match exists to catch price variance. A receipt posted solely at PO price cannot detect any.

---

### **PUR-009 · MEDIUM · NEW — `purchases.total_cost` is rounded to quantity precision (3 dp), not money precision**
**`server/src/models/Purchase.ts:185`** — `const totalCost = roundQty(quantity * unit_cost)` (`roundQty` from `server/src/utils/quantity`). Compare `PurchaseOrder.ts:139` and `:173`, which use `addCurrency`/`multiplyCurrency`/`roundCurrency`.

**Financial impact (measured).** Purchase 3 @ 33.333:
```
purchases.total_cost  = 99.999
supplier_ledger.debit = 99.999
GL Cr 2000            = 100.00     ← postEntry normalises to 2 dp (accountingService.ts:273)
```
Subledger AP and GL AP differ by 0.001 per affected purchase, permanently. `purchases.balance_amount` (`Purchase.ts:393`, `:491`) is computed from the 3-dp `total_cost`, so the document's own "Amount Due" disagrees with the GL.

**Related, distinct:** the GRN path writes `poItem.unit_price` into `stock_batches.unit_cost` unrounded (`PurchaseOrder.ts:957`) while the GL posts the 2-dp line total (`:1026`). Measured: 7 @ 3.335 → batch value 23.345 vs GL `Dr 1200 23.35` — a 0.005 divergence per receipt accumulating against invariant H. Both sit under the `> 0.005` tolerance in `__tests__/helpers/accountingInvariants.ts:247`, so neither is caught.

**Fix.** `roundCurrency(quantity * unit_cost)` at `Purchase.ts:185`; round `unit_price` to 2 dp before it reaches `stock_batches` in `addReceipt`.

**Standard.** Money is rounded once, at the boundary, to the currency's minor unit. A quantity-precision rounding function must never be applied to money.

---

### **PUR-010 · MEDIUM · NEW — The GRN client's idempotency key is never sent; a duplicated partial receipt double-receives**
**`lib/data/repositories/purchase_order_repository.dart:171-180`**; **`lib/features/purchase_orders/receive_goods_dialog.dart:128-156`**

`createReceipt` takes no `idempotencyKey` parameter and the dialog sends none, so the server's `PURCHASE_ORDER_RECEIPT` guard (`server/src/controllers/purchaseOrderController.ts:391-401`) is **dead code from this client**. `receive_goods_dialog.dart:128-142` also has **no `if (_saving) return;` early guard** in `_save()` — it relies on the button being disabled (`onPressed: _saving ? null : _save`, `:307`) and on `onFieldSubmitted: submitOnEnter(_save)` (`:377`) not racing. Compare the direct-purchase client, which does send a payload-derived key (`lib/features/purchases/purchase_form_dialog.dart:216-240`).

**Financial impact (measured at the model level).** Four sequential 6-unit attempts against a 10-unit line: first accepted, next three rejected (`"Cannot receive more than pending quantity (4)"`). A *full* line is therefore protected by the pending check. But a **partial** receipt leaves pending > 0, so a duplicated request is accepted: 5 of 10 submitted twice yields two receipts, two cost layers, two `Dr 1200 / Cr 2000` pairs, and `received_quantity = 10`. Indistinguishable from a genuine second delivery — the audit trail cannot separate a double submit from a real one.

**Fix.** Add `idempotencyKey` to `createReceipt`, derived from the payload as `purchase_form_dialog.dart:216` does; add `if (_saving) return;` at the top of `_save`.

**Standard.** Any money-moving POST must be retry-safe from the client. The server already implements this for every other purchase write.

---

### **PUR-011 · MEDIUM · NEW — `SupplierLedger.getBalance` orders by date while `rebuildBalances` computes by id; a backdated purchase makes the supplier-balance API disagree with the GL**
**`server/src/models/SupplierLedger.ts:66-71`** (`ORDER BY transaction_date DESC, id DESC`) vs **`:89-93`** (`ORDER BY id ASC`)

The docstring at `:76-87` documents the divergence as deliberate for the *rebuild*; it leaves `getBalance` reading the other order. `getGLReconciliation` also uses a third rule — `MAX(id)` (`Reports.ts:1305`).

**Financial impact (measured).** Purchases dated 2026-05-01 (100) then backdated 2026-01-15 (50), same supplier:
```
rebuildBalances (id order)  → suppliers.current_balance = 150
SupplierLedger.getBalance() → 100
```
`GET /api/purchase-orders/suppliers/:id/balance` (`purchaseOrderController.ts:472-488`) therefore serves **100** while the GL, `suppliers.current_balance`, invariant G and `getGLReconciliation` all say **150**. Invariant D reads `current_balance`, not `getBalance`, so it is blind to this.

**Fix.** Make `getBalance` order by `id DESC` over the same filtered set `rebuildBalances` uses, or return `suppliers.current_balance` directly.

**Standard.** A running balance has one canonical ordering. Two readers of the same column must not sort it differently.

---

### **PUR-012 · LOW · NEW (partial) — No lower-bound quantity guard in the receipt model; a DB CHECK is the only backstop**
**`server/src/models/PurchaseOrder.ts:876-889`** checks only `received_quantity > pending`. Zero and negative pass.

**Evidence (measured).** `received_quantity: -6` was accepted by `addReceipt` and rejected only by a table CHECK (`CHECK constraint failed: quantity_remaining >= 0 AND quantity_remaining <= quantity_original`), surfacing as a **500** carrying the raw SQLite message rather than a 400. `received_quantity: 0` was accepted with **no error at all**, creating `goods_receipts`, `goods_receipt_items`, `stock_batches` and `stock_movements` rows — all zero-valued, and no GL entry (`postedAmount > 0` at `:1027` is false).

**HTTP surface is protected:** `purchaseOrderController.ts:373-385` rejects missing/zero/negative with 400; the Flutter validator rejects `qty <= 0` and `qty > pending` (`receive_goods_dialog.dart:379-386`). Exposure is limited to non-HTTP callers — backfills, scripts, a future import path.

**Fix.** Mirror the controller's bounds inside `addReceipt`; map constraint violations to 400.

**Standard.** Validate in the model that owns the invariant. The controller is a convenience, not the guard.

---

### **PUR-013 · LOW · NEW — Receipts accept a warehouse different from the PO's, silently**
**`server/src/models/PurchaseOrder.ts:951-953`, `:971-973`, `:996-1013`**

Batch, movement and stock balance all use the receipt's `warehouse_id`; nothing compares it to `po.warehouse_id`.

**Impact (measured).** PO header warehouse 8, receipt warehouse 9 — accepted, no error. Inventory value lands in an unintended warehouse; warehouse-scoped stock and valuation reports for the PO's own warehouse are understated, and nothing records the deviation.

**Fix.** Validate, or record the deviation explicitly on the receipt.

---

### **PUR-014 · LOW · NEW — `purchases.balance_amount` has no floor at zero; the PO equivalent does**
**`server/src/models/Purchase.ts:393`** and **`:491`** — `p.total_cost - COALESCE(pa.paid_amount, 0) as balance_amount`, no `MAX(0, …)`. Compare `PurchaseOrder.ts:231` and `:310`, which use `MAX(0, po.total_amount - …)`.

**Impact.** Over-allocating a payment to a purchase yields a negative "Amount Due". The inconsistency between the two list endpoints is the actionable part.

---

### **PUR-015 · LOW · NEW — `backfillGlPreposting` re-posts voided purchases, and posts goods receipts to the GL without the supplier-ledger leg**
**`server/src/migrations/backfillGlPreposting.ts:133-143`** — `WHERE total_cost > 0`, **no `voided_at IS NULL`** — versus **`:253-258`** for receipts, which *does* filter `gr.voided_at IS NULL`. One-time, guarded by `schema_migrations` (`config/database.ts:99-101`, `:1741`).

**Financial impact (measured).** Void a 100 purchase, then run the backfill: `hasActiveLines` (`:88-92`) filters `voided = 0`, the voided group no longer matches, so a fresh `Dr 1200 100 / Cr 2000 100` is posted. `GL 1200 dr 0→130`, `GL 2000 cr 0→130`, with no matching stock or `supplier_ledger` row. `apImbalances()` → `{expected: 0, actual: 130}`. The same asymmetry on the receipts path (`:262-274`) posts `Dr 1200 / Cr 2000` with **no** `supplier_ledger` write, leaving GL AP permanently above the subledger — measured `apImbalances()` → `{expected: 200, actual: 330}`.

**Blast radius today:** the live database has **zero** `GOODS_RECEIPT` journal groups, so the receipts half has never fired. The purchases half is one-shot and already applied on this database; residual exposure is a restored pre-backfill backup or a fresh database whose purchases predate the first boot of this build.

**Fix.** Add `AND voided_at IS NULL` to the purchases query; write the `supplier_ledger` leg alongside the GL leg in the receipts section.

---

### **PUR-016 · INFO · ALREADY-KNOWN in substance, residual NOT recorded — The duplicate-PO-commitment bug is genuinely fixed in the write path; the repair script is still outstanding on the live database**
**Root cause is fixed, not papered over.** `PurchaseOrderModel.updateStatus` (`PurchaseOrder.ts:569-588`) posts no GL and no `supplier_ledger` row — `void status;` at `:583` with the rationale at `:576-582`; `create` documents the removal at `:177-180`. Grep for a `PURCHASE_ORDER` ledger writer across `server/src` (excluding tests) returns only `purchaseReturnController.ts:86`, `middleware/validation.ts:218`, `models/PurchaseReturn.ts:41`/`:815`, `utils/purchaseReturnBackfill.ts:102`/`:147` — all purchase-**return** *source types*, none a ledger write.

**Residual, measured on the live database:** `supplier_ledger` still holds **2 active `PURCHASE_ORDER` debit rows totalling 4000** — exactly the rows `scripts/dedupe-po.js` targets, which is dry-run by default (`dedupe-po.js:20`; `--apply` to write). Those 4000 sit inside the 20150 aging gross debits behind PUR-002's live −4000 figure.

**`scripts/repair-orphaned-ledger.ts` does not help here.** It is **customer**-ledger only (`:32-45`: `customer_ledger`, `INVOICE|RETURN|PAYMENT|REFUND`) and offers no remedy for supplier-side orphans.

Neither `known-issues.md` nor `gl-authority-map.md` records this residual → the *documentation* gap is NEW.

---

## Out of scope, but adjudicated because the brief asked

| Question | Verdict | Evidence |
|---|---|---|
| **Multi-currency PO** | **Not handled — not modelled at all.** | `PRAGMA table_info` on `purchases`, `purchase_orders`, `purchase_order_items`, `goods_receipts`, `supplier_ledger` returns **zero** columns matching `curr\|rate\|exch\|fx`. A multi-currency PO is stored in the same single-currency columns with no rate captured anywhere, so the FX difference is unrecoverable at receipt or settlement. |
| **Single supplier invoice covering multiple POs** | **Not applicable — the entity does not exist.** | No `supplier_invoices` table/route/controller/model; `grep` for `supplier_invoice\|supplierInvoice\|vendor_invoice` → 0 hits. `purchases.invoice_no` (`add-purchases-table.sql:14`) is unindexed free text; the live database has no index on it and no duplicate values, confirming it has never served as a key. |
| **Negative price** | **Handled.** | `purchaseController.ts:65-68` and `:102-105`; `Purchase.validateCreateDTO` `:135`; PO `purchaseOrderController.ts:51-54`, `:193-196`. Rejected with 400. |
| **Duplicate PO number** | **Handled** (DB level). | `purchase_orders.po_no VARCHAR(50) UNIQUE NOT NULL` (`init.sql:121`), enforced by `sqlite_autoindex_purchase_orders_1`. Measured: direct duplicate insert → `UNIQUE constraint failed: purchase_orders.po_no`. `generateDocNo` (`PurchaseOrder.ts:200-202`) is the only producer, so no legitimate collision path exists. |
| **Edit after finalize** | **Handled.** | PO header, add line, update line and delete line all require `Draft` (`PurchaseOrder.ts:364-366`, `:425-427`, `:475-477`, `:524-526`, `:614-616`). Received quantities can no longer move because `received_quantity` is only touched by `addReceipt`/its void. |
| **Void after finalize** | **Handled, with the PUR-001 caveat.** | `Purchase.void` guards payments, returns, returned quantity and consumed batches (`Purchase.ts:593-639`); `voidGoodsReceipt` guards consumed layers (`PurchaseOrder.ts:695-708`). Both are idempotent (second attempt rejected — measured). The GL reversal itself is defective on the purchase side (PUR-001). |
| **Purchase void into a closed period** | **Handled.** | `purchaseController.ts:268` calls `assertPeriodNotClosed`. The GRN equivalent is not (PUR-003). |

---

# 5. EDGE CASE TABLE

| # | Edge case | Verdict | Evidence / failure mode |
|---|---|---|---|
| 1 | **Zero quantity** — direct purchase | **Handled** | `purchaseController.ts:97-100`, `:61-64`; `Purchase.validateCreateDTO:134`. 400. |
| 2 | **Zero quantity** — PO line | **Handled** | `purchaseOrderController.ts:46-49`; `!item.quantity` at `:41`; 400. |
| 3 | **Zero quantity** — receipt line (HTTP) | **Handled** | `purchaseOrderController.ts:373-378` (`!item.received_quantity` → 400); Flutter `:383-384` (`qty <= 0`). |
| 4 | **Zero quantity** — receipt line (model) | **Not handled** | `addReceipt` accepts it; creates 4 orphan zero rows, no GL. Measured. → **PUR-012** |
| 5 | **Negative quantity** — receipt (HTTP) | **Handled** | `purchaseOrderController.ts:380-385` → 400. |
| 6 | **Negative quantity** — receipt (model) | **Partial** | Accepted by the model; stopped only by a DB CHECK, surfacing as a 500 with a raw SQLite message. Measured. → **PUR-012** |
| 7 | **Negative price** | **Handled** | `purchaseController.ts:65-68`, `:102-105`; `Purchase.validateCreateDTO:135`; PO `:51-54`. |
| 8 | **Receipt exceeding PO** | **Handled** | `PurchaseOrder.ts:885-888` — `received_quantity > roundQty(quantity − received_quantity)` → throw. Measured: 11 against 10 → `"Cannot receive more than pending quantity (10)"`. Also `purchaseOrderController.ts:870-872` blocks Draft/Cancelled. |
| 9 | **Invoice exceeding receipt** | **Not applicable** | No supplier-invoice entity. A receipt cannot be exceeded because nothing can be invoiced against it beyond the AP already raised. The nearest real case is PUR-008 (no invoice-price capture). |
| 10 | **Duplicate PO number** | **Handled** | DB `UNIQUE` on `po_no` (`init.sql:121`). Measured. |
| 11 | **Double submit — direct purchase** | **Handled** | Server `PURCHASE_RECORD` idempotency (`purchaseController.ts:34`, `:74`, `:110`) **plus** a client-supplied payload-derived key (`purchase_form_dialog.dart:216-240`). |
| 12 | **Double submit — PO create** | **Not handled** | `createPurchaseOrder` never reads the `Idempotency-Key` header; the client sends none. Financial impact nil — PO creation posts no GL (`PurchaseOrder.ts:177-180`) — but duplicate POs are possible. |
| 13 | **Double submit — GRN, full line** | **Handled (incidentally)** | The pending check blocks the duplicate. Measured: 4 × 6 against a 10-line → 1 accepted, 3 rejected. |
| 14 | **Double submit — GRN, partial line** | **Not handled** | Pending > 0 after the first, so the duplicate is accepted: 5 of 10 twice → two receipts, two batches, two `Dr 1200 / Cr 2000` pairs, `received_quantity = 10`. Server idempotency exists but the client never triggers it. → **PUR-010** |
| 15 | **Backdated to a closed period** — GRN | **Handled** | `postEntry` (`accountingService.ts:318-347`) finds no open period, `ON CONFLICT DO NOTHING` cannot revive the closed one, then throws `"No open accounting period covers …"`. |
| 16 | **Backdated to a closed period** — direct purchase | **Handled** | Same primitive. |
| 17 | **Void into a closed period** — purchase | **Handled** | `purchaseController.ts:268`. |
| 18 | **Void into a closed period** — GRN | **Not handled** | No period check anywhere on the path; `voidJournalLinesByReference` does not check. Measured: voided successfully inside a closed period. → **PUR-003** |
| 19 | **Future-dated** | **Not handled** | No upper bound in any purchase path; a `2030-01-01` receipt was accepted and created an open `2030-01` period. Measured. → **PUR-005** |
| 20 | **Partial receipt across multiple GRNs** | **Handled** | Additive and correctly keyed. Measured: 4 then 6 against a 10-line → `received_quantity 10`, status `Completed`, two `GOODS_RECEIPT` groups (400 / 600), ledger 400 → 1000. |
| 21 | **Single invoice covering multiple POs** | **Not applicable** | No supplier-invoice entity; `invoice_no` is unindexed free text with no duplicates in the live data. |
| 22 | **Multi-currency PO** | **Not handled** | No currency/rate/FX column on any purchase table. Not modelled. |
| 23 | **Rounding** | **Partial** | PO uses `roundCurrency`/`multiplyCurrency` correctly (`PurchaseOrder.ts:139`, `:173`). **Purchase** uses `roundQty` for money (`Purchase.ts:185`) → subledger 99.999 vs GL 100.00, measured. GRN writes unrounded `unit_price` into `stock_batches` while the GL posts the 2-dp total → 23.345 vs 23.35, measured. Both under the 0.005 invariant tolerance. → **PUR-009** |
| 24 | **Receiving into the wrong warehouse** | **Not handled** | No comparison to `po.warehouse_id`. Measured: PO warehouse 8, receipt warehouse 9, accepted. → **PUR-013** |
| 25 | **Receipt line from another PO** | **Not handled** | `poItem.po_id` never compared to `po_id` (`PurchaseOrder.ts:876-889`, `:921-926`). Measured: GL 3885 at PO-B's price, AP on PO-A's supplier, PO-B advanced. → **PUR-007** |
| 26 | **Void after post — GRN** | **Handled** | Complete and correct: GL voided, batch zeroed, `stock_balances` restored, `received_quantity` rolled back, PO status recomputed, ledger voided + rebuilt, idempotent. Measured 500 → 0 on every surface. |
| 27 | **Void after post — direct purchase** | **Partial** | Guards and idempotency are sound (measured: second void → `"already voided"`), but the GL reversal double-reverses inventory and books phantom shrinkage, in the wrong period. Confirmed on live data (`purchase 38`, 500). → **PUR-001** |
| 28 | **Edit after finalize** | **Handled** | All PO mutations require `Draft` (`PurchaseOrder.ts:364-366`, `:425-427`, `:475-477`, `:524-526`, `:614-616`). Purchases are immutable except via `void`. |
| 29 | **Concurrent double-receipt of the same PO line** | **Handled** | better-sqlite3 is single-connection and the pending check runs inside the transaction, so the read-check-write serialises. Measured: 4 sequential attempts, 1 accepted, 3 rejected. |
| 30 | **Partially-consumed receipt void** | **Handled** | `PurchaseOrder.ts:695-708` refuses if any layer from the receipt was consumed, so costing cannot be corrupted. |
| 31 | **Void a purchase whose stock was sold** | **Handled** | `Purchase.ts:629-639` — `remaining < original − 0.01` → throw. |
| 32 | **Void a purchase with payments / returns** | **Handled** | `Purchase.ts:593-600` (allocations), `:602-612` (open returns), `:614-620` (`returned_quantity`). |
| 33 | **GRN with no invoice** | **Not handled (by design)** | This is the *only* state the system supports. AP 2000 is raised at receipt and cleared by payment. No GRNI account, no reclassifying entry, no uninvoiced-receipt reporting. → §2 |
| 34 | **Supplier-less (walk-in) purchase** | **Handled** | `purchaseController` → `Purchase.ts:304` `paymentMethod: 'cash'` → `purchaseCreditAccount` (`accountingService.ts:818-832`) → `Cr 1000`. Measured: `1200 {dr:30}`, `1000 {cr:30}`. No `supplier_ledger` row (`Purchase.ts:280` is gated on `resolvedSupplierId`). Asserted at `__tests__/supplierlessPurchase.test.ts:140` — though the void assertion at `:260` is PUR-001's blind spot. |
| 35 | **Zero-unit-cost purchase** | **Partial** | `postPurchaseEntry` returns `null` for `totalCost <= 0` (`accountingService.ts:711`), so **no GL entry at all** — while a `supplier_ledger` row *is* written (`Purchase.ts:280-291`, zero/zero) and a cost layer is created at `unit_cost 0`. Measured. No divergence (both sides zero), but free goods enter inventory with no GL value and no audit trail in `journal_lines`. |
| 36 | **Backdated purchase → supplier-balance API** | **Not handled** | `getBalance` sorts by date, `rebuildBalances` by id. Measured: API 100 vs `current_balance` 150 vs GL 150. → **PUR-011** |

---

# 6. SUMMARY

The **write path is sound where ACC-16 touched it.** PO submission genuinely posts nothing, `PURCHASE_ORDER` is gone as a ledger type, partial receipts are additive and correctly keyed, over-receipt is blocked, concurrent receipts serialise, the GRN void is complete and reversible, and the GRN accrual direction (Dr 1200 / Cr AP) is correct. The `dedupe-po.js` root cause is genuinely fixed, not papered over.

**Three things are wrong at the top of the risk register:**

1. **PUR-001 (CRITICAL)** — voiding a purchase reverses inventory twice, books a phantom `7200` shrinkage, and lands the reversal in the current period instead of the original one. Measured at −500 on a 500 purchase where the answer is 0; and **already present on the live database** (`purchase 38`, 500). The shipped guard for it exists and passes, because it asserts `1200.debit` while the defect writes `1200.credit` — the exact failure mode `known-issues.md` §4 warns about, recurring one item later.

2. **GRNI does not exist** — and cannot, because **there is no supplier-invoice entity at all**. `purchases.invoice_no` is unindexed free text. The receipt is the accrual event; AP 2000 is raised and then settled by payment; there is no invoice leg to match, no reclassifying entry, and no way to age uninvoiced receipts. The three-way match the brief asks about does not exist in this codebase, and price variance is not mis-posted but *unrepresentable* (PUR-008).

3. **PUR-002 (HIGH)** — AP aging double-counts ledger reversal credits. Measured: true AP 300 reported as **0**; true AP 200 reported as 100. On the live database, supplier 1's true AP of **1000** is reported as **−4000**. Both invariants and the GL reconciliation are green throughout — three independent checks, all blind.

**Immediate triage order:** PUR-001 (one-line fix, live data already affected) → PUR-002 (one-line SQL fix, live aging report already wrong) → PUR-003 → PUR-016 residual (run `dedupe-po.js --apply` after a backup; it will reduce the live 4000 but not the 5000 reversal double-count, which is PUR-002). PUR-015 needs a decision: whether any deployed database predates `fn.backfillGlPreposting`.

**Not fixable by repair:** the absence of a GRNI account and a supplier-invoice entity requires a schema + flow addition, not a patch. Until that exists, "accrued/uninvoiced receipts" is not a number this system can produce.