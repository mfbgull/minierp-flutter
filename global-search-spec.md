# Global Entity-Aware Search & Command Palette — Implementation Spec

version: 1.0
status: draft
author: Codebuff (interview-derived)
date: 2026-08-19

---

## 0. Source Document

This spec is derived from the user-authored `global-search.md` feature request, refined through a structured interview. All decisions below are **user-confirmed**.

---

## 1. Feature Summary

Implement a **Global Search / Command Palette** that searches the SQLite database, identifies entity types, displays relevant context and metadata, and provides entity-specific actions — all from a single search entry point accessible everywhere in the app.

**Core flow:**
```
Search → Identify Entity → Show Context → Show Relevant Actions → Navigate to Existing Screen
```

---

## 2. User-Confirmed Design Decisions

| Decision Area | Choice | Rationale |
|---|---|---|
| Search UI | **Centered modal dialog** (backdrop overlay) | Like VS Code / Linear command palette |
| Action UX | **Right panel** | Two-column layout: results list on left, actions panel on right |
| Page registry | **Dynamic from GoRouter routes + shell destinations** | Auto-stays in sync with navigation |
| Empty state | **Recent items + quick action shortcuts** | Recently viewed customers, invoices, etc. |
| API design | **Single `/api/search` endpoint** | One endpoint returns all entity types |
| Keyboard shortcut | **Register in AppShell** (separate from screen_shortcuts.dart) | Not using the existing HardwareKeyboard handler |
| Search scope | **All entity types** (customers, suppliers, products, invoices, purchase orders, quotations, sales orders, payments, expenses, warehouses, employees, production/BOM) | Full coverage |
| Recent items storage | **SharedPreferences** (Flutter local) | No backend changes needed |
| Result limit | **10 per entity type** | Returns up to 10 per entity type |
| RTL support | **LTR only** | Search dialog always left-to-right |
| Search engine | **Simple LIKE with indexes** | Sufficient for ERP-scale data |
| Zod validation | **Yes, use Zod schema** | Consistent with existing middleware |
| Mobile support | **Desktop + mobile/web** | Ctrl+K on desktop, search icon on mobile |
| Error handling | **Inline error in dialog** | Show error within the dialog, don't dismiss it |
| Test framework | **Jest** | Matches existing `server/src/__tests__` |
| Recent items limit | **5 items** | Store/display up to 5 recently viewed |
| Debounce | **200ms** | Faster feel, fewer wasted requests |

---

## 3. Codebase Context (Discovered)

### 3.1 Backend Architecture

- **Framework:** Express + TypeScript
- **Database:** SQLite via `better-sqlite3`
- **DB config:** `server/src/config/database.ts` — single `db` export, WAL mode, foreign keys ON
- **Route pattern:** `server/src/routes/*.ts` → `server/src/controllers/*.Controller.ts` → `server/src/models/*.ts`
- **Response envelope:** `{ success: true, data }` / `{ success: false, error: "…" }`
- **Auth:** `authenticateToken` middleware (JWT in cookie)
- **Permissions:** `requirePermission(module, action)` — checks `role_permissions` + `permissions` tables
- **Validation:** Zod schemas via `validateZodQuery`, `validateZodBody`, `validateZodParams` in `server/src/middleware/validation.ts`
- **Logging:** `server/src/utils/logger.ts`
- **SQL sanitization:** `server/src/utils/sqlSanitizer.ts` — `sanitizeSortParams`, `getQueryParam`

### 3.2 Frontend Architecture

- **Framework:** Flutter (web + desktop)
- **Routing:** GoRouter with `StatefulShellRoute.indexedStack` for shell branches
- **State management:** Riverpod (ConsumerWidget, Provider, StateNotifier)
- **Shell:** `lib/features/shell/app_shell.dart` — navigation rail + app bar
- **Route definitions:** `lib/app.dart` — single `routerProvider` with all routes
- **Shell destinations:** `lib/features/shell/app_shell.dart` — `shellDestinations` list
- **API client:** `lib/core/api/endpoints.dart` + `lib/data/repositories/repository_client.dart`
- **Result pattern:** `ApiResult<T>` sealed class (`ApiSuccess` / `ApiFailure`)
- **Keyboard shortcuts:** `lib/widgets/screen_shortcuts.dart` — HardwareKeyboard handler for Ctrl+F/N/R/E
- **Localization:** `lib/l10n/app_localizations.dart` — English + Urdu
- **Toast/feedback:** `lib/widgets/app_toast.dart`
- **Icons:** Material Icons (`Icons.*`)

### 3.3 Database Schema — Searchable Tables

| Entity Type | Table | Searchable Fields |
|---|---|---|
| `customer` | `customers` | `customer_name`, `customer_code`, `phone`, `email`, `contact_person` |
| `supplier` | `suppliers` | `supplier_name`, `supplier_code`, `phone`, `email`, `contact_person` |
| `product` | `items` | `item_name`, `item_code`, `category`, `description` |
| `invoice` | `invoices` | `invoice_no`, `customer_name` (via join), `status` |
| `purchase_order` | `purchase_orders` | `po_no`, `status` (join with suppliers) |
| `quotation` | `quotations` | `quotation_no`, `customer_name` (via join) |
| `sales_order` | `sales_orders` | `so_no`, `status` (join with customers) |
| `payment` | `payments` | `payment_no`, `reference_no` (join with customers/suppliers) |
| `expense` | `expenses` | `description`, `reference_no` (join with categories) |
| `warehouse` | `warehouses` | `warehouse_name`, `warehouse_code` |
| `employee` | `employees` | `first_name`, `last_name`, `employee_code` |
| `production` | `productions` | `production_no`, `status` |
| `bom` | `boms` | `bom_no` (join with items) |

### 3.4 Existing Permissions Modules

The search must respect these permission modules (discovered from `seedDefaultPermissions`):
`customers`, `suppliers`, `inventory`, `invoices`, `purchases`, `purchase_orders`, `purchase_returns`, `payments`, `expenses`, `production`, `bom`, `sales`, `sales_orders`, `quotations`, `employees`, `pos`, `forecasts`, `activity_log`, `settings`, `roles`, `users`, `integrations`, `reports`

### 3.5 Existing Route Structure

**Backend API routes** (from `server/src/app.ts`):
- `/api/customers` → customers.ts
- `/api/suppliers` → suppliers.ts
- `/api/inventory` → inventory.ts (includes items, warehouses, stock)
- `/api/invoices` → invoices.ts
- `/api/purchases` → purchases.ts
- `/api/purchase-orders` → purchaseOrders.ts
- `/api/quotations` → sales.ts (quotations are under sales)
- `/api/sales-orders` → sales.ts
- `/api/payments` → payments.ts
- `/api/expenses` → expenses.ts
- `/api/employees` → employees.ts
- `/api/productions` → production.ts
- `/api/boms` → bom.ts

**Flutter shell routes** (from `app.dart`):
- `/` → Dashboard
- `/inventory` → InventoryShell
- `/customers` → CustomersScreen (sub-route `/:id` → CustomerDetailScreen)
- `/sales` → SalesShell
- `/purchasing` → PurchasingShell
- `/suppliers` → SuppliersScreen (sub-route `/:id` → SupplierDetailScreen)
- `/production` → ProductionShell
- `/payments` → PaymentsScreen
- `/expenses` → ExpensesScreen
- `/hr` → EmployeesScreen
- `/reports` → ReportsDashboardScreen
- `/forecasts` → ForecastShell
- `/activity-log` → ActivityLogScreen
- `/admin` → AdminShell (admin only)
- `/integrations` → IntegrationsScreen (admin only)
- `/settings` → SettingsScreen

---

## 4. Backend Implementation

### 4.1 New Files

| File | Purpose |
|---|---|
| `server/src/routes/search.ts` | Express router for `GET /api/search` |
| `server/src/controllers/searchController.ts` | Controller: parse query, call service, return results |
| `server/src/services/searchService.ts` | Business logic: run queries, rank results, build actions |
| `server/src/types/search.ts` | TypeScript interfaces for SearchResult, SearchAction, etc. |
| `server/src/__tests__/search.test.ts` | Jest tests for search functionality |

### 4.2 Route Registration

In `server/src/app.ts`:
```typescript
import searchRoutes from './routes/search';
// ...
app.use('/api/search', searchRoutes);
```

### 4.3 Zod Validation Schema

```typescript
// In server/src/routes/search.ts
import { z } from 'zod';
import { validateZodQuery } from '../middleware/validation';

const searchQuerySchema = z.object({
  q: z.string().min(2).max(100),
  limit: z.coerce.number().int().min(1).max(50).optional().default(10),
});
```

### 4.4 Endpoint Signature

```
GET /api/search?q=ali&limit=10
Authorization: Bearer <JWT>
```

### 4.5 Rate Limiting

The search endpoint is covered by the **existing global `apiLimiter`** applied in `app.ts`:

```typescript
// server/src/app.ts line 108
app.use('/api/', apiLimiter);
```

**Global limiter config** (`server/src/middleware/rateLimiter.ts`):
- **100 requests per minute** per IP
- Standard headers (`RateLimit-*`)
- Skipped in development and test environments
- Returns `429` with `retryAfter` header on exceed

**Why the global limiter is sufficient:**
- The search endpoint uses parameterized LIKE queries (no FTS indexing overhead)
- 200ms debounce on the frontend already limits request frequency
- 10 results per entity type keeps response payloads small
- ERP databases are typically small-to-medium (thousands, not millions of rows)

**When a dedicated search limiter would be needed:**
- If the ERP grows to 100K+ records per entity type
- If FTS5 is introduced (more expensive per-query cost)
- If the search endpoint is exposed to unauthenticated users
- If concurrent users exceed 50+ simultaneous searchers

**If a dedicated limiter is needed later:**
```typescript
// server/src/middleware/rateLimiter.ts (future)
export const searchLimiter = rateLimit({
  windowMs: 60 * 1000,    // 1 minute
  max: 30,                 // 30 search requests per minute per IP
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => {
    // Rate-limit by user ID (from JWT) instead of IP,
    // since ERP users may share IPs behind a NAT/firewall.
    const userId = (req as AuthRequest).user?.id;
    return userId ? `user:${userId}` : ipKeyGenerator(req.ip || '');
  },
  handler: (req: Request, res: Response) => {
    res.status(429).json({
      error: 'Too many search requests. Please slow down.',
      retryAfter: 60,
    });
  },
});
```

