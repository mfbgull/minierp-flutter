# Audit fixture extraction — 2026-10-26

## Changes

The shared setup in `accounting-audit/tests/backend-controls.cjs`, `backend-count-risk.cjs` and `backend-extension.cjs` now calls `accounting-audit/tests/lib/isolated-fixture.cjs`. The helper creates the fresh run directory, sets the original fixture environment, installs the original SQLite constructor path confinement, registers ts-node, loads the database module and initializes the evidence object. Its `startAuditSession` boots migrations, awaits seeding, registers cleanup before attempting login, and returns the authenticated API and account-net helpers. Each script retains its exact original directory prefix. Scenario bodies and evidence writers remain unchanged. The parent explicitly expanded the initial setup-only assignment to include the common authenticated bootstrap.

The smoke test `server/src/__tests__/isolatedAuditFixture.test.ts` runs the helper in a separate Node subprocess with an owned temporary directory. It asserts environment values and database module loading; executes a real SQLite query inside the fixture; rejects outside, sibling-prefix, traversal and memory database targets; and verifies rejected file paths were never created. It then runs migrations, logs in, makes an authenticated inventory-list GET, verifies the captured API evidence and account balances, and confirms the SQLite guard remains active after app loading. The subprocess isolates require.cache, the constructor proxy and environment from Jest. Cleanup only removes the test's own temporary directory.

No forensic audit scenarios were executed; no existing audit evidence or dirty audit orchestrator/document files were changed.

## Evidence

- Red: from `server/`, `npm test -- --runInBand --runTestsByPath src/__tests__/isolatedAuditFixture.test.ts --json --outputFile=../.omo/evidence/fallow-audit-fixture-red-20261026.json`. Exit 1, one failed test because the new helper did not exist (`MODULE_NOT_FOUND`). Artifacts `.omo/evidence/fallow-audit-fixture-red-20261026.json` and `.log`.
- Green: same invocation with outputFile `../.omo/evidence/fallow-audit-fixture-green-20261026.json`. Exit 0, one suite/one test passed, child process exited 0 and emitted `AUDIT_FIXTURE_CONFINEMENT_PASS`. Artifacts `.omo/evidence/fallow-audit-fixture-green-20261026.json` and `.log`.
- Typecheck: `npm run typecheck` in `server/`, no diagnostics; `.omo/evidence/fallow-audit-fixture-typecheck-20261026.log`.
- Lint: `npx eslint src/__tests__/isolatedAuditFixture.test.ts` in `server/`, exit 0, existing module-type warning only; `.omo/evidence/fallow-audit-fixture-lint-20261026.log`.
- Syntax: `node --check` on the helper and each of the three audit scripts; all exit 0. Artifact `.omo/evidence/fallow-audit-fixture-syntax-20261026.log`.
- LSP: smoke test diagnostics returned `No diagnostics found`.
- Duplication: root invocation `npx --yes fallow@3.34.1 dupes --format json --output-file .omo/evidence/fallow-audit-fixture-duplicates-20261026.json`, exit 0. Artifacts `.omo/evidence/fallow-audit-fixture-duplicates-20261026.json` and `.log`.

## Clone result and startup diagnosis

The final duplicate report contains four pre-existing query-template groups and zero groups involving `accounting-audit`. The original clone and the intermediate remaining bootstrap fingerprints are absent; the implementation does not suppress or baseline findings.

The expanded cold-start smoke initially exceeded its newly introduced 20-second subprocess limit. An independent 60-second diagnostic also hit its limit while the host was heavily loaded; a stage-traced diagnostic then completed normally, recording migration completion, seed readiness, authenticated session readiness, the pass marker and status 0. Artifact `.omo/evidence/fallow-audit-fixture-stages-20261026.log`; the earlier timed-out diagnostic is `.omo/evidence/fallow-audit-fixture-diagnostic-20261026.log`. The new smoke's local subprocess budget is 60 seconds to cover full ts-node/database/app startup. No existing or global timeout changed. The parent reported four CPUs, load average 35 and memory pressure during these attempts, and will serialize final full-suite verification.

Later LSP freshness checks timed out on the loaded host; the earlier smoke diagnostics were clean. These tool timeouts are not claimed as successful final LSP validation.
