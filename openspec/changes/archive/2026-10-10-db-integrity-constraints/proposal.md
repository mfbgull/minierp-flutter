# Database Integrity Constraints — DB-001, DB-002 (detection), DB-003, PUR-012, PUR-013, PUR-014, PUR-015, RET-008

## What Changes

- `migrations/add-goods-receipt-item-indexes.sql` — **new**, indexes all three
  FK columns on `goods_receipt_items`.
- `migrations/add-invoice-return-settled-ceiling.sql` — **new**, a trigger
  capping `invoice_returns.settled_amount` at `net_amount`.
- `config/database.ts` — `runLedgered` stamps a `fn.*` migration with a hash of
  its own function body; `verifyMigrationChecksums` re-hashes those bodies and
  adopts a one-time baseline for rows previously recorded as `'inline'`.
- `models/PurchaseOrder.ts` — `addReceipt` rejects a non-positive
  `received_quantity`, and a receipt warehouse that differs from a warehouse the
  PO actually named.
- `models/Purchase.ts` — both `balance_amount` projections floor at 0.
- `migrations/backfillGlPreposting.ts` — skips voided purchases; writes the
  missing `supplier_ledger` leg for goods receipts.
- `controllers/purchaseOrderController.ts` — maps `BusinessRuleError` to its own
  status instead of collapsing every receipt error to 500.
- `config/database.ts` — `assertJournalEntriesBalance` asserts at boot that every
  `journal_entry_id` group of live lines balances (DB-002 detection half).
- `__tests__/dbIntegrityConstraints.test.ts` — **new**, 35 tests.

Deltas recorded against `migration-ledger`, `query-performance`,
`invoice-returns`, `batch-source-typing`, `purchase-returns` and
`gl-posting-matrix`.

## Why

Eight findings, one theme: **the database was the last line of defence and had
none left.** Constraints that exist only in application code are constraints
that a raw-SQL maintenance path, a rollback CLI, or a non-HTTP caller walks
straight past.

## The eight

| # | Finding | Defect |
|---|---|---|
| 1 | DB-001 | `goods_receipt_items` had three FKs and **zero** indexes; the `goods_receipts` ON DELETE CASCADE full-scanned the receipt hot path |
| 2 | DB-003 | 66 of 99 ledger rows carried checksum `'inline'` and verification **skipped every one**, so editing an applied inline migration was invisible |
| 3 | RET-008 | `settled_amount` shipped with a floor at 0 and no ceiling, so a return could settle for more than it owes |
| 4 | PUR-012 | `addReceipt` checked only the upper bound: `0` created four zero-valued rows silently, `-6` surfaced as a 500 carrying a raw SQLite message |
| 5 | PUR-013 | a receipt into a different warehouse was accepted, silently moving stock somewhere the PO never authorised |
| 6 | PUR-014 | `purchases.balance_amount` had no floor, so over-allocating a payment produced a negative "Amount Due" |
| 7 | PUR-015 | the GL backfill re-posted voided purchases, and posted goods receipts to GL with no `supplier_ledger` leg |

## DB-002 — the detection half landed, prevention did not

`journal_lines` still has no write-time prevention, and it **cannot** get one
without redesigning the GL engine. The reason is worth recording because it looks
like an oversight otherwise:

- `postEntry` inserts lines **one statement per line**, so a row trigger
  asserting the group sums to zero fires on line 1 and would abort every
  legitimate posting.
- `voidJournalLinesByReference` voids every line of a reference with a **single**
  `UPDATE ... SET voided = 1`. A per-row trigger would see a half-voided group
  and abort every void.

SQLite has no `DEFERRABLE` constraint, so the only sound enforcement is a *seal*:
a parent row whose final UPDATE asserts the group balances. That means creating
a guaranteed `journal_entries` parent for the `journal_lines` grouping (the one
that exists today is optional and carries a different two-leg shape), backfilling
it, and routing all 5 insert sites and every void path through it. **Two prevention attempts were implemented, measured, and reverted.** Both are
recorded here so they are not repeated:

| attempt | scope | result |
|---|---|---|
| trigger on `DELETE` | any delete leaving the group unbalanced | **19 tests / 34 suites failed** — suites legitimately delete journal lines while cleaning up fixtures and drifted entries, and repairing damage is itself a delete |
| trigger on `UPDATE OF debit, credit` for live lines | the one operation no production path performs | **4 tests failed** — `taxGlRepairMigration`'s `corruptToGrossTax` fixture deliberately edits live credits to CREATE drift for the repair migration to fix |

