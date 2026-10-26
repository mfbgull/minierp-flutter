# Reversal verifier repair

Production scope: `server/scripts/verify-reversal-rules.ts`; regression: `server/src/__tests__/reversalVerificationCli.test.ts`.

The old CLI exited 0 while its unresolved seed promise left zero assertions executed. The regression was written and run first: `.omo/evidence/reversal-verification-cli-red.log` records expected 79 versus observed 0 PASS lines (Jest exit 1). The fix starts migrations before awaiting the admin seed, creates a valid supplier before both purchase fixtures, and funds the cash fixture through the existing owner-capital model. No accounting assertion or count was removed or relaxed.

Once enabled, the command reached 32 passing assertions before the funds guard rejected the empty starting cash fixture (`reversal-verification-cli-bootstrap.log`). Funding uses an actual 100000 cash capital posting dated before the verification transactions. The first full run produced 79 passes (`reversal-verification-cli-funded.log`). The regression also exposed SQLite cleanup with an open connection on the workspace filesystem (`reversal-verification-cli-cleanup-red.log`, ENOTEMPTY); the command now closes SQLite before removing its owned temporary database, including the error path.

Final invocations from `server/`:

```sh
npx jest --runInBand --runTestsByPath src/__tests__/reversalVerificationCli.test.ts
NODE_V8_COVERAGE="$PWD/../.omo/evidence/fallow-reversal-cli-v8-final" TS_NODE_PROJECT=tsconfig.test.json npm run verify:reversal-rules
npx tsc --noEmit --esModuleInterop --target ES2020 --lib ES2020,ES2022 --module commonjs --skipLibCheck --strict scripts/verify-reversal-rules.ts
npx eslint scripts/verify-reversal-rules.ts src/__tests__/reversalVerificationCli.test.ts
```

Observed final results: Jest exit 0, 1 suite / 1 regression passed (65.277 seconds); subprocess asserts exit 0, exactly 79 PASS lines, zero FAIL lines and `Result: 79 passed, 0 failed`. Direct CLI exit 0 with the same summary. Strict explicit script typecheck exit 0, no diagnostics. ESLint exit 0 for the test; the script is outside the existing lint configuration and was reported ignored, so script lint is not claimed.

Artifacts: `reversal-verification-cli-green.log`, `reversal-verification-cli-final.log`, `reversal-verification-cli-lint.log`, and raw source-mapped V8 files under `.omo/evidence/fallow-reversal-cli-v8-final/`. Earlier V8 files under `fallow-reversal-cli-v8/` are intermediate source versions and should not be used for final integration.

One rerun hit the unchanged shared setup hook's 15-second timeout under contention before executing this test; it passed on rerun without changing the timeout. An initial explicit typecheck omitted the project's ES2022 library and rejected existing Error cause arguments; the final invocation above restores the actual project library support.

Limits: this preserves two pre-existing tautological assertions (correction stamp and the receipt-added-stock expression). Passing the overall gate does not independently prove those two properties. Root has been notified; no expectations were rewritten to hide a legitimate economic failure. Full-suite execution belongs to root. This is a surgical lifecycle/fixture correction inside a pre-existing oversized verification script, not a refactor of its 79 checks.
