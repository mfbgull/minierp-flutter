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
| Consumed return credit cannot regenerate | One Rs 60 entitlement | Void/reissue allowed and another Rs 60 sale paid with reused credit | Rs 60 undercollection and signed AR mismatch | [F-002](findings/F-002/finding.md) |
| Two Rs 1,000 salary periods fully settled using Rs 200 carried advance | Expense 2,000; advance asset 0 | Expense 1,800; advance asset 200 | Profit/assets/equity overstated 200 | [F-020](findings/F-020/finding.md) |
| No loan principal exists before disbursement | Pre-loan receivable 0 | Pre-loan receivable −200 | Dated asset/cash position misstated | [F-021](findings/F-021/finding.md) |
| Rs 0.02 production cost conserved, output costs nonnegative | Inventory 0.02; clearing 0 | Inventory GL 0.03; clearing −0.01; batch cost −0.01 | Inventory GL/valuation inconsistency and phantom clearing credit | [F-022](findings/F-022/finding.md) |

## Invariants and their limits

The main run contains 397 numerical/control assertions, five failing for the single early-return defect. The remaining assertions are supporting evidence at their recorded snapshots, not 392 independently audited workflows. New oracle snapshots execute the existing A–J and credit-source/unapplied/advance/payable/tax extensions and check each individual journal group. Supplemental/dedicated defect runs are separately indexed by the oracle workstream.

The salary, loan and production defect fixtures have balanced journals and clean SQLite integrity/foreign-key checks. Economic correctness therefore fails despite structural consistency.

[Invariant-granularity evidence](evidence/invariant-granularity.md) independently demonstrates two existing-check limitations: reference-group balancing can hide individually unbalanced entries, and absolute AR comparisons can hide a sign reversal. Findings use signed balances as well as the original helper diagnostics.

No reconciliation of live or historical business records is claimed. All values above come from synthetic economic events.
