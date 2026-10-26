---
slug: unapplied-customer-cash-ui
status: awaiting-approval
intent: clear
review_required: false
approach: Customer-detail cash workspace using Stage E operations, with read-model prerequisites and durable receipt replay protection.
pending-action: Obtain approval of the proposed UI and backend read contracts before implementation.
---

# Unapplied customer cash: proposed UI plan

## Summary

Add an **Unapplied Cash** tab to Customer Detail, alongside Overview, Invoices,
Ledger, Payments and Statement. Keep **Record Payment** for immediate invoice
settlement; add a separate **Receive Advance** action for money received before
settlement. The new tab shows cash held, receipt history and application/refund
history, with **Apply to Invoices**, **Refund Cash** and **Reverse Receipt** actions.

The approved backend plan ends at Stage E. This is a new proposal, not an
extension of that approval. No product code is changed by this planning task.
Execution is direct, without subagents, and requires the user's approval.

## Affected user and ideal state

| ID | Desired result | Current gap | Work |
|---|---|---|---|
| IS1 | A cashier records advance cash without inventing an invoice or allocation. | Existing customer modal requires fully allocated invoice payments. | F2, F3 |
| IS2 | Staff distinguish outstanding receivables, return/store credit and cash held. | Existing customer metrics and payment models do not expose the new cash pool. | F1, F2, F3 |
| IS3 | Staff apply cash once, with an explicit date and invoice allocation amounts. | No Flutter path invokes the apply endpoint. | F2, F4 |
| IS4 | Staff refund available cash and reverse only unused receipts. | No Flutter path invokes these operations or explains dependencies. | F1, F5 |
| IS5 | Retries never collect, apply or refund cash twice, including after server key cleanup. | Shared retry-key helper exists, but receive replay currently expires after 30 days. | F1, F2, F3, F4, F5, F7 |
| IS6 | History, balances, cash direction and permissions remain trustworthy. | Missing cash read API; unified payments currently labels all customer rows as inflows. | F1, F6, F7 |

## Components and verified reference points

| Component | Existing reference | Planned change |
|---|---|---|
| Customer navigation | `lib/features/customers/customer_detail_screen.dart:42` | Add sixth tab and distinct receive action; retain page-scoped date range. |
| Existing invoice settlement | `lib/features/customers/customer_payment_modal.dart:37` | Preserve behavior; borrow existing dialog/form primitives rather than mixing workflows. |
| Customer payment history | `lib/features/customers/customer_payments_tab.dart:31` | Respect payment kind, refund direction and valid row actions. |
| Customer refresh | `lib/features/customers/customer_providers.dart:445` | Extend central invalidation to cash summaries/history and operation-date views. |
| Repository transport | `lib/data/repositories/repository_client.dart:51` | Reuse Dio, envelopes and headers; preserve structured domain error fields. |
| Retry keys | `lib/core/utils/idempotency_key.dart:18` | Reuse shared key generation; retain pending immutable requests through uncertain outcomes. |
| Replay retention | `server/src/utils/idempotency.ts:155` | Central completed keys are pruned after 30 days; add permanent receive replay before enabling persisted retries. |
| Payment DTO | `lib/data/models/payment.dart:8` | Parse payment kind and void state without breaking existing fixtures. |
| Unified cash movements | `server/src/models/Payment.ts:274` | Return refunds as cash outflows and receipt kinds as metadata. |
| Existing customer HTTP routes | `server/src/routes/customers.ts:1` | Add authenticated, authorized cash read endpoints. |
| Financial mutations | `server/src/services/unappliedCashService.ts:38` | Reuse existing receive/apply/refund/reverse; no new posting implementation. |
| Design | `docs/DESIGN.md:1` | Existing theme, spacing, typography, dialogs, dense tables and responsive behavior. |
| Mutation contracts | `docs/API.md:403` | Stage E endpoints and error codes remain authoritative. |

Discovery used the existing code graph plus direct source checks. The listed
gaps concern the inspected paths, not an assertion of exhaustive repository coverage.
The worktree contains prior uncommitted phase work; preserve it and do not reset it.

