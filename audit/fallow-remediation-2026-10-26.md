# Fallow continuation ledger - 2026-10-26

## Scope and starting state

Continues the original request to check and fix all Fallow findings. Earlier remediation and the eight-target October 22 cleanup are preserved. Starting revision: `8d292328`; current input: `.omo/evidence/fallow-current-20261026.json` (Fallow 3.34.1).

| Category | October 26 starting scan | Integration result |
|---|---:|---|
| Unused files | 9 | Actual CLI entrypoints registered; progress scan 0 |
| Live class / persisted enum warnings | 33 / 28 | Retained with existing per-symbol evidence in the October 21 ledger |
| Duplicate groups | 5 | Audit bootstrap consolidated; four previously reviewed domain/query templates retained |
| Health | 56 | Final full-suite coverage and scan pending |
| Structural health | 1 | Legacy BOM normalization extracted; progress scan 0 |

The working tree already contained unrelated accounting-audit reports, evidence, runner edits, audit decisions and local settings. They were preserved. Three clean audit CLI files were refactored only to share fixture/session setup. No live database or historical financial records were repaired.

## Fixes and verification evidence

- `correctionSafety.ts`: checks device/inode identity, including symlinks and hardlinks. Both correction entrypoints authorize before loading the database. Sixteen gate tests pass; the import-order and alias regressions were observed failing first.
- `fix-duplicate-purchase.ts`: explicit isolated target, read-only preview, apply flag, live/alias exclusion, consistent backup and canonical purchase voiding. The purchase row, batch and audit trail are retained.
- `PurchaseModel.void`: retires owned journal headers after their lines, inside the existing transaction; mixed headers with active unrelated lines stay active. Injected header failure rolls back all economic changes. Five focused suites / 62 tests pass.
- `verify-reversal-rules.ts`: starts migrations before awaiting the seed, uses current supplier/funding fixture prerequisites and closes SQLite before deleting its temporary directory. A subprocess regression caught the previous exit-0 / zero-assertion behavior. The CLI now runs all 79 existing checks. Two pre-existing tautological assertions are not treated as independent economic proof.
- Maintenance coverage: four fresh-fixture suites / nine tests exercise dry run, apply, idempotency, costing, traceability and read-only behavior.
- Script readiness: four suites / ten tests exercise actual fixture HTTP handlers, CLI source preservation and network selection. Historical audit SQL simulations still show 46 passing / four failing checks and six issues; their exit 0 is not reported as a passing audit.
- Audit fixture/session extraction: authenticated subprocess smoke passes; confinement is checked before and after application boot. Original scenario/evidence bodies and per-run prefixes stay intact.
- Coverage merger: retains the supplied Istanbul mappings, adds previously uninstrumented CLI files from V8, validates TypeScript source snapshots and generated offsets, and rejects stale captures. Repeated-input regression was observed failing before the mapping-preservation fix.

Evidence is in the dated `.omo/evidence/fallow-*-20261026.md` reports, `reversal-verification-cli-20261026.md`, and `duplicate-purchase-cli-20261026.md`. No suppression, threshold increase or replacement baseline was introduced.

## Starting health inventory (all 56 findings)

Original positions below identify the captured rows; later extractions may move functions.

