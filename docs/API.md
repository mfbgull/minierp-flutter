# API Reference

Base URL: `http://localhost:3011/api`

All endpoints require authentication (JWT cookie) unless marked otherwise. Responses use JSON format.

## Authentication

### POST /auth/login
Login and receive JWT token as httpOnly cookie.

**Rate Limited:** 5 requests per 15 minutes per username.

> **Security note:** The credentials below are development defaults. Change in production.

```json
// Request
{ "username": "admin", "password": "admin123" }

// Response 200
{ "success": true, "data": { "user": { "id": 1, "username": "admin", "email": "admin@minierp.local", "full_name": "Administrator", "role": "admin" } } }
```

### POST /auth/logout
Clear JWT cookie.

### GET /auth/me
Get the current authenticated user.

### POST /auth/change-password
**Rate Limited:** 3 requests per hour.

```json
// Request
{ "currentPassword": "old", "newPassword": "newpass123" }
```

---

## Dashboard

### GET /dashboard/summary
Server-side aggregated dashboard data. Replaces 5 separate full-table fetches.

| Query Param | Type | Description |
|---|---|---|
| `fromDate` | string (YYYY-MM-DD) | Range start — filters the money figures (sales, purchases, profit), the sales/purchases chart and recent productions. Omit for all-time totals + 7-day chart. |
| `toDate` | string (YYYY-MM-DD) | Range end (inclusive). Requires `fromDate`. |

```json
// Response 200
{
  "success": true,
  "data": {
    "totalItems": 150,
    "totalStockValue": 245000.50,
    "totalSalesRevenue": 890000.00,
    "totalPurchases": 560000.00,
    "totalProfit": 330000.00,
    "warehouseStockCount": 312,
    "lowStockItems": [{ "id": 1, "item_code": "ITM001", "item_name": "Widget", "current_stock": 5, "reorder_level": 10, "category": "Parts" }],
    "stockByCategory": [{ "category": "Parts", "total_stock": 500 }],
    "salesByDay": [{ "date": "2026-02-20", "total": 15000 }],
    "purchasesByDay": [{ "date": "2026-02-20", "total": 8000 }],
    "recentProductions": 12
  }
}
```

### GET /dashboard/cash-position
Closing balance per cash account (Cash, Bank, Easypaisa, JazzCash,
UPaisa), plus each account's opening/inflow/outflow and the individual
transactions behind the balance. Revenue/profit figures elsewhere net
out fully-returned invoices.

```json
// Response 200
{
  "success": true,
  "data": {
    "date": "2026-08-13",
    "accounts": [{
      "key": "cash",
      "name": "Cash",
      "balance": -5050,
      "opening": -4350,
      "inflow": 0,
      "outflow": 700,
      "net": -700,
      "transactions": [{
        "date": "2026-08-13",
        "type": "refund",
        "reference": "PAY004",
        "description": "Refund for return on INV-2026-152278",
        "amount": -700
      }]
    }],
    "total": -4350
  }
}
```

`transactions[].type` is one of `payment_received` | `supplier_payment`
| `expense` | `salary` | `refund` (positive = money in, negative = out).

### GET /dashboard/cash-opening-balances
Starting (seed) balance each cash account was founded with — a new
business records its opening cash here; the cash-position strip seeds
from it.

```json
// Response 200
{ "success": true, "data": { "accounts": [
  { "key": "cash", "name": "Cash", "amount": 20000 }
] } }
```

### PUT /dashboard/cash-opening-balances
Save the opening balances. Body: `{ "accounts": [{ "key": "cash", "amount": 20000 }] }`.
Returns the saved accounts in the same envelope as GET.

### GET /dashboard/sales-summary
Sales totals for a period — the dashboard's Sales Summary block.

| Query Param | Type | Description |
|---|---|---|
| `period` | string | `today` (default) \| `week` \| `month` |

`period=week` returns the **calendar week** containing today, aligned to the
signed-in user's saved week-start day (`monday` \| `saturday` \| `sunday`,
default `monday` — see the Preferences section below): a saturday-starting
user sees the Saturday→Friday week, a monday-starting user the Monday→Sunday
week. When no user context is available it falls back to the rolling 7-day
window. `today` and `month` keep their existing rolling semantics.

```json
// Response 200
{ "success": true, "data": { "period_total": 890000.00, "count": 42 } }
```

### GET /dashboard/expense-summary
Expense totals for a period — same `period` param and week-start-aware `week`
behavior as sales-summary (default `month`). Returns the same `{ period_total,
count }` envelope.

---

## Customers

### GET /customers
List customers. Supports pagination, sorting, and search.

