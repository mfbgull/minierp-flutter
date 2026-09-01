# MiniERP Flutter Codebase — Complete Knowledge Base

> Auto-generated from systematic full-codebase read (336 Dart files, 117,543 LOC).

---

## 1. Project Overview

**MiniERP** is a desktop Flutter ERP application — a port of a React web client against an existing Node/Express/SQLite backend. The backend runs unchanged; all business logic (FIFO costing, GL posting, AR aging, forecasts) stays server-side.

- **Version**: 1.0.0+1
- **Dart SDK**: ^3.12.2
- **336 Dart source files** across `lib/` (117,543 lines)
- **Backend**: Node.js + Express + TypeScript + SQLite (better-sqlite3)
- **Port**: 3011 (API base: `http://localhost:3011/api`)
- **Default login**: `admin` / `admin123`

---

## 2. Architecture

### 2.1 Layer Architecture (Feature-First)

```
lib/
├── main.dart / app.dart              # Entry point, router, providers
├── core/                              # Cross-cutting concerns
│   ├── api/                           # Dio HTTP client, interceptors, endpoints
│   ├── auth/                          # Token storage, AuthNotifier (Riverpod)
│   ├── i18n/                          # gen-l10n output (AppLocalizations)
│   ├── theme/                         # AppTheme (light/dark), border radius, status colors
│   └── utils/                         # Formatters, date math, error mapping, status labels
├── data/
│   ├── models/                        # Dart models (from TypeScript types/)
│   └── repositories/                  # One per module, typed API calls via Dio
├── features/                          # One folder per business module
│   ├── activity_log/                  # Read-only activity log viewer
│   ├── admin/                         # User/role management (admin-only)
│   ├── auth/                          # Login screen
│   ├── customers/                     # Customer CRUD + detail tabs + calculations
│   ├── dashboard/                     # Dashboard with panel blocks
│   ├── employees/                     # Employee management + salary pay
│   ├── expenses/                      # Expense tracking
│   ├── forecasts/                     # Demand forecasting, trends, accuracy
│   ├── integrations/                  # Email, SMS, weather, currency, tax integrations
│   ├── inventory/                     # Items, warehouses, stock movements
│   ├── owner_equity/                  # Owner equity/capital tracking
│   ├── payments/                      # Payment recording & allocation
│   ├── preferences/                   # User preferences (week start, etc.)
│   ├── production/                    # BOM, production runs
│   ├── purchase_orders/               # PO CRUD + goods receipts
│   ├── purchases/                     # Direct purchases + purchase returns
│   ├── quotations/                    # Quotation CRUD + PDF
│   ├── reports/                       # 19 report screens + report builder
│   ├── sales/                         # Invoice CRUD + PDF + returns
│   ├── sales_orders/                  # Sales order CRUD + PDF
│   ├── search/                        # Global search
│   ├── settings/                      # System settings (key-value)
│   ├── shell/                         # App shell (sidebar, topbar, routing)
│   └── suppliers/                     # Supplier CRUD + detail tabs
├── l10n/                              # ARB files for gen-l10n
└── widgets/                           # Shared UI components
```

### 2.2 State Management

- **Riverpod** (`flutter_riverpod: ^2.6.1`) — all state via providers/notifiers
- **Dio** (`dio: ^5.11.0`) — HTTP client with interceptors
- **go_router** (`go_router: ^17.3.0`) — declarative routing

### 2.3 Key Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `go_router` | Routing |
| `dio` | HTTP client |
| `flutter_secure_storage` | JWT token storage |
| `shared_preferences` | User preferences |
| `fl_chart` | Charts (line/bar/donut) |
| `pluto_grid` | Desktop data grids (AG-Grid replacement) |
| `pdf` + `printing` | A4 document generation & print |
| `qr_flutter` | QR codes |
| `intl` | Date/number formatting |
| `csv` | CSV export |
| `file_picker` | File save dialogs |
| `window_manager` | Desktop window management |

---

## 3. Core Layer (`lib/core/`)

### 3.1 API Client (`core/api/`)
- **`api_client.dart`**: Dio instance with interceptors (auth token injection, 401 redirect, error toasting)
- **`endpoints.dart`**: All API endpoint constants organized by module

