# batch-source-typing (Delta)

## ADDED Requirements

### Requirement: A receipt warehouse must match the warehouse its PO named
A goods receipt SHALL be rejected when its `warehouse_id` differs from the
`warehouse_id` recorded on the purchase order it receipts against.

The batch, the stock movement and the balance all use the RECEIPT's warehouse,
so a mismatch silently relocates stock to a warehouse the PO never authorised.

A purchase order with a NULL `warehouse_id` authorises no particular warehouse,
so the receipt's is accepted in that case.

#### Scenario: A receipt into an unauthorised warehouse is rejected
- **WHEN** a PO names warehouse 8 and a receipt supplies warehouse 9
- **THEN** the receipt is rejected

#### Scenario: A receipt into the PO's warehouse is accepted
- **WHEN** a PO names warehouse 8 and a receipt supplies warehouse 8
- **THEN** the receipt is created

#### Scenario: A warehouse-less PO accepts any receipt warehouse
- **WHEN** the PO records no warehouse
- **THEN** the receipt is created against the warehouse it supplies
