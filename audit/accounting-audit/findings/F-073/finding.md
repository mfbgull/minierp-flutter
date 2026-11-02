# F-073 — Explicit zero POS cash becomes a fabricated full cash receipt

> Current assessment, 2026-10-26: this report preserves its historical audit snapshot. See [remediation status](../../remediation/STATUS.md) for current source verification, fixes, tests and remaining limits.

**Status: Confirmed defect. Severity: Critical.** Executed on2026-10-25 against a fresh guarded fixture; independently verified read-only during finalization. No production fix applied.

## Reproduction and independent expected result

Run `node accounting-audit/tests/sales-channel-extension.cjs`. In final retained run `sales-channel-run-AFjr5O`, send authenticated `POST /api/pos/sale` with warehouse1, one item6 unit priced17.35, `cash_received:0` and valid `Idempotency-Key: SC-zero-cash-valid`.

The walk-in cash sale has received zero. The existing insufficient-cash rule should reject atomically: no payment, cash, invoice or inventory mutation. It cannot declare full cash collected merely because the supplied number is zero.

Actual201 response substitutes cash_received17.35, creates a Cash payment17.35 and marks the invoice paid. Before/after journal snapshots independently show cash **+1735paise**, AR unchanged, inventory **−925paise**, COGS+925 and revenue+1735. No real tender was supplied. This can release goods while recording a fictitious receipt; balanced journal/subledger checks still pass because the fabricated payment is copied consistently.

## Root cause / source

`server/src/controllers/posController.ts:156–182`, `resolvePosPaymentLegs`, computes `parseFloat(String(body.cash_received)) || total`. A valid zero is falsy and replaced with the total before the insufficient-cash comparison. The non-payment-leg POS branch therefore defeats its own guard. This source file still matches the original audit source snapshot at final review.

## Evidence and correction requirements

- Exact body/status/response: `accounting-audit/evidence/sales-channel-run-AFjr5O/api-events.json`.
- SQL/GL/payment/invoice evidence: `19-pos-zero-before.json`, `20-pos-zero-after.json` in that run; retained `erp.db`.
- Independent proof: [final-extension-verification.json](../../evidence/final-extension-verification.json), findingF073. Verifier: `node accounting-audit/tests/final-extension-verifier.cjs` opens retained DBs read-only and checks integer-paise deltas.
- Expected/actual assertions remain red in the sales-channel results. An earlier too-short idempotency key was a superseded harness error, not protection against this valid-key request.

Recommended correction: distinguish absent/unparseable input from numeric zero, preserve explicit zero and reject insufficient tender before committing any document/stock/payment. Regression must include zero, negative, insufficient positive, exact and excess tender, explicit credit legs, same-key retry and no-key compatibility. Assert the real tender independently of MiniERP's returned payment list. No fix implemented.
