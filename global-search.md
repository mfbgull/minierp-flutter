# Global Entity-Aware Search and Command Palette

Implement a complete **Global Search / Command Palette** for the ERP application.

## Tech Stack

* Backend: Node.js
* API: Express
* Database: SQLite
* SQLite driver: `better-sqlite3`
* Frontend: Flutter
* Existing ERP architecture and conventions must be preserved.
* Before making changes, inspect the existing backend routes, database schema, Flutter navigation, models, repositories/services, and UI patterns.

Do not rewrite existing architecture unnecessarily.

---

# 1. Feature Objective

Create a global search that allows the user to search for:

* Customers
* Suppliers
* Products / Items
* Sales invoices
* Purchase invoices
* Quotations
* Purchase orders
* Payments
* Expenses
* Warehouses
* Other important ERP entities already present in the database
* Application pages/modules/actions

The search must NOT behave like a simple navigation search.

It must search the actual database and understand **what type of entity the result represents**.

For example, when the user searches:

`Ali`

the system might return:

```text
CUSTOMERS

Ali Khan
Customer · Balance: Rs. 12,500

Actions:
→ Open Customer
→ Create Invoice
→ Receive Payment
→ View Ledger
→ View Sales History
```

If the same search matches a product:

```text
PRODUCTS

Ali Soap 100g
Stock: 42 · Sale Price: Rs. 85

Actions:
→ Open Product
→ Create Sale
→ Create Purchase
→ Adjust Stock
→ View Stock Movements
```

If it matches a supplier:

```text
SUPPLIERS

Ali Traders
Payable: Rs. 35,000

Actions:
→ Open Supplier
→ Create Purchase
→ Make Payment
→ View Ledger
→ View Purchase History
```

The system should therefore provide:

**Search → Identify Entity → Show Context → Show Relevant Actions**

---

# 2. UX Requirements

Add a global search entry point accessible from the main application shell.

Prefer:

* Keyboard shortcut such as `Ctrl + K` where applicable
* Search icon/button in the application header
* Flutter-friendly global search overlay/dialog
* Search should be accessible from all major screens

When opened, display:

```text
Search customers, suppliers, products, invoices...
```

As the user types, search results should update.

Do not require the user to first select a category.

The search should automatically determine relevant categories.

---

# 3. Search Result Structure

Every search result must have a consistent structure.

Conceptually:

```text
SearchResult

- type
- id
- title
- subtitle
- metadata
- score/relevance
- actions[]
```

Example:

```json
{
  "type": "customer",
  "id": 124,
  "title": "Ali Khan",
  "subtitle": "Customer",
  "metadata": {
    "balance": 12500
  },
  "actions": [
    "open",
    "create_invoice",
    "receive_payment",
    "ledger",
    "sales_history"
  ]
}
```

Do not tightly couple the Flutter UI to database table names.

The API should expose business/entity types such as:

* `customer`
* `supplier`
* `product`
* `sales_invoice`
* `purchase_invoice`
* `quotation`
* `purchase_order`
* `payment`
* `expense`
* `warehouse`

rather than raw SQLite table names.

---

# 4. Search API

Create an appropriate Express endpoint, for example:

```text
GET /api/search?q=ali
```

Use the project's existing API naming conventions if they differ.

Optional parameters may include:

```text
q
limit
```

For example:

```text
GET /api/search?q=ali&limit=30
```

The endpoint should return structured search results.

Example:

```json
{
  "query": "ali",
  "results": [
    {
      "type": "customer",
      "id": 124,
      "title": "Ali Khan",
      "subtitle": "Customer",
      "metadata": {
        "balance": 12500
      },
      "actions": [
        {
          "id": "open",
          "label": "Open Customer"
        },
        {
          "id": "create_invoice",
          "label": "Create Invoice"
        },
        {
          "id": "receive_payment",
          "label": "Receive Payment"
        },
        {
          "id": "ledger",
          "label": "View Ledger"
        }
      ]
    }
  ]
}
```

Use the project's existing response/error conventions.

---

# 5. Backend Search Implementation

Use `better-sqlite3`.

Do NOT load entire tables into Node.js and perform the search in JavaScript.

Search should be performed by SQLite.

Use parameterized queries.

Never concatenate raw user input directly into SQL.

For example:

```sql
WHERE name LIKE ?
```

with:

```text
%ali%
```

Use the existing database connection and repository/data-access architecture.

Do not create a second database connection system if one already exists.

---

# 6. What Fields Should Be Searchable

Inspect the actual database schema first.

Do not assume column names.

For customers, search relevant fields such as:

* Name
* Phone
* Code
* Email
* Customer number

For suppliers:

