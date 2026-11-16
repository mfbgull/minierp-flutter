# GLM money-path review (Task 1, read-only)

Date: 2026-11-16. Reviewer: GLM agent, worktree `/tmp/wt-glm-review`, detached at
`89c5b3e5` (current `main` HEAD). No code changed; nothing was fixed.

Scope reviewed cold, as asked:

- Supplier refund claims and receipts: `SupplierRefundClaim.ts`, `SupplierRefund.ts`,
  `supplierRefundClaimController.ts`, `supplierRefundController.ts`
- Cash guard: `cashBalanceGuard.ts` and every `assertCashTimeline` call site
- Idempotency middleware: `utils/idempotency.ts` and its callers
- Sales-order → invoice: `salesController.convertSalesOrderToInvoice`,
  `SalesOrderModel.convertToInvoice`, `InvoiceCreationService`

Method: source reading only. Where this report says "confirmed", the code path was
read end to end. Nothing here was exercised at runtime except where a test already
pins the behaviour (named below). Per D22, nothing is claimed "verified" that was
not run, and no failure is called pre-existing.

Severity: **High** = double-post / negative cash / silent data loss reachable by a
normal user flow. **Medium** = real accounting damage needing an unusual but
plausible sequence. **Low** = contract drift, reporting noise, or hardening.

---

## Findings

### F-1 — Medium — a claim can never be written off in two steps; the remainder strands in PARTIAL

`server/src/models/SupplierRefundClaim.ts:250` (call), `:1113-1121`
(`assertNoActivePosting`), docstring contradiction at `:218-219`.

`writeOff` calls `assertNoActivePosting(db, 'REFUND_CLAIM_WRITE_OFF', id)`, which
refuses when ANY non-voided journal line exists for that claim. The first
write-off posts such lines (`:264-265`), so a second write-off is always refused.

The method's own docstring says "a smaller amount leaves the claim PARTIAL"
(`:218-219`), implying the rest can be written off later. It cannot: the claim is
stuck PARTIAL forever unless a receipt lands. The comment at `:245-249` shows the
guard was aimed at retry double-posts (two keys, same intent), but it also blocks
two *deliberate, different-amount* write-offs, which the API explicitly supports
(`data.amount` defaults to remaining precisely so a partial write is possible).

Failing scenario:
1. Standalone claim, 5,000, no receipts.
2. Write off 2,000 with reason R1, key K1 → 201, claim PARTIAL.
3. Supplier refuses further negotiation; write off the remaining 3,000, key K2
   → 500/400 `An active GL posting already exists for REFUND_CLAIM_WRITE_OFF #id`.
4. The 3,000 sits in `refundsDue` with no permitted resolution except voiding the
   first write-off, for which no endpoint exists.

Proposed test (in `supplierRefundClaims.test.ts`): two sequential write-offs with
distinct keys (2,000 then 3,000) both succeed, `written_off_amount = 5,000`,
status RECEIVED, and exactly two `REFUND_CLAIM_WRITE_OFF` journal groups exist.
Red today on step 3.

### F-2 — Medium — cancelling a written-off claim (directly or via return void) orphans the write-off and silently drops the remainder

`server/src/models/SupplierRefundClaim.ts:184-195` (`cancel` guards only live
receipts), `server/src/models/PurchaseReturn.ts:934-952` (return void calls
`cancel` on the same rule).

`cancel` refuses only when live receipts are allocated. A claim with
`written_off_amount > 0` and no receipts can be cancelled, and the write-off's
`Dr 7300 / Cr AP` posting plus its `REFUND_CLAIM_WRITE_OFF` supplier-ledger debit
stay active while the claim that justified them disappears. The uncollected
remainder (`amount − received − written_off`) vanishes from `refundsDue` with no
entry, reversal, or report — the definition of silent data drop.

Failing scenario:
1. Purchase return 5,000 posts its credit note (Dr AP / Cr inventory) and opens
   claim SRC-1 for 5,000 (`PurchaseReturn.ts:775-785`).
