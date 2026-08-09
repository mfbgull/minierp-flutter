## Context

The Flutter port follows PORTING.md: the Node/Express/SQLite backend runs unchanged; every report screen is a thin client over a pre-existing endpoint. The `/reports/<slug>` sub-route in `lib/app.dart` already exists — it renders real screens for the ported reports and falls back to `ModulePlaceholderScreen` for the rest. `customer-statements` is one of the remaining placeholders (the only gap in the AR category).

The server side is fully in place and unchanged by this change:
- `GET /reports/customer-statements` (`server-reference/reportsController.ts`) reads optional `customerId`, `fromDate`/`startDate`, `toDate`/`endDate` — all three optional (no 400 path; the web always sends a range, so the port does too).
- Result shape (`server-reference/Reports.ts` `getCustomerStatements`): `{ statements: [{ customer_id, customer_name, customer_code, opening_balance, total_debits, total_credits, closing_balance, invoice_count, total_amount, paid_amount, balance, last_invoice_date }] }`. When a `customerId` is given the query filters to that customer; `opening_balance`/`balance` come from `customers.opening_balance` + summed invoices.

Existing building blocks to reuse:
- `top_debtors_report_screen.dart` is the exact skeleton to copy: `ConsumerStatefulWidget` + `PlutoGridStateManager` fed via `removeAllRows()` + `appendRows()`, hidden key column, `onRowDoubleTap` → detail dialog, `ScreenErrorPanel` on `AsyncError`, `saveCsv` export via a per-report CSV builder.
- `top_debtor_detail_dialog.dart` — the double-tap dialog pattern to mirror.
- `ReportDateRangeFilter` (`lib/widgets/date_picker_helpers.dart`) — shared From/To row writing non-nullable `StateProvider<DateTime>`s.
- `SearchableSelect<T>` (`lib/widgets/searchable_select.dart`) — the shared customer picker used across forms, fed by the existing customers list.
- `Formatters.currency/date/number`, `csvSuggestedName`, `saveCsv`, `screen_error_panel.dart`, l10n keys `fieldsCustomer`, `fieldsCustomerCode`, `reportsInvoicecount`, `reportsBalance`.

## Goals / Non-Goals

**Goals:**
- `/reports/customer-statements` renders a complete read-only customer statements report: grid, optional customer filter, date filter, double-tap detail dialog, CSV export.
- Follow the established report wiring exactly — endpoint constant → model → repository → providers → screen → route registration → CSV builder.

**Non-Goals:**
- No server changes (endpoint and controller exist and stay untouched).
- No mobile statement-card list (desktop-only port per PORTING.md §1).
- No PDF/Excel export (report ports ship CSV only — same as expenses/top-debtors).
- No drill-down into a per-customer line ledger — that surface already exists as `CustomerStatementScreen` at `/customers/:id/statement`.

## Decisions

### D1 — Screen mirrors `TopDebtorsReportScreen`
Copy the top-debtors structure 1:1: `ConsumerStatefulWidget`, a `PlutoGridStateManager` fed via `removeAllRows()` + `appendRows()` on provider change (the required Pluto pattern — the grid reads `rows` only in `initState`, and the passed list must stay mutable), hidden `key` column carrying the row's `customer_id` to the detail dialog, `onRowDoubleTap` → `CustomerStatementDetailDialog`, and `ScreenErrorPanel` on `AsyncError`.
**Why:** identical mechanics already solved; no new grid machinery.
**Alternative rejected:** `ref.watch(...).when(...)` rebuilding the grid — broken for PlutoGrid because `rows` is initState-only.

### D2. Query params `fromDate`/`toDate`/`customerId`
Follow the existing repository methods (`salesSummary`, `purchaseSummary` use camelCase). The controller accepts `fromDate || startDate` and `toDate || endDate`, so camelCase hits the same path and matches sibling ports. `customerId` is sent only when a customer is selected (provider value non-null), matching the web's `params.append('customerId', ...)` only in that branch.

### D3. Default range: last 3 months → today (web parity)
The web page's `CustomersSalesReport` initializes `fromDate = now - 3 months`. All sibling report ports default to last-month→today only because their web pages do; here the web page's own default is 3 months, so the from-provider defaults to `DateTime(now.year, now.month - 3, now.day)`. The to-provider defaults to today.
**Why:** keeps the port observationally identical to the reference app.
**Alternative rejected:** last-month→today for "consistency" — the web report the user is reviewing shows 3 months.

