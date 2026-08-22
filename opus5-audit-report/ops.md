# AUDIT: MIGRATIONS · AUDIT TRAIL · BACKUP/DR · TESTING · PERFORMANCE

All paths absolute. All DB inspection done on a copy at `/tmp/dbaudit/` (original untouched). No repo file was modified.

---

## LEAD ANSWERS (the two you flagged highest-priority)

### ✅ PART A item 5 — `foreign_keys` IS correctly ON. This is NOT a finding.

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/config/database.ts:19-33`
```ts
const db = new Database(dbPath, {...});
db.pragma('foreign_keys = ON');      // :24
db.pragma('journal_mode = WAL');     // :27
db.pragma('synchronous = NORMAL');   // :30
db.pragma('busy_timeout = 5000');    // :33
```
There is **exactly one** long-lived `new Database()` in the serving process (`grep "new Database("` → only `database.ts:19`; the others are `audit-trace.ts:41`, three `src/scripts/*`, and four `:memory:` tests). I confirmed the SQLite default is OFF (`PRAGMA foreign_keys` on a fresh connection to the live DB returns `0`), so line 24 is load-bearing and present. `busy_timeout` and `synchronous` are also set. **Empirical proof it works: `PRAGMA foreign_key_check` on the live DB returns 0 violations and `PRAGMA integrity_check` = `ok`.** The FK declarations are real, not decorative. Do not change this.

The real hole is narrower and worse (see **MIG-02** and **AUD-06**): the GL↔document link is *deliberately not* an FK, so FK enforcement cannot protect the ledger from hard deletes — and it hasn't.

### 🔴 PART C — There is NO backup. Not "a weak backup". None.

Zero hits repo-wide for `VACUUM INTO`, `.backup(`, `sqlite3_backup`, `integrity_check`, or any backup route/UI/job. The only `wal_checkpoint` in the codebase is in a release-packaging shell script. `ActionType.BACKUP_CREATE` exists as a dead enum member (`activityLogger.ts:95`) — aspiration, no implementation. Details in **DR-01 … DR-06**.

---

## PART A — MIGRATIONS & SCHEMA EVOLUTION

### MIG-01 — Migration tracking is *schema introspection*, not a ledger — P1
**Mechanism (this is the answer to your key question).** There is no tracking table and `user_version = 0` (confirmed). Instead, `database.ts` contains **47 hand-written runner functions**, invoked as **45 bare calls at module load** (`database.ts:1042-1086`), each guarding itself by *asking the schema whether the change is already there*:

```ts
// database.ts:112-117 — pattern A: does the column exist?
const columnCheck = db.prepare(`
  SELECT COUNT(*) as count FROM pragma_table_info('invoices')
  WHERE name='discount_scope'
`).get() as { count: number };
if (columnCheck.count === 0) { ...db.exec(migrationSQL); }
```
```ts
// database.ts:480-485 — pattern B: does the table exist?
const tableCheck = db.prepare(`
  SELECT name FROM sqlite_master WHERE type='table' AND name='purchase_returns'
`).get();
if (!tableCheck) { ...db.exec(migrationSQL); }
```
```ts
// database.ts:927-932 — pattern C: does a sentinel index exist?
SELECT COUNT(*) as count FROM sqlite_master WHERE type='index' AND name='idx_items_category'
```
Plus **pattern D — no guard at all**: `runGLFoundationMigration` (`:1406`), `runCashAccountsMigration` (`:1833`), `runOpeningBalancesMigration` (`:1848`) `db.exec()` an entire `.sql` file on **every single boot**, relying on `CREATE IF NOT EXISTS` / `INSERT OR IGNORE`.

And **every one of the 47 is wrapped in `catch (error: any) { logger.error(...) }`** — 52 such blocks in the file. Nothing gates startup on migration success.

*Why it matters:* the guard is a *proxy* for "did this migration run", not a record of it. When the proxy and the migration body diverge, the migration either never runs or runs forever. Both failure modes are live in this codebase (MIG-03, MIG-04). Any migration that half-applies leaves the DB structurally wrong, logs one line, and **the server starts and serves requests anyway.**

*Can a migration run twice / be skipped / partially apply?* **All three. Yes, yes, and yes** — proven below.

*Fix:* add `schema_migrations(filename TEXT PRIMARY KEY, applied_at, checksum)`; wrap each file in `db.transaction()`; **fail startup loudly** on any migration error. Backfill the table from the current schema once. **Migration needed: yes.**

---

### MIG-02 — 🔴 A migration silently destroys `payments.invoice_id`, and can leave FK enforcement OFF process-wide — P0
`database.ts:757-797` (duplicated verbatim in `server/src/migrations/add-supplier-payment-support.sql:26-43`):
```ts
db.exec(`
  PRAGMA foreign_keys=OFF;
  BEGIN TRANSACTION;
  CREATE TABLE payments_new ( ... invoice_id INTEGER, ...
      FOREIGN KEY (invoice_id) REFERENCES invoices(id), ... );
  INSERT INTO payments_new (id, payment_no, customer_id, supplier_id, payment_date,
        amount, payment_method, reference_no, notes, created_by, created_at)
    SELECT id, payment_no, customer_id, supplier_id, payment_date,
        amount, payment_method, reference_no, notes, created_by, created_at FROM payments;
  DROP TABLE payments;
  ALTER TABLE payments_new RENAME TO payments;
  COMMIT;
  PRAGMA foreign_keys=ON;
`);
```
**Two P0 defects in twelve lines:**

1. **`invoice_id` is declared in the new table and in its FK, but is absent from both the INSERT column list and the SELECT.** Then `DROP TABLE payments`. Every existing payment→invoice linkage is **silently discarded, unrecoverably**, the first time this runs on a real DB. FKs are off, so nothing objects. This is the only table-rebuild in the codebase and it touches money.
2. **`PRAGMA foreign_keys=ON` is only reached on the happy path.** If any statement raises (e.g. the `DROP TABLE` hits a lock), the `catch` at `:798` swallows it and **`foreign_keys` stays OFF for the entire remaining lifetime of the process** — every subsequent write in that boot runs unprotected. The one pragma keeping the FK graph honest is disarmed by a swallowed exception.

*Failure scenario:* upgrade an installation whose `payments` still has `customer_id NOT NULL`. Boot 1: linkages vanish; if the rebuild throws midway, the server comes up with FKs off and serves an entire business day writing unvalidated rows.
*Fix:* add `invoice_id` to both lists; move the pragma restore into a `finally`; wrap in `db.transaction()` (better-sqlite3 restores pragma/tx state properly) and re-assert `db.pragma('foreign_keys')===1` after. **Migration needed: yes — plus a data-recovery pass for any DB that already ran it.**

---

### MIG-03 — 🔴 A migration re-executes on *every* boot, twice per boot — P1
`runMissingFKIndexesMigration` guards on `idx_invoices_so_id`:
```ts
// database.ts:975-978
SELECT COUNT(*) as count FROM sqlite_master WHERE type='index' AND name='idx_invoices_so_id'
```
**`server/src/migrations/add-missing-fk-indexes.sql` never creates that index** (grep: the file's invoice lines are `idx_invoices_customer_id` at `:5` and `ANALYZE invoices;` at `:40`). I confirmed `idx_invoices_so_id` does not exist in the live DB. So the guard is permanently false and the file re-executes forever — and it is **called twice** in the boot sequence:
```
database.ts:1063  runMissingFKIndexesMigration();
database.ts:1069  runMissingFKIndexesMigration();   // ← same function, again
```
That is **2 full `ANALYZE invoices` + 20-odd `CREATE INDEX IF NOT EXISTS` on every start**. Harmless today at 6 invoices; at 100k invoices it is two full-table ANALYZE scans added to every boot. It is also the definitive proof that MIG-01's mechanism cannot tell "already applied" from "not applied". *Fix:* delete line 1069; point the guard at an index the file actually creates. **Migration needed: no.**

---

### MIG-04 — 🔴 The performance-index migration is permanently DEAD, and would crash if it ever ran — P1
```ts
// database.ts:927-932
WHERE type='index' AND name='idx_items_category'
```
`init.sql:367` already creates `idx_items_category`, and `init.sql` runs first (`database.ts:53`). I confirmed the index exists in the live DB → **`add-performance-indexes.sql` has never run and never will.** Its `ANALYZE;` (line 73) never runs either, so planner statistics go permanently stale.

Worse, the file is *broken*: `:54 purchase_orders(order_date)` (real column is `po_date`), `:57 productions(status)`, `:62 expenses(category_id)` — non-existent columns. `db.exec` aborts on the first bad statement, so even a corrected guard yields a **partially applied** index set. `add-search-indexes.sql` (24 indexes) is referenced by **no code whatsoever**.

Consequence measured on the live schema: **`invoice_items` has ZERO indexes** — see PERF-01. *Fix:* repair the three column names, re-point the guard, wire up `add-search-indexes.sql`. **Migration needed: yes.**

---

### MIG-05 — 🔴 Boot performs 14 classes of unconditional DATA MUTATION on production data — P0
Confirmed and expanded well beyond the 192-223 range. Every item below runs on **every** server start, inside a `try/catch` that swallows failure, **not** inside a transaction:

| # | `database.ts` | Mutation | Idempotent? | Destructive? |
|---|---|---|---|---|
| 1 | `:194-196` | `UPDATE invoices/payments SET customer_id = CAST(customer_id AS INTEGER)` | yes | no |
| 2 | `:201` | `UPDATE invoices SET returned_amount = total_amount WHERE returned_amount > total_amount` | yes | **yes — clamps silently, destroys evidence of the over-return bug** |
| 3 | `:202-214` | `UPDATE invoices SET paid_amount = SUM(payment_allocations), balance_amount = MAX(0, …)` — **ALL rows, no WHERE** | yes | **yes** |
| 4 | `:216-222` | 5× `UPDATE invoices SET status = …` — all rows | yes | **yes** |
| 5 | `:227-246` | `stock_balances` recomputed from `stock_movements`; UPDATE or INSERT per (item,warehouse) — **N+1 loop** | yes | yes |
| 6 | `:248-262` | `DELETE FROM stock_balances` for rows with no movements | yes | **yes — hard delete** |
| 7 | `:267-273` | `UPDATE items SET current_stock = SUM(stock_balances)` — all rows | yes | yes |
| 8 | `:277-305` | `UPDATE customer_ledger SET description` — regex-rewrites ledger narration, **N+1 loop** | mostly | **yes — mutates ledger text** |
| 9 | `:613` | `DROP TABLE IF EXISTS sales` — **unconditional, every boot** | yes | **yes** |
| 10 | `:838-846` | `UPDATE suppliers SET current_balance = (latest supplier_ledger.balance)` — all rows | yes | yes |
| 11 | `:1152` → `:1299-1329` | `seedDefaultPermissions()` — "**Always seed**"; re-grants all 83 permissions to Admin and all read perms to User | yes | **yes — see MIG-06** |
| 12 | `:1406` | `db.exec(add-gl-foundation.sql)` whole file, no guard | mostly | **see MIG-07** |
| 13 | `:1879-1962` | `runUnbatchedStockReconciliation` — INSERTs synthetic `BATCH-yy-RECON-nnnn` cost layers | **NO — burns a sequence** | yes |
| 14 | `:1990-2019` | `runOrphanedBatchCleanup` — `DELETE FROM stock_batches WHERE unit_cost <= 0 OR quantity_original <= 0`, after nulling `stock_movements.batch_id` | yes | **yes — hard-deletes cost layers** |

**The worst is #3 combined with the parallel audit's finding that invoices are hard-deleted.** `paid_amount`/`balance_amount`/`status` — three of the most consequential numbers in the system — are **not authoritative persisted state; they are derived and rewritten from `payment_allocations` on every boot.** Any correct value that disagrees with `SUM(payment_allocations)` is destroyed at next restart. There is no dry-run, no report of what changed, no backup, and **no audit-log row** (AUD-01). A restart is a silent write transaction against the general ledger's feeder tables.

**Ordering hazard #13 → #14:** `runUnbatchedStockReconciliation` (`:1085`) runs immediately before `runOrphanedBatchCleanup` (`:1086`). If an item's inbound movements and `standard_cost` are both 0, #13 creates a batch with `unit_cost = 0` and #14 deletes it in the same boot — while `getNextSequenceNumber(db,'BATCH_RECON_last_no')` (`:1941`) has already incremented. *Currently latent:* live `BATCH_RECON_last_no = 1`, so no churn is occurring — but the loop is armed for any zero-cost stock (free samples, promotional goods).

**#14 is destructive by design:** a legitimately zero-cost purchase (free sample) has its cost layer hard-deleted and its `stock_movements.batch_id` nulled on **every boot**, permanently breaking batch traceability for that stock.

*Fix:* move all 14 out of `import` side-effects into an explicit, opt-in `npm run repair` command that takes a `VACUUM INTO` backup first, runs in one transaction, and writes an `activity_log` row per mutation. **Migration needed: no — removal.**

---

### MIG-06 — 🔴 Permission revocation is silently reverted by every restart — P1
```ts
// database.ts:1151-1152
// Always seed — backfills missing permissions for existing databases
seedDefaultPermissions();
```
```ts
// database.ts:1306-1315
const adminRole = db.prepare('SELECT id FROM roles WHERE role_name = ?').get('Admin');
const allPermissions = db.prepare('SELECT id FROM permissions').all();
for (const perm of allPermissions) {
  db.prepare(`INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (?, ?)`)
    .run(adminRole.id, perm.id);
}
```
Live DB: Admin holds **83 of 83** permissions, User holds 24. If an operator uses `PUT /api/roles/:id/permissions` to revoke a permission from Admin or User, **the next boot re-grants it.** Combined with **AUD-04** (role/permission changes are not logged at all), you get: a privilege change that is invisible in the audit trail *and* silently undone. An auditor asking "who had delete rights on 3 August" cannot be answered, and the current state is not evidence of the configured state. *Fix:* seed only when `role_permissions` is empty for that role, or add a `seeded_at` marker; log every role-permission mutation. **Migration needed: no.**

---

### MIG-07 — Closing an accounting period is undone / corrupted by a restart — P1
`server/src/migrations/add-gl-foundation.sql:101-110` runs unguarded on every boot (`database.ts:1406`):
```sql
INSERT INTO accounting_periods (period_name, start_date, end_date, status)
SELECT strftime('%Y-%m','now'), date('now','start of month'),
       date('now','start of month','+1 month','-1 day'), 'open'
WHERE NOT EXISTS (SELECT 1 FROM accounting_periods WHERE status = 'open');
```
`period_name` is `TEXT UNIQUE` (verified DDL). `closePeriod` (`accountingController.ts:291`) is admin-only and correctly implemented. But an admin who closes the **current** month creates a state where no period is open and `'2026-08'` already exists → next boot the INSERT raises `UNIQUE constraint failed`, **aborting `add-gl-foundation.sql` at its final statement**, swallowed at `:1408`. And if the month has rolled over, the boot **silently re-opens a period**, defeating the close control. Either way, period closure — the primary accounting lock — is not durable across a restart. *Fix:* make this an explicit admin action, not a boot-time statement. **Migration needed: no.**

---

### MIG-08 — Rollbacks: 30 files, 11 of them are invalid SQL; 20 forward migrations have none; never wired to anything real — P2
`ls server/src/migrations/*.sql` = **50**; `rollbacks/*.sql` = **30**. **20 forward migrations have no rollback**, including every financially significant one: `add-gl-foundation.sql`, `add-supplier-payment-support.sql`, `add-purchase-returns-tables.sql`, `add-batch-costing.sql`, `add-cash-accounts.sql`, `add-opening-balances.sql`, `add-employees-table.sql`, `init.sql`. (No orphan rollbacks — the pairing is one-directional.)

**11 of the 30 are syntactically invalid.** They use `ALTER TABLE … DROP COLUMN IF EXISTS`, which SQLite does not support. Verified directly against the live schema:
```
EXPLAIN ALTER TABLE customers DROP COLUMN IF EXISTS credit_limit
  → sqlite3.OperationalError: near "EXISTS": syntax error
EXPLAIN ALTER TABLE customers DROP COLUMN credit_limit   → PARSED OK
```
39 such statements across: `rollback-add-activity-log-fields` (5), `-add-customer-ar-fields` (4), `-add-full-sales-cycle` (6), `-add-invoice-discount-tax-fields` (7), `-add-rack-tracking` (2), `-add-raw-materials-warehouse` (1), `-add-roles-permissions` (1), `-add-stock-adjustment-financial` (3), `-add-warehouse-to-production-inputs` (1), `-add_activity_log_columns` (5), `-customer-ar-migration` (4). `db.exec` aborts at the first one, so e.g. `rollback-add-roles-permissions.sql` drops four indexes, then dies on line 9 and **never reaches its three `DROP TABLE`s** — a partial teardown.

**None of the 30 uses `BEGIN`/`COMMIT`** — no rollback is atomic. And `runRollbackAll` (`database.ts:2038-2057`) iterates them **reverse-alphabetically**, not in dependency order, catching and ignoring each error so it grinds through a partial teardown.

**Are they ever executed?** Only via `--rollback` in `process.argv`, evaluated **at module load** (`database.ts:1089-1097`):
```ts
if (process.argv.includes('--rollback')) {
  const targetMigration = process.argv.find(a => a.startsWith('--rollback='));
  if (targetMigration) { runRollback(...); } else { runRollbackAll(); }
}
```
A bare `--rollback` anywhere in argv of **any** process that imports `config/database` triggers `runRollbackAll()` — 30 files of `DROP TABLE`/`DROP INDEX` against the live DB with **no confirmation, no `--force`, no dry-run, no backup**. Verdict: **effectively dead files that are simultaneously a loaded gun.** *Fix:* fix the syntax, add the 20 missing, wrap each in a transaction, and gate the flag behind an explicit interactive confirmation. **Migration needed: no.**

---

### MIG-09 — SQLite-specific migration safety — P1 (assessment)
- **ALTER TABLE limits:** mostly respected — additive `ADD COLUMN` throughout, plus one legitimate `RENAME COLUMN` (`:603`, `bom_items.raw_material_id → item_id`, guarded three ways at `:584-600`). Good.
- **Table rebuild:** exactly one (`:766-795`) and it is the P0 in MIG-02.
- **Drops/recreates a table holding financial data:** **YES, two.** `DROP TABLE payments` (`:789`) and `DROP TABLE IF EXISTS sales` **on every boot** (`:613`).
- **`foreign_keys` toggled during migration:** **YES**, `:767`/`:794`, with no `finally` (MIG-02).
- **Do migrations run in a transaction?** **NO.** Only **1 of 50** forward `.sql` files contains `BEGIN`/`COMMIT` (`add-supplier-payment-support.sql`). Every other multi-statement `db.exec()` runs statement-by-statement in autocommit, so **any error leaves the file half-applied and permanently so** — the guard now sees the first half as "done".
- **6 fully silent swallows** (also the ESLint `no-empty` errors) at `database.ts:664-669`:
```ts
try { db.exec(`ALTER TABLE invoices ADD COLUMN source_type VARCHAR(20)`); } catch {}
try { db.exec(`ALTER TABLE invoices ADD COLUMN quotation_id INTEGER`); } catch {}
try { db.exec(`ALTER TABLE invoices ADD COLUMN customer_name VARCHAR(200)`); } catch {}
```
Not even `logger.error`. Whether `invoices.customer_name` exists is unknowable from the logs.

### MIG-10 — PRAGMA settings review — P2
Correct: `foreign_keys=ON`, `journal_mode=WAL`, `busy_timeout=5000` (your multi-window SQLITE_BUSY concern **is** addressed — good), `page_size=4096`.
Gaps: **`cache_size` is never set** (default `-2000` = 2 MB — verified) — at 100k invoices this is the single cheapest perf win. **`synchronous=NORMAL`** (`:30`) means a power cut can lose recently committed transactions; acceptable *only* with a working backup, which there isn't (DR-01). **`mmap_size`, `wal_autocheckpoint`, `optimize` never touched.** `user_version` left at 0 despite being the obvious free migration counter.

### MIG-11 — Migration file resolution depends on two duplicate copies in `dist` — P3
`tsconfig.json` has `rootDir: "."`, so `src/config/database.ts` → `dist/src/config/`. 46 runners use `path.join(__dirname,'../migrations/…')` = `dist/src/migrations/`, but `runEmployeesMigration` (`database.ts:1573`) uses **`'../../migrations/…'`** = `dist/migrations/`. The build script papers over this by creating both:
```
"build": "tsc && rm -rf dist/migrations && cp -r src/migrations dist/migrations
          && rm -rf dist/src/migrations && mkdir -p dist/src && cp -r src/migrations dist/src/migrations"
```
Works in production (both dirs exist). **Breaks under ts-jest**, where `__dirname` = `server/src/config` and `server/migrations/` **does not exist** (verified) — so `add-employees-table.sql` silently fails in every test run against a fresh DB, swallowed at `:1581`. Deleting either `cp` line silently disables up to 46 migrations. *Fix:* one canonical path constant. **Migration needed: no.**

---

## PART B — AUDIT TRAIL

### AUD-01 — 🔴 Invoice create/update/delete are completely unlogged — P0
`server/src/controllers/invoiceController.ts` **does not import the activity logger at all** (imports at `:1-14`). Consequence — `deleteInvoice`, the most destructive operation in the product:
```
invoiceController.ts:603  function deleteInvoice(req: AuthRequest, res: Response) {
                  :648      PaymentModel.delete(db, alloc.payment_id);           // deletes payments
                  :653      InvoiceModel.reverseStockForItems(...)
                  :656      AccountingService.voidJournalLinesByReference(db,'INVOICE',invoiceId);
                  :662      InvoiceModel.deleteInvoiceItems(db, invoiceId);
                  :665      InvoiceModel.deleteLedgerEntryByReference(db, freshInvoice.invoice_no);
                  :671      InvoiceModel.deleteInvoice(db, invoiceId);
                  :679      res.status(200).json({ message: 'Invoice deleted successfully' });
```
Hard-deletes the invoice, its items, its ledger entries and orphaned payments — **and writes zero audit rows.** `userId` is read at `:607` only to stamp the stock reversal. `createInvoice` (`:134`) and `updateInvoice` (`:375`) likewise log nothing.

This is exactly why your `activity_log` census shows no Invoice CREATE/UPDATE/DELETE despite **18 invoices (ids 6-23) having been deleted** (verified: surviving ids are `[1,2,3,4,5,24]`). The two rows that *do* exist are hand-rolled SQL bolted onto other handlers:
```
invoiceController.ts:735  .run(userId,'CANCEL','Invoice',invoiceId, `Invoice ${invoice.invoice_no} cancelled`);
invoiceController.ts:1197 .run(userId,'RETURN','Invoice',invoiceId, `Return processed for …`);
```
**Root cause: logging is opt-in per controller, per handler, with no middleware backstop.** `req.activityLogged` is declared (`server/src/types/express.d.ts:12`) and **assigned in 40 places but read in zero** — the fingerprint of a catch-all logging middleware that was designed and never built. `server/src/middleware/` contains no logger import.
*Fix:* implement the intended middleware — after any 2xx on a mutating verb, if `!req.activityLogged`, write a row. Then retrofit the named gaps. **Migration needed: no** (but AUD-03 does).

### AUD-02 — Two parallel, incompatible logging paths — P1
(a) `server/src/services/activityLogger.ts` — `logCRUD` (`:189`), `logAuth` (`:169`), `logWithRequest` (`:210`) — writes all 10 columns and uses the `ActionType` enum. (b) **Raw `INSERT INTO activity_log` SQL** embedded in models and in the invoice/POS controllers, writing only 5 columns (no `log_level`, `ip_address`, `user_agent`, `metadata`, `duration_ms`) with generic verbs `'CREATE'`/`'DELETE'`/`'CANCEL'`/`'VOID'`/`'RETURN'` that match no enum member. **30 of ~60 `ActionType` members are dead** — `INVOICE_CREATE`, `INVOICE_DELETE`, `POS_SALE`, `PO_APPROVE`, `GRN_CREATE`, `BACKUP_CREATE`, `DATA_IMPORT/EXPORT`, `REPORT_GENERATE` … all declared, never emitted. Querying the log requires knowing which of two conventions each subsystem used.

POS also mislabels its one row (`posController.ts:206-208`): `action='CREATE'`, `entity_type='POS'` but `entity_id` = the **invoice** id — so `getByEntity('Invoice', id)` never surfaces a POS sale.

### AUD-03 — 🔴 No `old_value`/`new_value`. Four of the six ERP questions are unanswerable — P0
Verified live DDL — the table has **no** before/after columns and (per your FACT 4) no triggers:
```sql
CREATE TABLE activity_log ( id, user_id, action, entity_type, entity_id,
  description, created_at, log_level, ip_address, user_agent, metadata, duration_ms,
  FOREIGN KEY (user_id) REFERENCES users(id) )
```
Zero repo-wide hits for `old_value|new_value|before_value|previous_value`. The closest substitute captures **key names only, never values** (`expenseController.ts:107`, `paymentsController.ts:187`): `changes: Object.keys(req.body).filter(...)`.

| ERP question | Answerable today? |
|---|---|
| **Who** changed this | ⚠️ Partial — `user_id` is captured *where logging happens at all*; absent for invoices, POS detail, roles, settings |
| **What** changed | ❌ **No** — only a prose `description`; for updates, at best a list of field *names* |
| **When** | ✅ Yes — `created_at`, indexed |
| **Previous value** | ❌ **Impossible.** No column, no trigger, no journal. Unrecoverable by any query |
| **Why** | ❌ **No** — no reason/comment field. `voidPurchaseReturn` accepts a `reason` (`purchaseReturnController.ts:125`) — the sole exception, and it goes to the model not the log |
| **Which document caused it** | ⚠️ Partial — `entity_type`/`entity_id` when populated, but POS mislabels it and there is no correlation/request id linking the invoice, its stock movements, its ledger rows and its GL lines into one traceable event |

**Concretely: an invoice's amount can be edited after payment and there is no record that it changed, who changed it, or what it was.** That is not a gap in an ERP audit trail; it is the absence of one. *Fix:* add `old_value TEXT, new_value TEXT, reason TEXT, correlation_id TEXT`; have the logger diff the row. **Migration needed: yes.**

### AUD-04 — Privilege and configuration changes are entirely unlogged — P1
Zero logging in: `rolesController.ts` (`createRole:29`, `updateRole:58`, **`updateRolePermissions:83`**, `deleteRole:102`), `settingsController.ts` (`updateSetting:33`, `updateSettings:47`, `updateIntegrationSettings:71`), `preferencesController.ts:49`, `customReportsController.ts`, `dashboardLayoutController.ts`, `forecastsController.ts`, `mobileInvoiceController.ts`, `routes/stockBatches.ts` (PATCH `:64`, halt `:93`, unhalt `:127` — inline handlers), `routes/integrations.ts:22`. **Privilege escalation leaves no trace** — and per MIG-06 is silently reverted at restart. This matches your FACT 3 exactly.

**Coverage summary — 26 mutating controllers:** 11 log properly via the service (auth, customers, suppliers, users, inventory, payments, expenses, employees, bom, production, accounting); 7 log only via raw SQL in their model (purchase, purchaseOrder, purchaseReturn, sales/quotation/salesOrder, POS); **8 log nothing at all** (roles, settings, preferences, customReports, dashboardLayout, forecasts, mobileInvoice, stockBatches routes). `purchaseOrderController`'s `addLineItem`/`updateLineItem`/`deleteLineItem` (`:170/204/238`) log nothing. `productionController` **double-logs** (controller `:40` + `Production.ts:378`).

### AUD-05 — The audit log is deletable by anyone who can read it, and is not append-only — P1
```
server/src/routes/activityLog.ts:44
router.post('/cleanup', requirePermission('activity_log','read'), activityLogController.cleanupLogs);
```
A bulk destructive purge gated on **`activity_log:read`** — the same permission needed to view the log page. `database.ts:1288` defines only `activity_log:read`; there is no `:delete` permission to gate it with. The comment on `:43` says "admin only"; nothing enforces that. Retention is caller-supplied with a floor of 1:
```
activityLogController.ts:243   const { days = '90' } = req.body;
activityLogController.ts:246   if (isNaN(d) || d < 1) → reject      // days=1 is ACCEPTED
ActivityLog.ts:344-347         DELETE FROM activity_log WHERE created_at < datetime('now','-'||?||' days')
```
`POST /cleanup {days:1}` destroys all but 24 hours of the trail, and the only trace is the one `SYSTEM_CLEANUP` row (`activityLogController.ts:255`) — which the *next* cleanup also removes. **No trigger, no append-only constraint, no hash chain, no `is_deleted` flag, no off-box copy** (the CSV export at `ActivityLog.ts:372` drops `metadata`/`user_agent`/`duration_ms` and caps at 10,000 rows). `ActivityLogModel.delete(id)` (`ActivityLog.ts:359`) — single-row hard delete — exists, uncalled and unrouted.
No `UPDATE activity_log` exists anywhere and no PUT/PATCH route — **rows cannot be edited via the API. That part is correct.** *Fix:* introduce `activity_log:purge`, enforce a minimum retention (e.g. 365 days), and require the deletion itself to be logged to an append-only sink.

### AUD-06 — Deleted invoices left ₨685 of live, unvoided GL rows — measured — P0
Verified on the live DB copy:
```
journal_lines with reference_type='INVOICE' pointing at a deleted invoice : 72 rows
   of which voided=1 : 60 rows (₨2,330)
   of which voided=0 : 12 rows (₨685)  ← STILL COUNTED IN THE TRIAL BALANCE
journal_lines whose journal_entry_id has no journal_entries row           : 26 rows
customer_ledger hard-deleted ids                                          : 16-31 (16 rows)
dead invoice ids still carried in the GL                                  : 6…23
```
Financial misstatement, by account:
| Account | Effect |
|---|---|
| `1100` Accounts Receivable | **overstated ₨420** |
| `4000` Sales Revenue | **overstated ₨420** |
| `5000` Cost of Goods Sold | **overstated ₨265** |
| `1200` Inventory Asset | **understated ₨265** |

**Why FK enforcement cannot save you here** — `journal_lines`' own DDL declines the constraint:
```sql
journal_entry_id INTEGER NOT NULL,   -- logical grouping; no FK to journal_entries
                                     -- since that table may be missing for fresh installs
reference_type TEXT, reference_id INTEGER,   -- polymorphic: no FK possible
```
`PRAGMA foreign_key_list(journal_lines)` returns FKs only for `created_by`→`users` and `account_id`→`chart_of_accounts`. So `foreign_keys=ON` is doing its job (0 violations globally) while the ledger↔document link is structurally unprotected. `AccountingService.voidJournalLinesByReference` at `invoiceController.ts:656` is *supposed* to void these — 12 rows prove it does not always succeed (invoices deleted by a path that skipped it, or by the e2e script — see TEST-02). *Fix:* soft-delete invoices; add `reference_type/reference_id` integrity as a scheduled check; reconcile the 12 rows now. **Migration needed: yes (data fix).**

### AUD-07 — Log writes are fire-and-forget, outside the business transaction, lost on restart — P1
`activityLogger.ts:133-164`: in-memory `logQueue`, `BATCH_SIZE = 10`, `FLUSH_INTERVAL = 1000ms`; `log()` pushes and returns. `logCRUD` calls sit **after** the business `transaction()` commits, so the financial mutation is durable while its audit row is not. `server.ts:49-66` handles SIGTERM/SIGINT and calls `db.close()` but **never `flushLogs()`** — up to 9 queued entries plus the 1 s window are discarded on every restart. All insert failures are swallowed (`:254-260` re-`unshift`s the batch onto an **uncapped** queue → unbounded memory growth if inserts keep failing; `ActivityLog.ts:101-104` returns `0`, indistinguishable from success). `ActivityLog.insert()` (`:67`) is dead code — the service uses its own inline SQL.

### AUD-08 — `server/src/audit-trace.ts` is not audit infrastructure, and is a landmine — P2
1,341-line standalone dev script ("Run: `npx ts-node src/audit-trace.ts`"). Not imported anywhere, not in any npm script — **but it is inside `tsconfig` `include`, so it compiles into `dist` and ships.** It does destructive work at **module top level**:
```
audit-trace.ts:33-38
  if (fs.existsSync(AUDIT_DB_DIR)) { fs.rmSync(AUDIT_DB_DIR, {recursive:true, force:true}); }
  process.env.DATABASE_PATH = AUDIT_DB_DIR;
```
Merely `import`ing it recursively deletes `<repo>/audit-db` and **repoints `DATABASE_PATH` for every module loaded afterwards.** Harmless today; one stray import from becoming a P0.

---

## PART C — BACKUP, RECOVERY, DATA SAFETY

### DR-01 — 🔴 No backup mechanism exists — P0
No endpoint, no UI action, no scheduled job, no script a user can run. Repo-wide: **zero** hits for `VACUUM INTO`, `Database.prototype.backup`, `sqlite3_backup`, `integrity_check`, `PRAGMA quick_check`, `cron`, `systemd`, `rsync`. No `/api/backup` route; `server/src/routes/settings.ts` (14 lines) exposes only get/put settings. `VACUUM INTO` appears **only in prose**, `server-reference/SCHEMA_AND_SEED.md:35`. `ActionType.BACKUP_CREATE` (`activityLogger.ts:95`) is declared and never emitted.

The only two DB copies in the whole repo:
```
server/src/scripts/fix-duplicate-purchase.ts:57-59
  const backupPath = dbPath + `.backup-${Date.now()}`;
  fs.copyFileSync(dbPath, backupPath);
```
— a one-off dev script hardcoded to `PURCH-2026-0004`, and it is **the textbook unsafe WAL backup you flagged**: `erp.db` alone, no checkpoint first, no `-wal`. Against the live 3.2 MB WAL that "backup" omits every transaction still in the WAL. The second is a packaging `cp` (DR-03).

### DR-02 — 🔴 `installer-stub.sh --force` deletes the production database — P0
```
installer-stub.sh:17-19   if [ -e "$DIR" ]; then ... rm -rf "$DIR";   # $DIR = ~/.local/share/minierp
installer-stub.sh:34      rm -f "$DIR/server/database/erp.db"
```
Line 19 wipes `erp.db`, `erp.db-wal`, `erp.db-shm`, `server/uploads/` and `server/.env` — **no prompt, no preservation, no backup.** There is **no upgrade path**: the only way to install over an existing install is to destroy it. Line 34 removes `erp.db` but not `-wal`/`-shm` — latent `SQLITE_NOTADB`/corruption if a `-wal` is ever shipped. A byte-identical copy of this stub is heredoc'd into `tool/make_linux_setup.sh:203-256`, so there are two copies to keep in sync.

### DR-03 — 🔴 WAL checkpointing: the one call is racy, unchecked, and in a build script — P1
```
tool/make_linux_setup.sh:90-97
  (cd server && "$NODE" -e "const db=new D('database/erp.db');
     db.pragma('wal_checkpoint(TRUNCATE)'); db.pragma('optimize'); db.close();")
  cp server/database/erp.db "$STAGE/minierp/server/database/erp.db"
```
Separate process, possibly while the server runs; any write between checkpoint and `cp` lands in a WAL that is never copied. `wal_checkpoint(TRUNCATE)` **returns busy rather than throwing** when a reader holds a lock, and the return value is discarded — a failed checkpoint is indistinguishable from success.

**Application code never checkpoints.** Precise diagnosis of your FACT 2, measured: WAL = 3,234,232 bytes = **785 pages** at `page_size` 4096; `wal_autocheckpoint` = **1000 pages ≈ 4.1 MB**. So the WAL sits *just under* the auto-checkpoint threshold and SQLite never fires. Even when it does, auto-checkpoint is **PASSIVE — it recycles WAL space, it does not truncate the file**, so the high-water mark is permanent. **What pushed it to 3× the DB: the boot-time bulk UPDATEs of MIG-05**, which rewrite most of `invoices`, `stock_balances` and `items` in a handful of large transactions on every start.

Risks: slow reopen; `synchronous=NORMAL` (`database.ts:30`) means a power cut can lose recent commits; and **any naive `cp erp.db` loses up to 3.2 MB of committed data** — which is precisely what `fix-duplicate-purchase.ts:59` and `make_linux_setup.sh:97` do.

### DR-04 — 🔴 `db.close()` — the only thing that drains the WAL — effectively never runs in production — P1
`server/server.ts:49-81` — four handlers (SIGTERM, SIGINT, `unhandledRejection`, `uncaughtException`), all shaped `server.close(() => { db.close(); process.exit(); })`. Gaps:
1. **`db.close()` is inside the `server.close()` callback**, which waits for all connections to drain. With HTTP keep-alive (Express 5 default) an idle Flutter client holds it open; there is **no timeout and no `closeAllConnections()`** — so `db.close()` may never fire. `run.sh:36` then `kill -9`s after 5 s, untrappable.
2. **SIGHUP has no handler**; SIGKILL and power loss are untrappable.
3. `server.ts:22` `process.exit(1)` on missing env vars fires **after** `import db from './src/config/database'` (`:5`) has already run all 45 boot migrations — so a missing `JWT_SECRET` means "mutate the DB, then hard-exit without closing".
4. `database.ts:2025, 2034, 2042` — `runRollback`/`runRollbackAll` `process.exit(1)` with no `db.close()`.
5. **No Electron wrapper exists** — the four `// (Electron)` comments (`database.ts:9`, `app.ts:244/246`, `reconcile-stock-cash.ts:32`) are vestigial from a replaced port; `app.ts:244-264` still serves a dead `client/dist`. The real desktop shell is `make_linux_setup.sh:142-177`, which `nohup`s Node then **`exec`s the Flutter binary — so when the user closes the window the launcher shell is gone and the Node server is orphaned with no quit hook.** In normal end-user operation the server is only ever killed at logout/shutdown. **`db.close()` effectively never runs.**

### DR-05 — 🔴 The live DB and a placeholder JWT secret are committed to git; git is the de-facto backup and is not one — P0
`.gitignore` (47 lines) is the **stock unmodified Flutter template** — no `server/` section at all, no `*.db`, no `.env`, no `node_modules/`. `git check-ignore -v server/database/erp.db server/.env` → no output.
```
$ git ls-files server/database/ server/.env
server/.env
server/database/Untitled Folder/erp.db{,-shm,-wal}
server/database/erp.db{,-shm,-wal}
```
All tracked **and currently dirty** (`M erp.db`, `M erp.db-shm`, `M erp.db-wal`). Committing `-shm` is meaningless-to-harmful (pure shared memory, must never be restored) and a `-wal` restored against a mismatched `erp.db` (different salt/checksum) is **silently discarded by SQLite on open, rolling the DB back**. `git log -- server/database/erp.db` shows business data churning under *feature* commits (`cca70fd "feat: implement global search command palette"`). ~4 MB of new binary per commit. `server/node_modules` is also committed — **12,945 of 14,711 tracked files**.

`server/.env`: `JWT_SECRET=mini-erp-secret-key-change-in-production` — a literal placeholder instructing the reader to replace it, committed unchanged and now permanent in history; forgeable admin tokens offline. `HOST=0.0.0.0` overrides `server.ts:10`'s safer `127.0.0.1` default. Mitigation: `make_linux_setup.sh:106` generates a proper `openssl rand -hex 32` per packaged install — **so the weak secret affects dev and any repo-checkout deployment (`run.sh`)**, not packaged installs. `DEFAULT_ADMIN_PASSWORD=admin123` *is* pinned in packaged installs (`:106`).

**`server/database/Untitled Folder/erp.db`** — a 1.6 MB hand-made copy from Aug 12 with its own `-wal`/`-shm`. This is the closest thing to a backup in the project: ad-hoc, unlabelled, 9 days stale, provenance unrecorded.

### DR-06 — Export cannot be a recovery path; import does not exist — P1
Server-side export: **one endpoint, activity logs only**, capped at 10,000 rows (`routes/activityLog.ts:41`, `activityLogController.ts:223`). No csv/xlsx/pdf library in `server/package.json`.

Everything else is **client-side Flutter** — `lib/core/utils/csv_export.dart`, 24 builders, all operating on **data already loaded into the widget's list** (so you get whatever the grid is filtered/paginated to). All are presentation-layer views: formatted currency, localised labels, `'—'` for nulls, `sanitizeCsvCell` stripping leading `=+-@` (`:89` — good hardening). **Lossy by construction, not machine-reingestible.**

Against 64 tables: `journal_lines` ❌, `journal_entries` ❌, `payment_allocations` ❌, `purchase_allocations` ❌, `payments` ❌, `stock_movements` only per-item via a modal, and **no master data at all** (`items`, `customers`, `suppliers`, `users`, `roles`, `chart_of_accounts`, `settings`, `stock_batches`, `stock_balances`, `opening_balances`).

**Import: zero hits** for `importCsv|parseCsv|CsvToList|bulkImport|/import`. The `csv` package is encode-only. The only upload route in the server is `routes/employees.ts:26` (employee documents). **There is no path, automated or manual, from exported data back into the database.**

### DR-07 — Uploads live outside the DB — latent, not yet realised — P2
`middleware/upload.ts:13-22` — `multer.diskStorage` → `server/uploads/employees/`, 10 MB cap, MIME allowlist (`:26-36`). **Only the filename is persisted** (`employeeController.ts:325` → `employee_documents.file_path`). A DB-only backup loses every contract/ID scan; a DB-only restore leaves every row a dangling pointer. **Currently 0 files**, so the loss is latent — but `.gitignore` doesn't exclude `uploads/`, so the first upload starts committing HR documents to git (confidentiality). `employeeController.ts:362 fs.unlinkSync(filePath)` — irreversible, no trash. `make_linux_setup.sh:74` ships the **build machine's** uploads to every customer.

### DR-08 — Disaster-recovery posture: what a small business loses today — P0
**Disk failure or mid-write corruption ⇒ total loss of all business data since ~Aug 12**, and even that fallback is an unlabelled `Untitled Folder` copy plus a git blob whose `-wal` will very likely be discarded on open. Chain of reasoning:
1. No backup exists (DR-01) and no restore procedure is documented anywhere.
2. `synchronous=NORMAL` (`database.ts:30`) + a WAL that is never drained (DR-03) + `db.close()` that effectively never runs (DR-04) ⇒ the most recent commits are not guaranteed durable, and the *routine* shutdown is unclean.
3. Even a *successful* naive recovery (`cp erp.db`) silently discards up to 3.2 MB of WAL — i.e. potentially all recent activity.
4. No `integrity_check` anywhere, so corruption is discovered by a user seeing wrong numbers, not by the system.
5. No import path (DR-06), so hand-reconstruction from CSVs is impossible — and the CSVs omit the GL, payments and all master data anyway.
6. `installer-stub.sh --force` (DR-02) means *the upgrade procedure itself* is a total-loss event.
7. The one migration in MIG-02 destroys `payments.invoice_id` on upgrade with no backup taken first.

**Minimum viable fix, in order:** (a) `.gitignore` `server/database/`, `server/.env`, `server/node_modules/`, `server/uploads/` and purge them from history + rotate the JWT secret; (b) a `VACUUM INTO 'backup-<ts>.db'` endpoint/CLI — atomic, WAL-safe, single file, no `-wal` needed — on a nightly timer with 7 daily/4 weekly retention **plus `PRAGMA integrity_check` on the copy** to prove restorability; (c) `db.pragma('wal_checkpoint(TRUNCATE)')` on an interval and before backup; (d) make `installer-stub.sh` back up before touching `$DIR` and add a real upgrade path; (e) include `server/uploads/` in the backup set.

---

## PART D — TESTING

### TEST-01 — Inventory and the honest coverage picture — P1
**Dart `test/`: 27 files, 25,638 lines, 667 test blocks.** Dominated by `test/widget_test.dart` — **14,042 lines / 225 tests in one file** (54% of all Dart test code; a maintainability and isolation hazard on its own). Then `repositories/repositories_test.dart` (2,128), `sales_invoice_form_page_test.dart` (1,719), `models_test.dart` (901), `calculations/extra_calculations_test.dart` (790). Category split: ~13 unit, ~7 widget, ~5 integration (HTTP-mocked), **0 true e2e**.

**Server `server/src/__tests__/`: 12 test files + 2 support, 4,570 lines, 250 `it` blocks.** Best: `api.integration.test.ts` (1,028), `models.test.ts` (990), `purchaseReturn.test.ts` (512), `security.regression.test.ts` (379).

**Orphaned: `calculations/tests/invoiceCalculations.test.ts` + `invoiceLineCalc.test.ts` (243 lines) can never run** — they use `node:test`, `jest.config.js:5` sets `roots: ['<rootDir>/src']`, and **there is no root `package.json`**. Dead tests guarding the loose-item invoice branch.

**Money-critical path coverage:**

| Path | Verdict | Evidence |
|---|---|---|
| Partial payment | ⚠️ **customer side untested** | `paid_amount`/`balance_amount` asserted **only** on the supplier side (`models.test.ts:731-737`). `describe('Payments Endpoints')` (`api.integration.test.ts:140-171`) is **3 GET-only smoke tests** — no POST/PUT/DELETE |
| `payment_allocations` | ⚠️ **table name appears 0 times in any test** | API field exercised (`api.integration.test.ts:955`) but no test ever reads the rows. Supplier-side `purchase_allocations` *is* asserted (`models.test.ts:688`) |
| Sales return | ✅ Good | `api.integration.test.ts:712-878` — 4 tests, restock warehouse + stock deltas asserted (`:835/:839`) |
| Purchase return | ✅ **Strongest area** | `purchaseReturn.test.ts:184-433` + `api.integration.test.ts:480-710`; asserts movement, credit note, `supplier_ledger`, `journal_lines`, void reversal, 403 |
| **Invoice edit after payment** | ❌ **ABSENT — 0 hits** | Nothing verifies `paid_amount`/`balance_amount`/`status`/stock/GL after editing a paid invoice |
| Stock movement correctness | ✅ Good | `models.test.ts:273/286/297`, `api.integration.test.ts:821-828` |
| **Transaction rollback** | ❌ **ABSENT — 0 hits** for `.transaction(`/`ROLLBACK`/`BEGIN ` | No test forces a mid-transaction failure |
| **Concurrency** | ❌ **ABSENT — 0 hits** for `concurren`/`Promise.all`/`race` | Despite WAL + `busy_timeout=5000`. `getNextSequenceNumber`, stock deduction, FIFO consumption all untested under contention |
| **GL double-entry balance** | ❌ **`SUM(debit)==SUM(credit)` never asserted** | `journal_lines` asserted for `PURCHASE_RETURN` only (5 hits). 0 hits for `double-entry`/`trial_balance`. No GL coverage for invoices, payments, purchases, productions, expenses |
| Customer ledger running balance | ⚠️ Partial | `api.integration.test.ts:880-1027` checks row uniqueness and a **net-zero aggregate** (`:1024-1026`) — not the per-row `balance` sequence |
| FIFO / batch costing | ✅ **Well covered** | `models.test.ts:402-620` — FIFO, FEFO, halted, expired, NULL-expiry, insufficient stock |

**Highest-value MISSING tests, ranked:**
1. **Double-entry invariant**: after *every* mutating scenario, `SELECT SUM(debit)-SUM(credit) FROM journal_lines WHERE voided=0` must be 0 — and grouped per `reference_type/reference_id`. (I verified this currently holds globally at ₨15,760.20 = ₨15,760.20 — but nothing keeps it holding.)
2. **Transaction rollback**: insufficient stock on line 2 of a 3-line invoice ⇒ no invoice, no items, no movements, no ledger, no GL.
3. **Invoice edit after payment** ⇒ correct `paid_amount`/`balance_amount`/`status`, stock delta, GL reversal.
4. **Invoice delete** ⇒ **no orphaned `journal_lines`/`customer_ledger`** (this test would have caught AUD-06's 72 rows) **and** an `activity_log` row exists.
5. **Boot idempotency**: snapshot the DB, re-import `config/database`, assert **zero** row changes. This directly targets MIG-05 and is cheap.
6. **Concurrency**: two parallel invoice creates ⇒ no duplicate `invoice_no`, correct final stock.
7. **Customer-side partial payment + allocation**, reading `payment_allocations` rows.
8. **Migration replay**: apply all 50 files to `:memory:` twice; assert identical schema and no error (would have caught MIG-03, MIG-04, MIG-11).

### TEST-02 — 🔴 `e2e_expiry_override_test.py` writes to the live DB with no `try/finally`; the damage is confirmed and quantified — P0
**Confirmed.** `e2e_expiry_override_test.py:24 API = "http://localhost:3011/api"` — the real dev server backed by the live `server/database/erp.db` (its own usage block at `:14` says `cd server && node dist/server.js &`). Logs in with `admin`/`admin123` (`:64`). Creates a customer (`:71`), an item (`:75-81`), two purchases (`:85-99`) and **three invoices** (`:112`, `:156`, `:219`). **Mutates existing batch state**: `:145` halts a batch; `:150-152` `PATCH /stock-batches/{id} {"expiry_date": None}` — **nulls a real expiry date** — restored at `:175-177`; halts/unhalts at `:209/:217/:230-231`.

Cleanup is best-effort and unguarded — **there is no `try/finally`** (`:236-248`):
```python
238   inv_list = api("GET", "/invoices?limit=20&sort=desc", token=token)
241   for inv in inv_data:
242       if "E2E" in (inv.get("invoice_no") or ""):
243           api("DELETE", f"/invoices/{inv['id']}", token=token)
```
Several earlier lines raise on unexpected data (`:65 r["token"]`, `:102-103 [...][0]`, `:127-130`), and **any exception before `:236` skips cleanup entirely**, potentially leaving a batch halted or with a nulled `expiry_date`. The invoice cleanup is a **blind `"E2E" in invoice_no` scan over the newest 20 invoices — it can delete records this run did not create.**

**Damage confirmed in the live DB (measured, DR/AUD-06):** invoices `6…23` gone (18 hard deletes), `customer_ledger` ids `16-31` gone (16 rows), **72 orphaned `journal_lines` of which 12 are unvoided and misstate the trial balance by ₨420 AR / ₨420 revenue / ₨265 COGS / ₨265 inventory**, and 26 `journal_lines` with a dangling `journal_entry_id`. **Zero `activity_log` rows record any of it** (AUD-01). This is the concrete cost of AUD-01 + AUD-06 + no backup, and it has already been paid.

The `verify-picker{,2,3,4,5}.py`, `verify-crash.py`, `probe-page.py` scripts target the Flutter **web** build at `127.0.0.1:8765` and are **read-only Playwright UI drivers** — no `POST`/`DELETE`, no `requests`/`urllib`. They log in against live data and screenshot to `/tmp/drp`, but create nothing. `run-crash.sh` is a 5-line detached launcher hardcoding the absolute repo path. None is wired into any runner — 11 root-level ad-hoc `.py`/`.sh` artifacts, five of them near-duplicates.

### TEST-03 — Jest test isolation is correct, but rests on one line with no fail-closed guard — P1
**Good news, verified: `erp.db` appears 0 times in `test/`, `server/src/__tests__/`, `tool/`, `scripts/`, or any root `*.py`.** No Jest or Dart test opens the live DB. The guard:
```
server/src/__tests__/setup.ts:23-25
  // 3. Create isolated temp database for tests (never touch production DB)
  const testDbDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minierp-test-'));
  process.env.DATABASE_PATH = testDbDir;
```
with cleanup on `exit`/`SIGINT`/`SIGTERM` (`:28-45`). `dotenv` can't defeat it (only called in `server.ts`, which tests never import). **This is correct — do not change it.**

But it is a single point of failure, not defence in depth: `jest.config.js:15` has `setupFiles: []` (the earlier hook unused), and there is **no `if (NODE_ENV==='test' && !DATABASE_PATH) throw`** anywhere. If a test bypasses `setupFilesAfterEach` or invokes a `src/scripts/*` helper, `database.ts:10` falls back to the **live** path and immediately runs all 45 destructive boot migrations (MIG-05) before a single assertion. *Fix:* one fail-closed assertion at the top of `config/database.ts`.

**Test quality:** Dart uses **no mocking library** (dev_deps are only `flutter_test` + `flutter_lints`) — isolation via hand-written `HttpClientAdapter` fakes (`repositories_test.dart:31`, `dashboard_layout_controller_test.dart:24`, `api_client_test.dart:33`), assigned in 45 places. **One file constructs Dio with no adapter**: `sales_invoice_form_page_test.dart:49 _FakeInvoiceRepository() : super(RepositoryClient(Dio()))` — safe today only because every method is overridden and the bare `Dio()` has no `baseUrl`. Server: real `better-sqlite3` throughout, no `jest.mock` of the DB — 5 files use the (redirected) file DB, 4 use `:memory:`. `purchaseReturn.test.ts:17-31` is the best-practice case: replays the real migration chain into `:memory:`. `"test": "jest --forceExit"` masks leaked handles.

### TEST-04 — 🔴 There is no CI. `npm run typecheck` does not exist — P0
`.github` **does not exist**. Full YAML inventory outside `node_modules`: `analysis_options.yaml`, `devtools_options.yaml`, `l10n.yaml`, `pubspec.yaml`, `.dart_tool/native_assets.yaml`, `openspec/config.yaml` + six `openspec/changes/**/.openspec.yaml`. **No workflow file, no GitLab/Circle/Jenkins config.** Typecheck, lint, `dart analyze`, `flutter test` and `jest` are **never enforced**.

`AGENTS.md:285-299` (`# 15. SELF-AUDIT ENGINE`, `trigger: before_task_completion`) mandates `typescript_errors == 0`, `lint_errors == 0`, and:
```
298      - npm run typecheck
299      - npm run lint
```
**`server/package.json` has no `typecheck` script** (`:6-13` = start, dev, build, start:prod, test, lint). `npm run typecheck` fails with *Missing script* — so the documented pre-completion gate has been silently no-op'ing. **Nine spec docs claim it passed** (`item-expiry-spec.md:915`, `purchase-returns-spec.md:450,552`, `openspec/changes/global-search/tasks.md:151` "*zero issues*", `grid-pagination/tasks.md:81`, …). Only `openspec/changes/set-payments-po-id/tasks.md:9` uses the correct invocation and candidly admits the gap.

