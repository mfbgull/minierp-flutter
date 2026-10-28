# Verification ledger

Baseline: `843322e3c01adcfa13f7d40669487c77f04c532e` plus the source snapshot in `SOURCE-MANIFEST.json`.
Runs span 2026-10-26–27, Asia/Karachi. During verification, no commit, push, deployment, real-data repair,
baseline update, skipped valid test or CI-gate change was performed.
Gull subsequently authorized commit and push; delivery is recorded in Git history.

## Current final-source results

All executed final commands below exited0. Independent review is **CLEAR / APPROVE**
within this remediation scope; see [FINANCIAL-REVIEW.md](FINANCIAL-REVIEW.md).
These results certify the tested scope, not every financial workflow.

| Command | completed result | retained evidence |
|---|---|---|
| `server/ npm test -- --maxWorkers=2 --workerIdleMemoryLimit=1024MB --coverage --coverageReporters=json --coverageReporters=text-summary` with `NODE_OPTIONS=--max-old-space-size=2048` |252/252 suites,2002/2002 tests;2057.547s; no heap failure or late-log warning | `server-post-extraction.log`, `server-post-extraction.exit` |
| `flutter test --no-pub --reporter compact` |1042 passed;26m50s; explicit exit0 | `flutter-clean.log`, `flutter-clean.exit` |
| `scripts/check.sh --quick` | typecheck, lint, pinned Fallow, Flutter analyze and l10n drift all passed | `quick-complete.log`, `quick-complete.exit` |
| six focused post-extraction count/dependency suites |60 tests passed, including A–J invariants | `count-extraction.log` |
| guarded `server/ npm run verify:reversal-rules` after extraction |79 passed,0 failed | `reversal-final-79.log`, `standalone-db-guard.txt` |
| `git diff --check` | passed | final working-tree check |

The exact final source/test hashes are in `SOURCE-MANIFEST.json`; rechecking them
after the full run found no mismatch. Final coverage is statements77.32%,
branches72.11%, functions83.28%, lines79.00%. The retained
`server-coverage-final.json.gz` decompresses byte-for-byte to the coverage used by
the final gate; raw JSON SHA-256:
`3ac843ed4a0dcf932419493d852cf53138e0840cf8ed07922444208562d03726`.
CI configuration, Fallow baselines/thresholds, dependency manifests/locks and
`scripts/check.sh` are unchanged. The temporarily paused graph indexer was resumed.

The monolithic full `scripts/check.sh` attempt was interrupted and is not claimed
as a successful command. Both complete affected-side suites and every unchanged
quick gate were subsequently completed separately; they were not repeated merely
to obtain a second monolithic run after equivalent component verification.

## Targeted red/green history

Commands prefixed `server/` below ran with that working directory; Flutter and
`scripts/check.sh` ran at repository root. Exact test arguments also appear at the
start/end of their retained logs. The fixtures use the guards documented in
[SAFETY.md](SAFETY.md).