### 3.2 Auth (`core/auth/`)
- **`auth_notifier.dart`**: Riverpod `AuthNotifier` — login/logout/changePassword, session restore via `GET /auth/me`
- **`session_events.dart`**: Session event bus for cross-widget communication
- **`token_storage.dart`**: JWT storage via `flutter_secure_storage`

### 3.3 Theme (`core/theme/`)
- **`app_theme.dart`**: Light + dark `ThemeData` from DESIGN.md tokens
- **`app_border_radius.dart`**: Border radius constants
- **`status_colors.dart`**: Status → color mapping (Paid=green, Overdue=red, etc.)
- **`theme_mode_provider.dart`**: Theme mode state (follows system)

### 3.4 Utils (`core/utils/`)
- **`formatters.dart`**: Currency, date, number formatting
- **`date_utils.dart`** + **`date_range_math.dart`**: Date range calculations
- **`csv_export.dart`**: CSV generation for exports
- **`ledger_export.dart`**: Ledger-specific CSV export
- **`print_utils.dart`**: Print/PDF helpers
- **`error_mapper.dart`**: API error → user-friendly message mapping
- **Status label helpers**: `invoice_status.dart`, `po_status.dart`, `expense_status.dart`, `purchase_return_status.dart`, `movement_type_label.dart`, `cash_movement_labels.dart`

---

## 4. Data Layer (`lib/data/`)

### 4.1 Models (`data/models/`)
One Dart model per TypeScript interface in `types/client-types.ts`. All have `fromJson`/`toJson` factory constructors. Key models:
- `User`, `Customer`, `Supplier`, `Employee`
- `Item`, `Warehouse`, `StockMovement`, `StockBalance`
- `Invoice`, `InvoiceItem`, `Payment`, `PaymentAllocation`
- `Quotation`, `QuotationItem`
- `SalesOrder`, `SalesOrderItem`
- `PurchaseOrder`, `PurchaseOrderItem`, `GoodsReceipt`
- `BOM`, `BOMItem`
- `Production`, `ProductionInput`
- `Expense`, `ActivityLog`, `Setting`
- `TaxRate`, `Role`, `Permission`

### 4.2 Repositories (`data/repositories/`)
One repository per module. Each wraps Dio calls with typed responses. Pattern:
- `fetchXxxList(PagedRequest)` → `PaginatedResponse<Xxx>`
- `fetchXxxById(id)` → `Xxx`
- `createXxx(data)` → `Xxx`
- `updateXxx(id, data)` → `Xxx`
- `deleteXxx(id)` → `void`

---

## 5. Features — Module Details

### 5.1 Auth (`features/auth/`)
- Login screen with username/password
- JWT token stored in secure storage
- Session restore on app boot
- Admin role gating

### 5.2 Dashboard (`features/dashboard/`)
- 6 KPI stat cards + 5 chart panels (fixed grid)
- `DashboardSummaryProvider` fetches `GET /dashboard/summary`
- Panels: SalesPurchasesChart, StockByCategory, LowStockAlerts, RecentActivity, TopCustomers
- Layout persistence endpoints exist but are unwired

### 5.3 Customers (`features/customers/`)
- List with PlutoGrid (pagination, search, sort)
- Detail screen with tabs: Overview, Invoices, Payments, Ledger
- Customer statement with date range
- Business calculations in `calculations/customer_calculations.dart`

### 5.4 Suppliers (`features/suppliers/`)
- Same pattern as customers
- Detail tabs: Overview, Purchase Orders, Payments, Ledger
- Supplier statement with date range

### 5.5 Inventory (`features/inventory/`)
- Items CRUD with category, UOM, stock levels, pricing
- Warehouses CRUD
- Stock movements (transfer between warehouses)
- Stock by warehouse view
- Physical counts

### 5.6 Sales — Invoices (`features/sales/`)
- **Invoice creation**: header panel (customer, dates, discount scope/type), items grid, payment section, totals panel
- **Invoice detail/view**: read-only view with print, edit, delete actions
- **Invoice edit**: modify existing invoices
- **Returns**: invoice return tracking
- **PDF generation**: A4 invoice print via `pdf` package (`invoice_pdf.dart`)
- **Calculations**: `calculations/invoice_calculations.dart` — line totals, tax, discounts, packed vs loose items
- **Business rules**: `invoice_rules.dart` — validation, payment checks

