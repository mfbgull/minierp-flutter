# MiniERP → Flutter Porting Guide (Desktop Only)

**Scope:** Rebuild the React client as a **desktop Flutter application** against the existing Node/Express/SQLite backend. The backend (`server/`) is NOT ported — it runs unchanged. All business rules (FIFO costing, GL posting, AR aging, report engines, forecasts) stay server-side.

**Explicitly excluded — mobile view and its related things:**
- Compact Card System (`Compact*Card.tsx` components, `<768px` breakpoint logic)
- Mobile wizards: `SalesOrderMobileWizard`, `QuotationMobileWizard`, `PurchaseOrderMobileForm`
- 5-step mobile Invoice Wizard (`pages/invoice/InvoiceWizardPage.tsx` + `InvoiceStep*` — mobile-first flow; desktop invoice creation is the V2 grid, which IS in scope)
- `/mobile-invoices/*` API + `invoice_drafts` table (migration `add-mobile-invoice-tables.sql` stays in the server, just unused)
- `mobile-responsive.css`, PWA `serviceWorker.ts`

**Still in scope (desktop features):** keyboard-driven V2 invoice grid, POS, A4/thermal printing, Urdu RTL, dark mode, customizable dashboard.

---

## 0. Server prerequisites

1. `cd server && npm install && npm run build && npm start` (port 3011, API base `http://localhost:3011/api`). The server is bundled in this kit (`server/`); schema migrations auto-run on first startup.
2. **One required backend change for Flutter:** `POST /auth/login` currently returns the JWT only as an httpOnly cookie. Desktop Flutter has no cookie jar; modify the auth controller to also return `{ success, data: { token, user } }` in the body (cookie can stay for the web client). The auth middleware already accepts `Authorization: Bearer <token>` — no other auth change needed.
3. CSRF: the web client sends an `x-csrf-token` header, but there is no CSRF middleware file in `server/src/middleware/`; with Bearer-header auth CSRF is moot. Verify in `server/src/app.ts` that cookie-only flows don't block Bearer requests.
4. Dev data: a consistent snapshot of the live DB is bundled at `server/database/erp.db` (10 customers, 29 items, real transactions) — this is the server's default DB path (compiled `dist/src/config/database.js` resolves `__dirname/../../../database` → `server/database/`), mirroring the source repo layout, so the server picks it up as-is. For a clean DB instead, bootstrap via `server-reference/SCHEMA_AND_SEED.md`. Default login `admin` / `admin123`.
5. CORS is irrelevant for native desktop HTTP clients (no browser origin enforcement).

## 1. Flutter scaffold & dependencies

```yaml
dependencies:
  flutter_riverpod: ^2            # state (replaces TanStack Query + Contexts)
  go_router: ^14                  # routing (replaces react-router)
  dio: ^5                         # HTTP (replaces axios)
  flutter_secure_storage: ^9      # JWT storage
  shared_preferences: ^2          # localStorage equivalents (user prefs)
  fl_chart: ^0.68                 # charts (replaces chart.js)
  pluto_grid: ^8                  # AG-Grid replacement — see §6
  pdf: ^3                         # A4 invoice/quotation/receipt generation
  printing: ^5                    # print dialog / PDF preview
  qr_flutter: ^4                  # QR codes (POS/receipts)
  intl: ^0.19
  flutter_localizations:          # en + ur
  csv: ^6                         # CSV exports
  file_picker: ^8                 # export save dialogs
  window_manager: ^0.4            # desktop window chrome (optional)
dev_dependencies:
  flutter_lints: ^5
```

Suggested layout (feature-first):

```
lib/
├── main.dart / app.dart
├── core/
│   ├── api/            # dio client, interceptors, endpoint constants
│   ├── auth/           # token storage + AuthNotifier
│   ├── i18n/           # gen-l10n output
│   ├── theme/          # AppTheme (light/dark from DESIGN.md)
│   └── utils/          # formatters (currency/date), error mapping
├── data/
│   ├── models/         # Dart models from types/ (§4)
│   └── repositories/   # one per module, typed from docs/API.md
├── features/           # one folder per module (§5)
└── widgets/            # shared: DataTableShell, FormField, SearchableSelect, StatusBadge, ModalForm, ConfirmDialog, AppToast
```

## 2. Data layer rules