| Command / seam | result | evidence |
|---|---|---|
| `server/ npm test -- --runInBand auditCreditOwnership.test.ts` before initial fix | exit1;2 failed; expected409, actual200 | F-002-red.log |
| `server/ npm test -- --runInBand posPayments.test.ts` before fix | exit1;1 failed,22 passed; explicit0 expected400, actual201 | F-073-red.log |
| `server/ npm test -- --runInBand auditCreditOwnership.test.ts posPayments.test.ts --detectOpenHandles` | exit0;2 suites,25 tests passed | critical-green.log |
| `server/ npm test -- --runInBand auditStockRemediation.test.ts` red phases | exit1; partial correction, mixed-layer restoration, negative allocation reproduced; fixture limitations below | stock-initial-red.log; stock-red.log |
| `server/ npm test -- --runInBand auditPayrollChronology.test.ts` original phase | exit1;5 failed on economic recognition, source chronology and D15 | payroll-chronology-red.log |
| `server/ npm test -- --runInBand auditReservationHeaders.test.ts` red phase | exit1;3 failed; replay/null identity and header status | controls-red.log |
| `server/ npm test -- --runInBand invoiceCancelReversal.test.ts auditPayrollChronology.test.ts --testNamePattern 'F-070\|F-043'` | exit1;2 failed;10 intentionally unselected by filter | report-errors-red.log |
| `server/ npm test -- --runInBand auditPayrollChronology.test.ts auditStockRemediation.test.ts` after large-advance/count fixes | exit0;2 suites,12 tests passed, with A–J/extended fixtures and per-entry assertions | payroll-stock-green.log |
| dedicated `original surplus valuation` scenario | exit0;1 passed,5 intentionally unselected; final batch20, inventory delta20 | snapshot-verification.log |
| dedicated sub-cent salary / original surplus red | exit1;2 failed,12 unselected; create accepted0.001; surplus correction rejected500 before valuation assertion | review-regressions-red.log |
| `server/ npm test -- --runInBand auditReservationHeaders.test.ts invoiceCancelReversal.test.ts invoiceReturnVoidNeutrality.test.ts` | exit0;2 actual matching suites,12 passed; third filename matched no file | header-final.log |
| dedicated legacy-return header red | exit1;1 failed,5 unselected; header remained active | legacy-header-red.log |
| three pool ownership scenarios (partial/full/two targets) | exit0;3 passed | credit-three-target-cases.log |
| four credit suites after unsettled-ledger ownership fix | exit0;4 suites,18 passed | credit-four-suites.log |
| dedicated unsettled-ledger reuse red | exit1;1 failed,3 unselected; expected400, actual200 | ledger-credit-red.log |
| dedicated cumulative-return void red | exit1;1 failed,4 unselected; expected409, actual200 | cumulative-credit-red.log |
| credit ownership / existing offsets / purchase-return recheck | exit0;5 actual matching suites,34 passed; glob argument did not select the six invoice-return suites | credit-return-final.log |
| unsupported supplier-credit funding request | exit0;1 passed,3 unselected; existing rejection400, no payment written | supplier-controlled-verification.log |
| `flutter test --no-pub test/features/accounting_report_regressions_test.dart --reporter expanded` red phase | exit1;3 failed: salary hint, missing categories, malformed CSV | flutter-red.log |
| dedicated zero-cash dialog action before validator change | exit1;1 failed: no request submitted after tap | zero-widget-red.log |
| financial widget/report matrix | exit0;8 passed: model/render/CSV, zero-cash request, phone/desktop light/dark refresh and scroll | flutter-matrix.log; PNGs and current widget JSON/CSV in this directory |
| guarded `server/ npm run verify:reversal-rules` | exit0;79 assertions passed,0 failed | reversal-79.log |
| `scripts/check.sh --quick` first checkpoint | typecheck/lint/analyze/l10n passed; Fallow failed; no gates or baselines relaxed | quick-first.log |
| standalone `server/ npm run typecheck` after salary/snapshot fixes | exit0 | typecheck-first-final.log |

## Incomplete runs and honest limits

- The earlier full `scripts/check.sh` and selected coverage runs were interrupted.
  Partial `PASS` lines are not full-suite passes.
- The later serial full backend coverage run was explicitly stopped with exit130
  after finding a purchase-return assertion regression: the new date check ran
  before the existing net-quantity check and changed the diagnostic. The source
  check order was corrected; the valid existing assertion was retained and passed
  in the subsequent34-test run. See `server-full-stopped.log`.
- The subsequent two-worker run found three existing batch-only reservation
  compatibility failures and was stopped (exit143). New bin-delta SQL required
  a missing location identifier. Bin deltas now apply only to complete bin
  identities; batch-only reservations retain the existing metadata workflow.
  No existing assertions were relaxed. See `server-reservation-compatibility-red.log`.
- An early stock fixture leaked a feature flag into the production test and did
  not initialize the warehouse availability mirrors with its explicit bin rows.
  Those fixture defects were corrected; they are not claimed as production red
  baselines. Feature-off mixed-layer failure and omitted-item corruption were
  independently reproduced. Location surplus missing-bin and document valuation
  failures have their own retained red logs.
- The original shortage-to-surplus route rejected the correction on its invalid
  batch-source enum before the separate overwritten-snapshot cost assertion could
  run. The snapshot regression now asserts the existing20 cost policy and passes;
  no historical red result at the separate cost assertion is invented.
- A CSV test copied from the forensic audit originally retained `\r` when splitting
  standard CRLF output. The normal regression now parses the entire document with
  the project's CSV library and verifies3 columns per row; no valid test was skipped.
- Mounted widgets use real backend-shaped data and a captured fake-HTTP boundary.
  Backend economic routes are exercised independently. No complete native desktop
  Flutter-to-live-HTTP session, every print/export/mobile variant, process-crash
  recovery, multi-writer contention, or historical migration replay is certified.

## Final phase checkpoints and resolved failures

The quick gate after the completed252-suite run passed typecheck, lint, Flutter
analyze and l10n drift, but Fallow rejected3 new cognitive-complexity findings in
count posting/correction (`quick-complexity-gate.log`). No threshold or baseline
was changed. The repeated weighted-cost expression and surplus-bin loop were
mechanically extracted into the existing count-layer module. The independent
reviewer checked equivalence. The unchanged pinned Fallow command then exited0:
no new issues in97 changed files (`fallow-count-extraction.log`). Post-extraction
focused verification passed6 suites/60 tests, exit0 (`count-extraction.log`),
including accounting invariants and dependent stock/count tests. The standalone
guarded reversal verifier passed79/0 again, exit0 (`reversal-final-79.log`).
Complete post-extraction source verification subsequently passed252/2002 as recorded
above; the earlier252/2002 result below remains identified as pre-extraction evidence.

