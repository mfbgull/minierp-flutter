# F-002 — Consumed store credit can be voided, reissued and spent twice

> Current assessment, 2026-10-26: this report preserves its historical audit snapshot. See [remediation status](../../remediation/STATUS.md) for current source verification, fixes, tests and remaining limits.

**Status:** CONFIRMED in a clean dedicated fixture. **Severity:** Critical. **Category:** reusable financial entitlement / reversal integrity / receivables. **Owner:** financial-oracle. No production fix applied.

## Independent oracle

Sell Rs150 and collect Rs150; return Rs60. The customer has one Rs60 entitlement. Apply it to invoices30 and45: outstanding receivable must be15, remaining store credit0. The consumed credit cannot be voided while its downstream applications remain active. Reusing another60 on a further invoice60 undercollects60; economically total goods retained225 minus collected150 means receivable75.

## Minimal mounted-API reproduction

Invocation: `ORACLE_SUPPLEMENT=1 ORACLE_FAMILY=2b node accounting-audit/tests/oracle-lifecycle.cjs`.

1. Fresh migrated DB; create one supplier, item and customer; purchase20 @10.
2. Invoice10 @15 and pay150; return4 units with settlement `{type:"credit",amount:60}`.
3. Create invoice30 with credit_offset30 and invoice45 with credit_offset30. Both applications remain active; customer net receivable15 and GL1100+1110=15; every collector passes.
4. POST `/api/return-settlements/:id/void` returns **200**. The source credit settlement becomes void, while both credited invoices/payments/journals remain active. Customer balance becomes−45, GL remains+15: signed divergence60.
5. POST `/api/invoice-returns/:id/settle` with credit60 returns **200** again.
6. Create another invoice60 with credit_offset60: **201**, paid_amount60, balance_amount0; four additional stock units leave. No additional cash was received.

Final actual: customer current_balance15, credit_balance0; invoices show only15 outstanding. Correct economic outstanding and signed canonical GL total are75. The same original return entitlement funded120 of invoice offsets. The final canonical GL75 is economically correct; the invoice/customer operational15 is wrong. The earlier GL15 belongs to the before-third-sale checkpoint, not the final expected position. This is an actual successful duplicate spending sequence, not merely a missing validation hypothesis.

## Evidence and binary observables

Dedicated run `accounting-audit/evidence/oracle-run-z9sfxV/` contains only this family:

- `api-events.json`: all requests/statuses/responses plus economic hashes.
- `010-credit-before-void.json` / `010-credit-before-void-invariants.json`: before state; all collectors empty.
- `011-credit-two-targets.json`: consumed source successfully voided; original two invoice offsets retained.
- `012-credit-reissued.json`: second live60 credit settlement from the same return.
- `013-credit-double-spend.json`: new fully paid invoice60 and stock drawdown; customer15 versus GL75.
- `results.json`: rejection expectations and signed-reconciliation checks fail; family2b FAIL,73 checks.
- `accounting-audit/findings/F-002/database-proof.json`: readonly final invoice/customer evidence; integrity_check=ok, FK check empty.
- `accounting-audit/evidence/oracle-credit-repro.log`: captured failure output.

The built-in AR collector applies absolute values, so after void it reports magnitude difference−30 (15 versus45). The independent signed check correctly records +15 versus−45, a60 divergence; after duplicate spend both methods show60. Do not confuse magnitude comparison with the economic difference.

## Root cause and affected paths

`server/src/services/invoiceReturnService.ts:1296` implements the shared settlement reversal. Its credit branch1327–1338 performs `credit_balance=MAX(0,credit_balance-amount)` and reverses the source CREDIT ledger row, without checking or reversing consumption. The clamp conceals that zero credit remains. Neither it nor `voidSettlement` at701–734 verifies downstream credit-offset allocations. Source reversal frees settlement capacity; `applyCredit` at1077–1107 can mint the entitlement again. Active CREDIT_OFFSET journals and allocated payments still refer to the original applications.

The shared branch is also called by whole-return void at624, which requires the same guard. The exact source paths were graph-discovered/coverage-checked and read directly.

## Recommendation and regression requirements

Track source credit consumption durably and block source/settlement/whole-return reversal while any active draw exists; require downstream application reversal first. Eliminate the saturating clamp as a substitute for entitlement validation. Keep the existing all-or-nothing transaction and rebuild signed balances. A source-aware correction must include all callers of this shared primitive.

Add API regression tests for full and partial consumption, multiple target invoices, settlement and whole-return void, attempted reissue after void, replay/double request, source/application reversal order, and signed GL/customer/invoice-credit reconciliation after every stage. Assert monetary/stock outcomes and inability to reuse60; a balanced journal alone does not prevent this loss. No production changes were made.
