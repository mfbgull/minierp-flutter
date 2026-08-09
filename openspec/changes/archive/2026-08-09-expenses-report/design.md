## Context

The Flutter port follows PORTING.md: the Node/Express/SQLite backend runs unchanged, every report screen is a thin client over a pre-existing endpoint. The `/reports/<slug>` sub-route in `lib/app.dart` already exists — it renders real screens for the 12 ported reports and falls back to `ModulePlaceholderScreen` ("coming soon") for the rest. `/reports/expenses` is one of the remaining placeholders.

The server side is fully in place and unchanged by this change:
- `GET /reports/expenses` (`server-reference/reportsController.ts`) reads `fromDate` + `toDate` (400 without either) and optional `category`. It reads only those three — the web page's `vendor` query parameter is a no-op server-side.
- Result shape (`server-reference/Reports.ts` `getExpenseReport`): `{ summary: { totalAmount, totalExpenses, averageAmount }, expenses: [{ id, expense_no, expense_category, description, amount, expense_date, payment_method, reference_no, vendor_name, project, status }], categoryBreakdown: [{ expense_category, count, total_amount }] }`.

Existing building blocks to reuse:
- `Expense` model (`lib/data/models/expense.dart`) already matches every field of an `expenses[]` row.
- `expenseCategoriesProvider` (`lib/features/expenses/expense_providers.dart`) already loads `GET /expenses/categories`.
- `expenseStatusLabel`/`expenseStatusColor` (`lib/core/utils/expense_status.dart`), the `StatusBadge` widget, and `Formatters.currency/date/number`.
- Sibling report `purchase_summary_report_screen.dart` is the exact skeleton to copy: `ConsumerStatefulWidget` + `PlutoGridStateManager` + shared `ReportDateRangeFilter` + `ScreenErrorPanel` + `saveCsv` with a per-report CSV builder in `csv_export.dart`.

## Goals / Non-Goals

**Goals:**
- `/reports/expenses` renders a complete read-only expenses report: grid, KPI strip, category breakdown, date/category filters, CSV export.
- Follow the established report wiring exactly — model → repository → provider → screen → route registration → CSV builder.

**Non-Goals:**
- No server changes (endpoint already exists and stays untouched).
- No mobile card list, no detail dialog, no vendor filter (all cut from the web page — vendor is a server no-op, the detail overlay is mobile-only, and the port is desktop-only per PORTING.md §1).
- No PDF/Excel export (report ports ship CSV only).

## Decisions

### D1 — Screen mirrors `PurchaseSummaryReportScreen`
Copy the purchase-summary structure 1:1: `ConsumerStatefulWidget`, a `PlutoGridStateManager` fed via `removeAllRows()` + `appendRows()` on provider changes (the required Pluto pattern — the grid reads `rows` only at `initState`, and the passed list must stay mutable), `ReportDateRangeFilter` wired to from/to `StateProvider`s, `ScreenErrorPanel` on `AsyncError`, and the `saveCsv` export path.
**Why:** identical mechanics already solved once; no new grid machinery.
**Alternative rejected:** `ref.watch(...).when(...)` rebuilding the grid list each build — broken for PlutoGrid because `rows` is initState-only.

### D2 — Query params `fromDate`/`toDate`/`category` (camelCase)
Follow the existing repository methods (`salesSummary`, `purchaseSummary` use camelCase). The web sends `from_date`/`to_date`, but the controller accepts both (`fromDate || from_date`), so camelCase hits the same path and stays consistent with sibling ports.

### D3 — Category filter reuses the expenses feature's provider
The dropdown options come from `expenseCategoriesProvider` (imported from `expense_providers.dart` — no new network call). Selection state lives in a new `reportExpensesCategoryProvider = StateProvider<String?>`; the report provider appends it as the `category` param. The vendor filter is omitted outright.

### D4 — Models follow the `PurchaseSummaryReport` trio pattern
Add to `lib/data/models/report.dart`:
- `ExpensesReport { rows, summary, categoryBreakdown }` parsing the `expenses` / `summary` / `categoryBreakdown` keys with `[]` / `{}` fallbacks.
- `ExpensesReportRow` — one class per row, same field names as the API JSON (matching the existing `Expense` model's fields, but standalone: the CRUD model carries `created_at`/`updated_at`/`created_by_name` the report never returns, and the report row is immutable).
- `ExpenseCategoryBreakdown { category, count, totalAmount }` from `{ expense_category, count, total_amount }`.
- `ExpensesReportSummary { totalAmount, totalExpenses, averageAmount }` from the camelCase summary keys.

### D5 — Columns match the web `ExpensesReport.tsx` columnDefs
10 columns in web order: Expense No (semibold), Category, Description (flex), Amount (currency, right-aligned, `reportsTotalcost`-style `_moneyColumn` helper), Date (locale-formatted), Payment Method, Reference No, Vendor, Project, Status (`StatusBadge` + `expenseStatusLabel`). No hidden id column — there is no double-tap detail dialog (the web's detail sheet is mobile-only).

### D6 — Summary strip + category breakdown chips
- Three KPI cells: Total Expenses (`l10n.reportsTotalexpenses` exists) | Total Records | Average Expense. Two new l10n keys: `reportsTotalrecords` and `reportsAverageexpense` in both `en.arb` and `ur.arb`.
- Breakdown: a horizontally wrapping row of chips under the strip — name, amount, count — using `l10n.reportsExpensesbycategory` ("Expenses by Category") for the section label so only the two KPI keys are new.

### D7 — Defaults and refetch wiring
Date providers default to first day of last month → today (matches the web's initial `dateRange` state). Every report date provider in this repo already follows that convention; `isoDate()` converts. Category and date providers are watched by the report provider so any change automatically refetches.

### _ — Endpoint constant
Add `ApiEndpoints.reportExpenses = '/reports/expenses'` (grouped with the other report constants in `endpoints.dart`).

## Risks / Trade-offs

- **`averageAmount` on empty data** — server computes it only when `totalExpenses > 0`, so no divide-by-zero reaches the client; the strip renders server values verbatim.
- **Urdu l10n gaps** — `ur.arb` is already behind `en.arb` (known, §9 of PORTING.md); missing Urdu keys fall back to English, non-blocking.
- **PlutoGrid state quirks** — the mutable-rows/`onLoaded` constraints are already handled in the sibling screens; reuse the exact pattern rather than inventing a new one.

## Migration Plan

Client-only change: no DB migration, no server deployment, no API contract change. The route degrades gracefully to the placeholder if reverted; the diff is additive to one screen slot.

## Open Questions

None — endpoint shape, param contract, and all reuse points were verified against `server-reference/` and the ported screens.