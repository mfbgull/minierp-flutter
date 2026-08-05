# Database Schema

> **Note:** this document describes the schema at an earlier point in the project's history. The authoritative, machine-exact current state is `server-reference/CURRENT_SCHEMA.sql` (59 tables — includes `employees`, `employee_documents`, `item_locations`, `conversations`).

MiniERP uses SQLite with WAL (Write-Ahead Logging) mode. The database file is located at `./database/erp.db`.

Schema is initialized on first startup and migrations run automatically in `server/src/config/database.ts`.

## Entity Relationship Overview

```
users ----< activity_log
  |
  +----< stock_movements
  +----< purchase_orders ----< purchase_order_items
  |         |
  |         +----< goods_receipts ----< goods_receipt_items
  |
  +----< invoices ----< invoice_items
  |         |
  |         +----< payment_allocations >---- payments
  |
  +----< productions ----< production_inputs

customers ----< invoices
    |
    +----< payments
    +----< customer_ledger

suppliers ----< purchase_orders
    |
    +----< supplier_ledger

items ----< stock_movements
  |     +----< stock_balances (per warehouse)
  |     +----< invoice_items
  |     +----< purchase_order_items
  |     +----< bom_items
  |     +----< production_inputs
  |
  +----< boms (as finished item)

warehouses ----< stock_movements
    |
    +----< stock_balances
    +----< purchase_orders
    +----< goods_receipts
```

## Core Tables

### users
System users for authentication and audit trail.

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| username | VARCHAR(50) UNIQUE | Login username |
| email | VARCHAR(100) UNIQUE | Email address |
| password_hash | VARCHAR(255) | bcrypt hash (12 rounds) |
| full_name | VARCHAR(100) | Display name |
| role | VARCHAR(20) | `admin` or `user` |
| is_active | BOOLEAN | Soft delete flag |
| created_at | DATETIME | Auto-set |
| updated_at | DATETIME | Auto-set |

### settings
Key-value store for system configuration and document number sequences.

| Column | Type | Description |
|---|---|---|
| key | VARCHAR(50) PK | Setting identifier |
| value | TEXT | Setting value |
| description | TEXT | Human-readable description |
| updated_at | DATETIME | Last modified |

---

## Inventory Module

### items
Product and material master data.

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| item_code | VARCHAR(50) UNIQUE | Item identifier (e.g., ITM001) |
| item_name | VARCHAR(200) | Display name |
| description | TEXT | Detailed description |
| category | VARCHAR(100) | Category grouping |
| unit_of_measure | VARCHAR(20) | Nos, Kg, Ltr, Box, etc. |
| current_stock | DECIMAL(15,3) | Computed total across warehouses |
| reorder_level | DECIMAL(15,3) | Low stock threshold |
| standard_cost | DECIMAL(15,2) | Purchase/manufacturing cost |
| standard_selling_price | DECIMAL(15,2) | Default selling price |
| is_raw_material | BOOLEAN | Used in manufacturing |
| is_finished_good | BOOLEAN | Produced by manufacturing |
| is_purchased | BOOLEAN | Procured externally |
| is_manufactured | BOOLEAN | Produced internally |
| is_active | BOOLEAN | Soft delete |
| created_by | INTEGER FK | References users(id) |

### warehouses
Storage locations.

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| warehouse_code | VARCHAR(50) UNIQUE | Code (e.g., WH-001) |
| warehouse_name | VARCHAR(100) | Display name |
| location | TEXT | Physical location |
| is_active | BOOLEAN | Active flag |

### stock_movements
Every stock in/out event. Positive quantity = stock in, negative = stock out.

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| movement_no | VARCHAR(50) UNIQUE | Auto-generated (STK-YYYY-NNNN) |
| item_id | INTEGER FK | References items(id) |
| warehouse_id | INTEGER FK | References warehouses(id) |
| movement_type | VARCHAR(50) | PURCHASE, SALE, TRANSFER, PRODUCTION, ADJUSTMENT |
| quantity | DECIMAL(15,3) | Positive=in, Negative=out |
| unit_cost | DECIMAL(15,2) | Cost per unit |
| reference_doctype | VARCHAR(50) | Source document type |
| reference_docno | VARCHAR(50) | Source document number |
| remarks | TEXT | Notes |
| movement_date | DATE | Date of movement |
| created_by | INTEGER FK | References users(id) |

### stock_balances
Current stock per item per warehouse. Updated on every stock movement.

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| item_id | INTEGER FK | References items(id) |
| warehouse_id | INTEGER FK | References warehouses(id) |
| quantity | DECIMAL(15,3) | Current balance |
| last_updated | DATETIME | Last change timestamp |

**Unique constraint:** `(item_id, warehouse_id)`