| Query Param | Type | Description |
|---|---|---|
| `page` | number | Page number (default: 1) |
| `limit` | number | Items per page (default: 10) |
| `search` | string | Search by name, code, email, phone |
| `sortBy` | string | Column to sort by |
| `sortOrder` | string | `ASC` or `DESC` |

### GET /customers/:id
Get a single customer.

### POST /customers
Create a customer.

```json
{ "customer_code": "CUST001", "customer_name": "Acme Corp", "email": "acme@example.com", "phone": "555-0100", "billing_address": "123 Main St", "payment_terms": "Net 30", "credit_limit": 50000, "opening_balance": 0 }
```

### PUT /customers/:id
Update a customer.

### DELETE /customers/:id
Delete a customer (fails if customer has invoices).

### GET /customers/:id/ledger
Get the customer's AR ledger (all debit/credit transactions with running balance).

### GET /customers/:id/statement
Get a formatted customer statement with opening/closing balance.

| Query Param | Type | Description |
|---|---|---|
| `from` | string | Start date (YYYY-MM-DD) |
| `to` | string | End date (YYYY-MM-DD) |

### GET /customers/:id/balance
Get the customer's current balance.

### POST /customers/recalculate-balances
Recalculate all customer balances from invoice data.

---

## Suppliers

### GET /suppliers
List all active suppliers.

### GET /suppliers/next-code
Get the next auto-generated supplier code (e.g., `SUP0005`).

### GET /suppliers/:id
Get a single supplier.

### POST /suppliers
Create a supplier.

```json
{ "supplier_code": "SUP0001", "supplier_name": "Parts Inc", "contact_person": "John", "email": "john@parts.com", "phone": "555-0200", "payment_terms": "Net 30" }
```

### PUT /suppliers/:id
Update a supplier.

### DELETE /suppliers/:id
Delete a supplier (fails if supplier has purchase orders).

---

## Inventory

### Items

| Method | Path | Description |
|---|---|---|
| GET | /inventory/items | List all items |
| GET | /inventory/items/:id | Get single item |
| POST | /inventory/items | Create item |
| PUT | /inventory/items/:id | Update item |
| DELETE | /inventory/items/:id | Delete item |
| GET | /inventory/items-categories | List distinct categories |
| GET | /inventory/items-low-stock | List items below reorder level |
| GET | /inventory/items-uom | List units of measure |

**Create Item:**
```json
{
  "item_code": "ITM001",
  "item_name": "Steel Rod 10mm",
  "category": "Raw Materials",
  "unit_of_measure": "Kg",
  "reorder_level": 100,
  "standard_cost": 25.50,
  "standard_selling_price": 35.00,
  "is_raw_material": true,
  "is_purchased": true
}
```

### Warehouses

| Method | Path | Description |
|---|---|---|
| GET | /inventory/warehouses | List warehouses |
| GET | /inventory/warehouses/:id | Get single warehouse |
| POST | /inventory/warehouses | Create warehouse |
| PUT | /inventory/warehouses/:id | Update warehouse |

### Stock

| Method | Path | Description |
|---|---|---|
| GET | /inventory/stock-movements | List stock movements (filterable) |
| POST | /inventory/stock-movements | Create manual stock movement |
| GET | /inventory/stock-summary | Aggregated stock summary |
| GET | /inventory/stock-ledger/:itemId | Item-level stock ledger |
| GET | /inventory/stock-balances | Stock balances by warehouse |

---

## Invoices

### GET /invoices
List invoices with optional filters.

| Query Param | Type | Description |
|---|---|---|
| `customerId` | number | Filter by customer |
| `status` | string | Comma-separated: `Unpaid,Partially Paid,Paid,Overdue` |

### GET /invoices/:id
Get invoice with items and customer details.

### POST /invoices
Create invoice. Optionally records payment in the same transaction.

```json
{
  "invoice_no": "INV-2026-0001",
  "customer_id": 1,
  "invoice_date": "2026-02-20",
  "due_date": "2026-03-20",
  "items": [
    { "item_id": 1, "quantity": 10, "unit_price": 35.00, "tax_rate": 5, "discount_type": "percentage", "discount_value": 0 }
  ],
  "total_amount": 367.50,
  "notes": "First order",
  "record_payment": true,
  "payment": {
    "amount": 100,
    "payment_date": "2026-02-20",
    "payment_method": "Cash"
  }
}
```

### PUT /invoices/:id
Update invoice. Reverses old stock movements and creates new ones.

### DELETE /invoices/:id
**Admin only.** Delete invoice, reverse stock, clean up payments and ledger.

### GET /invoices/:id/payments
Get all payments allocated to an invoice.

