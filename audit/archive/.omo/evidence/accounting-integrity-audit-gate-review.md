# Independent adversarial challenge

Recommendation: APPROVE the bounded findings below for inclusion in the audit. This is not approval of accounting correctness, release readiness, or completion of the leader's still-in-progress consolidated audit.

originalIntent: Independently audit financial integrity using current source, clean synthetic lifecycle evidence and explicit module/figure coverage, without changing production or live data.
desiredOutcome: Actionable supported findings with honest unexecuted-area disclosure, rather than a blanket certification from passing suites.
userOutcomeReview: The inspected evidence supports eight concrete defects and one policy-qualified workflow restriction. The final executive summary and module matrix were still marked IN PROGRESS / INITIAL RECONNAISSANCE when reviewed. Their final synthesis remains the leader's responsibility.
blockers: [] for the bounded finding review. No unsupported requirement is invented as a blocker.

## Independent evidence

I opened only three retained synthetic databases using better-sqlite3 `{readonly:true,fileMustExist:true}`. No application was booted, no live database opened, no production or existing test file edited. Exact fresh SQL results: `accounting-audit/evidence/adversarial-db-check.json`. I independently parsed API transcripts and mounted-widget evidence and parsed the actual CSV using Python's standard csv reader: `accounting-audit/evidence/adversarial-api-ui-check.json`.

| Finding | Challenge result | Independent observation |
|---|---|---|
| F-001 | Confirm High chronology defect | Source invoice September11; return and all four return GL lines September9. Dr4100=15 and Cr5000=10 produce revenue−15/COGS−10; Dr1200=10 restores inventory before sale. Source return transaction checks closed period but no source-date lower bound. |
| F-002 | Confirm Critical reusable credit entitlement | Saved API sequence returns200 for consumed settlement void,200 for reissue,201 for another invoice60 paid entirely by credit. Saved DB invoices retain offsets30+30+60, one original60 settlement void and replacement60 active. Cash collection150; retained goods225; correct receivable75. GL1100−45 +1110+120 =75, customer net15. All journals balance. This is actual duplicate spending, not just a collector discrepancy. |
| F-020 | Confirm High recognition defect | Salary rows1000 August,200 September advance,800 September salary; GL wages1800 and advance asset200. Two earned salaries require2000 expense and zero remaining advance. Later loan events explain final Bank7700; do not compare that final bank value to the earlier payroll-only8000 snapshot. |
| F-021 | Confirm Medium chronology defect | Loan GL before disbursement is−200. Recorded API repayment201 and source direct repayment lacks source-date comparison. |
| F-022 | Confirm negative valuation / GL integrity defect | Independent DB output costs .01,.01,.01,−.01; negative remaining batch−.01; inventory GL .03 and clearing−.01 for input .02. High integrity classification is defensible, but demonstrated monetary magnitude is one cent; larger loss is not quantified. |
| F-023 | Confirm restriction; policy qualification required | Retained API results show both409; source explicitly guards original accrual date. No corrupted posting demonstrated. Ordinary later settlement should not mutate the old accrual; intended product treatment still needs explicit disposition. Existing finding correctly qualifies it. |
| F-040 | Confirm High display completeness defect | Mounted Text capture shows asset components1500/total1900, liability components500/total630, Balanced badge. Models omit other400/tax60/other70; source and synthetic valid API fixture support loss. No claim every backend balance-sheet formula is certified. |
| F-041 | Confirm Medium export defect | Standard CSV reader parses actual Cash row into four cells: Cash, empty, Rs. 1, 000.00. Source directly interpolates currency. |
| F-042 | Confirm Medium UI calculation defect | Actual mounted Text says paid200 + advance200 / remaining600; backend-origin row already includes advance in total_paid200 and remaining800. Source subtracts twice. No payment submission or financial loss was demonstrated by the UI scenario. |

## Oracle and coverage challenge

The built-in absolute-value AR collector is unsuitable as the independent signed oracle. For F-002 after source void, GL+15 versus customer−45 is a60 divergence, not30. The final duplicate-spend state is75 versus15. The newer harness adds the signed check; findings correctly explain this distinction. Collector counts and balanced journals do not imply economic correctness.

