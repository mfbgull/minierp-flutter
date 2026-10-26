# Unapplied customer cash — F1/F2 final gate

recommendation: APPROVE

Scope: final verification wave F1/F2 only. Equivalent delegated verdict: PASS.
blockers: []

## Original intent and desired outcome

originalIntent: Give staff a separate advance-cash workflow without inventing invoice allocations or conflating store credit with cash held.

desiredOutcome: Receive, inspect, apply, refund and reverse eligible cash through real interfaces; preserve financial direction, authorization, accounting and durable recovery without repairing historical data.

userOutcomeReview: The inspected mounted API tests, native runtime logs, fixture outputs, controller/repository code and rendered captures support these outcomes. No specific failed F1/F2 product criterion was established. This approval does not assert that the earlier canonical database change has been attributed, or independently certify the complete F3 visual matrix.

## Direct evidence review

- `.omo/plans/unapplied-customer-cash-ui.md`: original intent IS1–IS6, stages, final F1/F2 and success criteria inspected. Its introductory progress text is stale.
- `audit/unapplied-cash-ui-f1.md` through `audit/unapplied-cash-ui-f6.md`, and `audit/unapplied-cash-ui-final.md`: examined stage evidence and limitations; these are summaries rather than independent proof.
- `server/.tmp-test/ui-f7-run-xpB8SN/journeys.log`, `lost.log`, `resume.log`: inspected actual passing native-run tails (5, 1 and 1 tests respectively).
- `server/.tmp-test/ui-f7-run-xpB8SN/status.json`: inspected actual outputs: 500 receipt, 400 application, -100 refund, settled invoice, unused 60 receipt voided, single 70 recovery receipt, balanced GL, empty invariant collections and canonicalUnchanged=true.
- `integration_test/unapplied_cash_flow_test.dart:240`, `:307`, `:354`, `:413`, `:458`, `:510`, `:563`: real dialog interactions cover lifecycle, reversal, closed period/offline, concurrent capacity, roles, committed response loss and separate-process recovery. At :586 unsupported capability asserts no additional write request; :600 asserts one receipt after retry.
- `server/src/__tests__/unappliedCashApi.test.ts:44`, `:64`, `:89`, `:166`, `:211`, `:279`, `:301`: mounted real HTTP bodies exercise lifecycle/invariants, voided-source rejection, real central pruning, original payment identity after reversal, dependency errors, closed periods, rollback/concurrency and individual grants.
- `server/src/__tests__/unappliedCashReplay.test.ts:10`: real database reopen, unique keys and foreign-key retention coverage.
- `server/src/__tests__/unappliedCashReadApi.test.ts:20`: customer ownership, pagination-independent totals, dates, voided receipts and access checks.
- `server/src/controllers/unappliedCashController.ts:67`: durable lookup precedes period/customer checks and all financial writes; replay save and financial writes share immediate transaction. :16 advertises explicit no-store policies.
- `server/src/services/unappliedCashService.ts:58`, `:106`, `:126`, `:194`: apply/refund permanent records, no extra apply payment, negative refund, transactional dependency-safe reversal. `unappliedCashGl.test.ts:285` checks application replay after central-key deletion.
- `lib/features/customers/unapplied_cash_operation.dart:163`: serialized immutable persisted operations; original policy plus fresh capability; persist before dispatch; scope rechecks; uncertain denial retained. :278 checks current receipt before reversal recovery.
- `lib/data/repositories/unapplied_cash_repository.dart`: online financial/capability reads and explicit dependent cache invalidation after successful POST; inspected full file. `test/features/customers/unapplied_cash_pending_test.dart:148` and `:173` distinguish immutable replay from unsafe new requests. `unapplied_cash_providers_test.dart:16` exercises actual provider/repository refetch wiring.
- `server/src/models/Payment.ts:324`: refund direction is out while unified absolute amount contract is retained. `test/features/customers/unapplied_cash_payment_widgets_test.dart:230` and `:314` cover legacy mutable receipt and mixed bulk selection behavior; legacy invoice-payment UI itself was not rerun by this reviewer.
- Directly viewed `audit/screenshots/unapplied-cash-ui/f7-en-light-desktop-receive.png`, `f7-browser-apply-review.png`, `f7-browser-refund-review.png`, `f7-en-light-desktop-reverse.png`, `f7-browser-settled-workspace.png`. Visible content separates balances, explains no new collection on apply, identifies refund outflow and retains original reversal date.
- `/tmp/minierp-f7-flutter-full.jsonl`: terminal done event has success=true. `/tmp/minierp-f7-server-full.log`: explicitly FAILED fingerprint guard despite 152/1387 tests passing; this is not clean-run evidence.
- `scripts/check-unapplied-cash-ui.sh` and `server/scripts/run-guarded-tests.cjs`: inspected owned fixture checks, isolated storage and fingerprint guards. Independently ran read-only SHA-256: canonical main file equals `27e5cc340bb5a43a1d4974f3b206ccfd05919e13a75bcefa6e16b13e5bd7bc97`.

## Programming and remove-ai-slops pass

Loaded both requested skills and the TypeScript reference. Directly reviewed the relevant diff, financial/recovery production code and representative mounted, persistence, provider and runtime tests. Existing project framework/tool choices were preserved rather than treated as defects.

Coverage checked explicitly: excessive/useless tests; deletion-only and requested-removal tests; tautologies; implementation-mirroring assertions; unnecessary extraction, parsing and normalization; typed domain errors, boundary validation, transaction ownership and maintenance burden.

No criterion-blocking slop found. The critical tests assert real persisted money, original identity, denied POSTs and visible outcomes rather than source-text removal. Client HTTP fakes do not independently prove backend durability; the mounted pruning test and separate-process native journey supply that missing seam. Permanent-replay reopen test combines several constraint assertions in one case; large service/state files and duplicated reversal-source traversal are maintenance notes, not violations of the stated user outcome. Boundary parsing and minor-unit normalization have concrete financial/transport purposes. Broad catches inspected in the controller narrow typed errors and hide internal diagnostics at the HTTP boundary.

## Exact evidence gaps and non-blocking notes

1. Earlier canonical-file change remains unattributed (`audit/unapplied-cash-ui-final.md:88`). An unchanged later interval cannot establish absence of every earlier write. No inspected artifact proves this implementation wrote canonical data; no historical reconciliation is requested or recommended.
2. Clean full server rerun has no standalone raw log. Parent reports its terminal tool returned exit 0, 152 suites/1387 tests, 1454.969 seconds, with unchanged fingerprints; persistent summary is `audit/unapplied-cash-ui-final.md:99`. This reviewer cannot independently reproduce that tool-only exit record from a file. The older log must not be cited as the clean rerun.
3. No separate code-review report/notepad supplied or found in `audit`/`.omo`; `.omo/evidence` did not exist at initial inspection. Therefore explicit same-skill coverage in an earlier review cannot be confirmed. The direct skill pass above supplies independent coverage and this absence is not used as a blocker.
4. Final evidence header still says matrix incomplete, whereas its later entries say complete. Refresh stale status text for a reliable handoff.
5. This review did not rerun full suites or launch new financial mutations. It inspected existing executable tests/logs and actual rendered artifacts and computed the current canonical hash read-only. Full visual/accessibility F3 certification is outside this delegated scope.

## Report location

`omo-agent-toolkit ulw-loop status --json` returned ULW_LOOP_PLAN_MISSING, so the prescribed fallback is used: `.omo/evidence/unapplied-customer-cash-ui-gate-review.md`.
