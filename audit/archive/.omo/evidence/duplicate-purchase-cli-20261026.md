# Duplicate-purchase CLI repair

Owned implementation: `server/src/scripts/fix-duplicate-purchase.ts` (68 nonblank lines).
Owned regression suite: `server/src/__tests__/duplicatePurchaseRepairCli.test.ts` (125 nonblank lines).

The previous script deleted a purchase before reading its warehouse and used obsolete `stock_balances.id` SQL. Its original isolated warehouse regression is captured in `fallow-duplicate-warehouse-red.log`; the new current-schema regression fails before the fix with `no such column: id` in `duplicate-purchase-cli-red.log`.

The replacement requires explicit DATABASE_PATH, refuses the canonical live database and its symlink/hardlink aliases, and defaults to a read-only preview. Applying requires --apply. The writable application database and purchase model are imported only after those gates; the same application singleton is passed into PurchaseModel.void so its supplier-ledger transaction uses the same connection. A consistent SQLite online backup precedes the canonical operation. No migrations are run; the copy must already have the current schema. Missing/already-voided targets are no-ops. Connections close before returning. The original purchase number remains PURCH-2026-0004.

## Verification

Invocations from `server/`:

```sh
npx jest --runInBand --runTestsByPath src/__tests__/duplicatePurchaseRepairCli.test.ts
NODE_V8_COVERAGE="$PWD/../.omo/evidence/fallow-duplicate-cli-v8" npx jest --runInBand --runTestsByPath src/__tests__/duplicatePurchaseRepairCli.test.ts
npx tsc --noEmit --esModuleInterop --target ES2020 --lib ES2020,ES2022 --module commonjs --skipLibCheck --strict src/scripts/fix-duplicate-purchase.ts
npx eslint src/scripts/fix-duplicate-purchase.ts src/__tests__/duplicatePurchaseRepairCli.test.ts
```

All subprocesses receive `TS_NODE_PROJECT=tsconfig.test.json`. Raw source-mapped coverage lives in `.omo/evidence/fallow-duplicate-cli-v8/` (8 CLI processes); function invocation summary: `duplicate-purchase-cli-coverage-summary.log`. The worker does not integrate raw coverage into root's final report.

Seven CLI scenarios:

1. Warehouse 2 purchase: warehouse 1 stays 10, warehouse 2 falls 5 to 0, original row/batch retained, void attribution recorded, canonical GL voided, supplier reversal trace retained, remaining inventory/AP 5000, consistent pre-void backup, repeat no-op.
2. No --apply: read-only preview, exact serialized database unchanged, no backup.
3. Empty DATABASE_PATH: exit 1 before opening any database.
4. Canonical live directory: exit 1 before opening the live database.
5. Linked active payment: exit 1, recorded-payments reason, exact serialized database unchanged.
6. Consumed batch fixture: exit 1, already-sold/consumed reason, exact serialized database unchanged.
7. Missing target: exit 0 no-op, exact serialized database unchanged, no backup/schema initialization.

The first complete run passed 7/7 (`duplicate-purchase-cli-green.log`, 88.495s), before adding explicit legacy-header synchronization and supplier reversal assertions. The strengthened run exposed a genuine canonical purchase defect: 6/7 passed and the main scenario found `journal_entries.voided = 0` while matching journal_lines were voided (`duplicate-purchase-cli-final.log`). The assertion was not weakened. Root expanded ownership to `PurchaseModel.void`, the common primitive used by every purchase caller; the intentionally line-only generic accounting helper remains unchanged.

The canonical purchase fix selects headers owned by direct PURCHASE reference or linked PURCHASE journal lines, excludes every header with remaining active lines, and retires selected headers through the existing StockMovementModel.voidJournalEntry inside the original transaction. Direct legacy headers without lines are included; unrelated reference identities and mixed groups with active unrelated lines are preserved. No raw GL posting or schema migration was introduced.

New direct model regression: `server/src/__tests__/purchaseVoidJournalHeaders.test.ts`. Both tests failed before the source fix (`purchase-void-headers-red.log`): header ownership/attribution/idempotency, and injected header-retirement failure requiring rollback of the purchase, supplier ledger and canonical lines. The focused post-fix run includes these two tests, all seven CLI cases, purchaseVoid, accountingInvariants and glBalanceInvariant; captured artifact `purchase-void-headers-green.log`.

Final observed result: **exit 0; 5/5 suites, 62/62 tests passed**, 125.203 seconds. Exact invocation from `server/`:

```sh
npx jest --runInBand --runTestsByPath src/__tests__/purchaseVoidJournalHeaders.test.ts src/__tests__/duplicatePurchaseRepairCli.test.ts src/__tests__/purchaseVoid.test.ts src/__tests__/accountingInvariants.test.ts src/__tests__/glBalanceInvariant.test.ts
```

The final CLI assertions now pass for both GL stores, supplier reversal trace, correct warehouse, retained records and idempotency. The direct model tests additionally prove legacy line-less headers retire, linked headers retire, mixed active groups/unrelated identities remain active, and a header update failure rolls the whole reversal back. The generic accounting line-only void/restore contract was not changed.

Raw V8 artifacts were captured before the final Purchase.ts header fix. They remain current for the unchanged CLI script sources; root must not merge their obsolete Purchase.ts mappings over current full-suite model coverage. Root was explicitly notified. No further source/test edits or checks are running in this worker.

Strict script typecheck exited 0 with no diagnostics. Scoped ESLint exited 0 (existing package-module warning only); artifact `duplicate-purchase-cli-lint.log`. Full accounting invariants and full server suite remain root-owned and are not claimed here.

The backup inspection initially counted SQLite WAL/SHM sidecars as separate backups. That test-only filename filter was corrected to count actual timestamp/PID snapshot filenames; the full seven-scenario suite then passed. No production/accounting expectation was changed for that correction.
