# MiniERP

Desktop ERP for small and medium businesses. Built with Flutter, running against a Node.js + Express + SQLite backend.

## Current State

MiniERP is a mature, production-ready desktop ERP application. The Flutter client covers the full business workflow — from inventory and purchasing through sales, production, accounting reports, and forecasts. The backend runs unchanged; all business logic (FIFO costing, GL posting, AR aging, forecasts) stays server-side.

## Tech Stack

| Layer | Technologies |
|-------|--------------|
| Frontend | Flutter, Riverpod, Dio, go_router, PlutoGrid, pdf, printing |
| Backend | Node.js, Express, TypeScript, SQLite (better-sqlite3) |
| Desktop | Windows, macOS, Linux (single codebase) |
| Auth | JWT (Bearer token), role-based access (admin / user) |

## Quick Start

### Backend

```bash
cd server
npm install
npm run build
npm start
```

The server starts on port **3011** (`http://localhost:3011/api`). It auto-runs migrations on first startup and ships with a seeded development database.

Default login: **admin** / **admin123**

### Frontend

```bash
flutter pub get
flutter run -d linux   # or -d windows, -d macos, -d chrome
```

## Modules

| Module | Capabilities |
|--------|--------------|
| **Dashboard** | KPI cards, sales/purchases charts, stock by category, low stock alerts, recent activity, top customers |
| **Inventory** | Items, warehouses, stock movements, stock by warehouse, physical counts, batch management |
| **Customers** | CRUD, detail tabs (overview, invoices, payments, ledger, statement), credit-limit tracking |
| **Suppliers** | CRUD, detail tabs (overview, purchase orders, payments, ledger, statement) |
| **Sales** | Invoices (V2 keyboard-driven grid), returns, quotations, sales orders, POS checkout |
| **Purchases** | Direct purchases, purchase returns |
| **Purchase Orders** | CRUD, goods receipts, receipt history, status transitions |
| **Production** | BOM management, production runs (auto-consumes materials, creates finished stock) |
| **Payments** | Payment recording, multi-invoice allocation, payment history |
| **Expenses** | Expense tracking by category, status workflow |
| **Employees** | Employee records, salary payments, employee loans |
| **Reports** | 19 financial and operational reports (AR aging, P&L, cash flow, DSO, trial balance, stock valuation, etc.) |
| **Forecasts** | Demand forecasting dashboard, trends, accuracy tracking |
| **Admin** | User management, role management with permissions (admin-only) |
| **Activity Log** | Read-only audit trail with filters |
| **Integrations** | Email, SMS, weather, currency rates, tax calculations (admin-only) |
| **Owner Equity** | Owner capital, withdrawals, personal loans |
| **Settings** | Company info, document numbering, system preferences |
| **Search** | Global search across all modules (Ctrl+K) |

## Key Features

### Printing & Export
- **A4 documents**: Invoices, quotations, sales orders, purchase orders — native PDF via `pdf` + `printing`
- **Thermal receipts**: POS thermal receipt PDF (80mm roll-paper layout with QR code)
- **CSV export**: Activity log and ledger exports

### Internationalization
- **English** + **Urdu** (full RTL support)
- In-app locale switcher
- `flutter gen-l10n` with ARB source files

### Theme
- Light and dark modes (emerald professional palette)
- System-aware theme toggle with persistent preference
- High-contrast, data-dense layout optimized for 8-hour work sessions

### Architecture
- **State**: Riverpod providers / notifiers
- **HTTP**: Dio with interceptors (auth injection, 401 redirect, error mapping)
- **Routing**: go_router with `StatefulShellRoute` (branch state preserved)
- **Grids**: PlutoGrid for editable lists, shared `DataTableShell` for read-only tables
- **Calculations**: Pure functions ported from the original TypeScript client, covered by tests
- **Models**: Typed Dart models with `fromJson`/`toJson` for every API shape

## Testing & Quality

- **494/494 tests passing** (calculations, widgets, features)
- `dart analyze` clean (0 issues)
- **CI**: GitHub Actions runs `flutter analyze`, `flutter test`, server `typecheck`, `eslint`, and `npm test` on every push

## Data

- SQLite with WAL mode
- 59 tables, 153 indexes, 2 views
- FIFO batch costing, stock movement ledger, double-entry GL posting
- Nightly automated backups with retention (7 daily + 4 weekly)

## Remaining Work

1. **Custom report builder** — 4-step flow (entity picker, fields, columns, run); endpoints and l10n ready, UI not started
2. **Dashboard layout persistence** — 16 block types + save/reset/rename/duplicate; catalog wired, layout endpoints exist but are unwired
3. **ESC/POS direct printing** — thermal receipt PDF is shipped; direct ESC/POS network/USB driver pending

## Project Structure

```
lib/
├── main.dart / app.dart          # Entry point, router, providers
├── core/                         # Cross-cutting: API, auth, theme, i18n, utils
├── data/
│   ├── models/                   # Dart models
│   └── repositories/             # API clients per module
├── features/                     # One folder per business module (18 modules)
└── widgets/                      # Shared UI components
```

## License

MIT
