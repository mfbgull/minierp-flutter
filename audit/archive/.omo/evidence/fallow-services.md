# Fallow service remediation evidence

Scope: service lane of `.omo/plans/fallow-remediation-2026-10-21.md`. Original report: `audit/fallow-tools/fallow-before-20261021.json`. Thresholds remain cyclomatic >20 or cognitive >15. No baseline/configuration/suppression changes were made in this lane.

## Original finding dispositions

| Original path/symbol/line | Disposition |
|---|---|
| services/invoiceReturnService.ts txn:301 | Extract proportional header-discount valuation, requested settlement validation/posting, and legacy settlement processing. Reuse returnable-invoice validation while retaining both pre-transaction and fresh in-transaction reads. |
| services/cashService.ts getCashAccountTransactions:529 | Extract financing/refund transaction collection; retain each query, amount sign, classification, order, and final stable date sort. |
| services/cashService.ts collectFlows:102 | Extract historical flow folding with the original floor/upper bound and individual SQL predicates. Opening balances and current-period flows remain in the orchestrator. |
| services/InvoiceCreationService.ts transaction:155 | Extract idempotency replay and credit validation/application, retaining every call at its original point inside the transaction. |
| services/InvoiceCreationService.ts create:111 | Extract payment-leg normalization, method validation and currency summation; preserve credit validation and due-date ordering. |
| services/accountingService.ts postEntry:243 | Extract normalized-line validation and exact minor-unit balance validation. Period checks/creation and posting transaction remain in original order. Root's removal of openPeriod preserved. |
| services/paymentValidation.ts validateSupplierPayment:110 | Extract target-document validation after allocation shape/duplicate checks; bill/PO/purchase queries, period checks, balance limits and error precedence preserved. |
| services/reportQueryEngine.ts executeReport:204 | Extract SELECT alias decoding; main/count SQL, parameter slicing, limit and error boundary preserved. |
| services/reportQueryEngine.ts buildSelectClause:347 | Extract individual selection rendering and extra computed sort selections; retain validation and grouped aggregate order. |
| services/reportQueryEngine.ts assertComputedNamesAreSafe:166 | Extract reserved real/registry/joined column names; retain plain identifier, collision, then duplicate-name validation order. |
| services/reportQueryEngine.ts resolveNeededJoins:464 | Extract referenced field collection and express membership with some(); join construction and ordering preserved. |
| services/forecastService.ts readCachedForecasts:655 | Extract cached-item initialization and cached recommendation/safety-stock calculation. Preserve defaults, rounding, period mapping, service-level bucket choice and returned order. |
| services/SupplierPaymentService.ts callback:24 | Extract advance funding validation before the original period guard and writes; retain supplied method and source-date/amount errors. |
| dup:827d201f (accountingService three instances) | Required cash/bank account resolution has one private implementation, consumed by supplier payouts, owner contributions and cash withdrawals. Caller-specific account validation, posting lines and missing-account messages remain individual. |

`fallow-services-health-final.json` is a fresh Fallow 3.34.1 report. Programmatic filtering of `findings` by `cyclomatic > 20 || cognitive > 15` returns an empty array: all 13 original structural findings and new helpers are below both thresholds. The report still has 31 CRAP-only findings. These are explicitly pending root's full source-mapped coverage wave; they are not claimed resolved by this lane. Fallow exits 1 for those health findings; stderr is in `fallow-services-health-final.stderr`.

## Verification artifacts

Commands run from `server/` unless noted. Existing suites exercised real service/database/API behavior using the repository's isolated test databases.

| Scenario / exact invocation | Binary observable | Artifact |
|---|---|---|
| `npm test -- --runInBand --runTestsByPath src/__tests__/invoiceCreationService.test.ts src/__tests__/invoiceReturnAcceptance.test.ts src/__tests__/supplierPaymentAllocation.test.ts src/__tests__/accountingInvariants.test.ts src/__tests__/reportExpressionSecurity.test.ts src/__tests__/forecastConfigInjection.test.ts src/__tests__/invoiceReturnEdgeCases.test.ts` before edits | 7 suites, 72 tests pass | `.omo/evidence/fallow-services-before.log` |
| Same seven-suite invocation after first service extraction batch | 7 suites, 72 tests pass | `.omo/evidence/fallow-services-after.log` |
| `npm test -- --runInBand --runTestsByPath src/__tests__/supplierPaymentAllocation.test.ts` after supplier changes | 1 suite, 7 tests pass | `.omo/evidence/fallow-services-payment-after.log` |
| `npm test -- --runInBand --runTestsByPath src/__tests__/cashTruth.test.ts src/__tests__/cashInflowReversal.test.ts` before cash edits | 2 suites, 16 tests pass | `.omo/evidence/fallow-services-cash-before.log` |
| Same two-suite invocation after cash edits | 2 suites, 16 tests pass | `.omo/evidence/fallow-services-cash-after.log` |
| Root: `npx --yes fallow@3.34.1 health server/src/services --complexity --format json` (final run uses the same cached 3.34.1 launcher) | No functions exceed either structural threshold; 31 CRAP-only findings retained for coverage wave | `.omo/evidence/fallow-services-health-final.json` |

Final residual-extraction retest, new explicit account-lookup tests, final typecheck and lint results will be appended after their running processes complete.

## Retained advisory and review

`unappliedCashService.ts` is retained. Its responsibility is the receive/apply/refund/reverse lifecycle of unapplied cash, with common idempotency, source draw, cash timeline, customer validation and posting helpers. Direct import inspection finds one production consumer (`controllers/unappliedCashController.ts`) and three tests (`unappliedCashReplay`, `unappliedCashGl`, `invoiceCreationService`). Graph discovery found its service methods but inbound tracing for receive returned no callers despite these source consumers, so the graph result is not treated as proof of unreachability. No function in this service exceeds the structural thresholds. Its high-impact/CRAP advisory needs accurate coverage, not an arbitrary file split.

Graph discovery and coverage checks were used before/refreshed after editing. Coverage checks reported no recorded parse issue, with metadata changed for recently edited files; direct source was used for edits and Fallow/typechecking for current evidence.

Self-review: helpers have concrete domain responsibilities; writes remain inside existing transactions; SQL predicates, financial arithmetic, error text and validation order were preserved. The existing large service files remain large (accounting 1208, cash 549, invoice creation 319, return 1228, report 541, forecast 900 nonblank/noncomment lines by a simple line filter). Repository instructions requiring targeted edits and no gratuitous split take precedence over the generic skill's file-size recommendation. No new runtime dependency, broad abstraction, enum deletion or live-database repair was introduced.

Full server coverage/suite integration belongs to root after all lanes merge. Flutter was not changed and its full suite was not rerun.
