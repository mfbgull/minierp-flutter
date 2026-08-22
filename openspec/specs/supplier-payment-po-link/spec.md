# supplier-payment-po-link Specification

## Purpose
TBD - created by archiving change set-payments-po-id. Update Purpose after archive.
## Requirements
### Requirement: Single-PO supplier payment links to purchase_order_id
The system SHALL set `payments.purchase_order_id` to the allocated purchase order id when a
supplier payment allocates to exactly one purchase order and allocates to no purchases.

#### Scenario: Payment allocated to a single purchase order
- **WHEN** a supplier payment is created with exactly one entry in `po_allocations` and zero entries in `purchase_allocations`
- **THEN** the inserted `payments` row SHALL have `purchase_order_id` equal to that PO's id

#### Scenario: Payment spans multiple purchase orders
- **WHEN** a supplier payment is created with more than one entry in `po_allocations` (regardless of purchases)
- **THEN** the inserted `payments` row SHALL have `purchase_order_id` set to NULL

#### Scenario: Payment mixes purchase orders and purchases
- **WHEN** a supplier payment is created with at least one `po_allocations` entry and at least one `purchase_allocations` entry
- **THEN** the inserted `payments` row SHALL have `purchase_order_id` set to NULL

### Requirement: Allocations remain authoritative
The system SHALL continue to persist every allocation in `po_allocations` and
`purchase_allocations` exactly as before; setting `purchase_order_id` SHALL NOT change, remove,
or duplicate any allocation row.

#### Scenario: Allocations preserved when column is set
- **WHEN** a single-PO supplier payment is recorded and `purchase_order_id` is populated
- **THEN** the corresponding `po_allocations` row (payment_id, po_id, amount) SHALL still exist unchanged