### POST /invoices/:id/return
Process a customer return — reverses the sale's stock (restocked into the
`warehouse_id` when provided, otherwise the warehouse the sale was dispatched
from), posts the GL/ledger reversal and applies the disposition.

```json
{
  "reason": "Damaged goods",
  "disposition": "credit",        // "refund" | "credit" | "adjust"
  "warehouse_id": 1,              // optional restock target
  "items": [
    { "invoice_item_id": 10, "return_quantity": 2 }
  ]
}
```

### GET /invoices/returns
List invoice-return history (paginated).

---

## Payments

### GET /payments
List payments (paginated, sortable, searchable).

### GET /payments/:id
Get single payment with allocations.

### POST /payments
Create payment with allocations. Customer payments allocate across
`invoice_allocations`; supplier payments allocate across
`po_allocations` (purchase orders) and/or `purchase_allocations`
(direct purchases) — a supplier payment must carry at least one
allocation of either kind, and each line amount is validated against
that document's remaining balance.

```json
{
  "customer_id": 1,
  "payment_date": "2026-02-20",
  "amount": 500,
  "payment_method": "Bank Transfer",
  "reference_no": "TXN-12345",
  "invoice_allocations": [
    { "invoice_id": 1, "amount": 300 },
    { "invoice_id": 2, "amount": 200 }
  ]
}
```

Supplier payment against a direct purchase:

```json
{
  "supplier_id": 3,
  "payment_date": "2026-08-06",
  "amount": 250,
  "payment_method": "Cash",
  "purchase_allocations": [
    { "purchase_id": 12, "amount": 250 }
  ]
}
```

### PUT /payments/:id
Update payment.

### DELETE /payments/:id
**Admin only.** Delete payment and reverse allocations.

### POST /payments/:id/allocate
Allocate an existing payment to invoices.

---

## Purchase Orders

| Method | Path | Description |
|---|---|---|
| GET | /purchase-orders | List purchase orders |
| GET | /purchase-orders/:id | Get PO with items |
| GET | /purchase-orders/:id/payments | Get payments allocated to the PO |
| POST | /purchase-orders | Create PO |
| PUT | /purchase-orders/:id | Update PO |
| DELETE | /purchase-orders/:id | Delete PO |
| POST | /purchase-orders/:id/items | Add line item |
| PUT | /purchase-orders/:id/items/:itemId | Update line item |
| DELETE | /purchase-orders/:id/items/:itemId | Delete line item |
| POST | /purchase-orders/:id/status | Update PO status |
| GET | /purchase-orders/pending | List pending POs |
| GET | /purchase-orders/:id/receipts | Get goods receipts |
| POST | /purchase-orders/:id/receipts | Create goods receipt |

---

## Direct Purchases

| Method | Path | Description |
|---|---|---|
| POST | /purchases | Record a direct purchase |
| GET | /purchases | List purchases |
| GET | /purchases/:id | Get single purchase |
| GET | /purchases/:id/payments | Get payments allocated to the purchase |
| DELETE | /purchases/:id | Delete purchase |
| GET | /purchases/summary/item/:item_id | Purchase summary by item |
| GET | /purchases/summary/daterange | Purchase summary by date range |
| GET | /purchases/top-suppliers | Top suppliers report |

`POST /purchases` accepts an optional `supplier_id` — when provided the
server resolves the supplier name, links the purchase, and posts the AP
supplier-ledger entry (debit) so the purchase can be paid via
`POST /payments` with `purchase_allocations`. `invoice_no` / `remarks`
are also accepted.

```json
{
  "item_id": 4,
  "warehouse_id": 1,
  "quantity": 10,
  "unit_cost": 25,
  "purchase_date": "2026-08-06",
  "supplier_id": 3,
  "invoice_no": "SUP-2026-881",
  "remarks": "Rush order"
}
```

`GET /purchases/:id/payments` returns the payment history for one
purchase (`payment_no`, `payment_date`, `payment_method`, `reference_no`,
`notes`, per-purchase `amount`) — the same row shape as the invoice
payments endpoint. `GET /purchase-orders/:id/payments` is the PO
analogue (`po_allocations`).

Both `GET /purchases` and `GET /purchases/:id` rows also carry
`paid_amount` / `balance_amount` (allocated from `purchase_allocations`),
and the list accepts `sortBy=paid_amount` / `balance_amount`.

---

## Purchase Returns

First-class purchase return documents (`purchase_returns` header + lines) with
full reversal on void. A return reduces stock from the **source document's
warehouse** (the form never asks). The old `POST /purchases/:id/return`,
`POST /purchase-orders/:id/return-receipt` and `GET /purchases/returns`
endpoints were removed with the redesign.

