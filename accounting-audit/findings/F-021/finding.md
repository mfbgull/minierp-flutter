# F-021 — Employee loan repayments can precede the disbursement

**Status:** CONFIRMED, fresh current-logic API reproduction. **Severity:** High: a dated GL asset balance is demonstrably misstated. **Category:** transaction chronology/historical balances. **Owner:** backend-controls. No fix applied.

A repayment of a particular loan cannot extinguish its receivable before that loan exists. Reject a repayment before disbursement, or model any genuinely earlier cash as a separate unapplied receipt.

Invocation: `node accounting-audit/tests/backend-controls.cjs`.

POST `/api/employees/:id/loans` amount500, disbursement_date2026-09-15, Bank =>201. POST `/api/employees/:id/loans/:loanId/repay` amount200, payment_date2026-09-01, Bank =>201. Canonical journal at September1 contains DrBank200/Cr1300 employee loans200, making this loan's historical asset balance−200, before disbursement on September15. Expected4xx and no new repayment/journal; actual loan remaining300. This is newly created data, not legacy noise.

Root cause `server/src/controllers/employeeController.ts:851–950`: direct repayment checks positive amount, method, present date, current balance and active status; it does not compare repayment date to loan.disbursement_date. The sibling salary-deduction path does enforce this comparison at `:343`. `resolveLoanRepaymentMethod:378` checks salary date only when salary_payment_id supplied. The generic route has no date-chronology schema guard (`server/src/routes/employees.ts:31`).

Evidence: `accounting-audit/evidence/backend-run-Lbw3la/results.json` scenario `BACKEND-LOAN-PREDISBURSEMENT`: status201 and loanReceivableBeforeDisbursement−200; API request/response, employee loan/repayment rows and complete journal are captured; matching `erp.db` retained. Same scenario exists in first run4HRMlP and final consolidated rerun. Graph coverage checked employeeController, routes/employees and accountingService.

Potential impact: historical loan/cash/asset balances are misstated, and a later genuine disbursement appears funded by an impossible earlier repayment. Global Dr=Cr invariants do not detect chronology.

Proposed regression: disburse500 on15Sep; direct repayment200 on14Sep must reject with unchanged rows and GL,15Sep must succeed; same validation should hold for salary-linked repayment and all accepted date formats. Reuse a shared chronology validator at the domain boundary. No production change made.