## Proposed product choices for approval

1. Put the complete workspace on Customer Detail; do not create a separate
   sidebar module. Keep the existing Record Payment action unchanged.
2. Label the new receipt action **Receive Advance** and the balance **Unapplied
   Cash**. Add helper text: cash held for this customer, separate from store credit
   and invoice balance. Receiving cash does not mark invoices paid.
3. Staff choose invoice allocations, but not funding receipts. The server's
   existing FIFO source selection remains authoritative. No automatic use of this
   balance at checkout or during invoice creation.
4. Require a nonblank reason in the UI before reversal, up to 500 characters;
   the existing API may continue accepting an omitted reason for other clients.
5. Include the backend read/projection changes and durable receive replay below.
   A Flutter-only implementation cannot derive live capacity from paginated rows
   or make indefinite persisted receive retries safe after server key pruning.

These choices are proposals, not previously approved business rules. Approval
of this document accepts them; otherwise revise the specific choice first.
Test strategy is red-before-green, including repository, provider, widget,
mounted-route and accounting regression tests.

## Scope and guardrails

Use Flutter, Riverpod, Dio, go_router, PlutoGrid and the existing component
system. No new package or paid service is needed. English and Urdu are in scope.
Desktop is primary; narrow layouts must remain usable with scrolling forms,
stacked summaries and compact cards. No redesign of unrelated screens.

Do not repair, reconcile, activate or repeatedly audit historical dummy records.
Use clean isolated fixtures to prove new transactions. Do not change accounting
equations, weaken integrity checks, migrate the live database or write to
`server/database/erp.db`. F1 requires a new registered migration for durable
receipt replay metadata. Test it on isolated databases; never alter an existing
migration or backfill historical dummy receipts to implement this protection.

No un-apply, refund reversal, supplier advances, return-credit activation,
checkout auto-application, accounting-rule changes or new reports. No commits
unless the user explicitly requests them.

## Delivery order and dependencies

F1 -> F2 -> F3 -> F4 -> F5 -> F6 -> F7. F1 establishes the read and durable replay
contracts before widgets depend on them. Each stage supplies failing tests first,
then implementation
and observed passing evidence. Do not start the next stage over an unexplained
failure. All work is performed directly, not delegated.

## Todos

