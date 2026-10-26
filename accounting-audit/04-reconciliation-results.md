# Independent accounting reconciliations

The independent oracle derives expected amounts from economic events in integer paise. These tables present rupees for readability. Debit/credit signs in raw evidence are retained separately; payable and sales amounts below use normal financial-statement presentation.

## Specified retail lifecycle: verified bounded scenario

Evidence: [final main run](evidence/oracle-run-AbsZeT/results.json), its ordered `api-events.json`, `015-retail.json`, per-return SQL/GL snapshots, invariant snapshots and report responses. Actual requests were mounted on the real Express app against a fresh guarded database.

Events: owner funding Rs 10,000; purchase 70 units at Rs 10 on credit; first invoice 15 units at Rs 15, paid in cash; three separate one-unit returns with cash refunds; second invoice resells two returned units at Rs 15 on credit; transfer one unit to damaged stock and write it off at Rs 10; separate Rs 10 operating expense.

| Measure | Independent formula / expected | Actual DB / report | Difference | Status |
|---|---|---|---|---|
| Sale invoice count | 2 | 2 transaction records | 0 | PASS |
| Gross sold quantity | 15 + 2 = 17 | 17 | 0 | PASS |
| Returned quantity | 1 + 1 + 1 = 3 | 3 | 0 | PASS |
| Net sold quantity | 17 − 3 = 14 | 14 | 0 | PASS |
| Damaged/written-off quantity | 1 | 1 | 0 | PASS |
| Closing usable company stock | 70 − 17 + 3 − 1 = 55 | 55 | 0 | PASS |
| Gross sales | 17 × 15 = 255 | GL sales 255 | 0 | PASS |
| Sales returns | 3 × 15 = 45 | GL returns 45 | 0 | PASS |
| Net revenue | 255 − 45 = 210 | P&L 210 | 0 | PASS |
| Gross COGS | 17 × 10 = 170 | Sale/COGS evidence | 0 | PASS |
| Returned goods cost | 3 × 10 = 30 | Return/COGS reversal evidence | 0 | PASS |
| Net COGS | 170 − 30 = 140 | P&L 140 | 0 | PASS |
| Inventory valuation | 55 × 10 = 550 | Batch/GL/valuation report 550 | 0 | PASS |
| Damage loss | 1 × 10 = 10 | GL loss 10 | 0 | PASS |
| Separate operating expense | 10 | GL expense 10 | 0 | PASS |
| Total P&L expenses | 10 + 10 = 20 | P&L 20 | 0 | PASS total; breakdown separately reviewed |
| Gross profit | 210 − 140 = 70 | Derived from verified report values | 0 | PASS |
| Net profit | 210 − 140 − 10 − 10 = 50 | P&L 50 | 0 | PASS |
| Cash | 10,000 + 225 − 45 − 10 = 10,170 | GL/cash/balance sheet 10,170 | 0 | PASS |
| Customer receivable | Resale 2 × 15 = 30 | Customer/AR aging 30 | 0 | PASS |
| Supplier payable | Credit purchase 70 × 10 = 700 | Supplier/AP aging 700 | 0 | PASS |
| Total assets | 10,170 + 30 + 550 = 10,750 | Balance sheet 10,750 | 0 | PASS |
| Closing equity | 10,000 + 50 = 10,050 | Balance sheet 10,050 | 0 | PASS |
| Accounting equation | 10,750 − 700 − 10,050 = 0 | 0 | 0 | PASS |

The report window is **2026-09-01 through 2026-10-31**, with balance-sheet as-of 2026-10-31. The damage endpoint dates its posting to the execution day (2026-10-25). These results must not be described as September-only results.

The return/resale sequence therefore passes the requested economic test in this fixture. It does not establish that every return-credit reversal path is safe; F-002 demonstrates a distinct critical failure.

## Defect reconciliations