- **Schema source of truth: `server-reference/CURRENT_SCHEMA.sql`** — machine-exact dump of the live DB (59 tables, 153 indexes, 2 views: `vw_customers_with_balance`, `vw_items_with_stock`). Migration history is in `server/src/migrations/` (bundled server) and only matters for the server's bootstrapping.
- **System reference data: `server-reference/SEED_DATA.sql`** — tax rates, payment terms, expense categories, chart of accounts, roles/permissions, seasonal events, company settings. Fresh dev DB = schema + seed in two commands (`server-reference/SCHEMA_AND_SEED.md`).

- Response envelope: `{ success: true, data: … }` or `{ success: false, error: "…" }` (some 401/403/500 paths return bare `{ error }`). Map all to a `ApiResult<T>` sealed type.
- List endpoints share the pattern `page`, `limit`, `search`, `sortBy`, `sortOrder` (`ASC`/`DESC`) — build one `PagedRequest` helper (see `GET /customers`).
- Dates travel as `YYYY-MM-DD` strings; decimals as JSON numbers.
- Dio interceptors: 401 → clear session → login screen (matches `references/utils/api.ts`); 403 → toast the `error` message; network failure → toast.
- Timeout 10s like the web client.
- Rate limits to respect client-side (UX only): login 5/15min, change-password 3/hour, financial reports 10/min.

## 3. Auth & session

- `POST /auth/login` → store token in `flutter_secure_storage`, set as `Authorization: Bearer` on the dio instance; `GET /auth/me` to restore session at startup.
- `POST /auth/logout` (clear token), `POST /auth/change-password`.
- Roles: `admin` vs `user` from the JWT payload (`id, username, email, role`) — gate admin-only UI (users, roles, integrations, invoice/payment delete) and honor 403s.
- App boot: `AuthNotifier` (Riverpod) → splash → login or shell.

## 4. Models — port `types/`

| Kit file | Dart target |
|---|---|
| `types/client-types.ts` (~64 KB, all entities) | `data/models/*.dart` — one class per interface with `fromJson`/`toJson` |
| `types/invoiceV2.ts` | `data/models/invoice_v2.dart` |
| `types/server-types.ts` | response DTOs / request body classes |

Port all fields verbatim (names match API JSON keys). Watch for enums used in the UI: invoice status (`Unpaid, Partially Paid, Paid, Overdue`), PO status (`Draft, Submitted, Partially Received, Completed, Cancelled`), movement type (`PURCHASE, SALE, TRANSFER, PRODUCTION, ADJUSTMENT`), expense status, discount type (`percentage|fixed`), discount scope (`invoice|item`).

## 5. Route map → go_router

Full route inventory from `references/App.tsx` (lazy chunks = one screen each). `mode` prop maps to `go_router` state/path variants (`/create`, `/:id`, `/:id/edit`, `/:id/view`).

| Route path | Flutter screen |
|---|---|
| `/login` | `LoginScreen` |
| `/` | `DashboardScreen` |
| `/inventory/items` `/warehouses` `/stock-movements` `/stock-by-warehouse` `/physical-counts` | `ItemsScreen`, `WarehousesScreen`, `StockMovementScreen`, `StockByWarehouseScreen`, `PhysicalCountsScreen` |
| `/purchases`, `/purchases/returns` | `PurchasesScreen`, `PurchaseReturnHistoryScreen` |
| `/suppliers`, `/suppliers/create`, `/suppliers/:id`, `/suppliers/:id/edit`, `/suppliers/:id/statement` | `SuppliersScreen`, `SupplierFormScreen`, `SupplierDetailScreen`, `SupplierStatementScreen` |
| `/purchase-orders`, `…/create`, `…/:id`, `…/:id/edit` | `PurchaseOrdersScreen`, `PurchaseOrderFormScreen`, `PurchaseOrderDetailScreen` |
| `/bom`, `/production` | `BomScreen`, `ProductionScreen` |
| `/customers`, `/customers/:id`, `/customers/:id/statement` | `CustomersScreen`, `CustomerDetailScreen`, `CustomerStatementScreen` |
| `/sales` | `SalesScreen` (list/returns entry) |
| `/sales/invoice` | `SalesInvoiceScreen` (create) |
| `/sales/invoice/:id`, `…/view`, `…/edit` | `InvoiceDetailScreen` (view/edit modes) |
| `/sales/returns` | `InvoiceReturnHistoryScreen` |
| `/quotations` + create/edit/view | `QuotationsScreen`, `QuotationFormScreen`, `QuotationViewScreen` |
| `/sales-orders` + create/edit/view | `SalesOrdersScreen`, `SalesOrderFormScreen` |
| `/pos` | `PosScreen` |
| `/payments` | `PaymentsScreen` |
| `/expenses` | `ExpensesScreen` |
| `/employees` | `EmployeesScreen` (incl. salary pay modal) |
| `/users`, `/roles` | `UsersScreen`, `RolesScreen` (admin) |
| `/settings` | `SettingsScreen` |
| `/activity-log` | `ActivityLogScreen` |
| `/integrations` | `IntegrationsScreen` (admin) |
| `/reports` + 19 report routes (§11) | `ReportsDashboardScreen` + 19 report screens |
| `/reports/custom`, `/reports/custom/:id/edit` | `CustomReportsScreen`, `ReportBuilderScreen` |
| `/forecasts`, `/forecasts/demand`, `/forecasts/trends`, `/forecasts/accuracy` | `ForecastDashboardScreen`, `DemandForecastScreen`, `ForecastTrendsScreen`, `ForecastAccuracyScreen` |
| `*` | redirect `/` |

