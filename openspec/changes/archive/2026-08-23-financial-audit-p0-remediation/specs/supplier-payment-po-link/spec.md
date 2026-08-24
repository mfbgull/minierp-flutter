## ADDED Requirements

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
