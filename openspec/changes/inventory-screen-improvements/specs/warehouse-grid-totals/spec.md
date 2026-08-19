## ADDED Requirements

### Requirement: Warehouses grid displays Total Items and Unique Items
The Warehouses grid SHALL display each warehouse's Total Items and Unique
Items values returned by the server.

#### Scenario: Totals populated from server
- **WHEN** the Warehouses screen loads
- **THEN** the Total Items and Unique Items columns show the aggregate quantities computed by the server (not zero/blank)

#### Scenario: Warehouse with stock
- **WHEN** a warehouse has stock balances
- **THEN** Total Items equals the summed balance quantity and Unique Items equals the count of distinct items for that warehouse
