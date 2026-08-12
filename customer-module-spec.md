# Customer Module Parity — Implementation Spec

**Request:** Check the customer module in `/home/fawad/ai/minierp` (web/React reference) and implement the same in this app (`minierp-flutter`).
**Status:** Implemented 2026-08-12 (list upgrades first, then the full detail page + tabs + payment modal). See the file plan below for what landed; all `dart analyze` clean and the customer test suites pass.
**Date:** 2026-08-12

---

## 1. Goal

Bring the Flutter customers module to feature parity with the web app's customer module:
a full-screen customer detail page with 5 tabs (Overview / Invoices / Ledger / Payments / Statement),
a richer customer list (status tabs, full grid columns, per-row actions, delete, Fix Balances),
and a web-style Record Payment modal. All backend endpoints already exist and are **byte-identical**
between the two repos (`server/src/controllers/customersController.ts`), so this is a pure frontend port.

---

## 2. Current state (what already exists)

### Flutter app (target — `minierp-flutter`)
- **List:** `lib/features/customers/customers_screen.dart` — server-paginated PlutoGrid (search, page/limit/sort providers), Add Customer button, read-only columns (Code, Name, Phone, Email, Balance, Status).
- **Form:** `lib/features/customers/customer_form_dialog.dart` — create/edit dialog (name, contact person, phone, email, payment terms text + days, credit limit, opening balance, billing/shipping addresses).
- **Detail:** `lib/features/customers/customer_detail_dialog.dart` — **read-only** dialog (to be replaced by the page).
- **Ledger:** `lib/features/customers/customer_ledger_dialog.dart` — thin facade over the shared `lib/widgets/ledger_dialog.dart` (flat newest-first table + totals).
- **Providers:** `lib/features/customers/customer_providers.dart` — `customersProvider` (paged), `customerDetailProvider`, `customerLedgerProvider`.
- **Calculations:** `lib/features/customers/calculations/customer_calculations.dart` — already a 1:1 port of `calculations/customerCalculations.ts` (`CustomerMetrics`, `computeCustomerMetrics`, `calculateLedgerTotals`, `calculateCreditUtilization`, `calculateOverdueInvoices`, `countPaid/UnpaidInvoices`, `calculateAverageDaysToPay`, `getRecentInvoices/Payments`, format helpers). **No changes needed here.**
- **Payments (reusable):** `lib/features/payments/record_payment_dialog.dart` (global Record Payment with allocations), `payments_screen.dart`, `payments_providers.dart` (`paymentsProvider`, `paymentCustomerOptionsProvider`, `customerOpenInvoicesProvider`).
- **Sales (reusable):** `lib/features/sales/invoice_providers.dart` — `invoicesProvider` + `InvoiceFilters(status, customerId)` (server supports `customer_id`), `invoiceRepositoryProvider`.
- **Repositories:** `invoice_repository.dart` has `invoices({filters})`, `invoice(id)`, `createInvoicePayment`, `updatePayment`, `deletePayment`, `delete(id)`, `cancel(id)`. `customer_repository.dart` has `list/get/create/update/delete/ledger/balance` — **missing:** statement fetch.
- **Shared widgets:** `pluto_grid_screen.dart` mixin (F2/Enter/double-tap → `openRowDetail`), `status_badge.dart`, `screen_toolbar.dart`, `pagination_bar.dart`, `searchable_select.dart`, `app_toast.dart`, `form_field.dart`/`form_helpers.dart`, `date_picker_helpers.dart`, `ledger_table.dart` (`LedgerHeaderRow`/`LedgerEntryRow`/`LedgerTotalsRow`).
- **Printing:** `lib/features/sales/invoice_pdf.dart` + `printing` package — A4 PDF pattern to reuse for the payment receipt.
- **CSV export:** `csv` + `file_picker` packages already in `pubspec.yaml` (used by activity log / ledger-export patterns).
- **Locales:** `lib/l10n/en.arb` + `lib/l10n/ur.arb`; `customers*` keys exist (~12 today).

