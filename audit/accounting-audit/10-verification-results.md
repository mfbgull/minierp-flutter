# Verification results and reproducibility

Audit source revision: `15a784180a51b816759dc0d3440d4c8743dcdb98`. The intervening `8d292328` commit added audit artifacts/local settings. All1,172 protected hashes matched at the retained2026-10-25 checkpoint; finalization onOct26 finds10 later changed baseline files and17 added protected-scope files. These external edits are preserved, not attributed to this audit, and not certified by earlier suites. Root/independent comparisons and exact current source hashes are retained. This audit did not commit, modify product code or open a live database for writing.

## Standard checks

| Check | Executed result | Evidence / interpretation |
|---|---|---|
| Server `npm run typecheck` | PASS in quick run | `evidence/quick.log` |
| Server `npm run lint` | PASS in quick run | Nonfatal Node package-type warning retained; no suppression |
| Fallow gate in `scripts/check.sh --quick` | FAIL | New standalone audit CJS scripts reported unused/complex; original log retained. No gate/config/baseline exemption was added to conceal audit-helper findings |
| Root `flutter analyze`, initial quick run | FAIL,3 audit-harness infos | Curly-brace/unnecessary-import issues in newly added audit tests; harness subsequently corrected |
| `flutter analyze accounting-audit/tests` | PASS | Final scoped exit0; `evidence/flutter-harness-analyze.log` and `.exit` |
| Root `flutter analyze`, final rerun | PASS, exit0, no issues | Exact command/PID/times in `evidence/verification-runs.json`; `flutter-analyze-final.log` |
| Root `node scripts/l10n-drift.js` in quick run | PASS | `evidence/quick.log` |
| Full server, first attempt | INTERRUPTED; no full-suite result | `server-full.log` contains3 passed suites only. No complete JSON or final exit; not counted as pass |
| Full server, resumed | Test assertions PASS:232 suites/1,918 tests; clean process exit UNVERIFIED | Final JSON success=true/zero failed. Log reports Jest open handles; wrapper exited during daemon recovery and final shell exit was not captured. Do not claim exit0 or fully green CI |
| Full Flutter | PASS, exit0:1,034 visible tests and96 hidden loading checks | `flutter-full-resumed.log` final success=true; captured run completed05:27:57UTC2026-10-25;1,130 completion events total |
| Journal test on local temporary fixtures |21 assertions PASS; no clean exit claimed | Benchmark results JSON;206s did not establish a speed improvement over136s earlier under different load. Existing full run was preserved, not replaced |

The quick run as a whole exited1. A later successful subcheck does not rewrite that historical result. Existing full suites support regression confidence but do not establish economic correctness by themselves.

Full server test window:2026-10-25 04:55:54–05:34:40UTC. Exact result extraction is in [final-test-summary.json](evidence/final-test-summary.json). The recovered old run manifest does not contain every orphaned-process outcome; missing exit codes are explicitly unknown rather than reconstructed as0.

## New independent audit evidence