### TEST-05 — Actual toolchain results (measured) — P2
```
cd server && npx tsc --noEmit     →  exit 0, 0 errors      ✅ CLEAN
cd server && npx eslint .         →  413 problems (10 errors, 403 warnings), 51 files
cd server && npm run lint         →  identical: 413 problems (10 errors, 403 warnings)
```
The 10 errors: `__tests__/models.test.ts:244:26` (`no-non-null-asserted-optional-chain`), `models.test.ts:620:9` (`prefer-const`), **`config/database.ts:664,665,666,667,668,669` (`no-empty` ×6 — the silent `catch {}` migration swallows of MIG-09)**, `employeeController.ts:240:9` and `services/reportQueryEngine.ts:261:5` (`preserve-caught-error`). Bulk of the 403 warnings is `@typescript-eslint/no-explicit-any`; hotspots `searchService.ts` (6 unused vars) and `utils/encryption.ts` (`decrypt:29`, `isEncrypted:49` dead).

Note `tsconfig.json` has `"strict": false, "noImplicitAny": false, "strictNullChecks": false` — the clean `tsc` result is with the safety net down.

**Dart/Flutter toolchain UNAVAILABLE:** `which dart flutter` → nothing; `dart analyze` → *No such file or directory*. **I could not run `dart analyze`/`flutter analyze`; 25,638 lines of Dart test code plus all of `lib/` are UNVERIFIED for static analysis.** `analysis_options.yaml` exists and `flutter_lints ^6.0.0` is pulled, so lints are configured; whether they pass is unknown. Test suites were not run, per instructions.

