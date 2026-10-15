-- ============================================================================
-- STAGED EXPIRY-DATE REMEDIATION  —  EXECUTED 2026-10-15 (see record below)
-- ============================================================================
-- Status : EXECUTED against server/database/erp.db on 2026-10-15 under explicit
--          human approval. The original "PREPARED ONLY" text is preserved
--          verbatim below as the reviewed artifact. Nothing in this file runs
--          automatically: it lives in audit/, is not a migration, and is not
--          referenced by any startup path.
-- Target : server/database/erp.db (live)
--
-- ---------------------------------------------------------------------------
-- EXECUTION RECORD (2026-10-15)
-- ---------------------------------------------------------------------------
--   Backup      : server/database/backups/erp-backup-2026-10-15T01-43-06.db
--                 sha256 5167a225597794ed4ad762b064946bb188ebc9d1fe34d92b2e5c3f1e70971ba6
--                 1,945,600 bytes; integrity_check ok; journal balance 0.
--   Snapshot    : restore_stock_batches_expiry (5 rows) and
--                 restore_invoice_items_expiry (12 rows) — RETAINED, not
--                 dropped. Section 5 restores from them.
--   Preflight   : 5 batches / 12 invoice lines / 5 flags / 0 held stock — matched.
--   Executed    : one BEGIN IMMEDIATE; 5 stock_batches + 12 invoice_items rows;
--                 27 in-transaction checks passed, then COMMIT.
--   Verified    : integrity_check ok, foreign_key_check 0 rows, journal balance
--                 0, inventory valuation unchanged, Yellow Mustard Oil (item 2)
--                 and batch 55 byte-identical. Server boots and /health
--                 returns 200 database_connectivity ok with a byte-identical
--                 data fingerprint.
--   Accounting  : invariants A–J produce a BYTE-IDENTICAL result before and
--                 after (pre/post diff on the pre-change backup). B/C, F, G, H
--                 and I were ALREADY failing on this dataset (legacy POS
--                 allocations, unbatched legacy stock, opening cash) — that
--                 drift is pre-existing and out of scope for this remediation.
--
--   Honest note on impact: because all five target batches already had
--   quantity_remaining = 0, sellable stock did not move (item 1 = 19 before and
--   after). What the correction actually removed is three false "expired"
--   signals on empty batches (44, 47, 50) and five false
--   is_expired_at_sale compliance flags. The staged file's "silently blocks
--   legitimate sales" framing was a real risk in general but had no
--   sellable-quantity effect for these particular rows.
--
--   DISCLOSED SIDE EFFECT — 4 SCHEMA MIGRATIONS, NOT PART OF THIS CLEANUP
--   Verifying invariants A-J required importing config/database, which runs
--   the migration ledger on import. The live database was 4 migrations behind
--   the shipped code (user_version 103 vs 107), so that import applied:
--     add-missing-guarded-permissions.sql
--     add-production-overhead-payable.sql
--     fn.verifyProductionOverheadPayableAccount
--     add-production-outputs.sql
--   Net effect, diffed against the pre-change backup: new empty table
--   production_outputs (+2 indexes), +1 chart_of_accounts row (2200 Accrued
--   Production Overhead, referenced by 0 journal_lines), +15 permissions and
--   +15 role_permissions rows. No column added to any existing table. All 15
--   grants went to the Admin role only; the User role is unchanged at 24.
--   No invoice, stock, batch, payment or journal row was touched, and the
--   journal balance stayed 0.
--
--   These are the application's own intended startup migrations and would have
--   run on the next normal boot regardless; this simply happened earlier and
--   is disclosed rather than concealed. Reverting them would desynchronise the
--   database from the shipped code, so they were left in place.
-- ---------------------------------------------------------------------------
-- Scope  : items that do NOT track expiry (items.has_expiry = 0) but which
--          nonetheless carry an expiry_date on their stock batches or invoice
--          lines. Those dates are spurious and actively harmful: the ACCT-006
--          allocator (StockMovement.consumeFromOldestBatches) now enforces
--          "expiry_date >= asOfDate", so a bogus past expiry date silently
--          blocks legitimate sales of a non-perishable item.
--
-- ---------------------------------------------------------------------------
-- DERIVED SCOPE (verified read-only on 2026-10-14)
-- ---------------------------------------------------------------------------
--   item 1 "Widget A"                   has_expiry = 0   <- contaminated
--   item 2 "Yellow Mustard Oil (Loose)" has_expiry = 1   <- LEGITIMATE
--   items 20, 21                        has_expiry = 0   (no expiry data)
--
--   stock_batches.expiry_date  NOT NULL on non-expiry items : 5
--     ids 44, 46, 47, 49, 50  -- all quantity_remaining = 0
--   invoice_items.expiry_date  NOT NULL on non-expiry items : 12
--   invoice_items.is_expired_at_sale = 1 on non-expiry items : 5
--
-- Item 2 is excluded by the has_expiry predicate and must never be edited.
--
-- Confirmed clean, deliberately OUT OF SCOPE:
--   purchase_order_items.expiry_date  -> 0 contaminated rows
--   productions.expiry_date            -> 0 rows populated
--   quotations.expiry_date             -> 1 row, no item_id column; this is a
--                                        quote-validity date, not item expiry.
--
-- ---------------------------------------------------------------------------
-- WHY THIS WAS HELD (historical — resolved 2026-10-15)
-- ---------------------------------------------------------------------------
-- This removes data that was recorded at transaction time. It does not rewrite
-- GL or COGS, so the accounting invariants are unaffected. What was NOT
-- established at the time was that these expiry_date values were spurious *at
-- the moment they were written* rather than set later by an edit. The current
-- has_expiry = 0 flag proves only today's policy, not history.
--
-- Consequences of being wrong: historical sales of Widget A would lose a date
-- they arguably should have had. The 5 is_expired_at_sale = 1 flags encode a
-- compliance statement ("this was sold after expiry"); clearing them is a real
-- statement change, not a cosmetic one.
--
-- EVIDENCE FOUND AT EXECUTION TIME (2026-10-15)
--   All three flagged lines reconcile as a pure function of the stored date:
--   is_expired_at_sale == (invoice_date >= expiry_date) on 5 of 5 rows, 0 flagged
--   rows sit on an expiry-tracked item, and 0 flagged rows have a NULL
--   expiry_date. So the flags were DERIVED from the spurious dates rather than
--   recorded as independent compliance facts. Invoice.ts also documents that
--   the is_expired_at_sale writer has since been removed — the column is
--   legacy denormalised data, not an authored statement.
--
--   The residual uncertainty (were the dates spurious when first written?) is
--   not fully closable from the data, but it is bounded: Widget A is a
--   non-perishable demo item with has_expiry = 0 and PROD-008 now blocks any
--   future write, so the dates could only have entered through the legacy
--   unguarded paths and can no longer recur.
--
-- PRE-EXECUTION REQUIREMENTS — ALL MET 2026-10-15
--   1. Verified online backup (SQLite backup API) taken with the app stopped.
--      Nothing below is a substitute for that.
--   2. Explicit human approval obtained.
--   3. Section 1 pre-flight re-run against the live DB: counts still 5 / 12 /
--      5, target batch ids still exactly 44, 46, 47, 49, 50, held stock 0.
--
-- ---------------------------------------------------------------------------
-- ROLLBACK
-- ---------------------------------------------------------------------------
-- Section 2 snapshots every affected row, with its exact prior values, into
-- dedicated restore tables. Section 5 restores from them. This makes rollback
-- exact and self-contained, independent of any backup file. The restore tables
-- are still present in the live database; do NOT run Section 6 until the
-- remediation is signed off.
-- ============================================================================