The second is decisive. A guard that forbids manufacturing drift also forbids the
test proving drift is repairable, and would eventually forbid any repair that
corrects an existing entry by editing its amounts. Enforcement strong enough to
stop that is strong enough to block the fix. Note the production repair path
(`backfillInvoiceTaxGl`) repairs by void-and-repost through `postEntry`, never by
editing amounts — so the trigger blocked no real repair, only the proof that
repair works.

So **prevention** remains an architectural change to every GL write, tracked as
BUG-005, and is put to the user rather than taken unilaterally.

**Detection** did land, and it is the half that closes the audit's actual stated
vectors. `assertJournalEntriesBalance` runs at boot after the migration sequence
and before any HTTP listen, comparing each group's live lines in integer minor
units (so float artefacts cannot fail it) and aborting with `process.exit(1)`
that names the entry ids and the drift. The FK-OFF rebuild path and the
`--rollback` CLI both run under this gate, so raw SQL that writes an unbalanced
entry now fails the boot loudly instead of silently poisoning every report.
Fully voided groups are ignored; a half-voided group is caught.

Placement matters: the assertion must run AFTER `fn.initializeDatabase`, or a
first boot queries `journal_lines` before it exists and exits.

## Two places the ledger was imprecise

1. **RET-008** is worded as "exceeds the return's `returned_amount`". The
   column's own comment already said `≤ net_amount`, and `InvoiceReturn.ts:248`
   flips a return to `Settled` on `settled_amount >= net_amount`. Honouring
   `returned_amount` literally would let a return settle the restocking fee back
   out — the exact defect the constraint exists to prevent. Capped at
   `net_amount`; live rows confirm it (`returned 600, fee 50, net 550,
   settled 550`).
2. **PUR-013** as written rejects any warehouse difference. A PO with
   `warehouse_id IS NULL` authorises no particular warehouse, so the guard fires
   only when the PO **named** one. The first attempt omitted that and broke 22
   tests across 5 suites.

## Anti-vacuity, both directions

Every guard was neutralised in turn and its own test re-run. A guard whose test
still passes when the guard is deleted is not a guard.

| mutation | result |
|---|---|
| M1 — unregister the index migration | **4 failed** ✓ |
| M2 — unregister the ceiling trigger | **4 failed** ✓ |
| M3 — drop the `received_quantity > 0` guard | **2 failed** ✓ |
| M4 — drop the warehouse guard | **1 failed** ✓ |
| M5 — unfloor `purchases.balance_amount` | **1 failed** ✓ |
| M6 — unfilter voided purchases in the backfill | **1 failed** ✓ |
| M7 — drop the `supplier_ledger` leg | **2 failed** ✓ |
| M8 — restore the blanket `'inline'` skip | **2 failed** ✓ |
| M9 — drop the baseline adoption | **1 failed** ✓ |
| M10 — re-tighten PUR-013 to reject NULL warehouses | **1 failed** ✓ |
| M11 — revert the inline body hashing | **3 failed** ✓ (incl. the behavioural abort test) |
| M12 — neutralise the boot balance assertion | **3 failed** ✓ |
| all fixes applied | 35 of 35 pass |

The tests assert the ledger and schema consequences, not just that no exception
was thrown.

DB-003's tests were initially **source inspection only** — regexes over
`database.ts` asserting the right statements exist. Those pass even if the
mechanism is entirely dead, so they were joined by behavioural tests that read
the real ledger: every `fn.*` row carries a 16-hex body hash, none is stuck at
`'inline'`, a clean ledger verifies, and a tampered row makes
`verifyMigrationChecksums` throw. M11 confirms the behavioural one fails when the
hashing is reverted.

## Full verification

- `npx jest --silent` — **124 suites / 1106 tests green**
- `npx tsc --noEmit` — exit 0
- Live database probed **read-only**: 33 file-backed ledger rows all still match
  their checksum (so the boot gate stays clean), and the 66 `'inline'` rows are
  adopted as a baseline rather than aborting every existing install.
- `server/database/erp.db` never written.

## Risk and rollback

**DB-003 is the one that can take an install offline.** 66 legacy rows carry
`'inline'`. Aborting on them would fail every boot, so verification adopts the
current body as the baseline once and enforces from then on. An inline migration
edited *before* this change is therefore still not detected — unavoidable, as no
earlier record of it exists. This is logged at boot.

**PUR-013 and PUR-012** reject requests that previously succeeded. That is the
point, but callers relying on the permissive behaviour will now see 400s.

**RET-008** caps settlements that previously succeeded. Live data has 0
violating rows of 2, so no repair is needed.

Rollback: revert 4 source files and drop 2 migration files. No data change; the
new migrations are additive indexes and triggers only.