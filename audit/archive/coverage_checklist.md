# Coverage checklist

**Status key:** BLOCKED means the check was not executed because the requested application was absent from the active UI automation inventory (`apps: []`, `browsers: []`). It does not mean the feature is unsupported or failed. No business action was taken.

## Baseline and fixtures — BLOCKED

- [ ] BLOCKED — Inventory pre-existing records and record IDs/names/key balances in every module.
- [ ] BLOCKED — Check/reuse/create Shakoor; record ID and opening balance.
- [ ] BLOCKED — Check/reuse/create Demo Supp; record ID and opening balance.
- [ ] BLOCKED — Check/reuse/create Main Warehouse; set and read back default status.
- [ ] BLOCKED — Check/reuse/create Shop WH; record ID and stock.
- [ ] BLOCKED — Check/reuse/create Milk 1L; identify packaging terminology, pcs base, batch/expiry tracking, carton support/conversion, price and cost.
- [ ] BLOCKED — Check/reuse/create Rice; confirm kg-only purchase/stock and no carton; price and cost.
- [ ] BLOCKED — Check/reuse/create Hammer; confirm pcs base, no expiry, carton support/conversion, price and cost.
- [ ] BLOCKED — Milk batch/expiry fixture values, distinct dates, FEFO selection and expiry guards.
- [ ] BLOCKED — Record IDs, conversions, costs and baseline quantities for all created records.
- [ ] BLOCKED — Disposable environment/database confirmation and role/user inventory.

## UI-wide methodology — BLOCKED

- [ ] BLOCKED — Exhaustively navigate every screen and exercise every visible control/action button.
- [ ] BLOCKED — On every list (products, inventory, purchase orders, purchase bills, purchase returns, supplier payments, invoices, sales returns, customer payments, quotations, customers, suppliers, warehouses, reports): click every column header in both sort directions; open/apply/clear every filter; search; paginate; export when present.
- [ ] BLOCKED — On every form, submit empty required fields and exercise invalid, out-of-range, zero, negative, maximum-length and future/past date values; read back saved values after navigating away and returning.
- [ ] BLOCKED — Observe every Save/Post/Approve/Reverse/Refund/Convert/Export/Delete action and resulting state; capture irreversible confirmation and post-action state before stopping that workflow.
- [ ] BLOCKED — Record exact navigation path and before/action/after/read-back screenshots for each executable scenario.
- [ ] BLOCKED — For report reconciliations, export before and after the action and calculate numeric delta.
- [ ] BLOCKED — Use REA on the app binary, database, preferences and network evidence for financial discrepancies; determine data-layer versus presentation-layer origin.
- [ ] BLOCKED — Reproduce and cross-check each discrepancy using two independent sources; document both numeric values.

## Products — BLOCKED

- [ ] BLOCKED — Product create, edit and archive actions; persisted read-back.
- [ ] BLOCKED — SKU uniqueness and duplicate-SKU validation.
- [ ] BLOCKED — Units, price and tax fields; empty, invalid, zero, negative, boundary and out-of-range inputs.
- [ ] BLOCKED — Product list search, every filter, clear filter, every column sort direction, pagination and export.
- [ ] BLOCKED — Milk carton-to-pcs configuration and conversion; fractional/invalid carton quantity.
- [ ] BLOCKED — Hammer carton-to-pcs configuration and conversion; fractional/invalid carton quantity.
- [ ] BLOCKED — Rice purchase/stock in kg only and carton exclusion.
- [ ] BLOCKED — Milk batch and expiry requiredness, expiry entry, FEFO and expiry guards.
- [ ] BLOCKED — Confirm Hammer does not require expiry.

## Inventory and warehouses — BLOCKED

