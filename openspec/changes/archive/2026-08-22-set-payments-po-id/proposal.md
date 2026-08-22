## Why

`PaymentModel.createSupplierPayment` records supplier payments and their allocations in the
`po_allocations` / `purchase_allocations` junction tables, but it never populates the
`payments.purchase_order_id` column on the `payments` row. Reports that join
`payments.purchase_order_id` (e.g. `Reports.ts` PO paid-amount query) therefore silently
under-count supplier payments, so a PO can look "unpaid" even after it has been settled. This
is a data-consistency bug introduced when payment recording moved to the allocation junction
tables; fixing it closes the reporting gap with zero behavior change for callers.

## What Changes

- `PaymentModel.createSupplierPayment` will set `payments.purchase_order_id` when the payment
  allocates to **exactly one** purchase order (and no purchase allocations).
- When a payment spans multiple POs, or mixes PO + purchase allocations, `purchase_order_id`
  stays `NULL` (the column is single-valued, so a single link cannot represent multiple POs —
  the `po_allocations` table remains the source of truth for those cases).
- No API contract change, no new endpoint, no schema migration (the column already exists).

## Capabilities

### New Capabilities
- `supplier-payment-po-link`: Requirement that a supplier payment tied to a single purchase
  order is also reflected on `payments.purchase_order_id`, so PO-level payment reporting joins
  correctly.

### Modified Capabilities
<!-- none — this is an internal consistency fix, no existing spec requirement changes -->

## Impact

- **Code**: `src/models/Payment.ts` (`createSupplierPayment` INSERT). Possibly the `update`
  path if amount edits need to preserve the link (out of scope unless it rewrites allocations).
- **Reports**: `src/models/Reports.ts` PO paid-amount joins on `payments.purchase_order_id`
  will now pick up single-PO supplier payments.
- **Data**: Newly recorded single-PO supplier payments get the column set; historical rows
  get `NULL` until a later single-PO payment is recorded (no backfill needed — `po_allocations`
  remains the source of truth). The migration is idempotent (column-existence guard) and runs
  on server startup.
- **Risk**: None for existing flows — `purchase_order_id` was previously always `NULL` from
  this path, so populating it only *adds* information.