- [ ] 1. F1: Supply UI read contracts, payment metadata and durable receive replay.
  - Recommended task executor category: backend implementation, direct execution.
  - Add a read-only model `server/src/models/UnappliedCash.ts`; thin handlers in
    `server/src/controllers/unappliedCashController.ts` and routes in
    `server/src/routes/customers.ts`. Prepared statements only; no SQL in controllers.
  - Add `GET /api/customers/:id/unapplied-cash?operation_date=YYYY-MM-DD&page=1&limit=20`.
    Require `payments:read`; validate IDs, dates and bounded pagination. Return
    `{success,data:{customer_id,operation_date,remaining_amount,available_amount,
    refundable_amount,receipts:[...]},pagination:{currentPage,totalPages,totalItems,limit}}`.
    `remaining_amount` is the current total live pool, independent of history
    pagination. Available/refundable totals obey the service's source eligibility
    and receipt-date cutoff for the chosen operation date; they are current
    remaining capacities, not historical balances as of that date.
  - Receipt rows include source ID, payment ID/number/date/method, original,
    applied, refunded and remaining amounts, void state and `can_reverse`.
    Return all receipt states, including used and voided, with stable date/ID
    ordering. `can_reverse` is a dependency hint, not a guarantee: period and
    cash-timeline checks still run on POST. Exclude RETURN_CREDIT from all totals.
  - Add `GET /api/customers/:id/unapplied-cash/activity?page=1&limit=20&fromDate&toDate`:
    paginated APPLY/REFUND applications, operation date, amount, application ID,
    linked refund payment and invoice/source lines. Filter history by the existing
    customer-detail range; summary/capacity must not change with that range.
    Return 404 for a missing customer; 401/403 for authentication/permission denial.
  - Add `payment_kind` and `voided_at` to existing payment list/detail projections.
    In unified payments expose nullable `payment_kind`; preserve existing source,
    party and absolute-amount contracts, but classify customer REFUND as `out`.
    Keep source/type filters compatible. Apply creates no second cash movement.
  - Add a new immutable migration using the next unused sequence number,
    registered in `server/src/config/database.ts`, for
    `unapplied_receipt_replays`: customer ID, normalized idempotency key, canonical
    request hash, original payment ID and original response amount, with a unique
    constraint on `(customer_id, idempotency_key)` and payment/customer references.
    Retain these rows permanently, including after receipt reversal; no cascading
    deletion or inclusion in the central key-pruning job. No historical backfill.
  - In the receive operation's existing immediate transaction, check durable
    replay before current customer/period checks or financial writes. Same key
    and canonical body returns the original result; changed body returns 409
    `IDEMPOTENCY_CONFLICT`. Persist replay metadata atomically with the receipt,
    source, GL and central claim. Failure rolls everything back. A replay of a
    subsequently voided receipt returns its original ID, never a replacement;
    the UI refreshes the receipt's current state separately. Central 30-day
    pruning remains unchanged for other operations. Apply/refund already retain
    their permanent application records and must retain that protection.
  - Add authenticated `GET /api/unapplied-cash/capabilities` in
    `server/src/routes/unappliedCash.ts`, returning static replay policies:
    receive `durable-v1`, apply/refund `permanent-application-v1`, reverse
    `guarded-status-v1`. It exposes no financial/customer data and needs no
    `payments:read` grant, preserving the create-only receive workflow. Actual
    reads and POSTs retain their own permission checks. Advertise each policy
    only when its corresponding contract is implemented. F2 requires a fresh
    online capability response before permitting receive or resuming persisted
    writes; never infer support from the API version, local age or cached data.
    A missing marker means unsupported, not permission to send an old request.
  - Red tests: add `server/src/__tests__/unappliedCashReadApi.test.ts` for mounted
    reads, cross-customer isolation, pagination-independent totals, date eligibility,
    non-spendable return sources, consumed/refunded/voided sources, no-write reads,
    and permissions. Add refund-direction regressions to existing cash-movement tests.
  - Add a lost-response regression to `unappliedCashApi.test.ts`: receive commits,
    discard its response, advance the pruning clock beyond 30 days, call the real
    `pruneIdempotencyKeys` and assert the central receive claim was removed. Retry
    the same mounted POST/body/key and assert the original payment ID, one receipt,
    one source and one GL posting group. Changed payload must still return 409.
    Repeat after receipt reversal; no new receipt or cash posting may appear.
    Test rollback/retry, concurrent duplicate requests, migration constraints and
    retention across database reopen. Use fixture clocks/databases, not real waits.
    Test capability authentication and create-only access without financial reads.
  - QA: guarded targeted Jest run for new read tests, `unappliedCashApi.test.ts`,
    `unappliedCashGl.test.ts`, `cashTruth.test.ts` and `accountingInvariants.test.ts`;
    run server typecheck/lint. Record commands and results in
    `audit/unapplied-cash-ui-f1.md`. Document contracts in `docs/API.md`.

