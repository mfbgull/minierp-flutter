# F-060 — Fully voided journal lines retain active journal headers

**Status: Confirmed defect. Severity: Medium.** Audit-store/lineage inconsistency; no additional cash/GL effect demonstrated in these scenarios.

## Independent expectation and actual executed result

The reversal specification requires both accounting stores to reflect a financial void. A header with every child journal line voided should not continue to advertise itself active. Canonical journal_lines remain the financial authority; this finding does not treat a header amount as new cash or revenue.

`node accounting-audit/tests/payable-cash-extension.cjs` executes supplier advances/applications/voids, credit-expense payments/void/cancel and opening-seed replacement. Final retained run `payable-cash-run-GIxBh2` makes41 mounted API requests. Its552 checks have535 passing economic/control assertions and17 repeated header-status failures. All expected signed balances remain correct; individual active journals balance. The17 failures are repeated observations of one shared defect, not17 independent defects.

Independent read-only SQL joins journal_entries to journal_lines, groups each active header and requires child_count>0 with active_child_count=0. It finds **nine stale active headers** in the final fixture. Exact IDs/reference metadata/child counts are in [final-extension-verification.json](../../evidence/final-extension-verification.json), F060. This excludes headers that still have active children.

## Root cause / evidence / scope

`server/src/services/accountingService.ts:1429–1455`, `voidJournalLinesByReference`, updates only journal_lines. The exercised callers leave corresponding journal_entries.voided at0. Old and new source copies of this helper match; a separate later working-tree change to Purchase.void is outside this audit and does not establish that these advance/expense/opening callers are fixed.

Evidence: `accounting-audit/evidence/payable-cash-run-GIxBh2/results.json`, ordered api-events.json and each request's before/after SQL snapshot, plus retained erp.db. `node accounting-audit/tests/final-extension-verifier.cjs` opens it with readonly/fileMustExist and verifies the9 stale headers and0 unbalanced active line groups. An earlier464-check positive run omitted the header test and does not disprove this mismatch.

No historical replay or boot-induced duplicate posting was executed; no such financial impact is claimed. Current canonical report totals are correct in these bounded fixtures. The proven impact is conflicting active/void audit status across the two stored representations.

Recommended correction: coordinate line and applicable header status/attribution through the shared reversal primitive without voiding unrelated active children. Regression: real advance application/advance void, expense-payment void/cancel and opening replacement; assert both stores, lineage, signed balances, idempotent repeat and rollback on failure. Preserve original headers/lines. No production fix applied.
