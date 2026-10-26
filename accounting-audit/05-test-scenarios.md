# Independent end-to-end scenario results

All new financial writes used fresh synthetic databases with constructor-level path guards. Tests mounted the real Express app, sent authenticated HTTP bodies and retained SQL/GL/API snapshots. Money expectations use integer paise. Flutter report replay is separately identified; no live desktop business session was manipulated.

| Required family | Executed independent economic check | Result | Evidence / remaining limits |
|---|---|---|---|
| 1 Complete retail lifecycle | Buy70@10 on credit; sell15@15/cash225; three distinct one-unit returns/refunds; resell2@15 credit; damage/write-off1@10; expense10. Expected stock55/value550/revenue210/COGS140/loss10/opex10/profit50/cash10170/AR30/AP700/equity10050 | PASS bounded fixture,87 assertions | Main AbsZeT family1; actual P&L/BS/aging/valuation plus model and mounted-widget replay. Gross17, returned3, net14 units;2 invoices |
| 2 Customer return credit | Paid/partial invoices, refund part in cash, apply credit to new invoices, unapplied receipts/application/refund; separate credit60 split30+30 | FAIL F-002 Critical | z9sfxV proves void→reissue→second spend60; expected economic AR75, actual operational15. Ordinary split/refund caps pass |
| 3 Supplier return credit | Paid/unpaid/partial return/refund limits; actual attempt to split supplier return credit60 over unpaid purchases30/45 | PARTIAL; split unsupported | eVTI6t corrected42/42 checks; TQ4hqh two-target request500, no mutation. Aggregate AP15 correct; target credit allocation and consumed-credit reversal NOT VERIFIED |
| 4 Partial receipt/payment | PO10@10 creates no acquired stock/GL before receipt; GRN4 recognizes40, payment25 leaves15 AP. Tax residual7@3.33+tax1.01 split receipts2/5 then void | PASS named cases | AbsZeT family4;9MmRSv10c. Complete PO/cancellation/edit/payment combinations remain incomplete |
| 5 Independent damage/loss | Damage relocation without GL loss, separate write-off20 to7202 and quantity0/value0; retail single-unit loss10; warehouse transfer/reverse preserves total value | PASS named cases | AbsZeT5 and9MmRSv5b. Every loss reason, mixed-layer partial transfer and location branch not exhausted |
| 6 Reversals | Payment45 reversal then invoice3-unit cancellation restores stock; repeated cancellation4xx; GRN/transfer reversals. Production and drawings separately reversed | FAIL broader family | Ordinary cases pass, credit reversal F-002 fails; count partial reversal F-025 fails. Not all document reversals executed |
| 7 Backdates | Pre-receipt sale rejected; early sales return accepted, daily revenue−15/COGS−10/inventory+10; early supplier return accepted with daily inventory/AP−10; employee repayment before disbursement accepted | FAIL F-001/F-021 | AbsZeT7, ZHkdJ8 7c, Lbw3la loan fixture. FEFO/nonexpiry samples pass; all historical permutations not verified |
| 8 Failure/duplicates | Same invoice key replay, changed payload409; injected canonical GL insertion failure produces full economic rollback | PASS bounded single-process cases | AbsZeT8. No hard crash/power-loss or controlled multiple SQLite writer proof |
| 9 Period boundaries | Closed period rejects new posting atomically; Dec30 purchase/Dec31 sale/Jan1 receipt reconcile dated inventory/AR/cash/income and opening+movement=closing | PASS named cases; policy gap | AbsZeT9,9MmRSv9b. F-023 confirms later settlement of closed-source accrual is blocked; D15 unresolved |
| 10 Zero/partial/boundaries | Zero/negative quantities rejected;3×0.1 gives30paise; insufficient stock/funds rejected; partial/exact payment and fractional tax residual checked | PARTIAL | Named checks pass. All discounts/taxes/large numbers/rounding/unit conversions and negative-cash paths not exhausted |

## Additional independent high-risk scenarios

| Scenario | Economic oracle | Actual disposition |
|---|---|---|
| Payroll carryover | Two salary periods1000 each;200 advance earned next period,800 new cash; total expense2000/advance0 | FAIL F-020: expense1800/asset200; P&L and balance sheet propagate |
| Joint production tiny pool | Cost0.02, four outputs: all shares nonnegative, sum0.02, clearing0 | FAIL F-022: shares.01/.01/.01/−.01; GL inventory.03, batch total.02 |
| Positive overhead/cancel | Materials60+overhead30 split60/30; inventory130 incl raw40, payable30, clearing0; cancellation restores start | PASS exact bounded fixture; repeated delete404 |
| Owner cash/goods drawings | Goods3@cost10 despite selling price100 => drawings30; cash50 => drawings80, no expense; both voids neutral | PASS bounded fixture |
| Ordinary count correction |10@10 counted8 => inventory80/loss20; recount9 => inventory90/loss10; repeat rejects | PASS; repeat400 unchanged |
| Mixed-price count correction |5@10+5@20 count2, recount8 => value130/loss20 | FAIL F-024:500, full rollback retains prior40/110 |
| Partial count correction | Correct only A; omitted B's valid shortage persists | FAIL F-025: B restored too, inventory+20/loss−20, stale posted-count row |
| Nonzero-category balance sheet | Show other assets400, tax60, other liabilities70 or visible reconciling group | FAIL F-040; actual mounted capture |
| CSV currency cell | Rs1,000 occupies one escaped cell | FAIL F-041; quote-aware parser accepts correct quoting and detects actual4-cell row |
| Salary hint | Salary1000−already-paid200=800 remaining; advance already included | FAIL F-042:600 displayed |
| P&L expense detail | Damage10+operating10 explain total20 | FAIL F-043: detail10 only, total/profit correct |
| Quotation/SO/POS ordinary channels | Nonposting draft/confirmation; invoicing/fulfillment; paid cancel guard; neutral reversal; cash/credit/split POS and retries | Named economic assertions PASS; repeat SO cancellation500 is F-070 Low |
| Explicit zero POS cash | Tender0 cannot become a receipt or paid walk-in sale | FAIL Critical F-073: cash/payment17.35 invented and stock released |
| Reservation retry/optional line | One reservation3 is counted once; accepted NULL-line reservation releases | FAIL F-071 phantom reserved3; F-072 unreleasable ACTIVE2; non-null single-create control passes |
| Supplier advances/expense payables/opening count | Independent funding/application/settlement/reversal/no-cash and atomicity arithmetic | Economic assertions pass; F-060 header/line void mismatch fails separately |

Late extension runs: sales-channel AFjr5O692 assertions/7 mismatches; payable GIxBh2552 assertions/17 repeated header mismatches. Root read-only verification confirms all5 added findings. These are distinct from full-suite test counts and not692/552 independently audited workflows.

## Execution interpretation and reproduction

See [oracle workstream](workstreams/financial-oracle.md), [backend workstream](workstreams/backend-controls.md) and [Flutter workstream](workstreams/flutter-reports.md) for exact commands and ordered artifacts. Main397 assertions have5 genuine F-001 mismatches; dedicated credit73 assertions have9 genuine F-002 mismatches. A reproducer may intentionally exit0 after confirming a defect; that is not a passing correctness regression.

Earlier incorrect fixture bodies, HTTP verbs, account type, locale setup and a stricter-than-documented supplier refund cap are retained and explicitly superseded. None is counted as a product defect. No test, invariant or accounting guard was weakened. Carton conversion/serial tracking were not invented where no implementation was established.