---

## PART E — PERFORMANCE

### PERF-01 — 🔴 `invoice_items` has ZERO indexes; the most common join in the app is a full scan — P0
Measured on the live schema (consequence of MIG-04):
```
--- invoice detail: SELECT * FROM invoice_items WHERE invoice_id = 1
     SCAN invoice_items                              ← full table scan

--- sales by item: invoices JOIN invoice_items ON ii.invoice_id = i.id
     SCAN ii
     SEARCH i USING INTEGER PRIMARY KEY (rowid=?)
     USE TEMP B-TREE FOR GROUP BY
```
Tables with **zero user indexes** include `invoice_items`, `customers`, `suppliers`, `quotations`, `quotation_items`, `goods_receipts`, `goods_receipt_items`, `settings`, `warehouses`, `roles`, `opening_balances`.

At 100k invoices / ~350k `invoice_items`: **opening any single invoice scans 350k rows**; sales-by-item, stock valuation, COGS and gross-profit all degrade to full scans. *Fix:* `CREATE INDEX idx_invoice_items_invoice ON invoice_items(invoice_id)` and `(item_id)` — the single highest-value change in this report. Also index `customers(customer_name)`, `suppliers(supplier_name)`, `settings(key)`. **Migration needed: yes.**

### PERF-02 — 🔴 Customer-ledger running balance is fully recomputed and rewritten per row — P0
```ts
// server/src/utils/ledgerUtils.ts:128-144
function rebuildLedgerBalances(customerId: number): void {
  db.transaction(() => {
    const entries = db.prepare(`SELECT id, debit, credit FROM customer_ledger
                                WHERE customer_id = ? ORDER BY id ASC`).all(customerId);
    let runningBalance = 0;
    const updateStmt = db.prepare('UPDATE customer_ledger SET balance = ? WHERE id = ?');
    for (const entry of entries) {
      runningBalance = addCurrency(subtractCurrency(runningBalance, entry.credit), entry.debit);
      updateStmt.run(runningBalance, entry.id);   // ← one UPDATE per historical row
    }
  })();
}
```
Called from `invoiceController.ts:458` (create), `:668` (update), `:731` (delete) and `models/Payment.ts:484`. **Saving one invoice is O(that customer's entire history).** For a customer with 100k ledger rows: **100,001 statements and 100k row rewrites in one transaction** — tens of MB of WAL write amplification (this is also a prime contributor to DR-03's WAL high-water) and a multi-second stall that blocks **every** other request on the single-threaded synchronous `better-sqlite3` server. *Fix:* update incrementally from the changed row forward, or drop the materialized `balance` column and compute with a window function on read. **Migration needed: optional.**