### Reference web app (source — `/home/fawad/ai/minierp`)
- `client/src/pages/customers/CustomersPage.tsx` — search + All/Active/Inactive tabs, grid (Customer Code, Name+contact person, Contact Info phone+email, Address, Credit Limit, Current Balance, Credit Utilization, Payment Terms, Status, ⋮ actions View/Edit/Delete), Fix Balances button, Add Customer, `Alt+N` shortcut, double-click → detail.
- `client/src/pages/customers/CustomerDetailPage.tsx` — header + quick stats (Balance, Credit Limit, Utilization, Overdue) + tabs Overview/Invoices/Ledger/Payments.
- `client/src/components/customer/OverviewTab.tsx` — Financial Summary cards (Total Invoiced, Total Received, Outstanding, Avg Days to Pay), Invoice Status bars (Paid/Pending/Overdue/Total), collapsible Contact Information + Account Settings (+ Recent Invoices/Payments — **excluded by decision**).
- `client/src/components/customer/InvoicesTab.tsx` — grid (Invoice No, Date, Due Date, Total, Paid, Balance, Status, ⋮ View/Delete/Cancel guarded by `invoiceRules.ts`).
- `client/src/components/customer/LedgerTab.tsx` — ledger grouped by invoice (expand/collapse), CSV/PDF/Image/Print export toolbar, totals sidebar (`groupLedgerByInvoice` in `utils/ledgerGrouping.ts`, `ledgerExport` in `export-utils/ledgerExport.ts`).
- `client/src/components/customer/PaymentsTab.tsx` — grid (Payment No, Date, Amount, Method, Reference, Notes, ⋮ Print Receipt / Print Thermal / Edit / Delete).
- `client/src/components/customers/PaymentModal.tsx` — Record Payment with customer info, date, amount, method, reference, notes, **invoice allocations** (available invoices list, add/remove lines, per-line amount capped at balance, auto-allocate, total/allocated/unallocated summary, validation "amount must match allocated"), success screen with Print Receipt (A4) / Print Thermal options.
- `client/src/pages/customers/CustomerStatement.tsx` — date-range filter, customer info block, statement summary (opening/closing/debits/credits), transaction table with running balance.
- Business rules: `calculations/invoiceRules.ts` (`canDeleteInvoice`/`canShowDeleteAction`/`canCancelInvoice`); `utils/customerCalculations.ts` (already ported).

---

## 3. Confirmed decisions (from user interview)

| # | Question | Decision |
|---|---|---|
| 1 | Detail form factor | **Full-screen page** (web parity; PORTING.md `CustomerDetailScreen`) |
| 2 | Feature scope | **All**: status tabs, richer grid columns, per-row actions, Fix Balances, Record Payment, Invoices/Payments/Ledger tabs, customer statement |
| 3 | List grid columns | **Full parity with web** (incl. color coding) |
| 4 | Delete + Fix Balances | **Add both** |
| 5 | Overview tab sections | Financial summary cards, Invoice status breakdown, Contact information, Account settings (**no** Recent Invoices/Payments) |
| 6 | Invoices tab actions | **View + delete + cancel** (guarded by invoice rules) |
| 7 | Payments tab actions | **View + edit + delete + A4 print** (thermal out of scope) |
| 8 | Record Payment | **Rebuild web-style modal** (allocation list + auto-allocate + success/print) |
| 9 | Ledger tab | **Web-style grouped (by invoice, expand/collapse) + export** (CSV/PDF/Image/Print) |
| 10 | i18n | **Both en + ur** |
| 11 | Navigation to detail | **Double-click AND ⋮ View → page; remove the old read-only dialog** |
| 12 | Customer statement | **5th tab on the detail page** |

**Fixed constraints (from PORTING.md, unchanged):** desktop-only; no mobile card views; thermal printing excluded; no backend changes.

---

## 4. Navigation & routing