* Name
* Phone
* Code
* Email
* Supplier number

For products/items:

* Name
* SKU
* Barcode
* Item code
* Product code

For invoices:

* Invoice number
* Customer name
* Supplier name
* Reference number

For quotations:

* Quotation number
* Customer name

For purchase orders:

* PO number
* Supplier name

For warehouses:

* Warehouse name
* Warehouse code

Only search fields that actually exist.

---

# 7. Relevance Ranking

Do not simply return random matching rows.

Results should be ranked by relevance.

Suggested priority:

1. Exact name/code match
2. Name/code starts with query
3. Name/code contains query
4. Secondary field match
5. Related entity match

For example, searching:

```text
ali
```

should preferably show:

```text
Ali Khan
```

before:

```text
Muhammad Ali Traders
```

and both should appear before a weak match where `ali` occurs in an unrelated field.

If practical with the existing SQLite setup, use SQLite FTS for large datasets.

However, **do not introduce FTS unnecessarily** if the ERP database is small and normal indexed `LIKE` queries are sufficient.

---

# 8. Search Categories

Group results in the API or Flutter UI.

Suggested order:

```text
CUSTOMERS
SUPPLIERS
PRODUCTS
SALES INVOICES
PURCHASE INVOICES
QUOTATIONS
PURCHASE ORDERS
OTHER
PAGES & ACTIONS
```

Do not display empty categories.

For example, if there are no suppliers matching the query, do not show:

```text
SUPPLIERS
No results
```

Simply omit that section.

---

# 9. Entity-Specific Actions

This is one of the most important requirements.

Actions must depend on the entity type.

## Customer

Possible actions:

```text
Open Customer
Create Sales Invoice
Receive Payment
View Customer Ledger
View Sales History
```

Only expose actions that are actually supported by the existing application.

## Supplier

Possible actions:

```text
Open Supplier
Create Purchase
Make Payment
View Supplier Ledger
View Purchase History
```

## Product / Item

Possible actions:

```text
Open Product
Create Sale
Create Purchase
Adjust Stock
View Stock
View Stock Movements
```

## Sales Invoice

Possible actions:

```text
Open Invoice
Edit Invoice
Return Items
Record Payment
Print Invoice
```

Only show Edit/Return/etc. when the current business rules permit them.

For example, if an invoice cannot be edited after certain status/payment conditions, do not expose an invalid action.

## Purchase Invoice

Possible actions:

```text
Open Purchase
Edit Purchase
Return Items
Record Payment
Print
```

Again, obey existing business rules.

## Warehouse

Possible actions:

```text
Open Warehouse
View Stock
View Stock Movements
```

---

# 10. Action Architecture

Do not hard-code navigation logic throughout the search widget.

Create a clean action model.

Conceptually:

```text
SearchResult
    ↓
Entity Type
    ↓
Available Actions
    ↓
Flutter Action Handler
    ↓
Existing Screen / Route
```

For example:

```text
customer
    open
    create_invoice
    receive_payment
    ledger
```

The Flutter application should map these action IDs to existing application routes/screens.

Example concept:

```text
customer + open
    → CustomerDetailScreen(customerId)

customer + create_invoice
    → SalesInvoiceScreen(customerId: ...)

customer + receive_payment
    → ReceivePaymentScreen(customerId: ...)

customer + ledger
    → CustomerLedgerScreen(customerId: ...)
```

Use the existing navigation architecture rather than introducing a new navigation system.

---

# 11. Context Passing

When an action is selected, pass the relevant entity ID.

Example:

Searching:

```text
Ali Khan
Customer ID: 124
```

Selecting:

```text
Create Invoice
```

should open the existing invoice creation screen with:

```text
customerId = 124
```

The customer should already be selected if the existing invoice screen supports this.

Similarly:

```text
Product ID: 55
```

→ Create Sale

should open the sale/POS screen with that product available or selected according to the application's existing workflow.

Do not duplicate business logic in the search feature.

---

# 12. Navigation / Pages Search

The global search should also search application navigation.

For example, searching:

```text
invoice
```

could return:

```text
PAGES

Sales Invoices
Purchase Invoices
Invoice Returns
```

and:

```text
ACTIONS

Create Sales Invoice
Create Purchase
```

These are not database entities.

They are application commands/navigation targets.

Create a small searchable registry of available pages/actions based on the existing application routes.

Do not make the database responsible for page search.

---

# 13. Combined Search Example

If the user searches:

```text
ali
```

the result could look like:

```text
CUSTOMERS

Ali Khan
Customer · Balance: Rs. 12,500

  Open Customer
  Create Invoice
  Receive Payment
  View Ledger


SUPPLIERS

Ali Traders
Supplier · Payable: Rs. 35,000

  Open Supplier
  Create Purchase
  Make Payment
  View Ledger


PRODUCTS

Ali Soap 100g
Stock: 42 · Sale Price: Rs. 85

  Open Product
  Create Sale
  Adjust Stock
  View Stock
```

The user should not have to navigate manually through:

```text
Customers → Ali Khan → Actions
```

The global search should provide the shortcut.

---

# 14. Flutter UI

Create a reusable global search component.

Suggested structure:

```text
GlobalSearchButton
        ↓
GlobalSearchDialog / Overlay
        ↓
SearchField
        ↓
SearchResults
        ↓
SearchResultGroup
        ↓
SearchResultTile
        ↓
ActionMenu
```

The UI should support:

* Search input
* Loading state
* Empty state
* Error state
* Grouped results
* Entity icons
* Entity type labels
* Important metadata
* Available actions
* Keyboard navigation where supported
* Mouse/touch interaction
* Debounced API requests

Do not make an API request for every single keystroke.

Use a small debounce, approximately:

```text
200–300 ms
```

Cancel/ignore stale requests when the user continues typing.

---

# 15. Empty Search

When the search box is empty, show useful shortcuts instead of querying the entire database.

For example:

```text
Quick Actions

Create Sales Invoice
Create Purchase
Add Customer
Add Supplier
Add Product
Receive Payment
Make Payment
```

Also optionally show:

```text
Recent

Recently viewed customers
Recently opened invoices
Recently used actions
```

Only implement Recent if it fits the existing architecture cleanly.

---

# 16. Minimum Query Length

Do not perform database searches for extremely short queries unless useful.

Recommended:

```text
minimum 2 characters
```

For example:

```text
a
```

should not search the whole database.

But:

```text
al
```

can search.

Allow exact barcode/SKU searches to work efficiently even if they require special handling.

---

# 17. Performance

The search must remain fast with a growing ERP database.

Requirements:

* Use parameterized SQLite queries.
* Use appropriate indexes on searchable fields.
* Do not retrieve unnecessary columns.
* Apply a reasonable result limit.
* Do not return hundreds of results.
* Keep API response small.
* Use debounce on Flutter.
* Avoid N+1 database queries.
* Do not execute one query per result to construct metadata.

Use a reasonable default such as:

```text
30 total results
```

or an appropriate grouped limit based on the existing application.

---

# 18. Security and Permissions

The global search must respect the existing authentication and authorization system.

Do not expose:

* Records the current user is not allowed to access
* Sensitive information from restricted modules
* Actions the current user is not permitted to perform

For example, if a user cannot access financial reports, the global search must not expose those pages/actions.

Likewise, if the existing system has role-based permissions for:

* Customers
* Suppliers
* Sales
* Purchases
* Payments
* Inventory

respect those permissions.

Do not create a parallel permission system.

Use the application's existing authorization mechanism.

---

# 19. Business Rules

The search feature must NOT bypass existing ERP business rules.

For example:

If an invoice is:

```text
Paid
```

that does not automatically mean the user can edit it.

The search result should expose only valid actions according to the existing invoice rules.

Similarly:

* Returned invoices
* Cancelled invoices
* Draft purchases
* Closed transactions
* Restricted records

must follow existing rules.

The global search is an entry point into existing functionality, not a replacement for business validation.

---

# 20. Error Handling

Handle:

* Network failure
* Database failure
* Empty results
* Invalid query
* Unauthorized action
* Deleted record between search and action
* Stale search response

Example:

If the user searches for a customer and then the customer is deleted before selecting an action, show an appropriate error instead of crashing.

---

# 21. Search Result Icons

Use consistent icons based on entity type.

For example:

```text
Customer       person
Supplier       business
Product        inventory
Invoice        receipt
Payment        payments
Warehouse      warehouse
Expense        money
Page           navigation
Action         bolt/play/action icon
```

Use the application's existing icon library/style.

Do not introduce a visually inconsistent icon system.

---

# 22. Search Result Interaction

Recommended interaction:

```text
Search
  ↓
Select result
  ↓
Show available actions
```

Example:

```text
Ali Khan
Customer · Rs. 12,500 due
```

Selecting the result should reveal:

```text
Open Customer
Create Invoice
Receive Payment
View Ledger
View Sales History
```

Alternatively, actions can be visible directly beneath the result if this fits the existing UI better.

Choose the UX that feels natural within the existing Flutter application.

---

# 23. Do Not Duplicate Screens

The global search should navigate to existing screens.

Do NOT create:

```text
GlobalCustomerDetailScreen
GlobalInvoiceScreen
GlobalPaymentScreen
```