### PERF-03 — 🔴 Dashboard fan-out: ~12 HTTP requests, ~66 SQL statements, ~2.5M rows read at scale — P1
**Backend per endpoint:** `/dashboard/summary` **12** statements (`models/Dashboard.ts:89-226`); **`/dashboard/cash-position` 36** (`:233-277`), 25 of them unbounded full-history scans; `/dashboard/kpi` 3-5 each.

The multiplier is `services/cashService.ts:218-309` — **5 unbounded row-returning queries per cash account, filtered in JS**:
```ts
const push = (row) => { if (normalizeCashMethod(row.method) !== accountKey) return; out.push({...}); };  // :233
for (const r of db.prepare(`
  SELECT payment_date as date, payment_method as method, payment_no as reference, notes, amount
  FROM payments WHERE customer_id IS NOT NULL AND payment_date <= ?`).all(uptoDate)) { ... }   // :245-250
```
repeated for supplier payments (`:260`), expenses (`:273`), salary_payments (`:284`), purchases (`:295`), then `out.sort()` in JS (`:307`). **5 accounts × 5 queries = 25 scans that read the same ~250k rows five times over and discard ~80% in JS.** Every predicate is `payment_date <= ?` with **no lower bound** (`cashService.ts:60-134`). Also `getKPI` (`Dashboard.ts:454-466`) runs 2 stock-value queries **before** the metric switch, so a `total_customers` card pays for stock valuation.

