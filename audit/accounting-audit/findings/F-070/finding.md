# F-070 — Repeated sales-order cancellation is reported as a server failure

> Current assessment, 2026-10-26: this report preserves its historical audit snapshot. See [remediation status](../../remediation/STATUS.md) for current source verification, fixes, tests and remaining limits.

**Status: Confirmed defect. Severity: Low.** API error classification only; no second financial effect demonstrated.

In the fresh quotation→confirmed SO→invoice lifecycle, POST `/api/sales-orders/1/cancel` succeeds200 and economically reverses the invoice. Repeat the same request. Expected controlled invalid-state4xx under the documented reversal rules; actual500 with `Sales order is already cancelled`. Before/after economic hashes are identical on the second request. Do not describe this as duplicate money or stock restoration.

Source: `server/src/controllers/salesController.ts:314–328` maps only InvoiceCancellationGuardError to409, then maps the model's already-cancelled error to500. The state guard itself works.

Evidence: `accounting-audit/evidence/sales-channel-run-AFjr5O/api-events.json`, `04-sales-order-cancelled.json`, `05-sales-order-repeat-cancel.json`. Reproduction: `node accounting-audit/tests/sales-channel-extension.cjs`. Independent check of500 and equal hashes: [final-extension-verification.json](../../evidence/final-extension-verification.json), F070.

Recommended correction: classify the existing domain state error as a controlled4xx while retaining its no-mutation guard. Regression: repeated cancellation returns the documented client error and leaves journals, quantities, reservations and allocations unchanged. No fix applied.