| # | Original location | Symbol | Original CRAP | Disposition |
|---|---|---|---:|---|
| 1 | `server/scripts/verify-reversal-rules.ts:82` | `main` | 380 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 2 | `server/src/utils/legacyBomMigration.ts:17` | `migrateLegacyBomHeaders` | structural | Legacy normalization extracted; migration regression suites pass. |
| 3 | `server/scripts/dev/audit-trace.ts:1231` | `main` | 240 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 4 | `server/scripts/fixtures/unapplied-cash-ui.cjs:80` | `control.post("/command")` | 240 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 5 | `server/src/__tests__/glPostingMatrix.test.ts:255` | `it("SO conversion produces subledger row plu...")` | 63.6 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 6 | `server/src/__tests__/purchaseReturn.test.ts:157` | `seedPO` | 63.6 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 7 | `server/src/__tests__/purchaseReturn.test.ts:69` | `seedPurchase` | 56.3 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 8 | `scripts/openspec-archive-guard.js:96` | `main` | 156 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 9 | `server/scripts/dev/audit-trace.ts:76` | `runAllMigrations` | 132 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 10 | `server/src/__tests__/accountingInvariants.test.ts:454` | `it("voiding a stock transfer twice: second a...")` | 37.1 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 11 | `server/src/__tests__/auditRegression9.test.ts:467` | `it("splits materials + overhead between outp...")` | 37.1 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 12 | `server/src/__tests__/invoiceRestore.test.ts:25` | `insertInvoice` | 37.1 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 13 | `server/src/__tests__/search.test.ts:13` | `createFixture` | 37.1 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 14 | `server/src/models/OwnerCapital.ts:85` | `getAll` | 132 | Fresh focused coverage clears finding; owner transaction implementations retained. |
| 15 | `server/scripts/fixtures/unapplied-cash-ui.cjs:47` | `<arrow>` | 110 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 16 | `server/scripts/lib/correctionSafety.ts:56` | `assertCorrectionAuthorized` | 110 | Physical identity guard fixed; 16 authorization regressions pass. |
| 17 | `server/src/__tests__/accountingInvariants.test.ts:163` | `it("holds after invoice → payment → return →...")` | 31.6 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 18 | `server/src/__tests__/cashTruth.test.ts:68` | `it("an unpaid purchase contributes nothing t...")` | 31.6 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 19 | `server/src/__tests__/purchaseVoid.test.ts:33` | `seedPurchase` | 31.6 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 20 | `server/src/__tests__/reverseStockRestock.test.ts:442` | `it("return 2 then return 3 on same item; eac...")` | 31.6 | Executed test/fixture; final run will measure test files rather than use estimated coverage. |
| 21 | `server/src/models/OwnerWithdrawal.ts:454` | `<arrow>` | 55.9 | Fresh focused coverage clears finding; owner transaction implementations retained. |
| 22 | `server/src/scripts/backfill-batches.ts:34` | `backfillProductions` | 90 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 23 | `accounting-audit/tests/backend-controls.cjs:23` | `main` | 72 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 24 | `accounting-audit/tests/oracle-lifecycle.cjs:85` | `<arrow>` | 72 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 25 | `accounting-audit/tests/oracle-supplement.cjs:27` | `family("3b")` | 72 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 26 | `server/scripts/dev/audit-trace.ts:462` | `testFullPayment` | 72 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 27 | `accounting-audit/tests/oracle-lifecycle.cjs:53` | `api` | 56 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 28 | `server/scripts/dev/audit-trace.ts:1177` | `testCustomerStatement` | 56 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 29 | `server/scripts/recompute-item-amounts.js:50` | `main` | 56 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 30 | `server/scripts/repair-stock.ts:173` | `repairOrphanedBatches` | 56 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 31 | `docs/superpowers/verification/unapplied-cash-stage-d.cjs:76` | `main` | 42 | Historical snapshot/design harness; intentionally not replayed against live data for a metric. |
| 32 | `server/scripts/backfill-ledger-dates.js:22` | `main` | 42 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 33 | `server/scripts/dev/audit-trace.ts:569` | `testPartialPayment` | 42 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 34 | `server/scripts/dev/audit-trace.ts:645` | `testReturnWithFee` | 42 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 35 | `server/scripts/dev/audit-trace.ts:1061` | `testTransferBug` | 42 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 36 | `server/scripts/recompute-item-amounts.js:33` | `computeLineAmount` | 42 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 37 | `server/scripts/repair-stock.ts:91` | `run` | 42 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 38 | `server/src/models/OwnerWithdrawal.ts:587` | `<arrow>` | 42 | Fresh focused coverage clears finding; owner transaction implementations retained. |
| 39 | `server/src/scripts/reconcile-stock-cash.ts:44` | `flagUnbatchableStock` | 42 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 40 | `server/src/scripts/reconcile-stock-cash.ts:193` | `flagDuplicatePurchases` | 42 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 41 | `accounting-audit/run-verification.cjs:84` | `<arrow>` | 30 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 42 | `accounting-audit/run-verification.cjs:95` | `<arrow>` | 30 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 43 | `accounting-audit/tests/backend-count-risk.cjs:23` | `main` | 30 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 44 | `accounting-audit/tests/backend-extension.cjs:23` | `main` | 30 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 45 | `accounting-audit/tests/oracle-lifecycle.cjs:73` | `family` | 30 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 46 | `accounting-audit/tests/oracle-supplement.cjs:3` | `family("3c")` | 30 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 47 | `accounting-audit/tests/oracle-supplement.cjs:74` | `family("2b")` | 30 | Manual audit/oracle scenario; retained pending instrumented forensic execution; separate business failures are preserved. |
| 48 | `docs/superpowers/verification/unapplied-customer-payments.cjs:76` | `fixture` | 30 | Historical snapshot/design harness; intentionally not replayed against live data for a metric. |
| 49 | `server/scripts/apply-customer15-correction.ts:145` | `<arrow>` | 30 | Authorization ordering fixed; historical transaction replay remains a coverage boundary. |
| 50 | `server/scripts/dedupe-po.js:25` | `main` | 30 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 51 | `server/scripts/dedupe-po.js:84` | `tx` | 30 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 52 | `server/scripts/recompute-item-amounts.js:27` | `parseCurrency` | 30 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 53 | `server/scripts/reconcile-customer-credits.ts:15` | `main` | 30 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 54 | `server/scripts/rollback-customer15-correction.ts:39` | `<arrow>` | 30 | Authorization ordering fixed; historical transaction replay remains a coverage boundary. |
| 55 | `server/server.ts:105` | `getLocalIP` | 30 | Focused fixture/HTTP or CLI execution added; awaiting complete merged coverage. |
| 56 | `server/src/scripts/fix-duplicate-purchase.ts:56` | `fix` | 30 | Replaced destructive repair with canonical void; both journal stores, warehouse and rollback tested. |

## Integration verification

Pending: final server full suite with measured test-file coverage, static checks, mapped CLI merge, raw Fallow scan and new-only audit gate. Flutter code and shared API shapes were not changed; the full Flutter suite will not be rerun solely for these server changes.

