## ADDED Requirements

### Requirement: Expenses report screen renders at the reports route

The system SHALL render the Expenses report at the `/reports/expenses` route instead of the "coming soon" placeholder. The screen SHALL call `GET /reports/expenses` with `fromDate` and `toDate` query parameters (both required — the server returns a 400 without them) and an optional `category` parameter, then display the returned data: an expenses grid, a KPI summary strip, and a category breakdown list.

The report is read-only: it SHALL NOT create, update, or delete expense records. Request failures (network error, `{ success: false, error }` response) SHALL render the shared `ScreenErrorPanel` with the error message and a retry action that refetches.

#### Scenario: Initial load with default date range

- **WHEN** the user opens `/reports/expenses`
- **THEN** the screen fetches the report for the default range (first day of the previous month through today) and shows the grid rows, KPI strip, and category breakdown once loaded

#### Scenario: Server error

- **WHEN** the request fails (network error or `{ success: false, error }` response)
- **THEN** the screen shows the error panel with the error message and a retry button that refetches

#### Scenario: No expenses in range

- **WHEN** the report returns an empty expenses array
- **THEN** the grid shows the shared no-results placeholder, while the summary strip and category breakdown still render when present

### Requirement: Date range and category filtering

The user SHALL be able to narrow the report by date range and expense category. Changing either date refetches automatically; selecting a category from the dropdown (or clearing it to "All Categories") refetches with or without the `category` parameter. Category options SHALL come from `GET /expenses/categories`.

#### Scenario: Changing the date range

- **WHEN** the user picks a new From or To date in the report date control
- **THEN** the report refetches with the new dates and the grid, summary, and breakdown update

#### Scenario: Filtering by category

- **WHEN** the user selects a category from the dropdown
- **THEN** the report refetches with `category=<name>` and shows only expenses in that category

#### Scenario: Clearing the category

- **WHEN** the user selects "All Categories"
- **THEN** the report refetches without the `category` parameter

### Requirement: KPI summary strip

The screen SHALL show three KPI cells above the grid from the report `summary` object: **Total Expenses** (the summed amount), **Total Records** (the expense count), and **Average Expense** (total divided by count). The values SHALL be the server's own summary numbers, not a client-side recomputation of the rows.

#### Scenario: Summary values displayed

- **WHEN** the report returns a summary object
- **THEN** the three KPI cells show the total, count, and average formatted as currency/numbers consistent with the app theme

#### Scenario: Server summary is authoritative

- **WHEN** the report returns a summary object
- **THEN** the KPI strip displays those values verbatim

### Requirement: Expense grid

The system SHALL list every expense row in a read-only PlutoGrid with columns: Expense No, Category, Description, Amount, Date, Payment Method, Reference No, Vendor, Project, Status. Amounts are formatted as currency and right-aligned; dates are formatted per locale; the Status column renders the localized expense-status badge (same helper as the `/expenses` list screen).

#### Scenario: Grid renders row data

- **WHEN** the report returns expense rows
- **THEN** each row displays its fields with currency formatting and the status badge, preserving the web grid's column order

#### Scenario: Loading state

- **WHEN** a range change triggers a refetch
- **THEN** the grid shows the loading overlay and the export control is disabled until the new data lands

### Requirement: CSV export

The screen SHALL provide an Export CSV action using the shared `saveCsv` helper with a suggested filename following the sibling report screens' convention. The export SHALL include the grid's columns. Export failures SHALL show the shared failure toast; success shows the success toast.

#### Scenario: Exporting the report

- **WHEN** the report has rows and the user clicks Export CSV
- **THEN** a save dialog offers the suggested filename, the CSV contains the grid's columns, and a success toast appears

#### Scenario: Export disabled without data

- **WHEN** the report has no rows or is still loading
- **THEN** the export action is disabled