**Frontend (`lib/features/dashboard/dashboard_screen.dart`):** load-time watches on `dashboardSummaryProvider` (`:55`), `dashboardLayoutControllerProvider` (`:135`), `dashboardCashPositionProvider` (`:220`), **`dashboardKpiProvider(def.metric)` (`:695` — one HTTP request per KPI card)**, `dashboardArSummaryProvider` (`:1208`), `dashboardTopCustomersProvider(5)` (`:1372`), `expiryAlertsProvider` (`:1606`). **Default: ~12 requests.** `invalidateDashboardKpiCards` (`dashboard_providers.dart:112-116`) invalidates **all 16** catalog metrics regardless of visibility → any mutation triggers 16 refetches; with all cards on, **~24 requests / ~100-130 SQL statements**. Providers are `autoDispose`, so this repeats on every navigation back. At 100k invoices / ~250k cash-flow rows one dashboard load reads on the order of **2.5M rows** — seconds of blocked event loop.

**Bonus: two endpoints the client calls do not exist server-side** — `lib/core/api/endpoints.dart:82 /reports/expiry` and `:83 /dashboard/expiry-alerts` (no server match anywhere). The default-visible `panel_expiry_alerts` **404s on every dashboard load**.

### PERF-04 — Global search: 18 tables, all `LIKE '%x%'`, no FTS, ~400-1,960 statements per keystroke — P1
`services/searchService.ts:819-848` fans one `search()` out to 13 entity searches over **18 distinct tables**. **No FTS anywhere**; every predicate is `const q = '%${query}%'` (`:225`), and every entity ranks with `ORDER BY CASE WHEN … LIKE ? THEN 1 …` (`:234-241`, `:281-288`, `:328-334`, `:380-386`, `:663-670`) — non-sargable, forcing a sort. Measured:
```
--- customers LIKE '%ab%' OR phone LIKE '%ab%' ORDER BY CASE …
     SCAN customers
     USE TEMP B-TREE FOR ORDER BY
```
The N+1 is a **per-row permission re-check**: `filterActions` (`:172-199`) is called inside `rows.map(...)` at 13 sites (`:266,313,365,415,455,494,533,579,615,650,695,734,774`), and each call re-derives permissions from scratch — `SELECT role FROM users WHERE id=?` plus a **full `permissions` scan** (`getUserPermissions:146-163`) = **3 statements per result row**. Nothing cached or hoisted. `13 + 3×rows`: **~400 statements at default limit 10/entity, ~1,963 at max 50.** Per keystroke.
Bug found in passing: `searchService.ts:158-163` runs `SELECT p.module, p.action … WHERE rp.role_id = ?` via `.all()` **with no bound parameter**.

