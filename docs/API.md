# API Reference

Base URL: `http://localhost:3011/api` (development and manual server deploys)

Packaged desktop installs expose the same API on an ephemeral loopback port:
the app starts the bundled server on `127.0.0.1` and discovers the port from
`<data>/server.port`, then uses `http://127.0.0.1:<port>/api`.

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
| GET | /inventory/item-companies | List companies (search, status, paged) |
| POST | /inventory/item-companies | Create a company by name |
| GET | /inventory/item-companies/:id | Get one company |
| PUT | /inventory/item-companies/:id | Rename a company |
| POST | /inventory/item-companies/:id/archive | Archive an assigned company |
| POST | /inventory/item-companies/:id/restore | Restore an archived company |
| DELETE | /inventory/item-companies/:id | Delete an unused company |
| GET | /inventory/item-companies/:id/products | List the company's products |
| GET | /inventory/item-companies/:id/suppliers | List linked and purchasing suppliers |
| GET | /inventory/item-companies/:id/suppliers/:supplierId/products | List one supplier's products for the company |
| POST | /inventory/item-companies/:id/suppliers/:supplierId | Link a supplier manually |
| DELETE | /inventory/item-companies/:id/suppliers/:supplierId | Remove a manual supplier link |
| GET | /inventory/items-low-stock | List items below reorder level |
| GET | /inventory/items-uom | List units of measure |

**Create Item:**
```json
{
  "item_code": "ITM001",
  "item_name": "Steel Rod 10mm",
  "company_id": 3,
  "category": "Raw Materials",
  "unit_of_measure": "Kg",
  "reorder_level": 100,
  "standard_cost": 25.50,
  "standard_selling_price": 35.00,
  "is_raw_material": true,
  "is_purchased": true
}
```

### Companies and manufacturer identity

`item_companies` is the canonical company identity. Item responses expose
`company_id`, `company_is_active` and the canonical name in `manufacturer_name`.
`company_id` is authoritative when it is present. A create or update that sends
only the legacy `manufacturer_name` resolves or creates the matching active
company in the same transaction. A new assignment to an archived company is
rejected; unrelated edits to a product that already belongs to an archived
company are allowed.

`GET /inventory/item-companies` accepts `search`, `status` (`active`,
`archived`, `all`), `page` and `limit` (maximum 200). It returns
`{success, data, pagination}` where each row is
`{id, company_name, is_active, product_count}`. Company names are trimmed,
limited to 200 characters, and unique without regard to case. It requires
inventory read permission.

Create, detail, rename, archive and restore return the company object directly.
Rename propagates the new name to assigned products. A duplicate name returns
409. `DELETE` succeeds only when no product, including an inactive or
soft-deleted product, references the company; a referenced delete returns 409
and asks for archive instead. Deleting an unused company also removes its manual
supplier links; supplier records remain. Create, rename, archive/restore and
delete use inventory create, update, update and delete permissions.

Company supplier rows combine two independent facts: a manual link
(`item_company_suppliers`) and purchase history derived from valid posted
purchases and goods receipts for the company's products. `POST` and `DELETE`
on `/inventory/item-companies/:id/suppliers/:supplierId` change only the manual
link. Removing the link does not remove purchase history. Supplier responses
require inventory read plus suppliers read, and link changes require inventory
update plus suppliers read. Archived companies and sold-out products remain
queryable. Supplier rows carry `linked`, `purchased`, contact fields, product
count and the last valid purchase date.

### Batch supplier provenance

`GET /inventory/stock-batches` includes a `suppliers` array on every batch:
`[{"supplier_id": 1, "supplier_name": "ABC Traders"}]`. Both the legacy array and
paged response shapes include this field. Direct purchases resolve through
`purchases`; goods receipts resolve through their receipt **line**, receipt and
purchase order. Supplier names reflect the linked supplier's current name, with
the purchase's recorded name as a fallback for historical free-text purchases.

