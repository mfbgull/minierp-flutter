# Independent financial code review

Reviewed 2026-10-27 against the final post-extraction working source. This final verdict supersedes interim WATCH/BLOCK assessments; earlier review history is retained in [the earlier artifact](EARLIER-FINANCIAL-REVIEW.md) and regression evidence below.

**codeQualityStatus: CLEAR**  
**recommendation: APPROVE**  
**blockers: none established within the reviewed remediation scope.**

This is an independent source and executor-evidence review. The reviewer did not rerun database-writing scenarios or open the live database. Only this review artifact was changed during final review.

## CRITICAL

None outstanding established.

## HIGH

None outstanding established. Previously identified defects were repaired and re-reviewed: count surplus master/bin mismatch; incorrect shortage/surplus valuation; salary advance nontermination and multi-period allocation; ledger-credit entitlement reuse; cumulative sibling-return entitlement removal; and legacy journal-header synchronization.

## MEDIUM

None outstanding established within the reviewed changes. Final verification now replaces the prior pending-evidence finding. Interrupted, OOM, warning-contaminated and earlier failed runs are not counted as passing evidence.

## LOW

No actionable finding recorded. Scope limitations below remain explicit.

## Final evidence independently inspected

- `SOURCE-MANIFEST.json`: independently recomputed all 50 listed SHA-256 hashes; zero mismatches against current files.
- `server-post-extraction.log` and `.exit`: 252 suites / 2002 tests passed, exit 0. Checked for late-logging and heap-OOM diagnostics: none found. This run follows the final count-helper extraction.
- `quick-complete.log` and `.exit`: exit 0; typecheck, lint, pinned Fallow comparisons, Flutter analysis and l10n drift all pass. No gate/baseline relaxation was part of the reviewed remediation.
- `flutter-clean.log` and `.exit`: 1042 tests passed, exit 0. Existing nonfatal Flutter diagnostics are not represented as a warning-free run.
- `count-extraction.log`: 6 suites / 60 tests passed, covering count, dependent inventory and accounting-invariant paths.
- `reversal-final-79.log`: 79 passed, 0 failed. The executor reports launcher exit 0; this log's scenario summary was independently inspected.
- `credit-return-final.log`: 5 actual suites / 34 tests passed, including consumed ledger credit and cumulative-return entitlement regressions.
- `header-final.log`: 2 actual suites / 12 tests passed. Command selectors that matched no additional suite are not counted as coverage.
- `reservation-compatibility-green.log`: 2 suites / 17 tests passed.
- `test-lifecycle-red.log`: queued event absent at teardown before fix. `test-lifecycle-green.log`: 4 suites / 43 tests passed afterward.
- Earlier focused red/green, snapshot valuation and mounted Flutter evidence were inspected during prior passes; final comprehensive evidence above supersedes partial-run counts.

## Final source checks

**Credit ownership and supported cancellation.** `storeCreditOwnership.ts` caps ledger-credit draws by authoritative invoice-wide settlement capacity and per-return remainder, tracks local allocation across preloaded sibling rows, and records adjustment metadata without another payment/ledger/GL leg. Shared settlement reversal rejects owned draws. `invoiceReturnService.ts:624` computes remaining entitlement after removing the proposed return and its own settlements before permitting void, protecting sibling-funded entitlement.

The target invoice cancellation path does not require a newly invented ownership-release workflow: creation includes credit offset in paid amount, and `ledgerUtils.ts:162` preserves it in recomputation. `Invoice.ts:1040` supplies the shared direct/sales-order cancellation primitive and rejects positive paid amount before mutations. `invoiceController.ts:764` also blocks paid invoice deletion; its edit guard at line 275 rejects changes to the applied credit offset. Under these supported flows the credit-funded application remains active, so retaining its draw ownership is consistent. No material ownership-restoration defect was established by this final missed-path check.

**Count layers and extraction.** Original snapshot cost is separate from actual consumed shortage cost through migration 121. New surplus correction uses the snapshot; shortage restoration uses recorded exact layers. The final helpers in `physicalCountLayers.ts:8` and `:15` preserve weighted cost/fallback, bin ordering/availability, feature flag and remainder tolerance. The caller retains batch-master decrement and all operations within the correction transaction. The extraction is cohesive reuse, not gate evasion.

**Salary.** Shared employee write validation rejects invalid/sub-cent salary; payment validates legacy salary, and advance scheduling has a 1200-period work limit. Multi-period and zero-cash recognition behavior was reviewed with the mounted regression evidence. Recognition/source reversal ownership remains enforced.

**Reservations.** `StockReservation.ts:101` preserves existing metadata-only reservations when batch/location identity is absent. Complete identities still enforce ownership and bounded reserved quantity in the same create/reactivate/release transaction. Replay avoids a second delta. The revised controller test uses a real ACTIVE row and mounted release/repeat while retaining exact reserved=1 / available=9 assertions; this corrects an obsolete mock boundary without weakening financial expectations.

**Lifecycle and fixture changes.** Test teardown disposes the activity logger before deleting fixture files and closing Winston, with cleanup in finally. The regression checks initially absent then persisted audit data, proving more than warning suppression. No-write testing flushes earlier fixture audit work before baseline and GET-generated queued work before exact total_changes equality. Dashboard fixtures add the production account-name column while retaining financial expectations. These are valid test corrections rather than weakened coverage.

## Skill perspectives and scope limits

Consulted `remove-ai-slops`, `programming`, and the TypeScript guidance. Reviewed production changes and tests for tautology, removal-only assertions, implementation mirroring, unnecessary parsing/normalization and abstraction. No outstanding material violation established. Tests exercise observable financial, stock, response-privacy and lifecycle behavior; existing project framework conventions were respected.

Historical unknown credit ownership, old count-layer provenance and null historical count snapshots are not reconstructed. Conservative locks/legacy fallback are documented; this approval does not authorize historical data repair. The bounded review does not certify every financial path or historical record as correct. Existing application reversal limitations remain product scope, and no new application-reversal UI is implied. Final approval covers the reviewed remediation at the manifest-matching source and the explicitly inspected evidence above.
