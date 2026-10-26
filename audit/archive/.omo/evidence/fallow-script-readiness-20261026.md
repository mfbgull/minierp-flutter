# Script readiness evidence — 2026-10-26

Scope: `server/server.ts`, `src/utils/localNetwork.ts`, audit trace, unapplied-cash UI fixture, credit-reconciliation CLI, and their four focused test files. Shared accounting-audit files and audit decisions were untouched. No commit, suppression, threshold, or baseline change.

## Changes and directly observed scenarios

- `getLocalIP` now lives in a typed utility, preserving first external IPv4 enumeration order and fallback `0.0.0.0`; absent adapter arrays are safe. Tests cover IPv6/internal exclusion, selection order, absent adapters, and no eligible addresses without importing the server startup module.
- UI fixture exposes `createFixtureApps`; CLI startup still supplies its owned database and mounts the same applications. Real HTTP tests reject missing/wrong fixture tokens, invalid roles/actions/drop paths; create read/partial users and actual SQLite customer/invoice records; verify balanced invoice GL; toggle capabilities/offline reads; drop a successful response once while preserving errors; exercise period/prune/status/health. Only the downstream API response in the drop test is controlled, so middleware behavior can be observed without inventing a business operation. Command handlers use the real migrated test database/accounting service.
- Credit CLI exports its existing async entry function behind `require.main`, retaining readonly source/backup/query-only/fingerprint/cleanup behavior. Tests reject missing arguments without allocating a snapshot; reject absent source with `SQLITE_CANTOPEN` and remove the allocated directory; reconcile a real historical fixture, verify identical source SHA256, five expected customer IDs, emitted baseline, and snapshot removal.
- Audit startup uses a unique `mkdtemp` directory, canonical `erp.db`/database bootstrap and migrations, an isolated generated admin credential, and awaited admin seed. It no longer deletes fixed `server/audit-db` or replays a divergent migration list. Canonical seeded warehouses/users coexist with historical fixture inserts. Connection closes after completion/error. Database is retained at the printed unique path for inspection.

## Red/green startup regression

Invocation from `server/`: `npx jest src/__tests__/auditTraceReadiness.test.ts --runInBand --json --outputFile=../.omo/evidence/audit-trace-red.json`.

Original startup failed the canonical-bootstrap expectation, with filesystem mutations mocked and the attempted direct database open failing. Artifacts: `.omo/evidence/audit-trace-red.json` and `.omo/evidence/audit-trace-red.log` (1 failed test). After the fix, the test observes canonical bootstrap, unique environment directory, and zero recursive deletion calls. Initial green run with local-network tests: `.omo/evidence/audit-trace-green.json` / `.log` (2 suites, 3 tests pass).

## Focused verification commands

From `server/`:

```sh
npx jest src/__tests__/auditTraceReadiness.test.ts src/__tests__/localNetwork.test.ts src/__tests__/unappliedCashFixture.test.ts src/__tests__/creditReconciliationCli.test.ts --runInBand --coverage --coverageDirectory=.tmp-test/fallow-script-readiness-coverage --collectCoverageFrom=src/utils/localNetwork.ts --collectCoverageFrom=scripts/reconcile-customer-credits.ts --collectCoverageFrom=scripts/fixtures/unapplied-cash-ui.cjs --json --outputFile=../.omo/evidence/script-readiness-tests.json
npm run typecheck
npx eslint src/utils/localNetwork.ts src/__tests__/localNetwork.test.ts src/__tests__/auditTraceReadiness.test.ts src/__tests__/unappliedCashFixture.test.ts src/__tests__/creditReconciliationCli.test.ts
```

Artifacts: `.omo/evidence/script-readiness-tests.json`, `.omo/evidence/script-readiness-tests.log`, `.omo/evidence/script-readiness-typecheck.log`, `.omo/evidence/script-readiness-lint.log`; mapped Istanbul coverage: `server/.tmp-test/fallow-script-readiness-coverage/coverage-final.json` and `lcov.info`.