New warehouse, expiry and damage transfers record every contributing source
batch atomically with the transfer. Mixed batches list all contributing suppliers;
a later transfer retains that set. This identifies contributors, not quantities
remaining per supplier in a merged cost layer. Untraceable sources appear as
`{"supplier_id": null, "supplier_name": null}` (displayed as "Not recorded").
Historical general transfers are not assigned their first batch's supplier because
they may have combined several sources. Historical batch-targeted expiry/damage
transfers can be traced using their existing movement link.

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

**Allocation reconciliation (H7):** the allocation lines must sum to the
payment `amount` exactly (±0.01). The payment is the single source of
truth for how much money left the business — the supplier ledger, the
supplier balance and the GL cash posting all post the *full* amount — so
a 1,000 payment accepted with a single 100 allocation would desync every
one of them. There is no supplier-advance / unallocated-payment concept
here (advances exist only on the employee-salary side), so under- and
over-allocation are both rejected with 400 before anything is written.

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

## Unapplied Customer Cash

These endpoints hold customer cash separately from return/store credit. They
do not activate historical credit or change `credit_balance`. Existing
`POST /payments` still requires allocations; use the dedicated receive endpoint
for cash collected before invoice settlement.

All four endpoints require authentication, the payment permission below, and
an `Idempotency-Key` header containing 8..200 characters (a fresh UUID per
operation is recommended). Reuse the same key and payload when retrying a lost
response. Keys are independent per customer and operation; reverse keys are
scoped to the receipt. Changed payloads with the same key return 409
`IDEMPOTENCY_CONFLICT`. Receive retains a permanent receipt replay record;
apply/refund retain permanent application replay records. Reverse uses the
central idempotency retention policy. Completed central keys are pruned after
30 days; this does not delete receive/apply/refund replay records. A receive
retry after receipt reversal returns its original payment ID, never a new receipt.
Browser preflights permit this header. Sensitive-operation rate limits apply.

| Method | Path | Permission |
|---|---|---|
| POST | `/customers/:id/unapplied-cash` | `payments:create` |
| POST | `/unapplied-cash/apply` | `payments:update` |
| POST | `/unapplied-cash/refund` | `payments:create` |
| POST | `/payments/:id/reverse` | `payments:delete` |

### GET /unapplied-cash/capabilities

Requires authentication, but no payment-read grant; this endpoint exposes only
static compatibility metadata and uses `Cache-Control: no-store`.

```json
{"success":true,"data":{"receive":"durable-v1","apply":"permanent-application-v1","refund":"permanent-application-v1","reverse":"guarded-status-v1"}}
```

Clients must check this online before dispatching/resuming persisted requests;
absent/unsupported guarantees require recovery, not blind resubmission. Receipt
replay protection covers operations committed under `durable-v1`; no historical
receipt keys are reconstructed or backfilled. Unexpired pre-upgrade central
receive claims are promoted to durable records when legitimately replayed.

### GET /customers/:id/unapplied-cash

Requires `payments:read`. Optional `operation_date` is a real `YYYY-MM-DD` and
defaults to the server's local current date. `page` defaults to 1; `limit` to 20
(maximum 100). IDs and pagination must be positive safe integers; malformed
queries return 400, missing customers 404, unauthorized access 401/403.

```json
{
  "success": true,
  "data": {
    "customer_id": 1,
    "operation_date": "2026-10-02",
    "remaining_amount": 500,
    "available_amount": 500,
    "refundable_amount": 500,
    "receipts": [{
      "source_id": 1, "payment_id": 12, "payment_no": "PAY0012",
      "payment_date": "2026-10-01", "payment_method": "Cash",
      "original_amount": 500, "applied_amount": 0, "refunded_amount": 0,
      "remaining_amount": 500, "voided_at": null, "can_reverse": true
    }]
  },
  "pagination": {"currentPage": 1, "totalPages": 1, "totalItems": 1, "limit": 20}
}
```