if equivalent screens already exist.

Instead:

```text
Global Search
    ↓
Existing Customer Detail
Existing Invoice Creation
Existing Payment Screen
Existing Ledger
```

This is important for maintainability.

---

# 24. Backend Architecture

Before implementation, inspect the existing project and determine where the following belong:

```text
search routes
search controller
search service
database queries/repositories
entity/action definitions
```

Follow the project's current architecture.

If the project already has:

```text
routes/
controllers/
services/
repositories/
```

use them.

Do not introduce a completely different architecture.

---

# 25. Database Indexes

Inspect existing indexes.

Add indexes only where they materially improve search performance.

Potential indexes may include:

```text
customer name
customer phone
customer code

supplier name
supplier phone
supplier code

product name
product SKU
product barcode

invoice number
```

Use SQLite-compatible indexes.

Do not blindly create indexes on every column.

---

# 26. API Design Should Be Extensible

Design the response so new entities can be added later.

For example:

```text
SearchResult
```

should be generic enough that later we can add:

```text
employee
expense
quotation
purchase_order
stock_adjustment
```

without redesigning the Flutter search UI.

The Flutter UI should primarily care about:

```text
type
title
subtitle
metadata
actions
```

rather than knowing every database implementation detail.

---

# 27. Testing

Add tests for backend search functionality.

At minimum test:

### Customer

```text
Search customer by name
Search customer by phone
Search customer by code
```

### Supplier

```text
Search supplier by name
Search supplier by phone
```

### Product

```text
Search product by name
Search product by SKU
Search product by barcode
```

### Invoice

```text
Search invoice number
Search customer associated with invoice
```

### Ranking

Verify exact/strong matches appear before weaker matches.

### Actions

Verify correct actions are returned for each entity type.

### Permissions

Verify unauthorized entities/actions are not exposed.

### Empty search

Verify no expensive database query occurs for an empty/too-short query.

---

# 28. Acceptance Criteria

The feature is complete only when all of the following work:

* [ ] Global search can be opened from the main application.
* [ ] User can search without first selecting an entity type.
* [ ] Search queries the actual SQLite database.
* [ ] Customers can be found.
* [ ] Suppliers can be found.
* [ ] Products/items can be found.
* [ ] Invoices can be found.
* [ ] Other important existing ERP entities are included where appropriate.
* [ ] Application pages/routes can also be searched.
* [ ] Results are grouped by entity type.
* [ ] Results contain useful metadata.
* [ ] Results expose entity-specific actions.
* [ ] Actions navigate to existing screens.
* [ ] Relevant entity IDs are passed to those screens.
* [ ] Existing business rules are respected.
* [ ] Existing permissions are respected.
* [ ] Search is debounced in Flutter.
* [ ] Database queries are parameterized.
* [ ] Search has reasonable result limits.
* [ ] Search does not load entire database tables.
* [ ] Loading, empty, error, and stale-result states are handled.
* [ ] Backend tests are added.
* [ ] Flutter code follows the existing project architecture.
* [ ] No duplicate business logic or duplicate screens are introduced.

---

# 29. Implementation Process

Before coding:

1. Inspect the complete project structure.
2. Inspect the SQLite schema.
3. Identify all relevant ERP entities.
4. Identify existing API patterns.
5. Identify existing Flutter navigation/routes.
6. Identify existing permission/authentication mechanisms.
7. Identify existing customer, supplier, product, invoice, payment and ledger screens.
8. Identify existing repository/service patterns.
9. Propose the implementation plan.

Then implement incrementally:

```text
Phase 1
Backend search infrastructure

Phase 2
Entity-specific database searches

Phase 3
Search result/action API

Phase 4
Flutter global search UI

Phase 5
Navigation/action integration

Phase 6
Permissions and business-rule integration

Phase 7
Performance optimization

Phase 8
Tests
```

After implementation, run the existing test suite and relevant application checks.

Fix any regressions caused by the implementation.

---

# Important Instructions to the AI Agent

Do NOT blindly start coding.

First inspect the existing codebase and database.

Do NOT assume table names, column names, routes, or screen names.

Do NOT rewrite existing architecture.

Do NOT create duplicate screens.

Do NOT bypass existing business rules.

Do NOT bypass existing permissions.

Do NOT use raw SQL string concatenation with user input.

Do NOT load entire database tables into memory for searching.

Do NOT introduce a complicated search engine or SQLite FTS unless the existing database size/architecture justifies it.

The final implementation should feel like a **native part of the existing ERP**, not a separate feature bolted onto it.

The primary goal is:

**One search box → find anything → understand what it is → immediately perform the relevant action.**

