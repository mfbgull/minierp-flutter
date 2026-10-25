# F-023 — Closing the accrual period blocks later settlement of unpaid expenses and bills

**Status:** Accounting-policy decision required; the rejection behavior is confirmed. **Priority:** Medium workflow/policy restriction; excluded from confirmed financial-corruption severity counts. **Category:** period controls / AP lifecycle. **Owner:** backend-controls. No fix applied.

## Rule versus policy

Normal accrual settlement in a later open period debits an existing liability and credits cash on the payment date; it does not modify the original closed-period expense/bill journal. User decision D13 at audit/DECISIONS.md:7 approved accrual expenses and supplier bills; docs/API.md:773–779 documents settlement of recorded credit expenses and requires reversing payments before cancellation or financial edits. Neither cited policy explicitly prohibits settling after closing the original accrual period. REVERSAL-RULES scopes destructive, cancellation, correction and reversal paths; a new settlement is not reversal of the accrual.

The implementation explicitly rejects this case, so classify it as an observed over-restriction against ordinary accrual operation, with a policy question: is closing a period intentionally meant to freeze all future settlement of its outstanding liabilities? If yes, the limitation must be documented and disclosed before closure. Do not silently weaken period immutability in a future fix.

## Reproduction and outcome

Invocation: `node accounting-audit/tests/backend-controls.cjs`.

Create recorded Credit expense100 dated2026-07-10; create supplier bill net100/tax0 same date. Close July through POST `/api/accounting/periods/:id/close` =>200. With sufficient Bank funds, POST `/api/expenses/:id/payments` and `/api/supplier-bills/:id/payments`, amount100, payment_date2026-10-01, Bank. Both return409 due to original July date, while October remains open. Bank and both liabilities remain unchanged.

Independent economic expectation for allowing ordinary settlement: both201; Bank−200, expense payable+100, AP+100; July journal unchanged. Actual rejection does not corrupt GL, but prevents clearing obligations after month-end. Since periods cannot reopen through the API, the documented normal settlement workflow is unavailable.

Root cause: `server/src/models/ExpensePayment.ts:55` asserts the original expense's period is open in addition to payment date. `server/src/services/paymentValidation.ts:167` asserts the supplier bill's original date is open, reached through SupplierBill.pay and SupplierPaymentService. The new entries would be `EXPENSE_PAYMENT` and `SUPPLIER_PAYMENT`, dated October, distinct from the July sources.

Evidence: `accounting-audit/evidence/backend-run-Lbw3la/results.json`, scenario `BACKEND-CLOSED-SOURCE-SETTLEMENT`: both statuses409, before/after balances identical, exact close/payment requests and returned error bodies, original/new journal rows and retained erp.db. Confirmed in clean data; no live or historical DB involved.

Regression recommendation: close source period, pay in later open period, assert unchanged source journal byte-for-byte and payment-date-only journal additions; still reject attempts to change/cancel the old accrual or to backdate the new payment into July. Apply the same policy to direct purchases, POs and supplier advances after explicit scope comparison.
