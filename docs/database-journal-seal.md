# DB-002: journal balance at commit

The database now seals each journal automatically at the outer transaction's
commit. The seal means that every journal's active debit and credit totals are
equal in integer cents. It does not make a balanced journal immutable: a complete
void, restore, deletion, or balanced correction remains possible.

## Mechanism

`add-journal-balance-commit-guard.sql` maintains one signed `balance_cents` row
per `journal_entry_id`. Insert, update, and delete triggers apply each line's
rounded debit-minus-credit delta. Voided lines contribute zero. Moving a line
between groups subtracts from the old group and adds to the new group.

The balance references a singleton table whose only permitted key is zero. The
foreign key is `DEFERRABLE INITIALLY DEFERRED`, so transient differences between
individual statements are legal inside a transaction, but a nonzero final balance
prevents commit. SQLite checks an autocommit statement immediately; releasing a
nested savepoint does not bypass the outer transaction check. These semantics
are documented in [SQLite's deferred foreign key documentation](https://www.sqlite.org/foreignkeys.html#fk_deferred).

Each trigger performs indexed key updates rather than scanning all journal
lines. Empty groups retain a zero row. A zero sentinel is created on insertion
if absent, allowing schema-only production fixtures without copying business
records or special-casing their migration list.

SQLite's `REPLACE` can delete a conflicting row without firing its delete
trigger when recursive triggers are disabled. Dedicated guards therefore reject
replacement of an existing journal-line ID, including `UPDATE OR REPLACE` ID
collisions. Ordinary updates and fresh inserts remain available. See
[SQLite's REPLACE documentation](https://www.sqlite.org/lang_conflict.html).

## Integration and rollout

- The ledgered migration runs after historical backfills and builds balances
  from existing lines. Existing imbalance fails and rolls back the migration;
  no historical amounts are silently repaired.
- `postEntry` already wraps its lines in a transaction. `postLegacyStockEntry`
  now also owns a transaction, including its header, for direct callers.
- Whole-entry void and restore statements need no explicit seal calls.
- Historical tax-allocation fixtures perform both sides of their balanced
  reallocation in one transaction. Opening-balance and inventory-write-off
  fixtures likewise commit complete postings. Their existing assertions remain
  intact.
- The existing boot-time balance scan remains an independent detection layer.
  Its corruption fixtures explicitly simulate privileged maintenance with
  foreign keys disabled only during setup, then restore enforcement before
  asserting detection. The new prevention suite never disables foreign keys.
- There is no frontend or API contract change, and no live database was opened
  or migrated during this work.

Foreign keys must remain enabled on each connection, as they are on the server
connection and production fixtures. A privileged maintenance connection that
disables foreign keys, drops triggers, or edits the internal balance tables can
bypass the guard; that is outside its enforcement boundary. Such tools must
validate the actual journal lines before committing and before normal service
resumes. The boot scan is deliberately retained for this case. This mechanism
does not impose new account, period, or journal-header requirements.

## Verification

The initial regression run had eight failures and six passes before the guard.
The expanded direct-SQL suite passes 21 cases covering unmatched autocommit
lines, per-entry rather than global balance, business-write rollback, cents,
partial and complete mutations, nested savepoints, replacement, legacy posting,
historical backfill, migration rollback, and restoration of old voided data.

The first integration run passed 125 of 129 suites. Three suites exposed fixture
writes addressed above; a fourth hit its existing 10-second setup timeout and
passed unchanged on retry. The inventory fixture also passed its targeted retry.
Both remaining fixture suites passed their targeted retry (44 tests). The
purchase-order and inventory suites passed eight tests together. No timeout or
assertion was weakened.

Final verification from `server/`:

- `env TMPDIR=/dev/shm npm test -- --maxWorkers=2 --silent`: **129 suites,
  1,150 tests passed**, 336.968 seconds.
- `npm run typecheck`: passed.
- Direct `npx --no-install eslint` on all seven changed TypeScript files with
  `--max-warnings=0`: passed. There is no `npm run lint` script in this project.
- `git diff --check`: passed.

The existing Jest worker-exit warning and ESLint module-type notice remain.
No Flutter files changed and no manual desktop/mobile UI retest was performed.
