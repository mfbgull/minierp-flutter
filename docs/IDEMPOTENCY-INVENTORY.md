# Idempotency Inventory

Status: 2026-11-28. Covers issue #36. Every mutating route was scanned and
placed in exactly one class: it requires an `Idempotency-Key`, or it relies on
a state guard that makes a retry harmless.

Method: `server/src/app.ts` mounts were joined with each
`router.post|put|patch|delete` declaration under `server/src/routes/`.
The scan found **179** mutating routes. Reproduce it with
`node server/scripts/idempotency-inventory.js`.

## 1. Routes that require an `Idempotency-Key` (15)

The key is mandatory: a keyless request returns 400
`Idempotency-Key header is required for this operation`. The key is claimed
inside the same transaction as the write. Same key + same payload replays;
same key + different payload returns 409 `IDEMPOTENCY_CONFLICT`.

| Scope | Endpoint |
|---|---|
| `invoice_create` | `POST /invoices` |
| `invoices.return` | `POST /invoices/:id/return` |
| `invoice-returns.settle` | `POST /invoice-returns/:id/settle` |
| `payments.customer` | `POST /payments` (customer branch) |
| `payments.supplier` | `POST /payments` (supplier branch) |
| `payments.allocate` | `POST /payments/:id/allocate` |
| `purchases.record` | `POST /purchases` |
| `purchase-orders.receipt` | `POST /purchase-orders/:id/receipts` |
| `expenses.create` | `POST /expenses` |
| `accounting.overhead.settle` | `POST /accounting/overhead/settle` |
| `owner-equity.capital` | `POST /owner-equity/capital` |
| `owner-equity.withdrawal` | `POST /owner-equity/withdrawals` |
| `employees.salary.pay` | `POST /employees/:id/salary/pay` |
| `supplier-refunds.create` | `POST /supplier-refunds` |
| `supplier-refunds.claims.create` | `POST /supplier-refunds/claims` |
| `supplier-refunds.claims.write-off` | `POST /supplier-refunds/claims/:id/write-off` |

Proof tests: `idempotencyMandate.test.ts` (mandate and mobile exemption),
`idempotencyRound1.test.ts`, `idempotencyRound2.test.ts` (replay, conflict,
failed attempt leaves no claim), `supplierRefundValidation.test.ts`,
`invoiceIdempotency.test.ts`, `bootIdempotency.test.ts`.

## 2. Routes without a key (164)

`/api/mobile-invoices/*` stays keyless on purpose (D19). The mobile app sends
no key yet, and a natural-key duplicate check was rejected there. This file
does not change that decision.

The other unkeyed routes fall into these families. Each family makes a
duplicate request harmless, or accepts a duplicate with no money, stock or GL
effect.

| Family | Example | Why a retry is safe |
|---|---|---|
| Delete | `DELETE /api/customers/:id` | Second call finds no row; it returns 404 and deletes nothing |
| Terminal status | `POST /api/purchase-orders/:id/status` | The transition table refuses `Cancelled` -> `Cancelled` with 4xx |
| Set-state | `POST /api/inventory/item-companies/:id/archive` | Sets an absolute value, not a delta; the second call writes the same value |
| Recompute | `POST /api/customers/recalculate-balances` | Rebuilds balances from `customer_ledger`; the second call writes the same result |
| Upsert | `POST /api/settings/bulk` | Writes key/value pairs; the second call writes the same values |
| Counted create | `POST /api/forecasts/seasonal-events` | Creates a new row; a retry adds a second row. No money, stock or GL effect |
| Read-only | `POST /api/owner-equity/withdrawals/quote` | Computes a quote and writes nothing |

Known limitation: `PATCH /api/boms/:id/toggle-active` flips state. Two calls
return to the original state. It is a UI toggle with no money, stock or GL
effect, so it is documented here and not changed.

## 3. Routes with no direct request test (19)

These have no test that calls the route path (the model or a service may be
tested). Each was read and classified. The physical-count cancel route was in
this list; section 4 now covers it with a direct request test.

| Route | Class | Disposition |
|---|---|---|
| `POST /api/customers/recalculate-balances` | Recompute | Recomputed from the ledger; read and verified |
| `POST /api/suppliers/recalculate-balances` | Recompute | Recomputed from the ledger; read and verified |
| `POST /api/settings/bulk` | Upsert | Key/value upsert; verified by source read |
| `PUT /api/owner-equity/borrowers/:id/reactivate` | Set-state | Sets `active = 1` |
| `POST /api/owner-equity/withdrawals/quote` | Read-only | Writes nothing |
| `PATCH /api/boms/:id/toggle-active` | Toggle | Known limitation above |
| `PUT /api/dashboard/layout/:id/activate` | Set-state | Sets the active layout |
| `POST /api/reports/custom/:id/duplicate` | Counted create | A retry makes a second copy; no money, stock or GL |
| `POST /api/forecasts/generate` | Recompute | Builds the forecast list in memory |
| `POST /api/forecasts/compute-accuracy` | Recompute | Recomputes accuracy |
| `POST /api/forecasts/override` | Upsert | Upserts the month override |
| `POST /api/forecasts/seasonal-events` | Counted create | A retry makes a second row |
| `DELETE /api/forecasts/seasonal-events/:id` | Delete | 404 on the second call |
| `POST /api/inventory/item-companies/:id/suppliers/:supplierId` | Link | Link is keyed by the pair |
| `DELETE /api/inventory/item-companies/:id/suppliers/:supplierId` | Delete link | 404 on the second call |
| `PUT /api/inventory/item-companies/:id` | Update | Writes absolute fields |
| `POST /api/inventory/item-companies/:id/archive` | Set-state | Sets `active = 0` |
| `POST /api/inventory/item-companies/:id/restore` | Set-state | Sets `active = 1` |
| `DELETE /api/inventory/item-companies/:id` | Delete | 404 on the second call |

## 4. Direct-request guard test

`server/src/__tests__/idempotencyStateGuards.test.ts` calls the physical-count
cancel route twice. It asserts both calls return 200, the status stays
`Cancelled`, and no stock movement or stock-balance change results.

## 5. Rules kept

- Keys were added only where a retry gap was reproduced and the API contract
  supports a key. This change adds no key.
- `/api/mobile-invoices/*` stays keyless under D19.
- No UNIQUE index was added on `journal_lines(reference_type, reference_id)`.
- No natural-key duplicate check was added for mobile invoices.