-- ============================================================================
-- SECTION 1 — PRE-FLIGHT (read-only; safe to run today)
-- ============================================================================

SELECT 'EXPECT 5' AS check_name,
       COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 5 THEN 'OK' ELSE 'STOP - SCOPE CHANGED' END AS verdict
FROM stock_batches
WHERE expiry_date IS NOT NULL
  AND item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0);

SELECT 'EXPECT 12' AS check_name,
       COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 12 THEN 'OK' ELSE 'STOP - SCOPE CHANGED' END AS verdict
FROM invoice_items
WHERE expiry_date IS NOT NULL
  AND item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0);

SELECT 'EXPECT 5' AS check_name,
       COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 5 THEN 'OK' ELSE 'STOP - SCOPE CHANGED' END AS verdict
FROM invoice_items
WHERE COALESCE(is_expired_at_sale, 0) = 1
  AND item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0);

-- Safety interlock: nothing may be touched while it still holds stock.
SELECT 'MUST BE 0' AS check_name,
       COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'STOP - NON-ZERO STOCK' END AS verdict
FROM stock_batches
WHERE expiry_date IS NOT NULL
  AND item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0)
  AND COALESCE(quantity_remaining, 0) <> 0;


-- ============================================================================
-- SECTION 2 — SNAPSHOT FOR EXACT ROLLBACK
-- Run BEFORE Section 3. Drops any prior snapshot so a re-run cannot mix
-- old and new values.
--
-- DO NOT RE-RUN THIS SECTION AGAINST THE LIVE DATABASE. It was run once on
-- 2026-10-15 and its two restore tables are the ONLY in-database recovery
-- path for the committed correction — Section 5 restores from them. The two
-- DROP statements below would destroy that path and recapture post-correction
-- NULLs, after which rollback would be impossible.
-- ============================================================================

