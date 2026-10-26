# Production Fallow findings verification — 2026-10-26

## Scope and changes

- `server/src/utils/legacyBomMigration.ts`: extracted `legacyBomValues`, the normalization of legacy header fields into insert parameters. Number matching, ID collision allocation, SQL, fallback values and map mutation remain unchanged. Existing migration integration tests characterize these behaviors before and after extraction.
- `server/src/__tests__/ownerCapitalListModelCoverage.test.ts`: seven tests execute actual list SQL against an isolated in-memory schema. They cover default status/order, author join, explicit/all status, inclusive dates, each searchable column, bound search text, combined filters, sorting and pagination.
- Neither owner model was modified. The three assigned owner findings disappear with fresh coverage from existing tests. Line 587 in OwnerWithdrawal is the `softVoid` transaction, although the earlier report associated it with `update`.
- No live database, thresholds, suppressions, baselines, accounting policies or unrelated files changed.

## Invocations and observations

Commands below run from `server/` except Fallow, which runs from the repository root.

### Before extraction: migration and owner behavior

`npm test -- --runInBand --coverage --coverageDirectory=.tmp-test/fallow-production-baseline --coverageReporters=json --json --outputFile=../.omo/evidence/fallow-production-baseline-20261026.json --runTestsByPath src/__tests__/ownerEquity.test.ts src/__tests__/ownerWithdrawalEditRoutes.test.ts src/__tests__/bomItemsSchemaRepair.test.ts src/__tests__/stockRepairAndReconciliationCoverage.test.ts`

Observable: exit 0, 4 suites and 37 tests passed, zero failures. Artifacts:

- `.omo/evidence/fallow-production-baseline-20261026.json`
- `.omo/evidence/fallow-production-baseline-20261026.log`
- `server/.tmp-test/fallow-production-baseline/coverage-final.json`

Fresh function coverage directly shows Capital.getAll called once, cash-update transaction at line 454 called four times, and softVoid transaction at line 587 called once.

### After extraction: regression, real routes, accounting invariants and list SQL

`npm test -- --runInBand --coverage --coverageDirectory=.tmp-test/fallow-production-after --coverageReporters=json --json --outputFile=../.omo/evidence/fallow-production-after-20261026.json --runTestsByPath src/__tests__/ownerCapitalListModelCoverage.test.ts src/__tests__/ownerEquity.test.ts src/__tests__/ownerWithdrawalEditRoutes.test.ts src/__tests__/bomItemsSchemaRepair.test.ts src/__tests__/stockRepairAndReconciliationCoverage.test.ts src/__tests__/accountingInvariants.test.ts`

Observable: exit 0, 6 suites and 77 tests passed, zero failures. Includes invariants A–J, cash/stock/GL edit rollback behavior, real PUT routes and both legacy migration callers. Artifacts:

- `.omo/evidence/fallow-production-after-20261026.json`
- `.omo/evidence/fallow-production-after-20261026.log`
- `server/.tmp-test/fallow-production-after/coverage-final.json`

The new list suite required a TypeScript correction before completion: the afterAll callback must return void rather than Database.close()'s Database value. The final test run and checks use the corrected callback.

### Static checks

- `npm run typecheck`: exit 0. Artifact `.omo/evidence/fallow-production-typecheck-20261026.log`.
- `npx eslint src/utils/legacyBomMigration.ts src/__tests__/ownerCapitalListModelCoverage.test.ts`: exit 0, no lint errors (existing module-type warning only). Artifact `.omo/evidence/fallow-production-lint-20261026.log`.
- LSP initially reported no diagnostics for both changed files. A later whitespace-only separation in the migration file caused the LSP freshness request to time out; no claim of final LSP completion is made. Typechecking and Jest passed; the late edit added only a blank line.

### Fallow assigned-target check

`npx --yes fallow@3.34.1 health --coverage server/.tmp-test/fallow-production-after/coverage-final.json --format json --output-file .omo/evidence/fallow-production-after-health-20261026.json`

Artifacts: `.omo/evidence/fallow-production-after-health-20261026.json` and `.omo/evidence/fallow-production-after-health-20261026.log`.

Binary observable: the report's findings contain none of `legacyBomMigration.ts`, `OwnerCapital.ts` getAll, or `OwnerWithdrawal.ts` lines 454/587. Thus all four assigned targets are absent. The overall command exits 1 because isolated coverage intentionally omits most other suites; this is NOT a clean repository-wide health gate. The earlier comparison scan used the baseline coverage after extraction and is recorded as `.omo/evidence/fallow-production-baseline-health-20261026.{json,log}`.

## Review and remaining verification

Self-review: the extracted tuple preserves parameter ordering and every fallback operator from the original implementation, and both insert strategies consume the same tuple. No accounting production code changed. New list tests assert returned rows and not implementation calls.

The parent executor owns the final complete server suite and refreshed global coverage/Fallow scan. This worker does not claim full-suite completion. Flutter was not changed or tested.
