## 1. Data layer

- [x] 1.1 Add `ApiEndpoints.reportExpenses = '/reports/expenses'` to `lib/core/api/endpoints.dart` (report constants group).
- [x] 1.2 Add `ExpensesReport`, `ExpensesReportRow`, `ExpensesReportSummary`, `ExpenseCategoryBreakdown` models to `lib/data/models/report.dart` — `fromJson` factories with `[]`/`{}` fallbacks; parse `expenses` / `summary` / `categoryBreakdown` keys.
- [x] 1.3 Add `expenses({required String fromDate, required String toDate, String? category})` to `ReportRepository` in `lib/data/repositories/report_repository.dart` (`GET reportExpenses` with `fromDate`/`toDate`/`category` params, parse to `ExpensesReport`).
- [x] 1.4 Add to `lib/features/reports/report_providers.dart`: `reportExpensesFromDateProvider` / `reportExpensesToDateProvider` (default: first day of last month → today, `isoDate`-formatted) and `reportExpensesCategoryProvider` (`StateProvider<String?>`), plus `expensesReportProvider` (FutureProvider watching the three, calling repository `expenses()`).

## 2. l10n

- [x] 2.1 Add `reportsTotalrecords` ("Total Records") and `reportsAverageexpense` ("Average Expense") to `lib/l10n/en.arb` and `lib/l10n/ur.arb`.
- [x] 2.2 Run `flutter gen-l10n` so `AppLocalizations` picks up the new keys (build integration regenerates, but run explicitly to verify no errors).

## 3. Screen

- [x] 3.1 Create `lib/features/reports/expenses_report_screen.dart` — `ExpensesReportScreen` `ConsumerStatefulWidget` modeled on `purchase_summary_report_screen.dart`:
  - PlutoGrid state manager fed via `removeAllRows` + `appendRows` on provider change; `setShowLoading` while loading; `noRowsWidget` = `commonNoresults`.
  - 10 columns in web order (Expense No, Category, Description, Amount, Date, Payment Method, Reference No, Vendor, Project, Status) with currency/date renderers and `StatusBadge` + `expenseStatusLabel`.
  - Header: title (`reportsExpensesreport`), `ReportDateRangeFilter` bound to the from/to providers, category dropdown (options from `expenseCategoriesProvider`, value from `reportExpensesCategoryProvider`), Export CSV button.
  - KPI strip: Total Expenses | Total Records | Average Expense from `summary` (server values verbatim).
  - Category breakdown chips (name, currency total, count).
  - `ScreenErrorPanel` with retry on `AsyncError`; export disabled while loading or empty.

## 4. CSV export

- [x] 4.1 Add `buildExpensesReportCsv(AppLocalizations, ExpensesReport)` to `lib/core/utils/csv_export.dart` — columns per the web export (Expense No, Date, Category, Description, Vendor, Reference No, Payment Method, Project, Amount, Status), reusing `sanitizeCsvCell`, `Formatters`, `expenseStatusLabel`.
- [x] 4.2 Wire the screen's export to `saveCsv` with `csvSuggestedName('expenses-report')` and the shared `reportsExported`/`reportsExportfailed` toasts.

## 5. Route wiring & verification

- [x] 5.1 Register `'expenses' => const ExpensesReportScreen()` in the reports sub-route switch in `lib/app.dart` (add the import).
- [x] 5.2 Run `flutter analyze` — zero new issues (also `dart analyze` per PORTING.md §14).
- [ ] 5.3 Run the app (server on :3011), open `/reports/expenses`, verify: default last-month→today range loads the grid + KPI strip + breakdown; date change refetches; category filter narrows; Export CSV saves a file; a stop on the server shows the error panel with retry.