Excluded routes: `/invoices/create` (mobile wizard), `/ecosystem` (harness artifact).

## 6. Grid strategy — the hardest 30%

AG-Grid has no Flutter equivalent. Use **PlutoGrid** (editable cells, keyboard nav, sorting/filtering) — closest match; fall back to `DataTable2` for read-only lists.

- **Read-only lists** (items, customers, suppliers, POs, payments, expenses, reports results): PlutoGrid with server-side pagination/sort (`PagedRequest`).
- **Editable grids** (invoice V2 items, PO/quotation/sales-order line items): PlutoGrid in edit mode with:
  - searchable item picker cells (type-ahead → `GET /inventory/items?search=` or the generic `GenericSearchableCell` pattern in `references/components/shared/`)
  - editable cells validating quantity/price/discount (port `references/utils/inputGuard.ts` / `focusCell.ts` behavior)
  - keyboard-driven flow (Enter to confirm, arrows to move, F2 edit — port `references/hooks/useInvoiceV2Keyboard.ts` behavior, 13.6 KB reference)
- **Status cells:** port `references/utils/statusColors.ts` / `ag-grid-status-cells.css` → `StatusBadge` widget (color per status, used across all lists).
- Column definitions: each React page/component defines its columns (`*ColumnDefs` files, `references/components/common/MiniERPGrid.tsx` wrapper) — re-create column order/width/formatting from those files; screenshots in `screenshots/` for reference.

## 7. Calculation logic — port with test parity

Files in `calculations/` are the exact client-side business rules (instant UI feedback; server re-validates). Port 1:1 to `lib/features/<module>/calculations/` and port the `.test.ts` files to Dart tests — keep the same cases (they encode edge behavior).

| Kit file | Purpose | Port to |
|---|---|---|
| `invoiceCalculations.ts` | line totals, tax, discounts (scope/type), invoice totals | `sales/calculations/invoice_calculations.dart` |
| `invoiceLineCalc.ts` | per-line math (quantity × price, discount, tax) | same |
| `invoiceV2Calculations.ts` | V2 grid line calc | same |
| `invoiceRules.ts` | validation rules (negative qty, over-payment, etc.) | same |
| `quotationCalculations.ts` | quotation totals | `sales/calculations/quotation_calculations.dart` |
| `salesOrderCalculations.ts` | sales order totals | `sales/calculations/sales_order_calculations.dart` |
| `customerCalculations.ts` | customer balance/credit-limit logic | `customers/calculations/customer_calculations.dart` |
| `calculations/tests/*.test.ts` | edge cases (tax + discount precedence, rounding) | port as Dart tests |

Server-side engines you do NOT port (reference only — all in `server-reference/`): `entityRegistry.ts` (report builder entity metadata — read to build the field picker), `accountingService.ts` (GL/TB/BS), `reportQueryEngine.ts` (custom report engine), `forecastService.ts` (forecast engine), `Reports.ts` (all 19 predefined report SQL + shapes), `reportsController.ts` (report endpoint params).

## 8. Theming

- `docs/DESIGN.md` = full design system (light + dark palettes, spacing, typography, component styles, 437 lines). Core tokens:

| Role | Light | Dark |
|---|---|---|
| Background | `#FAFBFC` | `#0A0F0D` |
| Surface | `#FFFFFF` | `#111916` |
| Surface elevated | — | `#1A2820` |
| Border | `#E5E7EB` | `#2D3D36` |
| Text primary | `#111827` | `#ECFEED` |
| Text secondary | `#6B7280` | `#86EFAC` |
| Accent (emerald) | `#059669` | `#10B981` |
| Error | `#EF4444` | `#EF4444` |

- `styles/variables.css` = the token source (CSS custom properties) → `ThemeExtension` classes.
- Build `ThemeData` light + dark from these; RTL is automatic (`Directionality` from locale).
- Port `styles/global.css` layout conventions (dense data screens, card panels) to shared widgets.

## 9. i18n — Urdu + English

- `locales/en.arb` (812 keys) and `locales/ur.arb` (764 keys) are ready for `flutter gen-l10n` (flattened camelCase keys). Configure:
  ```yaml
  # l10n.yaml
  arb-dir: lib/l10n
  template-arb-file: en.arb
  output-localization-file: app_localizations.dart
  ```
- `ur.arb` is missing 48 keys vs en — set `untranslated-messages-file` and fall back to en for missing keys (same behavior as the web app).
- Urdu = RTL: verify every screen in both locales (the web app has `rtl.css` fixes; Flutter handles bidi natively but check mixed number/currency rendering).

## 10. Dashboard

- Port `dashboard/dashboardBlockRegistry.ts` → block registry: 16 block types — `SalesPurchasesChart, StockByCategory, LowStockAlerts, RecentActivity, ARSummary, TopCustomers, ForecastSnapshot, SalesSummary, ExpenseSummary, ProductionStatus, StockMovementSummary, KpiGauge, StatCards, CustomText, Deprecated, QuickActions`.
- Data endpoints: `GET /dashboard/summary` (aggregated KPI) + `GET /dashboard/top-customers`, `/sales-summary`, `/expense-summary`, `/production-status`, `/stock-movement-summary`, `/kpi`, `/ar-summary`.
- Layout persistence (port `useDashboardLayout.ts` behavior): `GET /dashboard/layout/active`, `GET /dashboard/layouts`, `POST /dashboard/layout`, `PUT /dashboard/layout/:id`, `PATCH /dashboard/layout/:id/rename`, `POST /dashboard/layout/duplicate`, `PUT /dashboard/layout/:id/activate`, `DELETE /dashboard/layout/:id`. Table `dashboard_layouts` is in `CURRENT_SCHEMA.sql`.
- Drag-drop: `ReorderableListView` / custom drag layer per block; block sizes small/medium/large from `dashboardConstants.ts`.
- Charts: `fl_chart` (line/bar/donut) — chart block components in `references/components/dashboard/blocks/*.tsx` are the visual spec.

## 11. Reports & report builder

**Where the reports actually live** — they are NOT schema (migrations only create `custom_reports` + forecast tables). Every report is computed at request time by server code:

| Report source of truth | Kit file |
|---|---|
| All 19 report SQL queries + exact result shapes (AR aging buckets, P&L, cash flow, DSO, stock valuation, BOM usage, batch traceability, …) | `server-reference/Reports.ts` (979 lines) |
| Endpoint wiring: query params, defaults (e.g. DSO defaults to last 30 days, sales summary to last month), 400s when dates missing | `server-reference/reportsController.ts` |
| GL/accounting reports & trial balance, balance sheet, journal posting rules | `server-reference/accountingService.ts` + `accountingController.ts` |
| Custom report engine (config-driven `executeReport(config)` — not per-report code) | `server-reference/reportQueryEngine.ts` |
| Forecast engine (models, accuracy, seasonal events, safety stock) | `server-reference/forecastService.ts` |
| UI spec per report (columns, filters, chart widgets) | `reports/pages/*.tsx` (19) + `forecasts/*.tsx` (4) |

Porting rule: the Flutter report screens consume these endpoints and render the shapes from `Reports.ts` — do NOT reimplement the SQL.