Totals cover all live UNAPPLIED_CASH sources for the customer, not just this
page. Return/store credit and voided sources/receipts never contribute. Available
and refundable amounts apply the service's current source and original-receipt
capacity limits, excluding receipts after `operation_date`. They are **not**
historical balances as of that date. Remaining cash includes future-dated live
receipts. Rows include used and voided receipts, newest payment date/ID first.
`can_reverse` is only an unused/dependency hint: POST still checks periods and
chronological cash availability. Use fresh reads; POST remains authoritative.

### GET /customers/:id/unapplied-cash/activity

Requires `payments:read`, with the same pagination bounds. Optional inclusive
`fromDate`/`toDate` must be real dates in ascending order. Returns
`{success,data:[{application_id,operation,operation_date,total_amount,payment_id,
lines:[{id,application_id,source_id,invoice_id,invoice_no,payment_id,amount,kind,
voided_at}]}],pagination:{currentPage,totalPages,totalItems,limit}}`.
Operation/kind are APPLY or REFUND. Results are newest operation date/ID first;
invoice/payment IDs are nullable where not applicable. This history range does
not affect the separate current-cash summary. Applications are not new cash
receipts. Existing payment list/detail responses now include `payment_kind` and
`voided_at`; unified payments include nullable `payment_kind`, positive absolute
amounts and `out` direction for customer REFUND documents.

Amounts are finite, positive JSON numbers, normalized to two currency decimal
places, with a minimum normalized amount of 0.01. IDs are positive safe
integers. `operation_date` must be a real `YYYY-MM-DD` date no later than the
end of next calendar year. Unknown body fields are rejected. Payment methods
are `Cash` (default), `Bank`, `Easypaisa`, `JazzCash`, and `Upaisa`.

### POST /customers/:id/unapplied-cash

```json
{ "amount": 500, "operation_date": "2026-10-01", "payment_method": "Cash" }
```

Returns 201 on creation, or 200 when replayed:

```json
{ "success": true, "data": { "paymentId": 41, "applicationId": null, "amount": 500 } }
```

Creates one positive UNAPPLIED_RECEIPT payment and a cash source, posting cash
against liability 2110 without changing customer AR. A customer with negative
`current_balance` is rejected with 409 `CUSTOMER_ALREADY_IN_CREDIT`.

### POST /unapplied-cash/apply

```json
{
  "customer_id": 1,
  "operation_date": "2026-10-02",
  "allocations": [{ "invoice_id": 12, "amount": 400 }]
}
```

Returns 200 with `{ "paymentId": null, "applicationId": 7, "amount": 400 }`
inside `data`. Supply 1..1000 allocations. Duplicate invoice lines are combined
before capacity checks. The server selects live cash sources oldest-first;
clients cannot set source kinds, counters, or source IDs. Invoices must belong
to this customer, remain payable, and not be dated after the application.
Allocations use the original receipts, not a new cash payment. Settlement
decreases invoice/customer AR and transfers liability 2110 to AR 1100.

### POST /unapplied-cash/refund

```json
{ "customer_id": 1, "amount": 100, "operation_date": "2026-10-03", "payment_method": "Cash" }
```

Returns 200 with the refund's positive payment ID, application ID and positive
refunded amount inside `data`. The persisted REFUND payment has a negative
amount. Only cash still held can fund a refund; applied cash and RETURN_CREDIT
sources cannot. The selected cash account must remain funded, including later
dated spending. Customer AR is unchanged.

### POST /payments/:id/reverse

```json
{ "reason": "Receipt entered twice" }
```

`reason` is optional; when supplied it must contain 1..500 characters after
trimming and cannot be blank. An empty body is accepted. Returns 200:

```json
{ "success": true, "data": { "paymentId": 41, "voided": true } }
```

This endpoint reverses only unused UNAPPLIED_RECEIPT payments. It atomically
voids the receipt journal/payment and retires its source, recording the acting
user and supplied reason. It cannot leave later cash spending unfunded. Normal
payment deletion continues through the existing payment API; this endpoint
does not introduce an un-apply or refund-reversal workflow.

