# F-040 — Balance sheet drops nonzero asset and liability categories

> Current assessment, 2026-10-26: this report preserves its historical audit snapshot. See [remediation status](../../remediation/STATUS.md) for current source verification, fixes, tests and remaining limits.

- Severity: MEDIUM (misleading financial presentation with correct aggregate API totals and no demonstrated underlying corruption); status: Confirmed defect, reproduced.
- Scope: Flutter balance-sheet screen and its CSV; no database corruption demonstrated.
- Root cause: `lib/data/models/report.dart:709` and `:731` omit `assets.other`, `liabilities.tax_payable`, and `liabilities.other` even though `server/src/models/Reports.ts:531` returns them. `lib/features/reports/balance_sheet_report_screen.dart:107` renders only inventory/AR/cash and AP. `lib/core/utils/csv_export.dart:401` repeats the incomplete presentation.
- Independent expectation: cash 1,000 + inventory 200 + receivables 300 + other assets 400 = total assets 1,900. AP 500 + tax 60 + other liabilities 70 = total liabilities 630. Equity 1,270 balances the sheet. Every nonzero category must be visible or grouped under a visible reconciling line.
- Actual mounted widget: components displayed for assets sum to 1,500 but total reads 1,900; liabilities show AP 500 but total 630. No texts for 400, 60, or 70. The widget still displays `Balanced` based on the server flag. The artifact contains all rendered Text widgets and input JSON.
- Financial impact: customer credits, loan receivables, input tax and prepayments can be hidden in other assets; tax payable, unpaid expenses, unapplied receipts and production overhead can be hidden in liabilities. The aggregate totals may be correct while the visible composition cannot reconcile.
- Reproduction: `flutter test accounting-audit/tests/flutter_reports_test.dart --reporter expanded`; scenario `F-040 balance sheet displays all nonzero API categories`; exit 1 with expected text Rs.400.00 absent. Uses synthetic balanced API-shaped data and the actual model and mounted screen, not a live database.
- Artifacts: `accounting-audit/evidence/flutter-balance-sheet-widget.json`, `accounting-audit/evidence/flutter-balance-sheet.csv`, `accounting-audit/evidence/flutter-report-regressions.log`, `accounting-audit/evidence/flutter-report-regressions.exit`.
- Recommended correction: preserve the three fields in typed models, render clearly labeled reconciling rows, export them consistently, and retain the failing widget regression. Add API-to-widget cases for nonzero supplier prepayments, tax payable and unpaid production overhead.
- Limit: this proves display loss for valid backend response categories; it does not certify all balance-sheet backend formulas or historical balances.