---

## Purchasing Module

### suppliers

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| supplier_code | VARCHAR(50) UNIQUE | Code (e.g., SUP0001) |
| supplier_name | VARCHAR(200) | Display name |
| contact_person | VARCHAR(100) | Contact name |
| email | VARCHAR(100) | Email |
| phone | VARCHAR(20) | Phone |
| address | TEXT | Address |
| payment_terms | VARCHAR(100) | Net 30, COD, etc. |
| is_active | BOOLEAN | Active flag |

### purchase_orders
PO header with lifecycle statuses.

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| po_no | VARCHAR(50) UNIQUE | PO number |
| supplier_id | INTEGER FK | References suppliers(id) |
| po_date | DATE | Order date |
| expected_delivery_date | DATE | Expected delivery |
| status | VARCHAR(20) | Draft, Submitted, Partially Received, Completed, Cancelled |
| total_amount | DECIMAL(15,2) | Total PO value |
| notes | TEXT | Notes |
| warehouse_id | INTEGER FK | Default receiving warehouse |
| created_by | INTEGER FK | References users(id) |

### purchase_order_items

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| po_id | INTEGER FK | References purchase_orders(id) CASCADE |
| item_id | INTEGER FK | References items(id) |
| quantity | DECIMAL(15,3) | Ordered quantity |
| received_quantity | DECIMAL(15,3) | Received so far |
| unit_price | DECIMAL(15,2) | Unit cost |
| amount | DECIMAL(15,2) | Line total |

### goods_receipts / goods_receipt_items
Track actual receipt of goods against POs.

---

## Sales Module

### customers

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| customer_code | VARCHAR(50) UNIQUE | Code (e.g., CUST001) |
| customer_name | VARCHAR(200) | Display name |
| contact_person | VARCHAR(100) | Contact name |
| email | VARCHAR(100) | Email |
| phone | VARCHAR(20) | Phone |
| billing_address | TEXT | Billing address |
| shipping_address | TEXT | Shipping address |
| payment_terms | VARCHAR(100) | Payment terms |
| credit_limit | DECIMAL(15,2) | Credit limit |
| current_balance | DECIMAL(15,2) | Outstanding AR balance |
| opening_balance | DECIMAL(15,2) | Opening balance |
| payment_terms_days | INTEGER | Days until due (default: 14) |
| is_active | BOOLEAN | Active flag |

### invoices

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| invoice_no | VARCHAR(50) | Invoice number |
| customer_id | INTEGER FK | References customers(id) |
| invoice_date | DATE | Invoice date |
| due_date | DATE | Payment due date |
| status | VARCHAR(20) | Unpaid, Partially Paid, Paid, Overdue |
| total_amount | DECIMAL(15,2) | Invoice total |
| paid_amount | DECIMAL(15,2) | Amount paid so far |
| balance_amount | DECIMAL(15,2) | Remaining balance |
| discount_scope | VARCHAR(20) | invoice or item |
| discount_type | VARCHAR(20) | percentage or fixed |
| discount_value | DECIMAL(15,2) | Discount amount/percent |
| notes | TEXT | Invoice notes |
| terms | TEXT | Payment terms text |
| created_by | INTEGER FK | References users(id) |

### invoice_items

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| invoice_id | INTEGER FK | References invoices(id) |
| item_id | INTEGER FK | References items(id) |
| quantity | DECIMAL(15,3) | Quantity sold |
| unit_price | DECIMAL(15,2) | Unit price |
| amount | DECIMAL(15,2) | Line total |
| tax_rate | DECIMAL(5,2) | Tax percentage |
| discount_type | VARCHAR(20) | percentage or fixed |
| discount_value | DECIMAL(15,2) | Line discount |

### payments

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| payment_no | VARCHAR(50) | Auto-generated (PAY001, PAY002...) |
| customer_id | INTEGER FK | References customers(id) |
| payment_date | DATE | Payment date |
| amount | DECIMAL(15,2) | Total payment amount |
| payment_method | VARCHAR(50) | Cash, Check, Bank Transfer, Card |
| reference_no | VARCHAR(100) | External reference |
| notes | TEXT | Notes |

### payment_allocations
Maps payments to invoices (many-to-many).

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| payment_id | INTEGER FK | References payments(id) |
| invoice_id | INTEGER FK | References invoices(id) |
| amount | DECIMAL(15,2) | Amount allocated |

### customer_ledger
Running transaction ledger for AR management.

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| customer_id | INTEGER FK | References customers(id) |
| transaction_date | DATE | Transaction date |
| transaction_type | VARCHAR(50) | INVOICE, PAYMENT, ADJUSTMENT |
| reference_no | VARCHAR(50) | Document reference |
| debit | DECIMAL(15,2) | AR increase |
| credit | DECIMAL(15,2) | AR decrease |
| balance | DECIMAL(15,2) | Running balance |
| description | TEXT | Transaction description |