### Errors and closed periods

- 400: malformed JSON/body/IDs, invalid dates or amounts, missing/malformed
  idempotency headers. Validation errors use `VALIDATION_ERROR`.
- 401/403: existing authentication and permission middleware responses.
- 404: missing customer, invoice, or unapplied receipt, with stable domain codes.
- 409: insufficient cash/source/receipt/invoice capacity, changed replay payload,
  cancelled/deleted invoices, already-voided receipts, or forbidden dependencies.
- 409 `PERIOD_CLOSED`: receive/apply/refund check their operation dates; reverse
  checks the original receipt date. An older receipt may be applied/refunded in
  a later open period, but cannot be reversed from a closed original period.
- 500 `INTERNAL_SERVER_ERROR`: generic response; no SQL, stacks or internal paths.

Domain errors use `{ "success": false, "error": { "code": "...", "message": "..." } }`.
Blocked reversal errors additionally expose `error.blockedBy`, for example:

```json
{
  "success": false,
  "error": {
    "code": "UNAPPLIED_ALREADY_APPLIED",
    "message": "Receipt has applied or refunded dependencies",
    "blockedBy": [{ "sourceId": 3, "consumed": 400, "invoices": [12] }]
  }
}
```

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

PO line create/add/update bodies accept `input_tax_amount` (nonnegative currency,
default zero) for the full ordered line. `unit_price` and line `amount` stay net
of recoverable tax; the PO `total_amount` includes tax. Submission records a
commitment. Each goods receipt recognizes inventory at net cost, recoverable tax
on the received quantity, and gross supplier AP. The final receipt assigns the
tax rounding remainder. Voiding a receipt reverses that receipt's tax and AP.

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

`POST /purchases` requires an identified, active `supplier_id`. The
server resolves the supplier name, links the purchase, and posts the AP
supplier-ledger entry (debit) so the purchase can be paid via
`POST /payments` with `purchase_allocations`. `invoice_no` / `remarks`
are also accepted.

Each line accepts `input_tax_amount` (nonnegative currency, default zero).
`total_cost` and batch cost remain net; `total_payable` includes tax.
`balance_amount` subtracts posted returns and active payment allocations.
Purchase returns include proportional tax in their payable credit and credit
note; inventory reversal remains net. Tax is stored per return line so final
returns exhaust the original tax exactly.

Multi-line bodies use `items: [{item_id, quantity, unit_cost,
input_tax_amount?, expiry_date?}]` and return an array. An unchanged request
with the same `Idempotency-Key` replays all original line IDs without posting
again. Pre-migration multi-line requests without a saved membership map return
409 for manual review; one-line legacy retries retain their array shape.

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

`payment_method: "Credit"` records an accrued expense when it reaches Recorded
status (Dr expense / Cr expense payable); Draft has no financial effect.
`GET /expenses/:id` includes `payments` and `paid_amount`. Settle with
`POST /expenses/:id/payments` using `{amount, payment_date, payment_method}`;
reverse with `POST /expenses/:id/payments/:paymentId/void` using `{reason}`.
Both require expenses:update; payment creation supports `Idempotency-Key`.
Reverse payments before cancelling or financially editing a credit expense.

## Supplier bills and advances

These routes return `{success: true, data}`. Lists require `supplier_id`, accept
`page` and `limit` (maximum 100), and include a pagination block. All writes
enforce accounting periods and run atomically with GL/subledger changes.

| Method | Path | Permission / purpose |
|---|---|---|
| GET | /supplier-bills, /supplier-bills/:id | purchases:read |
| POST | /supplier-bills | purchases:create and expenses:approve; recognize a non-stock bill |
| POST | /supplier-bills/:id/payments | payments:create; settle the bill |
| POST | /supplier-bills/:id/void | purchases:delete; reverse an unpaid bill |
| GET | /supplier-prepayments, /supplier-prepayments/:id | payments:read |
| GET | /supplier-prepayments/:id/targets?search= | payments:read; up to 50 matching unpaid documents for the same supplier |
| POST | /supplier-prepayments | payments:create; pay a supplier advance |
| POST | /supplier-prepayments/:id/apply | payments:create; apply an advance without new cash |
| POST | /supplier-prepayments/:id/void | payments:delete; reverse an unapplied advance |