### PERF-05 — Worst N+1 offenders (request paths), ranked — P1
| # | Location | Statements | At 100k invoices |
|---|---|---|---|
| 1 | `utils/ledgerUtils.ts:128-144` | 1 + N UPDATE | 100k+ per invoice save (PERF-02) |
| 2 | `models/Dashboard.ts:233-277` → `cashService.ts:218-309` | 36, 25 unbounded | ~2.5M rows/load (PERF-03) |
| 3 | `services/searchService.ts` (13 sites) | 13 + 3/row | ~1,960/keystroke (PERF-04) |
| 4 | `services/accountingService.ts:166-169` — `listAccounts().map(getAccountBalance)`; each does 3 statements incl. a **full CASE scan of `journal_entries`** (`:133-140`) | 1 + 3N | **181 statements, 60 full journal scans per trial balance** |
| 5 | `services/forecastService.ts:759-773` — sales history correctly batched (`:481-519`), but `loadModelConfig` (1-2), `getSeasonalMultiplier` (2), `autoSelectModel` (1), `calculateBiasFactor` (1) all per item | 5-6 × items | **~30k statements at 5k items**, run *synchronously* on cache miss (`:795`) — blocks the whole server. `computeForecastAccuracy:949-1030` adds 2/record |
| 6 | `models/Customer.ts:230-271` / `:273-326` — each row's CASE embeds **two correlated subqueries** (3-table join), plus a non-sargable per-row `AND pr.notes LIKE '%' \|\| cl.reference_no \|\| '%'` (`:255`, `:286`) | 2 subqueries/row | **400k correlated subqueries**, and **no LIMIT** |
| 7 | `models/Reports.ts:903-949` `getPurchaseSummary` (3 correlated subqueries/row, `:907-909`); `:993-1028` `getBOMUsageReport` (3/row, `:996-998`) | 3/row | unbounded |
| 8 | `models/Invoice.ts:182-249` `denormalizeExpiryInfo` — 4 statements per consumed item | 4/item | write path |
| Also | `posController.ts:87→88,91` and `:142→143` (per cart line); `invoiceController.ts:833→835`, `:942→943`, `:1114→1117`; `models/Payment.ts:198→200, 231→233, 284→286, 309→311` | | |
| Startup | `database.ts:233-246` (per item/warehouse) and `:284-305` (per ledger row) — MIG-05 #5/#8 | | boot-time N+1 |

