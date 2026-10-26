# Flutter report audit evidence

Primary deliverable: `accounting-audit/workstreams/flutter-reports.md`.

Findings: `accounting-audit/findings/F-040/finding.md`, `F-041/finding.md`, `F-042/finding.md`, `F-043/finding.md`.

| Criterion | Invocation | Binary observable | Artifact |
|---|---|---|---|
| Candidate inventory covers declared patterns across production Dart | `python3 accounting-audit/tests/flutter_inventory.py` | Exit0;431 files;223 candidate surfaces;4529 figure lines;2468 support lines | `accounting-audit/evidence/flutter-inventory-run.log`, `.exit`, `flutter-inventory-summary.json`, `flutter-figures.csv`, `flutter-surfaces.csv`, `flutter-support.csv` |
| Missing BS categories, malformed CSV, duplicated payroll deduction reproduced | `flutter test --no-pub accounting-audit/tests/flutter_reports_test.dart --reporter expanded` | Exit1; exactly3 application-behavior assertions fail | `accounting-audit/evidence/flutter-report-regressions.log`, `.exit`, `flutter-balance-sheet-widget.json`, `flutter-balance-sheet.png`, `flutter-balance-sheet.csv`, `flutter-csv-observation.json`, `flutter-salary-carryover-widget.json` |
| Actual backend responses retain independent expected numbers; real P&L and BS widgets show them; refresh action reloads | `FLUTTER_AUDIT_ORACLE=accounting-audit/evidence/oracle-run-AbsZeT/api-events.json flutter test --no-pub accounting-audit/tests/flutter_oracle_reports_test.dart --reporter expanded --exclude-tags known-defect` | Exit0;3 tests pass;15 numeric mappings exact;P&L provider loads1→2 after tap | `accounting-audit/evidence/flutter-oracle-replay.log`, `.exit`, `flutter-oracle-models.json`, `flutter-oracle-pnl-widget.json`, `flutter-oracle-balance-widget.json` |
| P&L expense breakdown fails to explain authoritative total | Same oracle invocation with `--tags known-defect` | Exit1; expected20 actual10 | `accounting-audit/evidence/flutter-pnl-breakdown.log`, `.exit`, `flutter-pnl-breakdown.json`; mounted output `flutter-oracle-pnl-widget.json` |
| Audit harness obeys static checks | `flutter analyze --no-pub accounting-audit/tests` | Exit0;No issues found | `accounting-audit/evidence/flutter-harness-analyze.log`, `.exit` |
| Referenced evidence exists, nonempty and has correct exit/result observables | `python3 accounting-audit/tests/flutter_verify_evidence.py` | Exit0; all checks true | `.omo/evidence/flutter-reports/verification.json` |

No production fix or existing test edit. Failing audit tests are intentional evidence of unfixed defects and live outside normal `test/`. Full suites/static quick execution are root-owned, not certified by this index. Inventory is candidate coverage, not a universal screen verification claim. Four actual confirmed defects, not four fixed defects.

F-041 detector follow-up: `flutter test --no-pub accounting-audit/tests/flutter_reports_test.dart --reporter expanded --plain-name F-041`; a CSV quote-state parser first accepts correctly quoted commas and doubled quotes, then rejects the actual unescaped report value. Evidence: `accounting-audit/evidence/flutter-csv-regression.log/.exit`.