Bill creation accepts `{supplier_id, bill_no, bill_date, due_date?, description,
net_amount, input_tax_amount?}`. It posts net expense and recoverable input tax
against gross AP. Active bill numbers are unique per supplier; after void, a
corrected bill can reuse the number while the original record remains visible.
Bill payments accept `{amount, payment_date, payment_method, reference_no?}`.
Reverse all payments before voiding; void bodies require `{reason}`.

Advances accept `{supplier_id, prepay_date, amount, payment_method,
reference_no?, notes?}` and post an asset against cash. Applications accept
`{applied_at, allocations: [{kind, id, amount}]}`, where kind is `purchase`,
`purchase_order` or `supplier_bill`. They settle AP against the advance asset.
Availability and document balances are validated together; duplicate targets,
cross-supplier targets and excess amounts are rejected. Standard payment voiding
restores advance availability. Advance-funded payments cannot be changed to cash
through the generic payment editor. Reverse applications before voiding an advance.

Bill/advance creation and settlement/application accept `Idempotency-Key`;
unchanged retries replay the saved result. Advances are separate from document
settlements, which still require full allocation of the payment amount.

`GET /reports/tax-summary?startDate=...&endDate=...` returns `total_tax` (net
output-tax movement), `input_tax` (net recoverable-tax movement) and `net_tax`
(output less input). These use posted GL movements, including returns and voids;
the report does not determine tax rates or filing eligibility.

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
| GET | /reports/company/stock | Yes | Current company stock and value |
| GET | /reports/company/sales | Yes | Company sales by product for a period |
| GET | /reports/company/purchases | Yes | Company purchases by product for a period |

Most reports accept `from` and `to` date query parameters.

### Company reports

All three endpoints require reports read permission plus the permission for the
viewed entity: inventory read for stock, invoices read for sales, and purchases
read for purchases. An archived `company_id` is valid because reports use the
stable company ID and do not depend on the company's current status.

`GET /reports/company/stock?company_id=...&page=...&limit=...` returns
`{company_id, as_of, valuation_basis, rows, totals, pagination}`. It has no date
parameters and always reports current stock. `as_of` is an ISO timestamp.
`valuation_basis` is `remaining_batch_cost`. Each row is
`{item_id, item_code, item_name, unit_of_measure, quantity, stock_value}`.
`totals` is `{stock_value, quantities_by_uom}`; `quantities_by_uom` maps each
unit to a number. Stock uses the same buckets as inventory valuation:
sellable minus reserved, plus expired and damaged physical stock. It does not
treat reserved stock as additive.

`GET /reports/company/sales` and `GET /reports/company/purchases` require
ordered `startDate` and `endDate` values in `YYYY-MM-DD` form. Both dates are
inclusive. They return `{company_id, view, startDate, endDate, amount_basis,
rows, totals, pagination}`. `view` is `sales` or `purchases`;
`amount_basis` is
`tax_inclusive_after_discounts_before_restocking_fees`.

Each product row carries `gross_quantity`, `return_quantity`, `net_quantity`,
`gross_value`, `return_value`, `net_value` and a `transactions` array. Returns
are separate columns and already reduce the net values. Returns are counted by
their own transaction date, including a return whose original document is older
than the period. Cancelled and voided documents and voided returns are
excluded. A document with several item lines or supplier joins is counted once.
`totals.quantities_by_uom` maps each unit to `{gross, returns, net}`. Products
are grouped by unit of measure and are never summed across different units.
`pagination.total` is the product count before the page slice. Double-tapping a
row in the desktop client opens its transaction list.

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
