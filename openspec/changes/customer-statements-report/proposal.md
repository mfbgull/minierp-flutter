## Why

The reports hub (`lib/features/reports/reports_dashboard_screen.dart`) lists 18 report cards; 13 are ported. `/reports/customer-statements` — the AR-category summary of every customer's opening balance, debits, credits, and closing balance over a date range — still renders the shared "coming soon" `ModulePlaceholderScreen`, leaving the AR group the only partially-ported category (ar-aging, top-debtors, dso are in; customer-statements is not).

## What Changes

- New `CustomerStatementsReportScreen` widget (`lib/features/reports/customer_statements_report_screen.dart`) rendered at the `/reports/customer-statements` route, replacing the placeholder.
- Reads `GET /reports/customer-statements?fromDate&toDate&customerId` — exact shape from `server-reference/Reports.ts` `getCustomerStatements`: `{ statements: [{ customer_id, customer_name, customer_code, opening_balance, total_debits, total_credits, closing_balance, invoice_count, total_amount, paid_amount, balance, last_invoice_date }] }`.
- Date-range filter (default **last 3 months → today**, mirroring the web page's initial state — the endpoint tolerates omitted dates, but the port always sends them) plus an optional **customer filter** (dropdown of `GET /customers`, empty = "All Customers", omits the `customerId` param). Both refetch automatically via provider wiring.
- Read-only PlutoGrid with the web's 6 columns: Customer Name, Customer Code, Opening Balance, Total Debits, Total Credits, Closing Balance (currency-formatted, right-aligned).
- Double-tap detail dialog per row (the pattern already used by top-debtors/purchase-summary/low-stock): customer code, invoice count, total amount, paid amount, balance, last invoice date.
- CSV export via the shared `saveCsv` helper (`buildCustomerStatementsCsv` in `csv_export.dart`).
- Data plumbing: `CustomerStatementRow` model in `report.dart`, `customerStatements()` on `ReportRepository`, `reportCustomerStatements` endpoint constant, `customerStatementsReportProvider` + from/to/customer filter providers in `report_providers.dart`.
- ~8 new l10n keys (`reportsOpeningbalance`, `reportsTotaldebits`, `reportsTotalcredits`, `reportsClosingbalance`, `reportsTotalamount`, `reportsPaidamount`, `reportsLastinvoicedate`, `reportsAllcustomers`) in `en.arb` + `ur.arb`.

Non-goals (deliberate scope cuts vs the web page, same precedents as the expenses port):
- **No PDF/Excel export** — Flutter report ports ship CSV only.
- **No mobile statement-card list** — desktop-only port (PORTING.md §1 excludes mobile).
- **No per-statement line-level drill-down** — this report is a per-customer summary; the line-level statement already exists as the ported `CustomerStatementScreen` at `/customers/:id/statement` and is out of scope here.

## Capabilities

### New Capabilities

- `reports-customer-statements`: Customer statements report screen — date-range and optional per-customer filtering, read-only statements grid, per-row detail dialog, and CSV export backed by `GET /reports/customer-statements`.

### Modified Capabilities

<!-- None — no spec-level requirement changes on existing capabilities (`openspec/specs/` currently only holds `reports-expenses`). -->

## Impact

- `lib/app.dart` — register `'customer-statements'` in the reports sub-route switch (route already exists, currently falls to the placeholder).
- `lib/core/api/endpoints.dart` — add `reportCustomerStatements = '/reports/customer-statements'`.
- `lib/data/models/report.dart` — add `CustomerStatementRow` (parses all 12 snake_case fields; `customer_id` → row key for the detail dialog).
- `lib/data/repositories/report_repository.dart` — add `customerStatements({String? fromDate, String? toDate, int? customerId})` returning `List<CustomerStatementRow>`.
- `lib/features/reports/report_providers.dart` — from/to `StateProvider<DateTime>` (default last-3-months → today), `reportStatementsCustomerIdProvider` (`StateProvider<int?>`), and `customerStatementsReportProvider` (FutureProvider watching all three).
- `lib/features/reports/customer_statements_report_screen.dart` — new screen (mirrors `top_debtors_report_screen.dart` structure).
- `lib/features/reports/customer_statement_detail_dialog.dart` — new double-tap detail dialog (mirrors `top_debtor_detail_dialog.dart`).
- `lib/core/utils/csv_export.dart` — add `buildCustomerStatementsCsv`.
- `lib/l10n/en.arb` + `lib/l10n/ur.arb` — ~8 new keys; `flutter gen-l10n` regenerates `AppLocalizations`.

**No backend change** — the endpoint, controller params (`customerId`, `fromDate`/`toDate` — all optional server-side), and result shape are verified against `server-reference/reportsController.ts` + `Reports.ts`. **No new dependencies** — `pluto_grid`, `riverpod`, existing widgets only. **No migration.**