| Method | Path | Description |
|---|---|---|
| GET | /purchase-returns | List return headers (paginated; `search`, `status`, `start_date`, `end_date`, `type`, `warehouse_id`) |
| GET | /purchase-returns/:id | Get one return (header + items) |
| POST | /purchase-returns | Create a return |
| POST | /purchase-returns/:id/void | Void a return (full reversal: stock, GL, credit note) |

`POST /purchase-returns` body — `source_type` is `PURCHASE` (a direct
purchase) or `PURCHASE_ORDER`; each line's `source_item_id` is the source
line id (`purchases.id` or `purchase_order_items.id`).

```json
{
  "return_date": "2026-08-05",
  "source_type": "PURCHASE",
  "source_id": 12,
  "warehouse_id": 1,
  "reason": "Damaged on delivery",
  "items": [
    { "source_item_id": 12, "quantity": 4 }
  ]
}
```

`POST /purchase-returns/:id/void` body: `{ "reason": "..." }` (optional). The
server rejects (400) returns that are not `POSTED`.

---

## Sales

| Method | Path | Description |
|---|---|---|
| GET | /sales/summary/item/:item_id | Sales summary by item |
| GET | /sales/summary/daterange | Sales summary by date range |
| GET | /sales/top-customers | Top customers report |
| GET | /sales/item-customer-history | Item-customer price history |
| GET | /sales/:id | Get single sale |
| DELETE | /sales/:id | Delete sale |

---

## BOM (Bill of Materials)

| Method | Path | Description |
|---|---|---|
| GET | /boms | List all BOMs |
| GET | /boms/:id | Get BOM with items |
| GET | /boms/by-item/:itemId | Get BOMs for a finished item |
| POST | /boms | Create BOM |
| PUT | /boms/:id | Update BOM |
| PATCH | /boms/:id/toggle-active | Toggle active status |
| DELETE | /boms/:id | Delete BOM |

---

## Production

| Method | Path | Description |
|---|---|---|
| POST | /productions | Record production run |
| GET | /productions | List productions |
| GET | /productions/:id | Get production with inputs |
| DELETE | /productions/:id | Delete production |
| GET | /productions/summary/item/:item_id | Production summary by item |

---

## Expenses

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | /expenses/categories | No | List expense categories |
| GET | /expenses/status-options | No | Get status options |
| GET | /expenses/payment-method-options | No | Get payment method options |
| POST | /expenses | Yes | Create expense |
| GET | /expenses | Yes | List expenses |
| GET | /expenses/summary | Yes | Expense summary |
| GET | /expenses/date-range | Yes | Expenses by date range |
| GET | /expenses/category/:category | Yes | Expenses by category |
| GET | /expenses/:id | Yes | Get single expense |
| PUT | /expenses/:id | Yes | Update expense |
| DELETE | /expenses/:id | Yes | Delete expense |
| POST | /expenses/categories | Yes | Create category |
| PUT | /expenses/categories/:id | Yes | Update category |
| DELETE | /expenses/categories/:id | Yes | Delete category |

---

## POS (Point of Sale)

| Method | Path | Description |
|---|---|---|
| POST | /pos/sale | Create POS sale |
| GET | /pos/transactions | List POS transactions |

---

## Reports

All report endpoints require authentication. Financial reports are additionally rate-limited (10/min).

| Method | Path | Rate Limited | Description |
|---|---|---|---|
| GET | /reports/ar-aging | Yes | Accounts Receivable aging |
| GET | /reports/customer-statements | Yes | Customer statements |
| GET | /reports/top-debtors | No | Top debtors |
| GET | /reports/dso | No | Days Sales Outstanding |
| GET | /reports/ar-summary | No | AR summary |
| GET | /reports/sales-summary | No | Sales summary |
| GET | /reports/sales-by-customer | No | Sales by customer |
| GET | /reports/sales-by-item | No | Sales by item |
| GET | /reports/stock-level | No | Stock levels |
| GET | /reports/low-stock | No | Low stock alert |
| GET | /reports/stock-valuation | Yes | Stock valuation |
| GET | /reports/inventory-movement | Yes | Inventory movement |
| GET | /reports/profit-loss | Yes | Profit & Loss |
| GET | /reports/cash-flow | Yes | Cash flow |
| GET | /reports/purchase-summary | No | Purchase summary |
| GET | /reports/supplier-analysis | No | Supplier analysis |
| GET | /reports/production-summary | No | Production summary |
| GET | /reports/bom-usage | No | BOM usage |
| GET | /reports/expenses | Yes | Expenses report |

Most reports accept `from` and `to` date query parameters.

