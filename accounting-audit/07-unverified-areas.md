# Limitations and evidence rules

Status: final scope register. A limitation is not a pass. Detailed unexecuted variants are retained in the module matrix and workstream registers.

- No inference about the integrity of any real business database: this audit uses fresh synthetic fixtures. Known dummy legacy discrepancies are neither repaired nor repeatedly audited.
- The external deprecated mobile consumer is absent from this repository; its idempotency-key behavior cannot be established locally.
- The D12 historical allocator description is stale relative to current inventoryEffectiveDate behavior: a pre-receipt sale is rejected in the new fixture. This is not counted as an open current defect. Mandatory invoice idempotency-key enforcement still involves the absent external mobile consumer; no policy change is made.
- Structural graph metadata reports partial SQL migration parsing and three Dart helper/model gaps. Direct source inspection is required for affected scopes; the graph is a discovery aid, not proof of completeness.
- Passing widget tests does not prove a live Flutter-to-server workflow. Each executed test and each static-only screen will be labeled explicitly.
- Simulated duplicate requests on a single synchronous SQLite process do not establish crash durability or multi-process contention behavior.
- Reports with identical values can share a defective formula. Only economic-event-derived expectations count as independent proof.
- Pre-existing local changes (.qoder/settings.local.json and audit/* artifacts) are preserved. Audit outputs are isolated under accounting-audit/; team coordination state is under .omo/teams/.

## Material unexecuted scope

- Complete quotation→SO→fulfillment, POS/walk-in/mobile parity, edit and all financial deletion/cancellation/reversal variants.
- Physical counts and correction, opening-stock edits, owner goods/cash withdrawals, salary deductions/loan write-off/reversal, positive production overhead/payable settlement and full production cancellation.
- Supplier advance lifecycle, all input/output tax and discount/rounding permutations, aging bucket boundary dates, all cash wallets/transfers/reconciliation counts, and custom report templates.
- Every dashboard KPI/trend/cache invalidation, every PDF/thermal print/export, all filter/group/search/pagination combinations, and full native Flutter→HTTP→database→reload workflows.
- Hard process interruption, power-loss/WAL recovery, explicitly coordinated multiple SQLite writers, and all conflicting-update interleavings.
- Historical migrations/replay on consistent business DB copies, including relevant WAL state. Fresh synthetic migrations were exercised; no production copy was necessary or made, and no historical accounting repair occurred.
- Carton conversion and serial accounting: no implemented conversion/serial workflow was established; these are unsupported/unverified requested cases, not invented fixture features.

The per-expression financial inventory is a candidate inventory, not a claim of independent recalculation. The audit provides explicit verification status for discovered areas; it does **not** fulfill exhaustive numerical verification of every displayed figure. Critical current defects independently block a trust or release recommendation regardless of remaining coverage.

## Outstanding policy disposition

F-023 proves that closing an expense/bill accrual period blocks its later settlement in an open period. Whether closure is intended to freeze future settlement of outstanding obligations is not explicitly established. This behavior is recorded as Accounting-policy decision required, not silently changed or counted as financial corruption. The full observation and ordinary-accrual alternative are in its finding.
