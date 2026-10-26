# Remaining audit implementation

User instruction: tackle all remaining issues one by one. This ledger records
current work; historical status sections in FINDINGS-STATUS.md are not closure evidence.

## Accepted product decisions

- ACCT-006: preserve current stock costing and show a clear warning for backdated sales.
- ACCT-009: implement accrual expenses, supplier bills, input tax and advances in this pass.
- ACCT-008: preserve keyless compatibility and complete migration telemetry for both invoice APIs.
- Existing historical dummy accounting gaps remain deferred under AGENTS.md. No live repair.

## Execution queue

| Finding | Current work / acceptance |
|---|---|
| CODE-002 | Targeted verification complete. Red: 10 failed / 1 passed. Green: authAuthority, authAsync, security.regression and auditRegression7: 4 suites / 71 tests passed. Full phase checks pending. |
| ACCT-013 | Targeted verification complete. Red: refund void did not throw. Green: 5 dependent suites / 63 tests, plus the mounted-route file's 7 tests. Invariants A–J hold before and after route rejection. Refund void is atomic, preserves lineage and checks original period and later cash balances. |
| PRET-002 | Targeted verification complete. Two new regressions red before fix. Automatic cash collection removed; actual refunds capped by source payments minus prior refunds across returns. Purchase-return, refund, PO-return and invariant suites passed; dependent idempotency fixture now pays the source purchase, and caller verification no longer pins source line numbers. Follow-up settlement/idempotency suites passed. |
| ACCT-010 | Targeted verification complete. Five historical regressions red before fix; 4 AR/API suites / 89 tests green. Invoice date cutoff, receipt dates, return dates/fees and bucket totals verified. Unapplied cash uses application operation_date. Legacy header-only amounts retain their existing invoice-date interpretation; no historical data is repaired. |
| CODE-001 | Targeted verification complete. Mounted desktop/mobile routes reject unknown customers/items with 404 and malformed lines with 400; production validation uses typed business errors. No rejected-request financial writes. Latest combined authority/validation/dependent run: 9 suites / 139 tests passed, including accounting invariants. |
| CODE-003 | Targeted verification complete. Server auth/password/security regressions passed; all 7 bootstrap tests passed. Three password widget regressions red before fix, then green; Flutter analyze clean. Server typecheck/lint passed. Role reads use assigned system-role authority; 12-character/72-byte policy applies to new password writes and bootstrap. Final visual QA/full suites pending. |
| CODE-004 | Targeted verification complete. Seven mounted form cases verify stable retry keys and edited-body rotation (including salary deductions); goods receipts included. Repository settlement payload corrected from settlements to allocations after a red regression. Combined repository/form run: 111 tests passed before the added seventh form; all seven forms then passed. Full phase checks pending. |
| ACCT-006 | Targeted verification complete. Localized warning beside backdated invoice dates explains current-stock costing, including batches received later. Red warning regression then all 60 invoice-form tests passed. Current costing retained under D13. |
| ACCT-008 | Targeted verification complete. D13 preserves compatibility. Both canonical and deprecated mobile submit routes emit safe keyed/keyless attempt events and keyless warnings; report script aggregates supplied JSON logs. Two mounted-route regressions red then green. Existing invoice-idempotency and accounting-invariant suites passed (46 tests). See INVOICE-IDEMPOTENCY-MIGRATION.md for count semantics and log retention limits. |
| PAY-002 | Verified and accepted under D13: parent-only voiding is the selected policy. auditRegression3 and auditRegression3Recovered: 2 suites / 16 tests passed. |
| WO-002 | Verified existing implementation: auditRegression9's damaged-stock cases passed in the 139-test dependent run. No additional source fix needed. |
| ACCT-009 | Targeted accounting checkpoint passed: 8 suites / 66 tests for credit expenses, bills, supplier advances, direct/PO purchase tax, refunds, tax consistency and A–J plus new account controls. Fifteen financial-form widgets passed; earlier repository/source integration checkpoint passed 120 client tests. Gross settlement ceilings, multi-line purchase replay, bill reissue after void and input-tax reporting are covered. Full server gates are running. Final visual/keyboard QA and customer-advance dependent suites remain in final verification. See ACCT-009-IMPLEMENTATION.md. |
| CODE-005 | Complete. All seven client extractions are done and verified sequentially: CSV builders/encoding, invoice responsive layout, dashboard sales-vs-purchases panel, date-picker calendar and focus state, purchase-order line editor, invoice return row and position preview, supplier allocation rows. Each moved cluster keeps its typed inputs, borrowed controllers and rendering; the parent keeps state ownership. Characterization tests were added before every move. `flutter analyze --no-pub` reports no issues and `git diff --check` exits 0. See CODE-005-EXTRACTIONS.md. |
| CODE-006 | Targeted recovery checkpoint passed 29 tests. Login storage and stale-token refresh regressions observed red then green. Twenty-four discarded-error sites now emit safe operation/type diagnostics; nine retain visible handling or usable recovery. Salary loan deductions post atomically and reverse with their parent. The analyzer cleanup that followed did not weaken any of that handling. See FLUTTER-ERROR-AND-LINT-REVIEW.md. |
| CODE-007 | Complete. The six async/resource/error-preservation lint rules are enabled and the tree is clean under them: 34 findings (32 `unawaited_futures`, one `avoid_void_async`, one `unnecessary_import`) were fixed at the source with `await`, explicit `unawaited(...)` or an import removal. No suppression, no `exclude:` entry and no rule change. `flutter analyze --no-pub` reports "No issues found!". JSON dynamic maps and valid late initialization are not treated as defects solely by count. |
| Accessibility QA | Partial but recorded. The four extracted supplier allocation rows exposed English-only accessible names (`tooltip: 'Remove'`, `'+ Add'`) in both locales; they now use `l10n.commonRemove` and `l10n.commonAdd`, and the English rendering is byte-identical so no existing assertion changed. The extracted date-picker day cells keep their `Semantics(label:, button: true)` and per-cell focus lifecycle, the extracted return row keeps its `FormFieldShell` label, and the extracted PO line row keeps its localized remove tooltip. Mounted assertions now prove the accessible tooltip of the remove actions (`tester.getSemantics(...).tooltip`). A full assistive-technology sweep (screen-reader pass on the desktop runtime) and an exhaustive WCAG contrast audit remain manual and are not claimed here. |
| DEPLOY-1 | Deferred historical dummy-data repair, not authorization to modify live records. |
| Tracker reconciliation | Complete. Every row in FINDINGS-STATUS.md now carries a GREEN status with its current evidence; ACCT-009 moved to GREEN (full verification) on the full-suite results, CODE-005/CODE-006/CODE-007 were moved off IN-PROGRESS, and the takeover repairs are recorded in this ledger. |