### PERF-06 — Reports and ledgers have no pagination and no date floor — P1
**Credit where due: 17 of 18 list models are correctly paginated** with `LIMIT ? OFFSET ?` + a separate COUNT (`Invoice.ts:374`, `Item.ts:151`, `Customer.ts:118`, `Payment.ts:145`, `Purchase.ts:343`, `PurchaseOrder.ts:296`, `PurchaseReturn.ts:198`, `Quotation.ts:340`, `SalesOrder.ts:347`, `Production.ts:474`, `Expense.ts:100`, `Employee.ts:160`, `BOM.ts:197`, `PhysicalCount.ts:204`, `StockMovement.ts:267/521`, `ActivityLog.ts:174`). There is **no shared helper** — `utils/queryUtils.ts` holds only `getQueryParam`/`getRouteParam`/`getQueryNumber`/`getQueryInteger` — which is why every non-`getAll` surface has none.

Unpaginated: **all 15 routed `/reports/*`** (`reportsController.ts` — the token `page` does not appear in the file), **all 12 `/dashboard/*`**, `GET /customers/:id/ledger` and `/statement` (`Customer.ts:230/273`), `GET /suppliers/:id/ledger` and `/statement` (`Supplier.ts:177/188`), `GET /stock-batches` (`routes/stockBatches.ts:22-53`, `SELECT sb.*`, no LIMIT), `/accounting/accounts/balances`, `/pos/transactions`, and `/reports/custom/:id/run` (LIMIT **only if saved** — `reportQueryEngine.ts:222-225`; its count query is deliberately unbounded, `:212-219`, so every run pays a second full scan).

**Only one report is bounded:** `Reports.ts:379 LIMIT 500` in `getInventoryMovementReport`.

Reports with **no date bound at all**: `getStockLevelReport:142`, `getLowStockReport:147`, `getStockValuationReport:152`, `getBatchTraceabilityReport:312`, `getTrialBalanceReport:244`, `getBalanceSheetReport:259`, `getARAgingReport:8`, `getAPAgingReport:18`, `getTopDebtors:48`. `getBOMUsageReport:230` defaults to `'2000-01-01'`→`'2099-12-31'`. `getSalesSummary` (`Reports.ts:233-267`) returns **every invoice in range to Node and sums in JS** (`:257-262`).

Aging reports use `julianday(due_date)` (`Reports.ts:5-29`, `:475-503`, `Dashboard.ts:672-688`) — function-on-column, never sargable, and there is no `due_date` index anyway:
```
--- AR aging: SUM(CASE WHEN julianday('now')-julianday(due_date) <= 30 …) GROUP BY customer_id
     SCAN invoices USING INDEX idx_invoices_customer_id
```
**At 100k invoices, AR aging, trial balance and the balance sheet each become multi-second full scans on the single-threaded server, blocking all other requests.** `Reports.ts:1030-1045` `getCustomerOutstanding`/`getSupplierOutstanding` accept `asOfDate` and **never use it**.

Also: **12 of 28 report handlers are exported but never routed** (compare `routes/reports.ts:12-27` with `reportsController.ts:321-329`) — `getSalesSummary`, `getSalesByCustomer`, `getSalesByItem`, `getStockLevelReport`, `getLowStockReport`, `getStockValuationReport`, `getInventoryMovementReport`, `getPurchaseSummary`, `getSupplierAnalysis`, `getProductionSummary`, `getBOMUsageReport`, `getExpensesReport`.

