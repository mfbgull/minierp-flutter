# SALES TRANSACTION FLOW — Forensic Accounting Audit

**Repo:** `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter`
**Scope:** sales invoice create/update/delete/restore/cancel, POS sale, SO→invoice conversion, quotation→SO→invoice chain
**Out of scope (other agents):** purchases, standalone returns/settlements, standalone payments, expenses, reports
**Date:** 2026-10-06

### Prior-art read first (mandated)

* `server/docs/known-issues.md` — read in full. Findings overlapping it are tagged **ALREADY-KNOWN** and are *not* re-presented as new.
* `server/docs/gl-authority-map.md` — read in full.
* `server/docs/integer-money-migration-plan.md` — read in full (status: `DESIGN / PLANNING DOCUMENT — NOT IMPLEMENTED`, line 3).

### Evidence method

Every "MEASURED" claim below was produced by executing the **real** server code (`InvoiceCreationService`, `AccountingService`, `InvoiceModel`, `PaymentRecordingService`, `StockMovementModel`, `LedgerUtils`) via `ts-node` against a throwaway `mkdtemp` database (`src/__tests__/setup.ts` pattern), plus read-only `sqlite3` queries against a `/tmp` copy of `server/database/erp.db`. **No repository file was created, edited or deleted.** The harness lives at `/tmp/sales-audit/harness.ts` and `/tmp/sales-audit/h2.ts`; DB copies at `/tmp/sales-audit/*.db`.

---

## 0. MONEY REPRESENTATION (asked explicitly)

**Money is NOT stored as INTEGER minor units. It is stored as SQLite NUMERIC-affinity floats, and the integer-money migration has NOT been done.**

| Column | Declared type | Measured `typeof()` on 416 GL lines + 63 invoice rows |
|---|---|---|
| `invoices.total_amount / paid_amount / balance_amount` | `DECIMAL(15,2)` | `integer` ×28 (all values happen to be whole) |
| `invoice_items.amount / net_amount / tax_amount` | `DECIMAL(15,2)` | `integer` ×35 |
| `journal_lines.debit / credit` | `DECIMAL(15,4)` (`add-gl-foundation.sql:61-62`) | `integer` ×395, **`real` ×7** — 14 lines carry a fractional value, 1 carries sub-cent content |
| `customer_ledger.balance` | `DECIMAL(15,2)` | `integer` ×67, **`real` ×12** |
| `stock_batches.unit_cost` | `DECIMAL(15,4)` (`add-batch-costing.sql:15`) | `integer` ×9 |
| `stock_movements.financial_value` | `DECIMAL(15,4)` | `integer` ×84, **`real` ×1** |

SQLite applies NUMERIC affinity to `DECIMAL`, so a value that happens to be whole is stored in the INTEGER storage class and a fractional one in REAL. **The declared precision is not enforced** — `DECIMAL(15,2)` will store `0.005`. This matches `integer-money-migration-plan.md:68-73`.

**Important nuance — the GL balance check IS exact integer arithmetic even though storage is float.** `AccountingService.postEntry` accumulates `toMinorUnits(debit)` (`accountingService.ts:284-285`, helper `utils/currency.ts:165-167`) and rejects on `totalDebitMinor !== totalCreditMinor` (`accountingService.ts:306`). There is **no epsilon**. This is strictly stronger than the `> 0.01` tolerance recorded in `integer-money-migration-plan.md:316-317` — that line is **stale**. The tolerance survives only in `postOwnerWithdrawalGoodsEntry` (`accountingService.ts:983`) and `assertSufficientFunds` (`:1044`, `:1049`).

**Consequence for the audit:** *storage* is float-exact-risky; *posting* is exact. Findings below therefore separate "imbalanced entry" (none exist — see §2) from "wrong but balanced entry" (where the real damage is).

---

## 1. FLOW TRACE (with exact account codes)

### 1.1 Sales invoice — create

```
lib/features/sales/sales_invoice_form_page.dart:1044  _save()
  └─ :1054-1057  guard qty<=0 per line, expiry dialog
  └─ :1069       _buildBody()                       (:924-958)
       sends customer_id, invoice_date, due_date, status,
       discount_scope/type/value, items[{item_id,quantity,unit_price,
       tax_rate,discount_type,discount_value, amount?(loose only)}],
       total_amount, credit_offset, record_payment
  └─ :1071-1076  invoiceRepository.create(body, idempotencyKey:)   [UPDATE sends NO key]
lib/core/api/endpoints.dart + api_client.dart  →  POST /api/invoices
server/src/routes/invoices.ts:15
  authenticateToken → requirePermission('invoices','create')
  → validateZodBody(zodBodySchemas.invoiceCreate)   [validation.ts:104-108 — items: z.array(z.any())]
  → invoiceController.createInvoice                  [invoiceController.ts:206]
      └─ InvoiceCreationService.create               [InvoiceCreationService.ts:81]
          ├─ validateInput                            [:67-76]  qty>0, unit_price>=0  (NO tax_rate check)
          ├─ computeInvoiceGrandTotal                 [currency.ts:130-152]
          ├─ client-total check  |Δ| > 0.01           [:89-91]
          ├─ offset check legs+credit ≤ total+0.01    [:114-116]
          ├─ credit-pool guard  offset ≤ avail+0.005  [:132-139]
          ├─ invoice_no = generateDocNo('INV',5)      [:141]   ← server-generated only
          ├─ InvoiceModel.createInvoice               [Invoice.ts:762-821]  INSERT invoices
          ├─ claimIdempotencyKey                     [:172-174]
          ├─ per line:
          │    InvoiceModel.findWarehouseForItem      [Invoice.ts:537-588]
          │    InvoiceModel.createInvoiceItem         [Invoice.ts:826-851]
          │        decomposeLineAmount                 [currency.ts:54-77] → amount/net_amount/tax_amount
          │    InvoiceModel.consumeFromOldestBatches  [StockMovement.ts:815]  ← FIFO / FEFO
          │    StockMovementModel.recordMovement ×N   [one SALE movement per cost layer]
          │    cogsAmount += consumed × unitCost      [:206]
          ├─ InvoiceModel.createLedgerEntry           [Invoice.ts:906-927]  customer_ledger DEBIT total
          ├─ AccountingService.postInvoiceEntry       [:213] → Dr 1100 / Cr 4000 / Cr 2100
          ├─ AccountingService.postCOGSEntry          [:214] → Dr 5000 / Cr 1200
          ├─ per payment leg → PaymentRecordingService.recordCustomerPayment [:221-237]
          │        → postPaymentEntry                 → Dr 1000/1010/1020/1030/1040 / Cr 1100
          ├─ credit offset → postCreditOffsetEntry    [:238-246] → Dr 1110 / Cr 1100
          ├─ ledgerUtils.rebuildLedgerBalances        [:248]
          └─ ledgerUtils.recalcCustomerBalanceFromLedger [:249] → customers.current_balance
```

### 1.2 POS sale — create

```
lib/features/sales/pos_screen.dart:281  repo.createSale(..., idempotencyKey:)
lib/features/sales/pos_repository.dart:35-56  → POST /api/pos/sale
server/src/routes/pos.ts:10  → validateZodBody(zodBodySchemas.posSale)  [validation.ts:174-197]
  ↳ NOTE: posSale is strictly typed — tax_rate ∈ [0,100], discount_value ≥ 0,
    discount_type ∈ enum. invoiceCreate is NOT.
posController.createPOSSale  [posController.ts:149]
  ├─ :182-186  computeInvoiceGrandTotal (same function as the invoice path)
  ├─ :188-207  legacy cash guard | tender >= total | → legs
  ├─ :212-218  AccountingService.getClosedPeriodCovering(sale_date) → 409
  ├─ :228-233  customerId = body.customer_id ?? ensureWalkinCustomer()  ['WALK-IN' shared row]
  └─ :236-254  InvoiceCreationService.create({ source:'POS', warehouseId, payments: legs })
                 → identical GL path as §1.1 (Dr 1100 / Cr 4000 / Cr 2100 / Dr 5000 / Cr 1200)
```

### 1.3 Quotation → Sales Order → Invoice

```
POST /api/sales-orders/:id/convert          [salesController.ts:361]
  └─ SalesOrderModel.convertToInvoice       [SalesOrder.ts:620-673]
       ├─ :649-655  items: SO lines → { item_id, quantity, unit_price, amount, discount_type:'none' }
       │            ⚠ tax_rate and discount_value are NOT carried
       ├─ :645     dueDate: invoiceData?.due_date ?? null     ⚠ null, not undefined
       ├─ :656     totalAmount: salesOrder.total_amount        (mismatch check only)
       └─ :636-671 InvoiceCreationService.create({ source:'SALES_ORDER', … })
```

`sales_order_items` has **no** `tax_rate` / `discount_*` columns (schema verified on the DB copy), while `quotation_items` does — so the tax is dropped at `Quotation.ts:595-605`, before the SO ever exists.

### 1.4 Edit / delete / restore / cancel

| Action | Endpoint | Stock | GL | Ledger | Guards |
|---|---|---|---|---|---|
| Update | `PUT /api/invoices/:id` (`routes/invoices.ts:16`) | reverse + re-consume FIFO (`invoiceController.ts:518`, `:545`) | `voidJournalLinesByReference('INVOICE', id)` `:578` then `postInvoiceEntry` `:588` + `postCOGSEntry` `:597` | `recalcCustomerBalanceFromLedger` `:609-611` | closed period `:335` (409); **`items` are NOT validated**; `credit_offset` change refused `:343-348`; **`deleted_payments` cross-invoice guard `:371-381`** |
| Delete | `DELETE /api/invoices/:id` (`:17`) | `reverseStockForItems(..., 'INVOICE_DELETE')` `:713` | void `INVOICE` `:718` + own returns `:722`; *"no lines voided"* guard `:726-728` | reversal rows `:731`, rebuild `:755-756` | status ∈ {Draft,Unpaid} ∧ paid=0 ∧ returned=0 `:695-700`; closed period `:702` |
| Restore | `POST /api/invoices/:id/restore` (`:18`) | re-consume FIFO `:809-848` | `restoreJournalLinesByReference` `:854-857` — **un-void, no re-post, no COGS** | drop REVERSAL rows `:862-869`, un-void original `:870-875` | `deleted_at` set `:800` — **no closed-period guard** |
| Cancel | `PUT /api/invoices/:id/cancel` (`:19`) | `reverseStockForItems(..., 'INVOICE_CANCEL')` `Invoice.ts:1107` | void `INVOICE` + own returns `Invoice.ts:1112-1119`; *"no lines voided"* guard `:1120-1124` | CANCELLATION credit `:1129-1138`, rebuild `:1141-1142` | already-cancelled `:1088`; **paid lock** `:1091-1096`; **returned lock** `:1097-1102`; closed period `invoiceController.ts:940` |

### 1.5 cashService's role in the sales flow

`cashService.ts` posts **nothing** for sales. Grep of `AccountingService`/`postEntry` inside it returns only `voidJournalLinesByReference('BACKFILL_OPENING'|'OPENING_BALANCE')` (`:396-397`) and one `postEntry` for OPENING_BALANCE (`:419`). In the sales flow it contributes exactly two things:

1. `isValidPaymentMethod` / `normalizeCashMethod` (`cashService.ts:62-80`) — the tender whitelist, consumed by `InvoiceCreationService.ts:103`, `invoiceController.ts:429`, `paymentWriterCore.ts:23`.
2. `CASH_GL_CODES` / `getCashAccountTotals` (`:31-48`, `:344-345`) — cash-account totals for the dashboard, read through `AccountingService.getAccountBalance`.

The sales cash leg itself is produced **only** by `AccountingService.postPaymentEntry` (`accountingService.ts:574-606`), whose account is chosen by `_cashOrBankAccountCode` (`:846-856`): `cash→1000`, `bank/checks/cards/transfer/raast→1010`, `easypaisa→1020`, `jazzcash→1030`, `upaisa→1040`, unknown→`1010`, null→`1000`.

---

## 2. JOURNAL ENTRIES PER EVENT — exact account codes

All codes below are quoted from `server/src/migrations/add-gl-foundation.sql:38-47` and confirmed against the live chart on the DB copy:

`1000` Cash · `1010` Bank · `1020` Easypaisa · `1030` JazzCash · `1040` UPaisa · `1100` Accounts Receivable (asset/debit) · `1110` Customer Credit (**asset, credit-normal** — contra-asset) · `1200` Inventory Asset (asset/debit) · `1300` Employee Loan Receivable · `2000` Accounts Payable · `2100` Tax Payable (liability/credit) · `3200` Owner Capital · `3300` Owner Drawings · `4000` Sales Revenue (revenue/credit) · `4100` Sales Returns (revenue/**debit** — contra-revenue) · `4150` Restocking Fee Income · `5000` Cost of Goods Sold (expense/debit) · `6000` Operating Expenses · `6100` Wages & Salaries

### Event 1 — Sales invoice, no tax (MEASURED, scenario A: 4 @ 100, no discount, no payment)

`postInvoiceEntry` `accountingService.ts:557-567` · `reference_type='INVOICE'`, `reference_id=invoices.id`

| # | Account | Dr | Cr |
|---|---|---|---|
| 1 | **1100** Accounts Receivable | 400.00 | |
| 2 | **4000** Sales Revenue | | 400.00 |

### Event 2 — Sales invoice, 10% tax (MEASURED, scenario A: 4 @ 100 + 10% tax)

`postInvoiceEntry` `accountingService.ts:542-553` (taxAmount = `InvoiceModel.getInvoiceTaxTotal`, `Invoice.ts:861-867` = `Σ invoice_items.tax_amount`)

| # | Account | Dr | Cr |
|---|---|---|---|
| 1 | **1100** Accounts Receivable | 440.00 | |
| 2 | **4000** Sales Revenue | | 400.00 |
| 3 | **2100** Tax Payable | | 40.00 |

Stored line: `amount=440.00, net_amount=400.00, tax_amount=40.00` (`Invoice.ts:826-851`).

### Event 3 — COGS recognition (MEASURED, scenario A, same transaction)

`postCOGSEntry` `accountingService.ts:1108-1118` · `reference_type='INVOICE'`, same `reference_id`

| # | Account | Dr | Cr |
|---|---|---|---|
| 1 | **5000** Cost of Goods Sold | 200.00 | |
| 2 | **1200** Inventory Asset | | 200.00 |

`200.00 = 4 units × 50.00` — the **FIFO layer cost**, not `unit_price`, not `items.standard_cost`.

### Event 4 — Customer payment (MEASURED, scenario O: 200 on a 500 invoice)

`postPaymentEntry` `accountingService.ts:595-605` · `reference_type='PAYMENT'`, `reference_id=payments.id`

| # | Account | Dr | Cr |
|---|---|---|---|
| 1 | **1000** Cash (or 1010/1020/1030/1040 per method) | 200.00 | |
| 2 | **1100** Accounts Receivable | | 200.00 |

### Event 5 — Store-credit offset applied at sale time

`postCreditOffsetEntry` `accountingService.ts:636-646` · `reference_type='CREDIT_OFFSET'`, `reference_id=invoices.id`

| # | Account | Dr | Cr |
|---|---|---|---|
| 1 | **1110** Customer Credit | *offset* | |
| 2 | **1100** Accounts Receivable | | *offset* |

Plus a sub-ledger-only row: `InvoiceModel.createLedgerEntry(..., 'CREDIT', 'CREDIT-{invoiceNo}', 0, poolApplied)` (`InvoiceCreationService.ts:244`) and `customers.credit_balance` decrement (`:243`). **No further GL** — the pool half has no ledger row to reverse (see `server/src/models/AGENTS.md`, "CREDIT OFFSET BEHAVIOUR").

### Event 6 — Sales return (goods), per the return service (`invoiceReturnService.ts:392-406`)

`postInvoiceReturnEntry` `accountingService.ts:1243-1250` · `reference_type='INVOICE_RETURN'`, `reference_id=invoice_returns.id` (**the return id, not the invoice id** — see the id-space warning at `Invoice.ts:1029-1036`)

| # | Account | Dr | Cr |
|---|---|---|---|
| 1 | **1100** Accounts Receivable | | Σ(returnedNet + returnedTax) |
| 2 | **4100** Sales Returns | Σ returnedNet | |
| 3 | **2100** Tax Payable | Σ returnedTax *(only when > 0)* | |

### Event 7 — Restocking fee (`invoiceReturnService.ts:407-415`)

`postReturnFeeEntry` `accountingService.ts:1286-1296` · `reference_type='RETURN_FEE'`, `reference_id=returnId`

| # | Account | Dr | Cr |
|---|---|---|---|
| 1 | **1100** Accounts Receivable | *fee* | |
| 2 | **4150** Restocking Fee Income | | *fee* |

### Event 8 — COGS reversal on return (`invoiceReturnService.ts:417-429`)

`postCOGSReversalEntry` `accountingService.ts:1160-1170`

| # | Account | Dr | Cr |
|---|---|---|---|
| 1 | **1200** Inventory Asset | *FIFO cost* | |
| 2 | **5000** Cost of Goods Sold | | *FIFO cost* |

### Event 9 — Cancel / delete (no new entry — void only)

`voidJournalLinesByReference` `accountingService.ts:1402-1428` sets `voided=1, voided_at, voided_by, void_reason` on every `reference_type='INVOICE'` line for the invoice (which covers **both** the revenue entry and the COGS entry, since they share the reference — deliberate, documented at `Invoice.ts:1074-1075`). Ledger-wise a `CANCELLATION` credit row is appended (`Invoice.ts:1129-1138`) or a `REVERSAL:INVOICE` row (`Invoice.ts:1011-1022`). **No offsetting GL entry is written** — the void is the reversal.

---

## 3. COGS RECOGNITION POINT AND INVENTORY VALUATION METHOD (proved from code)

### 3.1 Recognition point

**COGS is recognised at stock consumption, inside the invoice-create transaction, after the invoice header row is written.** `InvoiceCreationService.ts:190-214`:

```
:190  const consumption = InvoiceModel.consumeFromOldestBatches(item_id, warehouseId, quantity, db)
:192-207  for each consumed layer:
            recordMovement({ movement_type:'SALE', quantity: -consumed, unit_cost: layerCost, batch_id })
            cogsAmount += entry.consumed * entry.unitCost
:212  createLedgerEntry(...)                      ← customer_ledger
:213  postInvoiceEntry(...)                       ← Dr 1100 / Cr 4000 / Cr 2100
:214  if (cogsAmount > 0) postCOGSEntry(...)      ← Dr 5000 / Cr 1200
```

Order is therefore: invoice row → items → layers consumed (batches decremented) → AR/revenue/tax → COGS. All inside one `db.transaction()` (`:123`, `:254`). **MEASURED (scenario A):** 4 units at layer cost 50 produced `Dr 5000 200.00 / Cr 1200 200.00` in the same commit as `Dr 1100 440.00`.

The equivalent on the edit path is `invoiceController.ts:545-604` (`updatedCogsTotal` at `:571`, `postCOGSEntry` at `:597`), and on the restore path `invoiceController.ts:823-847` — which records the SALE movement but **posts no COGS** (see SALES-013).

### 3.2 Valuation method: **FIFO cost layers**, with **FEFO** substituted for expiry-tracked items. No weighted average, no batch costing at the invoice level.

Proved by:

* `add-batch-costing.sql:3-19` — `stock_batches` is the cost-layer table (`quantity_original`, `quantity_remaining`, `unit_cost DECIMAL(15,4)`), one row per receipt/production/transfer/return.
* `StockMovement.ts:869-870` — `const useFEFO = itemRow?.has_expiry === 1;`
* **FIFO ordering** (`StockMovement.ts:1032`, non-expiry items):
  `ORDER BY received_date ASC, id ASC` over `quantity_remaining > 0`.
* **FEFO ordering** (`StockMovement.ts:1008-1012`, expiry-tracked items):
  `ORDER BY CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END, expiry_date ASC, received_date ASC, id ASC`
  with `AND (expiry_date IS NULL OR expiry_date >= date('now'))` (`:1007`).
* **MEASURED (scenario A):** `Dr 1200 200.00` for 4 units = `4 × 50.00` layer cost, while revenue was `4 × 100.00` — proving the GL uses the layer cost, not the sale price.
* **Standard-cost fallback:** when no batch rows exist, `StockMovement.ts:1049-1054` (and `:929-935` on the flag-on path) returns `[{ batchId: null, consumed: quantity, unitCost: items.standard_cost }]` — i.e. the whole quantity at `items.standard_cost`.
* **Weighted average appears in exactly two places, neither of which drives the GL:**
  1. `StockMovement.ts:1129-1131` — the *mirror* batch created by an inter-warehouse transfer, averaged across the source layers.
  2. `Invoice.ts:710-717` — `avgUnitCost` written to the restore ADJUSTMENT movement. `Invoice.ts:730-738` explicitly states this posts **no** GL leg (`skipAdjustmentFinancialPosting: true`).
* **`add-item-locations.sql`** creates `item_locations` (rack tracking) only — it does **not** touch valuation. Per-location quantities live in `batch_stock_by_location` (added by `add-batch-location-model.sql`), which is a *second* representation of availability.

**KNOWN-ISSUE INTERACTION (ALREADY-KNOWN, `known-issues.md` item 3):** with `feature_batch_locations = ON`, `consumeFromOldestBatches` takes the no-per-location-coverage fallback (`StockMovement.ts:928-935`) and returns `batchId: null`, so the whole sale is priced at `items.standard_cost` and the sale movement carries `batch_id: null` — meaning `Invoice.ts:662-707`'s restore loop is skipped entirely. Not re-reported as new.

---

## 4. IS EVERY EVENT BALANCED? WHERE BALANCING IS ENFORCED VS NOT

### 4.1 Enforced — one chokepoint, and it is airtight

`AccountingService.postEntry` (`accountingService.ts:251-417`) validates, in order:

| # | Rule | Line | Failure |
|---|---|---|---|
| 1 | ≥ 2 lines | `:252-254` | throws |
| 2 | `entry_date` present | `:255-257` | throws |
| 3 | `debit ≥ 0 AND credit ≥ 0` | `:275-277` | throws |
| 4 | **debit XOR credit** (not both) | `:278-280` | throws |
| 5 | **exactly one of debit/credit non-zero** | `:281-283` | throws |
| 6 | account exists in `chart_of_accounts` | `:294-297` | throws |
| 7 | **Σ minor units debits === Σ minor units credits** | `:306-311` | throws |
| 8 | an open period covers `entry_date` | `:318-360` | throws |

Rule 7 is **exact integer minor-unit comparison** (`toMinorUnits`, `currency.ts:165-167`) — **zero epsilon**, strictly stronger than the `> 0.01` documented in `integer-money-migration-plan.md:316-317`.

Additionally enforced by the DB itself:

```sql
-- journal_lines
CHECK (debit = 0 OR credit = 0),
CHECK (debit >= 0 AND credit >= 0)
-- stock_balances
quantity DECIMAL(15,3) NOT NULL DEFAULT 0 CHECK(quantity >= 0)
```

**Every one of the 19 typed sales-relevant entry points routes through `postEntry`** — `postInvoiceEntry`, `postPaymentEntry`, `postCreditOffsetEntry`, `postCOGSEntry`, `postCOGSReversalEntry`, `postInvoiceReturnEntry`, `postReturnFeeEntry`, `postRefundEntry` (`accountingService.ts:514, 574, 614, 1087, 1133, 1191, 1265, 1354`). Verified: **no unbalanced entry exists anywhere in the DB copy** —

```
SELECT journal_entry_id, SUM(debit)-SUM(credit) FROM journal_lines WHERE voided=0
  GROUP BY journal_entry_id HAVING ABS(SUM(debit)-SUM(credit))>0.0001   → 0 rows
SELECT SUM(debit), SUM(credit) FROM journal_lines WHERE voided=0       → 243283.8 / 243283.8
```

**MEASURED in the harness:** every scenario (A–R) ended with `balanced = true`.

### 4.2 NOT enforced — where balancing is absent or bypassable

| Gap | file:line | Consequence |
|---|---|---|
| **`postEntry` validates the entry, not the business.** `postInvoiceEntry` returns `null` — no error, no posting — whenever `totalAmount <= 0` | `accountingService.ts:525` | A sale can relieve stock and post COGS with **zero** Dr AR / Cr revenue. MEASURED: scenario R (header discount ≥ line total) and scenario M (edit to zero total) |
| **`voidJournalLinesByReference` is not double-entry-aware.** It voids every matching line and writes nothing back | `accountingService.ts:1402-1428` | Voiding the *invoice* entry silently voids the *COGS* entry that shares `reference_type='INVOICE'`. Intentional (`Invoice.ts:1074-1075`) but means a partial void is impossible |
| **`restoreJournalLinesByReference` is a bare `UPDATE voided = 0`** — no balance recomputation, no cost re-derivation, no period guard | `accountingService.ts:1443-1468`; caller `invoiceController.ts:854-857` | SALES-013 |
| **`postLegacyStockEntry` writes `journal_lines` directly** and is *not* routed through `postEntry` | `accountingService.ts:438-497` (inserts at `:488-495`) | No XOR check, no period check, no account-existence check beyond a lookup. Balanced by construction (two legs, same amount), but it is a **second writer to `journal_lines` that bypasses the authority**. `gl-authority-map.md:2.1` lists it as canonical; it is not |
| **`assertNoActivePosting` exists but is NOT used on the invoice path** | `accountingService.ts:1065-1073`; only callers `models/OwnerCapital.ts:69`, `models/OwnerWithdrawal.ts:225,286` | Nothing structurally prevents a double revenue/COGS posting for one invoice. The only guard is the *optional* idempotency key |
| **A `restockRatio` rounding loss is possible on restore** | `Invoice.ts:659-664` `ratio = min(roundQty(effectiveQty/totalSold), 1)`, `restoreQty = roundQty(|movement.quantity| × ratio)` | Two partial returns can leave a sub-paisa residual on `stock_batches.quantity_remaining`. Same class as the documented `invoiceReturnService.ts:351` division loss (`integer-money-migration-plan.md:7.4`) |
| **Trial balance stays balanced while the sub-ledgers go wrong** | — | Every finding in §5 below is *balanced-but-wrong*. `known-issues.md` §"Validating a guard" item 4 applies verbatim: invariant A cannot see any of them |

---

## 5. TAX / VAT HANDLING

### 5.1 The one computation

`decomposeLineAmount` — `utils/currency.ts:54-77`. This is the **single** line-tax function, used by the storage path (`Invoice.ts:831`) *and* the total path (`currency.ts:141`):

```
:62-65  override = parseCurrency(args.amount);  gross = override > 0 ? roundCurrency(override)
                                                            : multiplyCurrency(quantity, unit_price)
:66-73  if (discount_value > 0):
           discountAmount = type=='flat' ? roundCurrency(dv)
                                         : roundCurrency(gross * dv/100)
           net = subtractCurrency(gross, Math.min(discountAmount, gross))   ← clamped at gross
:74-75  taxRate  = parseCurrency(args.tax_rate || 0)
        taxAmount = taxRate !== 0 ? roundCurrency(net * taxRate/100) : 0    ← on NET
:76     return { amount: addCurrency(net, taxAmount), netAmount: net, taxAmount, gross }
```

### 5.2 Answers to the specific questions

| Question | Answer | Proof |
|---|---|---|
| **Tax-inclusive or exclusive?** | The stored `invoice_items.amount` is **tax-INCLUSIVE**; `net_amount` + `tax_amount = amount`. Tax is computed on the **exclusive** net. | `add-invoice-item-tax-columns.sql:2-4` (`amount` comment) and the header of `currency.ts:46-51`. MEASURED (scenario A): `amount=440, net=400, tax=40` |
| **Which tax feeds the GL?** | `Σ invoice_items.tax_amount` read back from the stored rows — never recomputed. | `InvoiceModel.getInvoiceTaxTotal` `Invoice.ts:861-867`; called at `InvoiceCreationService.ts:213` and `invoiceController.ts:586`. Comment at `Invoice.ts:854-858` names the invariant (H3) |
| **Discount before or after tax?** | **Item-scope discount: before tax** (reduces the base). **Invoice/header-scope discount: AFTER tax** (never touches the base). | `currency.ts:72` (item discount → `net`) vs `currency.ts:145-151` (header discount subtracted from `linesTotal`, which already contains tax). See **SALES-001** |
| **Rounding** | Half-up at 2 dp via the `e+2` string trick, applied at **every** boundary: gross, discount, net, tax, amount, and again on the header total. Rounding mode is `Math.round`, which is **half-away-from-zero for positives and toward-zero for negatives**. | `roundCurrency` `currency.ts:8-11`; `addCurrency`/`subtractCurrency`/`multiplyCurrency` `:13-23`. Per-line rounding means `Σ tax ≠ tax(Σ)` **by design** — `currency.ts:79-88` and `integer-money-migration-plan.md:7.4` both state this and call it intentional |
| **Client/server parity** | Parity holds for the line decomposition. It **breaks** at the header-discount cap — see **SALES-006**. | Client `invoice_calculations.dart:44-70, 87-95, 122-128`; server `currency.ts:130-152` |

### 5.3 Validation bounds on `tax_rate` — the asymmetry

| Path | Bound | Location |
|---|---|---|
| **POS** | `tax_rate: z.number().min(0).max(100).optional()` | `middleware/validation.ts:181` |
| **Invoice** | **none** — `items: z.array(z.any()).min(1)` + `.passthrough()`; `validateInput` checks `item_id`, `quantity`, `unit_price` but **never `tax_rate`** | `validation.ts:104-108`; `InvoiceCreationService.ts:71-75` |
| **DB** | `invoice_items.tax_rate DECIMAL(5,2) DEFAULT 0` — no `CHECK`, no `NOT NULL` | `add-invoice-discount-tax-fields.sql:10` |

**MEASURED (scenario D):** `tax_rate: 500` accepted on `POST /api/invoices` → `Cr 2100 = 1000.00`, `Cr 4000 = 200.00`, `Dr 1100 = 1200.00`. Balanced, and output tax is 5× the goods value.

**MEASURED (scenario E):** `tax_rate: -50` accepted → `invoice_items.tax_amount = −100.00` stored **negative**, header `total_amount = 100.00`, and the GL posted `Dr 1100 100.00 / Cr 4000 100.00` with **no `2100` line at all**. See **SALES-002**.

---

## 6. CUSTOMER AR BALANCE DERIVATION — the actual SQL

There are **four** representations. They are reconciled, not unified (`gl-authority-map.md` §5).

### 6.1 Operational AR — what every AR report reads

`utils/reportSql.ts:68-70`:
```sql
-- AR_OUTSTANDING
WHERE balance_amount > 0
  AND status NOT IN ('Cancelled', 'Draft')
```
Consumers: `Reports.ts:16` (AR aging per customer), `:27` (aging summary), `:108` (top debtors), `:119` (DSO), `:209` (receivables summary), **`:1286` (the `getGLReconciliation` AR pairing)**, `Dashboard.ts:581, 696, 698`, `invoiceReturnService.ts:1060, 1167`.

`balance_amount` is written by `ledgerUtils.calculateInvoiceBalance` (`ledgerUtils.ts:144-185`):
```sql
SELECT COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) AS total_paid
FROM payment_allocations WHERE invoice_id = ? AND voided_at IS NULL
```
then `collections = paid + credit_offset` (`:166`),
`owed = (total_amount − returned_amount + return_fee) − collections` (`:173-176`), `balance = max(owed, 0)` (`:177`), and
`UPDATE invoices SET paid_amount = collections, balance_amount = balance` (`:181-182`).

### 6.2 GL AR — the control account

`AccountingService.getAccountBalance` (`accountingService.ts:136-174`):
```sql
SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0)
FROM journal_lines
WHERE account_id = ? AND line_date <= ? AND voided = 0
```
signed by `normal_balance` (`:159-161`).

### 6.3 Customer sub-ledger — `customers.current_balance`

`ledgerUtils.recalcCustomerBalanceFromLedger` (`ledgerUtils.ts:327-339`):
```sql
SELECT COALESCE(SUM(debit),0) − COALESCE(SUM(credit),0) AS net
FROM customer_ledger
WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL
```
→ `UPDATE customers SET current_balance = ?`. Plus `credit_balance` (unsigned pool, `-`) per `models/AGENTS.md`.

### 6.4 The reconciliation, and the answer to "AR = unpaid invoices − unapplied payments − credit notes"

`Reports.getGLReconciliation` (`Reports.ts:1284-1295`) pairs GL 1100 against `Σ balance_amount`:
```sql
SELECT COALESCE(SUM(balance_amount),0) FROM invoices
WHERE balance_amount > 0 AND status NOT IN ('Cancelled','Draft') AND invoice_date <= ?
```
`known-issues.md` item 6 fixes invariant F's equation as:
```
|GL(1100) + GL(1110)|  ==  |Σ (current_balance − credit_balance)|
```

**So the derivation is NOT the textbook "unpaid invoices − unapplied payments − credit notes" as one expression.** It is:

* **unpaid invoices** → `Σ balance_amount` over `AR_OUTSTANDING`, where each `balance_amount` already nets `− Σ positive payment_allocations − credit_offset + returned_amount + return_fee` (`ledgerUtils.ts:166-177`);
* **unapplied payments** → never deducted from AR at all. A payment with no allocation credits 1100 in full (`postPaymentEntry`) while no invoice's `balance_amount` changes → the two representations diverge by design until `allocateExistingPayment` runs;
* **credit notes** → appear **only** through the `credit_offset` reduction of `balance_amount` and the `Dr 1110 / Cr 1100` offset entry. A return settled as *store credit* posts **no** GL (`applyCredit`, `invoiceReturnService.ts:1005+`) — correct per `known-issues.md` item 6, which **measured** that adding an entry does not work.

### 6.5 MEASURED on the DB copy

```
AR_OUTSTANDING Σ(balance_amount)          = 5450.00
GL 1100 signed balance (credit-normal)    =   150.20   (Σcr 42800.20 − Σdr 42650.00)
GL 1110 signed balance                    = -3000.00   (debit-normal asset holding a credit)
GL 1200 signed balance                    =  2433.60
Σ invoices.total_amount != Σ invoice_items.amount → 0 rows (all invoices foot)
invoices with total_amount <= 0                    → 0 rows
per-entry Dr≠Cr over live journal_lines            → 0 rows
```

The 5450.00 vs 150.20 divergence is **placeholder divergence in an untracked scratch database** and is explicitly declared non-evidence by `known-issues.md` §1 ("These rows are *not* evidence about current behaviour, in either direction"). **Not reported as a finding.** All measurements in §5 are from clean databases driven through the current code.

---

## 7. FINDINGS

Severity scale: **CRITICAL** (silent, unbalanced, or unrecoverable money loss) · **HIGH** (silent, wrong GL/sub-ledger figure on a normal business path) · **MEDIUM** (wrong figure, or a correct figure via an accidental guard) · **LOW** (hardening / latent).

---

### SALES-001 — Invoice-scope (header) discount never reduces the tax base

**Severity: HIGH** · **Status: NEW**
**Files:** `server/src/utils/currency.ts:74-76`, `:145-151`

**Description.** Line tax is computed on the post-item-discount net (`currency.ts:74-75`). The invoice-scope discount is then subtracted from `linesTotal` — which *already contains tax* — at `currency.ts:151`. It therefore reduces revenue and AR but leaves `2100 Tax Payable` untouched. The identical discount expressed as an **item**-scope discount reduces the tax base.

**Financial impact.** MEASURED, same trade both ways (4 @ 100, 10% tax, 10% discount):

| Scope | `Cr 4000` | `Cr 2100` | `Dr 1100` |
|---|---|---|---|
| item-scope | 360.00 | **36.00** | 396.00 |
| invoice-scope | 360.00 | **40.00** | 400.00 |

**Output tax overstated by 4.00 (11.1%) purely from the discount scope**, and the AR/revenue side also disagrees by 4.00 — so the two presentations of the same sale cannot both be right. Scales linearly with tax rate × discount.

**Evidence.**
```ts
// currency.ts:74-76  — tax on net, BEFORE any header discount
const taxRate = parseCurrency(args.tax_rate || 0);
const taxAmount = taxRate !== 0 ? roundCurrency(net * (taxRate / 100)) : 0;
return { amount: addCurrency(net, taxAmount), netAmount: net, taxAmount, gross };
```
```ts
// currency.ts:145-151 — header discount subtracted from the tax-INCLUSIVE linesTotal
if (header?.discount_scope !== 'invoice') return linesTotal;
const discountValue = parseCurrency(header.discount_value || 0);
if (discountValue <= 0) return linesTotal;
const discount = header.discount_type === 'percentage'
  ? roundCurrency(subtotal * (discountValue / 100))
  : roundCurrency(discountValue);
return subtractCurrency(linesTotal, Math.min(discount, linesTotal));
```

**Fix.** Allocate the header discount pro-rata across lines *before* the tax step and recompute per-line tax — i.e. move the header discount into `decomposeLineAmount` as a second discount term, mirroring what `invoiceReturnService.allocateHeaderDiscount` already does on the return side (`invoiceReturnService.ts:304-308` computes `invoiceSubtotal` and allocates the header discount across return lines for exactly this reason). If the business genuinely intends "discount after tax", make it explicit in the schema (`tax_base_includes_header_discount`) rather than emergent.

**Accounting reference.** IAS 21.12 (taxable amount is the consideration for the transaction); IFRS 15 B5–B8 and B34 (discounts reduce the transaction price). For output VAT, the taxable consideration is the amount actually charged to the customer, so a post-tax discount overstates the liability.

---

### SALES-002 — Negative `tax_rate` accepted on the invoice path; GL silently credits revenue with the tax-inclusive total and omits `2100` entirely

**Severity: HIGH** · **Status: NEW**
**Files:** `server/src/services/accountingService.ts:533-556`; `server/src/services/InvoiceCreationService.ts:71-75`; `server/src/middleware/validation.ts:104-108`

**Description.** Two compounding defects.

1. No bound on `tax_rate` for `POST /api/invoices`. `validateInput` (`InvoiceCreationService.ts:71-75`) checks `item_id`, `quantity`, `unit_price` and never `tax_rate`; the zod schema is `items: z.array(z.any())` (`:107`), which validates nothing.
2. `postInvoiceEntry` selects the 3-line vs 2-line form with **`if (taxAmount > 0)`** (`accountingService.ts:536`). A *negative* `taxAmount` fails that test, so it takes the 2-line no-tax branch and credits `4000` with the **full `totalAmount`**, which already nets out the negative tax. `2100` is never touched.

**Financial impact.** MEASURED (scenario E — 2 @ 100, `tax_rate: -50`):

```
invoice_items : { amount: 100.00, net_amount: 200.00, tax_amount: -100.00 }   ← negative tax STORED
GL            : Dr 1100  100.00
                Cr 4000  100.00      ← revenue = gross (200) − tax (100); the tax vanished into revenue
                (no 2100 line)
Dr 5000 / Cr 1200 : 100.00 / 100.00  ← COGS posted normally
```

Revenue is **overstated by 100.00 on a 200.00 sale (+100%)**, and a negative liability is never recognised. The stored `tax_amount = -100.00` also poisons the tax summary and any future return mirroring.

**Evidence.**
```ts
// accountingService.ts:533-556
const taxAmount = Number(args.taxAmount) || 0;
const netAmount = args.totalAmount - taxAmount;

if (taxAmount > 0) {                       // ← negative tax falls through
  ...
  lines: [ Dr 1100 total, Cr 4000 net, Cr 2100 tax ]
}
// No tax — backward-compatible 2-line entry
lines: [ Dr 1100 args.totalAmount, Cr 4000 args.totalAmount ]   // ← 2100 omitted
```

**Fix.** (a) Reject `tax_rate < 0` (and `> ` a configured cap) in `InvoiceCreationService.validateInput` and in a typed zod item schema, matching `validation.ts:181`. (b) Change `if (taxAmount > 0)` to `if (taxAmount !== 0)` so a negative tax can never silently take the no-tax branch even if a negative rate ever reaches it.

**Accounting reference.** IAS 1.34 / IFRS 15 B5 — revenue is recognised at the fair value of the consideration; a negative output tax is not revenue.

---

### SALES-003 — `tax_rate > 100%` accepted on the invoice path (POS is bounded, the invoice path is not)

**Severity: MEDIUM** · **Status: NEW**
**Files:** `server/src/middleware/validation.ts:104-108` vs `:181`; `server/src/services/InvoiceCreationService.ts:71-75`

**Description.** The two sales create paths validate `tax_rate` inconsistently.

| Path | Bound | Line |
|---|---|---|
| `POST /api/pos/sale` | `z.number().min(0).max(100)` | `validation.ts:181` |
| `POST /api/invoices` | **none** | `validation.ts:107` + `InvoiceCreationService.ts:71-75` |

**Financial impact.** MEASURED (scenario D — 2 @ 100, `tax_rate: 500`):
```
Dr 1100 1200.00 | Cr 4000 200.00 | Cr 2100 1000.00 | Dr 5000 100.00 | Cr 1200 100.00
```
Output tax exceeds goods value 5×. Balanced and internally consistent, but the input tax rate is entirely client-controlled with no server cap on the primary sales endpoint.

**Evidence.** MEASURED GL dump above; bounds quoted from the two zod schemas.

**Fix.** Extract one shared `invoiceItemSchema` (item_id / quantity / unit_price / tax_rate / discount_type / discount_value / amount) and apply it to `invoiceCreate`, `mobileSubmit` and `posSale`, with `tax_rate: z.number().min(0).max(100)` and `quantity: z.number().positive()`. Replace `z.array(z.any())` at `:107` and `:237` and the `.passthrough()` on items. This closes SALES-002, SALES-003, SALES-009 and SALES-018 in one change.

**Accounting reference.** IAS 1 / IFRS 15 — rates come from legislation, not from the invoice operator.

---

### SALES-004 — `PUT /api/invoices/:id` is not idempotency-keyed and records payments outside the payment writer → double-submit duplicates cash

**Severity: HIGH** · **Status: NEW**
**Files:** `server/src/controllers/invoiceController.ts:426-465`; `lib/features/sales/sales_invoice_form_page.dart:1069-1076`

**Description.** The update path records an inline payment by calling the **model** directly rather than `PaymentRecordingService`:

```ts
// invoiceController.ts:445-465
const newPaymentNo = InvoiceModel.generatePaymentNoAtomic(db);
const newPaymentId = InvoiceModel.createPayment(db, newPaymentNo, parsedCustomerId, …);
InvoiceModel.createPaymentAllocation(db, newPaymentId, invoiceId, newPaymentAmount);
InvoiceModel.createLedgerEntry(db, parsedCustomerId, 'PAYMENT', newPaymentNo, …);
AccountingService.postPaymentEntry(db, { paymentId: newPaymentId, … });
```

That bypasses `PaymentRecordingService.recordCustomerPayment` (`services/PaymentRecordingService.ts:33-83`), which is the **only** place `beginIdempotentWrite` / `claimIdempotencyKey` (`:34-51`, `:77-80`) is applied to customer payments. `assertNoActivePosting` (`accountingService.ts:1065`) is not called either — its only callers are `OwnerCapital.ts:69` and `OwnerWithdrawal.ts:225, 286`.

The Flutter client only sends an `Idempotency-Key` on **create**:
```dart
// sales_invoice_form_page.dart:1071-1076
final result = _isEdit
    ? await invRepo.update(widget.invoice!.id, body)          // ← no key
    : await invRepo.create(body, idempotencyKey: _createIdempotencyKeyFor(body));
```
and the surrounding comment (`:1094-1097`) states the consequence in the code's own words: *"Update/delete are not idempotency-keyed, so they keep the honest failure message."*

**Financial impact.** A retried `PUT` (client timeout, user double-tap, proxy retry) creates **two `payments` rows, two `payment_allocations`, two `Dr 1000 / Cr 1100` journal entries, and two `customer_ledger` PAYMENT credits** for one intended receipt. Cash is overstated in the GL and in `collectFlows`; `paid_amount` is double-inflated and `balance_amount` clamps to 0. There is no GL/AR divergence — both sides move together — which is precisely why it is invisible to invariants A–E.

**Evidence.** The three call sites are quoted above. The idempotency table supports it (`add-idempotency-keys.sql`, `scope-idempotency-keys.sql`) and `idempotency.ts:189-212` (`startIdempotentRequest`) is not invoked anywhere in `updateInvoice`.

**Fix.** (a) Wrap the inline-payment block in `startIdempotentRequest(db, req.headers, IDEMPOTENCY_SCOPES.PAYMENT_CUSTOMER, hashRequestPayload(req.body))` + `claimIdempotencyKey`, matching `invoiceController.ts:1025-1033`. (b) Prefer routing through `PaymentRecordingService.recordCustomerPayment({ mode: 'INVOICE_SETTLEMENT', … })` so the allocation ceiling (`paymentValidation.ts:64-84`) and the period guard (`paymentWriterCore.ts:30-32`) apply. (c) Add `assertNoActivePosting` for the invoice's own `INVOICE` reference inside the transaction.

**Accounting reference.** Audit trail integrity — completeness of the record of transactions (ISA 240 / ISA 500).

---

### SALES-005 — Editing an invoice down to a zero total voids the original GL, posts nothing, and leaves a bare `Cr 1100` with no revenue

**Severity: HIGH** · **Status: NEW**
**Files:** `server/src/controllers/invoiceController.ts:578`, `:588`; `server/src/services/accountingService.ts:525`

**Description.** `updateInvoice` is **void-then-repost** with no floor on the repost:

```ts
// invoiceController.ts:578-595
AccountingService.voidJournalLinesByReference(db, 'INVOICE', invoiceId, {…});
const updatedTaxAmount = InvoiceModel.getInvoiceTaxTotal(db, invoiceId);
AccountingService.postInvoiceEntry(db, {
  invoiceId, invoiceNo: resolvedInvoiceNo,
  totalAmount: totalAmountNum, invoiceDate: invoice_date, userId, taxAmount: updatedTaxAmount,
});
```

and `postInvoiceEntry` returns `null` rather than throwing when the total is non-positive:
```ts
// accountingService.ts:525
if (!args.totalAmount || args.totalAmount <= 0) return null;
```

The only over-payment guard (`:437`) covers a **new** payment in the same request; nothing prevents editing the **lines** of an invoice that already carries payments.

**Financial impact.** MEASURED (scenario M — a 400.00 invoice fully paid 400.00, then edited so the lines total 0.00):

```
invoice row : { status:'Paid', total_amount:0, paid_amount:400, balance_amount:0, payment_status:'Paid' }

live GL lines touching this invoice:
  INVOICE   1100 Accounts Receivable   D=400  C=0     voided=1   ← original sale DEBIT removed
  INVOICE   4000 Sales Revenue         D=0    C=400   voided=1
  INVOICE   5000 Cost of Goods Sold    D=200  C=0     voided=1
  INVOICE   1200 Inventory Asset       D=0    C=200   voided=1
  PAYMENT   1000 Cash                  D=400  C=0     voided=0   ← payment survives
  PAYMENT   1100 Accounts Receivable   D=0    C=400   voided=0   ← bare CREDIT, no offsetting debit
```

Result: **GL `1100` carries a 400.00 credit for which no sale exists; GL `4000` carries no revenue at all.** The sub-ledger says "Paid, balance 0". The **trial balance stays perfectly balanced**, so invariant A passes and nothing alerts. A later `getGLReconciliation` AR pairing reports a delta of 400.00.

**Evidence.** Quoted above; measured dump reproduced.

**Fix.** Before voiding, reject the edit when the invoice already has recorded payments/credit and the recomputed `totalAmountNum` is `<= 0` (or `< paid_amount`) — mirror `Invoice.ts:1091-1102`'s paid-lock, which `cancelInvoiceInternal` already has and `updateInvoice` does not. Alternatively, when `totalAmountNum <= 0` and payments exist, post an explicit balancing reversal (`Dr 4000 / Cr 1100` for the residual) instead of silently voiding.

**Accounting reference.** Accrual / cut-off: a receivable may not be derecognised without derecognising the corresponding revenue (IAS 1.27, IFRS 15.25). The trial balance being balanced is not evidence of correctness.

---

### SALES-006 — A header discount ≥ the tax-inclusive line total yields a zero-value invoice that still relieves stock and posts COGS with no revenue

**Severity: MEDIUM-HIGH** · **Status: NEW**
**Files:** `server/src/utils/currency.ts:151`; `server/src/services/accountingService.ts:525`; `server/src/services/InvoiceCreationService.ts:190-214`; `lib/features/sales/calculations/invoice_calculations.dart:116`

**Description.** `computeInvoiceGrandTotal` clamps the header discount to `linesTotal` (the **tax-inclusive** sum), so an over-large discount drives the header total to exactly `0`. Stock consumption and `postCOGSEntry` run *before* the revenue posting and are not conditional on the total.

Secondary defect — the **client and server clamp to different bases**, so the Flutter form cannot even save such an invoice:
```dart
// invoice_calculations.dart:111-116
final subtotal = calculateSubtotal(items);
final raw = invoiceDiscount.type == percentage ? subtotal * value/100 : value;
final rounded = _round2(raw);
return rounded > subtotal ? subtotal : …;      // ← capped at GROSS subtotal
```
```ts
// currency.ts:151
return subtractCurrency(linesTotal, Math.min(discount, linesTotal));   // ← capped at GROSS+TAX
```

**Financial impact.** MEASURED (scenario R — 1 @ 100 with 10% tax, flat header discount 5000):
```
server grand total              = 0.00
Dr 5000 Cost of Goods Sold 50.00 | Cr 1200 Inventory Asset 50.00
(no 1100 line, no 4000 line, no 2100 line at all)
```
**Inventory worth 50.00 left the building and a COGS charge was booked against zero revenue.** The invoice's `total_amount = 0`, so `AR_OUTSTANDING` excludes it, `paid_amount = 0`, and it is invisible everywhere. A 500% *percentage* discount reaches the same state through `currency.ts:71-72` (`Math.min(5×gross, gross)` → `net = 0`).

MEASURED client/server disagreement: the client sends `total_amount = 10.00` (tax survives because it caps at the tax-exclusive subtotal), the server computes `0.00`, and `InvoiceCreationService.ts:89-91` throws → **HTTP 400 `total_amount disagrees with line items`**. The Flutter form is therefore *unusable* for any invoice-scope discount ≥ the pre-tax subtotal, while other API clients silently create the zero-value stock loss.

**Evidence.** Quoted above; measured GL dump.

**Fix.** (a) Make the client and server clamp to the same base — cap at `linesTotal` in `calculateDiscount` (`invoice_calculations.dart:116`), or cap at `subtotal` in `currency.ts:151` and document that tax is not discountable. (b) Add a floor: reject `discount_value` whose clamped discount would make the header total `< 0`, and reject a zero/negative grand total on a line-bearing invoice. (c) Guard `postCOGSEntry` on `totalAmount > 0`, or move the COGS posting after an explicit "invoice is saleable" assertion.

**Accounting reference.** IAS 2.9 / IAS 2.27 — cost of inventories is recognised as an expense in the period in which the related revenue is recognised. A sale with no revenue cannot simultaneously derecognise inventory at cost.

---

### SALES-007 — Soft-deleted invoices remain in every AR surface, producing an AR/GL divergence equal to the deleted invoice total

**Severity: HIGH** · **Status: NEW**
**Files:** `server/src/controllers/invoiceController.ts:753-754`; `server/src/utils/reportSql.ts:68-70`

**Description.** `deleteInvoice` performs an AUD-06 soft delete: the row survives with `status = 'Deleted'`, `deleted_at` stamped — but **`balance_amount` is left at its full value**. `AR_OUTSTANDING` excludes only `('Cancelled','Draft')`:

```ts
// reportSql.ts:68-70
export const AR_OUTSTANDING = (alias = ''): string =>
  `${p}balance_amount > 0 AND ${p}status NOT IN ('Cancelled', 'Draft')`;
```

No AR surface filters `deleted_at IS NULL` — `grep -rn "deleted_at" src/` shows the predicate exists only in `models/Invoice.ts:285, 331` (the invoice list/detail queries) and `models/Customer.ts:105, 127`, `models/Item.ts:115`. AR aging, top debtors, DSO, receivables summary, the dashboard AR cards and the `getGLReconciliation` AR pairing read `invoices` directly.

**Financial impact.** MEASURED (scenario K — a 400.00 invoice soft-deleted, GL lines voided as `deleteInvoice` does):
```
AR_OUTSTANDING rows            : { n: 9, total: 3056.00 }
GL 1100 (debit-normal, live)   : { net: 2656.00 }
=> getGLReconciliation AR delta = 3056.00 − 2656.00 = 400.00   == exactly the deleted invoice
```

So every deleted invoice permanently inflates AR aging buckets, DSO, `getTopDebtors`, the dashboard "receivables" card, and `getReceivablesSummary`, and shows up as a non-zero delta in the one report that is supposed to prove the two representations agree.

**Evidence.**
```ts
// invoiceController.ts:753-754 — balance_amount is NOT touched
db.prepare('UPDATE invoices SET status = ?, payment_status = ?, return_status = ?,
  deleted_from_status = ?, deleted_from_payment_status = ?, deleted_from_return_status = ?,
  deleted_at = ?, deleted_by = ? WHERE id = ?')
  .run('Deleted', 'Unpaid', 'None', …, new Date().toISOString(), userId, invoiceId);
```

**Fix.** Add `'Deleted'` to `AR_OUTSTANDING` (the status is the only signal every surface already selects), **and** filter `deleted_at IS NULL` inside `AR_OUTSTANDING` itself so a future soft-delete status cannot repeat the bug. Then re-examine every `netRevenueSum` consumer (`Reports.ts:122, 1083, 1091, 1098`), which filters only `NET_REVENUE_STATUS` = `status != 'Cancelled'` (`reportSql.ts:43-44`) and therefore also counts deleted invoices as revenue.

**Accounting reference.** IAS 1 — an asset (receivable) may not be recognised when the underlying transaction has been voided; deleted sales must not appear as receivables.

---

### SALES-008 — `INVOICE_SETTLEMENT` allocation ceiling ignores payments already received → overpayment accepted, leaving a credit balance in a debit-normal asset

**Severity: HIGH** · **Status: NEW** *(ownership note: the defect lives in `services/paymentValidation.ts`, which the payments-domain agent may also claim; it is reported here because `INVOICE_SETTLEMENT` is the invoice-settlement mode and the divergence surfaces in the sales AR derivation)*

**File:** `server/src/services/paymentValidation.ts:31-40`

```ts
function allocationCeiling(mode, invoice): AllocationCeiling {
  if (mode === 'REFUND') return null;
  if (mode === 'INVOICE_SETTLEMENT') {
    return { amount: parseCurrency(invoice.total_amount) - parseCurrency(invoice.returned_amount) };
  }
  return { amount: parseCurrency(invoice.balance_amount) };
}
```

The `INVOICE_SETTLEMENT` branch uses the invoice **gross total**, not the outstanding balance — so it ignores everything already collected.

**Financial impact.** MEASURED (scenario O — a 500.00 invoice, then a 200.00 partial payment, then a second 400.00 payment):
```
after payment 1 (200): { status:'Overdue', paid_amount:200, balance_amount:300 }
   GL: Dr 1000 200.00 / Cr 1100 200.00
payment 2 of 400 ACCEPTED (ceiling was 500, remaining was 300) → 100.00 OVERPAYMENT
   GL: Dr 1000 400.00 / Cr 1100 400.00
final: { paid_amount: 600, balance_amount: 0 }        ← clamped by ledgerUtils.ts:177
```

Consequences:
1. GL `1100` (asset, debit-normal) now carries a **credit balance** of 100.00 for that invoice. MEASURED: `GL 1100 debit-positive net` goes negative by exactly the overpayment.
2. `balance_amount` clamps to 0, so `AR_OUTSTANDING` (`balance_amount > 0`) **drops the invoice entirely** — the operational AR loses 300.00 while GL `1100` still holds the credit. That is a live, quantified AR-vs-GL break.
3. `payment_status` reports `'Overpaid'` **only if the return status is `'None'`** (`ledgerUtils.ts:220-221`); the Overdue branch at `:232-237` then overwrites it. MEASURED: status came back `'Overdue'`, not `'Overpaid'` — the overpayment is invisible in the status field.
4. Per `known-issues.md` item 6 the H9 policy routes overpayments to **`1110 Customer Credit`**; `postPaymentEntry` (`accountingService.ts:602-604`) *always* credits `1100`. So the overpayment sits in the wrong account relative to the documented model.

**Evidence.** Quoted ceiling; measured dump.

**Fix.** Change the `INVOICE_SETTLEMENT` ceiling to `max(0, balance_amount)` — the outstanding amount, which is what `ledgerUtils.ts:173-177` already computes. If overpayment is a legitimate business case, make it an explicit mode with an explicit posting (`Dr 1100 / Cr 1110`) rather than an accident of the general mode.

**Accounting reference.** IFRS 9 / IAS 32 — an overpayment is a financial **liability** to the customer, not a negative receivable. IAS 1.27.

---

### SALES-009 — Client-controlled `amount` override accepted on **packed** lines; `invoice_items` desynchronises from `unit_price × quantity`

**Severity: MEDIUM-HIGH** · **Status: NEW**
**Files:** `server/src/utils/currency.ts:62-65`, `:29-32`; `server/src/middleware/validation.ts:107`

**Description.** `decomposeLineAmount` honours an `amount` override whenever it is positive, with **no check that the item is a loose/amount-driven sale**:

```ts
// currency.ts:62-65
const override = parseCurrency(args.amount);
const gross = override > 0
  ? roundCurrency(override)
  : multiplyCurrency(args.quantity, args.unit_price);
```

The docstring at `currency.ts:29-32` states the override is for *"loose amount-driven lines"* and that the amount *"IS the business data (same trust level as qty/rate)"*. Only the **client** enforces the restriction:
```dart
// sales_invoice_form_page.dart:948
if (line.isLoose) 'amount': line.amount,
```
The server never checks `items.sale_type`. POS is accidentally protected (`validation.ts:177-184` declares item fields explicitly, so an unknown `amount` key is stripped); `POST /api/invoices` is not (`items: z.array(z.any())`).

**Financial impact.** MEASURED (scenario N — `sale_type = 'packed'`, quantity 1, `unit_price` 10, `amount` 999999):
```
stored line : { quantity:1, unit_price:10, amount:999999, net_amount:999999, tax_amount:0, sale_type:'packed' }
GL          : Dr 1100 999999.00 | Cr 4000 999999.00 | Dr 5000 50.00 | Cr 1200 50.00
```

The stored row is **internally inconsistent**: `unit_price × quantity = 10 ≠ amount = 999999`. Every downstream consumer that reads `unit_price` (invoice PDFs, `thermal_invoice_pdf.dart`, `return` mirroring at `invoiceReturnService.ts:296-306`) now disagrees with the money. Gross margin on that line reads as 999,999 − 50. The entry is balanced, so no invariant fires.

**Evidence.** Quoted above; measured dump.

**Fix.** Reject `amount` on a line whose `items.sale_type != 'loose'`, inside `InvoiceCreationService.create` (where `item_id` is available) — e.g. `if (item.amount !== undefined && itemRow.sale_type !== 'loose') throw`. Add the corresponding zod refinement. This closes the gap `known-issues.md` §"amount override" has left open on the loose-item design.

**Accounting reference.** IFRS 15 B31 — the transaction price is the amount the entity expects to be entitled to; it must be derived from the contract (price × quantity), not from an unrestricted client override on a quantity-based sale.

---

### SALES-010 — Backdating a sale into a CLOSED accounting period returns HTTP 500, not 409, and the create path has no pre-check

**Severity: MEDIUM** · **Status: NEW**
**Files:** `server/src/services/accountingService.ts:355-360`; `server/src/utils/businessRuleError.ts:32-47`; `server/src/services/InvoiceCreationService.ts` (absence)

**Description.** The invoice-**create** path is the only money-moving sales write with no closed-period pre-check. `grep -rn "assertPeriodNotClosed|getClosedPeriodCovering" src/` shows call sites in `invoiceController.ts:335, 433, 702, 940`, `posController.ts:212`, `invoiceReturnService.ts:640, 743`, `paymentWriterCore.ts:31`, `paymentController`, `expenseController`, `purchaseController`, `employeeController`, `models/Payment.ts`, `models/Expense.ts`, `models/OwnerCapital.ts`, `models/OwnerWithdrawal.ts`, `models/PurchaseReturn.ts` — **none in `InvoiceCreationService.ts`**, which therefore relies on `postEntry`'s internal period check firing *after* the invoice row and stock movements are written.

`postEntry` throws:
```
No open accounting period covers 2026-01-10. Open a period in accounting_periods before posting.
```
and `CLASSIFY_PATTERNS` (`businessRuleError.ts:32-47`) only matches `/inside closed accounting period/i` — **this message does not match**, so `handleBusinessError` falls through to **HTTP 500**.

**Financial impact.** No misstatement (the transaction rolls back atomically), but: the correct client-visible behaviour (409, as POS/update/delete/cancel all return) becomes a 500, so the Flutter client's "outcome unknown → retry" branch (`sales_invoice_form_page.dart:1093-1101`) fires on a request that *definitely* did not commit, and the user is told to retry a backdated sale that can never succeed.

**Evidence.** MEASURED (scenario G):
```
#### G: sale into CLOSED period threw:
  "No open accounting period covers 2026-01-10. Open a period in accounting_periods before posting."
  -> matches /inside closed accounting period/i ?  false
```

**Fix.** Add at the top of `InvoiceCreationService.create` (inside the transaction):
```ts
AccountingService.assertPeriodNotClosed(this.db, input.invoiceDate, `Invoice for ${input.customerId}`);
```
and add `[/No open accounting period covers/i, 409]` to `CLASSIFY_PATTERNS` so the message can never regress to 500.

**Accounting reference.** IAS 10 — events after the reporting period / closed-period discipline. Reporting into a closed period is a control failure regardless of balance.

---

### SALES-011 — Future-dated sales are accepted and auto-create an **open** accounting period

**Severity: MEDIUM** · **Status: NEW**
**Files:** `server/src/services/accountingService.ts:324-353`; `server/src/services/InvoiceCreationService.ts:61-65`, `:67-76`

**Description.** `postEntry` auto-creates a calendar-month period when the entry date falls outside every existing period:
```ts
// accountingService.ts:325-332
const periodName = input.entry_date.slice(0, 7);
db.prepare(`INSERT INTO accounting_periods (period_name, start_date, end_date, status)
            VALUES (?, ?, ?, 'open') ON CONFLICT(period_name) DO NOTHING`)
  .run(periodName, startDate, endDate);
```
`validateInput` (`InvoiceCreationService.ts:67-76`) checks only `customer_id`, `invoice_date` presence, `items.length`, and per-line `item_id`/`quantity`/`unit_price`. **There is no future-date check on any sales write.**

**Financial impact.** MEASURED (scenario H):
```
#### H: future-dated 2099-12-31 sale SUCCEEDED, invoice 6;
        auto-created period = {"period_name":"2099-12","status":"open",
                               "start_date":"2099-12-01","end_date":"2099-12-31"}
```

A typo in the date field (or a deliberate future-dated sale) silently **opens a new accounting period** and posts revenue, AR and COGS into it. Consequences: (a) the period calendar is polluted with future open periods; (b) `due_date` defaults to `invoice_date + 15 days` (`InvoiceCreationService.ts:61-65`), so the invoice is never `Overdue`; (c) `getAccountBalance(…, asOfDate)` filters `line_date <= asOfDate`, so the whole sale is invisible from today's balance sheet and trial balance while the stock has physically left.

**Evidence.** Quoted above; measured dump.

**Fix.** Reject `invoice_date > today` in `validateInput` (or allow it behind an explicit `allow_future_dating` flag for genuine forward invoicing). At minimum, warn and refuse the *auto-create* path for dates more than one period ahead of the latest open period, so a typo cannot mint a period.

**Accounting reference.** IAS 10.12 — the reporting period is the period presented; transactions dated outside it are either non-adjusting subsequent events or errors.

---

### SALES-012 — `PUT /api/invoices/:id` accepts a duplicate `invoice_no` (→ HTTP 500) and performs **no per-item validation at all**

**Severity: MEDIUM** · **Status: NEW**
**Files:** `server/src/controllers/invoiceController.ts:299`, `:317`, `:524-534`; `server/src/models/Invoice.ts:963-989`

**Description.** `updateInvoice` validates only `customer_id`, `invoice_date`, and `items.length`:
```ts
// invoiceController.ts:317-319
if (!customer_id || !invoice_date || !items || items.length === 0) {
  return res.status(400).json({ error: 'Customer, date, and items are required' });
}
```
There is **no per-item validation** — contrast `InvoiceCreationService.validateInput` (`:71-75`) and `Invoice.createInvoice` (`Invoice.ts:769-773`), both of which reject `quantity <= 0` and `unit_price < 0`. `createInvoiceItem` (`Invoice.ts:826-851`) validates nothing; it just calls `decomposeLineAmount` and inserts.

Consequences measured / traced:
* `quantity <= 0` → `StockMovement.consumeFromOldestBatches` throws a bare `Error` at `StockMovement.ts:822-824`, which matches no `CLASSIFY_PATTERNS` → **HTTP 500** instead of 400.
* `unit_price < 0` → a negative line amount → negative/zero `totalAmountNum` → the SALES-005 zero-total path.
* `invoice_no` is read at `:299` and written at `Invoice.ts:973` with **no uniqueness pre-check**, and `invoices.invoice_no` is `VARCHAR(50) UNIQUE`.

**Financial impact.** MEASURED (scenario J): writing a duplicate `invoice_no` throws `SQLITE_CONSTRAINT_UNIQUE`. Because `handleBusinessError` has no pattern for constraint violations, the client receives **HTTP 500**. Two invoices then share one `invoice_no`, which breaks `reverseStockForItems`'s `WHERE reference_docno = ?` lookups (`Invoice.ts:607-617`) and `getReturnHistory`'s join (`Invoice.ts:1371`) — the stock-reversal machinery is keyed on `reference_docno`, not on `invoice_id`.

**Evidence.** Quoted above; measured `SQLITE_CONSTRAINT_UNIQUE`.

**Fix.** (a) Call a shared `validateInvoiceItems(items)` from `InvoiceCreationService.validateInput`, `Invoice.createInvoice` **and** `invoiceController.updateInvoice` — one function, three callers. (b) Before `InvoiceModel.updateInvoice`, `SELECT id FROM invoices WHERE invoice_no = ? AND id <> ?` and 409 on a hit. (c) Map `SQLITE_CONSTRAINT_UNIQUE` to 409 in `classifyError`.

**Accounting reference.** Document completeness and uniqueness (ISA 240, ISA 500); a non-unique document reference breaks the audit trail.

---

### SALES-013 — `POST /api/invoices/:id/restore` has no closed-period guard, and re-consumes stock at *today's* FIFO layers while un-voiding the *original* COGS line

**Severity: MEDIUM** · **Status: NEW**

**Files:** `server/src/controllers/invoiceController.ts:789-918` (esp. `:809-848`, `:854-857`), `server/src/services/accountingService.ts:1443-1468`

**Description.** Three defects in the undo path.

1. **No closed-period guard.** `deleteInvoice` has one (`:702`) and `cancelInvoice` has one (`:940`); `restoreInvoice` (`:789-918`) has none. Sequence: delete in an open period → close the period → restore → `restoreJournalLinesByReference` un-voids lines dated **inside the closed period**. This is exactly the mutation `assertPeriodNotClosed` (`accountingService.ts:1015-1029`) exists to prevent, and `restoreJournalLinesByReference` deliberately does **not** re-check it — it is a raw `UPDATE` inside the service.
2. **Stale COGS cost.** Restore re-consumes FIFO at line `:823-828` and records new SALE movements, but **posts no COGS** — it only un-voids the old `Dr 5000 / Cr 1200` at their **original** layer cost (`:854`). `deleteInvoice` restored the batches (`:713`), so in the common case the same layers are consumed again and the cost matches. But any intervening purchase/receipt between delete and restore changes which layers are oldest, and then **GL `1200`/`5000` no longer equals the layer value relieved from `stock_batches`** — the exact divergence class `known-issues.md` §1 measured at −1,533.20, reintroduced by a different path.
3. **Asymmetric undo.** `deleteInvoice` sets `payment_allocations.amount = 0` (`:736`) and may void the payment's GL lines (`:740`) and delete the payment row (`:743`). `restoreInvoice` reverses **none** of that. It also leaves delete's `INVOICE_DELETE` ADJUSTMENT stock movements in place — correct for the ADJUSTMENT net-out, but it means `stock_movements` grows monotonically across every delete/restore cycle while the GL does not.

**Financial impact.** A GL-vs-layer inventory divergence equal to `|new FIFO cost − original FIFO cost| × quantity` (indeterminate, unbounded by the code); plus a closed-period mutation with no control.

**Evidence.**
```ts
// invoiceController.ts:809-848 — re-consumes stock, records movements, posts NOTHING
const consumption = InvoiceModel.consumeFromOldestBatches(item.item_id, warehouseId, item.quantity, db);
for (const entry of consumption) { StockMovementModel.recordMovement({ … movement_type:'SALE' … }); }
// :850-857 — restores the OLD posting instead of re-posting at the new cost
AccountingService.restoreJournalLinesByReference(db, 'INVOICE', invoiceId);
AccountingService.restoreJournalLinesByReference(db, 'INVOICE_RETURN', invoiceId, { owningInvoiceId: invoiceId });
```
```ts
// accountingService.ts:1450-1466 — raw UPDATE; no period check, no balance recomputation
UPDATE journal_lines SET voided = 0, voided_by = NULL, void_reason = NULL
WHERE reference_type = ? AND reference_id = ? AND voided = 1 …
```

**Fix.** (a) `AccountingService.assertPeriodNotClosed(db, invoice.invoice_date, …)` at the top of `restoreInvoice` — or add the check inside `restoreJournalLinesByReference` itself, which is the better home since that primitive is the authority. (b) Post COGS at the newly-consumed cost and void the un-voided original, exactly as `updateInvoice` does at `invoiceController.ts:578-604`, so the GL always equals the layer value. (c) Mirror `:736-747` in reverse.

**Accounting reference.** Perpetual inventory / FIFO integrity (IAS 2.23); period lock integrity (see SALES-010).

---

### SALES-014 — Cancelled invoices are terminal: no reinstate path exists

**Severity: LOW** · **Status: NEW** (design fact, not a defect in the code's own terms)

**Files:** `server/src/routes/invoices.ts:17-20`; `server/src/models/Invoice.ts:1088-1090`, `:695-700`; `server/src/controllers/invoiceController.ts:800`

**Description.** There is no route or service that moves an invoice out of `'Cancelled'`:
* `cancelInvoiceInternal` blocks a second cancel (`Invoice.ts:1088-1090`).
* `deleteInvoice` requires `status ∈ {Draft, Unpaid}` (`invoiceController.ts:695-700`) — a cancelled invoice is not deletable.
* `restoreInvoice` requires `deleted_at` set (`:800`) — a cancelled invoice is not soft-deleted.

So once cancelled, the only way back is to hand-edit the database. Meanwhile `updateInvoice` **does** accept a cancelled invoice (`invoiceController.ts:485-487` explicitly preserves `Cancelled` on edit) and will happily re-post revenue for it — `voidJournalLinesByReference` + `postInvoiceEntry` at `:578-595` with no status guard. That is the inconsistency: a cancelled invoice can be *edited into* an active sale while it cannot be *reinstated*.

**Financial impact.** No misstatement on its own, but the combination with SALES-005 means a cancelled invoice with payments can be re-armed by an edit.

**Fix.** Either add `POST /api/invoices/:id/reinstate` (reverse of `cancelInvoiceInternal`, keyed like `restoreInvoice`), or — cheaper and more defensible — have `updateInvoice` reject any invoice whose `status === 'Cancelled'`, which is what `deleteInvoice` effectively does.

---

### SALES-015 — Multi-warehouse sales are never split across warehouses

**Severity: MEDIUM** · **Status: NEW**
**Files:** `server/src/services/InvoiceCreationService.ts:180`; `server/src/models/Invoice.ts:537-588`

**Description.** One warehouse is resolved **per line** and only that warehouse is drawn down:
```ts
// InvoiceCreationService.ts:180
const warehouseId = item.warehouse_id || input.warehouseId
                 || InvoiceModel.findWarehouseForItem(this.db, item.item_id, item.quantity);
```
`findWarehouseForItem` returns a **single** id. When an explicit warehouse is given it validates, **warns, and proceeds anyway** on insufficiency:
```ts
// Invoice.ts:546-551
if (!balance || balance.quantity < requestedQty) {
  logger.warn(`Insufficient stock for item ${itemId} at warehouse ${explicitWarehouseId}: ` +
              `available=${balance?.quantity ?? 0}, requested=${requestedQty}. Proceeding anyway.`);
}
return explicitWarehouseId;
```
and when auto-selecting it warns and picks the single best warehouse:
```ts
// Invoice.ts:567-572
logger.warn(`No warehouse has sufficient sellable stock for item ${itemId}: ` +
            `best sellable=${best.sellable_qty}, requested=${requestedQty}. Using warehouse ${best.warehouse_id}.`);
```

**Financial impact.** MEASURED (scenario Q — item stocked WH-A = 3 @ 50 and WH-X = 5 @ 80; sale of 6 with explicit `warehouse_id = WH-A`):
```
#### Q THREW: I4: sellable stock 3, requested 6 (expired, halted, or location-blocked batches are excluded from sale)
```
The entire 6-unit sale is **refused** even though 8 units are on hand elsewhere, and the same 6 units would have succeeded from WH-X at a *different* cost (80 vs 50) — so the FIFO-cost that reaches the GL depends on which warehouse the operator happens to pick, not on which stock is actually cheapest to consume. With `warehouseId` supplied by POS (`posController.ts:244`, required at `:157-160`) this is the **only** behaviour POS has.

**Fix.** Either implement cross-warehouse line splitting (consume from the selected warehouse first, then spill to the next with sufficient sellable stock, producing one SALE movement + one COGS contribution per warehouse) or make the rejection an explicit 400 with the available quantities surfaced, rather than an opaque `SellableStockUnavailableError` naming one warehouse.

**Accounting reference.** IAS 2.23 — the cost of inventories is determined on a consistent basis. Warehouse-pinned sale costing is not the same basis as free-choice FIFO.

---

### SALES-016 — Quotation → sales order → invoice silently drops line tax (and discount) end-to-end

**Severity: HIGH** · **Status: NEW**
**Files:** `server/src/models/Quotation.ts:595-605`; `server/src/models/SalesOrder.ts:649-655`; `server/src/migrations/add-full-sales-cycle.sql`

**Description.** `quotation_items` **has** `tax_rate`, `discount_type`, `discount_value` (`Quotation.ts:39, 62`; schema `add-full-sales-cycle.sql:38-42`). `sales_order_items` **has none** — verified on the DB copy:
```sql
CREATE TABLE sales_order_items (
  id, so_id, item_id, quantity, delivered_quantity, unit_price, amount,   -- no tax, no discount
  …
);
```
`convertToSalesOrder` writes only those columns:
```ts
// Quotation.ts:595-605
const soItemStmt = db.prepare(`
  INSERT INTO sales_order_items (so_id, item_id, quantity, unit_price, amount)
  VALUES (?, ?, ?, ?, ?)`);
for (const item of quotation.items || []) { soItemStmt.run(salesOrderId, item.item_id, item.quantity, item.unit_price, item.amount); }
```
and `convertToInvoice` then hard-codes the discount off and omits tax:
```ts
// SalesOrder.ts:649-655
items: (salesOrder.items || []).map((item) => ({
  item_id: item.item_id, quantity: item.quantity, unit_price: item.unit_price,
  amount: item.amount, discount_type: 'none' as const,     // ← no tax_rate
})),
```

**Financial impact.** Tax negotiated and recorded on a quotation is **never** recognised: `invoice_items.tax_rate` is 0 → `getInvoiceTaxTotal` returns 0 → `postInvoiceEntry` takes the 2-line branch → **no `Cr 2100 Tax Payable` at all**. The invoice header total equals the quotation total (because `item.amount` is passed as the `amount` override, `currency.ts:62-65`), so the *arithmetic* reconciles while the *tax* silently disappears. Revenue is understated by the tax relative to a direct invoice of the same goods, and output tax liability is understated by 100% on the entire quotation-driven share of sales.

**Evidence.** Quoted above; the `sales_order_items` DDL was read from the `/tmp` DB copy.

**Fix.** Add `tax_rate DECIMAL(5,2) DEFAULT 0`, `discount_type VARCHAR(20) DEFAULT 'percentage'`, `discount_value DECIMAL(15,2) DEFAULT 0` to `sales_order_items` via a migration; backfill from `quotation_items` where `source_type = 'QUOTATION'`; carry them through `Quotation.convertToSalesOrder` and `SalesOrder.convertToInvoice`. Because `amount` is currently the override, `decomposeLineAmount` would otherwise treat the tax-inclusive quotation amount as the gross — the columns must land together.

**Accounting reference.** IAS 1 / IFRS 15 B5 — the transaction price (and therefore the tax base) is fixed at contract inception; a tax term cannot be dropped by a downstream system boundary.

---

### SALES-017 — SO→invoice conversion drops the due date, so converted invoices can never age

**Severity: MEDIUM** · **Status: NEW**
**Files:** `server/src/models/SalesOrder.ts:645`; `server/src/services/InvoiceCreationService.ts:61-65`, `:121`; `server/src/models/Invoice.ts:804`

**Description.**
```ts
// SalesOrder.ts:645
dueDate: invoiceData?.due_date ?? null,     // null, not undefined
```
```ts
// InvoiceCreationService.ts:121
const dueDate = input.dueDate === undefined ? defaultDueDate(input.invoiceDate) : input.dueDate;
```
`null !== undefined`, so the `+15 days` default is **skipped**, and `createInvoice` then writes `data.due_date || null` → `NULL` (`Invoice.ts:804`). The `POST /api/invoices` and POS paths pass `undefined` and get the default correctly.

**Financial impact.** Every sales-order-converted invoice has `due_date = NULL`. `updateInvoiceStatus` only computes `Overdue` when `invoice.due_date` is truthy (`ledgerUtils.ts:235`), and `AR_OUTSTANDING` buckets on `julianday(i.due_date)` (`Reports.ts:11-14`), where `NULL` yields `NULL` → every bucket `CASE` falls to `ELSE 0`. Result: the invoice is **excluded from every AR aging bucket** while still contributing its `balance_amount` to the `total_outstanding` and `totalReceivables` totals. AR aging totals therefore cannot be reconciled against their own buckets for any shop that sells via sales orders — the single largest receivables control.

**Evidence.** Quoted above.

**Fix.** `dueDate: invoiceData?.due_date ?? undefined` at `SalesOrder.ts:645`, or make `InvoiceCreationService.ts:121` treat `null` like `undefined` (`input.dueDate == null`). The second is better — it fixes every caller.

---

### SALES-018 — Non-numeric money fields are blocked only by accidental `NOT NULL` constraints, and surface as HTTP 500

**Severity: LOW** · **Status: NEW**
**Files:** `server/src/middleware/validation.ts:107`; `server/src/services/InvoiceCreationService.ts:71-75`

**Description.** `items: z.array(z.any())` performs no coercion, so `validateInput`'s comparisons see the raw JSON value. `!item.quantity || item.quantity <= 0` and `item.unit_price === undefined || item.unit_price < 0` both pass for a non-numeric value, because `NaN <= 0` and `NaN < 0` are both `false` and `"abc" !== undefined`.

**Evidence — MEASURED, and it fails safely:**
```
unit_price: "abc"  → NOT NULL constraint failed: invoice_items.amount
unit_price: null   → NOT NULL constraint failed: invoice_items.unit_price
```
Both roll the whole transaction back; **no partial write and no HTTP 201 with NULL money.** The accidental backstop is `invoice_items.amount NOT NULL` (`add-invoice-item-tax-columns.sql:5`) plus `invoice_items.unit_price NOT NULL` (base `init.sql`).

**Why it is still a finding.** `invoices.total_amount`, `paid_amount` and `balance_amount` are all **nullable** (`invoices` DDL: `DECIMAL(15,2) DEFAULT 0`, no `NOT NULL`, verified on the DB copy). The entire protection rests on one column of a *child* table. If a future migration relaxes `invoice_items.amount`, or a code path writes the invoice header before the items, `better-sqlite3` will bind `NaN` as SQL `NULL` (verified: `SELECT typeof(a)` returns `'null'`) and the exact SALES-005 failure reappears silently — revenue voided, nothing reposted, HTTP 201. The failure mode is currently unreachable; the *absence of a validation policy* is the defect.

**Fix.** Close it with the shared item schema recommended in SALES-003: `unit_price: z.number().min(0)`, `quantity: z.number().positive()`, and add `Number.isFinite()` assertions in `validateInput` so the guard is explicit rather than an emergent property of a child-table constraint.

---

### SALES-019 — POS split tender can create an unbounded AR credit sale on the single shared `WALK-IN` customer

**Severity: MEDIUM** · **Status: NEW**
**Files:** `server/src/controllers/posController.ts:28-43`, `:178`, `:188-190`, `:236-254`

**Description.** The presence of a `payments` array — **including an empty one** — selects the split-tender path, and that path drops the cash guard entirely:
```ts
// posController.ts:178, 188-192
const usesLegs = Array.isArray(body.payments);
const legs: PosPaymentLeg[] = usesLegs ? body.payments! : [{ amount: 0, payment_method: 'Cash' }];
if (!usesLegs) { /* cashReceived >= total guard lives HERE only */ }
```
`body.payments: []` therefore bypasses the guard: `legs = []` → `legsTotal = 0` (`InvoiceCreationService.ts:99-110`) → `balanceAmount = totalAmount` → `status = 'Unpaid'`.

The customer is the **single shared row** created by `ensureWalkinCustomer()`:
```ts
// posController.ts:28-43
SELECT id FROM customers WHERE customer_code = 'WALK-IN' LIMIT 1
…
INSERT INTO customers (customer_code, customer_name, is_active) VALUES ('WALK-IN', 'Walk-in Customer', 1)
```
and POS passes no `creditOffset` (`:236-254`), so store credit cannot be applied at the till.

**Financial impact.** Every charge-later POS sale (empty `payments`) accumulates on one customer id. `AR_OUTSTANDING` then reports a single "Walk-in Customer" row aggregating every shop's credit sales, and `Dr 1100` carries the matching balance with **no per-transaction counterparty** — the receivable is not collectible from anyone, yet it sits in AR aging, DSO and the dashboard indefinitely. There is no ceiling, no credit-limit check (`customers.credit_limit` exists — `add-customer-ar-fields.sql:5` — and is never consulted on this path), and no ageing write-off path.

**Evidence.** Quoted above; flow traced `posController.ts:236-254` → `InvoiceCreationService.ts:93-120`.

**Fix.** Require a non-empty `payments` array whenever the split path is chosen (or a `charge_later: true` flag with an explicit customer), refuse POS credit sales against `WALK-IN`, and either exclude `WALK-IN` from AR aging/receivables reporting or recognise it as a contra-receivable on its own reporting line.

**Accounting reference.** IFRS 9 (E3) — a receivable must be a contractual right to consideration from a real counterparty; an unidentifiable walk-in balance is not a collectible asset and fails the impairment model.

---

### SALES-020 — COGS accumulates unrounded per-layer products and rounds once at the end

**Severity: LOW** · **Status: NEW** *(the *class* is ALREADY-KNOWN at `integer-money-migration-plan.md:§3.4, §5.2, §7.3`; these specific sites are not listed there)*

**Files:** `server/src/services/InvoiceCreationService.ts:206`, `:214`; `server/src/controllers/invoiceController.ts:571`, `:601`

```ts
// InvoiceCreationService.ts:206 — raw float multiply, no roundCurrency per layer
cogsAmount += entry.consumed * entry.unitCost;
// :214 — one rounding for the whole invoice
if (cogsAmount > 0) AccountingService.postCOGSEntry(this.db, { …, cogsAmount: parseCurrency(cogsAmount), … });
```
```ts
// invoiceController.ts:571 / :601 — identical
updatedCogsTotal += entry.consumed * entry.unitCost;
… cogsAmount: parseCurrency(updatedCogsTotal) …
```

**Financial impact.** `stock_batches.unit_cost` is `DECIMAL(15,4)` (`add-batch-costing.sql:15`). A 4-dp layer cost of `33.3333` × 3 units gives `99.9999`; the layer is decremented by exactly 3, `stock_batches` value falls by `99.9999`, and GL `1200` is credited **100.00**. The 0.0001 residue is absorbed by the 4-dp column and excused by the tolerance class documented at `integer-money-migration-plan.md:§7.3`. It is *invisible today* and becomes a hard imbalance the moment `journal_lines` becomes integer minor units — which is exactly the `§10 R2` risk the plan raises, but at a site the plan does not name.

**Evidence.** Quoted above. Note this does **not** affect the sales entry's balance today, because `postEntry` re-rounds every leg and then compares integer minor units exactly — so the COGS entry is balanced *within itself*; the residue is between the GL and the layer, not inside the entry.

**Fix.** `cogsAmount = addCurrency(cogsAmount, multiplyCurrency(entry.consumed, entry.unitCost))` at both sites, so each layer's cost is committed to 2 dp before summation and GL `1200` foots exactly against `stock_batches`.

---

### SALES-021 — `InvoiceModel.createLedgerEntry` seeds the running balance without the `reversed_by IS NULL` filter (latent)

**Severity: LOW** · **Status: NEW** (masked today)

**Files:** `server/src/models/Invoice.ts:906-927` vs `server/src/utils/ledgerUtils.ts:28-33`

The two ledger writers disagree on which row is the chain predecessor:

```ts
// Invoice.ts:908-913  — NO reversed_by filter
SELECT balance FROM customer_ledger
WHERE customer_id = ? AND voided = 0
ORDER BY transaction_date DESC, id DESC LIMIT 1
```
```ts
// ledgerUtils.ts:28-33  — the filter IS present
SELECT balance FROM customer_ledger
WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL
  AND transaction_date <= ?
