# Database Integrity Constraints — Tasks

Covers DB-001, DB-002 (detection half), DB-003, PUR-012, PUR-013, PUR-014,
PUR-015, RET-008. DB-002's prevention half is recorded, not done.

## Phase 0 — Verify every finding against the current code

- [x] 0.1 Confirm DB-001: `PRAGMA index_list('goods_receipt_items')` is empty on
      the live database.
      **done-when:** read-only probe returns zero indexes for all three FK columns.
- [x] 0.2 Confirm DB-003: the ledger holds `'inline'` checksums that verification skips.
      **done-when:** read-only probe shows 66 of 99 rows with `checksum = 'inline'`.
- [x] 0.3 Confirm RET-008: `settled_amount` has a floor at 0 and no ceiling.
      **done-when:** `add-invoice-returns.sql` line 36 shows only
      `settled_amount >= 0`, and the live table holds 0 violating rows of 2.
- [x] 0.4 Confirm PUR-012 / PUR-013 / PUR-014: no quantity floor, no warehouse
      comparison, no balance floor.
      **done-when:** each absence read directly at the cited line.
- [x] 0.5 Establish the ledger's wording is imprecise for RET-008 and PUR-013, and
      decide the correct semantics from the code rather than the prose.
      **done-when:** the `net_amount` ceiling and the NULL-warehouse exemption are
      both justified from `InvoiceReturn.ts:248` and the live rows respectively.

## Phase 1 — DB-001, the index migration

- [x] 1.1 Add `add-goods-receipt-item-indexes.sql` covering `receipt_id`,
      `po_item_id` and `item_id`, idempotently.
      **done-when:** the migration applies to a fresh DB and re-applying is a no-op.
- [x] 1.2 Register it with `runLedgered(...)`.
      **done-when:** the boot path creates all three indexes.

## Phase 2 — RET-008, the settlement ceiling

- [x] 2.1 Add the ceiling as a TRIGGER, not a CHECK.
      **done-when:** `add-invoice-return-settled-ceiling.sql` installs two triggers
      (INSERT and UPDATE) with no table rebuild.
- [x] 2.2 Cap at `net_amount`, not `returned_amount`.
      **done-when:** a settlement of 560 against `net 550` is rejected; 550 and a
      partial 200 are accepted.
- [x] 2.3 Do NOT edit `add-invoice-returns.sql`.
      **done-when:** `git diff` shows no change to any previously applied `.sql`.

## Phase 3 — PUR-012 and PUR-013, the model guards

- [x] 3.1 `addReceipt` rejects `received_quantity <= 0` with a `BusinessRuleError(400)`.
      **done-when:** 0 and -6 both throw before any insert.
- [x] 3.2 `addReceipt` rejects a receipt warehouse differing from the PO's.
      **done-when:** a differing warehouse throws; the PO warehouse is accepted.
- [x] 3.3 The warehouse guard fires only when the PO NAMED one.
      **done-when:** a PO with `warehouse_id IS NULL` still accepts a receipt —
      the first attempt omitted this and broke 22 tests across 5 suites.
- [x] 3.4 The controller maps `BusinessRuleError` to its own status.
      **done-when:** a guard breach returns 400, not 500.

## Phase 4 — PUR-014, the balance floor

- [x] 4.1 Floor both `purchases.balance_amount` projections at 0.
      **done-when:** `MAX(0, p.total_cost - COALESCE(pa.paid_amount, 0))` at both
      sites, matching the PO equivalent.

## Phase 5 — PUR-015, the GL backfill

- [x] 5.1 Skip voided purchases, guarded on the column existing.
      **done-when:** the query carries `voided_at IS NULL` behind a
      `pragma_table_info` probe.
- [x] 5.2 Write the `supplier_ledger` leg for each backfilled goods receipt,
      DEBIT-normal, and skip one that already exists.
      **done-when:** the INSERT is present with an `alreadyLedgered` guard.

## Phase 6 — DB-003, checksum coverage

- [x] 6.1 Hash a `fn.*` body from its own source at apply time.
      **done-when:** `runLedgered` stamps `checksumOfFunction(key, fn)`.
- [x] 6.2 Re-hash those bodies during verification instead of skipping them.
      **done-when:** the blanket `if (checksum === 'inline') continue` is gone.
- [x] 6.3 Adopt a one-time baseline for the 66 legacy `'inline'` rows.
      **done-when:** verification UPDATEs them to the current hash and logs the
      count, instead of aborting every existing install's boot.
- [x] 6.4 Keep the genuine two-real-hash mismatch fatal.
      **done-when:** `if (current !== checksum)` still throws.

## Phase 6b — DB-002, the detection half

- [x] 6b.1 `assertJournalEntriesBalance` compares each `journal_entry_id` group's
      live lines in integer minor units.
      **done-when:** matches the application invariant in `accountingService`, so
      a float-summation artefact cannot fail the boot.
- [x] 6b.2 It runs AFTER the migration sequence, before any HTTP listen.
      **done-when:** placed after the 4150 boot guard. Placed earlier it queried
      `journal_lines` before `fn.initializeDatabase` created it, and a first boot
      exited 1 — caught by running the suite, not by reading the diff.
- [x] 6b.3 It fails loudly, naming the entry ids and the drift.
      **done-when:** the message carries Dr, Cr and the difference, so an operator
      sees the size of the problem without querying.
- [x] 6b.4 Fully voided groups are ignored; half-voided groups are caught.
      **done-when:** both asserted behaviourally.

## Phase 7 — Anti-vacuity

- [x] 7.1 Neutralise each guard in turn and re-run its own test.
      **done-when:** M1–M12 each produce at least one failure; all fixes applied
      gives 35 of 35.
- [x] 7.2 Replace DB-003's source-inspection tests with behavioural ones.
      **done-when:** a tampered `fn.*` ledger row makes `verifyMigrationChecksums`
      throw, and M11 shows that test fails when the hashing is reverted.

## Phase 8 — Verification

- [x] 8.1 `npx tsc --noEmit` — exit 0.
- [x] 8.2 `npx jest --silent` — 124 suites / 1106 tests green.
- [x] 8.5 `npx eslint` on all six changed source files — 0 errors, 0 warnings.
- [x] 8.3 Live database probed read-only; `git status` clean under `database/`
      and `server/database/`.
- [x] 8.4 Archive via the gate — every box above is ticked.

## Recorded, not done

- **DB-002** — `journal_lines` still has no cross-row balance enforcement, and
  cannot get one without a redesign. `postEntry` inserts one statement per line
  and `voidJournalLinesByReference` voids every line of a reference in a single
  `UPDATE`, so a per-row trigger would abort on the first line of any posting
  and on the first line of any void. SQLite has no `DEFERRABLE`. The only sound
  option is a seal: a guaranteed `journal_entries` parent whose final UPDATE
  asserts the group balances — requiring a backfill and rewiring all 5 insert
  sites plus every void path. Put to the user; tracked as BUG-006.