- 19 report screens, one per endpoint in `docs/API.md` (§Reports): AR aging, customer statements, top debtors, DSO, AR summary, sales summary / by customer / by item, stock level, low stock, stock valuation, inventory movement, P&L, cash flow, purchase summary, supplier analysis, production summary, BOM usage, expenses. All take `from`/`to` date params (see `reportsController.ts` for exact names: `fromDate`/`toDate`/`startDate`/`endDate`/`asOfDate`); render into PlutoGrid + `fl_chart` summary widgets (see each `reports/pages/*.tsx`).
- **Custom report builder** (biggest single feature, `reports/ReportBuilder.jsx` 54 KB + `CustomReportsPage.jsx`): 4-step flow —
  1. Entity picker: `GET /custom-reports/entities`, `GET /custom-reports/entities/:key` (metadata from `server-reference/entityRegistry.ts`)
  2. Field selection + filters
  3. Columns/sort/aggregation config
  4. `POST /custom-reports/run` → result grid
  - Saved reports CRUD: `GET/POST /custom-reports`, `PUT/DELETE /custom-reports/:id`, `POST /custom-reports/:id/duplicate`, templates: `GET/POST /custom-reports/templates`.

## 12. Printing & export

- **A4:** `pdf` package — port `InvoiceTemplateA4` / `QuotationTemplateA4` layouts (`references/components/invoice/`); use `printing` for the native print dialog. Screenshots `invoice-fixed.png` = target layout.
- **Thermal (POS/retail, optional):** `ThermalInvoiceTemplate` + `ThermalPaymentReceipt` (`references/components/invoice/`, `references/components/payment/`) → ESC/POS via network/USB (keep behind an abstraction; can ship A4-only first).
- **CSV export:** `exportUtils.ts` + `ledgerExport.ts` patterns → `csv` package + `file_picker` save dialog (activity log export endpoint exists: `GET /activity-logs/export`).

## 13. Feature notes (behaviors that must match)

- **Invoice create (V2):** header panel (customer, dates, terms, discount scope/type), items grid, payment section (record payment inline), totals panel. `POST /invoices` accepts optional nested payment. Update reverses stock movements server-side.
- **Payments:** multi-invoice allocation (`POST /payments` with `invoice_allocations`), `POST /payments/:id/allocate`.
- **Customer/Supplier detail tabs:** Overview / Invoices / Payments / Ledger (+ POs for suppliers) — port tab structure from `references/components/customer/` and `references/components/suppliers/`.
- **Statements:** date-range statement + current balance (`GET /customers/:id/statement?from&to`).
- **PO flow:** status transitions (`POST /purchase-orders/:id/status`), goods receipts (`GET/POST /purchase-orders/:id/receipts`).
- **Production:** record run against BOM (auto-consumes materials, posts stock + GL).
- **Physical counts:** tables `physical_counts` / `physical_count_items` (in `CURRENT_SCHEMA.sql`) — adjust stock from counted values.
- **Activity log:** filters (user/entity/action/date), stats endpoints, CSV export.
- **Integrations page:** settings CRUD + test actions (email/notification), weather, currency rates/convert, tax calc (admin).
- **Settings:** key-value store (`GET/PUT /settings/:key`, bulk) — document numbering, tax rates, payment terms, company info.

## 14. Verification checklist (Definition of Done)

- [x] Login/logout/change-password; 401 redirect; admin-only screens gated
- [ ] Dashboard renders all 16 block types; layout save/reset/rename/duplicate persists per user
- [ ] CRUD + search/pagination/sort on every list module
- [ ] Invoice V2: keyboard entry, line math matches `calculations/` tests, stock movement + customer ledger updated (verify in server DB)
- [ ] Payment allocation updates invoice `paid_amount`/`balance_amount`
- [ ] PO → goods receipt reduces PO `received_quantity`; status transitions correct
- [ ] Production run consumes BOM materials and creates finished stock
- [ ] All 19 reports + custom report builder run end-to-end
- [ ] Urdu RTL renders correctly across screens; no missing-string crashes
- [ ] A4 invoice print matches `screenshots/invoice-fixed.png` layout
- [ ] Dark/light theme toggle applies to all screens
- [ ] `dart analyze` clean, all ported calculation tests green

## 15. What to copy vs reimplement (recap)

**Copy/port verbatim:** models (types/), validation schemas (schemas/ — zod → Dart validators), calculations + tests, locale strings (locales/), design tokens (DESIGN.md + styles/), API contract (docs/API.md), DB schema (CURRENT_SCHEMA.sql + SEED_DATA.sql).

**Reimplement from spec:** all screens/widgets, state management, grids, charts, printing, dashboard drag-drop, report builder UI.

**Never port:** server logic, mobile view artifacts (§Scope), Electron wrapper, CLI/agent harnesses.