### D4. No KPI strip
Unlike purchase-summary/expenses/sales-summary, the web `CustomerStatementsReport` renders **no** summary strip — just a grid (the AR-category KPIs live on the dashboard hub). So the port ships no KPI row; the header holds the title, filters, and export button only.
**Why:** port the visible surface, not invented chrome.

### D5. Model — single `CustomerStatementRow`
The endpoint returns `{ statements: [...] }` — a wrapper object with one key, so the model is a single row class; the repository parses `data['statements']` into `List<CustomerStatementRow>`, mirroring the `TopDebtorRow` pattern (bare-array style, `_getList` style helper) rather than a wrapper `CustomerStatementsReport` class. All 12 fields map from snake_case JSON with `asInt`/`asNum`/`asString` fallbacks; `customer_id` is kept for the detail-dialog row key.

### D6. Customer filter — `SearchableSelect<int>`
Options from the existing customers list. Decision: which source?
- **Chosen:** a `StateProvider<int?>` (`reportStatementsCustomerIdProvider`) + a `FutureProvider` over `GET /customers` (mirrors the web's `useQuery(['customers'])`). The list is small (`limit 1000` pattern used elsewhere), refetch-on-open is not needed.
- **Rejected:** `SearchableSelect<Customer>` bound directly to the CRUD customers screen's provider — that provider is screen-local to the customers feature; importing it into reports creates a cross-feature coupling the other report ports avoid. The web page independently fetches `GET /customers` too.
Selection writes the provider; clearing sets it to null (the shared widget's `onChanged: T?` already nulls on clear). The report provider watches it, so filter change refetches automatically.

### D7. Detail dialog renders from grid row data
`CustomerStatementDetailDialog` — mirror `top_debtor_detail_dialog.dart`: full-width, close/X header, read-only fields (Customer Code, Invoice Count, Total Debits, Total Credits, Opening Balance, Closing Balance, Total Amount, Paid Amount, Balance, Last Invoice Date via `Formatters.date`). Server sends `last_invoice_date` (the web modal's `last_payment_date` is never populated by the server — always '-' there); the port shows the real field labeled "Last Invoice Date".
### D8. CSV export
`buildCustomerStatementsCsv(AppLocalizations, List<CustomerStatementRow>)` in `csv_export.dart` via the existing `_buildGridCsv` helper — columns in web export order: Customer Name, Customer Code, Opening Balance, Total Debits, Total Credits, Closing Balance. Wired to `saveCsv` + `csvSuggestedName('customer-statements')` + `reportsExported`/`reportsExportfailed` toasts. Disabled while loading or empty.

### D9 — Endpoint constant
Add `ApiEndpoints.reportCustomerStatements = '/reports/customer-statements'` alongside the other report constants.

### D10 — l10n keys
New keys (en + ur): `reportsOpeningbalance` ("Opening Balance"), `reportsTotaldebits` ("Total Debits"), `reportsTotalcredits` ("Total Credits"), `reportsClosingbalance` ("Closing Balance"), `reportsTotalamount` ("Total Amount"), `reportsPaidamount` ("Paid Amount"), `reportsLastinvoicedate` ("Last Invoice Date"), `reportsAllcustomers` ("All Customers"). Existing keys reused: `reportsCustomerstatementsreport` (title), `fieldsCustomer`, `fieldsCustomerCode`, `reportsInvoicecount`, `reportsBalance`, `fieldsFromdate`/`fieldsTodate`, `reportsExported`, `reportsExportfailed`, `commonNoresults`.

## Risks / Trade-offs

- **Server always returns every customer even with an empty range** — the LEFT JOIN produces a row per customer with zeroed aggregates; the grid shows all customers with zero totals rather than the no-results text when a narrow range matches nothing. → Matches the web behavior exactly (same query server-side); no mitigation needed.
- **Urdu l10n gaps** — `ur.arb` is already behind `en.arb` (known, PORTING.md §9); missing keys fall back to English, non-blocking.
- **PlutoGrid state quirks** — the mutable-rows/`onLoaded` constraints are already handled by the sibling screens; reuse that exact pattern rather than inventing a new one.

## Migration Plan

Client-only change: no DB migration, no server deployment, no API contract change. The route degrades gracefully to the placeholder if reverted; the diff is additive to one screen slot.

## Open Questions

None — endpoint shape, param contract (verified against `server-reference/reportsController.ts` + `Reports.ts`), and all reuse points confirmed against the ported siblings.