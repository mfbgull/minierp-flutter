# Customer and supplier adjustments

Approved by Gull in the implementation request, 2026-11-07.

## Goal

Represent the same business through one Party with separate customer and supplier profiles. Explicitly settle outstanding sales against recognized supplier liabilities without cash movement. A purchase of Rs 1,000 and sale of Rs 2,000 must leave Rs 1,000 receivable after adjustment.

## Contract

- Preserve original customer/supplier IDs, documents, contacts, terms, and accounting history. Migrate existing profiles to independent Parties; never auto-match names.
- Explicit linking confirms identity, refuses conflicting roles, and logs attribution. Add missing roles through existing validation. No unlink after adjustment history.
- Separate adjustment header and invoice/payable allocations. Immutable posting, protected reversal, required retry key, atomic journals and append-only subledgers.
- Both allocation totals equal the positive amount, within current document balances. Only accrued liabilities qualify. Respect document ownership, currency precision, dates and open periods.
- Post debit of source payable control account and credit of receivable control account through shared accounting service. No cash, tax, revenue, stock or profit effect.
- Authoritative document balances, payment limits, advances, returns, cancellation guards, current/historical aging and reports recognize adjustments. Preserve cash-collected and refundable-cash meanings.
- Reverse through one primitive; retain original records, append opposite subledgers, void canonical/legacy journal references consistently, rebuild balances, attribute reason/user/time. Enforce existing period protection.
- APIs under /api/parties cover linking, adding roles, position, targets, adjustment history/detail/post/reverse. Additive customer/supplier role information; permissions seeded without non-Admin grants.
- Flutter exposes linking, role badges, both balances and net, adjustment allocation/confirmation, history/detail/reversal. Use Riverpod/Dio/PlutoGrid and English/Urdu strings. Stable retry keys and both-role cache invalidation.

## Tasks

- [x] 1. Backend identity, schema, API and adjustment service.
  - Recommended task executor category: deep-high
  - Owner: adjustment_core. Tests first; mounted HTTP example, validation, retries, reversal and rollback.
- [x] 2. Existing financial workflows and reporting integration.
  - Recommended task executor category: deep-high
  - Owner: adjustment_integration. Tests first; source balance calculations, aging, refund safety, payment limits, cancellation guards and invariants A–J.
- [x] 3. Flutter workflow and widget tests.
  - Recommended task executor category: visual-engineering
  - Owner: adjustment_flutter. Tap-driven linking, allocation, confirmation, history/reversal and error states; localization and analysis.
- [x] 4. Documentation and final integration fixes.
  - Recommended task executor category: unspecified-high
  - Update API/database/reversal/decision documentation to final implementation. No unrelated historical data repair.

## Final verification wave

- [x] F1. Independent review of financial integration, API authorization and UI behavior.
- [x] F2. Run scripts/check.sh for server and Flutter, record exact outcomes and surface QA. Investigate failures without weakening tests.
  - 2026-11-09: full `scripts/check.sh` passed, exit 0 (`all checks passed`).
    All seven CI-identical gates ok: server typecheck, lint, test (--silent --coverage), fallow;
    flutter analyze, l10n drift, test (1138 passed, 1 skipped, 0 failed).
    Evidence: `.omo/evidence/party-adjustment-f2-final-checks.md`.
    Capture note: server Jest suite/test counts were truncated by the log capture;
    the gate exit code is the authoritative CI-identical result.

## Execution notes

Current checkout was clean before execution. Work occurs in the user-selected workspace; no commit, push, release, or production-data mutation requested.
Native shell tool is blocked by an existing context-mode NODE_TOO_OLD hook failure. Node REPL child-process execution remains available. Do not alter global tooling as part of this feature.