**Complete backend verification before count extraction passed:**252/252 suites,2002/2002 tests,
exit0 from launcher and explicit status file,2423.403s. Exact command:

```sh
cd server
NODE_OPTIONS='--max-old-space-size=2048' npm test -- --maxWorkers=2 --workerIdleMemoryLimit=1024MB --coverage --coverageReporters=json --coverageReporters=text-summary
```

`server-clean-all.log` and `server-clean-all.exit` retain the completed result.
Coverage: statements77.33%, branches72.10%, functions83.28%, lines78.99%; the
complete pre-extraction JSON is retained as `server-coverage-pre-extraction.json.gz`.
All accounting invariants, dependent return/payment/payroll/count/production and
reversal suites ran. No heap failure or “Cannot log after tests are done” occurred.
The final quick gate subsequently passed; independent review subsequently approved the final scope.

A bounded storage experiment used documented `TEST_TMPDIR` with a fresh `/tmp`
root and isolated coverage output for `posPayments.test.ts`:23 tests passed,
exit0,95.384s (`fixture-storage-benchmark.log`). It did not improve the observed
total runtime, so the ongoing complete run retains the default guarded fixture
root and was not restarted for this experiment. That focused coverage summary
is not counted as complete source coverage.

The first recycled-worker run exposed an existing shared teardown defect: setup
removed the database and closed Winston while the activity logger's timer still
ran. It was stopped with exit130 and retained as `server-late-timer-investigation.log`.
The new `auditTestLifecycle.test.ts` requires a queued event to be absent during
the test and persisted by file-level teardown. Red: expected1/received0, exit1
(`test-lifecycle-red.log`). Shared setup now calls existing `disposeLogger()`
before cleanup, with cleanup guaranteed by `finally`; disposal errors are not
swallowed. Green:4 suites/43 tests, exit0, no late-log warnings
(`test-lifecycle-green.log`). Financial source and integrity checks are unchanged.
The complete run is restarted with the proven cleanup and memory recycling.

The coverage run without worker recycling was deliberately stopped with exit130
after214 passing suites, fixture assertions and two heap crashes. The retained
log is `server-coverage-resource-and-fixture-failures.log`; it is not a full pass.
The complete replacement uses `--maxWorkers=2 --workerIdleMemoryLimit=1024MB
--coverage --coverageReporters=json --coverageReporters=text-summary`, with the
same2GB per-worker heap cap and an explicit exit file. Production is unchanged;
the final source/test hashes are in `SOURCE-MANIFEST.json`.
`dashboard-owner-recheck.log` passed2 suites/18 tests, exit0, including the
corrected chart fixture and the owner-withdrawal file whose worker had crashed.
`cash-read-isolated.log` passed11 tests, exit0.

Final coverage-run follow-ups (production source unchanged): the old mocked
controller release test expected controller-side SQL after that responsibility
moved into the shared model. Its replacement exercises actual release and replay,
retains reserved1/available9, and strengthens generic500 sanitization. Two suites/
18 tests passed, exit0 (`reservation-controller-final.log`).
The cash-read no-write assertion failed once by one SQLite change, then the
unchanged file passed11/11 (`cash-read-unmodified-recheck.log`). Customer setup
queues activity writes on a1000ms flush timer. The test now drains setup work
before measuring and drains GET work before retaining exact total-change equality.
That isolated version passed11/11; the complete final execution subsequently
passed as recorded above.
The dashboard's minimal chart fixture now includes the real account-name column;
its expected amounts remain unchanged. Coverage workers also exhausted the imposed
2GB heap in two files. Those are resource failures, not passing tests. The final
complete run must recycle workers before the heap limit; no gate is relaxed.

Clean complete Flutter run: `flutter test --no-pub --reporter compact`, exit0
from both launcher and explicit status file,1042 tests passed in26m50s.
See `flutter-clean.log` and `flutter-clean.exit`. The redundant code-graph
daemon was temporarily paused to release indexing pressure, then resumed after
this run; no database/test integrity guard or gate was changed.

The earlier Flutter log reached1042 tests and “All tests passed” in38m34s,
but the launcher returned143. This is not recorded as a clean successful command;
see `flutter-full-final.log`. A fresh run records its exit status explicitly.

Current-source follow-up: standalone typecheck and `git diff --check` exited0.
Reservation compatibility follow-up passed2 suites/17 tests, exit0, including
existing batch-only lifecycle and complete-bin retry/release/reactivation checks:
`reservation-compatibility-green.log`.
The guarded reversal verifier was rerun after the final credit/header changes:
79 passed,0 failed, exit0; see `reversal-final-79.log`. All eight phone/desktop
light/dark top/bottom captures were manually inspected; the tested fixture is
readable, scrollable and shows the added categories and balanced totals.

The complete final backend suite and unchanged quick/Fallow gate have now passed.
The final independent review is CLEAR / APPROVE within this scope. This document does not assert
comprehensive financial safety or certify the explicitly unexecuted workflows.
