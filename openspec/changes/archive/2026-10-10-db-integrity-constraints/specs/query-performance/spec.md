# query-performance (Delta)

## ADDED Requirements

### Requirement: Foreign key columns used for joins and cascades are indexed
Every foreign key column on a hot transactional table SHALL carry an index, so
that a parent delete, update, or join resolves by lookup rather than by full
table scan.

`goods_receipt_items` carried three foreign keys and no indexes at all, so the
`goods_receipts` ON DELETE CASCADE and every parent update scanned the whole
receipt table.

#### Scenario: A goods receipt delete does not scan the item table
- **WHEN** a goods receipt is deleted
- **THEN** its items are found by index on `receipt_id`

#### Scenario: Each FK column is individually covered
- **WHEN** the schema is inspected
- **THEN** `goods_receipt_items` has an index covering `receipt_id`,
      `po_item_id` and `item_id`