| Execution | Observed result | Correct interpretation |
|---|---|---|
| Main economic oracle, AbsZeT |397 assertions,392 pass,5 fail; no setup-blocked family | Five genuine early-sales-return mismatches F-001; bounded retail87 checks pass |
| Dedicated credit oracle, z9sfxV |73 assertions,64 pass,9 fail | F-002 actual entitlement reuse; signed economic obligation75 vs operational15 |
| Supplier paid/unpaid/partial cap, eVTI6t |42/42 assertions pass | Corrected collected-cash policy; not supplier multi-target allocation |
| Supplier two-target attempt, TQ4hqh | Request500,43 checks including5 capability mismatches | Unsupported allocation; aggregate/no-cash invariants pass; do not relabel capability as PASS |
| Early supplier return, ZHkdJ8 |21 checks including4 mismatches | F-001 purchase chronology extension |
| Transfer/FEFO/funds/year/tax supplement | Named scenarios pass in9MmRSv | Separate F-002 and superseded supplier-cap expectation are not counted as passing cases |
| Backend forensic probes, Lbw3la | Four captured behaviors, exact readonly verifier PASS | Three economic defects F-020–022 and policy-qualified F-023; verifier expects observed bad state, not correct production behavior |
| Positive backend extension, OF2b8i |3 bounded scenarios PASS | Positive overhead/reversal, owner drawings/reversal, ordinary count correction |
| Count risk, ZBybHv |2 defects captured and readonly verified | F-024 failed correction rolls back; F-025 partial correction commits false stock/loss |
| Flutter actual-API positive replay |3 tests PASS, exit0 | Models, mounted P&L refresh and balance-sheet figures match the independent retail oracle |
| Flutter F-040–042 detector |3 assertions fail, exit1 | Reproduced nonzero-category omission, malformed CSV and double-subtracted carryover |
| Targeted final F-041 parser detector | Quoted/doubled-quote controls pass, actual export assertion fails | A correctly escaped future CSV can pass; final detector is quote-aware |
| Flutter F-043 detector |1 assertion fails, exit1 | Expense details10 fail to explain total20; profit50 remains correct |
| Invariant query-grain/sign probe | Executed, assertions PASS | Synthetic demonstration of existing A/F coverage limits, not production corruption proof |
| Independent adversarial review | Bounded inclusion APPROVE | Read-only SQL/API/widget/source verification; final consolidation remains leader-owned |
| Payable/cash final extension, GIxBh2 |552 checks,535 pass/17 repeated header-status failures across41 requests | Supplier advance/expense/count economic controls pass; nine stale headers prove one F-060 audit-store defect |
| Sales-channel final extension, AFjr5O |692 checks,685 pass/7 mismatches; no blocked scenario | Ordinary quote/SO/POS controls pass; F-070–073 reproduce status, reservation and phantom-cash defects |
| Final extension read-only verifier |PASS, findingsF060/F070/F071/F072/F073 independently verified | Only retained fixture DBs opened readonly/fileMustExist; integer-paise cash/stock deltas and positive reservation control asserted |

## Authoritative evidence and rerun commands

- `node accounting-audit/tests/oracle-lifecycle.cjs`; select supplemental families with `ORACLE_SUPPLEMENT=1 ORACLE_FAMILY=2b`, `3b`, `3c`, or `7c` as documented in the oracle workstream.
- `node accounting-audit/tests/backend-controls.cjs`, `backend-extension.cjs`, `backend-count-risk.cjs`; readonly proof via `backend-verify-evidence.cjs` and `backend-verify-extension.py`.
- Flutter commands/tags/environment are in [Flutter workstream](workstreams/flutter-reports.md) and finding folders; expected failures must not be reported as passing regressions.
- `python3 accounting-audit/tests/invariant-granularity.py` opens SQLite only in memory.
- `node accounting-audit/tests/final-extension-verifier.cjs` verifies late retained evidence without importing application boot; this was executed at finalization.
- `node accounting-audit/run-verification.cjs artifacts` generates final artifact hashes and checks local Markdown link targets. The original compare checkpoint is retained; do not overwrite it and mistake later external changes for audit edits.

Fresh fixture directories, SQL snapshots, API bodies/status/responses, source references, exact expected/actual comparisons and real mounted-widget image/text/export files are retained. Prior setup failures remain for transparency and are excluded from product-defect counts. No fabricated screenshot, API success, test pass or real-data reconciliation is used.

Some audit harnesses were also subsequently refactored by external work. The final artifact manifest hashes the **delivered bytes**, not a retroactive assertion that every earlier command used those later bytes. Original tracked harness/source versions are available in artifact commit8d292328, whose protected production source matched15a78418; immutable raw stage/API/DB evidence is retained. For exact historical replay use matching versions in an isolated disposable checkout, never reset the shared working tree. The final read-only extension verifier was executed against the retained evidence during this finalization; a fresh full replay of later-edited harnesses is not claimed.

## Coverage deliberately not upgraded

The full-scope gaps in [limitations](07-unverified-areas.md) remain even if the existing suites pass. Per-module PASS refers only to a named bounded case; NOT TESTED/PARTIAL rows are not green by inheritance. There is no whole-app live UI verification, all-report certification, historical migration replay or multi-process crash-durability proof.

Both original full test collections executed; they were **intentionally not rerun after later shared-workspace source/config changes**, since no production correction was made by this audit and chasing unrelated implementation work is outside its snapshot scope. Current-source drift, dependencies/config status and unchanged finding-source checks are in [final-source-state.json](evidence/final-source-state.json). Current Fallow remediation/config edits are external; the historical failed quick run remains recorded. No claim is made that every current working-tree check passes.
