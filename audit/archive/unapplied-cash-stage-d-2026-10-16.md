# Unapplied customer payments: Stage D

Status: Stage D implementation and verification complete.
The user reviewed Stage C and authorized Stage D. No Stage E routes or Flutter
changes are included.

## Implementation

- `UnappliedCashService` accepts an injected database. Receive, apply, refund
  and unused-receipt reversal execute in immediate transactions, including
  nested savepoints when invoked by another transaction.
- Receive posts Dr the selected cash/bank account and Cr 2110, using the
  positive receipt payment ID. It leaves both customer balances and the
  customer ledger untouched.
- Apply normalizes duplicate invoices, validates ownership and invoice
  capacity with the extracted shared payment validator, and draws cash sources
  oldest-first. Every draw also respects the original receipt's allocation and
  refund ceiling. Allocations reference the original receipt; there is no new
  cash payment. The application ID keys Dr 2110 / Cr 1100, with a matching
  customer-ledger credit and customer-balance reduction.
- Refund draws only live UNAPPLIED_CASH sources, creates a negative REFUND
  payment, and posts Dr 2110 / Cr the selected cash/bank account using that
  payment ID. The shared cash timeline guard prevents an unfunded payout.
- Reversal checks the original receipt period and rejects applied/refunded
  dependencies with `UNAPPLIED_ALREADY_APPLIED`, status 409, and source/invoice
  details. An unused receipt's GL, payment and source retire atomically;
  removing cash cannot leave later spending unfunded.
- Legacy payment update/delete/allocation methods reject owned payments.
  Invoice allocation deletion rejects live source consumptions. Invoice
  cancellation checks live draws, not only the caller's possibly stale paid
  amount. Invoice deletion rechecks the dependency inside its transaction;
  customer reassignment cannot detach an applied invoice from its source owner.
  Invoice edits that try to delete payments reach the guarded payment primitive.
  Public un-apply remains
  deferred: existing consumers cannot void an application while leaving its
  counters behind.
- Apply/refund keys are unique per customer and operation. Permanent request
  hashes on application headers preserve replay after transient idempotency
  records are pruned. The standard idempotency scopes are
  `unapplied_cash.apply` and `unapplied_cash.refund`; their stored keys are
  namespaced with the customer ID and their numeric resource is the application
  ID. Same-key changed payloads return 409 without writes.

## Schema follow-ups

Migration 108 is unchanged. Registered migration 109 adds permanent replay
metadata, the refund payment link, and a unique cash-source origin receipt.

A failing 0.30 receipt / 0.10 apply test exposed binary floating-point drift in
108's generated remaining amount: 0.20 refundable could compare greater than
the unrounded generated value. Registered migration 110 rebuilds the source
and consumption tables with currency-rounded generated remaining amounts,
preserving IDs, timestamps, application relationships, constraints and indexes.
Additional invoice/payment lookup indexes cover legacy mutation guards. The
nonempty migration regression verifies all source, draw and header rows and
`foreign_key_check` after the rebuild.

## Accounting collectors

The A-J collectors now accept an optional injected connection, preserving their
default database and existing equations. K-N also run in the master assertion:

- K: absolute GL 2110 versus live unapplied-cash remaining, to cents; missing
  account 2110 throws.
- L: each live cash source's applied/refunded counters and remaining amount
  versus live consumption rows. Missing draws and offsetting cross-source
  corruption are detectable.
- M: source refund, consumption, remaining and refundable bounds.
- N: live allocations cannot exceed a positive RECEIPT or UNAPPLIED_RECEIPT.
  Negative refunds are not receipts.

Historical RETURN_CREDIT counters are returned separately by
`historicalCreditSourceBaseline`. Their lack of original draw records is not
reported as a green L check. They cannot fund new applications or refunds.

## Observed historical verification

Command, from the repository root:

```bash
node docs/superpowers/verification/unapplied-cash-stage-d.cjs server/database/erp.db
```

