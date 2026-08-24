## MODIFIED Requirements

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