## Takeover repairs (2026-10-20)

The previous session stopped mid-pass with the server suite red. The failures
were re-reproduced from scratch before anything was changed, then repaired at
the source. No test was weakened, skipped or deleted.

| Area | Red state | Repair |
|---|---|---|
| `mobileInvoiceDeprecation` | The deprecated `/api/mobile-invoices/submit` answered with the typed `VALIDATION_ERROR` envelope instead of its legacy `{ error: 'Customer is required', field: 'customer_id' }` body. | `zodBodySchemas.mobileSubmit` was restored to the legacy-tolerant shape. The canonical `/api/invoices/*` route keeps typed validation; the deprecated route still rejects unknown customers with 404 and malformed lines with 400 through `InvoiceCreationService`. ACCT-008 compatibility restored. |
| `controllers` (changePassword) | The wrong-current-password case answered 400 because the fixture's new password was rejected by the new 12-character policy before the current-password check. | The fixture now uses a policy-valid new password; the assertion is still 401. The policy itself is unchanged. |
| `userSelfRole` | Three status-code failures: the test demoted the acting admin in the database, which under DB-backed authority immediately revoked that admin's authority, so the SEC-04 guard was never reached and a later case ran as a non-admin. | The self-edit scenarios now act through users that hold admin authority at request time, so the SEC-04 guard is reached and answers 400 with no update; the "admin edits another user" case answers 200 again. |
| `unappliedCashReadApi` | A token for a non-existent user was expected to answer 403; under DB-backed authority that is correctly 401. | The fixture now creates a real active user with a permission-less role and asserts 403, and additionally asserts 401 for the non-existent id. |
| `dashboardKpi`, `dashboardWeek` | The dashboard KPI cards now derive from the GL profit-and-loss report, but the two in-memory test fixtures did not have `chart_of_accounts`, `journal_lines` or `supplier_bills`. | Both fixtures were rebuilt against the GL, and the KPI cards are now asserted equal to `ReportsModel.getProfitLossReport` computed from the same data — the card and the income statement are equal by construction rather than by coincidence. |
| `auditRegression3Recovered`, `expiryDetection`, `liveDbGuard`, `envHardening` | Reported as "failed to run: worker SIGKILL/SIGTERM". | Not code defects. Re-run in band they pass (23 tests). The earlier full run was executed with unbounded jest workers on a 15 GiB machine already at load 10; suites taking 31 minutes each were the symptom. Full suites must be run with capped workers. |
| Client analyzer | 34 findings under the six new lint rules. | Fixed at the source; see FLUTTER-ERROR-AND-LINT-REVIEW.md. |
| Date-range pill at narrow widths | The financial visual QA caught a 123px horizontal overflow of the date-range pill at a 390px window. | The pill now bounds itself to the width it is given: the container, the label area and the bar text are flexible, and the bar text ellipsizes. Desktop layout is unchanged (the pill still sizes to its content). All 55 date-range picker tests and all 24 financial visual tests pass. |
| PO create body assertion | `test/widget_test.dart` still expected a pre-input-tax PO item body. | Updated to the current schema (`input_tax_amount` is now posted and accepted by the server). The production payload was not changed. |
| Return settle body assertion | `test/repositories/invoice_return_payload_test.dart` still expected `settlements`; the server reads `req.body.allocations`. | Updated to the wire contract the server consumes. |
| Password-policy fixtures | Four widget tests entered a 10- or 9-character password, which the new client-side 12-character policy rejects before the request is sent, so the expected success snackbar / error banner never appeared. | The fixtures now use policy-valid passwords. The policy itself is unchanged and every original assertion still holds. |

## Verification

Server: `npm test -- --silent --maxWorkers=2` — 164 suites, 1457 tests, 0 failures
(exit 0, 1528s). The worker count is capped because the machine has 15 GiB of RAM
and the previous unbounded run lost four suites to the OOM killer.

Client: `flutter analyze --no-pub` — no issues. `flutter test --no-pub
--concurrency=2` — 1001 tests, 0 failures (exit 0). `node scripts/l10n-drift.js` —
exit 0 (55-key fallback gap, within the 60-key cap). `git diff --check` — exit 0.

Nothing in the audit ledger is left IN-PROGRESS. DEPLOY-1 stays deferred: it is
historical dummy-data repair and no live record was touched.

No full-suite pass is claimed until the phase gates below run. Run affected regressions after each fix, accounting
invariants for financial changes, and the full affected-side suites at phase completion.
