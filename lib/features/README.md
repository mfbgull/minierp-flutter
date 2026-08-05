# Features (one folder per module)

Module map — each folder is created and filled during its porting step
(PORTING.md §5 route inventory). Calculations from the kit's
`calculations/` are ported 1:1 into `lib/features/<module>/calculations/`
with test parity (PORTING.md §7).

| Folder | Module (routes) |
|---|---|
| `auth/` | `/login` — LoginScreen (AuthNotifier wired: login/restore/logout) + SplashScreen |
| `dashboard/` | `/` — DashboardScreen placeholder (16 block types) |
| `inventory/` | items, warehouses, stock-movements, stock-by-warehouse, physical-counts |
| `purchases/` | purchases, purchase returns |
| `suppliers/` | suppliers CRUD + statement |
| `purchase_orders/` | PO CRUD + receipts |
| `production/` | BOM, production runs |
| `customers/` | customers CRUD + statement |
| `sales/` | sales list, invoice (V2 grid primary), returns, quotations, sales orders, POS |
| `payments/` | payments + multi-invoice allocation |
| `expenses/` | expenses |
| `employees/` | employees + salary pay |
| `admin/` | users, roles (admin-gated) |
| `settings/` | settings key-value store |
| `activity_log/` | activity log + export |
| `integrations/` | integrations (admin) |
| `reports/` | 19 report screens + custom report builder |
| `forecasts/` | forecast dashboard, demand, trends, accuracy |

Suggested porting order (README §Quick start):
models → api/repositories → auth → theme → shell/layout → dashboard →
inventory → sales (invoice V2) → everything else.