### 5.7 Quotations (`features/quotations/`)
- CRUD with items grid
- Status workflow: Draft → Sent → Accepted/Rejected/Expired → Converted
- PDF generation: A4 quotation print (`quotation_pdf.dart`)
- Convert to sales order or invoice

### 5.8 Sales Orders (`features/sales_orders/`)
- CRUD with items grid
- Status: Draft → Confirmed → Delivered → Invoiced → Completed
- Source tracking (from quotation or direct)
- PDF generation: A4 sales order print (`sales_order_pdf.dart`)

### 5.9 Purchases (`features/purchases/`)
- Direct purchase recording
- Purchase returns

### 5.10 Purchase Orders (`features/purchase_orders/`)
- CRUD with items grid
- Status: Draft → Submitted → Partially Received → Completed
- Goods receipt tracking (`receive_goods_dialog.dart`)
- Receipt history
- PDF generation: A4 PO print (`purchase_order_pdf.dart`)

### 5.11 Production (`features/production/`)
- BOM (Bill of Materials) management
- Production run recording (consumes BOM materials, creates finished stock)
- Cost calculations (material cost + overhead)

### 5.12 Payments (`features/payments/`)
- Payment recording with multi-invoice allocation
- Payment edit/delete
- Receipt printing

### 5.13 Expenses (`features/expenses/`)
- Expense CRUD with categories
- Status tracking (Approved/Pending/Rejected)

### 5.14 Employees (`features/employees/`)
- Employee CRUD with personal info, bank details, emergency contacts
- Salary management
- Employee documents

### 5.15 Reports (`features/reports/`)
- 19 report screens (AR aging, P&L, cash flow, DSO, stock valuation, etc.)
- Each consumes server-side endpoints
- PlutoGrid for results, fl_chart for visualizations
- **Custom report builder** not yet implemented

### 5.16 Forecasts (`features/forecasts/`)
- Demand forecasting dashboard
- Forecast trends
- Forecast accuracy tracking

### 5.17 Settings (`features/settings/`)
- Key-value settings store
- Company info, currency, date format, decimal places

### 5.18 Admin (`features/admin/`)
- User management (CRUD)
- Role management with permissions
- Admin-only gating

### 5.19 Activity Log (`features/activity_log/`)
- Read-only activity log viewer
- Filters by user, entity, action, date

### 5.20 Integrations (`features/integrations/`)
- Email, SMS, weather, currency, tax integrations
- Settings CRUD + test actions

### 5.21 Owner Equity (`features/owner_equity/`)
- Owner capital/withdrawal tracking

### 5.22 Preferences (`features/preferences/`)
- User preferences (week start day, etc.)

### 5.23 Search (`features/search/`)
- Global search across modules

### 5.24 Shell (`features/shell/`)
- App shell with sidebar navigation
- Top bar with user info, theme toggle
- Route management

---

## 6. Shared Widgets (`lib/widgets/`)

- `StatusBadge` — color-coded status labels
- `SearchableSelect` — type-ahead dropdown for entity selection
- `ConfirmDialog` — confirmation modals
- `AppToast` — toast notifications
- `DataTableShell` — wrapper for PlutoGrid with common config
- `FormField` — styled form inputs
- `ModalForm` — modal form wrapper
- `ScreenToolbar` — screen-level toolbar with actions

---

## 7. Business Calculations (Ported from TypeScript)

All pure functions, no UI dependencies. Located in `lib/features/<module>/calculations/`.

### 7.1 Invoice Calculations
- `calculateItemBase(item)` — qty × rate (or loose amount)
- `calculateItemDiscount(item)` — per-item discount
- `calculateItemTotal(item, discountScope)` — line total with tax
- `calculateSubtotal(items)` — sum of all line bases
- `calculateTax(items, discountScope)` — total tax
- `calculateDiscount(items, discountScope, invoiceDiscount)` — total discount
- `calculateTotal(items, discountScope, invoiceDiscount)` — grand total
- `calcItemLine(input)` — packed vs loose line math
- `applyLineFieldUpdate(item, field, value)` — field update patch
- `getFieldOrder()` / `getNextField()` — keyboard navigation

