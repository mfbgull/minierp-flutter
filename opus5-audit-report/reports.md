# AUDIT: REPORTING · GLOBAL SEARCH · DUPLICATED BUSINESS LOGIC

Read-only. No files modified. All line numbers verified against source. All numeric scenarios below were computed by querying the live DB read-only (`erp.db?mode=ro&immutable=1`) — they are actual current values, not hypotheticals.

**Correction to a premise:** `global-search-spec.md` is **10,601 words**, not 94,000. I read the security/correctness-relevant sections in full (§4.5, §4.8, §4.10, §4.11, §6, §10, §12).

**Live DB scale (for right-sizing recommendations):** customers 11, suppliers 1, items 13, invoices 5, invoice_items 5, purchase_orders 3, quotations 0, sales_orders 0, payments 9, expenses 1, warehouses 1, employees 0, productions 0, boms 0, stock_movements 94, stock_batches 5, journal_lines 108, journal_entries 39, custom_reports 5, **users 1 (admin)**.

---

## PART A — DELIVERABLE 1: REPORT INVENTORY AND DATA SOURCES

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Reports.ts` exports **33 functions** (lines 1209–1219). `reportsController.ts` wraps **28**. `routes/reports.ts` exposes only **16**.

| Report (Reports.ts) | Lines | Data source (tables) | Routed? |
|---|---|---|---|
| getARAgingReport | 5–29 | `invoices.balance_amount` + customers | yes |
| getCustomerStatements | 32–80 | `invoices` (total/paid/balance) | yes |
| getTopDebtors | 83–97 | `invoices.balance_amount` | yes |
| getDSOMetric | 100–114 | `invoices.total_amount`, `balance_amount` | yes |
| getReceivablesSummary | 117–231 | `invoices.balance_amount` | yes |
| getSalesSummary | 233–267 | `invoices` | **no — dead** |
| getSalesByCustomer | 270–284 | `invoices` | **no — dead** |
| getSalesByItem | 287–296 | **`invoice_items.amount`** | **no — dead** |
| getStockValuationReport | 299–365 | `stock_batches` + `items` fallback | **no — dead** |
| getInventoryMovementReport | 368–400 | `stock_movements` (LIMIT 500) | **no — dead** |
| getSupplierAnalysis | 403–423 | `purchase_orders` + `purchase_order_items` | **no — dead** |
| getBatchTraceability | ~425–473 | `stock_movements`, `stock_batches` | yes |
| getAPAgingReport | 475–503 | **`purchase_orders.balance_amount`** | yes |
| getAPSummary | 505–520 | **`po.total_cost` − `SUM(payments.amount)`** | **no — dead** |
| getProfitLossReport | 522–559 | `invoices`, `stock_movements`, `expenses` | yes |
| getBalanceSheet | 561–714 | `stock_batches`, `items`, `invoices`, GL cash, `supplier_ledger`, `settings`, `expenses` | yes |
| getIncomeStatement | 716–731 | delegates to P&L | yes |
| getTrialBalance | 733–773 | `AccountingService.getAllAccountBalances` (**both** GL tables) | yes |
| getGeneralLedger | 775–779 | **`customer_ledger`** (mislabelled) | yes |
| getCashFlow | 781–810 | `cashService.collectFlows` | yes |
| getTaxSummary | 812–816 | **`invoice_items.amount * tax_rate/100`** | yes |
| getDailySales / getMonthlySales | 818–828 | `invoices.total_amount` | **no — dead** |
| getGrossProfit | 830–834 | `invoices`, `stock_movements` | **no — dead** |
| getStockLevelReport | 836–870 | **`stock_balances.quantity`** | **no — dead** |
| getLowStockReport | 872–901 | `stock_balances` | **no — dead** |
| getPurchaseSummary | 903–949 | `purchase_orders` | **no — dead** |
| getProductionEfficiency | 951–984 | `productions` | **no — dead** |
| getBOMUsageReport | 993–1028 | `boms`, `bom_items` | **no — dead** |
| getCustomerOutstanding | 1030–1037 | `invoices` | **no — dead** |
| getSupplierOutstanding | 1039–1045 | **`SUM(po.total_amount)` gross** | **no — dead** |
| getCashReconciliation / save | 1072–1179 | `cashService` + `cash_reconciliations` | yes |
| getExpenseReport | 1181–1207 | `expenses` | **no — dead** |

**~17 of 33 report functions are unreachable dead code** — the surviving half of the "remove 22 duplicate report screens" refactor (FACT 9). They still contain divergent formulas that will be resurrected the moment someone adds a route.

---

## PART A — DELIVERABLE 2: CONCEPT → IMPLEMENTATION DIVERGENCE TABLE

**This is the core deliverable.** All paths are under `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/`.

### (a) Invoice line amount — `invoice_items.amount`: **4 implementations, 3 different meanings**

| # | file:line | Formula | Semantics |
|---|---|---|---|
| 1 | `server/src/models/Invoice.ts:732` | `multiplyCurrency(qty, unit_price)` | **GROSS** (no discount, no tax) |
| 2 | `server/src/models/MobileInvoice.ts:238` | `qty * unit_price` | **GROSS** |
| 3 | `server/src/models/SalesOrder.ts:681-685` | copies `sales_order_items.amount` | depends on SO origin |
| 4 | `server/src/models/Quotation.ts:627-641` → SO:585 → invoice | `round(qty*price*(1−disc%)*(1+tax%),2)` | **NET of discount, INCLUSIVE of tax** |

```ts
// Quotation.ts:627-641  — NET + TAX
private static calculateLineAmount(item: CreateQuotationItemDTO): number {
  const baseAmount = item.quantity * item.unit_price;
  let afterDiscount: number;
  if (item.discount_type === 'percentage')  afterDiscount = baseAmount * (1 - (item.discount_value || 0) / 100);
  else if (item.discount_type === 'amount') afterDiscount = baseAmount - (item.discount_value || 0);
  else                                      afterDiscount = baseAmount;
  const afterTax = afterDiscount * (1 + (item.tax_rate || 0) / 100);
  return Math.round(afterTax * 100) / 100;
}
```
```ts
// Invoice.ts:731-733  — GROSS
static createInvoiceItem(db, invoiceId, item): void {
  const amount = multiplyCurrency(item.quantity, item.unit_price);
```
**Verdict: DISAGREE.** `SUM(invoice_items.amount)` is not a meaningful quantity across the table. Confirms FACT 6 at code level.

### (b) Invoice header total — `invoices.total_amount`: **4 implementations**

| # | file:line | Formula |
|---|---|---|
| 1 | `server/src/models/Invoice.ts:695` | `data.total_amount ?? 0` — **client-supplied, never recomputed or validated** |
| 2 | `server/src/models/MobileInvoice.ts:205-210` | `Σ(qty*price) + Σ(qty*price*tax/100)` — server-computed, **ignores discounts** |
| 3 | `server/src/models/SalesOrder.ts:672` | copies `sales_orders.total_amount` |
| 4 | `server/src/controllers/posController.ts` | `total` computed in-controller |

**Verdict: DISAGREE.** Path 1 is the primary web/desktop path and trusts the client for the single most important money figure in the system. This is the root cause of FACT 4 (header ≠ Σ lines).

### (c) Outstanding / receivable: **6 implementations, 4 different status sets**

| # | file:line | Formula | Status filter |
|---|---|---|---|
| 1 | `Reports.ts:5-29` getARAgingReport | `SUM(i.balance_amount)` | `Unpaid, Partially Paid, Overdue` |
| 2 | `Reports.ts:117-231` getReceivablesSummary | `SUM(balance_amount)` | `Unpaid, Partially Paid, Overdue, **Sent**` |
| 3 | `Reports.ts:612-617` getBalanceSheet AR | `SUM(balance_amount)` | `Unpaid, Partially Paid, Overdue, **Sent**` |
| 4 | `Reports.ts:83-97` getTopDebtors | `SUM(balance_amount)` | `Unpaid, Partially Paid, Overdue` |
| 5 | `Reports.ts:42` getCustomerStatements | `SUM(i.balance_amount)` | **none** (incl. Cancelled) |
| 6 | `utils/ledgerUtils.ts:44-58` updateCustomerBalance | `SUM(balance_amount)` → writes `customers.current_balance` | `Unpaid, Partially Paid, Overdue` |
| 7 | GL account `1100` (`accounts_receivable`) | `Σ(debit−credit)` from `journal_lines` | `voided = 0` |

**Verdict: DISAGREE.** AR aging and the balance sheet use different status sets, so the aging report's grand total never equals the balance sheet's AR line whenever a `Sent` invoice exists. #5 counts Cancelled invoices. #7 is currently **−180** (a negative asset) while #1–#6 are all **0**.

### (d) Customer balance: **5 implementations — currently 3 different values for the same customer**

| # | file:line | Formula | Live value (customer 1) |
|---|---|---|---|
| 1 | `customers.current_balance` written by `ledgerUtils.ts:44-58` and `Customer.ts:337-344` | `SUM(inv.balance_amount)` over 3 statuses | **0** |
| 2 | `customers.credit_balance` | separate stored column | **600** |
| 3 | `SUM(customer_ledger.debit − credit)` | running-sum recomputation | **−180** |
| 4 | last `customer_ledger.balance` (`ledgerUtils.ts:11-16`) | stored running balance | **−180** |
| 5 | GL account `1100` | `journal_lines` | **−180** |

**Verdict: DISAGREE.** `Customer.getBalance` (`Customer.ts:328-330`) returns #1 (= 0); the customer ledger screen shows #4 (= −180); global search shows #1 (`searchService.ts:230` `COALESCE(current_balance,0)`); `credit_balance` (600) is displayed nowhere in these reports. Confirms FACT 3. Note #3 and #4 now agree — `rebuildLedgerBalances` has been run — but see REP-14 for why they can drift again.

### (e) Supplier balance / AP: **6 implementations**

| # | file:line | Formula |
|---|---|---|
| 1 | `suppliers.current_balance` written at `Payment.ts:391`, `SupplierLedger.ts:98` | last running balance |
| 2 | `Supplier.ts:224-228` | `COALESCE(sl.balance,0)` where `sl.id = MAX(id)` per supplier |
| 3 | `Reports.ts:632-644` balance-sheet AP | same MAX(id) pattern **+ `sl1.balance > 0`** and `transaction_date <= ?` |
| 4 | `Dashboard.ts:632-644` | same MAX(id) pattern (no `> 0` filter) |
| 5 | `Reports.ts:475-503` getAPAgingReport | `po.balance_amount`, status `Approved, Received, Partial` |
| 6 | `Reports.ts:505-520` getAPSummary | `SUM(po.total_cost − COALESCE(p.paid_amount,0))` |
| 7 | `Reports.ts:1039-1045` getSupplierOutstanding | `SUM(po.total_amount)` — **gross PO value, not outstanding at all** |
| 8 | GL account `2000` (`accounts_payable`) | **zero activity — nothing ever posts to it** |

**Verdict: DISAGREE.** #3 adds `balance > 0`, silently dropping supplier credit balances (prepayments) from liabilities — asymmetric with #4 which the dashboard uses, so dashboard AP ≠ balance-sheet AP the moment any supplier is in credit. #6 reads `total_cost` while #5/#7 read `total_amount` / `balance_amount` — three different PO money columns. #7 is simply wrong. #8 is dead.

### (f) Stock quantity on hand: **5 implementations**

| # | file:line | Formula |
|---|---|---|
| 1 | `items.current_stock` — read at `Dashboard.ts:107,155-158,163`, `searchService.ts:324`, `Item.ts:134`, `MobileInvoice.ts:121` | denormalised column |
| 2 | `SUM(stock_balances.quantity)` — `Reports.ts:840`, `inventoryController.ts:148`, `Invoice.ts:512,528` | per item-warehouse |
| 3 | `SUM(stock_batches.quantity_remaining)` — `Reports.ts:299-365` | batch level |
| 4 | `SUM(stock_movements.quantity)` — implicit in P&L/COGS | movement ledger |
| 5 | `stock_balances.quantity` single-warehouse — `posController.ts:88` | per warehouse |

Writers of #1 (`UPDATE items SET current_stock = (SELECT SUM(quantity) FROM stock_balances WHERE item_id=?)`) appear in **6 separate places**: `PhysicalCount.ts:317-320`, `Production.ts:258,369`, `Purchase.ts:228`, `PurchaseOrder.ts:836-844`, `PurchaseReturn.ts:388`, plus a boot-time resync at `config/database.ts:266-268`.

**Verdict: currently AGREE, structurally fragile.** Live check across all 13 items: the only item with stock (WIDGET-A) reads 11 from all four of `items.current_stock`, `SUM(stock_balances)`, `SUM(stock_batches.quantity_remaining)`, `SUM(stock_movements.quantity)`. They agree only because `config/database.ts:266` re-syncs #1 from #2 on **every server boot** — masking any drift accumulated during a run. Two operational hazards remain: `Reports.ts:845` `Math.max(0, row.total_stock)` **hides negative stock**, and `inventoryController.ts:146` explicitly comments that `stock_balances` is authoritative "instead of item.current_stock" while the dashboard and global search still read `current_stock`.

### (g) Inventory valuation: **3 implementations**

| # | file:line | Formula | Live value |
|---|---|---|---|
| 1 | `Reports.ts:595-610` (balance sheet), `Dashboard.ts:102-114`, `Reports.ts:299-365` | `SUM(sb.quantity_remaining * sb.unit_cost)` + legacy fallback | **26,000** |
| 2 | `config/database.ts:1752` (seeded custom report) | `ROUND(current_stock * standard_cost, 2)` | **26,000** |
| 3 | GL account `1200` `Inventory Asset` | `journal_lines` + `journal_entries` UNION | **−69,015** |

**Verdict: #1 and #2 AGREE today (coincidence: batch `unit_cost` == `standard_cost`). #3 DISAGREES by 95,015.** The balance sheet reports inventory as a +26,000 asset while the trial balance — shown two screens away — reports the same inventory as a **−69,015 negative asset**.

### (h) COGS / cost: **3 implementations**

```sql
-- Reports.ts:534-545 (getProfitLossReport)  and identical at Dashboard.ts:139-148, Reports.ts:830 (getGrossProfit)
SELECT COALESCE(ABS(SUM(sm.quantity * sm.unit_cost)),0) FROM stock_movements sm
WHERE sm.movement_date BETWEEN ? AND ?
  AND ( sm.movement_type = 'SALE'
        OR (sm.movement_type = 'ADJUSTMENT' AND sm.reference_doctype IN ('RETURN','INVOICE_DELETE','INVOICE_UPDATE')) )
```
```sql
-- Reports.ts:662-671 (getBalanceSheet cogsYTD)  — NOTE 'OUT'
SELECT COALESCE(ABS(SUM(quantity * unit_cost)),0) FROM stock_movements
WHERE movement_date <= ?
  AND ( movement_type IN ('SALE','OUT')                       -- <-- extra type
        OR (movement_type = 'ADJUSTMENT' AND reference_doctype IN ('RETURN','INVOICE_DELETE','INVOICE_UPDATE')) )
```
Third: GL account `5000` Cost of Goods Sold = `journal_lines` D 2,765 / C 500 → **+2,265**.

**Verdict: DISAGREE in code; numerically equal today.** P&L COGS = balance-sheet cogsYTD = **2,000** right now only because the live data contains zero `'OUT'` movements (`movement_type` distribution: ADJUSTMENT 43, PURCHASE 31, SALE 20). The GL says 2,265. Any code path that starts writing `movement_type='OUT'` immediately desynchronises P&L net income from balance-sheet equity.

### (i) Gross profit: **2 implementations — AGREE**

`Reports.ts:830-834` getGrossProfit and `Reports.ts:522-559` getProfitLossReport use byte-identical revenue and COGS SQL. `Dashboard.ts:218` `totalProfit = salesRevenue − cogs` uses the same pair. `getIncomeStatement` (716-731) delegates to `getProfitLossReport`. **Verdict: AGREE. Do not change.**

### (j) Total payments received: **2 implementations — the `payments` vs `payment_allocations` split (Task 3)**

```ts
// utils/ledgerUtils.ts:67-71  — calculateInvoiceBalance: ALLOCATIONS
const paidResult = db.prepare(`
  SELECT COALESCE(SUM(amount), 0) as total_paid
  FROM payment_allocations
  WHERE invoice_id = ?
`).get(invoiceId);
```
```ts
// models/Reports.ts:509 and :515  — getAPSummary: RAW PAYMENTS
LEFT JOIN (SELECT purchase_order_id, SUM(amount) as paid_amount
           FROM payments GROUP BY purchase_order_id) p ON po.id = p.purchase_order_id
```
Also on `payment_allocations`: `Invoice.ts:821-822`, `Payment.ts:525-526`. Also on raw `payments`: `cashService.ts:80-101`, `Purchase.ts:289,374`, `PurchaseOrder.ts:246,325`, `searchService.ts:545`.

**Verdict: DISAGREE — yes, this exact divergence exists.** `getAPSummary` groups raw `payments` by `purchase_order_id`, so a payment covering three POs counts against only whichever `purchase_order_id` the header carries, while the AR side (`calculateInvoiceBalance`) correctly uses the allocation table. There is **no `payment_allocations` equivalent for the AP side** — supplier payments have no allocation table at all.

### (k) Cash on hand: **2 implementations — differ by Rs 23,100 right now**

| # | file:line | Formula | Live value |
|---|---|---|---|
| 1 | `Reports.ts:622-625` (balance sheet) → `accountingService.ts:109-160` | GL balance of the single `cash` account, `journal_lines ∪ journal_entries`, `voided=0` | **+3,000** |
| 2 | `services/cashService.ts:60-134` `collectFlows` → dashboard cash card + cash reconciliation + cash-flow report | `opening_balances` + Σ`payments`(customer) − Σ`payments`(supplier) − Σ`expenses` − Σ`salary_payments` − Σ`purchases.total_cost`, across **5** accounts | **−20,100** |

```ts
// Reports.ts:619-625 — the comment claims "'cash' or 'bank'" but only 'cash' is read
const cashAccount = AccountingService.getAccountByTextCode(db, 'cash');
const cashBalance = cashAccount
  ? AccountingService.getAccountBalance(db, cashAccount.id, asOfDate).balance
  : 0;
```
**Verdict: DISAGREE by 23,100.** Same user, same app, same day: dashboard card says cash is **−20,100**; balance sheet says cash is **+3,000**. The balance sheet also silently omits Bank / Easypaisa / JazzCash / UPaisa from assets entirely (only `text_code = 'cash'` is read), despite the code comment at line 575 claiming otherwise.

### (l) Revenue for a period: **3 formulas across 10+ sites**

| Formula | Sites |
|---|---|
| `SUM(total_amount − COALESCE(returned_amount,0))` **AND `status != 'Cancelled'`** — correct | `Reports.ts:532` (P&L), `Reports.ts:659` (BS), `Reports.ts:831` (gross profit), `Dashboard.ts:120,172,179,480,489,605` |
| `SUM(total_amount)` — **no Cancelled exclusion, no returns** | `Reports.ts:107` (DSO), `Reports.ts:144`, `Reports.ts:274`, `Reports.ts:820` (daily sales), `Reports.ts:826` (monthly sales), `Invoice.ts:989,1057`, `salesController.ts:456` |
| `SUM(total_amount)` **with** `status != 'Cancelled'` but **no returns** | `Dashboard.ts:294` (getTopCustomers), `Dashboard.ts:583` |
| `SUM(invoice_items.amount)` | `Reports.ts:291` (getSalesByItem) |

**Verdict: DISAGREE.** Concrete: invoice 5 (`INV-2026-462699`, total 600, status `Returned`) is **excluded** from P&L revenue (2,400) but **included** in DSO's credit-sales denominator and in `getDailySales`/`getMonthlySales` (3,000). Daily-sales totals overstate revenue by exactly the returned amount.

---

## PART A FINDINGS

### REP-01 · P0 · Balance sheet does not balance and is not GL-derived
`server/src/models/Reports.ts:561-714`

Assets, liabilities and equity are each pulled from a **different unrelated source** — `stock_batches`, `invoices`, one GL account, `supplier_ledger`, `settings`, `expenses`, `stock_movements` — so `balanced` at line 684 is an accidental identity check between quantities with no accounting relationship:
```ts
const totalAssets = inventoryValue + ar.total + cashBalance;      // 680
const totalLiabAndEquity = totalLiabilities + totalEquity;        // 683
const balanced = Math.abs(totalAssets - totalLiabAndEquity) < 0.01; // 684
```
**Live failure, as of 2026-12-31:** inventory 26,000 + AR 0 + cash 3,000 = **assets 29,000**. AP 500 + equity (0 opening RE + 300 net income) = **liabilities+equity 800**. `balanced = false`; **out of balance by Rs 28,200 (3,625%)**. `lib/features/reports/balance_sheet_report_screen.dart:217-229` renders this as a red **"Out of Balance"** badge.

Root cause is FACT 2: Accounts Payable, Owner's Equity, Retained Earnings, Operating Expenses and Tax Payable have **zero GL activity** — purchases (109,150 of PURCHASE movements), supplier payments and expenses post nothing. Equity is therefore never a balancing plug.

**Fix:** derive all three sections from `getAllAccountBalances` (grouped by `chart_of_accounts.type`) and add the missing posting helpers for purchases/AP/expenses/opening equity. **Migration: yes** — backfill journal entries for historical purchases/expenses, or set a GL cutover date and label pre-cutover balance sheets as unavailable.
**Do not show this report to a business owner until fixed.**

### REP-02 · P0 · Trial balance is arithmetically sound but economically absurd
`server/src/models/Reports.ts:733-773` → `server/src/services/accountingService.ts:109-160`

The implementation is **correct** (see CORRECT list): it UNIONs `journal_lines` with legacy `journal_entries` via `text_code` and excludes `voided = 1`. Live output:

| code | account | normal | debit | credit | balance |
|---|---|---|---|---|---|
| 1000 | Cash | debit | 3,000.00 | 0.00 | **3,000.00** |
| 1100 | Accounts Receivable | debit | 3,420.00 | 3,600.00 | **−180.00** |
| 1200 | Inventory Asset | debit | 1,750.00 | 70,765.00 | **−69,015.00** |
| 4000 | Sales Revenue | credit | 0.00 | 3,420.00 | 3,420.00 |
| 4100 | Sales Returns | debit | 600.00 | 0.00 | 600.00 |
| 5000 | Cost of Goods Sold | debit | 2,765.00 | 500.00 | 2,265.00 |
| 7100 | Inventory Correction | debit | 0.00 | 1,250.00 | **−1,250.00** |
| 7200 | Inventory Shrinkage | debit | 68,000.00 | 0.00 | 68,000.00 |
| | **TOTALS** | | **79,535.00** | **79,535.00** | balanced = **true** |

`Cash` has **3,000 debits and zero credits** — no cash has ever left the GL. `Inventory Asset` is **−69,015** while the balance sheet says +26,000. Accounts Payable, Owner's Equity, Retained Earnings, Operating Expenses, Tax Payable are absent (zero activity). The screen shows a green "✓ Balanced" tick (`trial_balance_report_screen.dart:118`) on a trial balance where two of three asset accounts are negative.
**Fix:** the report is fine; the *posting* is broken. Same remediation as REP-01. **Migration: yes.**

### REP-03 · P0 · Two irreconcilable definitions of "cash on hand" (Rs 23,100 apart)
`server/src/models/Reports.ts:622-625` vs `server/src/services/cashService.ts:60-134`

See concept (k). Balance sheet **+3,000** (GL, `cash` account only) vs dashboard/reconciliation/cash-flow **−20,100** (transactional, 5 accounts, includes `opening_balances` seed of 5,000 and the 500 direct-purchase outflow at `cashService.ts:126-131`). The cash-reconciliation report will tell a shopkeeper the till should hold **negative twenty thousand rupees**.
**Fix:** make `cashService` the single source of truth and have the balance sheet consume it (summing all 5 accounts), or post every cash movement to the GL and delete `cashService`'s independent aggregation. Do not keep both. **Migration: yes** if GL becomes canonical.

### REP-04 · P1 · `getGeneralLedger` returns the customer subledger
`server/src/models/Reports.ts:775-779`
```ts
return db.prepare(`SELECT * FROM customer_ledger WHERE transaction_date BETWEEN ? AND ?`).all(startDate, endDate);
```
Routed at `routes/reports.ts:24` and shown as "General Ledger" in `lib/features/reports/general_ledger_report_screen.dart`. It contains no account codes, no purchases, no expenses, no supplier activity. An accountant asked for the GL will receive AR transactions only and conclude the business has no expenses.
**Fix:** rewrite against `journal_lines JOIN chart_of_accounts` with `voided = 0`; rename the existing query to `getCustomerLedgerReport`. **Migration: no.**

### REP-05 · P1 · P&L and balance-sheet COGS use different movement-type sets
`server/src/models/Reports.ts:534-545` (`movement_type = 'SALE'`) vs `Reports.ts:662-671` (`movement_type IN ('SALE','OUT')`)

Quoted side by side under concept (h). **Currently numerically equal (both 2,000) because no `'OUT'` rows exist** — a latent divergence, not an active one. The instant an `'OUT'` movement is written, P&L net income and balance-sheet equity diverge by that cost with no error surfaced.
**Fix:** extract one `cogsForPeriod(db, from, to)` helper and call it from `getProfitLossReport`, `getGrossProfit`, `getBalanceSheet` and `Dashboard.ts:139`. **Migration: no.**

### REP-06 · P1 · Profit uses `stock_movements.unit_cost`, which was historically the sale price
`server/src/models/Reports.ts:526-530` (the code's own admission):
> historical SALE movements may have `unit_cost = sale_price`

This answers Task 7 directly: profit is **not** GL-derived (`revenue − COGS` from accounts) and is **not** recomputed from `items.standard_cost` either. It is recomputed from whatever was stamped into `stock_movements.unit_cost` at sale time. Current writers are correct — `posController.ts` and `Invoice.consumeFromOldestBatches` pass the **actual batch cost** (`entry.unitCost`), which is the right FIFO behaviour. But `MobileInvoice.ts:249` passes `unit_cost: item.unit_price` — **the selling price**:
```ts
StockMovementModel.recordMovement({
  ..., movement_type: 'SALE', quantity: -item.quantity,
  unit_cost: item.unit_price,        // <-- SELLING price recorded as cost
```
**Live failure:** any invoice created through the mobile path yields COGS = revenue for those lines, i.e. **zero gross profit** on them, while the same sale entered on desktop shows the true margin. Live SALE movements total −3,330 at "cost" against 2,400 of revenue — cost exceeding revenue is the signature of this bug.
**Fix:** `MobileInvoice.ts` must use `consumeFromOldestBatches` like the other two paths. **Migration: yes** to correct historical SALE rows, or accept a documented cutover date.

### REP-07 · P1 · Reports that count Cancelled and double-count Returned revenue
- `Reports.ts:818-822` `getDailySales`, `Reports.ts:824-828` `getMonthlySales`: `SUM(total_amount)`, **no** `status != 'Cancelled'`, **no** `returned_amount`.
- `Reports.ts:100-114` `getDSOMetric` line 107: `SELECT SUM(total_amount) FROM invoices WHERE invoice_date BETWEEN ? AND ?` — same, and this is the **denominator of a routed KPI** (`routes/reports.ts:16`).
- `Reports.ts:32-80` `getCustomerStatements`: no status filter at all.
- `Reports.ts:287-296` `getSalesByItem`: `SUM(ii.amount)` — mixes the three units from concept (a).
- `Reports.ts:812-816` `getTaxSummary`: `SUM(amount * tax_rate / 100)`. For quotation-sourced lines `amount` **already includes tax**, so tax is computed on a tax-inclusive base — **over-stating tax by `tax_rate²/100`%**. Routed at `routes/reports.ts:26`; this feeds a filing.

**Live failure:** invoice 5 is `Returned` (total 600, fully returned). P&L revenue = 2,400 (correct). `getDailySales` = 3,000. DSO's credit-sales base = 3,000. Same period, 25% overstatement.
**Fix:** one shared `netRevenueExpr` SQL fragment applied to all revenue sites; for tax, compute from a tax-exclusive base column. **Migration: yes** for tax — add `invoice_items.tax_amount` and `invoice_items.net_amount` and backfill, because the current single `amount` column cannot express both meanings.

### REP-08 · P1 · `getCustomerStatements`: two branches with different join semantics + broken footing
`server/src/models/Reports.ts:32-80`
```ts
// 71-74
if (startDate && endDate) {
  query += customerId ? ` AND i.invoice_date BETWEEN ? AND ?` : ` AND (i.invoice_date BETWEEN ? AND ? OR i.id IS NULL)`;
```
The `customerId` branch has a `WHERE c.id = ?` (line 50) so the date filter lands in **WHERE** — which annihilates the LEFT JOIN, returning **zero rows** for a customer with no invoices in range. The all-customers branch has **no WHERE at all** (query ends at the LEFT JOIN, line 66), so the fragment is appended to the **ON clause** — correctly preserving customers with no invoices. Selecting a specific customer can therefore show "no data" for a customer the all-customers view lists with zeros.

Separately: `opening_balance` is selected (39, 56) but **never added** — `closing_balance` = `SUM(i.balance_amount)` (42, 59). And `total_debits`/`total_credits` are period-filtered while `balance_amount` is a current-state column with no date filter, so **opening + debits − credits ≠ closing** by construction. Returns are ignored, so a fully returned invoice still contributes debits.
**Fix:** rebuild from `customer_ledger` with an explicit opening-balance carry-forward. **Migration: no.**

### REP-09 · P2 · `getInventoryMovementReport` summary counts rows, not quantities, over a truncated set
`server/src/models/Reports.ts:368-400`. `LIMIT 500` at line 379, then the summary at 389-397 is computed **from the limited rows**, and `totalInbound`/`totalOutbound` are row **COUNTs** rather than `SUM(quantity)`; `netMovement = totalInbound − totalOutbound` is therefore a count difference presented as a quantity. On the 501st movement the totals silently stop growing. Unrouted (dead) today. **Fix:** compute the summary in a separate un-limited aggregate query using `SUM(quantity)`.

### REP-10 · P2 · `getSupplierAnalysis` row multiplication + hardcoded metric
`server/src/models/Reports.ts:403-423`: `COUNT(po.id) as total_orders` with `LEFT JOIN purchase_order_items` — a 5-line PO counts as 5 orders and `SUM(po.total_amount)` is multiplied 5×. Line 420: `on_time_delivery_rate: 100` hardcoded. Also `Reports.ts:951-984` `getProductionEfficiency` hardcodes `scrapped_quantity: 0` and `status: 'Completed'`. Unrouted. **Fix:** `COUNT(DISTINCT po.id)` and aggregate items in a subquery, or delete these functions.

### REP-11 · P2 · Wrong/ignored parameters and mislabelled columns
- `Reports.ts:1030-1037` `getCustomerOutstanding` accepts `asOfDate` and **never uses it**.
- `Reports.ts:1039-1045` `getSupplierOutstanding` returns `SUM(po.total_amount)` labelled `outstanding` — gross purchase value.
- `Reports.ts:855` aliases `standard_cost` as `standard_selling_price`.
- `Reports.ts:845` `Math.max(0, row.total_stock)` **masks negative stock** — the single most important inventory red flag is suppressed.
All unrouted. **Fix:** delete the dead functions; keep and fix line 845 before routing `getStockLevelReport`.

### REP-12 · P2 · UTC "today" defaults in report controllers
`server/src/controllers/reportsController.ts` lines 10, 20, 84, 246, 261, 284 all use `new Date().toISOString().split('T')[0]` (UTC). The codebase elsewhere deliberately uses local dates — `Dashboard.ts:259` and `Dashboard.ts:308-310` both call `date('now','localtime')` with an explicit comment explaining why. For a UTC+5 user between 00:00 and 05:00 local, the AR aging / AP aging / AR summary / trial balance / balance sheet / cash reconciliation defaults resolve to **yesterday**, silently excluding today's documents. Also `utils/ledgerUtils.ts:27` writes `transaction_date` with `date('now')` (UTC) while the client sends local ISO dates elsewhere — mixing two calendars in one column.
**Fix:** one `todayLocal(db)` helper (the `Dashboard.ts:308` implementation) used everywhere. **Migration: no.**

### REP-13 · P2 · Date-range semantics — VERIFIED SAFE (BETWEEN does not drop the last day)
Task 6 resolved definitively rather than left UNVERIFIED. Live schema + data check: `invoices.invoice_date`, `stock_movements.movement_date`, `expenses.expense_date`, `customer_ledger.transaction_date`, `supplier_ledger.transaction_date`, `purchase_orders.po_date`, `payments.payment_date`, `journal_lines.line_date` are all declared `DATE` and **stored as TEXT of length exactly 10** (`'2026-08-14'`) with **zero** time components anywhere. `BETWEEN ? AND ?` with `YYYY-MM-DD` bounds is therefore **inclusive of the last day**. No report loses its end date.

**But the same pattern on a DATETIME column is broken, in a duplicate function:**
```ts
// services/activityLogger.ts:327-330  — BUG: created_at is DATETIME 'YYYY-MM-DD HH:MM:SS'
if (startDate && endDate) { dateFilter = ' WHERE created_at BETWEEN ? AND ?'; params.push(startDate, endDate); }
```
```ts
// models/ActivityLog.ts:252-258  — CORRECT duplicate of the same function
if (startDate && endDate) {
  dateFilter = ' WHERE created_at >= ? AND created_at < ?';
  params.push(localDateToUtcBound(startDate, false), localDateToUtcBound(endDate, true));
}
```
Both are named `getStats(startDate?, endDate?)`. `controllers/activityLogController.ts:69` calls the **fixed** one; the buggy one survives as the exported `getActivityStats` at `activityLogger.ts:399`. Anything wired to that export loses the entire last day. **Fix:** delete `activityLogger.getStats` and its re-export. **Migration: no.**

### REP-14 · P2 · Ledger running balances rebuilt in insertion order, not date order
`server/src/utils/ledgerUtils.ts:128-143` (`rebuildLedgerBalances`) and `server/src/models/SupplierLedger.ts:81-98` both iterate `ORDER BY id ASC`. A back-dated document inserted today gets the newest `id`, so it lands at the **end** of the running-balance chain regardless of its `transaction_date`. `getStatement` (`Customer.ts:311`) then reads those balances `ORDER BY transaction_date ASC` — producing a statement whose printed running balance jumps non-monotonically. Also `Customer.ts:315-322`: opening balance is `ORDER BY transaction_date DESC LIMIT 1`, which for same-day entries picks an arbitrary row (no `id` tiebreaker). **Fix:** `ORDER BY transaction_date ASC, id ASC` in both rebuilds and in the opening-balance lookup. **Migration: yes** — re-run both rebuilds after the fix.

### REP-15 · P2 · Reports read orphaned rows (FACT 5 confirmed live)
Verified now: **12** `journal_lines` rows with `voided = 0` and `reference_type='INVOICE'` point at invoice IDs that no longer exist; **3** `customer_ledger` INVOICE rows reference deleted `invoice_no`s. These orphans are inside the trial balance (they are part of the 79,535) and inside the customer ledger. Invoice deletion clears `payment_allocations` (`Invoice.ts:899`) and `payments` (`Invoice.ts:906`) but does not void the corresponding journal lines — `accountingService.voidJournalLinesByReference` (787-800) exists and is simply not called on this path. **Fix:** call it inside the invoice-delete transaction; add a FK-integrity check. **Migration: yes** — void the 12 existing orphans.

### REP-16 · P2 · Global date range silently skips three report screens
`lib/features/reports/report_providers.dart:399-406` — `_reportRangePairs` lists only DSO, cash-flow, P&L, statements and activity log. `applyGlobalReportRange` (409-414) therefore does **not** update `reportGeneralLedgerFrom/ToDateProvider` (277-282), `reportIncomeStatementFrom/ToDateProvider` (297-302) or `reportTaxSummaryFrom/ToDateProvider` (317-322). A user sets the dashboard range to Q1, opens P&L (Q1) then Income Statement — **the same numbers by delegation** — and sees a different period with no indication why. **Fix:** add the three missing pairs.

### REP-17 · P2 · Client calls two endpoints that do not exist
`lib/core/api/endpoints.dart:82-83` define `/reports/expiry` and `/dashboard/expiry-alerts`; `lib/data/repositories/report_repository.dart:242-266` calls both. Server-side grep across all of `server/src/` for `reports/expiry`, `'/expiry'` and `expiry-alerts` returns **nothing** — the only `expiry` routes are `stockBatches.ts:62-85` (batch expiry_date update). The expiry report screen and the dashboard expiry-alerts feed are permanently 404. **Fix:** implement the two handlers or remove the screens.

---

## PART B — CUSTOM REPORTS ENGINE

### REP-18 / SEC · **P0 · SQL injection via `computedColumns[].expression` — arbitrary read of any table including `users`**

**Injection point** — `server/src/services/reportQueryEngine.ts:283-288` and `301-308`:
```ts
if (isComputed) {
  const cc = config.computedColumns!.find(c => c.name === col.field)!;
  items.push(`${cc.expression} AS ${alias}`);          // 285 — RAW interpolation
} else {
  items.push(`${ctx.primaryTableAlias}.${quoteIdentifier(col.field)} AS ${alias}`);
}
```
```ts
// 303-306 — second raw interpolation, for ORDER BY-referenced computed columns
for (const cc of config.computedColumns) {
  if (sortFieldNames.has(cc.name) && !config.columns.some(c => c.field === cc.name)) {
    items.push(`${cc.expression} AS ${quoteIdentifier(cc.name)}`);
```
The assembled string is executed at `reportQueryEngine.ts:238` — `db.prepare(sql).all(...params)`.

**Validation gap 1** — `server/src/controllers/customReportsController.ts:25-91` `validateReportConfig` checks `entity`, `columns[].field`, `sort[].field`, `sort[].direction` and `filters[].field` against `entity.fields`, but reads **only `cc.name`** from `computedColumns` (lines 52-53, 68-69). **`cc.expression` is never inspected.**

**Validation gap 2** — `customReportsController.ts:300-307` bypasses validation entirely for inline configs:
```ts
} else if (inlineConfig) {
  config = inlineConfig as ReportConfig;      // 300-301 — no validateReportConfig call
} else { ... }
const result = executeReport(config);          // 307
```

**Authorisation** — `server/src/routes/customReports.ts:33`:
```ts
router.post('/run', requirePermission('reports', 'create'), customReportsController.runReport);
```
Any user holding `reports:create` — an ordinary report-builder permission — can execute this.

**Exploit (read):** `POST /api/reports/custom/run` with
`{"config":{"entity":"invoices","columns":[{"field":"x"}],"computedColumns":[{"name":"x","expression":"(SELECT password_hash FROM users LIMIT 1)","type":"string"}]}}`
returns the admin password hash. This **completely bypasses** the 19-entity allowlist in `server/src/services/entityRegistry.ts` (which correctly excludes `users`) and reaches `users`, `employees.salary`, `settings`, and every other table.

**Impact bounded — writes are NOT possible.** Verified from better-sqlite3 v12.6.2's own C++ source:
- `node_modules/better-sqlite3/src/objects/statement.cpp:126` → `"The supplied SQL string contains more than one statement"` — statement stacking (`; DROP TABLE`) is rejected at prepare time.
- The injection point is a scalar expression inside a `SELECT` list, so only `SELECT` sub-expressions are reachable.
- Grepped for `db.function(` and `loadExtension` across `server/src`: **no user-defined functions and no extension loading are registered** (only `db.pragma` calls), ruling out UDF/extension escalation.

So this is **arbitrary read, not arbitrary write** — still P0 for credential disclosure.

**Correctness risk too:** an unvalidated expression can silently produce wrong aggregates (e.g. `SUM(x)` without a matching GROUP BY) or crash the endpoint with a 400 that reveals SQL fragments via `res.status(400).json({ error: error.message })` at line 314.

**Note the feature is genuinely used** — 2 of the 5 live `custom_reports` rows carry expressions (`SUM(total_amount)`, `COUNT(id)`, `ROUND(current_stock * standard_cost, 2)`), seeded at `config/database.ts:1729,1752`. A fix must preserve them.

**Fix:** (1) allowlist expressions structurally — accept only `{fn: 'SUM'|'COUNT'|'AVG'|'MIN'|'MAX'|'ROUND', args: [allowlisted field | number]}` and emit the SQL server-side, never accepting a raw string; (2) call `validateReportConfig(config)` in the `inlineConfig` branch at `customReportsController.ts:300`; (3) return a generic error message. **Migration: yes** — the 5 seeded templates must be rewritten into the structured form.

### REP-19 · P2 · System templates are a stored-payload vector
`server/src/models/CustomReport.ts:135-158` `createTemplate` writes rows with `user_id = SYSTEM_USER_ID = 0`, and `getTemplates()` (127-133) returns them to **every** user. `customReportsController.ts:357-386` `createTemplate` is gated only by `reports:create` with no ownership or admin check. A user with `reports:create` can store a malicious `computedColumns` payload as a system template; any other user who loads it into the builder and clicks Run executes it inline (which, per REP-18 gap 2, skips validation) under **their own** credentials.
Positive: `CustomReport.findById(id, userId)` (47-52) **is** correctly user-scoped.
**Fix:** require an admin role for `createTemplate`; validate on read as well as write.

### What is correct in the engine — do not change
- `reportQueryEngine.ts:125-127` `quoteIdentifier` — proper `"` doubling; every field/table/alias goes through it.
- `buildFilterExpression` (401-522) — **all filter values are bound**, never interpolated (`ctx.paramValues.push(value)`).
- Relative-date tokens (78-90 fixed allowlist; 100-106 regex-validated `^([+-]\d+)\s+(day|days|month|months|year|years)$`) — safe by construction.
- `entityRegistry.ts` — a genuine 19-entity allowlist that correctly excludes `users`. Sound design; it is only bypassed via REP-18.
- `buildHavingClause` (541-551) sets `havingMode = true`, which skips the `validFieldNames` check at 418-422 — but the field still passes through `quoteIdentifier`, so it can reference an arbitrary **column name** and cannot inject. Not a vulnerability; worth tightening for error quality.

---

## PART C — GLOBAL SEARCH

### SRCH-01 · P1 · Missing bind parameter — search 500s for every non-admin user
`server/src/services/searchService.ts:155-163`
```ts
const role = db.prepare('SELECT role_id FROM users WHERE id = ?').get(userId) as { role_id: number } | undefined;
if (!role?.role_id) return new Set();

const perms = db.prepare(`
  SELECT p.module, p.action
  FROM role_permissions rp
  JOIN permissions p ON p.id = rp.permission_id
  WHERE rp.role_id = ?
`).all() as { module: string; action: string }[];      // <-- no argument for the ?
```
`.all()` supplies nothing for `?`. better-sqlite3 throws `RangeError: Too few parameter values were provided` (verified: `node_modules/better-sqlite3/src/util/binder.cpp:19`). Admin returns early at 149-153 and never reaches this line.

`searchController.ts:29-34` swallows it in a bare `catch { res.status(500).json({error:'Search failed'}) }`, so the server log shows nothing and Flutter renders the generic error state (`global_search_dialog.dart:150-157`).

**Currently latent:** the live DB has exactly **one** user (`id=1, username=admin, role='admin', role_id=1`), so nothing is broken today. The first non-admin user created makes Ctrl+K fail 100% of the time for them.

**Why CI is green:** `server/src/__tests__/search.test.ts` forces `UPDATE users SET role_id = 1, role = 'admin' WHERE username = 'admin'` in its fixture and every request uses the admin cookie. The non-admin branch is never executed.
**Fix:** `.all(role.role_id)`. Add a non-admin fixture. **Migration: no.**

### SRCH-02 · P1 · Results are not permission-filtered — only *actions* are
`server/src/services/searchService.ts:819-848` runs all 13 entity searches plus pages unconditionally:
```ts
const results: SearchResult[] = [
  ...searchCustomers(trimmed, limit, userId),
  ...searchSuppliers(trimmed, limit, userId),
  ...searchProducts(trimmed, limit, userId),
  ...searchInvoices(trimmed, limit, userId),
  ... 9 more ...
];
```
`routes/search.ts` applies **only** `authenticateToken` — no `requirePermission`. `filterActions` (172-199) gates *buttons*; nothing gates *rows*.

Any authenticated user — including one with zero module permissions — can read, via Ctrl+K:
- invoice numbers, customer names and **`total_amount`** (`searchInvoices`, 370-418);
- **payment amounts and methods** (`searchPayments`, 537-582 — subtitle interpolates `Rs. ${amount}`);
- **expense descriptions, categories and amounts** (`searchExpenses`, 584-616);
- employee names, codes, departments and phone numbers (`searchEmployees`, 655-698);
- customer and supplier balances (`searchCustomers:230` `COALESCE(current_balance,0)`, `searchSuppliers:277`).

Mitigation: `searchEmployees` does **not** select `salary` (the field exists in `entityRegistry.ts:311-331` but is not exposed here).

**Spec delta:** the implementation faithfully matches spec §4.10, which is scoped to actions ("*For each result's actions*") and never requires row-level filtering — **the gap originates in the spec**, which simultaneously states "Do NOT bypass existing permissions or business rules" (§12). Acceptance criterion "Actions are filtered by user permissions" is met; there is no criterion for results.
**Fix:** skip each `searchXxx` call unless the user holds `<module>:read`. **Migration: no.**

### SRCH-03 · P2 · `filterActions` is O(rows) × 2 queries — N+1
`server/src/services/searchService.ts:172-180`: `filterActions` calls `getUserPermissions(userId)` **per row** (each of which runs 1–2 queries), then runs `SELECT role FROM users WHERE id = ?` **again** at line 178. With `limit=50` across 13 entities that is up to 650 rows × ~3 queries ≈ **~2,000 queries per keystroke**. Spec §6 explicitly requires "N+1 prevention: single query per entity type". **Fix:** resolve permissions once in `search()` and pass the `Set` down.

### SRCH-04 · P2 · Cancelled invoices and inactive warehouses/employees are searchable
`searchInvoices` (370-418) has **no status filter** — Cancelled invoices appear as normal results, and their contextual actions are gated only by `ENTITY_ACTIONS.invoice` `condition` closures. `searchWarehouses` (620-653) and `searchEmployees` (655-698) both **SELECT `is_active`** and never filter on it — terminated employees remain findable. By contrast customers, suppliers and items correctly filter `is_active = 1` (e.g. `searchCustomers` line ~233).
**Fix:** add `is_active = 1` to warehouses/employees; add `status != 'Cancelled'` to invoices or badge them in the subtitle.

### SRCH-05 · P3 · Dead ranking helpers; result cap 5× the spec
`searchService.ts:205-222` define `rankClause(field, alias='name')` and `rankParams(prefix)` — **never called** (ranking is duplicated inline in each search function instead; `alias` is unused). Also: spec §6 fixes "Max results per entity type: 10" and "Total max results ~130", but `searchController.ts:8` allows `Math.min(Number(req.query.limit ?? 10), 50)` and `routes/search.ts` validates `limit` up to 50 → **13 × 50 = 650** results and a large payload. **Fix:** delete the dead helpers; cap `limit` at 10 per spec.

### SRCH-06 · Contextual actions — VERIFIED SAFE, do not change
Task 10, the security question: **no palette action mutates data.**
```dart
// lib/features/search/search_navigation.dart:30-38
void executeSearchAction(BuildContext context, SearchResult result, SearchAction action) {
  final router = GoRouter.of(context);
  Navigator.of(context, rootNavigator: true).pop();
  router.go(resolveSearchPath(result, action));
}
```
Every action — Customer → Create invoice / Add payment, Product → Sell / Purchase / Stock history, Invoice → Return / Payment / Print — is pure `router.go` navigation to an existing screen, which then enforces its own permissions server-side on submit. No POST/PATCH/DELETE is reachable from the palette.

Permission checking is **server-side at generation time**, not client-side hiding: `searchService.ts:172-199` `filterActions` removes actions whose `ENTITY_ACTIONS[...].permission` the user lacks and evaluates status `condition` closures, before the response is serialised. `lib/features/search/search_action_panel.dart:103-116` renders whatever the server returned and contains **no client-side permission logic** — the correct arrangement.

One gap: `PAGE_ACTIONS` (`searchService.ts:115-136`) declares `permission` only on `reports` (126) and the create/receive/make entries (130-135). Plain module pages (`inventory`, `customers`, `sales`, `payments`, `expenses`, `hr`, `activity_log`, `settings`) carry no permission, so they appear for everyone — cosmetic only, since each route guards itself, but it leaks the module list.

### SRCH-07 · P3 · LIKE performance and the index question (Task 11)

**Measured shape per keystroke** (parsed from `searchService.ts`):

| function | `LIKE ?` predicates | tables touched |
|---|---|---|
| searchCustomers | 8 | customers |
| searchSuppliers | 8 | suppliers |
| searchProducts | 7 | items |
| searchInvoices | 5 | invoices ⋈ customers |
| searchQuotations | 3 | quotations ⋈ customers |
| searchPayments | 2 | payments ⋈ customers ⋈ suppliers |
| searchExpenses | 2 | expenses |
| searchWarehouses | 2 | warehouses |
| searchEmployees | 6 | employees |
| searchBOMs | 2 | bom_items ⋈ boms ⋈ items |
| searchPurchaseOrders | 1 | purchase_orders ⋈ suppliers |
| searchSalesOrders | 1 | sales_orders ⋈ customers |
| searchProductions | 1 | productions ⋈ items |
| searchPages | 0 | users |
| **total** | **48** | **14 queries** |

**The `add-search-indexes.sql` indexes are unusable — confirmed.** All ~25 are plain B-trees on single text columns (`idx_customers_name ON customers(customer_name)` etc.). SQLite can only use a B-tree for `LIKE` when the pattern has a **literal prefix**; `'%term%'` has none, so every one of these queries is a full table scan. Two of thirteen searches bind a prefix pattern and *could* use an index — `searchPurchaseOrders:429` (`WHERE po.po_no LIKE ?` bound with `qs = 'term%'`) — but even that requires `case_sensitive_like=ON` or a `COLLATE NOCASE` index to qualify, and neither is set. Note also the **inconsistency**: `searchSalesOrders:507` uses the identical `WHERE so.so_no LIKE ?` shape but binds `q = '%term%'`, so PO search matches prefixes only while SO search matches substrings — the same UX gesture behaves differently on two adjacent entities.

The indexes are not harmless: they add write amplification on every insert/update to 15 hot tables for zero read benefit. The `ORDER BY CASE WHEN ... LIKE ?` ranking also forces a sort of the full candidate set.

**Recommendation for this system's actual scale — keep LIKE. Do not adopt FTS5 or trigram.** Total searchable rows across all 14 tables is **~45** (customers 11, items 13, invoices 5, payments 9, POs 3, expenses 1, warehouses 1; quotations/SOs/employees/productions/BOMs are all 0). A full scan of a 45-row database is sub-millisecond; 14 such scans plus ranking will complete far inside the 200 ms budget of spec §6. Spec §12 already says "Do NOT introduce FTS5 — simple LIKE is sufficient", and that judgement is correct here. Concretely:
1. **Drop the unusable indexes** (or keep only the prefix-capable `po_no` one, with `COLLATE NOCASE`) — they are pure write overhead. Keep any that also serve non-search queries.
2. **Fix SRCH-03 first** — ~2,000 permission queries per keystroke is the real cost driver, roughly 40× the row scans.
3. **Revisit only past ~50k rows per entity.** At that point add FTS5 external-content tables with triggers (better recall than trigram for multi-word names, and SQLite-native). Trigram (`fts5(..., tokenize='trigram')`) is the right choice only if true substring matching mid-word is a hard requirement; it costs ~3–5× the index size.
4. Note the scaling shape: cost is ~`48 predicates × total rows`, not `rows²` — this stays acceptable well past the current scale.

---

## WHAT IS CORRECT — DO NOT CHANGE

1. **`accountingService.ts` posting engine** (184-279 `postEntry`) — validates ≥2 lines, debit XOR credit per line, balanced debit/credit totals, and an open accounting period. Textbook double entry.
2. **`accountingService.getAccountBalance` (109-160)** — correctly UNIONs `journal_lines` (`account_id`) with legacy `journal_entries` (matched by `text_code`), filters `voided = 0` and `line_date/entry_date <= ?`, and signs the result per `normal_balance` (145-147). This is the *only* place both GL tables are read together, and it is right. FACT 1's "a trial balance reading only one omits the other" does **not** apply to `getTrialBalance` — it reads both.
3. **`getTrialBalance` (Reports.ts:733-773)** — delegates entirely to `getAllAccountBalances`. Verified: totals foot exactly (79,535 = 79,535). The *report* is correct; the *data* is not.
4. **`getIncomeStatement` (Reports.ts:716-731)** — delegates to `getProfitLossReport`, with a comment recording the earlier fix where COGS was missing. Exactly the right pattern; the model for fixing REP-05.
5. **`getGrossProfit` vs `getProfitLossReport`** — byte-identical revenue and COGS SQL. Already consolidated.
6. **`getCashFlow` (781-810) and `getCashReconciliation` (1072-1179)** — both consume `cashService.collectFlows`, so they cannot disagree with the dashboard card by construction. `saveCashReconciliation` (1135-1179) validates account keys against the `CASH_ACCOUNTS` allowlist and snapshots the expected balance at save time — correct audit behaviour.
7. **`cashService.ts` design** — `normalizeCashMethod` (42-51) correctly maps `'credit'` to `null` (not a cash movement) and unknown methods to `'bank'`; `getCashAccountTotals` (178-200) derives opening/closing by differencing two cumulative snapshots rather than maintaining a running column. Sound. (Its *disagreement with the GL* is REP-03; the service itself is well built.)
8. **`getExpenseReport` (Reports.ts:1181-1207)** — `whereClause` assembled from a fixed conditions array with parameterised values. Injection-safe.
9. **`calculateInvoiceBalance` (ledgerUtils.ts:60-86)** — correctly sums `payment_allocations` (not raw `payments`) and handles `returned_amount` and `return_fee` with explicit currency helpers. This is the model the AP side should copy.
10. **`utils/currency.ts` usage** — `parseCurrency` / `addCurrency` / `subtractCurrency` / `multiplyCurrency` throughout ledger and invoice math avoids float drift.
11. **Local-date discipline in `Dashboard.ts`** — lines 253-259 and 305-310 use `date('now','localtime')` with a comment explaining the UTC+5 failure mode. This is the correct pattern; REP-12 is about the places that don't follow it.
12. **`Reports.ts:526-530`** — an honest inline comment documenting that historical SALE movements may carry `unit_cost = sale_price`. Keep such comments.
13. **`entityRegistry.ts`** — real 19-entity allowlist, `users` correctly excluded. Right architecture.
14. **`reportQueryEngine.ts` identifier quoting (125-127) and filter-value binding (401-522)** — both correct. Only `computedColumns[].expression` escapes.
15. **`CustomReport.findById(id, userId)` (CustomReport.ts:47-52)** — properly user-scoped.
16. **Palette actions are navigation-only** — `search_navigation.dart:30-38`. No mutation from Ctrl+K. Keep this invariant.
17. **Server-side action permission filtering** — `filterActions` (searchService.ts:172-199) computes the action list server-side; `search_action_panel.dart` has no permission logic. Correct direction of trust.
18. **Flutter report screens are pure presentation** — grepped all 20 screens for `fold`/`reduce`/recomputation: the only client arithmetic is a max-for-bar-scaling (`ar_summary_report_screen.dart:266`) and summing the user's own *counted* cash for reconciliation variance (`cash_reconciliation_screen.dart:191`). **No business total is recomputed client-side** — no Dart/SQL divergence to audit. This is unusually disciplined; preserve it.
19. **Report route hardening** — all 16 routes in `routes/reports.ts` carry `requirePermission('reports','read')`, and 12 also carry `sensitiveOperationLimiter`. `/dso` adds `validateZodQuery(zodSchemas.period)`.
20. **Search input validation** — `routes/search.ts` zod schema (`q: z.string().min(2).max(100)`, `limit` int 1-50) plus a 200 ms client debounce (`global_search_dialog.dart:61-66`) and a `<2` char short-circuit in both `search_provider.dart:19` and `searchService.ts:821`. Every search predicate is parameterised — no string concatenation anywhere in `searchService.ts`.
21. **`ActivityLog.ts:252-258`** — the `localDateToUtcBound` + half-open-interval pattern is the correct way to filter a DATETIME column by local dates. Use it as the template if any report ever filters on `created_at`.

---

## UNVERIFIED

1. **Runtime confirmation of REP-18.** I did not execute the injection. better-sqlite3's native module fails to load in this workspace (`NODE_MODULE_VERSION 137` vs required `127`, `ERR_DLOPEN_FAILED`), so I established the behaviour by reading the addon's C++ source (`binder.cpp:19`, `statement.cpp:126`) rather than by running it. The code path (285/305 → 238) is unambiguous from source; the *exploit string* is reasoned, not demonstrated.
2. **Whether any deployment has a non-admin user.** The live DB has one user (admin), so SRCH-01 is latent here. I cannot see other installations.
3. **Whether `movement_type = 'OUT'` is ever written.** Grep of the current writers shows only `SALE`, `PURCHASE`, `ADJUSTMENT`, `TRANSFER`, `PRODUCTION`. `'OUT'` appears only in the balance-sheet query. It may be a legacy value from an earlier schema — REP-05 is a live *code* divergence with zero current *numeric* impact.
4. **`settings.opening_retained_earnings`** is absent from the live `settings` table, so equity's opening component is 0. Whether any deployment sets it is unknown; the REP-01 imbalance would shift by that amount but not close (the gap is 28,200).
5. **Real-world query latency.** The performance analysis in SRCH-07 is derived from row counts, the absence of usable indexes, and the query-count arithmetic — not from `EXPLAIN QUERY PLAN` or wall-clock measurement (blocked by the same native-module failure).
6. **`getBatchTraceability` (Reports.ts:~425-473)** — routed and read only in outline; not audited for formula divergence.
7. **The 17 unrouted report functions** were audited for formulas but not for whether some other module imports them directly (I checked `routes/` and `controllers/`, not every file).

---

## PRIORITISED REMEDIATION

**P0 — before any owner sees the accounting reports**
1. REP-18 — structured allowlist for `computedColumns[].expression`; call `validateReportConfig` in the inline branch (`customReportsController.ts:300`). *Credential disclosure.*
2. REP-01 / REP-02 / REP-03 — one decision: **the GL is canonical**. Add the missing posting helpers (purchases/AP, supplier payments, expenses, opening equity), rebuild `getBalanceSheet` from `getAllAccountBalances`, and have the balance sheet consume `cashService` (or vice versa) so cash has one value. Until then, gate the balance sheet, trial balance and cash reconciliation behind a "provisional — do not file" banner.

**P1**
3. SRCH-01 — `.all(role.role_id)` plus a non-admin test fixture (one-character fix, total outage for non-admins).
4. SRCH-02 — filter search results by `<module>:read`.
5. REP-06 — `MobileInvoice.ts:249` must use `consumeFromOldestBatches`, not `unit_price`, as `unit_cost`.
6. REP-07 — one shared net-revenue SQL fragment; separate tax-exclusive and tax-inclusive line columns (**needs a migration**).
7. Concept (a)/(b) — one `computeInvoiceLineAmount()` and one server-side `total_amount` recomputation shared by all four creation paths; stop trusting `data.total_amount` at `Invoice.ts:695`.
8. REP-04 — real general ledger from `journal_lines`.
9. REP-05 — single `cogsForPeriod` helper.
10. REP-08 — rebuild customer statements from `customer_ledger` with a real opening balance.

**P2**
11. REP-15 — call `voidJournalLinesByReference` on invoice delete; void the 12 existing orphans.
12. REP-14 — `ORDER BY transaction_date ASC, id ASC` in both ledger rebuilds, then re-run them.
13. REP-12 — one `todayLocal(db)` helper across the six controller defaults and `ledgerUtils.ts:27`.
14. REP-13 — delete `activityLogger.getStats` and its `getActivityStats` re-export.
15. SRCH-03 — hoist permission resolution out of `filterActions`.
16. SRCH-04 — status/`is_active` filters on invoices, warehouses, employees.
17. REP-16 / REP-17 — add the three missing range pairs; implement or remove the two 404 endpoints.
18. **Delete the ~17 unrouted report functions** — they are the other half of the "remove 22 duplicate report screens" cleanup and every one still carries a divergent formula waiting to be re-exposed.

**P3**
19. SRCH-05 — delete dead `rankClause`/`rankParams`; cap `limit` at 10; align `searchSalesOrders`/`searchPurchaseOrders` binding.
20. SRCH-07 — drop the unusable leading-wildcard indexes; keep LIKE.
21. REP-09 / REP-10 / REP-11 — fix or delete.
22. REP-19 — admin-gate `createTemplate`.

agentId: afd549fbd64d89cf8 (use SendMessage with to: 'afd549fbd64d89cf8', summary: '<5-10 word recap>' to continue this agent)
<usage>subagent_tokens: 172410
tool_uses: 86
duration_ms: 2417664</usage>