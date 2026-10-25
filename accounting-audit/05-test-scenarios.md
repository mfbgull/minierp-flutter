# Independent scenario obligations

Status: planned; execution is recorded in workstreams and evidence, never inferred from this plan.

| Family | Independent expected accounting | Execution status |
|---|---|---|
| 1 Retail lifecycle | Buy 70 units at Rs 10; gross sales less three valid returns plus resale determine net revenue and COGS; one damaged unit costs Rs 10 once; separate expense Rs 10 | NOT TESTED |
| 2 Customer credit | Paid return creates an obligation; cash refund reduces cash only for refunded amount; allocating residual credit reduces receivables without new revenue/cash | NOT TESTED |
| 3 Supplier return credit | Inventory decreases at original cost; payable/debit-credit obligation changes once; applications to multiple invoices have no cash leg | NOT TESTED |
| 4 Partial receipt/payment | PO creation has no acquisition posting under documented model; only received quantity creates inventory/payable; actual payment reduces cash and payable | NOT TESTED |
| 5 Damage | Dr loss, Cr inventory exactly once; stock and valuation both fall | NOT TESTED |
| 6 Reversals | Net economic effects neutral; consumed credit/dependent stock guarded; repeated reversal has no additional effect | NOT TESTED |
| 7 Backdating | Compare event-date stock/cost to actual allocation; distinguish documented unresolved policy from new faults | NOT TESTED |
| 8 Failure/duplicates/conflicts | Failed operation commits nothing; repeated same-key API request creates one economic event | NOT TESTED |
| 9 Period boundaries | Opening + dated movements = closing; closed periods remain immutable; income and cash assigned to actual event periods | NOT TESTED |
| 10 Boundaries | Zero/partial/exact/overpayment, discounts, cents, stock and funds ceilings tested independently | NOT TESTED |

Money expectations use integer minor units or decimal arithmetic. Synthetic fixtures alone are retained. Runtime artifacts must identify request, expected result, actual result, source, and SQL/GL evidence.
