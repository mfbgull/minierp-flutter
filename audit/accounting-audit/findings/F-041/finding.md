# F-041 — Balance-sheet CSV splits currency amounts into extra columns

> Current assessment, 2026-10-26: this report preserves its historical audit snapshot. See [remediation status](../../remediation/STATUS.md) for current source verification, fixes, tests and remaining limits.

- Severity: MEDIUM; status: FAIL, reproduced.
- Scope: balance-sheet CSV export.
- Root cause: `lib/core/utils/csv_export.dart:403`–`:453` interpolates currency/date text directly into comma-separated rows. Unlike the shared `buildGridCsv` path used by other reports, these rows do not escape commas. The exact cash path is line 410.
- Independent expectation: a cash amount 1,000 in the three-column sheet must decode as `["Cash", "", "Rs. 1,000.00"]`.
- Actual: exported line `Cash,,Rs. 1,000.00` decodes as four cells `["Cash", "", "Rs. 1", "000.00"]`. The date heading also includes an unquoted comma in English. This is an actual generated export, not a hypothetical parsing issue.
- Impact: opening the report in a CSV consumer splits the leading thousands from the amount and changes the sheet shape; exported amounts are no longer one cell.
- Reproduction: `flutter test accounting-audit/tests/flutter_reports_test.dart --reporter expanded`; scenario `F-041 balance sheet CSV preserves monetary values in one cell`; exit 1 on cell-list comparison.
- Artifacts: `accounting-audit/evidence/flutter-balance-sheet.csv`, `accounting-audit/evidence/flutter-csv-observation.json`, `accounting-audit/evidence/flutter-report-regressions.log`, `accounting-audit/evidence/flutter-report-regressions.exit`.
- Recommended correction: route each balance-sheet row through the existing CSV escaping encoder, including heading/date rows. Regression should parse the full CSV with a CSV parser and assert stable column counts and exact currency cells for positive/negative values above 999, multi-million values, and quoted symbols.
- Audit detector review: the final test uses a CSV quote-state parser, not naive comma splitting; self-checks accept a correctly quoted thousands separator and doubled quotation marks. The targeted re-run is `flutter test --no-pub accounting-audit/tests/flutter_reports_test.dart --reporter expanded --plain-name F-041`; captured in `accounting-audit/evidence/flutter-csv-regression.log/.exit`. A correctly escaped production row can pass this test.
- Limit: this finding applies to the balance-sheet builder. It does not assert every other report export is affected.
