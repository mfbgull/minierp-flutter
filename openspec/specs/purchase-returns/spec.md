# Purchase Returns

## Purpose

Users can create purchase returns (against a direct purchase or a purchase
order) from the purchase return screen and from the source documents' row
menus. A return reduces stock from the source document's warehouse and, when
posted, creates the supplier credit note + GL reversal.
## Requirements
### Requirement: purchase-return-entry
The purchase return screen SHALL expose a dedicated new-return action that opens the purchase return entry flow.

#### Scenario: new return from purchase return screen
- **WHEN** a user is on the purchase return screen
- **THEN** a new-return action is available and opens the purchase return entry flow

### Requirement: purchase-order-return-menu
A purchase order's 3-dot menu SHALL offer a Return option that routes to purchase return creation for that order.

#### Scenario: return from purchase order
- **WHEN** a user opens the 3-dot menu on a purchase order
- **THEN** a Return option is available and routes to purchase return creation for that order

### Requirement: purchase-return-menu
A purchase's 3-dot menu SHALL offer a Return option that routes to purchase return creation for that purchase.

#### Scenario: return from purchase
- **WHEN** a user opens the 3-dot menu on a purchase
- **THEN** a Return option is available and routes to purchase return creation for that purchase

### Requirement: purchase-return-source-warehouse
A purchase return SHALL reduce stock from the source document's warehouse; the warehouse SHALL NOT be user-selectable.

#### Scenario: warehouse is fixed to the source
- **WHEN** a user submits a return for a purchase or purchase order
- **THEN** stock is reduced in the source document's warehouse and the form shows it read-only

### Requirement: Returnable quantity validation aggregates duplicate lines
Returnable quantity SHALL be derived from the source document (`purchases.quantity - returned_quantity`, `purchase_order_items.received_quantity - returned_quantity`). When one request contains multiple lines for the same `(source_type, source_item_id)`, validation SHALL aggregate their quantities and validate the aggregate against the source headroom; conflicting unit costs across duplicates SHALL be rejected. The `returned_quantity` increment SHALL re-check headroom atomically in the UPDATE.

#### Scenario: Duplicate lines cannot over-return
- **WHEN** a return request carries two lines of 50 each against a 50-unit purchase with nothing returned
- **THEN** the request fails 400 naming the aggregate overage, and no stock, ledger, credit-note, or counter row is written

#### Scenario: Aggregate within headroom passes
- **WHEN** a 100-unit purchase receives two lines of 30 and 40 against the same item
- **THEN** the return posts with returned_quantity = 70

### Requirement: Returns consume the source document's own batches
Stock reduction for a return line SHALL consume the batch created by that line's own source document (direct purchase: source_type='PURCHASE' with its id; PO line: source_type='GOODS_RECEIPT' with its goods-receipt-item id). If available coverage in those batches is less than the requested quantity, creation SHALL fail naming the shortfall — silent partial consumption is prohibited. Per-line batch consumption SHALL be persisted (`purchase_return_batches`) and void SHALL restore exactly those batches, making create-then-void a value-identity operation on inventory.

#### Scenario: Return after most stock was sold fails loudly
- **WHEN** 45 of 50 purchased units were sold and a full 50-unit return is requested
- **THEN** the request fails naming the 5-unit shortfall and records nothing

#### Scenario: Void restores exactly what create consumed
- **WHEN** a valid return consuming batch X (10 units) is voided
- **THEN** batch X's quantity_remaining increases by exactly 10 and no other batch changes

### Requirement: Supplier resolution is foreign-key based and fails closed
Purchase-return supplier identity SHALL come from `purchases.supplier_id` or `purchase_orders.supplier_id`. Name-based lookup SHALL NOT exist. An unresolvable supplier SHALL abort the transaction before any write; posting a credit note without its supplier-ledger entry is prohibited. Every supplier-ledger entry written by return create or void SHALL be followed by a balance rebuild for that supplier.

#### Scenario: Renamed supplier still gets credited
- **WHEN** a return is created against a purchase whose supplier has been renamed since
- **THEN** the credit note and supplier_ledger credit post to the FK-resolved supplier id and suppliers.current_balance reflects it

### Requirement: Paid-stock returns require disposition
A return whose value exceeds the purchase's unpaid balance SHALL require an explicit disposition (`credit_on_account` | `refund_expected`); otherwise creation SHALL be refused. The chosen disposition SHALL be recorded on the credit note.

#### Scenario: Overpaid return must declare disposition
- **WHEN** goods worth 500 are returned from a fully paid purchase with no disposition supplied
- **THEN** creation fails explaining the supplier would be owed money; supplying `refund_expected` succeeds and stamps the credit note

### Requirement: A purchase return settled in cash is capped by the cash collected on the source document
A purchase return with `disposition: 'refund_expected'` SHALL NOT pay out more
cash than was collected against the source purchase or purchase order. When
nothing has been collected, the disposition SHALL be refused.

`refund_expected` promises money to the supplier, so it may only promise money
that arrived. Refunding the full return value regardless of collections posts
`Dr Cash / Cr AP` and manufactures both a cash asset and an AP credit out of an
unpaid purchase — a balanced entry, so every ledger invariant stays green.

The caller-facing remedy is `credit_on_account`, which records the credit note
without moving cash.

#### Scenario: Refunding an unpaid purchase is refused
- **WHEN** a purchase of 900 has no allocation against it and a return of value 300 carries `disposition: 'refund_expected'`
- **THEN** the request returns an error of 400 or greater
- **AND** the response explains that nothing has been collected and names `credit_on_account`
- **AND** net cash is unchanged

#### Scenario: A partially paid purchase refunds at most the collected amount
- **WHEN** a purchase of 500 has 100 collected and a return of value 250 carries `disposition: 'refund_expected'`
- **THEN** the return is accepted
- **AND** the refund moves no more than the 100 collected
- **AND** the trial balance still foots

#### Scenario: Credit on account remains available on an unpaid purchase
- **WHEN** a return against a fully unpaid purchase carries `disposition: 'credit_on_account'`
- **THEN** the return is accepted
- **AND** no cash moves

### Requirement: The collected amount is read from live allocations
The collected amount SHALL be the sum of `purchase_allocations` (or
`po_allocations`) whose `voided_at IS NULL`, and SHALL exclude voided rows.

A voided allocation is money that was taken back, so counting it would permit a
refund of cash that no longer exists.

#### Scenario: A voided allocation does not count as collected
- **WHEN** a purchase has one live allocation of 100 and one voided allocation of 400
- **THEN** the collected amount is 100
- **AND** a refund of more than 100 is refused

#### Scenario: An allocation for a different document is not counted
- **WHEN** the only allocation against a purchase belongs to another purchase
- **THEN** the collected amount for this purchase is 0