### PERF-07 — 142 indexes on a 1 MB DB: 12 are provably redundant; the ones that matter are missing — P2
Measured on the live DB: **64 tables, 142 user indexes, 37 autoindexes, 2 views, 2 triggers, `sqlite_stat1` present (35 rows).**

**10 exact duplicates** (same table, identical column list) — pure write amplification, from `add-missing-indexes.sql` and `add-missing-fk-indexes.sql` using a different naming convention than `init.sql`:
```
bom_items(bom_id)              idx_bom_items_bom            = idx_bom_items_bom_id
invoices(customer_id)          idx_invoices_customer        = idx_invoices_customer_id
productions(output_item_id)    idx_productions_output_item  = idx_productions_output_item_id
purchase_orders(supplier_id)   idx_po_supplier              = idx_purchase_orders_supplier_id
sales_orders(customer_id)      idx_so_customer              = idx_sales_orders_customer_id
stock_balances(item_id)        idx_stock_balances_item      = idx_stock_balances_item_id
stock_balances(warehouse_id)   idx_stock_balances_warehouse = idx_stock_balances_warehouse_id
stock_movements(item_id)       idx_stock_movements_item     = idx_stock_movements_item_id
stock_movements(warehouse_id)  idx_stock_movements_warehouse= idx_stock_movements_warehouse_id
work_orders(finished_item_id)  idx_wo_item                  = idx_work_orders_finished_item_id
```
**2 prefix-redundant**: `activity_log`: `idx_activity_log_user(user_id)` ⊂ `idx_activity_log_user_created_at(user_id,created_at)`; `idx_activity_log_entity(entity_type,entity_id)` ⊂ `idx_activity_log_entity_created_at(…,created_at)`. Worst ratios: `stock_movements` 8 indexes/105 rows, `activity_log` 7/149, **`purchases` 7 indexes/1 row**, `purchase_returns` 5/0, `productions` 5/0, `sales_orders` 4/0.

**Missing composites for exactly the hot paths you named** — measured:
```
--- customer_ledger WHERE customer_id=? AND transaction_date BETWEEN ? AND ? ORDER BY transaction_date, id
     SEARCH customer_ledger USING INDEX idx_customer_ledger_customer (customer_id=?)
     USE TEMP B-TREE FOR ORDER BY                    ← missing (customer_id, transaction_date, id)

--- stock_movements WHERE item_id=? AND warehouse_id=? AND movement_date>=? ORDER BY movement_date DESC
     SEARCH stock_movements USING INDEX idx_stock_movements_date (movement_date>?)
     ← planner picks the DATE index and ignores item/warehouse; missing (item_id, warehouse_id, movement_date)

--- journal_lines WHERE reference_type=? AND reference_id=?
     SEARCH journal_lines USING INDEX idx_journal_lines_reference    ✅ CORRECT — exists, do not change

--- payment_allocations WHERE invoice_id=?
     SEARCH payment_allocations USING INDEX idx_payment_allocations_invoice   ✅ CORRECT — exists
```
Also missing: `invoice_items(invoice_id)` (PERF-01), `invoices(status, invoice_date)`, `invoices(due_date)`, `customer_ledger(customer_id, id)` for PERF-02's `ORDER BY id`. **Net recommendation: drop 12, add 6.** `ANALYZE` lives only in dead migration files (MIG-04), so planner stats drift permanently stale as the DB grows. **Migration needed: yes.**

### PERF-08 — `ORDER BY` on computed expressions — unavoidable full materialize + sort — P2
`Dashboard.ts:158 ORDER BY (current_stock * 1.0 / reorder_level)`; `Reports.ts:880-881 ORDER BY (COALESCE(SUM(sb.quantity),0)*1.0/i.reorder_level)` after a `HAVING`; `Reports.ts:342 ORDER BY total_value` (a CASE expression); `Reports.ts:1009 ORDER BY usage_count` (a correlated-subquery alias); `searchService.ts` × 5 (PERF-04); `reportQueryEngine.ts:555-577 ORDER BY "computedAlias"`; and on the **paginated** invoice list, `models/Invoice.ts:135-145` maps `customer_name` → `COALESCE(c.customer_name, i.customer_name)` — a computed sort that defeats the index and forces a full sort before OFFSET.

### PERF-09 — Frontend↔backend interaction risks — P2
(a) **Request fan-out** — dashboard ~12 requests default / ~24 with all KPI cards (PERF-03); one HTTP round trip *per KPI card* (`dashboard_screen.dart:695`); over-invalidation of all 16 (`dashboard_providers.dart:112-116`); one guaranteed 404 per load. (b) **Payload sizes** — the unpaginated ledger/statement/report/stock-batches endpoints (PERF-06) serialize their entire result to JSON in one response; at 100k invoices a customer statement is a multi-MB payload the Flutter client must parse on the UI isolate. (c) **Client-side export is bounded by what's loaded** (DR-06), so "export to CSV" silently exports only the current page — a correctness trap, not just a perf one. (d) `autoDispose` providers refetch the whole dashboard on every navigation back.

---

## WHAT IS CORRECT — DO NOT CHANGE

1. **`PRAGMA foreign_keys = ON`** at `database.ts:24`, plus `journal_mode=WAL` (`:27`) and **`busy_timeout=5000`** (`:33`). Verified working: `foreign_key_check` = 0 violations, `integrity_check` = `ok`. Your multi-window SQLITE_BUSY concern is already addressed.
2. **Jest test isolation** — `server/src/__tests__/setup.ts:23-25` redirects `DATABASE_PATH` to a temp dir before any import, with cleanup on `exit`/`SIGINT`/`SIGTERM`. **No test touches the live DB.** Verified by exhaustive grep. Add the fail-closed assertion (TEST-03) but keep the mechanism.
3. **`server/src/scripts/reconcile-stock-cash.ts`** — genuinely read-only and *enforced*: `:46 new Database(dbPath, { readonly: true })`. The well-built script of the three; use it as the template.
4. **`purchaseReturn.test.ts:17-31`** — replays the real migration chain into `:memory:`. The correct pattern for every server test.
5. **Purchase-return test coverage** (`purchaseReturn.test.ts:184-433`, `api.integration.test.ts:480-710`) and **FIFO/FEFO batch coverage** (`models.test.ts:402-620`, incl. halted/expired/NULL-expiry edge cases). Genuinely good.
6. **`fix-duplicate-purchase.ts:61/121`** — `const fix = db.transaction(() => {...}); fix();` — correct atomicity with FKs ON. (Its *backup* is unsafe, DR-01; the transaction is right.)
7. **`journal_lines` CHECK constraints** — `CHECK (debit = 0 OR credit = 0)` and `CHECK (debit >= 0 AND credit >= 0)`. Real invariants enforced in the schema. **Verified: the GL currently balances exactly — ₨15,760.20 debits = ₨15,760.20 credits, zero per-reference imbalance.**
8. **`sanitizeCsvCell`** (`lib/core/utils/csv_export.dart:89`) — strips leading `=+-@`. Correct CSV formula-injection hardening, tested (`test/core/csv_export_test.dart:138`).
9. **`getNextSequenceNumber`** (`server/src/utils/sequence.ts`) — atomic `INSERT … ON CONFLICT DO UPDATE`; correct against races. `initializeSequenceFromMax` validates table/column against allowlists.
10. **`activity_log` has no UPDATE path** — no `router.put/patch`, no `UPDATE activity_log` anywhere. Rows cannot be edited via the API. Keep it that way (and add the same protection against bulk DELETE, AUD-05).
11. **`make_linux_setup.sh:106`** generates a per-install `openssl rand -hex 32` JWT secret. Correct; extend the idea to `DEFAULT_ADMIN_PASSWORD` (currently pinned to `admin123`).
12. **`journal_lines(reference_type, reference_id)`** and **`payment_allocations(invoice_id)`** indexes exist and are used — verified by EXPLAIN QUERY PLAN. Two of the four hot paths you asked about are already right.
13. **Pagination on 17 of 18 list models** — correct `LIMIT/OFFSET` + separate COUNT. Extend the pattern to reports/ledgers; don't rework what's there.
14. **`upload.ts:26-36`** MIME allowlist + 10 MB cap on employee documents.
15. **`security.regression.test.ts`** (379 lines, 30 tests — JWT, CSRF, XSS, SQL injection, Helmet, authz boundary). A real regression net; keep and extend.

---

## UNVERIFIED / OUT OF SCOPE

- **`dart analyze` / `flutter analyze` results — UNVERIFIED.** Neither binary exists in this workspace container. All of `lib/` and 25,638 lines of Dart test code are unchecked for static analysis.
- **Test suites were not executed** (per instructions, to avoid any live-DB risk). Pass/fail status of `jest` and `flutter test` is **UNVERIFIED** — TEST-01's coverage findings are from reading the test source, not from a run.
- **The exact cause of the 12 unvoided orphaned `journal_lines`** is UNVERIFIED — `invoiceController.ts:656` does call `voidJournalLinesByReference`, so either those invoices were deleted by another path, or the void failed silently. The 72 orphaned rows and the ₨420/₨265 misstatement are **measured fact**; attribution to `e2e_expiry_override_test.py` specifically is **inferred** from the id ranges (6-23) and timestamps (2026-08-20), not proven.
- **Whether MIG-02 has already destroyed `payments.invoice_id` on this installation** is UNVERIFIED — it depends on whether the rebuild branch ever fired here. The code defect is certain; the historical damage is not established.
- **PERF estimates at 100k invoices** are analytical projections from EXPLAIN QUERY PLAN on a 6-invoice DB, not measured under load. The query plans and the absence of indexes are measured fact; the second-counts are not.

agentId: a2d4b952f31a7996c (use SendMessage with to: 'a2d4b952f31a7996c', summary: '<5-10 word recap>' to continue this agent)
<usage>subagent_tokens: 197817
tool_uses: 31
duration_ms: 6563220</usage>