**Key difference from global limiter:** A dedicated search limiter would key on **user ID** (from JWT) rather than IP, because ERP users often sit behind a NAT/firewall sharing a single external IP.

### 4.6 Response Shape

```json
{
  "success": true,
  "data": {
    "query": "ali",
    "results": [
      {
        "type": "customer",
        "id": 124,
        "title": "Ali Khan",
        "subtitle": "CUST001 · Rs. 12,500 due",
        "metadata": {
          "balance": 12500,
          "phone": "0300-1234567"
        },
        "actions": [
          { "id": "open", "label": "Open Customer" },
          { "id": "create_invoice", "label": "Create Sales Invoice" },
          { "id": "receive_payment", "label": "Receive Payment" },
          { "id": "ledger", "label": "View Ledger" },
          { "id": "sales_history", "label": "View Sales History" }
        ]
      }
    ],
    "total": 25
  }
}
```

### 4.7 Response Fields Per Entity Type

Every search result returns a consistent envelope: `type`, `id`, `title`, `subtitle`, `metadata`, `actions`. The `title`, `subtitle`, and `metadata` fields vary by entity type. Below is the exact field mapping for each.

#### 4.7.1 Customer

```json
{
  "type": "customer",
  "id": 124,
  "title": "Ali Khan",
  "subtitle": "CUST001 · Rs. 12,500 due",
  "metadata": {
    "balance": 12500,
    "phone": "0300-1234567",
    "email": "ali@example.com"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `customers.customer_name` | Display name |
| `subtitle` | Composed | `"{customer_code} · Rs. {current_balance} due"` |
| `metadata.balance` | `customers.current_balance` | Decimal, 0 if null |
| `metadata.phone` | `customers.phone` | Nullable |
| `metadata.email` | `customers.email` | Nullable |

#### 4.7.2 Supplier

```json
{
  "type": "supplier",
  "id": 12,
  "title": "Ali Traders",
  "subtitle": "SUP-012 · Payable: Rs. 35,000",
  "metadata": {
    "balance": 35000,
    "phone": "0321-7654321",
    "email": "ali@traders.com"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `suppliers.supplier_name` | Display name |
| `subtitle` | Composed | `"{supplier_code} · Payable: Rs. {current_balance}"` |
| `metadata.balance` | `suppliers.current_balance` | Decimal, 0 if null |
| `metadata.phone` | `suppliers.phone` | Nullable |
| `metadata.email` | `suppliers.email` | Nullable |

#### 4.7.3 Product / Item

```json
{
  "type": "product",
  "id": 55,
  "title": "Ali Soap 100g",
  "subtitle": "ITEM-055 · Stock: 42 · Rs. 85",
  "metadata": {
    "stock": 42,
    "price": 85,
    "category": "FMCG",
    "unit": "Nos"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `items.item_name` | Display name |
| `subtitle` | Composed | `"{item_code} · Stock: {current_stock} · Rs. {standard_selling_price}"` |
| `metadata.stock` | `items.current_stock` | Decimal, 0 if null |
| `metadata.price` | `items.standard_selling_price` | Decimal |
| `metadata.category` | `items.category` | Nullable |
| `metadata.unit` | `items.unit_of_measure` | "Nos", "Kg", etc. |

#### 4.7.4 Invoice

```json
{
  "type": "invoice",
  "id": 42,
  "title": "INV-2024-0042",
  "subtitle": "Ali Khan · Unpaid · Rs. 12,500",
  "metadata": {
    "status": "Unpaid",
    "total": 12500,
    "balance": 12500,
    "customer_name": "Ali Khan",
    "invoice_date": "2024-08-15"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `invoices.invoice_no` | Document number |
| `subtitle` | Composed | `"{customer_name} · {status} · Rs. {balance_amount}"` |
| `metadata.status` | `invoices.status` | Unpaid, Partially Paid, Paid, etc. |
| `metadata.total` | `invoices.total_amount` | Decimal |
| `metadata.balance` | `invoices.balance_amount` | Decimal — amount still due |
| `metadata.customer_name` | `invoices.customer_name` or JOIN | Denormalized or joined |
| `metadata.invoice_date` | `invoices.invoice_date` | ISO date string |

#### 4.7.5 Purchase Order

```json
{
  "type": "purchase_order",
  "id": 15,
  "title": "PO-2024-0015",
  "subtitle": "Ali Traders · Submitted · Rs. 85,000",
  "metadata": {
    "status": "Submitted",
    "total": 85000,
    "supplier_name": "Ali Traders",
    "po_date": "2024-08-10"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `purchase_orders.po_no` | Document number |
| `subtitle` | Composed | `"{supplier_name} · {status} · Rs. {total_amount}"` |
| `metadata.status` | `purchase_orders.status` | Draft, Submitted, etc. |
| `metadata.total` | `purchase_orders.total_amount` | Decimal |
| `metadata.supplier_name` | JOIN `suppliers.supplier_name` | Resolved at query time |
| `metadata.po_date` | `purchase_orders.po_date` | ISO date string |

#### 4.7.6 Quotation

```json
{
  "type": "quotation",
  "id": 8,
  "title": "QUO-2024-0008",
  "subtitle": "Ali Khan · Accepted · Rs. 45,000",
  "metadata": {
    "status": "Accepted",
    "total": 45000,
    "customer_name": "Ali Khan",
    "quotation_date": "2024-08-05"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `quotations.quotation_no` | Document number |
| `subtitle` | Composed | `"{customer_name} · {status} · Rs. {total_amount}"` |
| `metadata.status` | `quotations.status` | Draft, Sent, Accepted, etc. |
| `metadata.total` | `quotations.total_amount` | Decimal |
| `metadata.customer_name` | JOIN `customers.customer_name` | Resolved at query time |
| `metadata.quotation_date` | `quotations.quotation_date` | ISO date string |

#### 4.7.7 Sales Order

```json
{
  "type": "sales_order",
  "id": 22,
  "title": "SO-2024-0022",
  "subtitle": "Ali Khan · Confirmed · Rs. 67,000",
  "metadata": {
    "status": "Confirmed",
    "total": 67000,
    "customer_name": "Ali Khan",
    "so_date": "2024-08-12"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `sales_orders.so_no` | Document number |
| `subtitle` | Composed | `"{customer_name} · {status} · Rs. {total_amount}"` |
| `metadata.status` | `sales_orders.status` | Draft, Confirmed, etc. |
| `metadata.total` | `sales_orders.total_amount` | Decimal |
| `metadata.customer_name` | JOIN `customers.customer_name` | Resolved at query time |
| `metadata.so_date` | `sales_orders.so_date` | ISO date string |

#### 4.7.8 Payment

```json
{
  "type": "payment",
  "id": 89,
  "title": "PAY-0089",
  "subtitle": "Ali Khan · Rs. 5,000 · Cash",
  "metadata": {
    "amount": 5000,
    "method": "Cash",
    "customer_name": "Ali Khan",
    "payment_date": "2024-08-18"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `payments.payment_no` | Document number |
| `subtitle` | Composed | `"{customer_name} · Rs. {amount} · {payment_method}"` |
| `metadata.amount` | `payments.amount` | Decimal |
| `metadata.method` | `payments.payment_method` | Cash, Check, etc. |
| `metadata.customer_name` | JOIN `customers.customer_name` | Or `suppliers.supplier_name` |
| `metadata.payment_date` | `payments.payment_date` | ISO date string |

#### 4.7.9 Expense

```json
{
  "type": "expense",
  "id": 33,
  "title": "Office rent August",
  "subtitle": "Office Supplies · Rs. 25,000",
  "metadata": {
    "amount": 25000,
    "category": "Office Supplies",
    "expense_date": "2024-08-01"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `expenses.description` | Expense description |
| `subtitle` | Composed | `"{category_name} · Rs. {amount}"` |
| `metadata.amount` | `expenses.amount` | Decimal |
| `metadata.category` | JOIN `expense_categories.category_name` | Resolved at query time |
| `metadata.expense_date` | `expenses.expense_date` | ISO date string |

#### 4.7.10 Warehouse

```json
{
  "type": "warehouse",
  "id": 1,
  "title": "Main Warehouse",
  "subtitle": "WH-001 · Default Location",
  "metadata": {
    "code": "WH-001",
    "location": "Default Location"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `warehouses.warehouse_name` | Display name |
| `subtitle` | Composed | `"{warehouse_code} · {location}"` |
| `metadata.code` | `warehouses.warehouse_code` | Short code |
| `metadata.location` | `warehouses.location` | Nullable |

#### 4.7.11 Employee

```json
{
  "type": "employee",
  "id": 5,
  "title": "Ahmed Khan",
  "subtitle": "EMP-005 · Developer",
  "metadata": {
    "code": "EMP-005",
    "department": "Developer",
    "phone": "0300-1112233"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | Composed | `"{first_name} {last_name}"` |
| `subtitle` | Composed | `"{employee_code} · {department}"` |
| `metadata.code` | `employees.employee_code` | Short code |
| `metadata.department` | `employees.department` | Nullable |
| `metadata.phone` | `employees.phone` | Nullable |

#### 4.7.12 Production

```json
{
  "type": "production",
  "id": 10,
  "title": "PRD-2024-0010",
  "subtitle": "Widget A · In Progress · Qty: 100",
  "metadata": {
    "status": "In Progress",
    "planned_quantity": 100,
    "item_name": "Widget A",
    "start_date": "2024-08-15"
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `productions.production_no` | Document number |
| `subtitle` | Composed | `"{item_name} · {status} · Qty: {planned_quantity}"` |
| `metadata.status` | `productions.status` | Draft, In Progress, etc. |
| `metadata.planned_quantity` | `productions.planned_quantity` | Decimal |
| `metadata.item_name` | JOIN `items.item_name` | Finished good name |
| `metadata.start_date` | `productions.start_date` | ISO date string, nullable |

#### 4.7.13 BOM

```json
{
  "type": "bom",
  "id": 7,
  "title": "BOM-0007",
  "subtitle": "Widget A · Active · 3 components",
  "metadata": {
    "is_active": true,
    "item_name": "Widget A",
    "component_count": 3
  }
}
```

| Field | Source Column | Notes |
|---|---|---|
| `title` | `boms.bom_no` | Document number |
| `subtitle` | Composed | `"{item_name} · {Active|Inactive} · {N} components"` |
| `metadata.is_active` | `boms.is_active` | Boolean |
| `metadata.item_name` | JOIN `items.item_name` | Finished good name |
| `metadata.component_count` | Subquery `COUNT(bom_items)` | Number of raw materials |

#### 4.7.14 Page / Action

```json
{
  "type": "page",
  "id": "reports",
  "title": "Reports",
  "subtitle": "Module · 20+ report types",
  "metadata": {
    "path": "/reports",
    "icon": "assessment_outlined"
  }
}
```

| Field | Source | Notes |
|---|---|---|
| `title` | Static registry | Page/action display name |
| `subtitle` | Static registry | Category label |
| `metadata.path` | Static registry | GoRouter path |
| `metadata.icon` | Static registry | Material icon name |

#### 4.7.15 Response Envelope

All entity types share the same top-level structure:

```typescript
interface SearchResult {
  type: string;          // 'customer' | 'supplier' | 'product' | ... | 'page'
  id: number | string;   // numeric ID for entities, string key for pages
  title: string;         // primary display text
  subtitle: string;      // secondary display text (composed string)
  metadata: Record<string, unknown>;  // entity-specific fields
  actions: SearchAction[];
}

interface SearchAction {
  id: string;            // 'open' | 'create_invoice' | ...
  label: string;         // 'Open Customer' | 'Create Sales Invoice' | ...
}
```

**Subtitle format convention:** All subtitles follow the pattern `"{code/status} · {key info}"` using `·` (middle dot) as separator. Currency values are prefixed with `Rs.` (Pakistani Rupee, matching the existing `formatCurrency` utility).

### 4.8 Search Strategy (Simple LIKE with Indexes)

For each entity type, run a parameterized LIKE query:

```sql
-- Example: customers
SELECT id, customer_name AS name, customer_code AS code, phone, email, current_balance AS balance
FROM customers
WHERE is_active = 1
  AND (customer_name LIKE ? OR customer_code LIKE ? OR phone LIKE ? OR email LIKE ? OR contact_person LIKE ?)
ORDER BY
  CASE
    WHEN customer_name LIKE ? THEN 1        -- starts with
    WHEN customer_name LIKE ? THEN 2        -- contains
    WHEN customer_code LIKE ? THEN 3        -- code match
    ELSE 4                                   -- other field match
  END,
  customer_name ASC
LIMIT ?
```

Parameter binding for query `ali`:
```
%ali%  (all LIKE fields)
ali%   (starts-with for ranking)
%ali%  (contains for ranking)
ali%   (code starts-with)
10     (limit)
```

Repeat for each entity type with appropriate field names.

### 4.9 Entity-Action Registry (Backend)

Define actions per entity type in `searchService.ts`:

```typescript
const ENTITY_ACTIONS: Record<string, ActionDef[]> = {
  // ── CUSTOMER ──────────────────────────────────────────────
  // No status field — always show all actions. Actions are
  // universally applicable regardless of customer state.
  customer: [
    { id: 'open', label: 'Open Customer' },
    { id: 'create_invoice', label: 'Create Sales Invoice', permission: 'invoices:create' },
    { id: 'receive_payment', label: 'Receive Payment', permission: 'payments:create' },
    { id: 'ledger', label: 'View Ledger' },
    { id: 'sales_history', label: 'View Sales History' },
  ],

  // ── SUPPLIER ──────────────────────────────────────────────
  // No status field — always show all actions.
  supplier: [
    { id: 'open', label: 'Open Supplier' },
    { id: 'create_purchase', label: 'Create Purchase', permission: 'purchases:create' },
    { id: 'make_payment', label: 'Make Payment', permission: 'payments:create' },
    { id: 'ledger', label: 'View Supplier Ledger' },
    { id: 'purchase_history', label: 'View Purchase History' },
  ],

  // ── PRODUCT / ITEM ────────────────────────────────────────
  // No status field — always show all actions.
  product: [
    { id: 'open', label: 'Open Product' },
    { id: 'create_sale', label: 'Create Sale', permission: 'invoices:create' },
    { id: 'create_purchase', label: 'Create Purchase', permission: 'purchases:create' },
    { id: 'adjust_stock', label: 'Adjust Stock', permission: 'inventory:update' },
    { id: 'stock_movements', label: 'View Stock Movements' },
  ],

  // ── INVOICE ───────────────────────────────────────────────
  // Statuses: Draft | Sent | Unpaid | Partially Paid | Paid |
  //           Overdue | Cancelled | Returned | Partially Returned
  //
  // Source: invoiceController.ts returnInvoiceItems() blocks Cancelled.
  //         ledgerUtils.updateInvoiceStatus() determines final status.
  invoice: [
    { id: 'open', label: 'Open Invoice' },
    {
      id: 'return_items',
      label: 'Return Items',
      permission: 'invoices:update',
      // Can return if NOT cancelled. Partially Returned and Returned
      // are allowed — the server checks per-item returned_qty to
      // prevent over-returning. Cancelled invoices are blocked.
      condition: (row) => row.status !== 'Cancelled',
    },
    {
      id: 'record_payment',
      label: 'Record Payment',
      permission: 'payments:create',
      // Can record payment if balance > 0. Paid and Fully Returned
      // invoices have zero balance. Cancelled invoices are blocked.
      // Partially Paid / Partially Returned / Unpaid / Overdue can
      // still receive payments.
      condition: (row) =>
        row.status !== 'Paid' &&
        row.status !== 'Returned' &&
        row.status !== 'Cancelled',
    },
    {
      id: 'print',
      label: 'Print Invoice',
      // Always available — even for cancelled/returned invoices
      // (user may need a copy for records).
    },
  ],

  // ── PURCHASE ORDER ────────────────────────────────────────
  // Statuses: Draft | Submitted | Partially Received | Completed | Cancelled
  //
  // Source: PurchaseOrder.ts line 696 — Draft and Cancelled cannot
  //         receive goods. Line 169/584 — Submitted triggers the
  //         goods receipt workflow.
  purchase_order: [
    { id: 'open', label: 'Open Purchase Order' },
    {
      id: 'receive',
      label: 'Receive Goods',
      permission: 'purchases:create',
      // Can receive only if PO is Submitted or Partially Received.
      // Draft POs must be submitted first. Completed POs are fully
      // received. Cancelled POs cannot receive.
      condition: (row) =>
        row.status === 'Submitted' ||
        row.status === 'Partially Received',
    },
  ],

  // ── QUOTATION ─────────────────────────────────────────────
  // Statuses: Draft | Sent | Accepted | Rejected | Expired
  //
  // Source: salesController.ts line 167 — Converted status is
  //         blocked. Only Accepted quotations can be converted.
  //         Draft/Sent quotations should be accepted first.
  quotation: [
    { id: 'open', label: 'Open Quotation' },
    {
      id: 'convert_to_so',
      label: 'Convert to Sales Order',
      permission: 'sales_orders:create',
      // Only Accepted quotations can be converted to a sales order.
      // Draft/Sent need to be accepted by the customer first.
      // Rejected/Expired cannot be converted.
      condition: (row) => row.status === 'Accepted',
    },
  ],

  // ── SALES ORDER ───────────────────────────────────────────
  // Statuses: Draft | Confirmed | Delivered | Invoiced | Completed | Cancelled
  //
  // Source: SalesOrder.ts lines 366/370/386/503/536/543/617/621 —
  //         Cancelled cannot create invoice. Invoiced/Completed
  //         already have an invoice. Draft/Confirmed/Delivered can
  //         create invoices.
  sales_order: [
    { id: 'open', label: 'Open Sales Order' },
    {
      id: 'create_invoice',
      label: 'Create Invoice',
      permission: 'invoices:create',
      // Can create invoice if SO is Draft, Confirmed, or Delivered.
      // Cancelled — blocked. Invoiced — already has linked invoice.
      // Completed — fully delivered and invoiced.
      condition: (row) =>
        row.status !== 'Cancelled' &&
        row.status !== 'Invoiced' &&
        row.status !== 'Completed',
    },
  ],

  // ── PAYMENT ───────────────────────────────────────────────
  // No mutable status — payments are immutable records.
  payment: [
    { id: 'open', label: 'Open Payment' },
    { id: 'print', label: 'Print Receipt' },
  ],

  // ── EXPENSE ───────────────────────────────────────────────
  // No status field — always show open action.
  expense: [
    { id: 'open', label: 'Open Expense' },
  ],

  // ── WAREHOUSE ─────────────────────────────────────────────
  // No status field — always show all actions.
  warehouse: [
    { id: 'open', label: 'Open Warehouse' },
    { id: 'view_stock', label: 'View Stock' },
    { id: 'stock_movements', label: 'View Stock Movements' },
  ],

  // ── EMPLOYEE ──────────────────────────────────────────────
  // No status field — always show all actions.
  employee: [
    { id: 'open', label: 'Open Employee' },
    { id: 'pay_salary', label: 'Pay Salary', permission: 'employees:update' },
  ],

  // ── PRODUCTION ────────────────────────────────────────────
  // Statuses: Draft | In Progress | Completed | Cancelled
  //
  // All actions are always available — the existing screen handles
  // status-based UI gating (e.g., can't start a completed production).
  production: [
    { id: 'open', label: 'Open Production' },
  ],

  // ── BOM ───────────────────────────────────────────────────
  // has `is_active` boolean — inactive BOMs should not offer
  // production. The BOM screen filters inactive BOMs by default.
  bom: [
    { id: 'open', label: 'Open BOM' },
    {
      id: 'produce',
      label: 'Start Production',
      permission: 'production:create',
      // Only active BOMs can start production.
      condition: (row) => row.is_active === true,
    },
  ],
};

// ─────────────────────────────────────────────────────────────────
// ACTION CONDITION REFERENCE
// ─────────────────────────────────────────────────────────────────
// This table summarizes the business rules derived from the codebase.
// Each condition is enforced server-side in the existing controllers;
// the search service merely mirrors these rules for action visibility.
//
// | Entity          | Action            | Allowed Statuses              | Blocked Statuses               | Source                              |
// |-----------------|-------------------|-------------------------------|--------------------------------|-------------------------------------|
// | Invoice         | Return Items      | All except Cancelled           | Cancelled                       | invoiceController.ts:802            |
// | Invoice         | Record Payment    | Unpaid, Partially Paid,        | Paid, Returned, Cancelled       | ledgerUtils.ts:88                   |
// |                 |                   | Partially Returned, Overdue,   |                                 |                                     |
// |                 |                   | Draft, Sent                    |                                 |                                     |
// | Invoice         | Print             | All (always)                   | —                               | —                                   |
// | Purchase Order  | Receive Goods     | Submitted, Partially Received  | Draft, Completed, Cancelled     | PurchaseOrder.ts:696                |
// | Quotation       | Convert to SO     | Accepted                       | Draft, Sent, Rejected, Expired  | salesController.ts:167              |
// | Sales Order     | Create Invoice    | Draft, Confirmed, Delivered    | Cancelled, Invoiced, Completed  | SalesOrder.ts:366,370,536           |
// | BOM             | Start Production  | is_active = true               | is_active = false               | bom_screen.dart (default filter)    |
// | Customer        | All actions       | Always                         | —                               | —                                   |
// | Supplier        | All actions       | Always                         | —                               | —                                   |
// | Product         | All actions       | Always                         | —                               | —                                   |
// | Payment         | All actions       | Always (immutable)             | —                               | —                                   |
// | Expense         | All actions       | Always                         | —                               | —                                   |
// | Warehouse       | All actions       | Always                         | —                               | —                                   |
// | Employee        | All actions       | Always                         | —                               | —                                   |
// | Production      | All actions       | Always (screen gates UI)       | —                               | —                                   |
```

### 4.10 Permission Filtering

For each result's actions:
1. Get the current user's `role_id` from the JWT
2. Query `role_permissions` + `permissions` to get the user's allowed `module:action` pairs
3. Filter out actions whose `permission` field is not in the user's allowed set
4. Admin role bypasses all permission checks (existing `requirePermission` pattern)

### 4.11 Page/Action Registry (Backend)

A static list of searchable pages/actions, searched server-side:

```typescript
const PAGE_ACTIONS: PageAction[] = [
  { id: 'dashboard', title: 'Dashboard', path: '/', icon: 'space_dashboard_outlined', keywords: ['home', 'overview'] },
  { id: 'inventory', title: 'Inventory', path: '/inventory', icon: 'inventory_2_outlined', keywords: ['items', 'products', 'stock'] },
  { id: 'customers', title: 'Customers', path: '/customers', icon: 'people_outline', keywords: ['clients', 'accounts'] },
  { id: 'sales', title: 'Sales', path: '/sales', icon: 'point_of_sale_outlined', keywords: ['invoices', 'billing'] },
  { id: 'purchasing', title: 'Purchasing', path: '/purchasing', icon: 'shopping_cart_outlined', keywords: ['buy', 'procurement'] },
  { id: 'suppliers', title: 'Suppliers', path: '/suppliers', icon: 'local_shipping_outlined', keywords: ['vendors', 'buyers'] },
  { id: 'production', title: 'Manufacturing', path: '/production', icon: 'factory_outlined', keywords: ['bom', 'work order', 'manufacturing'] },
  { id: 'payments', title: 'Payments', path: '/payments', icon: 'account_balance_wallet_outlined', keywords: ['receipts', 'transactions'] },
  { id: 'expenses', title: 'Expenses', path: '/expenses', icon: 'receipt_long_outlined', keywords: ['costs', 'spending'] },
  { id: 'employees', title: 'Employees', path: '/hr', icon: 'badge_outlined', keywords: ['hr', 'staff', 'salary'] },
  { id: 'reports', title: 'Reports', path: '/reports', icon: 'assessment_outlined', keywords: ['analytics', 'summary'] },
  { id: 'forecasts', title: 'Forecasts', path: '/forecasts', icon: 'insights_outlined', keywords: ['demand', 'prediction'] },
  { id: 'activity_log', title: 'Activity Log', path: '/activity-log', icon: 'history', keywords: ['audit', 'history'] },
  { id: 'settings', title: 'Settings', path: '/settings', icon: 'settings_outlined', keywords: ['config', 'preferences'] },
  { id: 'create_invoice', title: 'Create Sales Invoice', path: '/sales/form', icon: 'add_circle_outline', keywords: ['new', 'billing', 'sale'], action: true },
  { id: 'create_purchase', title: 'Create Purchase', path: '/purchasing', icon: 'add_circle_outline', keywords: ['new', 'buy'], action: true },
  { id: 'add_customer', title: 'Add Customer', path: '/customers', icon: 'person_add', keywords: ['new', 'client'], action: true },
  { id: 'add_supplier', title: 'Add Supplier', path: '/suppliers', icon: 'business', keywords: ['new', 'vendor'], action: true },
  { id: 'receive_payment', title: 'Receive Payment', path: '/payments', icon: 'payments', keywords: ['money', 'incoming'], action: true },
  { id: 'make_payment', title: 'Make Payment', path: '/payments', icon: 'money_off', keywords: ['outgoing', 'expense'], action: true },
];
```

Filter by user permissions (e.g., non-admins don't see `/admin`, `/integrations`; users without `reports:read` don't see Reports).

---

## 5. Frontend Implementation

### 5.1 New Files

| File | Purpose |
|---|---|
| `lib/features/search/global_search_dialog.dart` | Main dialog widget |
| `lib/features/search/search_provider.dart` | Riverpod provider for search state + API calls |
| `lib/features/search/search_result_tile.dart` | Individual result tile widget |
| `lib/features/search/search_action_panel.dart` | Right panel showing actions for selected result |
| `lib/features/search/search_registry.dart` | Client-side page/action definitions (mirrors backend) |
| `lib/features/search/recent_items.dart` | SharedPreferences-based recent items manager |
| `lib/data/repositories/search_repository.dart` | API client for search endpoint |

### 5.2 Keyboard Shortcut

Register `Ctrl+K` in `AppShell` (`lib/features/shell/app_shell.dart`):

```dart
// In AppShell's build method, wrap with a RawKeyboardListener or use
// Focus + onKeyEvent to detect Ctrl+K and show the search dialog.
```

**NOT** in `screen_shortcuts.dart` — the user chose to register it independently in AppShell.

Also add a search icon button in the AppBar actions (visible on mobile where keyboard shortcuts don't work):

```dart
IconButton(
  tooltip: 'Search (Ctrl+K)',
  icon: const Icon(Icons.search),
  onPressed: () => _openSearchDialog(context),
),
```

### 5.3 Dialog Structure

```
GlobalSearchDialog
├── SearchField (TextField with autofocus, debounce)
├── ResultsPanel (left ~60% width)
│   ├── LoadingState (circular progress)
│   ├── EmptyState ("Type to search...")
│   ├── ErrorState (inline error message)
│   ├── GroupedResults
│   │   ├── SearchResultGroup ("CUSTOMERS")
│   │   │   ├── SearchResultTile × N
│   │   │   └── ... (max 10 per group)
│   │   ├── SearchResultGroup ("PRODUCTS")
│   │   └── ... (only non-empty groups)
│   └── EmptyQueryState
│       ├── QuickActions (Create Invoice, Add Customer, etc.)
│       └── RecentItems (last 5 viewed)
└── ActionPanel (right ~40% width)
    ├── EntityHeader (icon, title, subtitle, metadata)
    └── ActionList (vertical list of action buttons)
```

### 5.3.1 Desktop Layout — Two-Column Modal (1200×700px)

When a result is selected, the right panel shows entity details and actions.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  🔍  Search customers, suppliers, products, invoices...              [Esc]  │
├───────────────────────────────────────┬─────────────────────────────────────┤
│                                       │                                     │
│  RESULTS                              │  SELECT A RESULT                    │
│                                       │                                     │
│  CUSTOMERS                            │  ┌─────────────────────────────┐    │
│  ┌─────────────────────────────────┐  │  │  👤  Ali Khan                │    │
│  │ 👤 Ali Khan               124  │──│──│  Customer · CUST001          │    │
│  │    CUST001 · Rs. 12,500 due    │  │  │  Balance: Rs. 12,500        │    │
│  └─────────────────────────────────┘  │  │  Phone: 0300-1234567        │    │
│  ┌─────────────────────────────────┐  │  └─────────────────────────────┘    │
│  │ 👤 Ali & Sons              89  │  │                                     │
│  │    CUST045 · Rs. 0             │  │  ACTIONS                             │
│  └─────────────────────────────────┘  │                                     │
│                                       │  ┌─────────────────────────────┐    │
│  PRODUCTS                             │  │  → Open Customer          ↵ │    │
│  ┌─────────────────────────────────┐  │  └─────────────────────────────┘    │
│  │ 📦 Ali Soap 100g          55  │  │  ┌─────────────────────────────┐    │
│  │    ITEM-055 · Stock: 42        │  │  │  → Create Sales Invoice     │    │
│  └─────────────────────────────────┘  │  └─────────────────────────────┘    │
│                                       │  ┌─────────────────────────────┐    │
│  SUPPLIERS                            │  │  → Receive Payment           │    │
│  ┌─────────────────────────────────┐  │  └─────────────────────────────┘    │
│  │ 🏭 Ali Traders            12  │  │  ┌─────────────────────────────┐    │
│  │    SUP-012 · Payable: 35,000   │  │  │  → View Ledger               │    │
│  └─────────────────────────────────┘  │  └─────────────────────────────┘    │
│                                       │  ┌─────────────────────────────┐    │
│                                       │  │  → View Sales History        │    │
│                                       │  └─────────────────────────────┘    │
│                                       │                                     │
└───────────────────────────────────────┴─────────────────────────────────────┘
  ◄── 60% width ──►                     ◄── 40% width ──►
```

**Key behaviors:**
- Left panel scrolls independently; right panel stays fixed
- Clicking a result in the left panel updates the right panel
- Keyboard ↑/↓ navigates results; Enter/→ opens the action panel; Enter on an action executes it
- Right panel shows entity icon, title, subtitle, metadata, then a vertical list of actions
- Actions with `Enter`/`↵` indicator execute on Enter key

### 5.3.2 Desktop Layout — Empty State (No Query)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  🔍  Search customers, suppliers, products, invoices...              [Esc]  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  QUICK ACTIONS                                                              │
│                                                                             │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────┐  │
│  │  ➕ Create Invoice    │  │  ➕ Create Purchase   │  │  👤 Add Customer │  │
│  └──────────────────────┘  └──────────────────────┘  └──────────────────┘  │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────┐  │
│  │  💰 Receive Payment  │  │  📄 Add Supplier     │  │  📦 Add Product  │  │
│  └──────────────────────┘  └──────────────────────┘  └──────────────────┘  │
│                                                                             │
│  RECENT                                                                     │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ 👤 Ali Khan                              Customer · 2 min ago      ↵ │  │
│  ├───────────────────────────────────────────────────────────────────────┤  │
│  │ 📄 INV-2024-0042                         Invoice · 15 min ago     ↵ │  │
│  ├───────────────────────────────────────────────────────────────────────┤  │
│  │ 📦 Widget A                              Product · 1 hour ago      ↵ │  │
│  ├───────────────────────────────────────────────────────────────────────┤  │
│  │ 🏭 Ali Traders                           Supplier · yesterday      ↵ │  │
│  ├───────────────────────────────────────────────────────────────────────┤  │
│  │ 💰 PAY-0089                              Payment · yesterday       ↵ │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.3.3 Desktop Layout — Loading State

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  🔍  ali                                                           [Esc]   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         ◌  Searching...                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.3.4 Desktop Layout — No Results

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  🔍  xyzzy123                                                      [Esc]   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         No results for "xyzzy123"                           │
│                                                                             │
│                         Try a different search term                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.3.5 Desktop Layout — Error State

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  🔍  ali                                                           [Esc]   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         ⚠  Connection error                                 │
│                            Could not reach the server.                      │
│                            Check your network and try again.                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.3.6 Desktop Layout — Inline Error (Entity Deleted)

When an action is executed but the entity no longer exists:

```
┌───────────────────────────────────────┬─────────────────────────────────────┐
│  🔍  ali                              │                                     │
│                                       │  ┌─────────────────────────────┐    │
│  RESULTS                              │  │  ⚠  Customer not found       │    │
│                                       │  │  This customer may have      │    │
│  CUSTOMERS                            │  │  been deleted since you      │    │
│  ┌─────────────────────────────────┐  │  │  searched.                   │    │
│  │ 👤 Ali Khan               124  │──│──│                             │    │
│  │    CUST001 · Rs. 12,500 due    │  │  │  [Dismiss]                   │    │
│  └─────────────────────────────────┘  │  └─────────────────────────────┘    │
│                                       │                                     │
│                                       │  The dialog stays open.             │
└───────────────────────────────────────┴─────────────────────────────────────┘
```

### 5.3.7 Mobile / Narrow View (< 768px)

On mobile or narrow browser windows, the two-column layout collapses to a single column. The action panel replaces the results panel (drill-down pattern).

**State 1 — Results list:**
```
┌───────────────────────────────────────┐
│  🔍  ali                         [✕]  │
├───────────────────────────────────────┤
│                                       │
│  CUSTOMERS                            │
│  ┌─────────────────────────────────┐  │
│  │ 👤 Ali Khan               124  │  │
│  │    CUST001 · Rs. 12,500 due    │  │
│  └─────────────────────────────────┘  │
│  ┌─────────────────────────────────┐  │
│  │ 👤 Ali & Sons              89  │  │
│  │    CUST045 · Rs. 0             │  │
│  └─────────────────────────────────┘  │
│                                       │
│  PRODUCTS                             │
│  ┌─────────────────────────────────┐  │
│  │ 📦 Ali Soap 100g          55  │  │
│  │    ITEM-055 · Stock: 42        │  │
│  └─────────────────────────────────┘  │
│                                       │
└───────────────────────────────────────┘
```

**State 2 — After tapping a result (drill into actions):**
```
┌───────────────────────────────────────┐
│  ←  Ali Khan                    [✕]  │
├───────────────────────────────────────┤
│                                       │
│  👤  Ali Khan                         │
│  Customer · CUST001                   │
│  Balance: Rs. 12,500                  │
│  Phone: 0300-1234567                  │
│                                       │
│  ACTIONS                              │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  → Open Customer               │  │
│  └─────────────────────────────────┘  │
│  ┌─────────────────────────────────┐  │
│  │  → Create Sales Invoice         │  │
│  └─────────────────────────────────┘  │
│  ┌─────────────────────────────────┐  │
│  │  → Receive Payment              │  │
│  └─────────────────────────────────┘  │
│  ┌─────────────────────────────────┐  │
│  │  → View Ledger                  │  │
│  └─────────────────────────────────┘  │
│  ┌─────────────────────────────────┐  │
│  │  → View Sales History           │  │
│  └─────────────────────────────────┘  │
│                                       │
└───────────────────────────────────────┘
```

**Key mobile behaviors:**
- Single column, full width
- Tapping a result pushes the action view (back arrow to return to results)
- Tapping an action closes the dialog and navigates
- Close button (✕) dismisses the dialog
- The back arrow (←) in the action view header returns to the results list
- The dialog takes ~90% of screen height on mobile

### 5.3.8 Keyboard Navigation

```
Desktop keyboard flow:

  Ctrl+K  →  Open dialog (autofocus search field)
  Esc     →  Close dialog
  ↑ / ↓  →  Navigate results list
  Enter   →  If result focused: open action panel (or execute first action)
              If action focused: execute action
  ← / →  →  Move between results panel and action panel
  Tab     →  Move focus between search field and results
```

### 5.3.9 Dialog Sizing & Positioning

| Property | Desktop | Mobile (< 768px) |
|---|---|---|
| Width | 720px (or 60% viewport, max 900px) | 100% - 32px (16px margin each side) |
| Height | 500px (or 70% viewport, max 600px) | 90% viewport height |
| Position | Centered on screen | Bottom-anchored (sheet style) |
| Backdrop | Semi-transparent black (0.5 opacity) | Semi-transparent black (0.5 opacity) |
| Border radius | 12px | 16px (bottom corners only on mobile) |
| Shadow | Elevated card shadow | Elevated card shadow |
| Results panel width | 60% | 100% (single column) |
| Action panel width | 40% | 100% (drill-down, replaces results) |
| Z-index | Above AppBar + FAB | Above AppBar + FAB |

### 5.4 Search Provider (Riverpod)

```dart
// search_provider.dart
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider.autoDispose<SearchResponse>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.length < 2) return SearchResponse.empty();
  // Debounce handled via ref.onDispose + Timer
  final repo = ref.watch(searchRepositoryProvider);
  return repo.search(query: query, limit: 10);
});

final selectedResultProvider = StateProvider<SearchResult?>((ref) => null);
```

### 5.5 Debounce Implementation

```dart
// In search_provider.dart or the dialog widget
Timer? _debounce;

void _onSearchChanged(String value) {
  _debounce?.cancel();
  _debounce = Timer(Duration(milliseconds: 200), () {
    ref.read(searchQueryProvider.notifier).state = value;
  });
}
```

### 5.6 Recent Items (SharedPreferences)

```dart
// recent_items.dart
class RecentItems {
  static const _key = 'global_search_recent_items';
  static const _maxItems = 5;

  static Future<List<RecentItem>> getItems() async { ... }
  static Future<void> addItem(RecentItem item) async { ... }
  static Future<void> clear() async { ... }
}

// RecentItem model
class RecentItem {
  final String entityType; // 'customer', 'invoice', etc.
  final int entityId;
  final String title;
  final String subtitle;
  final DateTime viewedAt;
}
```

#### 5.6.1 Recording Trigger — When Is a RecentItem Stored?

A `RecentItem` is recorded when the user **selects a search result** (clicks/taps a result tile), NOT when the dialog opens or when an action is executed.

**Trigger points analyzed:**

| Event | Record? | Rationale |
|---|---|---|
| Dialog opens | ❌ No | The dialog hasn't shown any entity yet — nothing to record |
| User types a query | ❌ No | Typing is exploratory, not a commitment to view |
| **User selects a result** | ✅ **Yes** | The user explicitly chose to view this entity — this is the "view" moment |
| User executes an action | ❌ No | The action navigates away from search; recording on selection already captured it |
| Action fails (entity deleted) | ❌ No | Entity no longer exists — should not appear in recents |

**Why record on selection, not on action execution:**
- Selection = "I want to see this entity" — the most natural "recently viewed" signal
- Action execution is optional — the user might just want to view the entity without performing an action
- Recording on selection means the entity appears in recents even if the user dismisses the dialog without acting
- Avoids duplicate entries if the user selects the same result multiple times (upsert by `entityType + entityId`)

**Implementation — recording on selection:**

```dart
// In the search dialog, when a result tile is tapped:
void _onResultSelected(SearchResult result) async {
  // 1. Update the selected result (shows action panel on desktop,
  //    pushes to action view on mobile)
  ref.read(selectedResultProvider.notifier).state = result;

  // 2. Record as recently viewed
  await RecentItems.addItem(RecentItem(
    entityType: result.type,
    entityId: result.id,
    title: result.title,
    subtitle: result.subtitle,
    viewedAt: DateTime.now(),
  ));
}
```

**Deduplication — upsert behavior:**

```dart
static Future<void> addItem(RecentItem item) async {
  final prefs = await SharedPreferences.getInstance();
  final items = await getItems();

  // Remove existing entry for the same entity (move to top)
  items.removeWhere((e) =>
    e.entityType == item.entityType && e.entityId == item.entityId);

  // Insert at the beginning (most recent first)
  items.insert(0, item);

  // Trim to max items
  if (items.length > _maxItems) {
    items.removeRange(_maxItems, items.length);
  }

  // Serialize and persist
  final json = items.map((e) => e.toJson()).toList();
  await prefs.setStringList(_key, json.map((e) => jsonEncode(e)).toList());
}
```

**Recent items in the empty search state:**

When the search box is empty, the dialog shows:
1. **Quick Actions** — always shown (static shortcuts)
2. **Recent** — up to 5 recently viewed entities, sorted by `viewedAt` descending

Each recent item shows:
- Entity icon (type-based)
- Title (e.g., "Ali Khan")
- Subtitle (e.g., "Customer · 2 min ago")
- Relative time ("2 min ago", "1 hour ago", "yesterday")

Clicking a recent item:
1. Records it again as a new "view" (moves to top of recents)
2. Navigates to the entity's detail screen (same as `open` action)

**Clearing recent items:**

```dart
// Option 1: User explicitly clears (via a "Clear" button in the recent section)
static Future<void> clear() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_key);
}

// Option 2: Automatic expiry (optional — not required for initial implementation)
// Remove items older than 30 days during getItems()
```

**Storage format in SharedPreferences:**

```json
[
  {
    "type": "customer",
    "id": 124,
    "title": "Ali Khan",
    "subtitle": "CUST001",
    "viewedAt": "2026-08-19T14:30:00.000"
  },
  {
    "type": "invoice",
    "id": 55,
    "title": "INV-2024-0042",
    "subtitle": "Rs. 12,500",
    "viewedAt": "2026-08-19T14:25:00.000"
  }
]
```

### 5.7 Action Navigation — Route Resolution Map

#### 5.7.1 Existing GoRouter Route Inventory

The app uses `StatefulShellRoute.indexedStack` with tabbed shells. Each entity maps to one of these navigation patterns:

| Pattern | Example | How entity is referenced |
|---|---|---| |
| **Shell path** | `/customers`, `/sales` | Navigates to the shell (list view) |
| **Shell path + tab index** | `/sales` + `SalesShell._index = 1` | Selects a tab within a shell |
| **Detail sub-route** | `/customers/:id` | Path parameter (int) |
| **Standalone route + extra** | `/sales/form` | `extra: Invoice?` |
| **Dialog (no route)** | `showItemDetailDialog(context, itemId: id)` | Called as function, not routed |

#### 5.7.2 Navigation Architecture by Module

**Sales module** (`/sales` → `SalesShell`):
- Tab 0: `SalesScreen` (invoices grid)
- Tab 1: `SalesOrdersScreen` (sales orders grid)
- Tab 2: `QuotationsScreen` (quotations grid)
- Tab 3: `InvoiceReturnsScreen` (invoice returns grid)
- Standalone: `/sales/form` → `SalesInvoiceFormPage(invoice: Invoice?)` — null = create, Invoice = edit
- Standalone: `/sales/print-preview` → `InvoicePrintPreviewPage(invoice: Invoice)`

**Purchasing module** (`/purchasing` → `PurchasingShell`):
- Tab 0: `PurchaseOrdersScreen` (purchase orders grid)
- Tab 1: `PurchasesScreen` (direct purchases grid)
- Tab 2: `PurchaseReturnsScreen` (purchase returns grid)
- Dialogs: `PurchaseOrderDetailDialog`, `PurchaseDetailDialog`, `PurchaseReturnDetailDialog` — opened via `showDialog()` from within their respective screens

**Inventory module** (`/inventory` → `InventoryShell`):
- Tab 0: `ItemsScreen` (items grid)
- Tab 1: `WarehousesScreen` (warehouses grid)
- Tab 2: `StockMovementScreen` (stock movements grid)
- Tab 3: `StockByWarehouseScreen` (stock by warehouse grid)
- Tab 4: `PhysicalCountScreen` (physical counts grid)
- Dialogs: `ItemDetailDialog`, `StockLedgerDialog`, `StockMovementDetailDialog`, `PhysicalCountDetailDialog` — opened via `showDialog()` from within their screens

**Production module** (`/production` → `ProductionShell`):
- Tab 0: `ProductionScreen` (production runs grid)
- Tab 1: `BomScreen` (BOM list grid)
- Dialogs: `ProductionDetailDialog`, `BomDetailDialog` — opened via `showDialog()` from within their screens

**Standalone detail screens** (GoRouter sub-routes):
- `/customers/:id` → `CustomerDetailScreen(customerId: int)`
- `/suppliers/:id` → `SupplierDetailScreen(supplierId: int)`

**List-only screens** (no sub-route, dialogs handle details):
- `/payments` → `PaymentsScreen` (list + `PaymentDetailDialog`)
- `/expenses` → `ExpensesScreen` (list + `ExpenseFormDialog`)
- `/hr` → `EmployeesScreen` (list + `EmployeeDetailDialog`)
- `/reports` → `ReportsDashboardScreen` (hub) + `/reports/:report` sub-routes
- `/settings` → `SettingsScreen`
- `/` → `DashboardScreen`

#### 5.7.3 Route Resolution Map — All Entity + Action Combinations

The resolution function maps each `entityType + actionId` pair to the correct navigation. There are three strategies:

**Strategy A — Direct route navigation** (detail screens with sub-routes):
```dart
customers/customer_detail_screen.dart:  CustomerDetailScreen(customerId: int)
suppliers/supplier_detail_screen.dart:  SupplierDetailScreen(supplierId: int)
```

**Strategy B — Standalone route + extra** (forms/preview screens):
```dart
// /sales/form accepts Invoice? as extra. null = new, Invoice = edit.
// Cannot pass customerId directly — existing screen has no such param.
// Workaround: navigate to /sales/form, user selects customer in the form.
context.push('/sales/form'); // or context.push('/sales/form', extra: invoice);
```

**Strategy C — Navigate to shell + open dialog** (entities with dialog-only detail views):
These screens have no GoRouter sub-route. The detail view is a dialog opened by a function call from within the screen. Strategy: navigate to the shell tab, then call the dialog opener. The dialog functions accept an entity ID parameter.

```dart
// Inventory items — dialog opened by function:
showItemDetailDialog(context, itemId: 42);
// This works from anywhere IF the context has access to the Riverpod providers.
// Best approach: navigate to /inventory, then show dialog.

// Other entity dialogs follow the same pattern:
showDialog(context: context, builder: (_) => PurchaseOrderDetailDialog(...));
showDialog(context: context, builder: (_) => ProductionDetailDialog(...));
// etc.
```

#### 5.7.4 Complete Resolution Table

| Entity Type | Action ID | Navigation Strategy | Route / Call | Params | Notes |
|---|---|---|---|---|---|
| `customer` | `open` | **A** | `/customers/:id` | `customerId = result.id` | Direct sub-route |
| `customer` | `create_invoice` | **B** | `/sales/form` | `extra: null` | User selects customer in form. No customerId param exists. |
| `customer` | `receive_payment` | **C** | `/payments` | — | User creates payment from the payments screen |
| `customer` | `ledger` | **A** | `/customers/:id` | `customerId = result.id` | CustomerDetailScreen has ledger tab |
| `customer` | `sales_history` | **A** | `/customers/:id` | `customerId = result.id` | CustomerDetailScreen has sales tab |
| `supplier` | `open` | **A** | `/suppliers/:id` | `supplierId = result.id` | Direct sub-route |
| `supplier` | `create_purchase` | **C** | `/purchasing` | — | Tab 1 (Purchases) — user selects supplier |
| `supplier` | `make_payment` | **C** | `/payments` | — | User creates payment from the payments screen |
| `supplier` | `ledger` | **C** | `/suppliers/:id` | `supplierId = result.id` | SupplierDetailScreen has ledger tab |
| `supplier` | `purchase_history` | **C** | `/suppliers/:id` | `supplierId = result.id` | SupplierDetailScreen has history tab |
| `product` | `open` | **C** | `/inventory` | — | Tab 0 (Items) — opens `ItemDetailDialog(itemId: result.id)` |
| `product` | `create_sale` | **B** | `/sales/form` | `extra: null` | User selects item in invoice form |
| `product` | `create_purchase` | **C** | `/purchasing` | — | Tab 1 (Purchases) — user selects item |
| `product` | `adjust_stock` | **C** | `/inventory` | — | Tab 0 (Items) — user triggers stock adjustment dialog |
| `product` | `stock_movements` | **C** | `/inventory` | — | Tab 2 (Stock Movements) — shows item's movements |
| `invoice` | `open` | **C** | `/sales` | — | Tab 0 (Invoices) — user double-taps row for detail |
| `invoice` | `return_items` | **C** | `/sales` | — | Tab 0 — user uses row action menu |
| `invoice` | `record_payment` | **C** | `/payments` | — | User creates payment against this invoice |
| `invoice` | `print` | **B** | `/sales/print-preview` | `extra: Invoice` | Requires full Invoice object — must fetch first |
| `purchase_order` | `open` | **C** | `/purchasing` | — | Tab 0 (Purchase Orders) — `PurchaseOrderDetailDialog` |
| `purchase_order` | `receive` | **C** | `/purchasing` | — | Tab 0 — user triggers receive goods action |
| `quotation` | `open` | **C** | `/sales` | — | Tab 2 (Quotations) — `QuotationDetailDialog` |
| `quotation` | `convert_to_so` | **C** | `/sales` | — | Tab 2 — user uses row action |
| `sales_order` | `open` | **C** | `/sales` | — | Tab 1 (Sales Orders) — `SalesOrderDetailDialog` |
| `sales_order` | `create_invoice` | **C** | `/sales` | — | Tab 1 — user triggers create invoice from SO |
| `payment` | `open` | **C** | `/payments` | — | `PaymentDetailDialog` |
| `payment` | `print` | **C** | `/payments` | — | User triggers print from payment detail |
| `expense` | `open` | **C** | `/expenses` | — | `ExpenseFormDialog` opens in edit mode |
| `warehouse` | `open` | **C** | `/inventory` | — | Tab 1 (Warehouses) |
| `warehouse` | `view_stock` | **C** | `/inventory` | — | Tab 3 (Stock by Warehouse) |
| `warehouse` | `stock_movements` | **C** | `/inventory` | — | Tab 2 (Stock Movements) |
| `employee` | `open` | **C** | `/hr` | — | `EmployeeDetailDialog` |
| `employee` | `pay_salary` | **C** | `/hr` | — | `SalaryPaymentDialog` from employees screen |
| `production` | `open` | **C** | `/production` | — | Tab 0 (Production) — `ProductionDetailDialog` |
| `bom` | `open` | **C** | `/production` | — | Tab 1 (BOM) — `BomDetailDialog` |
| `bom` | `produce` | **C** | `/production` | — | Tab 1 — user triggers production from BOM |
| `page` | `*` | **A** | path from registry | — | Direct route (e.g., `/reports`, `/settings`) |

#### 5.7.5 Implementation — Resolution Function

```dart
/// Resolves the navigation target for a search result action.
///
/// Returns a [NavigationTarget] with the GoRouter path, any extra data,
/// and whether the dialog needs to be invoked after navigation.
NavigationTarget resolveNavigation(SearchResult result, SearchAction action) {
  final key = '${result.type}_${action.id}';

  return switch (key) {
    // ── Strategy A: Direct sub-route ──
    'customer_open' => NavigationTarget(path: '/customers/${result.id}'),
    'customer_ledger' => NavigationTarget(path: '/customers/${result.id}'),
    'customer_sales_history' => NavigationTarget(path: '/customers/${result.id}'),
    'supplier_open' => NavigationTarget(path: '/suppliers/${result.id}'),
    'supplier_ledger' => NavigationTarget(path: '/suppliers/${result.id}'),
    'supplier_purchase_history' => NavigationTarget(path: '/suppliers/${result.id}'),

    // ── Strategy B: Standalone route + extra ──
    'customer_create_invoice' => NavigationTarget(path: '/sales/form'),
    'product_create_sale' => NavigationTarget(path: '/sales/form'),
    'invoice_print' => NavigationTarget(
      path: '/sales/print-preview',
      fetchFirst: true, // Must fetch Invoice object before navigating
    ),

    // ── Strategy C: Navigate to shell, invoke dialog ──
    'product_open' => NavigationTarget(
      path: '/inventory',
      dialog: 'item_detail',
      dialogParams: {'itemId': result.id},
    ),
    'invoice_open' => NavigationTarget(path: '/sales', tabIndex: 0),
    'purchase_order_open' => NavigationTarget(path: '/purchasing', tabIndex: 0),
    'quotation_open' => NavigationTarget(path: '/sales', tabIndex: 2),
    'sales_order_open' => NavigationTarget(path: '/sales', tabIndex: 1),
    'payment_open' => NavigationTarget(path: '/payments'),
    'expense_open' => NavigationTarget(path: '/expenses'),
    'warehouse_open' => NavigationTarget(path: '/inventory', tabIndex: 1),
    'employee_open' => NavigationTarget(path: '/hr'),
    'production_open' => NavigationTarget(path: '/production', tabIndex: 0),
    'bom_open' => NavigationTarget(path: '/production', tabIndex: 1),

    // ── Page actions ──
    'page_*' => NavigationTarget(path: action.path ?? '/'),

    // ── Fallback ──
    _ => NavigationTarget(path: '/'),
  };
}
```

#### 5.7.6 Navigation Target Model

```dart
class NavigationTarget {
  const NavigationTarget({
    required this.path,
    this.extra,
    this.tabIndex,
    this.dialog,
    this.dialogParams,
    this.fetchFirst = false,
  });

  /// GoRouter path (e.g., '/customers/124', '/sales').
  final String path;

  /// Optional extra data passed via GoRouter (e.g., Invoice object).
  final Object? extra;

  /// If set, switch the shell to this tab index after navigation.
  /// Used for PurchasingShell, SalesShell, etc.
  final int? tabIndex;

  /// If set, invoke this dialog function after navigation.
  /// The dialog is opened by the destination screen's own logic.
  final String? dialog;

  /// Parameters for the dialog function.
  final Map<String, dynamic>? dialogParams;

  /// If true, fetch the full entity from the API before navigating
  /// (needed for screens that accept full objects as extra, like Invoice).
  final bool fetchFirst;
}
```

#### 5.7.7 Execution Flow

```dart
void _executeAction(BuildContext context, SearchResult result, SearchAction action) async {
  final target = resolveNavigation(result, action);

  // 1. Close the search dialog first
  Navigator.of(context).pop();

  // 2. If fetchFirst, get the full entity from API before navigating
  if (target.fetchFirst) {
    final entity = await _fetchEntity(result.type, result.id);
    if (entity == null) {
      // Entity was deleted — show inline error (already handled by search dialog)
      return;
    }
    context.push(target.path, extra: entity);
    return;
  }

  // 3. Navigate to the shell path
  context.go(target.path);

  // 4. If tabIndex, the shell's IndexedStack will be switched
  //    (requires a callback mechanism — see implementation notes below)
  if (target.tabIndex != null) {
    // Emit a tab-switch event that the shell listens to
n    // (e.g., via a Riverpod provider or a GlobalKey to the shell state)
  }

  // 5. If dialog, invoke it after a brief delay (to let the screen mount)
  if (target.dialog != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openDialog(target.dialog!, target.dialogParams!);
    });
  }
}
```

#### 5.7.8 Tab Index Switching — Provider Definitions & Integration

The shell tabs (SalesShell, PurchasingShell, ProductionShell, InventoryShell) use internal `StatefulWidget` state (`_index`). To switch tabs from outside (e.g., from the search action resolver), expose each shell's tab index as a **Riverpod `StateProvider`**.

##### 5.7.8.1 Provider Definitions

Create a single file `lib/features/shell/shell_tab_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab index for the Sales shell.
/// Index map:
///   0 = Invoices (SalesScreen)
///   1 = Sales Orders (SalesOrdersScreen)
///   2 = Quotations (QuotationsScreen)
///   3 = Invoice Returns (InvoiceReturnsScreen)
final salesTabProvider = StateProvider<int>((ref) => 0);

/// Tab index for the Purchasing shell.
/// Index map:
///   0 = Purchase Orders (PurchaseOrdersScreen)
///   1 = Purchases (PurchasesScreen)
///   2 = Purchase Returns (PurchaseReturnsScreen)
final purchasingTabProvider = StateProvider<int>((ref) => 0);

/// Tab index for the Production shell.
/// Index map:
///   0 = Production Runs (ProductionScreen)
///   1 = Bill of Materials (BomScreen)
final productionTabProvider = StateProvider<int>((ref) => 0);

/// Tab index for the Inventory shell.
/// Index map:
///   0 = Items (ItemsScreen)
///   1 = Warehouses (WarehousesScreen)
///   2 = Stock Movements (StockMovementScreen)
///   3 = Stock by Warehouse (StockByWarehouseScreen)
///   4 = Physical Counts (PhysicalCountScreen)
final inventoryTabProvider = StateProvider<int>((ref) => 0);
```

##### 5.7.8.2 Tab Index Constants

Create `lib/features/shell/shell_tab_indices.dart` for type-safe tab references:

```dart
/// Sales shell tab indices.
abstract final class SalesTab {
  static const int invoices = 0;
  static const int salesOrders = 1;
  static const int quotations = 2;
  static const int invoiceReturns = 3;
}

/// Purchasing shell tab indices.
abstract final class PurchasingTab {
  static const int purchaseOrders = 0;
  static const int purchases = 1;
  static const int purchaseReturns = 2;
}

/// Production shell tab indices.
abstract final class ProductionTab {
  static const int productionRuns = 0;
  static const int bom = 1;
}

/// Inventory shell tab indices.
abstract final class InventoryTab {
  static const int items = 0;
  static const int warehouses = 1;
  static const int stockMovements = 2;
  static const int stockByWarehouse = 3;
  static const int physicalCounts = 4;
}
```

##### 5.7.8.3 Shell Integration (Example: SalesShell)

Each shell reads from its provider instead of using a local `int _index = 0`:

```dart
// In lib/features/sales_orders/sales_shell.dart
class _SalesShellState extends ConsumerState<SalesShell> {
  @override
  Widget build(BuildContext context) {
    // Read tab index from the provider instead of local state
    final _index = ref.watch(salesTabProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            // Update the provider (also updates local rebuild)
            ref.read(salesTabProvider.notifier).state = i;
            moduleTabRefreshOnVisit['/sales']?[i].call(ref);
          },
          destinations: [
            // ... same destinations as before
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: const [
              SalesScreen(),
              SalesOrdersScreen(),
              QuotationsScreen(),
              InvoiceReturnsScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
```

Apply the same pattern to `PurchasingShell`, `ProductionShell`, and `InventoryShell`.

##### 5.7.8.4 Search Action Integration

The search resolver sets the tab provider before navigating:

```dart
void _executeAction(
  BuildContext context,
  WidgetRef ref,
  SearchResult result,
  SearchAction action,
) async {
  final target = resolveNavigation(result, action);

  Navigator.of(context).pop(); // Close search dialog

  if (target.fetchFirst) {
    final entity = await _fetchEntity(result.type, result.id);
    if (entity == null) return;
    context.push(target.path, extra: entity);
    return;
  }

  // Set the tab provider BEFORE navigating so the shell
  // renders the correct tab when it mounts.
  if (target.tabIndex != null) {
    _setShellTab(ref, target.path, target.tabIndex!);
  }

  context.go(target.path);

  if (target.dialog != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openDialog(target.dialog!, target.dialogParams!);
    });
  }
}

/// Maps a GoRouter path to its corresponding tab provider and sets the index.
void _setShellTab(WidgetRef ref, String path, int tabIndex) {
  switch (path) {
    case '/sales':
      ref.read(salesTabProvider.notifier).state = tabIndex;
    case '/purchasing':
      ref.read(purchasingTabProvider.notifier).state = tabIndex;
    case '/production':
      ref.read(productionTabProvider.notifier).state = tabIndex;
    case '/inventory':
      ref.read(inventoryTabProvider.notifier).state = tabIndex;
  }
}
```

##### 5.7.8.5 Resolution Table — Tab Indices by Action

| Entity + Action | Path | Provider | Tab Index | Tab Name |
|---|---|---|---|---|
| `invoice_open` | `/sales` | `salesTabProvider` | `SalesTab.invoices` (0) | Invoices |
| `sales_order_open` | `/sales` | `salesTabProvider` | `SalesTab.salesOrders` (1) | Sales Orders |
| `quotation_open` | `/sales` | `salesTabProvider` | `SalesTab.quotations` (2) | Quotations |
| `purchase_order_open` | `/purchasing` | `purchasingTabProvider` | `PurchasingTab.purchaseOrders` (0) | Purchase Orders |
| `product_open` | `/inventory` | `inventoryTabProvider` | `InventoryTab.items` (0) | Items |
| `warehouse_open` | `/inventory` | `inventoryTabProvider` | `InventoryTab.warehouses` (1) | Warehouses |
| `product_stock_movements` | `/inventory` | `inventoryTabProvider` | `InventoryTab.stockMovements` (2) | Stock Movements |
| `warehouse_view_stock` | `/inventory` | `inventoryTabProvider` | `InventoryTab.stockByWarehouse` (3) | Stock by Warehouse |
| `production_open` | `/production` | `productionTabProvider` | `ProductionTab.productionRuns` (0) | Production |
| `bom_open` | `/production` | `productionTabProvider` | `ProductionTab.bom` (1) | BOM |

##### 5.7.8.6 Why Riverpod Over GlobalKey

| Approach | Pros | Cons |
|---|---|---|
| **Riverpod StateProvider** (recommended) | Consistent with existing architecture; testable; no GlobalKey coupling; works with `ref.read` from anywhere | Requires each shell to be a `ConsumerWidget`/`ConsumerStatefulWidget` (already is) |
| GlobalKey | Simple; no provider needed | Tight coupling; hard to test; requires exposing shell state class; breaks if shell is rebuilt |

The spec mandates **Riverpod StateProvider** for consistency with the existing architecture.

#### 5.7.9 Context Passing — Limitations & Workarounds

| Scenario | Limitation | Workaround |
|---|---|---|
| Create invoice for customer | `SalesInvoiceFormPage` has no `customerId` param | Navigate to `/sales/form`; user selects customer in the form |
| Open product detail | No GoRouter sub-route; uses `showItemDetailDialog()` | Navigate to `/inventory`, invoke dialog with `itemId` |
| Print invoice | `InvoicePrintPreviewPage` requires full `Invoice` object | Fetch invoice from API first, then navigate with `extra: invoice` |
| Open expense | No sub-route; uses `ExpenseFormDialog` | Navigate to `/expenses`, user opens dialog |
| Open payment | No sub-route; uses `PaymentDetailDialog` | Navigate to `/payments`, user opens dialog |
| Open employee | No sub-route; uses `EmployeeDetailDialog` | Navigate to `/hr`, user opens dialog |

For future improvement: screens like `SalesInvoiceFormPage` could accept an optional `customerId` parameter to pre-fill the customer. This is out of scope for the initial implementation.

### 5.8 Entity Icons

```dart
IconData _entityIcon(String type) => switch (type) {
  'customer' => Icons.person,
  'supplier' => Icons.business,
  'product' => Icons.inventory_2,
  'invoice' => Icons.receipt,
  'purchase_order' => Icons.shopping_cart,
  'quotation' => Icons.request_quote,
  'sales_order' => Icons.shopping_bag,
  'payment' => Icons.payments,
  'expense' => Icons.receipt_long,
  'warehouse' => Icons.warehouse,
  'employee' => Icons.badge,
  'production' => Icons.factory,
  'bom' => Icons.view_list,
  'page' => Icons.description,
  'action' => Icons.bolt,
  _ => Icons.help_outline,
};
```

---

## 6. Performance Requirements

| Requirement | Target |
|---|---|
| Debounce delay | 200ms |
| Min query length | 2 characters |
| Max results per entity type | 10 |
| Total max results | ~130 (13 entity types × 10) |
| API response time | < 200ms for typical queries |
| SQLite indexes | Add indexes on searchable fields (name, code, phone, number columns) |
| Query technique | Parameterized LIKE with `%query%` — no table loading into JS |
| N+1 prevention | Single query per entity type with all needed columns, no sub-queries for metadata |

### 6.1 New Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(customer_name);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers(supplier_name);
CREATE INDEX IF NOT EXISTS idx_suppliers_phone ON suppliers(phone);
CREATE INDEX IF NOT EXISTS idx_items_name ON items(item_name);
CREATE INDEX IF NOT EXISTS idx_items_barcode ON items(barcode);
CREATE INDEX IF NOT EXISTS idx_invoices_no ON invoices(invoice_no);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_no ON purchase_orders(po_no);
CREATE INDEX IF NOT EXISTS idx_quotations_no ON quotations(quotation_no);
CREATE INDEX IF NOT EXISTS idx_sales_orders_no ON sales_orders(so_no);
CREATE INDEX IF NOT EXISTS idx_payments_no ON payments(payment_no);
CREATE INDEX IF NOT EXISTS idx_warehouses_name ON warehouses(warehouse_name);
CREATE INDEX IF NOT EXISTS idx_employees_name ON employees(first_name, last_name);
CREATE INDEX IF NOT EXISTS idx_productions_no ON productions(production_no);
CREATE INDEX IF NOT EXISTS idx_boms_no ON boms(bom_no);
```

Add these via a migration file: `server/src/migrations/add-search-indexes.sql`.

---

## 7. Error Handling

### Backend
- Network/database errors → `{ success: false, error: "Search failed" }` (500)
- Invalid query (too short) → `{ success: false, error: "Query must be at least 2 characters" }` (400)
- Unauthorized → 401 via existing `authenticateToken` middleware

### Frontend
- Network failure → Show inline "Connection error. Try again." in the dialog
- Empty results → Show "No results for '{query}'" with suggested actions
- Stale response (user kept typing) → Cancel/ignore via `autoDispose` on the FutureProvider
- Deleted entity between search and action → When action navigates to a screen that can't find the entity, the existing screen's error handling takes over (404 handling already exists in detail screens)

---

## 8. Testing

### 8.1 Backend Tests (`server/src/__tests__/search.test.ts`)

Using **Jest** + **supertest** (matching existing test patterns):

| Test Category | Tests |
|---|---|
| Customer search | By name, by code, by phone, by email |
| Supplier search | By name, by code, by phone |
| Product search | By name, by code, by category |
| Invoice search | By invoice number, by customer name (join) |
| Purchase order search | By PO number |
| Quotation search | By quotation number |
| Sales order search | By SO number |
| Payment search | By payment number |
| Warehouse search | By name, by code |
| Employee search | By name, by employee code |
| Production search | By production number |
| BOM search | By BOM number |
| Page/action search | By title, by keywords |
| Ranking | Exact match before contains, starts-with before contains |
| Actions | Correct actions returned per entity type |
| Permission filtering | Unauthorized actions excluded |
| Empty/too-short query | Returns 400 or empty |
| Limit parameter | Respects custom limit |
| No results | Returns empty array, not error |

### 8.2 Frontend Tests

Minimal widget tests for:
- Search dialog opens on Ctrl+K
- Recent items display when search is empty
- Action panel shows correct actions for selected result

---

## 9. Migration File

New file: `server/src/migrations/add-search-indexes.sql`

Register in `database.ts`:
```typescript
function runSearchIndexesMigration(): void {
  // ... check + exec migration
}
```

---

## 10. Acceptance Criteria

- [ ] `Ctrl+K` opens the search dialog from any screen (desktop)
- [ ] Search icon in AppBar opens the dialog (mobile/web)
- [ ] Typing 2+ characters triggers debounced (200ms) API search
- [ ] Results grouped by entity type, only non-empty groups shown
- [ ] Each result shows icon, title, subtitle with metadata
- [ ] Selecting a result opens the right action panel
- [ ] Actions are filtered by user permissions
- [ ] Clicking an action navigates to the existing screen with correct context (entity ID)
- [ ] Empty search state shows recent items (up to 5) + quick action shortcuts
- [ ] "No results" state shown for empty query results
- [ ] Error state shown for network/server errors (inline in dialog)
- [ ] Stale requests are cancelled when user keeps typing
- [ ] Dialog closes after action navigation
- [ ] Backend: single `/api/search` endpoint with Zod validation
- [ ] Backend: parameterized LIKE queries, no table loading into JS
- [ ] Backend: indexes added for searchable fields
- [ ] Backend: permission-aware action filtering
- [ ] Backend: page/action registry search
- [ ] All existing tests pass
- [ ] New Jest tests added for search

---

## 11. Implementation Phases

### Phase 1: Backend Search Infrastructure
- Create `searchService.ts` with per-entity search functions
- Create `searchController.ts`
- Create `search.ts` route with Zod validation
- Add migration for search indexes
- Register route in `app.ts`

### Phase 2: Backend Entity Searches + Actions
- Implement all 13 entity type searches
- Implement action registry per entity type
- Implement permission filtering
- Implement page/action registry search

### Phase 3: Backend Tests
- Write Jest tests for all search scenarios

### Phase 4: Flutter Search UI
- Create `search_repository.dart`
- Create `search_provider.dart`
- Create `global_search_dialog.dart` with centered modal
- Create `search_result_tile.dart`
- Create `search_action_panel.dart` (right panel)
- Create `recent_items.dart` (SharedPreferences)

### Phase 5: Navigation Integration
- Implement action → route resolution
- Implement entity ID context passing
- Register Ctrl+K shortcut in AppShell
- Add search icon to AppBar

### Phase 6: Polish
- Loading, empty, error states
- Stale request cancellation
- Entity icons and consistent styling
- Mobile responsive layout

---

## 12. What NOT to Do

- Do NOT create new screens — navigate to existing screens only
- Do NOT introduce FTS5 — simple LIKE is sufficient
- Do NOT bypass existing permissions or business rules
- Do NOT create a second database connection
- Do NOT load entire tables into Node.js for searching
- Do NOT use raw SQL string concatenation
- Do NOT add RTL support (LTR only per user decision)
- Do NOT register Ctrl+K in the existing `screen_shortcuts.dart` system
- Do NOT duplicate the page/action registry — backend is the source of truth, Flutter can have a client-side mirror for UI labels only
