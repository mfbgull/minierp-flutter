## ADDED Requirements

### Requirement: Price-history hint on rate edit
When a rate cell enters edit mode and the line has both an item and a customer, the form SHALL call `GET /sales/item-customer-history?item_id=:id&customer_id=:id`; if `transaction_count > 0` a price-history overlay SHALL be shown anchored under the rate cell (past prices, lowest, count) without stealing focus. Click-outside SHALL close it.

#### Scenario: Hint appears when history exists
- **WHEN** a rate cell is edited on a line with item_id and customer_id set and the history endpoint returns transaction_count > 0
- **THEN** a price-history overlay appears under the rate cell showing past prices / lowest / count and does not steal focus

#### Scenario: Close on outside click
- **WHEN** the user clicks outside the hint
- **THEN** the hint closes

#### Scenario: No hint without item or customer
- **WHEN** the rate cell is edited but item_id or customer_id is unset, or transaction_count is 0
- **THEN** no hint is shown