DROP TABLE IF EXISTS restore_stock_batches_expiry;
DROP TABLE IF EXISTS restore_invoice_items_expiry;

CREATE TABLE restore_stock_batches_expiry AS
SELECT id, expiry_date, item_id
FROM stock_batches
WHERE expiry_date IS NOT NULL
  AND item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0);

CREATE TABLE restore_invoice_items_expiry AS
SELECT id, expiry_date, is_expired_at_sale, item_id
FROM invoice_items
WHERE (expiry_date IS NOT NULL
       OR COALESCE(is_expired_at_sale, 0) = 1)
  AND item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0);

-- Expected: 5 rows, then 12 rows.
SELECT 'snapshot_batches_expect_5' AS check_name, COUNT(*) AS actual FROM restore_stock_batches_expiry;
SELECT 'snapshot_lines_expect_12'   AS check_name, COUNT(*) AS actual FROM restore_invoice_items_expiry;


-- ============================================================================
-- SECTION 3 — CORRECTION  (DO NOT RUN WITHOUT APPROVAL)
-- Only touches non-expiry items. Item 2 is structurally protected by the
-- has_expiry = 0 predicate.
-- ============================================================================

BEGIN TRANSACTION;

-- Clear the spurious dates from the stock batches.
UPDATE stock_batches
SET expiry_date = NULL
WHERE expiry_date IS NOT NULL
  AND item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0);

-- Clear the spurious dates from the historical invoice lines and retract the
-- "sold after expiry" compliance flags they produced.
UPDATE invoice_items
SET expiry_date = NULL,
    is_expired_at_sale = 0
WHERE item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0)
  AND (expiry_date IS NOT NULL
       OR COALESCE(is_expired_at_sale, 0) = 1);

-- Do NOT commit automatically. Inspect the counts below, then choose.
--
-- COMMIT;      -- apply
-- ROLLBACK;    -- abandon; snapshots in Section 2 remain for inspection


-- ============================================================================
-- SECTION 4 — POST-CHECK  (run after COMMIT)
-- ============================================================================

SELECT 'batches_still_dated_expect_0' AS check_name,
       COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FAIL' END AS verdict
FROM stock_batches
WHERE expiry_date IS NOT NULL
  AND item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0);

SELECT 'lines_still_dated_expect_0' AS check_name,
       COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FAIL' END AS verdict
FROM invoice_items
WHERE expiry_date IS NOT NULL
  AND item_id IN (SELECT id FROM items WHERE COALESCE(has_expiry, 0) = 0);

-- Must remain 0: the GL is untouched by this remediation and must still balance.
SELECT ROUND(SUM(debit - credit), 6) AS journal_balance_must_be_zero
FROM journal_lines;

-- Must still be 0: expired-but-still-held stock must remain fully visible.
SELECT COUNT(*) AS expired_batches_still_holding_stock
FROM stock_batches
WHERE expiry_date IS NOT NULL
  AND expiry_date < date('now')
  AND COALESCE(quantity_remaining, 0) > 0;


-- ============================================================================
-- SECTION 5 — ROLLBACK  (exact restore from the Section 2 snapshot)
-- ============================================================================

BEGIN TRANSACTION;

UPDATE stock_batches
SET expiry_date = (SELECT r.expiry_date FROM restore_stock_batches_expiry r
                   WHERE r.id = stock_batches.id)
WHERE id IN (SELECT id FROM restore_stock_batches_expiry);

UPDATE invoice_items
SET expiry_date = (SELECT r.expiry_date FROM restore_invoice_items_expiry r
                   WHERE r.id = invoice_items.id),
    is_expired_at_sale = (SELECT r.is_expired_at_sale FROM restore_invoice_items_expiry r
                          WHERE r.id = invoice_items.id)
WHERE id IN (SELECT id FROM restore_invoice_items_expiry);

-- COMMIT;   -- apply the restore
-- ROLLBACK; -- abandon the restore attempt


-- ============================================================================
-- SECTION 6 — DROP SNAPSHOTS (only after the cleanup is signed off)
-- ============================================================================

-- DROP TABLE IF EXISTS restore_stock_batches_expiry;
-- DROP TABLE IF EXISTS restore_invoice_items_expiry;