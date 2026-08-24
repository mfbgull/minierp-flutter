# Activity Log Grid

## Purpose

The activity log screen grid loads and displays activity records.

## Requirements

### Requirement: activity-log-grid-data-visibility
The activity log screen grid MUST load and display data records.

#### Scenario: activity log renders rows
- **WHEN** a user opens the activity log screen
- **THEN** the grid shows activity log records instead of an empty state caused by missing or misbound data

### Requirement: Grid surfaces change detail
The activity log grid/detail view SHALL display old_value/new_value diffs, reason, and correlation id where present, and SHALL allow filtering/grouping by correlation id to follow one business event across its linked rows.

#### Scenario: Value diff is visible
- **WHEN** a user opens a log row recorded with old_value and new_value
- **THEN** both values render readably (JSON pretty-printed) without opening raw SQL tools

#### Scenario: Follow one event across rows
- **WHEN** a user filters by a correlation id
- **THEN** all rows sharing that id (invoice mutation plus stock/GL entries) are listed in order
