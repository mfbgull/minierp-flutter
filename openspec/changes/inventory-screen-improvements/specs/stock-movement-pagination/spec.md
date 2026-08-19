## ADDED Requirements

### Requirement: Stock Movement grid paginates loaded rows
The Stock Movement screen SHALL split its loaded movement rows into
client-side pages so the grid does not render one unbounded list.

#### Scenario: Grid shows paged rows
- **WHEN** the Stock Movement screen loads with more rows than the page size
- **THEN** the grid displays only the current page and renders a pagination control below it

#### Scenario: User navigates pages
- **WHEN** the user changes the page via the pagination control
- **THEN** the grid shows the corresponding page of rows without refetching from the server

#### Scenario: Filter change keeps paging
- **WHEN** the user changes the movement-type filter
- **THEN** the grid reloads and pagination restarts at the first page