### 7.2 Quotation Calculations
- Same pattern: `calculateItemTotal`, `calculateSubtotal`, `calculateTax`, `calculateDiscount`, `calculateTotal`

### 7.3 Sales Order Calculations
- Same pattern with `unitPrice` instead of `rate`

### 7.4 Customer Calculations
- `calculateLedgerTotals(ledger, returnedInvoiceNos)` — debit/credit/balance
- `computeCustomerMetrics(invoices, ledger, customer)` — all metrics in one pass
- `calculateCreditUtilization(balance, creditLimit)`
- `calculateOverdueInvoices(invoices)`
- `calculateAverageDaysToPay(invoices)`

---

## 8. Validation (Ported from Zod)

All validation rules ported from `schemas/validation-schemas.ts` to Dart validators.

Key schemas: `customerSchema`, `itemSchema`, `supplierSchema`, `purchaseOrderSchema`, `invoiceSchema`, `bomSchema`, `productionSchema`, `expenseSchema`, `settingsSchema`

---

## 9. i18n

- **Template**: `en.arb` (812 keys)
- **Urdu**: `ur.arb` (764 keys — 48 missing, falls back to English)
- **Config**: `l10n.yaml` → `flutter gen-l10n`
- **Output**: `AppLocalizations` class
- **RTL**: Urdu = RTL, handled natively by Flutter

---

## 10. Design System

- **Light mode**: `#FAFBFC` background, `#FFFFFF` surface, `#059669` accent (emerald)
- **Dark mode**: `#0A0F0D` background, `#111916` surface, `#10B981` accent
- **Typography**: Inter (headings/body), JetBrains Mono (numbers)
- **Spacing**: 4px base scale
- **Components**: Buttons, cards, inputs, tables, modals, badges

---

## 11. API Contract

- **Base URL**: `http://localhost:3011/api`
- **Auth**: JWT Bearer token (stored in secure storage)
- **Response envelope**: `{ success: true, data: ... }` or `{ success: false, error: "..." }`
- **Pagination**: `page`, `limit`, `search`, `sortBy`, `sortOrder` (ASC/DESC)
- **Dates**: `YYYY-MM-DD` strings
- **Timeout**: 10 seconds

---

## 12. Database

- **SQLite** with WAL mode
- **59 tables**, 153 indexes, 2 views
- **Schema source**: `server-reference/CURRENT_SCHEMA.sql`
- **Seed data**: `server-reference/SEED_DATA.sql`
- Key tables: `users`, `customers`, `suppliers`, `items`, `warehouses`, `invoices`, `invoice_items`, `payments`, `payment_allocations`, `purchase_orders`, `purchase_order_items`, `stock_movements`, `stock_balances`, `boms`, `bom_items`, `productions`, `production_inputs`, `expenses`, `employees`, `settings`, `activity_log`

---

## 13. Remaining Gaps (Priority Order)

1. **Custom report builder** — 4-step flow (entity picker → fields → columns → run)
2. **Dashboard block system** — 16 block types + layout save/reset/rename/duplicate
3. **Thermal (POS) printing** — ESC/POS for receipt printers
4. **POS screen** — Point of Sale interface
5. **Minor UX** — In-app locale switcher, dark/light theme toggle in Settings

---

## 14. Testing

- **29 test files** in `test/`
- Tests cover: calculations (invoice, quotation, SO, customer, production), core utils, widgets, features (dashboard, preferences, purchase orders, quotations, reports, sales)
- **494/494 tests passing** (as of 2026-08-10)
- `dart analyze` clean (0 issues)

---

## 15. Key Patterns

1. **Repository pattern**: One repo per module, wraps Dio calls
2. **Provider pattern**: Riverpod providers for all state
3. **Feature-first organization**: Each module self-contained
4. **Calculation separation**: Business math in pure functions, no UI deps
5. **Grid strategy**: PlutoGrid for editable grids, DataTable2 for read-only
6. **PDF generation**: `pdf` package for A4 documents, `printing` for native print dialog
7. **Status-driven UI**: Status colors/badges used consistently across modules
8. **Paged requests**: Shared `PagedRequest` helper for all list endpoints