- [ ] 2. F2: Add typed client data, structured errors and safe operation state.
  - Recommended task executor category: Flutter data/state implementation, direct execution.
  - Add `lib/data/models/unapplied_cash.dart`,
    `lib/data/repositories/unapplied_cash_repository.dart` and
    `lib/features/customers/unapplied_cash_providers.dart`; extend
    `lib/core/api/endpoints.dart`, existing Payment/UnifiedPayment DTOs and refresh hooks.
  - Repository methods map exactly to F1 GETs and all four Stage E POSTs, with
    snake_case bodies, explicit operation dates and `Idempotency-Key` on every write.
    Never call legacy payment creation with an unallocated amount.
  - Preserve optional domain `code` and typed dependency details in `ApiError` and
    transport parsing, including `blockedBy`; keep existing string-error envelopes
    compatible. Never display raw exception dumps or log sensitive payloads.
  - Use integer minor units for form calculations and allocation totals; convert
    only at the API boundary. Reject nonfinite, nonpositive and excessive values;
    accept at most two entered currency decimal places. Server remains authoritative.
  - Keep one immutable normalized body and key per attempted operation. Disable
    repeated submission while pending; retry an uncertain outcome with the exact
    same body/key, not a newly generated key. Do not allow editing an uncertain
    request into a new payment. After confirmed success, clear it and refresh.
    Same-key retry alone is not sufficient evidence of safety: the server must
    support the durable contract recorded when this request was first dispatched.
  - Add a small feature-scoped pending-operation store using the existing local
    preferences dependency: persist before dispatch, scope by API server and user,
    retain after timeout/navigation/restart, and offer Resume/Retry on return only
    after a fresh online replay-capability check. Persist operation kind, first
    dispatch time and confirmed replay policy with the immutable body/key.
    Store no auth tokens, isolate other users, and delete confirmed operations.
    Do not silently replay on launch or claim that lost local state proves failure.
    Receive retries under `durable-v1`, and apply/refund under their permanent
    application contract, remain safe after central key pruning. If the original
    guarantee is absent or the server no longer advertises support, enter
    `recovery_required`: disable POST and key rotation, retain the request and
    explain that its outcome must be verified. Never treat age, an empty history
    page or a missing central key as proof it did not commit. Unsupported/legacy
    pending requests require explicit review of that single operation, not a
    historical balance audit or automatic reconciliation/repair.
  - Reverse has no permanent replay record. Persisted reversal recovery must
    fetch current receipt status before any resubmission: if already voided, show
    that current state without claiming this request caused it; if still unused
    and live, offer the guarded same-key reversal. Missing/inaccessible status
    stays `recovery_required`. It must never create a replacement receipt.
  - Fetch financial capacities online rather than accepting offline cached reads
    as authorization to spend. Explicitly invalidate affected repository cache
    keys after successful POSTs, including `/unapplied-cash/*` writes whose URL
    does not identify the customer. Provider invalidation alone is insufficient.
  - Red tests: new `test/repositories/unapplied_cash_repository_test.dart`,
    `test/features/customers/unapplied_cash_providers_test.dart` and pending-state
    tests. Assert exact URLs/bodies/headers, nullable result IDs, error details,
    stable retry after timeout/restart and after central pruning, missing/changed
    capability blocking POST, unsupported pending requests entering recovery,
    reversal status recovery, different-user isolation, cache freshness
    and all affected provider refetches. Run these with `flutter test <paths>`;
    record evidence in `audit/unapplied-cash-ui-f2.md`.

- [ ] 3. F3: Build the customer workspace and receive flow.
  - Recommended task executor category: Flutter UI implementation, direct execution.
  - Add `lib/features/customers/customer_unapplied_cash_tab.dart` and
    `unapplied_cash_receive_dialog.dart`; update Customer Detail to six tabs.
    Use existing theme tokens, MovableDialog and form/date/toast primitives.
    Record new interaction/state rules in `docs/DESIGN.md` before using them.
  - Header actions are distinct: Record Payment and Receive Advance. On narrow
    screens use a wrapping/action menu layout rather than overflowing the title.
    Gate receive by `payments:create`; cash reads by `payments:read`. Lack of read
    permission must not be mistaken for zero balance or prevent an otherwise
    authorized receive action. Existing customer access rules remain intact.
  - Show independent invoice balance, existing store-credit value when available,
    and live unapplied cash; do not sum these into a fabricated net balance.
    Show loading, empty, error/retry and stale/offline states explicitly.
  - Receive form: fixed customer, amount, operation date and payment method.
    Methods exactly Cash/Bank/Easypaisa/JazzCash/Upaisa; no Credit, notes or reference
    fields because the Stage E strict body does not accept them. Defaults: today's
    local business date and Cash. Explain that invoices will remain unchanged.
  - Success names the operation, amount and resulting payment ID; refresh live
    reads and histories. Do not reuse a generic invoice-paid success message.
  - Red widget tests in `test/features/customers/unapplied_cash_receive_test.dart`:
    zero invoices, valid receive by taps, bad input/no POST, create permission,
    already-in-credit conflict, duplicate taps, timeout/retry and offline gating.
    Record test output and rendered dialog/workspace screenshots in
    `audit/unapplied-cash-ui-f3.md` and `audit/screenshots/unapplied-cash-ui/`.

