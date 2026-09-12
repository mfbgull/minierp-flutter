# MiniERP

[![CI](https://github.com/mfbgull/minierp-flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/mfbgull/minierp-flutter/actions/workflows/ci.yml)

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
- **CI**: GitHub Actions runs two jobs on every push:
  - **flutter** — `flutter pub get`, `flutter analyze` (0-issue gate), `flutter test`
  - **server** — `typecheck`, `eslint` (zero errors gate), `npm test` (jest), and the reversal-rules verification gate (`npm run verify:reversal-rules`, 81-case C1–C8 invariants)

  Job outcomes appear as the CI badge above; failing job logs include the exact step that broke the gate.

## Data

- SQLite with WAL mode
- 59 tables, 153 indexes, 2 views
- FIFO batch costing, stock movement ledger, double-entry GL posting
- Nightly automated backups with retention (7 daily + 4 weekly) — see [Backup & Restore](#backup--restore)

## Backup & Restore

Disaster-recovery procedures. DR-01 = take backups, DR-02 = prove they are restorable.

### When backups happen

| Trigger | Mechanism | Retention |
|---------|-----------|-----------|
| Server runtime | `backupService` in-process timer — nightly, and fires on boot if the last backup is > 24h old. Runs `wal_checkpoint(TRUNCATE)` then `VACUUM INTO` for a consistent snapshot, `integrity_check` on the copy. | 7 daily + 4 weekly |
| Manual (admin UI / API) | `POST /api/admin/backup` (permission `admin:create`); list via `GET /api/admin/backup`, download `GET /api/admin/backup/:name/download`, delete `DELETE /api/admin/backup/:name`. Path-traversal-guarded. | managed by service |
| Manual (CLI) | `npm run db:backup` from `server/` — `better-sqlite3` `db.backup()` page-by-page snapshot, safe while the server holds the DB open in WAL mode. Keeps newest 30. | 30 snapshots |
| CI (scheduled) | `nightly-backup.yml` runs daily 03:00 UTC: fresh seeded DB → backup → restore verification. Fails loudly if backups stop being restorable. | — |

Snapshots live in `<db-dir>/backups/` as `erp-backup-<timestamp>.db` (CLI) or `erp-<timestamp>.db` (service).

### Verify a backup before relying on it (DR-02)

```bash
cd server
node scripts/verify-backup.js database/backups/<snapshot>.db
```

Copies the snapshot to a temp path (the original is never touched) and checks: `PRAGMA integrity_check`, core schema tables present, GL balanced per reference group (`journal_lines` debit == credit), and `stock_balances` == Σ batch layers. Exit 0 = restorable and internally consistent.

```bash
node scripts/restore-smoke.js database/backups/<snapshot>.db
```

Opens a restored copy and reads core row counts — proves the snapshot opens as a working database with expected content (fails if `users` is empty).

### Restore procedure

1. **Stop the server** (or point `DATABASE_PATH` at a new directory for a side-by-side restore).
2. **Verify the snapshot** you intend to restore (both scripts above — never restore an unverified backup).
3. **Copy the snapshot over the live path** (default `server/database/erp.db`):
   ```bash
   cp <snapshot>.db server/database/erp.db
   rm -f server/database/erp.db-wal server/database/erp.db-shm   # stale WAL sidecars
   ```
   If restoring side-by-side instead, set `DATABASE_PATH=/path/to/restore-dir` before starting.
4. **Start the server.** Migrations auto-apply (idempotent), so an older snapshot is brought up to the current schema on boot.
5. **Post-restore checks**: log in and confirm dashboard totals; spot-check a recent invoice in the ledger; re-run `node scripts/verify-backup.js server/database/erp.db` against the restored live file (read-only).

**Recovery point**: worst case with default retention is ~24h of data loss (last nightly snapshot) — take a manual `POST /api/admin/backup` before risky operations such as migrations or bulk imports.

**Testing your DR plan**: the nightly CI workflow exercises backup → verify → restore smoke against a fresh DB every day, so the chain is continuously proven — but you should still rehearse the full restore procedure on a non-production machine periodically.

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