Lifecycle assertions use real mounted routes and fixed economic expectations, with migrations and constructor-path guards confined to fresh directories. `transpileOnly` is harness convenience, not static verification. Shared collectors are supporting checks, not independent oracles. Snapshot hashes cover a declared subset of tables; unchanged hashes cannot prove absence of every side effect or crash durability. Generic report fetches without amount assertions do not prove numerical correctness.

Backend and Flutter workstream matrices appropriately distinguish mapped/reviewed, executed, PARTIAL and NOT TESTED. The central matrix was still initial reconnaissance at inspection; final publication must integrate bounded statuses and keep unexecuted variants visible. In particular no universal coverage is established for physical counts, reservation races, POS/mobile parity, production reversal/positive overhead, owner withdrawal variants, multi-currency personal loans, custom-report formulas, printed PDFs, locale/date combinations, cache freshness, historical migrations, crash/restart or multi-process contention. Full suites are leader-owned and were intentionally not rerun here; their eventual success must not upgrade these rows to PASS.

## Programming and remove-ai-slops direct pass

Consulted `/home/fawad/.codex/plugins/cache/sisyphuslabs/omo/5.1.40/skills/programming/SKILL.md` and `remove-ai-slops/SKILL.md`. Applied their test-value, shared-source, unnecessary abstraction, boundary, error handling and maintenance criteria directly to the audit scripts and cited production seams. No production implementation diff is part of this audit; no unsolicited cleanup is authorized.

- No deletion-only tests, requested-removal tests or tautological identity assertions found in the inspected scenarios. The economic numeric expectations can fail and do fail on current behavior. Repeated collector invocations are lifecycle checkpoints, not independent findings or exhaustive coverage.
- NOTE: `flutter_reports_test.dart` F-041 uses `split(',')`. Valid quoted CSV would still fail this assertion, so this is a current-defect diagnostic, not a ready permanent regression. Use a real CSV parser before promotion. My independent standard-parser check confirms the present finding despite that harness limitation.
- NOTE: `backend-verify-evidence.cjs` asserts known bad observed values; it verifies reproducibility of an audit artifact, not desired future behavior. Do not migrate those assertions unchanged into a regression suite expecting a fix.
- Snapshot serializers/inventory scanners have a justified audit evidence purpose; no production extraction, normalization or parsing was added. Direct numeric production evidence, rather than implementation-shaped expected arithmetic, establishes the findings.
- Source mechanisms checked include credit's saturating clamp, salary recognition transition, final-output allocation residual, UI field omission and carryover subtraction. Reports recommend shared-source corrections, not symptom masking.
- No separate code review report explicitly covering these skill perspectives was present in the inspected workstreams. This direct pass supplies that coverage; absence alone is not a blocker. Long procedural disposable harnesses and broad catch-to-BLOCKED reporting deserve maintenance care if adopted permanently, but do not invalidate observed failed economic outcomes.

## Checked artifact paths and exact limits

Read team guide/team.json, root AGENTS, the three listed skills/role criteria, `accounting-audit/00-executive-summary.md`, `03-coverage-matrix.md`, `07-unverified-areas.md`, workstreams/backend-controls.md and flutter-reports.md, all nine finding.md files F-001/F-002/F-020–023/F-040–042, F-001/database-proof.json, tests/oracle-lifecycle.cjs, oracle-supplement.cjs, backend-controls.cjs, backend-verify-evidence.cjs and flutter_reports_test.dart; actual retained API/results/DB artifacts for oracle-run-z9sfxV, oracle-run-AbsZeT, backend-run-Lbw3la; Flutter widget JSON, CSV, payroll fixture references and regression log/exit. financial-oracle.md was not yet present when initially requested; this is a timing gap, not evidence against its final conclusions.

Graph-first symbol discovery and exact path coverage were consulted; no recorded gaps on cited eight source paths, a best-effort signal only. Direct source reads covered invoiceReturnService.ts, employeeController.ts, Production.ts, ExpensePayment.ts, paymentValidation.ts, report.dart, salary_pay_dialog.dart and csv_export.dart. No exhaustive negative source claim rests on graph absence.

No screenshot visual review or new mounted widget/API rerun was performed by this reviewer; findings were independently challenged against actual saved rows, transcripts and rendered Text capture plus source. Evidence DBs contain synthetic identity/authentication material; they are local reproduction artifacts, not public export bundles. No live secret or real customer record was used in this pass.