ORDER BY transaction_date DESC, id DESC LIMIT 1
```

`Invoice.ts`'s version picks the **newest** row regardless of position in `(transaction_date, id)` order. For a backdated invoice it therefore reads a *later* row's balance as its seed. **Currently masked**: every caller immediately calls `rebuildLedgerBalances` (`InvoiceCreationService.ts:248`, `Invoice.ts:1141`, `invoiceController.ts:422`), which rebuilds the whole chain in date order (`ledgerUtils.ts:263-282`) and overwrites the wrong value. `Invoice.ts:1011-1022` and `invoiceController.ts:609-611` are the only paths that do not — and both operate on balances already rebuilt.

**Failure mode if the rebuild is ever removed or skipped:** every `customer_ledger.balance` from the insert onward is wrong, and `getCustomerStatements` (which sums `debit`/`credit`, `Reports.ts:47-56`) would disagree with the stored chain — i.e. a statement that does not foot to its own closing balance. `integer-money-migration-plan.md:§3.2` already flags `customer_ledger.balance` as a derived, drift-prone column.

**Fix.** Delete `InvoiceModel.createLedgerEntry` and route `InvoiceCreationService.ts:212`, `:244` and `Invoice.ts:1129` through `ledgerUtils.createLedgerEntry`. One writer, one predecessor rule.

---

### SALES-022 — Stale documentation: `models/AGENTS.md` contradicts the return-ledger date actually written

**Severity: LOW (informational)** · **Status: NEW**

**Files:** `server/src/models/AGENTS.md` ("RETURN ledger entries must use `invoice.invoice_date` (not today's date)") vs `server/src/services/invoiceReturnService.ts:418-424` (writes `todayLocal()`).

The **code is correct and the doc is stale**: `ledgerUtils.createLedgerEntry` selects the predecessor *at or before* the insert position (`ledgerUtils.ts:30`) and then calls `rebuildLedgerBalances` (`:59`), which re-derives the entire chain in date order (`:263-282`) — so a backdated insert cannot corrupt the chain regardless of date choice. Flagged only so the next agent does not "fix" working code to match stale guidance.

---

## 8. EDGE CASE TABLE

`H` = Handled · `P` = Partial · `N` = Not handled · `U` = Undeterminable

| # | Module | Transaction | Edge case | Handled? | Evidence | Sev | Fix |
|---|---|---|---|---|---|---|---|
| 1 | Invoice create | POST /api/invoices | **zero quantity** | **H** | `InvoiceCreationService.ts:73` `if (!item.quantity \|\| item.quantity <= 0) throw`; mirrored `Invoice.ts:771`. `consumeFromOldestBatches` backstops at `StockMovement.ts:822-824` | — | — |
| 2 | Invoice create | POST /api/invoices | **negative quantity** | **H** | same two lines (`<= 0` covers negatives) | — | — |
| 3 | Invoice create | POST /api/invoices | **negative unit_price** | **H** | `InvoiceCreationService.ts:74`; `Invoice.ts:772` | — | — |
| 4 | **Invoice update** | PUT /api/invoices/:id | **zero / negative quantity** | **N** | `invoiceController.ts:317` validates only the envelope; no per-item check. `StockMovement.ts:823` throws a bare `Error` → no `CLASSIFY_PATTERNS` match → **HTTP 500** | Med | Share `validateInvoiceItems` with the create path (SALES-012) |
| 5 | **Invoice update** | PUT /api/invoices/:id | **negative unit_price** | **N** | `createInvoiceItem` (`Invoice.ts:826-851`) validates nothing → negative line amount → negative `totalAmountNum` → the SALES-005 void-without-repost path | High | Reject `unit_price < 0` before the void at `invoiceController.ts:578` |
| 6 | Line math | all | **zero / negative discount_value** | **H** | `currency.ts:68` gates on `discountValue > 0`; `:72` clamps `Math.min(discountAmount, gross)`; client clamps too (`invoice_calculations.dart:47-49, 116`) | — | — |
| 7 | Line math | all | **discount ≥ line total** (flat or % ≥ 100) | **N** | `currency.ts:72` → `net = 0`; `currency.ts:151` → header total `0`. MEASURED (scenario R): `Dr 5000 50 / Cr 1200 50` with **no 1100/4000/2100 line at all** | Med-High | SALES-006 |
| 8 | Tax | POST /api/pos/sale | **tax_rate > 100%** | **H** | `validation.ts:181` `z.number().min(0).max(100)` | — | — |
| 9 | Tax | POST /api/invoices | **tax_rate > 100%** | **N** | `validation.ts:107` `z.array(z.any())`; `InvoiceCreationService.ts:71-75` no tax check. MEASURED (D): `Cr 2100 1000` on `Cr 4000 200` | Med | SALES-003 |
| 10 | Tax | POST /api/invoices | **negative tax_rate** | **N** | No bound; `accountingService.ts:536` `if (taxAmount > 0)` sends a negative tax down the **no-tax** branch. MEASURED (E): `tax_amount = −100` stored, `Cr 4000 100`, **no 2100 line** | High | SALES-002 |
| 11 | Tax | all | **tax base excludes an invoice-scope discount** | **P** | `currency.ts:74-75` before `:145-151`. MEASURED: same 10% discount → tax **40.00** (invoice scope) vs **36.00** (item scope) | High | SALES-001 |
| 12 | Tax | all | **rounding** | **H** (as designed) | `roundCurrency` `currency.ts:8-11`, half-up via `Math.round`; per-line rounding means `Σ tax ≠ tax(Σ)` **by design** (`currency.ts:79-88`; `integer-money-migration-plan.md:§7.4`) | — | — |
| 13 | Rounding | all | **float money storage** | **P** | Declared `DECIMAL(15,2)`/`(15,4)`; MEASURED `journal_lines.debit` = `integer`×395 / **`real`×7**; `customer_ledger.balance` = `real`×12. `postEntry` balance check **is** exact integer minor units (`accountingService.ts:284-311` + `currency.ts:165-167`) — note `integer-money-migration-plan.md:316-317` is **stale** about the `>0.01` tolerance | Med | Execute the migration plan; fix the stale tolerance line |
| 14 | Numbering | POST /api/invoices | **same invoice_no twice** | **H** | `input.invoiceNo` is never set from any HTTP surface (`invoiceController.ts:210-239`, `posController.ts:236-254`, `SalesOrder.ts:637-656`); `generateDocNo` → `getNextSequenceNumber` is atomic (`utils/sequence.ts:10-22`) | — | — |
| 15 | **Invoice update** | PUT /api/invoices/:id | **duplicate invoice_no** | **N** | `invoiceController.ts:299` reads it, `Invoice.ts:973` writes it, no pre-check; `invoices.invoice_no UNIQUE`. MEASURED (J): `SQLITE_CONSTRAINT_UNIQUE` → **HTTP 500**. Breaks `reverseStockForItems`'s `reference_docno` lookups (`Invoice.ts:607-617`) | Med | SALES-012 |
| 16 | Idempotency | POST /api/invoices | **double submit** | **P** | Keyed: `invoiceController.ts:236-237` → `InvoiceCreationService.ts:124-130, 172-174`. But the key is **optional** — `normalizeIdempotencyKey` returns `null` when the header is absent (`idempotency.ts:51-59`) — and `assertNoActivePosting` (`accountingService.ts:1065`) is **not** called on invoices | Med | Require the header for `POST /api/invoices`; add `assertNoActivePosting` |
| 17 | Idempotency | POST /api/pos/sale | **double submit** | **P** | Keyed (`posController.ts:251-253`); client derives the key from the body hash (`pos_screen.dart:60-67`). Same optionality caveat | Med | as above |
| 18 | **Invoice update** | PUT /api/invoices/:id | **double submit of a payment** | **N** | `invoiceController.ts:445-465` uses `InvoiceModel.createPayment` directly, bypassing `PaymentRecordingService`'s `beginIdempotentWrite` (`:34-51`). Client sends no key on update (`sales_invoice_form_page.dart:1071-1076`) | **High** | SALES-004 |
| 19 | Period | POST /api/invoices | **backdated into a CLOSED period** | **P** | Blocked, but **HTTP 500**: no `assertPeriodNotClosed` in `InvoiceCreationService`; `accountingService.ts:355-360` throws a message `businessRuleError.ts:32-47` does not match. MEASURED (G) | Med | SALES-010 |
| 20 | Period | PUT /api/invoices/:id | **backdated / edit in a closed period** | **H** | `invoiceController.ts:335` → `assertPeriodNotClosed` → 409 via `invoiceController.ts:664-666` | — | — |
| 21 | Period | DELETE / PUT cancel | **closed period** | **H** | `invoiceController.ts:702`, `:940` → 409 (`:769-771`, `:977-979`) | — | — |
| 22 | Period | POST /api/pos/sale | **closed period** | **H** | `posController.ts:212-218` → 409 | — | — |
| 23 | Period | POST /api/invoices | **future-dated** | **N** | No future check anywhere. MEASURED (H): `2099-12-31` succeeded and **auto-created an open period** `2099-12` (`accountingService.ts:324-353`) | Med | SALES-011 |
| 24 | Payment | invoice settlement | **partial payment** | **H** | `paymentValidation.ts:64-84`; `PaymentRecordingService.recordCustomerPayment`; `ledgerUtils.calculateInvoiceBalance:144-185`. MEASURED (O): 200 of 500 → `Dr 1000 200 / Cr 1100 200`, `balance_amount = 300` | — | — |
| 25 | Payment | invoice settlement | **overpayment** | **N** | `paymentValidation.ts:36-40` ceiling = `total_amount − returned_amount`, ignoring prior payments. MEASURED (O): 200 then 400 on a 500 invoice → **accepted**, `paid_amount = 600`, GL `1100` credit of 100, `payment_status` reported `'Overdue'` not `'Overpaid'` | **High** | SALES-008 |
| 26 | Payment | invoice settlement | **unapplied payment** | **P** | A payment with no allocation credits `1100` in full (`postPaymentEntry`) while no `balance_amount` changes → AR representation diverges from GL by design until `allocateExistingPayment` (`PaymentRecordingService.ts:84-127`) | Med | Reconcile unapplied payments as a separate AR line |
| 27 | Return | POST /:id/return | **full return** | **H** | Over-return guard `invoiceReturnService.ts:319-327`; GL `postInvoiceReturnEntry` `:392-406` (Cr 1100 / Dr 4100 / Dr 2100); COGS reversal `:417-429`; `returned_amount`/`return_fee` sync `:430-433`; `updateInvoiceStatus` → `'Fully Returned'` (`ledgerUtils.ts:211-212`) | — | — |
| 28 | Return | POST /:id/return | **partial return** | **H** | `invoice_items.returned_qty` tracking (`invoiceReturnService.ts:355-358`); proportional batch restore `Invoice.ts:646-664`; `allocateHeaderDiscount` mirrors the sale-side discount on the return base (`invoiceReturnService.ts:304-308`) | — | — |
| 29 | Cancel | PUT /:id/cancel | **cancel-after-post** | **H** | `Invoice.ts:1091-1096` **paid lock** → 409; `:1097-1102` **returned lock** → 409; `:1120-1124` and `invoiceController.ts:726-728` **"no journal lines voided"** integrity guard; closed period `:940` | — | — |
| 30 | Edit | PUT /api/invoices/:id | **edit-after-finalize** | **P** | Closed period blocked (409, `:335`). But **payments and returns are NOT locked** on the update path (only `cancelInvoiceInternal` has those locks, `Invoice.ts:1091-1102`) — which is what enables SALES-005 (edit a paid invoice to zero) | **High** | SALES-005 |
| 31 | Void | PUT /:id/cancel | **void / reinstate** | **N** (reinstate) | Cancel is terminal: `Invoice.ts:1088` blocks re-cancel, `invoiceController.ts:695-700` blocks delete, `:800` blocks restore. No reinstate route in `routes/invoices.ts` | Low | SALES-014 |
| 32 | Restore | POST /:id/restore | **soft-delete → restore round trip** | **P** | GL is **un-voided, not re-created** (`invoiceController.ts:854-857`) → **no orphaned GL entries**, correct. But: **no closed-period guard**, **no COGS re-post at the new FIFO cost**, and the payment-allocation zeroing at `:736`/payment void at `:740` is **not reversed** | Med | SALES-013 |
| 33 | Warehouse | invoice create | **multi-warehouse sale** | **N** | One warehouse per line: `InvoiceCreationService.ts:180`; `Invoice.ts:537-588` returns a single id and only **warns** on insufficiency (`:546-551`, `:567-572`). MEASURED (Q): 6 units with WH-A=3 / WH-X=5 and `warehouse_id=WH-A` → `SellableStockUnavailableError: sellable stock 3, requested 6` | Med | SALES-015 |
| 34 | Warehouse | invoice create | **warehouse with insufficient stock, auto-select** | **H** (rejects) | `Invoice.ts:559-573` picks the best warehouse, then `consumeFromOldestBatches` throws `SellableStockUnavailableError` (`StockMovement.ts:859-866`) → 400 (`invoiceController.ts:254-256`) | — | — |
| 35 | Stock | invoice create | **sale when stock insufficient → negative inventory?** | **H** | Three independent guards: `StockMovement.ts:859-866` (availability), `:985-992` / `:1075-1082` (residual after layer walk), and the DB `CHECK (quantity >= 0)` on `stock_balances.quantity` (DDL verified). Negative inventory is **not reachable** | — | — |
| 36 | Stock | invoice create | **expired / halted / location-blocked stock** | **H** | `StockMovement.ts:1007`, `:1041-1047`, `:905-925` exclude `expiry_date < date('now')`, `halted`, and non-ACTIVE `status_override`. Client also blocks (`sales_invoice_form_page.dart:1013-1035`) | — | — |
| 37 | Concurrency | invoice create | **concurrent double-sell of the last unit** | **H** *(single process only)* | Single `new Database(...)` connection (`config/database.ts:33`), synchronous better-sqlite3, and the whole sale in one `db.transaction()` (`InvoiceCreationService.ts:123, 254`) → requests serialize; the second sees `quantity_remaining = 0`. **MEASURED (P):** 2 requests for 1 unit → `created=1 blocked=1`, `batch.quantity_remaining=0`, `stock_balances.quantity=0`. No `cluster` / `worker_threads` / multi-process config found. **Would break** if a second server process ever shares the file (WAL allows concurrent readers; the read-then-decrement in `consumeFromOldestBatches` is not atomic across connections) | — | Add `BEGIN IMMEDIATE` or a `busy_timeout`-guarded CAS update if multi-process is ever contemplated |
| 38 | Line math | invoice create | **client `amount` override on a packed line** | **N** | `currency.ts:62-65` has no `sale_type` check. MEASURED (N): packed item, qty 1, `unit_price` 10, `amount` 999999 → stored `unit_price` 10 / `amount` 999999; `Cr 4000 999999` vs `Dr 5000 50` | Med-High | SALES-009 |
| 39 | Ingress | invoice create | **non-numeric money field** | **P** (accidental guard) | `validation.ts:107` `z.array(z.any())`; `NaN <= 0` and `NaN < 0` are both false so `validateInput` passes. MEASURED: `"abc"` → `NOT NULL constraint failed: invoice_items.amount`; `null` → `NOT NULL constraint failed: invoice_items.unit_price`. Fails safely — but `invoices.total_amount/paid_amount/balance_amount` are all nullable, so the guard is one child-table constraint, not a policy | Low | SALES-018 |
| 40 | Chain | SO convert | **quotation tax dropped** | **N** | `sales_order_items` has no `tax_rate` column (DDL verified); `Quotation.ts:595-605` writes only 5 columns; `SalesOrder.ts:649-655` hard-codes `discount_type:'none'` and omits tax → `getInvoiceTaxTotal` = 0 → **no `Cr 2100`** | **High** | SALES-016 |
| 41 | Chain | SO convert | **due date dropped** | **N** | `SalesOrder.ts:645` passes `null`; `InvoiceCreationService.ts:121` defaults only on `undefined`; `Invoice.ts:804` writes `NULL`. Invoice then excluded from every AR aging bucket (`Reports.ts:11-14`, `julianday(NULL)` → `NULL` → `ELSE 0`) | Med | SALES-017 |
| 42 | AR | invoice delete | **soft-deleted invoice still counted as AR** | **N** | `invoiceController.ts:753-754` sets `status='Deleted'` but leaves `balance_amount`; `reportSql.ts:70` excludes only `('Cancelled','Draft')`. MEASURED (K): operational AR 3056.00 vs GL 1100 2656.00 → **delta = 400.00 = the deleted invoice** | **High** | SALES-007 |
| 43 | POS | POST /api/pos/sale | **split tender with `payments: []` → credit sale on WALK-IN** | **P** | `posController.ts:178` (`Array.isArray`), `:188-190` (`legs = []`), cash guard only in the `!usesLegs` branch; `ensureWalkinCustomer()` `:28-43` is one shared row; no `creditOffset`, no `credit_limit` check | Med | SALES-019 |
| 44 | POS | POST /api/pos/sale | **change amount carries float dust** | **P** | `posController.ts:193` `parseFloat(String(body.cash_received))` accepts `'100.005'`; `:108` `Math.max(0, cashReceived - cashLeg)` is a raw unrounded subtraction. Cosmetic — the recorded leg is `Math.min(cashReceived, total)` at `:199`. **ALREADY-KNOWN**: `integer-money-migration-plan.md:§3.3` lists `posController.ts:56/65/78/123` | Low | plan §6 Phase 3 step 3 |
| 45 | Balancing | all | **unbalanced journal entry** | **H — none exist** | `accountingService.ts:251-311`: ≥2 lines, non-negative, XOR, non-zero, account exists, **exact integer-minor-unit `Σdr === Σcr` (`:306`)**, open period. DB: `CHECK (debit = 0 OR credit = 0)` / `CHECK (debit >= 0 AND credit >= 0)`. MEASURED on the DB copy: `243283.8 / 243283.8`, **0** per-entry imbalances; every harness scenario balanced | — | — |
| 46 | Balancing | all | **balanced-but-wrong entries** | **N** | Every finding in §7 is balanced-but-wrong: zero-total void-without-repost (05), zero-value invoice with COGS (06), negative-tax revenue inflation (02), packed-line override (09). Invariant A (trial balance) **cannot** see any of them — `known-issues.md` §"Validating a guard" item 4 applies verbatim | High | Add an invariant: `Σ (Dr 1100) − Σ (Cr 1100)` per non-cancelled invoice must equal its `total_amount` |

---

## 9. SUMMARY

**22 findings: 0 CRITICAL · 7 HIGH · 9 MEDIUM · 6 LOW.**

The double-entry engine is genuinely strong. `postEntry` enforces exact integer-minor-unit balance with no epsilon, the DB has `CHECK` constraints on the line shape, all 19 typed entry points route through the single authority, and I could not construct a single unbalanced entry. Money storage is float-affinity and the integer migration is not done, but the *posting* path already normalises to minor units, so storage floatness does not currently produce an imbalance.

The damage is all in the **business layer that decides what to post**: five distinct paths reach a state where the entry is balanced but the *fact* is wrong — a void with no repost (SALES-005), a zero-value invoice that still relieves stock (SALES-006), revenue inflated by a swallowed negative tax (SALES-002), a client-overridden sale price on a quantity-based line (SALES-009), and a deleted invoice that stays in AR (SALES-007). **None is visible to the trial balance or to invariants A–E.** This is precisely the pattern `known-issues.md` §"Validating a guard" item 4 warns about: the suite asks "did anything previously asserted break?" and cannot ask "is the thing I care about correct?"

The single highest-leverage change is a **shared, typed invoice-item schema + validator** applied at `validation.ts`, `InvoiceCreationService.validateInput`, `Invoice.createInvoice` and `invoiceController.updateInvoice`. It closes SALES-002, SALES-003, SALES-009, SALES-012, SALES-018 and half of SALES-015 in one commit, and makes the update path validate what the create path already validates.

The next highest-leverage change is one new invariant: **per non-cancelled invoice, `Σ live journal_lines on 1100` must equal `invoices.total_amount`.** That single assertion catches SALES-002, SALES-005, SALES-006, SALES-007 and SALES-009 — none of which the current nine invariants can see.