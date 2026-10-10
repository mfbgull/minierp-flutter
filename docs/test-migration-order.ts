// Test-fixture migration harness - investigation record (2026-10-10)
//
// PURPOSE
// Find an authoritative migration order so 24 test files stop each maintaining
// their own hand-written MIGRATIONS array. This is the blocker on DB-002
// prevention (docs/bugs.md BUG-005): no migration that application code depends
// on can be added without editing 24 lists.
//
// RESULT: the naive approach does not work. Do not build a generated .sql list.
//
// ---------------------------------------------------------------------------
// 1. PRODUCTION ORDER, CAPTURED EMPIRICALLY (this part is sound)
// ---------------------------------------------------------------------------
// 88 .sql files on disk. Hooking fs.readFileSync during a real boot against an
// empty DB: 107 reads, 72 unique files, starting at init.sql.
//
// The 34 runLedgered(.sql) entries are NOT the order. Inline fn.* migrations
// interleave their own .sql reads, so neither alphabetical order nor the
// schema_migrations rowid order reproduces a correct sequence. Every .sql read
// in database.ts goes through MIGRATIONS_DIR (45 readFileSync calls, 0
// bypasses), which is what makes the runtime capture complete.
//
// 16 .sql files are never applied at boot. Three of them are applied by test
// fixtures, so this looked like a production defect. It is not: a fresh boot
// already provides every column those three files add
//   add-stock-adjustment-financial.sql -> stock_movements.{financial_value,
//     financial_posted,journal_entry_id}
//   add-customer-ar-fields.sql       -> customers.{credit_limit,
//     current_balance,opening_balance,payment_terms_days}
//   add-returned-amount.sql          -> invoices.returned_amount
// All present on a clean boot via other migrations; these three are redundant
// duplicates. Dropping them from fixtures is schema-neutral.
//
// ---------------------------------------------------------------------------
// 2. WHY A GENERATED .sql LIST IS NOT THE FIX
// ---------------------------------------------------------------------------
// Applying only those 72 .sql files to an empty DB FAILS:
//   add-bom-tables.sql       -> no such column: item_id
//   add-search-indexes.sql   -> no such table: main.quotations
//   add-expired-stock.sql   -> no such column: batch_id
// and leaves 8 of the columns above missing.
//
// The inline fn.* migrations create schema (tables and columns) that later .sql
// files depend on. A .sql-only fixture is not a schema with some extras
// removed - it is a broken schema. Any helper that replays .sql files alone
// will silently diverge from production, which is the exact failure mode the
// 24-list duplication already causes.
//
// ---------------------------------------------------------------------------
// 3. THE FIX THAT ACTUALLY WORKS
// ---------------------------------------------------------------------------
// Export the production migration runner and have fixtures call it, instead of
// reimplementing it in test code. Extract the sequence currently executed at
// module scope in src/config/database.ts into a callable, path-parameterised
// function (e.g. runMigrations(db, migrationsDir)) that both production boot and
// a shared test helper use. Fixtures then get production schema by
// construction: no generated list to keep in sync, no order to get wrong.
//
// Cost: this edits production boot code, which all 124 suites depend on.
// It is the correct design, but it should be done as its own change with its
// own verification, not folded into DB-002.
//
// STATUS: nothing from this investigation is wired in. No helper file exists.
//       No test file was modified. The tree is unchanged.