2. Partial write-off 2,000 (F-1's guard allows the first one).
3. User voids the return (no receipts → permitted, `PurchaseReturn.ts:940-946`),
   which cancels the claim; the credit note reverses, but the write-off entry and
   its ledger debit are untouched.
4. Result: a 2,000 expense and an AP movement referencing a cancelled claim on a
   voided return — goods never left stock, yet a refund write-off stands. The
   remaining 3,000 is untracked everywhere. The exact GL↔subledger delta depends
   on the ledger sign conventions; I did not run it, so I do not assert a number —
   the test below establishes it.

Proposed test: post purchase → return with `refund_expected` claim → write off a
part → void the return → assert invariants A–J, invariant G (GL AP vs supplier
subledger), and that `refundsDue` still accounts for the remainder. Expect red;
then either refuse cancel/void while `written_off_amount > 0`, or reverse the
write-off with the cancel.

### F-3 — Medium — `SupplierRefund.void` dates its subledger reversal "today", against the codebase's own same-date reversal rule

`server/src/models/SupplierRefund.ts:399-407` vs `server/src/utils/ledgerUtils.ts:98-101`.

`voidJournalLinesByReference` voids the GL lines retroactively (`voided = 1`,
original `line_date` kept, excluded from balances — `accountingService.ts:1489-1503`).
But the supplier-ledger void entry is appended with
`transaction_date: new Date().toISOString().split('T')[0]` — today, not the
receipt's date. `ledgerUtils.reverseLedgerEntry` deliberately does the opposite
and documents why: "positioned where the original sat in the chain — same
transaction_date — so the rebuilt running balances treat the pair as a net-zero
event at that point, not as an end-of-chain one" (`ledgerUtils.ts:98-101`).

Consequences, concrete:
- For any as-of date D where refund_date ≤ D < void date, GL AP already shows the
  receipt undone while the supplier subledger still shows it applied — the two
  disagree in every as-of view in that window.
- `new Date().toISOString()` is UTC: for a server in PKT (UTC+5) a void between
  00:00 and 04:59 local stamps *yesterday* into the subledger chain, so even the
  current-date reconciliation can disagree on the boundary day.

The payment path does not have this problem — `Payment.delete` reverses ledger
rows through `reverseLedgerEntry` (`Payment.ts:719-733`), same-date.

Proposed test: receipt 3,000 on 2026-11-01; void it on 2026-11-10; assert the
supplier-ledger as-of balance on 2026-11-05 equals the GL AP as-of balance on the
same date (and that a mid-chain receipt from another document between the two
dates does not change the verdict). Red today for the window drift.

### F-4 — Low — replay responses are thinner than the original creations

Three places:
- Refund receipt replay: `supplierRefundController.ts:117-120` returns
  `{ data: { id } }`; the original returns the full row plus message (`:142-148`).
- Claim create / write-off replay: `supplierRefundClaimController.ts:88-91`, `:159-162`
  — same shape drop.
- Invoice create replay: `InvoiceCreationService.ts:413` returns
  `taxAmount: 0, cogsAmount: 0, paymentId: null, paymentNo: null, items: [], warnings: []`
  — a replayed backdated invoice loses its warnings in the response body (the
  `backdated_before_receipt` flag is still in the DB, `:226-230`).

No money impact — replay never re-posts — but a client that renders the replay
body shows blanks, and the Flutter dialog cannot distinguish "replayed, here is
your document" from a partial failure by shape alone.

Proposed test: create, then replay with the same key; assert the replay body
carries the same fields as the original (or at least `invoice_no`, `warnings`,
`paid_amount`).

### F-5 — Low — 30-day idempotency retention is a real (accepted) double-post window

`server/src/utils/idempotency.ts:166-177`; pruning runs from
`backupService.ts:269`. A retry with the same key arriving more than 30 days
after the original commit re-executes the write in full. This is decision 8.4's
accepted trade-off and is unit-tested (`idempotencyRound1.test.ts:434`), so it is
recorded here only so the window is visible next to the D19 mandate: the mandate
guarantees replay for 30 days, not forever. Note the comparison at `:172-175` is
a string compare of `YYYY-MM-DD` against `CURRENT_TIMESTAMP`; a row completed on
the cutoff day itself is kept (prefix sorts first), so the window is 30 days plus
one — harmless direction, worth a comment if anyone tightens it.

### F-6 — Low — `claimIdempotencyKey` upsert can overwrite the resource link

`server/src/utils/idempotency.ts:150-156` (`ON CONFLICT ... DO UPDATE SET
resource_id = excluded.resource_id`). Within one synchronous single-connection
process this cannot fire (a pre-check in `beginIdempotentWrite` always ran in the
same handler). But nothing in the schema or helper *prevents* it: two server
processes sharing one database (not the D16 bundled deployment, but nothing
blocks someone running `server/` standalone twice against one file) can both pass
the pre-check, both commit, and the second upsert silently repoints the key at
the second resource. A later retry of the *first* write replays the *second* —
wrong document returned, first write unreachable through the key.

Proposed test (needs two connections, so it is a deliberate concurrency probe,
not part of the suites): two open transactions on one DB file claim the same
(scope,key) with different resource ids; assert the second claim errors or the
first link survives. `DO NOTHING` plus a logged conflict would be the fix.

### F-7 — Low — sales-order conversion is protected only by its state machine, and a retry loses the invoice reference

`server/src/controllers/salesController.ts:331-366`; `SalesOrder.ts:645-707`.

Double conversion is genuinely blocked: the status check (`:342-348`) and the
`afterCreate` status flip (`SalesOrder.ts:692`) sit inside one transaction, so a
retry after a lost 201 gets 400 `Sales order already Invoiced`. But the retry
response carries no invoice id or number, and D19's mandatory-key list does not
include this endpoint, so there is no replay path that hands the created invoice
back. The user must go find the invoice by hand. Related: `convertToInvoice`
defaults `invoice_date` to `new Date().toISOString().split('T')[0]`
(`SalesOrder.ts:657`) — UTC, so an after-midnight-local conversion dates the
invoice yesterday for a UTC+5 deployment. Same UTC pattern in `SupplierRefund.void`
(F-3) and in the write-off defaults nowhere else that I traced.

Proposed test: convert with a key (the endpoint ignores it today), lose the
response, retry; assert the retry identifies the invoice (replay body or the
existing 400 enriched with `invoiceId`). Separately pin the UTC default as
intended or switch to a local-date helper.

### F-8 — Low — `writeOff` accepts an unvalidated `write_off_date`

`server/src/models/SupplierRefundClaim.ts:243` and `:262`:
`data.write_off_date || claim.claim_date` goes straight into
`assertPeriodNotClosed` and `postEntry`/`createEntry`. There is no format check
and no lower bound against `claim.claim_date`, so a write-off can be dated before
its own claim (only the closed-period guard would catch a closed period). A
typo'd date lands the expense in an arbitrary period. Low because the Flutter
dialog uses a date picker, but the API accepts anything.

Proposed test: `write_off_date: '1999-01-01'` and `'not-a-date'` are both
rejected with 400.

### F-9 — Info — cash-guard coverage is complete on the paths traced; one stale test header says otherwise

Every `assertCashTimeline` call site was checked
(`cashBalanceGuard.ts:17` definition; callers in `SupplierRefund.ts:391`,
`Expense.ts:239-245`, `OwnerCapital.ts:196-225`, `Payment.ts:659-697`,
`OwnerWithdrawal.ts:253-495`, `ExpensePayment.ts:71`,
`employeeController.ts:1138`, `accountingService.ts:1635/1706`,
`unappliedCashService.ts:256`, `PaymentRecordingService.ts:196`,
`SupplierPaymentService.ts:143`). Salary (`postSalaryEntry`,
`accountingService.ts:1635`) and loan disbursement (`:1706`) both run the
chronological guard after posting — the "GAP 2 is RED" header comment in
`moneyPathReviewGaps.test.ts:13-17` describes the pre-fix state; the probe test
itself (`:189-242`) pins the fixed behaviour and only passes with the guard
present. The header is stale and should say "guards this from regressing", not
"RED". The refund void runs the guard *after* the GL void inside the same
transaction (`SupplierRefund.ts:387-391`) — correct order, and a throw rolls back
the status flip and ledger entry with it. The daily-bucket SQL is cent-safe
(`ROUND(debit*100) - ROUND(credit*100)`, `cashBalanceGuard.ts:27-35`) and
agrees with the D2 same-day ordering.

No new guard gap found. (The one candidate — `unappliedCashService.cashTimeline`
wrapping the guard in `try` — rethrows as `UnappliedCashError`, `:255-261`; the
guard is not swallowed.)

### F-10 — Info — D21 has exactly one lazy require, and Task 2 removes it

`accountingService.ts:1656-1658` is the only lazy `require('./cashBalanceGuard')`
in the tree (verified by grep). `SupplierPaymentService.ts:19` already imports
the guard top-level; D21's memory that it also used a lazy require is out of
date. The extraction landed by Task 2 in this same worktree; see the commit.

---

## What was checked and found sound (so the next reader does not redo it)

- **Refund receipt create is atomic.** Controller wraps model create + key claim
  in one `db.transaction` (`supplierRefundController.ts:122-140`); a failure in
  the GL posting rolls back the receipt row, the claim allocation and the ledger
  entry together. The claim cap is re-checked fresh inside `applyReceipt`
  (`SupplierRefundClaim.ts:312-335`), so a stale pre-transaction read cannot
  over-allocate.
- **Excess handling matches D19.** One entry at the full amount, claim absorbs
  only its room, overage stays Cr AP (`SupplierRefund.ts:217-247, 284-299`);
  `treat_excess_as_advance` is explicit, never silent.
- **Void order is correct.** Allocation released before the GL void, guard after
  the void, all inside one transaction (`SupplierRefund.ts:367-421`).
- **Idempotency claim placement.** Refund create/claim-create/write-off all claim
  inside the write transaction; invoice create claims inside
  `InvoiceCreationService`'s transaction (`:218-220`). The structural GAP-1 pin
  (`moneyPathReviewGaps.test.ts:70-110`) covers the settle path only — the three
  refund controllers rely on discipline, not a pin (minor; noted, not a finding).
- **Replay/conflict semantics.** Same key + same payload replays; different
  payload 409s (`idempotency.ts:131-139`); malformed key 400s (`:63-71`); mandate
  message is a shared constant (`:298`).
- **Invoice creation ordering.** Period guard → replay → entity checks →
  credit-offset check → invoice row → key claim → stock consumption → ledger →
  GL → payment legs → credit-offset draw → afterCreate (SO status) → ledger
  rebuilds, all in one transaction (`InvoiceCreationService.ts:162-247`). The
  closed-period guard precedes the FIFO-retroactivity message deliberately
  (`:163-169`). COGS is summed with `addCurrency` discipline where it matters and
  posted through `parseCurrency` (`:329, :235`).
- **SO conversion passes line inputs, not stored amounts** — the BUG-006
  re-gross trap is documented and avoided (`SalesOrder.ts:681-690`), and the
  header total is not sent (`:687-691`), so the service recomputes.
- **Warehouse fallback for invoice lines always resolves to a concrete
  warehouse** (`Invoice.ts:524-568`), selling from stock that exists, and fails
  inside the transaction otherwise.

## What I did not run

- No test suites were executed for Task 1 (read-only review; the findings'
  "proposed tests" are unexecuted by definition — F-2/F-3's GL↔subledger deltas
  are reasoned, not measured).
- The Flutter client was not inspected for Task 1 (Task 3 covers it separately).
- `creditNoteRefundable`'s allocation-table arithmetic was read but not probed
  against a database; no defect is claimed there.
- Whether `PaymentRecordingService.recordCustomerPayment` re-validates the
  invoice total inside its own path was not traced (the caller passes the exact
  leg amount; the allocation is capped by `recordPaymentLegs`).