- Add `GoRoute(path: ':id')` under the `/customers` branch in `lib/app.dart` → `CustomerDetailScreen` (reads `id` from `state.pathParameters`, pushes via `context.push('/customers/$id')`).
- `CustomersScreen.openRowDetail(id)` becomes: `context.push('/customers/$id')` (replaces `showCustomerDetailDialog`).
- **Remove** `customer_detail_dialog.dart` usage (delete the file or leave the opener unused — prefer deleting since decision 11 says the dialog is replaced). Keep `customer_form_dialog.dart` (create/edit) and `customer_ledger_dialog.dart` (still useful from other entry points; verify references — if nothing else uses the ledger dialog after the page lands, it can stay for the Suppliers facade symmetry).

---

## 5. Customers list screen (`customers_screen.dart`)

### 5.1 Status tabs (All / Active / Inactive)
- Add `customersStatusProvider = StateProvider<String?>((_) => null)` (`null`=All, `'active'`, `'inactive'`).
- Pass `status` into the existing `PagedRequest` → the server's `?status=` filter (already wired in `customersController.getCustomers`).
- Render a `SegmentedButton<String?>` or tab row in the toolbar area (matches the web tab bar). Changing tabs resets to page 1.

### 5.2 Full grid column parity
Columns (order matches web `CustomersPage` columnDefs):
1. `#` serial (existing mixin) — hidden id cell stays.
2. **Code** (`customer_code`) — mono/number-styled text.
3. **Name** + contact person sub-line (renderer shows name, and `contact_person` in muted small text below).
4. **Phone/Email** — phone with email sub-line.
5. **Address** (`billing_address`) — multi-line text (split on `\n`).
6. **Credit Limit** (`credit_limit`) — right-aligned currency, color-coded by utilization (see 5.3).
7. **Current Balance** (`current_balance`) — right-aligned currency, colored by sign (positive = warning/red-ish, zero = neutral).
8. **Credit Utilization %** (`credit_utilization_percent`) — `N/A` when no credit limit; `>=90` high (danger), `>=75` medium (warning), else low (success).
9. **Payment Terms** (`payment_terms_days`) — `"N days"`.
10. **Status** (`is_active`) — `StatusBadge` (Active green / Inactive blueGrey).
11. **Actions** column — `⋮` (`PopupMenuButton`) with View / Edit / Delete (destructive).

All values already present on the `Customer` model and returned by the server list endpoint — no backend work. Column width/format parity per web (`code` 120, `name` flex, phone 180, address 200, credit limit 120, balance 140, utilization 140, terms 120, status 100).

### 5.3 Color-coding helper
Add a small pure helper (or reuse `customer_calculations.dart`): given balance + credit limit, compute utilization and the CSS-style bucket (`danger >= 90`, `warning >= 75`, `low`). Web: `getCreditUtilizationClass`, `getBalanceCellClass` (`styles/ag-grid-status-cells.css`) → Flutter: cell `TextStyle` colors resolved from `Theme.of(context).colorScheme` (error / tertiary / primary), matching light+dark.

