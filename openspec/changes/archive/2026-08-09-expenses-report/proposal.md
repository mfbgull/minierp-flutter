## Why

The Flutter port has 12 of the 18 report screens (PORTING.md §11), but the **Expenses report** (`/reports/expenses`) still renders the shared "coming soon" `ModulePlaceholderScreen`. The report is a standard `GET /reports/expenses` endpoint with a documented result shape — porting it closes the last financial-category gap on the reports dashboard.

## What Changes

- New `ExpensesReportScreen` widget (`lib/features/reports/expenses_report_screen.dart`) rendered at the `/reports/expenses` route, replacing the placeholder.
- Reads `GET /reports/expenses?fromDate&toDate&category` — the exact shape from `server-reference/Reports.ts` `getExpenseReport`: `{ summary: {totalAmount, totalExpenses, averageAmount}, expenses: [...], categoryBreakdown: [...] }`.
- Date-range filter (last month → today default, shared `ReportDateRangeFilter` widget) plus optional category dropdown (options from the existing `GET /expenses/categories` provider). Category and date changes refetch automatically.
- KPI strip: Total Expenses | Total Records | Average Expense.
- PlutoGrid with the 10 web columns (expense no, category, description, amount, date, payment method, reference no, vendor, project, status); expense-status badge via existing `expenseStatusLabel`.
- Category breakdown chips (name, total, count).
- CSV export via the shared `saveCsv` helper (same pattern as purchase-summary; adds `buildExpensesReportCsv`).
- Data plumbing: `ExpensesReport`-style models in `report.dart`, `expenses()` method on `ReportRepository`, `expensesReportProvider` + date/category filter providers in `report_providers.dart`, `ApiEndpoints.reportExpenses`.
- 2 new l10n keys (`reportsTotalrecords`, `reportsAverageexpense`) in `en.arb` + `ur.arb`.

Non-goals (deliberate scope cuts vs the web page):
- **No mobile card list** — desktop-only port (PORTING.md §1 excludes mobile).
- **No detail dialog** — the web's expense detail overlay is mobile-only; desktop shows the full row in the grid.
- **No vendor filter** — the web sends `vendor` but the controller reads only `fromDate`/`toDate`/`category`; it's a no-op like the purchase-summary port noted.
- **No PDF/Excel export** — Flutter report ports export CSV; PDF is out of scope for reports.

## Capabilities

### New Capabilities

- `reports-expenses`: Expenses report screen — date-range and category filtering, expense grid, KPI summary, category breakdown, and CSV export backed by `GET /reports/expenses`.

### Modified Capabilities

<!-- None — no spec-level requirements change on existing capabilities. -->

## Impact

- `lib/app.dart` — register `'expenses'` in the reports sub-route switch (route already exists, currently falls to placeholder).
- `lib/core/api/endpoints.dart` — add `reportExpenses = '/reports/expenses'`.
- `lib/data/models/report.dart` — add `ExpensesReport` wrapper + `ExpensesReportRow` + `ExpenseCategoryBreakdown` models.
- `lib/data/repositories/report_repository.dart` — add `expenses()` method (`fromDate`/`toDate`/`category` params).
- `lib/features/reports/report_providers.dart` — date providers + `expensesReportProvider`.
- `lib/core/utils/csv_export.dart` — add `buildExpensesReportCsv`.
- `lib/l10n/en.arb` + `ur.arb` — 2 new keys.
- No server changes (endpoint exists and is unchanged).