- [ ] BLOCKED — Warehouse create/edit; default warehouse persistence; stock assignment.
- [ ] BLOCKED — Opening stock by warehouse/product; Milk batch and expiry breakdown.
- [ ] BLOCKED — Positive and negative adjustments; reasons and GL effects.
- [ ] BLOCKED — Warehouse transfer; approval flow if present; before/after quantities by warehouse and total.
- [ ] BLOCKED — Transfer greater than available stock; negative-stock behavior.
- [ ] BLOCKED — Low-stock alerts and thresholds.
- [ ] BLOCKED — Stock-by-warehouse versus inventory-total report quantity.
- [ ] BLOCKED — Product stock movements versus current stock-on-hand.
- [ ] BLOCKED — Transfers conserve total stock and change each warehouse by the transfer quantity.

## Purchases and purchase orders — BLOCKED

- [ ] BLOCKED — Create PO; receive partial quantity; verify received stock and partial status.
- [ ] BLOCKED — Receive remaining quantity; verify closed status and full stock.
- [ ] BLOCKED — PO edit after receipt; downstream bill and inventory propagation.
- [ ] BLOCKED — Purchase bills in fully paid, partially paid and unpaid states; totals, payments, balances and AP aging.
- [ ] BLOCKED — Partial supplier payment, second payment clearing bill, full reversal and partial reversal; exact read-back and no rounding drift.
- [ ] BLOCKED — Returns against received PO and paid, partially paid and unpaid purchase bills.
- [ ] BLOCKED — Supplier credit/debit notes, AP/statement effects and credit availability/application/refund.
- [ ] BLOCKED — Supplier overpayment refund; cash/refund record, AP and P&L impact.
- [ ] BLOCKED — One supplier payment allocated across multiple bills.
- [ ] BLOCKED — Overpay bill, pay cancelled bill and return more than purchased.
- [ ] BLOCKED — Milk and Hammer carton purchases/receipts in Main Warehouse; base quantities, costs, returns and transfers.
- [ ] BLOCKED — Partial carton receipts/returns; fractional and invalid amounts; conversion accuracy.
- [ ] BLOCKED — Milk receipt batch/expiry data; Rice purchased directly in kg.
- [ ] BLOCKED — Supplier statement and AP aging after each purchase-side action.
- [ ] BLOCKED — Purchase bill list versus AP aging total; before/after AP aging exports.
- [ ] BLOCKED — Purchase returns versus supplier credits/debit notes totals.

## Sales, invoices and payments — BLOCKED

- [ ] BLOCKED — Create fully paid, partially paid and unpaid invoices; totals, payments, balances, statuses and AR aging.
- [ ] BLOCKED — Partial payment, second payment clearing invoice, full reversal and partial reversal; exact balance/status and no rounding drift.
- [ ] BLOCKED — Returns against paid, partially paid and unpaid invoices; credit notes, non-negative balances and credit rules.
- [ ] BLOCKED — Customer refund of return credit; refund record, AR and P&L impact.
- [ ] BLOCKED — Apply return credit to later invoice; allocation and balances.
- [ ] BLOCKED — One customer payment allocated across multiple invoices.
- [ ] BLOCKED — Overpay invoice, pay cancelled invoice and return more than sold.
- [ ] BLOCKED — Customer statement and AR aging after each sales-side action.
- [ ] BLOCKED — Invoice list versus AR aging total; before/after AR aging exports.
- [ ] BLOCKED — Sales returns versus credit notes/customer credits totals.

## Quotations — BLOCKED

- [ ] BLOCKED — Create quotation; empty/invalid/boundary validation and persisted read-back.
- [ ] BLOCKED — Convert quotation to invoice; line items, prices and taxes.
- [ ] BLOCKED — Edit source quotation after conversion; verify converted invoice behavior.
- [ ] BLOCKED — Convert quotation to sales order; lines/prices and status.
- [ ] BLOCKED — Filter by status, date range and customer; confirm results.
- [ ] BLOCKED — Search, each column sort direction, pagination and export.

## Payments (both directions) — BLOCKED

