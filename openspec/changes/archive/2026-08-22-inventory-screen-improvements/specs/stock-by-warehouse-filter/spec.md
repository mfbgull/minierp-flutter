## ADDED Requirements

### Requirement: Warehouse dropdown filters Stock by Warehouse grid
The Stock by Warehouse screen toolbar SHALL provide a warehouse dropdown
that filters the grid to the selected warehouse's balances, plus an
"All Warehouses" entry that shows every warehouse.

#### Scenario: Default shows all warehouses
- **WHEN** the Stock by Warehouse screen loads
- **THEN** the warehouse dropdown defaults to "All Warehouses" and the grid shows balances across all warehouses

#### Scenario: Select a specific warehouse
- **WHEN** the user selects a warehouse from the dropdown
- **THEN** the grid shows only balances for that warehouse

#### Scenario: Search and Refresh remain available
- **WHEN** the toolbar is rendered
- **THEN** Search and Refresh buttons are present and operate as before alongside the warehouse dropdown