- [ ] 4. F4: Apply existing cash to invoices without collecting more money.
  - Recommended task executor category: Flutter UI implementation, direct execution.
  - Add `lib/features/customers/unapplied_cash_apply_dialog.dart`. Require
    `payments:update` for the action and existing invoice-read permission for
    invoice selection; explain unavailable access rather than showing an empty list.
  - Fixed customer, operation date, date-eligible cash capacity, searchable open
    invoices, per-invoice allocation amounts, selected total and cash remaining.
    Load all eligible invoice pages needed for selection; do not mistake page one
    for the customer's complete invoice set. Exclude future/cancelled/deleted and
    settled invoices. Fetch fresh balances when opening or changing operation date.
  - No cash-collection amount or payment-method field. Unique invoice lines,
    positive amounts, per-invoice balance cap, total within eligible pool and at
    most 1,000 lines. Optional Auto Allocate uses oldest invoice date then ID and
    fills only available capacity; staff can review/edit before explicit confirm.
  - On 409, show the domain explanation, refresh current capacities/balances and
    preserve entered values for review; never silently clamp and resubmit. Unknown
    outcome instead resumes the immutable keyed request, even if refreshed capacity
    is now lower because the first attempt already succeeded.
  - Red widget tests in `test/features/customers/unapplied_cash_apply_test.dart`:
    multi-invoice allocation, partial application, no cash-method field, source
    date cutoff, fractional totals, stale invoice/pool conflict, permissions and
    safe replay. Verify invoice status/balance refresh after success. Evidence:
    `audit/unapplied-cash-ui-f4.md`.

- [ ] 5. F5: Add refund and dependency-safe reversal.
  - Recommended task executor category: Flutter UI implementation, direct execution.
  - Add `unapplied_cash_refund_dialog.dart` and `unapplied_cash_reverse_dialog.dart`
    under `lib/features/customers/`. Refund requires `payments:create`; reversal
    requires `payments:delete`. The server always rechecks authorization/state.
  - Refund shows cash-out language, fixed customer, date-eligible refundable
    amount, positive entered amount and method. Explain it refunds the FIFO pool,
    not an arbitrarily chosen receipt. Confirm amount/method/date before posting.
    Show `INSUFFICIENT_CASH` and period-lock errors as actionable failures, with
    no local balance deduction and no invented negative cash allowance.
  - Reverse only offers live unused UNAPPLIED_RECEIPT rows. Show original receipt
    number/amount/date and require reason. No editable reversal date: the backend
    uses the original receipt date. Used/partly-refunded/voided receipts have a
    disabled or absent action with explanation; a raced dependency remains 409.
    Display linked source/invoice blockers without exposing raw response JSON.
  - Do not offer generic edit/delete for advance/refund documents, or offer an
    unsupported un-apply/refund reversal. Existing ordinary receipts retain their
    existing valid actions. Refresh cash/history after successful operations.
  - Red widget tests in `test/features/customers/unapplied_cash_refund_reverse_test.dart`:
    partial refund, too much/insufficient bank-cash, used-receipt rejection with
    blockers, closed original period, repeated reverse replay, permissions and
    pending retry. Evidence: `audit/unapplied-cash-ui-f5.md`.