---

## Manufacturing Module

### boms (Bill of Materials)

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| bom_name | VARCHAR(200) | BOM name |
| finished_item_id | INTEGER FK | Output item |
| output_quantity | DECIMAL(15,3) | Quantity produced per batch |
| is_active | BOOLEAN | Active flag |

### bom_items

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| bom_id | INTEGER FK | References boms(id) CASCADE |
| item_id | INTEGER FK | Raw material item |
| quantity | DECIMAL(15,3) | Required quantity per batch |

### productions

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| production_no | VARCHAR(50) UNIQUE | Auto-generated (PROD-YYYY-NNNN) |
| output_item_id | INTEGER FK | Finished goods item |
| output_quantity | DECIMAL(15,3) | Quantity produced |
| warehouse_id | INTEGER FK | Finished goods warehouse |
| raw_materials_warehouse_id | INTEGER FK | Raw materials warehouse |
| production_date | DATE | Production date |
| bom_id | INTEGER FK | References boms(id) |
| remarks | TEXT | Notes |
| created_by | INTEGER FK | References users(id) |

### production_inputs

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| production_id | INTEGER FK | References productions(id) |
| item_id | INTEGER FK | Raw material consumed |
| quantity | DECIMAL(15,3) | Quantity consumed |
| warehouse_id | INTEGER FK | Source warehouse |

---

## Other Tables

### expenses

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| expense_no | VARCHAR(50) | Expense reference |
| category_id | INTEGER FK | References expense_categories(id) |
| amount | DECIMAL(15,2) | Expense amount |
| expense_date | DATE | Date of expense |
| payment_method | VARCHAR(50) | Cash, Card, Bank Transfer |
| description | TEXT | Details |
| status | VARCHAR(20) | Pending, Approved, Rejected |
| created_by | INTEGER FK | References users(id) |

### expense_categories
15 default categories: Office Supplies, Travel, Utilities, Rent, Salaries, Marketing, Maintenance, Insurance, Taxes, Professional Services, Training, Equipment, Fuel, Meals, Other.

### activity_log
Audit trail for all system actions.

| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| user_id | INTEGER FK | References users(id) |
| action | VARCHAR(100) | CREATE, UPDATE, DELETE, LOGIN, etc. |
| entity_type | VARCHAR(100) | Item, Invoice, Payment, etc. |
| entity_id | INTEGER | ID of affected entity |
| description | TEXT | Human-readable description |
| log_level | VARCHAR(20) | INFO, WARN, ERROR |
| ip_address | VARCHAR(45) | Client IP |
| user_agent | TEXT | Browser/client info |
| metadata | TEXT | JSON additional data |
| duration_ms | INTEGER | Operation duration |
| created_at | DATETIME | Timestamp |

### supplier_ledger
AP transaction ledger for suppliers (mirrors customer_ledger structure).

### invoice_drafts
Temporary storage for mobile invoice wizard drafts (JSON items, 7-day expiry).

### tax_rates
Configurable tax rates (defaults: GST 5%, GST 10%, GST 15%, VAT 20%).

### payment_terms
Configurable payment terms (defaults: Due on Receipt, Net 7, Net 14, Net 21, Net 30).

---

## Indexes

Performance indexes are defined in `server/src/migrations/add-performance-indexes.sql` and `add-missing-indexes.sql`. Key indexes:

- `idx_invoices_customer_id`, `idx_invoices_status`, `idx_invoices_date`, `idx_invoices_due_date`
- `idx_payments_customer_id`, `idx_payments_date`
- `idx_payment_allocations_payment`, `idx_payment_allocations_invoice`
- `idx_stock_movements_item_warehouse`, `idx_stock_movements_date`
- `idx_customer_ledger_customer_id`, `idx_customer_ledger_reference`
- `idx_activity_log_created_at`, `idx_activity_log_entity`
- `idx_items_category`, `idx_items_item_code`
- `idx_customers_code`, `idx_customers_name`

---

## Document Number Generation

All document numbers use atomic generation via `INSERT ... ON CONFLICT DO UPDATE` to prevent race conditions:

| Document | Pattern | Settings Key |
|---|---|---|
| Stock Movement | STK-YYYY-NNNN | `STK_last_no_YYYY` |
| Production | PROD-YYYY-NNNN | `PROD_last_no_YYYY` |
| Sale | SALE-YYYY-NNNN | `SALE_last_no_YYYY` |
| Payment | PAY001, PAY002... | `PAY_last_no` |
