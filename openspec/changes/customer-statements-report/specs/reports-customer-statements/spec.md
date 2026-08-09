## ADDED Requirements

### Requirement: Customer statements report screen renders at the reports route

The system SHALL render the Customer Statements report at the `/reports/customer-statements` route instead of the "coming soon" placeholder. The screen SHALL call `GET /reports/customer-statements` with `fromDate` and `toDate` query parameters and an optional `customerId` parameter, then display the returned `statements` array: a read-only PlutoGrid of per-customer statement rows.

The report is read-only: it SHALL NOT create, update, or delete customer/invoice/payment records, and it SHALL NOT reuse or modify the per-customer line-level statement screen at `/customers/:id/statement`. Request failures (network error, `{ success: false, error }` response) SHALL render the shared `ScreenErrorPanel` with the error message and a retry action that refetches.

#### Scenario: Initial load with default date range

- **WHEN** the user opens `/reports/customer-statements`
- **THEN** the screen fetches the report for the default range (same day 3 months ago through today — mirroring the web page's initial state) and shows the statement rows once loaded

#### Scenario: Server error on load

- **WHEN** the request fails (network error or `{ success: false, error }` response)
- **THEN** the screen shows the error panel with the error message and a retry button that refetches

#### Scenario: Empty statements array

- **WHEN** the report returns an empty `statements` array
- **THEN** the grid shows the shared no-results placeholder and the export action is disabled

### Requirement: Date-range and customer filtering

The user SHALL be able to narrow the report by date range and by a single customer. Changing the From or To date refetches automatically. Choosing a customer from the dropdown refetches with the `customerId` parameter; choosing "All Customers" omits it. Customer options SHALL come from `GET /customers` (id + customer name).

#### Scenario: Changing the date range

- **WHEN** the user picks a new From or To date in the report date control
- **THEN** the report refetches with the new dates and the grid updates

#### Scenario: Filtering by customer

- **WHEN** the user selects a customer from the dropdown
- **THEN** the report refetches with `customerId=<id>` and shows only that customer's statement row

#### Scenario: Clearing the customer filter

- **WHEN** the user selects the "All Customers" option
- **THEN** the report refetches without the `customerId` parameter

### Requirement: Customer statements grid

The system SHALL list every statement row in a read-only PlutoGrid with columns in web order: Customer Name, Customer Code, Opening Balance, Total Debits, Total Credits, Closing Balance. Amount columns SHALL be formatted as currency, right-aligned, and consistent with the app theme. Each row carries an invisible id key (the server's `customer_id`) so it can be opened in the detail dialog.

#### Scenario: Columns match the web report

- **WHEN** the grid renders
- **THEN** the six columns appear in the web's order with currency-formatted amount cells

### Requirement: Detail dialog per row

The system SHALL show a detail dialog when the user double-taps a grid row: Customer Code, Invoice Count, Total Amount, Paid Amount, Balance, and Last Invoice Date (formatted per locale). The dialog is read-only and dismissible via its close button, Escape, or outside-tap.

#### Scenario: Double-tapping a row

- **WHEN** the user double-taps a statement row
- **THEN** a dialog opens showing the row's customer code, invoice count, totals, balance, and last invoice date

#### Scenario: Dismissing the dialog

- **WHEN** the user closes the dialog or presses Escape
- **THEN** the dialog closes and the grid remains unchanged

### Requirement: CSV export

The user SHALL be able to export the currently visible statement rows to a CSV file with columns: Customer Name, Customer Code, Opening Balance, Total Debits, Total Credits, Closing Balance. The export uses the shared `saveCsv` helper and shows the app's standard "exported" / "export failed" toasts. Export is disabled while the report is loading or empty.

#### Scenario: Successful export

- **WHEN** the report has rows and the user taps Export CSV and confirms the save
- **THEN** a CSV file is written with one row per statement and the "exported" toast appears

#### Scenario: Export failure feedback

- **WHEN** the file write fails
- **THEN** the "export failed" toast appears and no crash occurs

### Requirement: Statement rows come from the server verbatim

The screen SHALL render the server's own numbers (opening_balance, total_debits, total_credits, closing_balance, balance, invoice_count, total_amount, paid_amount) without client-side recomputation — the endpoint MUST NOT be reimplemented in the client (PORTING.md §11: the Flutter screens consume the endpoint and render the shape from `Reports.ts`).

#### Scenario: Server values displayed verbatim

- **WHEN** the report returns rows
- **THEN** every cell displays the exact server value formatted per the app's currency/date conventions