- [ ] BLOCKED — Customer receipt against one or more invoices; partial, overpayment and allocation.
- [ ] BLOCKED — Customer payment reversal (full and partial) and refund; persisted read-back.
- [ ] BLOCKED — Supplier payment against one or more bills; partial, overpayment and allocation.
- [ ] BLOCKED — Supplier payment reversal (full and partial), supplier refund and supplier credit application.
- [ ] BLOCKED — Payment lists: search, filters, sorts, pagination and export.
- [ ] BLOCKED — Attempt every payment action, capture dialogs/results, and reverse only when product supports it.

## Customers and suppliers — BLOCKED

- [ ] BLOCKED — Customer/supplier balances, aging, statements and transaction histories.
- [ ] BLOCKED — Credit limits and enforcement.
- [ ] BLOCKED — Lists: search, filters, each column sort direction, pagination and export.
- [ ] BLOCKED — Forms: empty required fields, invalid/out-of-range/zero/negative/boundary values and persisted read-back.

## Reports — BLOCKED

- [ ] BLOCKED — Profit and loss, balance sheet and trial balance.
- [ ] BLOCKED — AR aging and AP aging.
- [ ] BLOCKED — Inventory valuation, stock-on-hand and stock movement.
- [ ] BLOCKED — Customer statements and supplier statements.
- [ ] BLOCKED — Export reports before and after each relevant test action.
- [ ] BLOCKED — Invoice list versus AR aging; purchase bill list versus AP aging.
- [ ] BLOCKED — Returns versus customer/supplier credit totals.
- [ ] BLOCKED — Stock-on-hand versus stock movements and stock-by-warehouse.
- [ ] BLOCKED — Trial balance debit versus credit; AR/AP subledgers versus TB control balances.
- [ ] BLOCKED — Valuation report versus quantity-times-cost under the app's stated costing method.
- [ ] BLOCKED — Reconciliation/audit report, if exposed.

## Accounting and inventory invariants — BLOCKED

- [ ] BLOCKED — Sales: partial/unpaid invoice balances equal AR aging due.
- [ ] BLOCKED — Sales: allocated payment amount does not exceed related invoice totals.
- [ ] BLOCKED — Sales: paid invoice count equals zero-balance invoice count.
- [ ] BLOCKED — Sales: returns equal credits applied to customer balance or refunded.
- [ ] BLOCKED — Sales: full reversal restores original invoice balance.
- [ ] BLOCKED — Purchases: partial/unpaid bill balances equal AP aging due.
- [ ] BLOCKED — Purchases: allocated supplier payments do not exceed related bill totals.
- [ ] BLOCKED — Purchases: paid bill count equals zero-balance bill count.
- [ ] BLOCKED — Purchases: returns equal supplier credits applied or refunded.
- [ ] BLOCKED — Purchases: full reversal restores original bill balance.
- [ ] BLOCKED — Inventory: warehouse stock sum equals inventory total report.
- [ ] BLOCKED — Inventory: movement quantity sum equals current stock-on-hand.
- [ ] BLOCKED — Inventory: transfer conserves total stock and changes per-warehouse stock exactly.
- [ ] BLOCKED — Financial: trial balance debit total equals credit total.
- [ ] BLOCKED — Financial: AR and AP subledgers equal TB control account balances.
- [ ] BLOCKED — Financial: valuation equals stock quantity times app-stated cost.

## Roles, permissions and safety — BLOCKED

- [ ] BLOCKED — Role/user selector and users per role, if exposed.
- [ ] BLOCKED — Low-privilege visibility/modification of financial data, payment reversal and return approval.
- [ ] BLOCKED — Destructive actions and reversibility; irreversible workflows require confirmation-dialog and post-action screenshots before marking blocked.

## Access blocker evidence

- `execution_log.jsonl`: CUA returned an empty app/browser inventory; window enumeration method was unavailable.
- No app screenshot exists because no app/browser surface was available. These are access blockers, not findings about application behavior.
