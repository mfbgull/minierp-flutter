# Maintenance CLI coverage, 2026-10-26

Owner: maintenance_coverage. Production scripts are unchanged. Four new Jest suites execute their existing entrypoints against fresh project-local SQLite files. No live or historical database was opened. No Fallow thresholds, exclusions, or coverage mappings were changed.

Follow-up: the duplicate-purchase defect initially left unresolved below was subsequently fixed in the CLI and the canonical PurchaseModel.void primitive. See `.omo/evidence/duplicate-purchase-cli-20261026.md` for red regressions and final 62/62 passing focused tests. The verification CLI lifecycle was separately repaired in `.omo/evidence/reversal-verification-cli-20261026.md`. The original four maintenance characterization suites remain unchanged by those follow-ups.

## Invocation and artifacts

Run from `server/`:

```sh
npx jest --runInBand --runTestsByPath src/__tests__/maintenance-ledger-cli.test.ts src/__tests__/maintenance-batches-cli.test.ts src/__tests__/maintenance-stock-repair-cli.test.ts src/__tests__/maintenance-reconciliation-cli.test.ts --coverage --coverageDirectory=.tmp-test/fallow-maintenance-coverage --coverageReporters=json --coverageReporters=text-summary
npx eslint src/__tests__/maintenance-ledger-cli.test.ts src/__tests__/maintenance-batches-cli.test.ts src/__tests__/maintenance-stock-repair-cli.test.ts src/__tests__/maintenance-reconciliation-cli.test.ts
```

Captured test log: `.omo/evidence/fallow-maintenance-targeted.log`.
Captured lint log: `.omo/evidence/fallow-maintenance-lint.log`.
Final observed results: Jest exit 0, 4/4 suites and 9/9 tests passed (50.9 seconds); ESLint exit 0 (only the repository's existing module-type warning). ts-jest compiled the new suites with the configured test tsconfig. The initial lint failure from raw require calls and subsequent generic-type compilation failure were corrected, then the complete focused scenario set was rerun successfully.
Measured Istanbul artifact: `server/.tmp-test/fallow-maintenance-coverage/coverage-final.json`.
Function statement summary: `.omo/evidence/fallow-maintenance-coverage-summary.log`.

## Scenarios and binary observables

| Suite | Scenario | Required observable |
| --- | --- | --- |
| maintenance-ledger-cli | Date backfill dry run, apply, repeat | Dry run leaves rows equal; corrected dates rebuild ordered balances to 90; voided row stays 999; repeat logs nothing to do |
| maintenance-ledger-cli | PO dedupe dry run, apply, repeat | No dry-run append; one attributed credit of 100; original marked voided; repeat row count stays 4 |
| maintenance-ledger-cli | Recompute amount boundaries | Flat and percentage discounts plus tax yield 16.5; excess discount caps at zero; malformed currency defaults zero; header stays 999; repeat stale count zero |
| maintenance-batches-cli | Production and purchase backfill | Material 10 plus overhead 4 yields unit cost 7; zero-output fallback uses movement cost or zero; movement links identify batches; repeat creates zero batches |
| maintenance-stock-repair-cli | Orphan cleanup | Empty unreferenced batch deleted; referenced batch tombstoned with link retained; remaining quantity/invalid cost/original quantity preserved for review |
| maintenance-stock-repair-cli | Empty cleanup | Zero rows and no-op log |
| maintenance-stock-repair-cli | Unbatched cost reconciliation | Other warehouse and adjustment costs excluded; weighted unit cost 5.2; standard-cost fallback 3; zero-cost fallback 0; canonical debit and credit both 32; sequence reaches 3; repeat adds no batch/JE |
| maintenance-reconciliation-cli | Exact duplicate matching | Item, quantity, cost and date near-matches ignored; exit 0; database bytes unchanged |
| maintenance-reconciliation-cli | Gaps and paid/unpaid duplicates | Uncovered quantity 5 valued at 30 using weighted cost 6; four issues; paid and unpaid paths reported; exit 1; database bytes unchanged |

These characterize unchanged command behavior; they do not certify that historical repair policies conform to all present accounting rules. The PO dedupe test explicitly records its existing active-row balance algorithm, not a new accounting policy.

## Owned finding disposition

| Finding | Measured statements within function |
| --- | --- |
| backfill-ledger-dates main | 37/38 |
| dedupe-po main / tx | 42/42; 18/18 |
| recompute-item-amounts main / parseCurrency / computeLineAmount | 30/32; 3/4; 10/10 |
| repair-stock repairOrphanedBatches / unbatched run | 22/22; 17/19 |
| backfill-batches backfillProductions | 26/26 |
| reconcile-stock-cash flagUnbatchableStock / flagDuplicatePurchases | 23/23; 16/16 |
| fix-duplicate-purchase fix | Unresolved: genuine warehouse defect reproduced; no passing test added that blesses it |

The root agent owns final Fallow scan, coverage integration and full server-suite verification. Flutter and full server suites were not run by this worker. Newly added tests are 64, 102, 91 and 82 nonblank lines, each owning one CLI operation family. No production escape hatches, argument objects, one-caller helpers or logging changes were introduced. Test-only boundaries use explicitly typed Jest module loading and isolated database filenames.

## Investigated defect: wrong warehouse in duplicate-purchase correction

Reproduction command from repository root:

```sh
node .omo/evidence/fallow-duplicate-warehouse-repro.cjs
```

Artifact: `.omo/evidence/fallow-duplicate-warehouse-red.log` (exit 1, assertion expected warehouse 2, observed warehouse 1).
The reproduction transpiles and executes the current source unchanged, using a fresh SQLite file and a deterministic movement-number stub. It does not boot production models or open the application database. Fixture purchase warehouse is 2, quantity 5; warehouse 1 holds 10 and warehouse 2 holds 5. Actual result: reversal warehouse 1, balances warehouse 1 = 5 and warehouse 2 = 5. The temporary database and backup are deleted in finally.

Cause: the transaction deletes the purchase and only then selects its warehouse, so the lookup always misses and falls back to 1. The narrow warehouse correction is to include `warehouse_id` in the already-loaded purchase type and use it before deleting. This alone does not make this script safe: it hard-deletes a financial row, bypasses canonical purchase void logic, lacks active-payment/return checks, and does not reverse GL. Root must assess protected reversal routing before treating this script as an authorized repair. No delete/void policy was changed in this worker.

Additional source concern reported to root: `repair-stock.ts` checks `uncovered <= 0.0005` before `uncovered < 0`, making its over-coverage trimming branch unreachable. This branch remains uncovered and unchanged; no suppression was added.
