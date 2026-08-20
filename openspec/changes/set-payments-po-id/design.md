## Context

`PaymentModel.createSupplierPayment` (`src/models/Payment.ts`) records a supplier payment by
inserting a `payments` row, writing each allocation into `po_allocations` /
`purchase_allocations`, posting a `supplier_ledger` PAYMENT entry, and updating
`suppliers.current_balance`. The `payments` table already has a `purchase_order_id` column
(used by `Reports.ts` to compute paid-amount per PO), but `createSupplierPayment` never sets
it — so single-PO supplier payments are invisible to those joins.

## Goals / Non-Goals

**Goals:**
- Populate `payments.purchase_order_id` when a supplier payment allocates to exactly one PO.
- Keep `po_allocations` as the authoritative, multi-PO-capable record of allocations.

**Non-Goals:**
- No schema migration (column exists).
- No change to the `update`/allocation-rewrite paths.
- No historical backfill of existing rows.
- No change to how multi-PO or PO+purchase mixed payments are stored (`purchase_order_id`
  stays `NULL` for those).

## Decisions

**D1 — Set the column in the existing INSERT, derived from allocations.**
Compute `singlePoId` inside `createSupplierPayment`:
- `poAllocs.length === 1 && purchaseAllocs.length === 0` → `parseInt(poAllocs[0].po_id, 10)`
- otherwise → `null`
Then include `singlePoId` in the `INSERT INTO payments (...) VALUES (...)`.
*Rationale*: one localized change, reuses the already-validated `poAllocs`, no new query.
Alternative considered: a post-insert `UPDATE payments SET purchase_order_id = ?` — rejected as
an extra write with no benefit.

Note: `payments.purchase_order_id` did **not** previously exist (it was referenced by
`Reports.ts` but never created). A new idempotent migration
`src/migrations/add-payments-purchase-order-id.sql` (guarded by a column-existence check in
`runPaymentsPurchaseOrderIdMigration`) adds it on server startup, so no manual step is needed.

**D2 — Leave the column `NULL` for multi-PO / mixed allocations.**
The `purchase_order_id` column is single-valued and cannot represent multiple POs. Forcing a
value there would mis-attribute payments. The junction `po_allocations` remains the source of
truth for those cases, and the Reports join already handles them via `po_allocations`.
*Rationale*: correctness over convenience; avoids silently attributing a multi-PO payment to a
single PO.

**D3 — No change to `PaymentModel.update`.**
Updating a payment's amount/date does not rewrite allocations, so any `purchase_order_id` set
at creation is preserved. Recomputing it on update would add complexity for no current caller.

## Risks / Trade-offs

- [Risk] A report joins BOTH `payments.purchase_order_id` and `po_allocations`, double-counting
  single-PO payments. → Mitigation: `Reports.ts` currently joins only `payments.purchase_order_id`;
  if a future report joins both, it must de-duplicate (prefer `po_allocations` as canonical).
- [Risk] `po_id` in allocation is a string and could be non-numeric. → Mitigation: reuse the
  same `parseInt(alloc.po_id, 10)` already used for validation; if it is `NaN` the single-PO
  condition (exactly one valid allocation) simply won't hold, so column stays `NULL`.

## Migration Plan

No migration. Deploy is a code change only. Rollback = revert the edit; historical rows keep
whatever value was set. No data loss.

## Open Questions

- None. (A historical backfill is optional and explicitly out of scope.)
