# supplier-payment-po-link Specification

## Purpose

Supplier payments link to the purchase order they settle: new single-PO
payments record the linkage at creation, historical rows are backfilled from
allocations, and exactly one counterparty is enforced.

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


### Requirement: Existing single-PO payments are backfilled
A one-time migration SHALL set `payments.purchase_order_id` for existing rows where `po_allocations` contains exactly one distinct po_id and `purchase_allocations` is empty. The backfill SHALL be idempotent (NULL-only predicate) and SHALL log the affected count to activity_log.

#### Scenario: Historical single-PO payment recovers its link
- **WHEN** the migration runs against a database with a fully-PO-allocated payment whose purchase_order_id is NULL
- **THEN** the column equals that PO's id, allocations are unchanged, and re-running changes nothing

### Requirement: Exactly one counterparty per payment
The payments table SHALL enforce `(customer_id IS NULL) <> (supplier_id IS NULL)` via CHECK constraint, and the create API SHALL reject requests supplying both or neither with 400 before any write.

#### Scenario: Both counterparties rejected
- **WHEN** a create request supplies customer_id and supplier_id together
- **THEN** it fails 400 and no row is written (previously supplier_id was silently discarded)

#### Scenario: Database enforces what the API misses
- **WHEN** a write path bypasses the controller guard
- **THEN** the CHECK constraint aborts the insert
