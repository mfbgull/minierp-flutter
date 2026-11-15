## ADDED Requirements

### Requirement: Item selection excludes items with no sellable stock
The system SHALL compute, per item and warehouse, a **sellable availability** quantity: stock held in batches that are not expired (`expiry_date IS NULL OR expiry_date >= today`), not halted, and (when batch locations are enabled) not status-overridden away from ACTIVE; plus, for non-batch-tracked items, plain `stock_balances.quantity`. The invoice item picker SHALL only offer items whose total sellable availability across warehouses is greater than zero. Availability computations MUST NOT mutate stock tables.

#### Scenario: Only expired stock exists
- **WHEN** an item's only stock lives in batches whose `expiry_date` is before today, and the user opens the invoice item picker
- **THEN** the item does not appear as a selectable option

#### Scenario: Mixed expired and non-expired stock
- **WHEN** an item has one expired batch (qty 50) and one non-expired batch (qty 30), and the user opens the invoice item picker
- **THEN** the item appears as selectable, because sellable availability (30) is greater than zero

### Requirement: Sellable quantity is exposed for item selection
The items list endpoint SHALL support a sellable filter (e.g. `?sellable_only=1`) that returns only items whose sellable availability is greater than zero, and each returned item row SHALL include its sellable availability quantity. The filter and field MUST be computed from the same batch-level rules as backend sale validation, so the picker's offer can never disagree with what the backend will accept.

#### Scenario: Picker list matches backend rules
- **WHEN** the frontend requests items with the sellable filter
- **THEN** every returned item has sellable availability greater than zero computed with the same non-expired, non-halted, ACTIVE-batch rules the backend uses when validating sales

### Requirement: Expired stock is never consumed by a sale
Every backend sale path (desktop invoice create, desktop invoice update, POS sale, sales-order→invoice convert, mobile invoice submit) SHALL allocate stock only from batches that are non-expired, non-halted, and (when batch locations are enabled) ACTIVE. When a requested line cannot be fully satisfied from such batches, the sale request SHALL be rejected with a client error (HTTP 400) naming the item and the shortfall, and the underlying transaction SHALL roll back so no stock, ledger, or GL changes persist.

#### Scenario: Insufficient non-expired stock, sufficient expired stock
- **WHEN** a sale line requests quantity 100 of an item whose non-expired batches hold 60 and whose expired batches hold 200
- **THEN** the backend rejects the request with a 400 naming the item and the shortfall, expired batches are not consumed, and stock quantities are unchanged

#### Scenario: Direct API request attempts to sell an expired batch
- **WHEN** a client calls the invoice or POS sale API directly with a line whose only satisfying stock is expired
- **THEN** the backend rejects the request with a 400 and no stock movements are recorded

#### Scenario: POS sale of expired-only stock
- **WHEN** a POS sale line's item has only expired stock in the warehouse
- **THEN** the backend rejects the sale with a 400 and no invoice or payment records are created

### Requirement: FEFO allocation ignores expired batches
When an item is expiry-tracked, batch allocation SHALL order consumable batches by earliest `expiry_date` first (dates before today excluded, NULL expiry last) and SHALL allocate across multiple non-expired batches to satisfy a quantity, consuming only from non-expired batches.

#### Scenario: Sufficient non-expired stock across multiple batches
- **WHEN** an expiry-tracked item has non-expired batches with expiry dates 2026-10-01 (qty 40) and 2026-12-01 (qty 70), and a sale line requests quantity 50
- **THEN** the allocation consumes 40 from the 2026-10-01 batch and 10 from the 2026-12-01 batch

### Requirement: Draft invoices revalidate expiry at save
When a draft invoice is saved (created or updated), stock consumption SHALL be validated against expiry as of the save date. A batch that was non-expired when the line was added but is expired at save time SHALL NOT be consumed; if no non-expired stock satisfies the line, the save SHALL be rejected with a client error naming the item.

#### Scenario: Batch expires while in a draft invoice
- **WHEN** a line was added to a draft invoice when its batch was non-expired, the batch's `expiry_date` passes before the invoice is saved, and the item has no other non-expired stock
- **THEN** the save is rejected with a 400 naming the item, and the draft's previously recorded state is not silently modified into an expired-batch sale

### Requirement: Expired-batch sale override flow is removed
The system SHALL NOT provide any mechanism to sell expired stock by overriding batch expiry. The frontend override dialog, the temporary expiry-clearing PATCH calls, the `expired_batch_overrides` request field, and the `override_sale` invoice flag SHALL be removed; the backend SHALL ignore/reject such overrides. Invoice presentation SHALL NOT render expired-sale labels or expiry-override notices, because expired stock cannot appear on a valid invoice.

#### Scenario: Override request field is rejected
- **WHEN** a client submits `POST /api/invoices` with a non-empty `expired_batch_overrides` field
- **THEN** the backend rejects the request with a 400 (unknown/unallowed field), or ignores the overrides entirely and enforces expiry blocking — no `override_sale` flag is set and no expired batch is consumed

#### Scenario: No expired-sale labeling remains
- **WHEN** a user views or prints any invoice
- **THEN** no "sold after expiry" / expired-sale badge or expiry-override notice is rendered for invoice lines, since expired stock can no longer be sold

### Requirement: Returns and reversals never make expired batches sellable
Returns, cancellations, deletions, and updates that reverse stock SHALL restore quantity to the original batches regardless of expiry (stock records stay truthful), but restored quantity in an expired batch SHALL NOT count toward sellable availability and SHALL NOT be consumable by any subsequent sale until the batch is no longer expired.

#### Scenario: Return of an item whose batch has since expired
- **WHEN** a sale is returned after its original batch expired, and the restored quantity lands back on that expired batch
- **THEN** the item's sellable availability does not increase from the restored expired quantity, and a new invoice line for that item is rejected unless other non-expired stock exists

#### Scenario: Invoice update reverses then re-consumes
- **WHEN** an invoice update reverses the original consumption (restoring expired-in-the-meantime batches) and the new lines need stock
- **THEN** re-consumption only allocates from non-expired batches; if insufficient, the update is rejected with a 400 and the invoice retains its original state
