## 1. Data layer

- [ ] 1.1 Add `ApiEndpoints.reportCustomerStatements = '/reports/customer-statements'` to `lib/core/api/endpoints.dart` (report constants group, next to `reportTopDebtors`).
- [ ] 1.2 Add `CustomerStatementRow` model to `lib/data/models/report.dart` — all 12 fields (`customer_id`, `customer_name`, `customer_code`, `opening_balance`, `total_debits`, `total_credits`, `closing_balance`, `invoice_count`, `total_amount`, `paid_amount`, `balance`, `last_invoice_date`) with `fromJson` using the file's `asInt`/`asNum`/`asString` helpers and numeric `?? 0` / string `?? ''` fallbacks.
- [ ] 1.3 Add `customerStatements({String? fromDate, String? toDate, int? customerId})` to `ReportRepository` in `lib/data/repositories/report_repository.dart` — `GET reportCustomerStatements` with `fromDate`/`toDate` (always sent when non-null) and `customerId` (sent only when non-null); parse `data['statements']` into `List<CustomerStatementRow>` (mirror the `TopDebtorRow` parsing style).
- [ ] 1.4 Add to `lib/features/reports/report_providers.dart`: `reportStatementsFromDateProvider` (default `DateTime(now.year, now.month - 3, now.day)` — web parity, not the usual last-month default), `reportStatementsToDateProvider` (default today), `reportStatementsCustomerIdProvider` (`StateProvider<int?>`), a small `customersForReportProvider` (FutureProvider over `GET /customers`, id + name), and `customerStatementsReportProvider` (FutureProvider watching all three, omitting `customerId` when null).

## 2. l10n

- [ ] 2.1 Add to `lib/l10n/en.arb` and `lib/l10n/ur.arb`: `reportsOpeningbalance` ("Opening Balance"), `reportsTotaldebits` ("Total Debits"), `reportsTotalcredits` ("Total Credits"), `reportsClosingbalance` ("Closing Balance"), `reportsTotalamount` ("Total Amount"), `reportsPaidamount` ("Paid Amount"), `reportsLastinvoicedate` ("Last Invoice Date"), `reportsAllcustomers` ("All Customers").
- [ ] 2.2 Run `flutter gen-l10n` so `AppLocalizations` picks up the new keys (build regenerates, but run explicitly to verify no errors).

## 3. Screen

- [ ] 3.1 Create `lib/features/reports/customer_statements_report_screen.dart` — `CustomerStatementsReportScreen` `ConsumerStatefulWidget` modeled on `top_debtors_report_screen.dart`:
  - PlutoGrid state manager fed via `removeAllRows` + `appendRows` on provider change; `setShowLoading` while loading; hidden `key` column carrying `customer_id` (hide via `hideColumn` in `onLoaded`); `noRowsWidget` = `commonNoresults`.
  - 6 columns in web order: Customer Name (semibold), Customer Code, Opening Balance, Total Debits, Total Credits, Closing Balance — currency columns via a `_moneyColumn` helper (right-aligned, `Formatters.currency`), matching `top_debtors_report_screen.dart`'s.
  - Header: title (`reportsCustomerstatementsreport`), `ReportDateRangeFilter` bound to the from/to providers, customer `SearchableSelect<int>` (options from `customersForReportProvider`, label = customer name; selection writes `reportStatementsCustomerIdProvider`, clear → null), Export CSV button.
  - `onRowDoubleTap` → open `CustomerStatementDetailDialog` with the row (by hidden key).
  - `ScreenErrorPanel` with retry on `AsyncError`; CSV disabled while loading or empty.

## 4. Detail dialog

- [ ] 4.1 Create `lib/features/reports/customer_statement_detail_dialog.dart` — `customerStatementDetailDialog(context, row)` mirroring `top_debtor_detail_dialog.dart`: full-width dialog, title = customer name, close/X + Escape dismiss; read-only field rows: Customer Code, Invoice Count, Opening Balance, Total Debits, Total Credits, Closing Balance, Total Amount, Paid Amount, Balance, Last Invoice Date (`Formatters.date`).

## 5. CSV export

- [ ] 5.1 Add `buildCustomerStatementsCsv(AppLocalizations, List<CustomerStatementRow>)` to `lib/core/utils/csv_export.dart` via `_buildGridCsv` — columns in web export order: Customer Name, Customer Code, Opening Balance, Total Debits, Total Credits, Closing Balance (currency-formatted).
- [ ] 5.2 Wire the screen's export to `saveCsv` with `csvSuggestedName('customer-statements')` and the shared `reportsExported` / `reportsExportfailed` toasts.

## 6. Route wiring & verification

- [ ] 6.1 Register `'customer-statements' => const CustomerStatementsReportScreen()` in the reports sub-route switch in `lib/app.dart` (add the import; keep the dashboard entry as-is — it already lists the slug).
- [ ] 6.2 Run `flutter analyze` — zero new issues (also `dart analyze` per PORTING.md §14).
- [ ] 6.3 Run the app (server on :3011), open `/reports/customer-statements`, verify: default last-3-months→today range loads all customers' rows; date change refetches; customer filter narrows to one and clears back; double-tap opens the detail dialog; Export CSV saves a file; stopping the server shows the error panel with a working retry.