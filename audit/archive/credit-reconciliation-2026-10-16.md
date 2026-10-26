# Customer credit reconciliation — Stage C

Generated at `2026-10-16T06:51:01.302Z` from a consistent SQLite backup made
through an explicitly read-only source connection. The reporter opened the
backup read-only with `PRAGMA query_only = ON`. This is evidence for review;
no balances, historical credits, or production schema were corrected.

## Reproduction

From `server/`:

```bash
node -r ts-node/register scripts/reconcile-customer-credits.ts database/erp.db
```

The command requires an explicit source filename, makes a temporary SQLite
backup, reports JSON, then closes and removes the backup. It does not import
the application's database bootstrap or apply migrations.

## Source identity

- Source main-file SHA-256:
  `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f`.
- Consistent backup SHA-256:
  `09b1de6b9bfe6aa7aa656deec64b0d3d79468cca576da3813e574713469d1045`.
- Source main-file and existing WAL/SHM fingerprints were unchanged across the
  reporting command.

## Findings

Derived credit is live RETURN credit minus live REFUND debit minus live
CREDIT_OFFSET credit. Voided and reversed ledger entries are excluded.

| Customer ID | RETURN credit | REFUND debit | CREDIT_OFFSET | Stored credit_balance | Derived credit | Agrees |
|---|---|---|---|---|---|---|
| 1 | 1450.20 | 1200.00 | 0.00 | 0.00 | 250.20 | No |
| 12 | 2400.00 | 2300.00 | 0.00 | 0.00 | 100.00 | No |
| 13 | 1200.00 | 400.00 | 0.00 | 0.00 | 800.00 | No |
| 14 | 1200.00 | 0.00 | 0.00 | 0.00 | 1200.00 | No |
| 15 | 2300.00 | 550.00 | 1800.00 | 0.00 | -50.00 | No |

All five customers disagree. Customer 15's negative 50.00 is retained as a
finding. This calculation does not establish whether stored balances or
reconstructed history are authoritative.

## Accounting baseline

The existing AR invariant's arithmetic, reproduced on the isolated backup:

| Measure | Amount |
|---|---|
| Absolute GL balance for 1100 + 1110 | 3499.80 |
| Absolute customer receivable less store credit | 1699.80 |
| Historical F discrepancy | 1800.00 |

In a separate disposable historical backup, the actual migration runner
applied migration 108 and then replayed the ledger. All nine existing invariant
collector results were unchanged before/after both runs:
`glImbalances`, `customerArImbalances`, `supplierApImbalances`, `stockImbalances`,
`arImbalances`, `apImbalances`, `inventoryImbalances`, `cashImbalances`, and
`orphanSourceBatches`. The F discrepancy remained exactly 1800.00.

The migrated backup had 13 RETURN_CREDIT sources, 8550.20 credited, 1800.00
consumed, and zero refundable cash. Replay duplicated nothing, and
`PRAGMA foreign_key_check` returned no violations. Source main/WAL/SHM hashes
were unchanged. No migration was executed on the canonical database.

## Implementation checkpoint

- Stages 0–C are implemented: intercepted SQLite constructor guard, guarded-test
  runner, deterministic fixtures, complete registered schema/backfill migration,
  and read-only reporter/CLI.
- The 23 directly affected tests passed after observed failing runs for the
  missing guard, seeds, and reconciliation service.
- Initial server typecheck and lint passed; final full-suite/static evidence
  is recorded below when complete.
- Historical sources remain inert. No receive/apply/refund/reverse API has
  been added at this checkpoint.

## Stage C review gate

The approved plan requires review of this evidence before Stage D. Approval to
continue implements new unapplied-cash operations while preserving the findings
above. Historical activation and repair still require separate decisions.

## Final verification

The completed full server run exited 0:

```bash
cd server
node scripts/run-guarded-tests.cjs --maxWorkers=2 --silent --json --outputFile=/tmp/minierp-stage0-c-server-final.json
```

- **148 suites passed; 1316 tests passed; 0 failed.**
- Jest reported that a worker required forced teardown. This warning is not
  treated as a clean process-lifecycle result or attributed to pre-existing
  code without a baseline comparison.
- Follow-up: all **23 new tests passed** with `--runInBand --detectOpenHandles`;
  the follow-up exited 0 and reported no open handles. Evidence is in
  `server/.tmp-test/unapplied-cash-handle-check.json`.
- Final server `npm run typecheck`, `npm run lint`, and `git diff --check`
  passed. Lint emitted the existing Node module-type configuration warning.
- The guarded runners compared source main/WAL/SHM fingerprints around their
  entire child runs and exited 0. No canonical migration or repair was run.
- Earlier full-run attempts were interrupted/rescheduled and provide no full
  verdict; the 148-suite result above is from the completed replacement run.
- Flutter tests, Flutter analysis, and l10n drift were intentionally not rerun:
  this completed phase changes only server behavior and supporting documents.

The Stage C approval request has been presented. Stages D/E remain unstarted
until that review gate is approved; no historical credit has been activated.