| Independent economic obligation | Expected | Actual | Difference / impact | Evidence |
|---|---|---|---|---|
| Return cannot precede its source sale/receipt | Reject; no 9 September movement | Accepted; 9 September revenue −15, COGS −10, inventory +10 | Historical statements contain effects before source events | [F-001](findings/F-001/finding.md) |
| Supplier return cannot precede acquisition | Reject; no 9 September movement | Return accepted201; dated inventory/AP each −10 before purchase10 September | Historical assets/liabilities appear before acquisition | [F-001](findings/F-001/finding.md) |
| Consumed return credit cannot regenerate | One Rs 60 entitlement | Void/reissue allowed and another Rs 60 sale paid with reused credit | Rs 60 undercollection and signed AR mismatch | [F-002](findings/F-002/finding.md) |
| Explicit zero POS cash is zero real tender | Reject walk-in sale; cash delta0, stock unchanged | Cash/payment+17.35, stock value−9.25, AR delta0 | Fictitious cash collection; goods released without supplied tender | [F-073](findings/F-073/finding.md) |
| Two Rs 1,000 salary periods fully settled using Rs 200 carried advance | Expense 2,000; advance asset 0 | Expense 1,800; advance asset 200 | Profit/assets/equity overstated 200 | [F-020](findings/F-020/finding.md) |
| No loan principal exists before disbursement | Pre-loan receivable 0 | Pre-loan receivable −200 | Dated asset/cash position misstated | [F-021](findings/F-021/finding.md) |
| Rs 0.02 production cost conserved, output costs nonnegative | Inventory 0.02; clearing 0 | Inventory GL 0.03; clearing −0.01; batch cost −0.01 | Inventory GL/valuation inconsistency and phantom clearing credit | [F-022](findings/F-022/finding.md) |
| Mixed-cost count correction preserves original layers | Recount2→8 yields inventory130/loss20 | Correction500; rollback retains inventory40/loss110 | Legitimate correction blocked; no committed mutation on failed request | [F-024](findings/F-024/finding.md) |
| Correcting item A preserves omitted item B's shortage | Aggregate inventory120/loss130 | Inventory140/loss110; B restored while its count row still says shortage | Inventory +20, loss −20, profit/equity +20 | [F-025](findings/F-025/finding.md) |

## Additional ordinary-case reconciliation

Evidence: [extension verification](evidence/backend-extension-verification.json), `backend-extension-run-OF2b8i/results.json` and ordered SQL/API stage snapshots.

- Production: six units at10 consume60; attributable overhead30 creates payable30, output cost90 allocated60/30. Including remaining raw stock40, inventory130; clearing0. Cancellation restores all initial account balances and materials, repeated delete404. This does not refute the tiny-pool rounding defect F-022.
- Owner drawings: three goods at cost10 reduce inventory30 and debit drawings30, despite selling value300; cash withdrawal50 takes drawings to80 and bank to950. Both voids restore initial balances and10 raw units. No operating expense is created.
- Ordinary physical count:10 units at10 counted8 gives stock8/inventory80/loss20; correction9 gives inventory90/loss10. A repeated correction is rejected400 without mutation. Mixed-cost and partial-body correction failures are independently documented above.
- Supplier split attempt: purchase100 paid100, return60 on account, new purchases30 and45 yield aggregate payable15 and cash9,900. Requested credit30+30 across target purchases returns500; targets remain unpaid30/45 and economic state is unchanged. Aggregate reconciliation passes; the requested allocation capability is unsupported/unverified, not a successful scenario.

## Late channel/payable controls and audit-store reconciliation

AFjr5O sales-channel and GIxBh2 payable fixtures were independently verified read-only in [final-extension-verification.json](evidence/final-extension-verification.json).

- Ordinary quotation/SO conversion and cancellation have no premature recognition; paid SO cancellation is blocked409; reversing payment then cancelling is neutral. Repeating a completed cancellation returns500 but makes no second mutation (F-070 Low).
- POS split52.05 is Cash20 + Bank15 + AR17.05; ordinary cash/credit partial returns and same-key replay pass. Explicit zero tender is a separate critical failure; the cash oracle is actual supplied tender, not the returned fabricated payment.
- Supplier advance200.75 is an asset/cash movement, not an expense or AP reduction. Applying80.24 moves no cash and leaves advance120.51/AP84.41. Reversal restores the original asset/payable; consumed-source guards and injected failure rollback pass.
- Credit expense120.37 recognizes payable without cash. Payment40.12 leaves80.25, exact payment settles; void/cancel economic effects reconcile. Opening cash/bank seeds100.10/50.20, count variance−0.15 and unknown-account atomic rejection were tested.
- Despite correct canonical monetary effects,9 headers remain active with all child lines voided (F-060). No reboot duplication or extra money is claimed.
- Reservation replay leaves reserved6 vs one active row3; after release, physical10/available7/reserved3 with no active entitlement (F-071). A NULL optional line ID leaves an accepted reservation unreleasable (F-072). These are availability/control discrepancies, not demonstrated changes to inventory GL value.

## Invariants and their limits

The main run contains 397 numerical/control assertions, five failing for the single early-return defect. The remaining assertions are supporting evidence at their recorded snapshots, not 392 independently audited workflows. New oracle snapshots execute the existing A–J and credit-source/unapplied/advance/payable/tax extensions and check each individual journal group. Supplemental/dedicated defect runs are separately indexed by the oracle workstream.

The salary, loan and production defect fixtures have balanced journals and clean SQLite integrity/foreign-key checks. Economic correctness therefore fails despite structural consistency.

[Invariant-granularity evidence](evidence/invariant-granularity.md) independently demonstrates two existing-check limitations: reference-group balancing can hide individually unbalanced entries, and absolute AR comparisons can hide a sign reversal. Findings use signed balances as well as the original helper diagnostics.

No reconciliation of live or historical business records is claimed. All values above come from synthetic economic events.