The script opens the source read-only, backs it up, installs the live-database
constructor guard in a child process, applies the actual migration runner to
the backup, and exercises real service operations. Seven checkpoints compare
every A-J violation label and discrepancy amount, rather than changing actual
and expected accounting balances being compared. K-N pass; foreign keys hold;
replaying the migration runner preserves all sources and consumptions.

Source main SHA-256:
`63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f`.
Consistent input backup SHA-256:
`09b1de6b9bfe6aa7aa656deec64b0d3d79468cca576da3813e574713469d1045`.
Main/WAL/SHM fingerprints remain unchanged.

The customer in the added invoice scenario owes 499.80, receives 500 held cash,
applies 400, and then owes 99.80. Refunding the remaining 100 succeeds. Reversal
of that consumed receipt is blocked; receiving and reversing a separate unused
50 also preserves the baseline.

Existing historical findings remain exactly:

| Collector | Finding | Difference |
|---|---|---:|
| C | Invoice 26 paid amount versus allocations | -1200.00 |
| C | Invoice 27 paid amount versus allocations | -600.00 |
| C | Invoice 31 paid amount versus allocations | -1200.00 |
| C | Invoice 39 paid amount versus allocations | -500.00 |
| C | Invoice 40 paid amount versus allocations | -400.00 |
| F | GL AR versus customer balances | 1800.00 |
| G | GL AP versus supplier balances | -400.00 |
| H | GL inventory versus batch values | -1533.20 |
| I | GL cash versus operational cash | -24100.00 |

There are still 13 historical RETURN_CREDIT sources, credited 8550.20 in total,
with reconstructed consumption 1800.00 and refundable cash zero. No historical
discrepancy is repaired or historical credit activated.

## Test evidence

- Initial behavior red: 7 failed / 6 passed against unimplemented service
  methods, followed by 13 passing operation tests.
- Corruption-test red: L, N and historical-baseline assertions fail against
  empty collector stubs. K's initial unbalanced mutation was correctly refused
  by the database commit guard; its final planted drift changes both journal
  sides in a balanced transaction.
- Currency red: 1 failed / 24 passed; the fractional scenario raises
  `c_refundable_le_remaining` before migration 110.
- Key-scope red: the two-customer same-key test raises an idempotency conflict
  before customer namespacing.
- Invoice-guard red: a stale unpaid snapshot can cancel an already-applied
  invoice, and reassignment to another customer succeeds, before the shared
  dependency guards. The cancellation fixture includes its acting user, so a
  missing-user foreign key cannot disguise this regression.
- Seven targeted suites passed, 70 tests: unapplied GL/migration, payment
  recording, deletion, edit, guards and invoice cancellation. Jest reported
  its previously observed worker teardown warning.
- Final focused run: 3 suites / 68 tests passed, including the A-N master and
  invoice-creation return-credit isolation. A subsequent filtered run passes
  all 3 customer-key/stale-invoice/reassignment scenarios (29 other cases were
  excluded by the name filter, not disabled).
- Complete unfiltered server run: **149 suites / 1349 tests passed**, zero
  failures and zero skipped tests, exit 0, in 1171.816 seconds. All 32 unapplied
  cash cases ran. The guarded runner's canonical main/WAL/SHM check passed.
  Jest emitted the previously observed worker teardown warning; this is not
  represented as a clean open-handle diagnostic.
- `npm run typecheck`, `npm run lint`, and `git diff --check` passed. Lint emits
  the existing MODULE_TYPELESS_PACKAGE_JSON Node warning.
- Flutter suites and localization checks are intentionally not rerun: this
  phase changes neither Flutter nor the public API contract.

Stage D stops here. Stage E's mounted API implementation is a separate phase.

Final gate command, from `server/`:

```bash
node scripts/run-guarded-tests.cjs --maxWorkers=2 --silent --json --outputFile=.tmp-test/stage-d-server-full.json
```

The guarded runner checks canonical main/WAL/SHM fingerprints around Jest.