Final outcomes: focused Jest **exit 0, 4/4 suites and 10/10 tests pass** (66.881 seconds); typecheck **exit 0**; scoped ESLint **exit 0** (only existing package module-type warning). One earlier loaded-host run exceeded the default ten-second deadline in the new full-schema/SQLite backup integration scenario. That single new test now has an explicit 60-second startup/I/O budget; no global timeout or behavior assertion changed. The complete four-suite scenario was rerun successfully after that adjustment.

From root: `node --test scripts/unapplied-cash-fixture.test.cjs` — exit 0, existing environment rejection test passes; artifact `.omo/evidence/unapplied-fixture-node-tests.log`.

## Historical audit runtime — execution evidence, not passing accounting verification

From `server/`:

```sh
NODE_V8_COVERAGE=/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/.omo/evidence/fallow-readiness-cli-v8 TS_NODE_PROJECT=tsconfig.test.json TS_NODE_COMPILER_OPTIONS='{"sourceMap":true,"inlineSources":true}' node -r ts-node/register/transpile-only scripts/dev/audit-trace.ts
```

Observable: exit 0, all eleven scenarios execute; **46 checks pass and four fail, with six diagnostic issues retained**. These are manually implemented historical SQL simulations, not calls through current production models. No expected outcome was changed to make them green. Exit 0 means the historical harness completed, not that accounting verification passed. Output explicitly states this limitation. The pre-existing hardcoded C2 diagnosis remains a historical assertion, not independently reproduced production evidence.

Artifact `.omo/evidence/audit-trace-runtime.log`; raw V8 `.omo/evidence/fallow-readiness-cli-v8/coverage-26585-1792975655877-0.json`. Audit source-map cache embeds the current source (59,477 characters) with 968 compiled line lengths. Every named scenario, `main`, and `runAllMigrations` executed once. Parent owns merging validated source-mapped coverage and the final Fallow scan.

Full server suite and final integration/static gates are delegated to the parent task. Flutter suite was not rerun: these changes do not affect Flutter or shared business API contracts. No complete-task or all-Fallow-findings-cleared claim is made by this scoped report.

## Additional assigned security repair: correction target aliases

Parent subsequently handed over `server/scripts/lib/correctionSafety.ts` and the existing `server/src/__tests__/correctionAuthorization.test.ts` for the physical-file identity bypass. The shared gate now recognizes the lexical live path first and otherwise compares bigint device/inode metadata from `statSync`, which follows directory/file symlinks and also identifies hardlinks. A missing canonical file remains supported in isolated CI environments. Token, explicit target, checksum-bound live override, and apply flag gates and exit statuses are preserved; the returned `dbPath` remains the caller's resolved explicit target.

Tests mock all target/canonical filesystem reads and metadata. The only real metadata sampled belongs to the test source and correction helper source; **no live database is read or written**. Added four cases: directory-symlink metadata identity rejection; hardlink identity rejection; alias checksum/apply independence and exact successful return; unrelated physical file acceptance. Existing twelve tests, including both entrypoint import-order cases, remain intact.

Exact invocation from `server/`: `npx jest src/__tests__/correctionAuthorization.test.ts --runInBand --json --outputFile=../.omo/evidence/correction-alias-red.json`; after the source fix, the same command with output file `correction-alias-green.json`.

Red observable: **exit 1, 3 failed / 13 passed / 16 total**, reproducing alias acceptance and skipped live checksum challenge. Artifacts `.omo/evidence/correction-alias-red.json` and `.omo/evidence/correction-alias-red.log`.

Green observable: **exit 0, 16/16 tests pass** (11.054 seconds). Artifacts `.omo/evidence/correction-alias-green.json` and `.omo/evidence/correction-alias-green.log`. No global typecheck, Fallow scan, or full-suite rerun was performed during this final scoped repair; parent owns the serialized final verification.
