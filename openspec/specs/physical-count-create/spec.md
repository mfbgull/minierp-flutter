# physical-count-create Specification

## Purpose
Enables warehouse staff to initiate new physical counts through a dedicated UI workflow. Creates count snapshots, assigns them to warehouses, and provides a clean interface for entering count dates and notes, with proper validation and grid refresh upon successful creation.
## Requirements
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

