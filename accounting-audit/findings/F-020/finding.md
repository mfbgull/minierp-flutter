# F-020 — Salary advance consumed by the next payroll remains an asset

**Status:** CONFIRMED, current logic, fresh isolated fixture. **Severity:** High. **Category:** recognition/valuation/report propagation. **Owner:** backend-controls. No fix applied.

## Economic rule and independent oracle

For a monthly salary of 1,000, paying 1,200 in August should expense August wages 1,000 and recognize a 200 advance. After September salary is completed using that 200 advance plus 800 new cash, cumulative salary expense must be 2,000 and the advance asset zero. Cash paid is 2,000. This follows the approved split salary/advance model (audit/DECISIONS.md D3), with the advance becoming earned salary when applied. It does not require changing the salary amount, expense category or payment method.

## Real reproduction

Invocation from repo root: `node accounting-audit/tests/backend-controls.cjs`.

1. Fresh migrated DB, fund Bank with owner capital 10,000 dated 2026-01-01.
2. POST `/api/employees` salary 1,000.
3. POST `/api/employees/:id/salary/pay` amount1,200, date2026-08-20, methodBank, typepartial =>201.
4. POST same salary route amount800, date2026-09-20, typefull =>201.
5. GET salary history, P&L for August–September and balance sheet at September30; query canonical GL.

Actual: both months show paid, September total_paid1,000 / remaining0. GL6100 cumulative expense1,800, GL1310 advance asset200, Bank8,000. P&L totalExpenses1,800 / netProfit−1,800. Balance sheet otherAssets200, totalAssets8,200, equity8,200, balanced=true. Correct economic values: expenses2,000, profit−2,000, otherAssets0, totalAssets/equity8,000. The report is balanced but wrong by200.

## Root cause and scope

- `server/src/controllers/employeeController.ts:271–314` creates next-period advance row and posts Dr1310/Crcash.
- `employeeController.ts:472–505` includes prior advance in period-paid SUM, reduces new salary cash accordingly, then posts only new cash as wage expense. There is no reclassification of the applied advance in this transaction.
- `server/src/services/accountingService.ts:1551–1591` selects1310 only for postingKind advance; default salary selects6100.
- `server/src/models/Employee.ts:386–405` includes advance in paid total, explaining the operational paid flag.

Graph source discovery and path coverage were checked. Source path has no recorded indexing gap, with best-effort caveat. A literal1310/reference search and graph salary-advance symbol sweep supported the missing recovery transition; dynamic journal/report evidence establishes the actual defect independently of negative search claims.

## Evidence and binary observable

`accounting-audit/evidence/backend-run-Lbw3la/results.json`: scenario `BACKEND-SALARY-ADVANCE-RECOGNITION`, defectReproduced=true; contains exact requests/statuses/responses, salary rows, chart and full journal. Corresponding `erp.db` retained. `backend-probes-verified.log` captures run outcome. Final corrected harness rerun may have a newer backend-latest-run.txt; use its scenario with same ID for final consolidated evidence.

## Remediation direction / regression

On application of an advance, post Dr6100/Cr1310 for the exact applied amount with pay-period dating and a durable link. Reverse that recognition atomically when the salary is reversed; disallow reversing the source advance after consumption unless the downstream application is reversed. Test two months, partial applications, larger advance spanning months, cancellation and closed-period recognition. No production changes are authorized by this audit.