---

## Activity Logs

| Method | Path | Admin? | Description |
|---|---|---|---|
| GET | /activity-logs | No | List logs (filtered, paginated) |
| GET | /activity-logs/stats | No | Activity statistics |
| GET | /activity-logs/recent | No | Recent activity |
| GET | /activity-logs/entity-types | No | Available entity types |
| GET | /activity-logs/actions | No | Available actions |
| GET | /activity-logs/users | No | Users for filtering |
| GET | /activity-logs/user/:id | No | Activity by user |
| GET | /activity-logs/entity/:type/:id | No | Activity by entity |
| GET | /activity-logs/export | No | Export logs as CSV |
| POST | /activity-logs/cleanup | Yes | Cleanup old logs |

---

## Settings

| Method | Path | Description |
|---|---|---|
| GET | /settings | Get all settings |
| GET | /settings/:key | Get setting by key |
| PUT | /settings/:key | Update setting |
| POST | /settings/bulk | Bulk update settings |

---

## Preferences

Per-user date-range picker preferences (week-start day, default range, custom
presets), synced server-side across devices. Scoped to the authenticated user
and guarded by the `settings` module permissions (`read` for GET, `update` for
PUT) — an admin or settings-capable user can change their own week start, which
also re-aligns the dashboard's `period=week` blocks.

### GET /preferences
The current user's preferences. Server defaults (`monday`, no default range,
no presets) are returned when no row exists yet — nothing is written on read.

```json
// Response 200
{
  "success": true,
  "data": {
    "weekStart": "monday",
    "defaultRange": { "from": "2026-08-03", "to": "2026-08-09" },
    "presets": [{ "id": "summer", "name": "Summer", "from": "2026-06-01", "to": "2026-08-31" }]
  }
}
```

`defaultRange` is `null` when unset; `presets` is always an array.

### PUT /preferences
**Partial** update — fields not present keep their current value; returns the
saved merged object. `defaultRange: null` clears the saved default.

```json
// Request — any subset of the three fields
{ "weekStart": "saturday", "defaultRange": null }

// Response 200
{ "success": true, "data": { "weekStart": "saturday", "defaultRange": null, "presets": [] } }
```

**Validation (400 on violation):** `weekStart` must be `monday` | `saturday` |
`sunday`; `defaultRange` must be `{ "from", "to" }` (YYYY-MM-DD) with `from <=
to`, or `null`; each preset must be `{ "id", "name", "from", "to" }` with a
non-empty unique `id` and `from <= to`.

---

## Integrations (Admin Only)

All integration endpoints require both authentication and admin role.

| Method | Path | Description |
|---|---|---|
| GET | /integrations/settings | Get all integration configs |
| PUT | /integrations/settings/:service | Update service config |
| POST | /integrations/test/email | Test SendGrid |
| POST | /integrations/test/notification | Test Twilio |
| GET | /integrations/weather | Get weather data |
| GET | /integrations/validate/phone | Validate phone number |
| GET | /integrations/currency/rates | Get exchange rates |
| POST | /integrations/currency/convert | Convert currency |
| POST | /integrations/tax/calculate | Calculate tax |

---

## Mobile Invoices

| Method | Path | Description |
|---|---|---|
| POST | /mobile-invoices/draft | Create draft |
| PUT | /mobile-invoices/draft/:id | Update draft |
| GET | /mobile-invoices/draft/:id | Get draft |
| DELETE | /mobile-invoices/draft/:id | Delete draft |
| GET | /mobile-invoices/items/search | Search items |
| GET | /mobile-invoices/customers/search | Search customers |
| GET | /mobile-invoices/tax-rates | Get tax rates |
| GET | /mobile-invoices/payment-terms | Get payment terms |
| POST | /mobile-invoices/submit | Submit final invoice |

---

## Health Check

### GET /health
Requires authentication like all other endpoints — the global auth middleware runs before the route, so an unauthenticated probe returns `401 { "error": "Access token required" }` (any HTTP response can still be treated as "server is up" by a health check).

```json
// Response 200 (with auth)
{ "status": "ok", "timestamp": "2026-02-20T12:00:00.000Z", "uptime": 3600 }
```

---

## Error Responses

All errors follow a consistent format:

```json
// 400 Bad Request
{ "success": false, "error": "Validation error message" }

// 401 Unauthorized
{ "error": "Access token required" }

// 403 Forbidden
{ "error": "Admin access required" }

// 404 Not Found
{ "success": false, "error": "Resource not found" }

// 500 Internal Server Error
{ "error": "Failed to <action>" }
```

Note: In production, error messages are generic and do not leak internal details.