- [ ] 6. F6: Integrate all affected payment surfaces and localization.
  - Recommended task executor category: Flutter integration, direct execution.
  - Update `customer_payments_tab.dart`, `features/payments/payments_screen.dart`,
    `payment_detail_dialog.dart`, `unified_payment_detail_sheet.dart`, relevant row
    and bulk-action dispatch, `unified_payment_labels.dart`, and shared payment
    receipt widgets/PDFs reached by these flows. Inspect callers before editing;
    don't leave a second edit/delete or mislabeled print path for new kinds.
  - Display advance versus ordinary receipt versus refund distinctly. Refunds are
    cash outflows on customer history, unified hub, detail and exports/print.
    Applications belong in cash activity with invoice links, not new cash receipts.
    Receipt reprints use persisted data, never recreate a POST. Voided receipt
    history remains visible in the new workspace; existing hub exclusions stay.
  - Add English/Urdu keys in `lib/l10n/en.arb` and `ur.arb`, generate localizations,
    and check RTL, keyboard navigation, focus, screen-reader labels, contrast,
    loading/disabled states and long customer/invoice names. Do not hardcode copy.
  - Red regressions cover kind parsing, legacy fixture compatibility, refund row
    direction, invalid edit/delete/bulk-action exclusion, print labels and
    provider refresh. Run affected repository/widget/receipt tests plus
    `node scripts/l10n-drift.js`. Evidence: `audit/unapplied-cash-ui-f6.md`.

- [ ] 7. F7: Verify the complete user journey on an isolated running app.
  - Recommended task executor category: integration QA, direct execution.
  - Use a fresh migrated fixture server/database and Flutter client, never the live
    database. Add `integration_test/unapplied_cash_flow_test.dart` and fixture
    setup/teardown using the repository's safe test patterns. Do not run a fixture
    setup against an arbitrary configured server; assert the isolated target first.
  - Journey A: create a fresh customer, receive 500, create an invoice for 400,
    apply 400, refund 100. UI shows zero cash held and settled invoice; persisted
    payments show one 500 advance and one 100 outflow, not an extra 400 cash receipt.
    Verify balanced GL and accounting invariants A-N through server integration tests.
  - Journey B: separate unused receipt, reverse with reason; it cannot be applied
    or refunded afterward. Journey C: response lost after commit, safe same-key
    retry/resume after more than 30 days and actual central-key pruning, one
    financial write. Restart the client with its persisted request before retry;
    also verify unsupported capability enters recovery without issuing a POST.
    Exercise read-only/partial permission
    roles, closed period, another-session capacity change and network failure.
  - Capture workspace and every dialog in light/dark themes at 1440x900 and
    390x844, English and Urdu; include error, empty and pending states, scrolled
    dialog ends, keyboard focus and full readable totals. Use an agent-controlled
    Flutter runtime/browser and actual taps, not code inspection alone.
  - Run targeted tests after each stage. At final integration, run full affected
    server and Flutter suites plus typecheck/lint/analyze/l10n checks using
    `scripts/check.sh`; use the guarded server test runner as required to protect
    canonical DB fingerprints. No historical repair/reconciliation scripts.
    Record actual command exit codes/counts, warnings and environment limitations.
  - Final evidence: `audit/unapplied-cash-ui-final.md`, with screenshots and
    test-result paths. A blocked runtime test is reported as unverified, not passed.

## Final verification wave

- [ ] F1. Verify every product choice against mounted API and rendered UI evidence;
  no code-only completion claim. All four operations and failure paths must work.
- [ ] F2. Check accounting invariants, authorization, exact-key retries after
  central retention expiry, permanent receipt replay, fail-closed recovery, cache
  freshness, financial direction and absence of writes to the live database.
- [ ] F3. Check design-system fidelity, English/Urdu, narrow/wide layouts, light/dark,
  accessibility and legacy invoice-payment behavior against fresh captures/tests.

## Commit strategy

Do not commit without explicit authorization. If later requested, group focused
changes by F1 read contracts, F2 client foundation, F3-F5 workflows, F6 integration
and F7 verification; each group must have its relevant passing tests.

## Success criteria

All IS1-IS6 outcomes are verified; users can receive, inspect, apply, refund and
reverse eligible cash through real UI interactions. Cash held is never confused
with store credit or receivables. Refunds appear as outflows, applications do not
collect cash, uncertain retries do not duplicate money even after central keys
are pruned, unsupported recovery cannot blindly resubmit, unauthorized actions are
blocked, stale data cannot override server validation, and historical dummy gaps
are left untouched. No unexplained test failures or invented verification claims.

## Approval gate

Status: awaiting approval of the five proposed product choices and this scope.
Next action: accept or revise this proposal, then promote it to an execution plan
under `.omo/plans/` before implementation. No implementation has started.
