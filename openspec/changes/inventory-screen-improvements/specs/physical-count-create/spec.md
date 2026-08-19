## ADDED Requirements

### Requirement: Physical Count screen provides a New Count action
The Physical Count screen toolbar SHALL provide a "New Count" button that
creates a physical count via the existing API and refreshes the grid.

#### Scenario: Open create dialog
- **WHEN** the user clicks "New Count"
- **THEN** a dialog opens to enter a warehouse, count date, and notes

#### Scenario: Create succeeds
- **WHEN** the user submits a valid count
- **THEN** the count is created via the API and the grid refreshes to include the new count

#### Scenario: Create fails
- **WHEN** the create request fails (e.g. missing warehouse)
- **THEN** the dialog shows an error and the grid is unchanged
