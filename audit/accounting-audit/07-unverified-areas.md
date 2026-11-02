# Limitations and evidence rules

Status: final scope register. A limitation is not a pass. Detailed unexecuted variants are retained in the module matrix and workstream registers.

- No inference about the integrity of any real business database: this audit uses fresh synthetic fixtures. Known dummy legacy discrepancies are neither repaired nor repeatedly audited.
- The external deprecated mobile consumer is absent from this repository; its idempotency-key behavior cannot be established locally.
- The D12 historical allocator description is stale relative to current inventoryEffectiveDate behavior: a pre-receipt sale is rejected in the new fixture. This is not counted as an open current defect. Mandatory invoice idempotency-key enforcement still involves the absent external mobile consumer; no policy change is made.
- Structural graph metadata reports partial SQL migration parsing and three Dart helper/model gaps. Direct source inspection is required for affected scopes; the graph is a discovery aid, not proof of completeness.
- Passing widget tests does not prove a live Flutter-to-server workflow. Each executed test and each static-only screen will be labeled explicitly.
- Simulated duplicate requests on a single synchronous SQLite process do not establish crash durability or multi-process contention behavior.
- Reports with identical values can share a defective formula. Only economic-event-derived expectations count as independent proof.
- Pre-existing local changes and later shared-workspace edits are preserved. Audit outputs are under accounting-audit/, with one OPEN-DECISION addition to audit/DECISIONS.md and team state under .omo/teams/. Do not attribute other source/config changes to this audit.

## Material unexecuted scope

- All edit/deletion/cancellation/channel variants and mobile parity. A bounded quotation→SO→invoice/fulfillment/cancellation and POS cash/credit/split/return/replay extension was subsequently executed; zero POS tender and reservation paths fail F-070–073.
- Opening-stock edits, salary deductions/loan write-off/reversal and production-overhead payable settlement. Ordinary count correction, owner cash/goods withdrawals/voids, positive overhead and production cancellation were subsequently executed; mixed-cost and omitted-item count corrections fail (F-024/F-025). Other count/location/production variants remain incomplete.
- All input/output tax and discount/rounding permutations, aging bucket boundaries, all wallet/count variants and custom templates. Supplier advances/application/void and expense payables/settlement were subsequently executed, with canonical economic assertions passing but journal headers failing F-060. A dedicated cash-transfer/reversal and supplier-advance cash-refund endpoint was not established by bounded discovery.
- Every dashboard KPI/trend/cache invalidation, every PDF/thermal print/export, all filter/group/search/pagination combinations, and full native Flutter→HTTP→database→reload workflows.
- Hard process interruption, power-loss/WAL recovery, explicitly coordinated multiple SQLite writers, and all conflicting-update interleavings.
- Historical migrations/replay on consistent business DB copies, including relevant WAL state. Fresh synthetic migrations were exercised; no production copy was necessary or made, and no historical accounting repair occurred.
- Carton conversion and serial accounting: no implemented conversion/serial workflow was established; these are unsupported/unverified requested cases, not invented fixture features.
- Supplier return-credit allocation across multiple purchases was attempted through the public payment route, returned500 and left economic state unchanged. Source inspection found supplier-prepayment application, but no return-note-to-target allocation workflow. Correct aggregate AP is not proof of individual invoice settlement. No successful split or consumed-credit reversal is claimed for suppliers.

The per-expression financial inventory is a candidate inventory, not a claim of independent recalculation. The audit provides explicit verification status for discovered areas; it does **not** fulfill exhaustive numerical verification of every displayed figure. Critical current defects independently block a trust or release recommendation regardless of remaining coverage.

## Snapshot and later source drift

The executed audit source is the2026-10-25 snapshot, baseline15a78418 (later artifact commit8d292328). All1,172 protected hashes matched at the saved Oct25 checkpoint. On Oct26,10 previously hashed files differ, and further files/config/dependencies have been added or changed by other work. The new POS/reservation/accounting helper sources used for final proof still match their original hashes. No broad current-tree revalidation or certification is inferred from the earlier full suites. Source drift is recorded in final-extension-verification.json and final-source-state.json; the prior unchanged checkpoint is retained.

## Outstanding policy disposition

F-023 proves that closing an expense/bill accrual period blocks its later settlement in an open period. Whether closure is intended to freeze future settlement of outstanding obligations is not explicitly established. This behavior is recorded as Accounting-policy decision required, not silently changed or counted as financial corruption. The full observation and ordinary-accrual alternative are in its finding.
