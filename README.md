# MiniERP → Flutter Migration Kit

Reference package for rebuilding the MiniERP client as a **desktop Flutter app** against the existing Node/Express/SQLite backend. Mobile view and related artifacts are deliberately excluded — see `PORTING.md` §Scope.

## Contents

| Path | What it is |
|---|---|
| `PORTING.md` | **Start here.** Full port spec: scaffold, route map, module matrix, grid strategy, calculations, theming, i18n, printing, verification checklist |
| `docs/API.md` | Complete REST API contract (~100 endpoints, payloads, errors) |
| `docs/DATABASE.md` | Full SQLite schema + indexes + document-number sequences |
| `docs/DESIGN.md` | Design system: light/dark palettes, typography, component specs (437 lines) |
| `docs/minierp-architecture.drawio` | Architecture diagram (draw.io) |
| `docs/README.md` | Original project README (features, modules, CLI) |
| `server-reference/CURRENT_SCHEMA.sql` | **Machine-exact dump of the live DB — the current state (59 tables, 153 indexes, 2 views). Use this as the Flutter data-layer source of truth** |
| `server-reference/SEED_DATA.sql` | **System reference data: 5 tax rates, 8 payment terms, 15 expense categories, 17 chart-of-accounts, 4 roles, 80 permissions + 116 grants, 5 seasonal events, 46 settings. Idempotent.** |
| `server-reference/SCHEMA_AND_SEED.md` | How to bootstrap a fresh dev DB in two commands |
| `server/` | **The full backend, bundled and runnable** (Express + SQLite, all migrations/controllers/services) — the Flutter app runs against this |
| `server/database/erp.db` | **Consistent snapshot of the live DB** (10 customers, 29 items, real transactions) — at the server's default DB path, so the bundled server runs with real data immediately |
| `references/` | Client spec files PORTING.md points at: App routes, api client, keyboard hook, grid cells, invoice/print templates, dashboard blocks, detail tabs (68 files) |
| `server-reference/Reports.ts` | **All 19 report SQL queries + result shapes** (AR aging, P&L, cash flow, …) |
| `server-reference/reportsController.ts` | Report endpoint params/defaults |
| `server-reference/reportQueryEngine.ts` | Custom report engine (config-driven) |
| `server-reference/accountingService.ts` + `accountingController.ts` | GL: trial balance, balance sheet, journal posting |
| `server-reference/forecastService.ts` | Forecast engine (models, accuracy, safety stock) |
| `server-reference/entityRegistry.ts` | Report-builder entity metadata (server-side, read-only reference) |
| `types/client-types.ts`, `types/invoiceV2.ts`, `types/server-types.ts` | All entity/response types → Dart models |
| `schemas/validation-schemas.ts` | Zod validation → Dart validators |
| `calculations/*.ts` + `calculations/tests/` | Client-side business math to port 1:1 with test parity |
| `locales/en.json`, `ur.json` | Source locale files (nested) |
| `locales/en.arb`, `ur.arb` | Flattened, gen-l10n-ready (812 / 764 keys) |
| `dashboard/` | Block registry, constants, layout persistence hook (React reference) |
| `reports/` | Custom report builder UI (54 KB JSX — the hardest feature) + `pages/` with all 19 report page specs |
| `forecasts/` | 4 forecast page specs (dashboard, demand, trends, accuracy) |
| `styles/` | Design tokens (variables.css), global, RTL, AG-Grid status-cell styling |
| `export-utils/` | CSV/ledger export logic reference |
| `screenshots/` | Login, menu, invoice A4, header, current-page — visual targets |
| `AGENTS.md` | Project rule engine spec (port to the Flutter repo's AGENTS.md) |

## Quick start for the Flutter project

1. Read `PORTING.md` fully.
2. Run the bundled server: `cd server && npm install && npm run build && npm start` (port 3011).
3. Apply the one auth tweak (return JWT in login response body) — `PORTING.md` §0.
4. Scaffold `flutter create` + dependencies from `PORTING.md` §1.
5. Port in this order: models → api/repositories → auth → theme → shell/layout → dashboard → inventory → sales (invoice V2) → everything else.

## Not included

- `server/node_modules` + `server/dist` — run `npm install && npm run build` once (155 MB of deps not worth shipping)
- Any mobile-view artifacts (compact cards, mobile wizards, `/mobile-invoices`, invoice_drafts)
- Git history, Electron wrapper, CLI/agent harnesses
