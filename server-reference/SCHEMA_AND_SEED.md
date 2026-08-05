# Bootstrap a fresh dev database in two commands

Builds a database identical (for system/reference data) to the live `database/erp.db`:

```bash
sqlite3 erp.db < CURRENT_SCHEMA.sql
sqlite3 erp.db < SEED_DATA.sql
```

Or in Node (what the Flutter dev is likely to use):

```js
const db = require('better-sqlite3')('erp.db');
db.exec(require('fs').readFileSync('CURRENT_SCHEMA.sql', 'utf8'));
db.exec(require('fs').readFileSync('SEED_DATA.sql', 'utf8'));
```

## What you get

| Table | Rows | Notes |
|---|---|---|
| `tax_rates` | 5 | No Tax, GST 5/10/15%, VAT 20% |
| `payment_terms` | 8 | Due on Receipt, Net 7…Net 90 |
| `expense_categories` | 15 | Office Supplies … Other |
| `chart_of_accounts` | 17 | Cash → Inventory Shrinkage (17, not 14 — the GL migration seeds 17) |
| `roles` | 4 | Admin (all 80 permissions), User (36 read-only), + 2 test roles (Test Role 2, Manager) |
| `permissions` | 80 | Same set the server seeds in `database.ts` |
| `role_permissions` | 116 | Admin=80, User=36, test roles=0 |
| `forecast_seasonal_events` | 5 | New Year, Eid ×2, Black Friday, Back to School (recurring) |
| `settings` | 46 | Email/SMS providers, weather, company info, invoice numbering |

## Notes

- Both files are idempotent (`INSERT OR IGNORE`) — safe to re-run against a populated DB.
- **Transactional data is NOT included** (items, customers, invoices, stock, employees, conversations…). A consistent full snapshot is bundled at `server/database/erp.db` (kit's server folder — the server's default DB path, taken via `VACUUM INTO`; it runs as-is).
- Verified 2026-08-03: applying both files to an empty DB reproduces the live DB's system tables exactly (source: `server/database/erp.db`, the DB the running server uses).
- No default admin user is seeded (the dev login `admin`/`admin123` is created by the server on startup — `database.ts`).