### 5.4 Row actions menu
- `PopupMenuButton<_CustomerAction>` in the Actions column (View / Edit / Delete).
- **View** → `context.push('/customers/$id')`.
- **Edit** → existing `showCustomerFormDialog(context, customer: c)` (pass the row's `Customer` so the form pre-fills without a fetch).
- **Delete** → confirm dialog (`customersConfirmdelete`-style message with the customer name) → `customerRepository.delete(id)` → toast + `ref.invalidate(customersProvider)`. Surface server 400 "Cannot delete customer with existing transactions" via `ErrorBanner`/toast.
- Keep double-click → detail page (decision 11).

### 5.5 Toolbar additions
- **Fix Balances** button (secondary/tonal, next to Add Customer): confirm dialog ("Recalculate all customer balances from unpaid invoices?") → `POST /customers/recalculate-balances` (add `recalculateBalances()` to `CustomerRepository`) → toast success + invalidate list.
- Keep Add Customer, search, refresh, pagination bar as-is. `Ctrl+N` new-customer shortcut already handled by `ScreenToolbar` (web `Alt+N` parity).

---

## 6. Customer detail page (`customer_detail_screen.dart` — new)

Full-screen page under the shell branch (not a dialog). Structure:

### 6.1 Header + quick stats (web `CustomerHeader`)
- Back arrow (`context.pop`) → "Back to Customers".
- Customer name (title) + contact person suffix + phone sub-line.
- **Record Payment** primary button → opens the new web-style payment modal (§9).
- Quick-stats bar (4 tiles): **Balance** (currency, red when negative), **Credit Limit** (currency), **Utilization %** (danger/warning color classes), **Overdue count** (danger when > 0). Data from `computeCustomerMetrics` (already ported).

### 6.2 Tabs
`DefaultTabController` + `TabBar` (or custom segmented tabs matching the app's style): **Overview | Invoices | Ledger | Payments | Statement**.

### 6.3 Data providers (new, in `customer_providers.dart`)
Mirror the web `useCustomerData` (customerKeys):
- `customerDetailProvider` — exists.
- `customerInvoicesProvider(id)` → `GET /invoices?customer_id=<id>` via existing `InvoiceFilters(customerId: id)` (unpaginated full list; web passes `customerId`, server accepts `customer_id` — use the repo's existing `InvoiceFilters.toQuery()` which sends `customer_id`).
- `customerLedgerProvider` — exists (used by the ledger tab + kept for the dialog facade).
- `customerPaymentsProvider(id)` → `GET /payments?customerId=<id>` (add `paymentsForCustomer(int id)` to `InvoiceRepository`/payments repo — verify existing endpoint param name; the web uses `customerId`).
- `customerStatementProvider(id, from, to)` → `GET /customers/:id/statement?fromDate&toDate` (add `statement(id, fromDate, toDate)` to `CustomerRepository`; parse `{customer, period, openingBalance, closingBalance, transactions}`).
- All `autoDispose.family`, invalidation helper `invalidateCustomerQueries(ref, id)` (invalidates detail + invoices + ledger + payments + the global `invoicesProvider`), matching web `invalidateCustomerQueries`.

### 6.4 Overview tab (`customer_overview_tab.dart` — new)
- **Financial Summary** — 4 `SummaryCard`s: Total Invoiced, Total Received, Outstanding Balance, Avg. Days to Pay (from `computeCustomerMetrics`).
- **Invoice Status** — 4 status tiles with proportional bars: Paid, Pending (Unpaid + Partially Paid), Overdue, Total Invoices.
- **Contact Information** (collapsible) — phone, email, billing address, shipping address ("Same as billing" fallback).
- **Account Settings** (collapsible) — payment terms days, credit limit, opening balance, customer since (`created_at`).
- Use existing `detail_labels.dart`/card conventions; collapsible = `ExpansionTile` or a small local state widget.

### 6.5 Invoices tab (`customer_invoices_tab.dart` — new)
- PlutoGrid (read-only, client-side sort) over `customerInvoicesProvider`.
- Columns: Invoice No (link-style → open invoice detail via `context.push('/sales/form', extra: invoice)`? — **note:** the web navigates to `/sales/invoice/:id?mode=view`; in Flutter the sales form/detail is `/sales/form` with `extra: Invoice`. Verify the correct existing route and use it), Date, Due Date, Total, Paid, Balance (colored), Status (`StatusBadge`).
- Row actions (⋮): **View** (same route), **Delete** (only when `canShowDeleteAction`), **Cancel** (only when `canCancelInvoice`).
- Delete/cancel confirm dialogs; on success invalidate customer queries + invoices. Delete shows a warning when `paid_amount > 0` (web behavior; though the rule already blocks paid invoices, keep the guard).
- Port `calculations/invoiceRules.ts` → `lib/features/customers/calculations/invoice_rules.dart` (`canDeleteInvoice`, `canShowDeleteAction`, `canCancelInvoice`) — check whether `lib/features/sales/calculations/` already has an equivalent before creating (avoid duplication; the sales module may own invoice rules).

### 6.6 Ledger tab (`customer_ledger_tab.dart` — new)
- Port `utils/ledgerGrouping.ts` → `lib/features/customers/calculations/ledger_grouping.dart` (`InvoiceGroup`, `UngroupedEntry`, `groupLedgerByInvoice`, `extractInvoiceNo` — including the `linked_invoice_no` / RETURN handling).
- Render grouped rows in PlutoGrid: group header row (Invoice ref + "N payments — Balance: X"), expand/collapse chevron toggling child rows (child rows show payment entries). Rows carry `_isGroupHeader`/`_isChild`/`_groupId` flags (mirror web `GroupedRow`).
- Totals sidebar: Total Debit, Total Credit, Current Balance — computed with `calculateLedgerTotals` + returned-invoice exclusion (already ported; pass `returnedInvoiceNos` from invoices with status `Returned`).
- **Export toolbar** (CSV / PDF / Image / Print):
  - CSV → `csv` package + `file_picker` save dialog (port `export-utils/ledgerExport.ts` shapes).
  - PDF → `pdf` + `printing` (A4 table layout; follow `invoice_pdf.dart` pattern).
  - Image → capture the grid/table via `RepaintBoundary` + `toImage` → save PNG.
  - Print → native print dialog via `printing` with the PDF.
- Empty state: "No ledger entries".

### 6.7 Payments tab (`customer_payments_tab.dart` — new)
- PlutoGrid over `customerPaymentsProvider`: Payment No, Date, Amount, Method, Reference, Notes.
- Row actions (⋮): **Print Receipt (A4)** (reuse `invoice_pdf.dart`/receipt pattern or a new `payment_receipt_pdf.dart`; fetch receipt data from `GET /payments/:id`), **Edit** (reuse existing `lib/features/payments/edit_payment_dialog.dart`), **Delete** (confirm + `deletePayment`; invalidate).
- Amount read-only on edit (web behavior — amount cannot change; delete + recreate instead).

### 6.8 Statement tab (`customer_statement_tab.dart` — new)
- Date-range filter (From/To date pickers via `date_picker_helpers.dart`; default last 30 days → today).
- Statement header block: customer info + summary (Opening Balance, Closing Balance, Total Debits, Total Credits).
- Transaction table: Date | Reference | Description | Debit | Credit | Balance (running balance computed from opening; opening-balance row + closing-balance row, mirroring web `CustomerStatement.tsx`).
- Optional: A4 print of the statement via `pdf`/`printing` (nice-to-have; mark as stretch — web's "Download PDF" is a stub there too).

---

## 7. Record Payment modal (`customer_payment_modal.dart` — new, web-style)

Opened from the detail header's **Record Payment** button with the customer pre-bound. Web `PaymentModal` parity:
- Header shows customer name + code (read-only).
- Fields: Payment Date (default today), **Total Amount**, Payment Method (reuse `kPaymentMethods`), Reference No, Notes.
- **Invoice Allocations** section:
  - "Available Invoices" list (open invoices `balance > 0` fetched via `InvoiceFilters(customerId, status: 'Unpaid,Partially Paid,Overdue')`) with balance + Add button.
  - "Allocated Invoices" list: per-line amount input (capped at invoice balance) + remove (×).
  - **Auto Allocate** button (fills remaining amount across open invoices oldest-first, skipping already-allocated).
  - Summary row: Total Payment / Total Allocated / **Unallocated** (highlighted when ≠ 0).
  - Validation: amount > 0; total amount must equal total allocated; at least one allocation.
- Submit → `POST /payments` with `invoice_allocations` (reuse `invoiceRepository.createInvoicePayment`).
- On success: **success screen** (like web) with "Print Receipt (A4)" and "Close" actions → then invalidate customer queries.
- Note: the existing global `RecordPaymentDialog` stays untouched (Payments module). This is a separate web-style modal per decision 8. (Do NOT attempt to parameterize the existing dialog to pre-select a customer unless trivial.)

---

## 8. Business rules & calculations summary

| Rule | Source (web) | Flutter target | Status |
|---|---|---|---|
| Customer metrics | `customerCalculations.ts` | `customers/calculations/customer_calculations.dart` | **Already ported** |
| Ledger totals w/ returned-invoice exclusion | same | same | **Already ported** |
| Invoice delete/cancel guards | `invoiceRules.ts` | `invoice_rules.dart` (customers or sales calculations) | **To port** |
| Ledger grouping | `ledgerGrouping.ts` | `ledger_grouping.dart` | **To port** |
| Ledger export | `export-utils/ledgerExport.ts` | `ledger_export.dart` (CSV/PDF/image/print) | **To port** |
| Credit/balance cell coloring | `statusCellUtils.ts` + `ag-grid-status-cells.css` | small color helper in the customers screen | **To port** |

---

## 9. Repository additions

- `CustomerRepository.statement(int id, {String? fromDate, String? toDate})` → `GET /customers/:id/statement` (new `CustomerStatement` DTO in the repo or a model).
- `CustomerRepository.recalculateBalances()` → `POST /customers/recalculate-balances`.
- `CustomerRepository` already has `delete` (soft). Verify it surfaces the server 400 message.
- Payments-by-customer: add `paymentsForCustomer(int customerId)` (enveloped list; check param name `customerId` vs `customer_id` against `paymentsController`).
- `deleteInvoice`/`cancel` already exist on `InvoiceRepository`.

---

## 10. l10n keys (add to both `en.arb` and `ur.arb`)

Prefix all new keys under `customers` (existing: `customersActions`, `customersAddress`, `customersConfirmdelete`, `customersCustomername`, `customersCustomers`, `customersDelete`, `customersEmail`, `customersNewcustomer`, `customersPhone`, `customersSave`). Needed (draft names; finalize during implementation):
- Tabs: `customersOverview`, `customersInvoices`, `customersLedger`, `customersPayments`, `customersStatement`
- List: `customersAll`, `customersActive`, `customersInactive`, `customersCreditlimit`, `customersCurrentbalance`, `customersCreditutilization`, `customersPaymentterms`, `customersContactperson`, `customersAddress`, `customersFixbalances`, `customersFixbalancesconfirm`, `customersDeleteconfirm`, `customersCannotedelete`, `customersView`
- Quick stats: `customersBalance`, `customersUtilization`, `customersOverdue`, `customersCreditlimit`
- Overview: `customersTotalinvoiced`, `customersTotalreceived`, `customersOutstanding`, `customersAvgdaystopay`, `customersInvoicestatus`, `customersPaid`, `customersPending`, `customersTotal`, `customersContactinfo`, `customersAccountsettings`, `customersCustomersince`
- Invoices tab: `customersInvoiceno`, `customersDuedate`, `customersTotal`, `customersPaid`, `customersBalance`, `customersStatus`, `customersDeleteinvoice`, `customersCancelinvoice`, `customersCancelwarning`
- Payments tab: `customersPaymentno`, `customersAmount`, `customersMethod`, `customersReference`, `customersNotes`, `customersEditpayment`, `customersDeletepayment`, `customersPrintreceipt`
- Statement: `customersFrom`, `customersTo`, `customersOpeningbalance`, `customersClosingbalance`, `customersTotaldebits`, `customersTotalcredits`, `customersTransactiondetails`
- Payment modal: `customersRecordpayment`, `customersTotalamount`, `customersAllocation`, `customersAvailableinvoices`, `customersAllocatedinvoices`, `customersAutoallocate`, `customersUnallocated`, `customersPaymentrecorded`, `customersPrintreceipta4`
- Ledger export: `customersExportcsv`, `customersExportpdf`, `customersExportimage`, `customersPrint`

Also add equivalent keys to `ur.arb` (decision 10). Run `flutter gen-l10n` after edits.

---

## 11. File plan

**New files**
```
lib/features/customers/customer_detail_screen.dart      (page: header, quick stats, tabs, modals)
lib/features/customers/customer_overview_tab.dart
lib/features/customers/customer_invoices_tab.dart
lib/features/customers/customer_ledger_tab.dart         (grouped grid + export toolbar)
lib/features/customers/customer_payments_tab.dart
lib/features/customers/customer_statement_tab.dart
lib/features/customers/customer_payment_modal.dart      (web-style record payment)
lib/features/customers/calculations/ledger_grouping.dart
lib/features/customers/calculations/invoice_rules.dart  (or sales/calculations/ if it belongs there)
lib/features/customers/calculations/ledger_export.dart  (CSV/PDF/image/print helpers)
```

**Modified files**
```
lib/features/customers/customers_screen.dart            (status tabs, columns, actions menu, delete, Fix Balances, → page)
lib/features/customers/customer_providers.dart          (status provider, per-customer invoices/payments/statement providers, invalidation helper)
lib/data/repositories/customer_repository.dart          (statement, recalculateBalances)
lib/data/repositories/invoice_repository.dart           (paymentsForCustomer if missing)
lib/app.dart                                            (/customers/:id GoRoute)
lib/l10n/en.arb, lib/l10n/ur.arb                        (new keys + gen-l10n)
```

**Removed**
```
lib/features/customers/customer_detail_dialog.dart       (replaced by the page; verify no other references)
```

---

## 12. Edge cases & behaviors to preserve

1. **Delete customer** → server soft-deactivates; 400 when invoices/payments exist — surface the exact message.
2. **Invoice delete** only for `Draft`/`Unpaid` with `paid_amount == 0 && returned_amount == 0`; cancel allowed unless already `Cancelled`.
3. **Ledger totals** exclude RETURN/REFUND entries and entries of fully returned invoices (returned-invoice set from invoices with status `Returned`) — already in the ported `calculateLedgerTotals`.
4. **Statement balance** = opening + Σ(debit − credit) per row; running balance displayed per transaction.
5. **Payment modal**: amount must equal allocation total; per-line cap at invoice balance; auto-allocate oldest-first; no allocation → block submit.
6. **Empty states**: no ledger entries, no invoices, no payments, no open invoices for allocation.
7. **Loading/error** states per tab (reuse `DetailError`/spinner conventions).
8. **Invalidation**: after payment/invoice/payment-edit/delete/cancel → invalidate detail + invoices + ledger + payments (+ global invoices list) so all tabs refresh.
9. **Currency formatting** via `Formatters.currency` (settings-aware); keep web's color semantics for balance/utilization.
10. **RTL (Urdu)**: verify new tab bars, tables, and quick-stats render correctly (Flutter handles bidi; check mixed number/currency strings).
11. **Keyboard**: keep `Ctrl+N` new-customer; double-click + F2/Enter open the detail page (mixin already routes through `openRowDetail`).

---

## 13. Out of scope (explicit)

- Thermal receipt printing (PORTING.md gap; web's thermal path excluded).
- Mobile compact-card views / `<768px` layouts (PORTING.md excluded).
- Backend changes (controllers identical already).
- Recent Invoices/Payments sections in Overview (user decision 5).
- Custom report builder / dashboard (separate PORTING gaps).
- Customer import/export in the list (not in web module).

---

## 14. Validation plan (Definition of Done)

1. `dart analyze` → 0 issues.
2. `flutter test` → all existing tests green (including `test/sales_invoice_form_page_test.dart`, `widget_test.dart`, calculation tests); add unit tests for:
   - `ledger_grouping.dart` (group by invoice, RETURN handling, `linked_invoice_no`, ungrouped entries — port the TS behavior).
   - `invoice_rules.dart` (delete/cancel guards).
   - statement running-balance math (pure helper).
3. `flutter gen-l10n` runs clean; no missing `customers*` keys in `ur.arb` (fallback OK for any stragglers).
4. Manual smoke (desktop): list tabs filter; row menu actions; detail page all 5 tabs; record payment allocation math + success/print; delete/cancel guards; ledger export file outputs.
5. `flutter build linux` (or the project's standard build) succeeds.

---

## 15. Open questions (low priority — resolve during implementation)

- Exact route for opening an invoice from the Invoices tab (`/sales/form` with `extra: Invoice` vs a dedicated detail route) — verify against `SalesInvoiceFormPage`/sales shell.
- Whether `invoice_rules.dart` belongs in `features/customers/calculations/` or `features/sales/calculations/` (avoid duplication with any existing sales rules).
- Payments-by-customer query param name (`customerId` vs `customer_id`) — confirm against `server/src/controllers/paymentsController.ts`.
- Statement A4 print: include now (pdf/printing) or defer (web's is a stub).
