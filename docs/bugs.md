# Known Bugs — not yet fixed

Backlog of defects that are **confirmed or suspected but deliberately unfixed**.
Each entry says what was observed, how it was observed, and what is still unknown,
so the next person does not have to re-derive it.

For audit findings and their disposition see [`audit-coverage-ledger.md`](audit-coverage-ledger.md)
(67 rows — 65 canonical Part-0 IDs plus DB-004, DB-005/006/007/008, SALES-020,
PRET-001 and RET-008; counts recounted and verified to foot). This file holds
defects found *outside* that audit pass, plus audit rows whose code fix was
reverted.

Status values: `FIXED` (done, kept for regression context) · `OPEN` (unfixed,
actionable) · `NEEDS-INVESTIGATION` (observed, root cause not established).

> **Concurrency note.** At least one other session was editing
> `sales_invoice_form_page.dart`, `invoice_rules.dart` and
> `extra_calculations_test.dart` while BUG-001 was being fixed. BUG-002 was
> landed by that session, not by the author of BUG-001 — reconcile the diffs
> before committing, and check `git status` for files you did not touch.

---

## BUG-001 · Overpaying at invoice creation saved an unpaid invoice with no warning

**Status:** `FIXED` — `lib/features/sales/sales_invoice_form_page.dart`
**Found:** 2026-10-08 · **Severity:** high (silent data loss)

### Symptom

Entering a payment larger than the invoice grand total on the create form saved
the invoice, recorded **no** payment, left the invoice `Unpaid`, and showed no
warning or error. The user was told "Invoice saved successfully!".

### Root cause — three compounding defects, all client-side

The **server was correct throughout**. Verified directly against the API:

| step | result |
|---|---|
| `POST /invoices` with `record_payment:true`, no `payment` block | `201`, `status=Unpaid`, `paid=0` |
| `POST /payments` 150 against a 100 total | `400` `"Allocation amount (150.00) for invoice 1 exceeds the remaining balance (100.00)"` |
| `POST /payments` exactly 100 | `201`, invoice becomes `Paid` |

1. **Create mode is a two-step flow.** The form sends `record_payment: true`
   with **no `payment` block** (`_buildBody`), so the invoice is created unpaid;
   each payment method is then posted separately to `POST /payments`. The
   rejection therefore only surfaces from the *second* call.
2. **The result was discarded.** `_save()` called
   `await _postPaymentBodies(bodies, stopOnFirstFailure: false)` without using
   its `bool`, so the save reported success no matter what the payment returned.
3. **The error toast was erased.** `_submit()` then popped the page and showed
   "Invoice saved successfully!"; `showAppToast` calls `..hideCurrentSnackBar()`
   first (`lib/widgets/app_toast.dart:18`), so the success toast silently
   replaced the server's rejection message.

Compounding it: `_validatePayment()` already contained the correct
`doesPaymentExceedBalance` check, but its **only** call site was inside
`_recordPayments()`, documented *"Edit mode only"*. Create mode never validated.

### Fix

- Create-mode overpayment guard in `_save()`, before anything is persisted,
  compared against the total **before** the payment is applied.
  `_remainingBalance` is deliberately *not* reused there — it is the balance
  *after* the payment (see BUG-002).
- `_postPaymentBodies` records the first rejection; `_submit()` and
  `_saveAndPrint()` no longer report success or pop when a payment was
  rejected, and show the server's reason instead.
- Added `surfaceErrors` so the message is not shown twice.

### Regression coverage

`test/sales_invoice_form_page_test.dart` → group `overpayment at creation`
(2 tests). Both verified **red before** the fix and green after.

---

## BUG-002 · `_validatePayment()` compared the payment against the balance *after* it

**Status:** `FIXED` — `sales_invoice_form_page.dart:658,749`
**Found:** 2026-10-08 · **Severity:** high — fixed in a concurrent session, not by the author of BUG-001

### The arithmetic

`_validatePayment()` called:

```dart
if (doesPaymentExceedBalance(_paymentSum, _remainingBalance)) { ... }
```

`_remainingBalance` is the balance **after** this payment
(`balance − _paymentSum − _creditOffset`), but the callee's contract is the
opposite — its second argument is the balance **before**:

```dart
bool doesPaymentExceedBalance(num totalPaymentAmount, num remainingBalance) =>
    totalPaymentAmount > remainingBalance;
```

confirmed by its unit test (`test/calculations/extra_calculations_test.dart:308`):

```dart
expect(doesPaymentExceedBalance(110, 100), true);
expect(doesPaymentExceedBalance(90, 100), false);
```

So `_paymentSum` was compared against a figure that had already had
`_paymentSum` subtracted — the payment counted twice. For a 1,000 balance:

| payment | `_remainingBalance` | check | expected |
|---|---|---|---|
| 400 | 600 | `400 > 600` → pass | pass |
| 600 | 400 | `600 > 400` → **blocked** | pass |
| 1,000 | 0 | `1000 > 0` → **blocked** | pass |

The threshold sat near **half** the balance instead of the full balance.

### Fix

Add the in-progress payment back before comparing, keeping `_remainingBalance`
for its *display* use where "balance after this payment" is the right figure:

```dart
num get _balanceBeforePayment => _remainingBalance + _paymentSum;
```

`_validatePayment` now calls `doesPaymentExceedBalance(_paymentSum,
_balanceBeforePayment)`. Backed by a doc comment on `doesPaymentExceedBalance`
spelling out the operand contract, and by a regression test (`full payment
against the balance is allowed`).

### Note on the investigation

While diagnosing this, a widget-test probe against `_editInvoice()` (balance
1,000) posted **nothing** for 499, 500, 501 and 999, and showed no error. That
contradicted the arithmetic, which predicts 499 should pass — the probe most
likely never registered the amount on the payment method, leaving
`_paymentBodies()` empty (it filters on `m.amount > 0`).

**That probe result was a harness artefact and was never reproduced as a product
defect.** It is recorded only so the same false alarm is not re-derived.

## BUG-003 · SALES-008 reverted: `INVOICE_SETTLEMENT` ceiling ignores prior payments

**Status:** `OPEN` (recorded `won't-fix` in the audit ledger, guard enforced)
**Severity:** high if it ever becomes reachable

The audit finding is correct as written: the `INVOICE_SETTLEMENT` branch of
`allocationCeiling` (`server/src/services/paymentValidation.ts`) uses the invoice
**gross total**, so it ignores payments already received.

It is **not reachable today**. That mode has exactly one production caller,
`InvoiceCreationService.create`, which records the payment in the same
transaction that creates the invoice — so the row is already stored as settled
when the ceiling is evaluated, and the gross total is correct there. The audit's
prescribed `max(0, balance_amount)` fix would reject **every** fully-paid
invoice at creation. An earlier attempt at
`total − (returned + paid)` broke exactly that and was reverted.

The finding is now enforced rather than merely documented: a source scan in
`settlementCashIntegrity.test.ts` asserts exactly one call site and pins the
ceiling expression, and it was proved non-vacuous by injecting a second caller.

**Open decision:** whether to close it by construction — give invoice creation
its own mode and make `INVOICE_SETTLEMENT` balance-bounded — which would need the
guard test widened to match.

---

## BUG-004 · C-04 blocked on the inventory batch/lot rewrite

**Status:** `CLOSED` — untraceable, and superseded by the batch/lot rewrite
**Severity:** medium
**Checked:** 2026-11-14 · **Closed:** 2026-11-15

Closed. The record is kept, not deleted, so the ID is not reused and the
reason is on file.

This entry is stale on two counts.

1. **The blocker is gone.** The batch/lot rewrite it waited on has landed.
   `batch_stock_by_location`, `stock_reservations`, `invoice_return_batches`
   and `locations` all exist in the schema, and `inventory-batch-lot-spec` is
   fully checked off except task 8.6 (a deliberate deferral). A dependency on
   that change can no longer hold anything back.
2. **The finding cannot be found.** `C-04` appears in no audit archive or
   findings table. No `C-04` row exists to remediate, so there is nothing to
   unblock.

Action: the underlying concern is superseded. The batch/lot rewrite landed
(`batch_stock_by_location`, `stock_reservations`, `invoice_return_batches`,
`locations`), so the code that `C-04` referred to no longer exists in that
shape. No concrete defect could be found against the current code, and the ID
appears in no audit archive or findings table. No code was touched. If a
concrete defect is ever found, open a new entry with its own evidence rather
than reopening this ID.

---

## BUG-005 · Database-level prevention of unbalanced journals (DB-002)

**Status:** `FIXED` — detection and commit-time prevention shipped · **Severity:** HIGH
**Audit row:** DB-002

The production-schema fixture migration removed the old test-harness blocker.
The new `add-journal-balance-commit-guard.sql` uses trigger-maintained integer
balances and a deferred foreign key to zero. Every group must balance at commit;
intermediate states inside a transaction are allowed. This supports complete
posting, voiding, restoration, deletion, and balanced corrections without a
separate application seal call. See [design and validation](database-journal-seal.md).

### Historical analysis and reverted attempts (superseded)

The notes below record the earlier investigation, not the current constraints.

### The finding

`add-gl-foundation.sql` gives `journal_lines` only PER-LINE checks
(`debit = 0 OR credit = 0`). There is no cross-row constraint and no trigger, so
"debits == credits" is enforced only in application code at
`accountingService.ts:300-311`. The FK-OFF non-transactional rebuild path and
the `--rollback` CLI execute raw SQL with no such guard.

### Why it is not simply a missing trigger

A row-level trigger asserting the group sums to zero cannot work here, and
adding one would break the system rather than protect it:

- **`postEntry` inserts one statement per line** (`accountingService.ts:393-410`).
  The trigger would fire on line 1 of a balanced two-line entry and abort every
  legitimate posting.
- **`voidJournalLinesByReference` voids every line of a reference in a SINGLE
  `UPDATE ... SET voided = 1`.** A per-row trigger would observe a half-voided
  group and abort every void in the system.

SQLite cannot defer a `CHECK` constraint. It does support deferred foreign keys;
the final implementation uses that distinction to enforce balance at commit.

### The only sound option, and its cost

A **seal**: a guaranteed parent row whose final UPDATE asserts the group
balances. That requires

1. creating a `journal_entries` table for the `journal_lines` grouping — the one
   that exists today is OPTIONAL (only `add-stock-adjustment-financial.sql`
   creates it) and has a different two-leg shape (`debit_account`,
   `credit_account`, `amount`), so it cannot be reused as-is;
2. backfilling a parent row for every existing `journal_entry_id` group;
3. routing all **5** `INSERT INTO journal_lines` sites through a seal step;
4. routing every void path through a matching unseal.

That is a redesign of every GL write, against a suite where 123 of 124 suites
encode GL invariants. It is put to the user rather than taken unilaterally.

### What IS now enforced — the detection half

`assertJournalEntriesBalance` runs at boot, after the migration sequence and
before any HTTP listen. It compares each `journal_entry_id` group's live lines in
**integer minor units** (matching the application invariant, so float artefacts
cannot fail it) and aborts with `process.exit(1)` naming the entry ids and the
drift. Fully voided groups are ignored.

So an unbalanced entry written by raw SQL — the FK-OFF rebuild path, the
`--rollback` CLI — now fails the boot loudly instead of leaving books that every
report then reads. Covered by 5 behavioural tests, proved non-vacuous by M12.

### Two prevention attempts, both reverted — do not repeat them

Both were implemented, measured against the full suite, and removed.

**Attempt 1 — a trigger on `DELETE`.** Fires whenever the surviving lines of an
entry do not balance, which includes routine teardown. Result: **19 tests across
34 suites failed**, 18 of them with `cannot delete a journal line that would
leave its entry unbalanced`. Suites legitimately delete journal lines while
cleaning up fixtures and drifted entries, and repairing damage is itself a
delete — so guarding it protects less than it costs.

**Attempt 2 — a trigger on `UPDATE OF debit, credit` for live lines.** Scoped
precisely to the one operation no production path performs, so it broke no
posting, void or repair (`backfillInvoiceTaxGl` repairs by void-and-repost via
`postEntry`, never by editing amounts). Result: **4 tests failed** in
`taxGlRepairMigration.test.ts`, whose `corruptToGrossTax` fixture deliberately
edits live credits to CREATE drift for the repair migration to fix.

That second failure is the decisive one. A guard that forbids manufacturing
drift also forbids the test that proves drift is repairable, and would in time
forbid any future repair that corrects an existing entry by editing its amounts.
Enforcement strong enough to stop that is enforcement strong enough to block the
fix. Ship the detection, not the prohibition.

### A third attempt — the seal — hit a blocker bigger than DB-002

A **seal** design sidesteps all four operations above: an entry is built freely,
then sealed in one separate statement that the database checks atomically. Sealing
asserts the live lines balance, and a `BEFORE INSERT` trigger on `journal_lines`
refuses to add lines to a sealed entry, so a balanced entry cannot later be
broken. Void/un-void never add a line, so neither trips it.

It was implemented — migration, triggers, and the seal call in
`AccountingService.postEntry` — and reverted, for a reason unrelated to the GL:

> `SqliteError: no such table: journal_entry_seal` — 38 occurrences, 51 tests,
> 11 suites.

**24 test files maintain their own hand-written list of migrations to apply**, and
**15 of them call `AccountingService`**. None had the new migration, so the seal
insert failed. The production boot path was fine; the fixtures were not.

This is a structural limitation of the test harness, and it is worth more than
DB-002: **the project currently cannot add ANY migration that runtime code
depends on.** A migration that only adds indexes or triggers is invisible to
those fixtures and lands safely (as DB-001 and RET-008 did). A migration that
application code then reads from breaks them.

Two ways forward, neither chosen unilaterally:

1. Add the migration to each of the 24 lists — works, but every future migration
   that runtime code depends on must be added 24 times, and any list missed
   breaks as a confusing `no such table` at a distance from its cause.
2. Make the fixtures apply the whole `src/migrations` directory instead of a
   hand-picked subset. Removes the duplication permanently. It is a real
   refactor: some fixtures deliberately apply a SUBSET (e.g. an invoice-return
   suite that omits later migrations), and applying all of them may change what
   those tests exercise.

Option 2 is the fix. It is also a separate piece of work from DB-002.

### What stays unenforced until the redesign lands

Raw SQL can still *write* an unbalanced entry; the boot gate only notices on the
next start. Nothing prevents it at write time.

## BUG-006 · `sales_order_items` has no tax or discount columns

**Status:** `FIXED` — **Severity:** medium-high
**Found:** 2026-11-14 · **Fixed:** 2026-11-15 · branch `feat/bug-006-so-tax-discount`

SALES-016: a sales order could not carry per-line tax or discount, so converting
one to an invoice either dropped those values or hard-coded `discount_type: 'none'`.

Fix: migration `126_sales_order_item_tax_discount.sql` adds `tax_rate`,
`discount_type` and `discount_value` to `sales_order_items` (additive, defaults
`0` / `'none'` / `0`, no backfill). The server recomputes every line amount and the
header total from the sent rate and discount — it never trusts a client total.
`convertToInvoice` now sends the real per-line values and omits `amount`, because
`decomposeLineAmount` treats a positive `amount` as a gross override (passing the
stored tax-inclusive amount double-applied the tax and discount). The Flutter form
collects a tax rate and a discount (none / amount / percent) per line, and both
sides round with the same rule.

Tests: 16 server, 7 Dart parity, 3 form widget.

---

## BUG-008 · No way to void a refund receipt from the app

**Status:** `FIXED` — `lib/features/purchases/void_refund_dialog.dart` · **Severity:** medium
**Found:** 2026-11-14 · PRET-002 follow-up
**Fixed:** 2026-11-14 (`72d18d6f`)

The server can void a supplier refund receipt (`POST /supplier-refunds/:id/void`)
and correctly refuses the void with `409` plus a structured `details` blocker list
when the cash or bank day would go negative. The Flutter client cannot reach that
path.

### Why this exists

Refunds are only ever *created*, from the purchase-return detail dialog. Nothing
lists a supplier refund, so there is no row to act on and no void button anywhere
in `lib/`. This is not an oversight in one screen — the listing surface was never
built.

### What is already in place (do not rebuild)

- `ApiError.cashBlockers` parses the `409` `details` array into typed
  `CashBlocker {id, date, amount, type}` rows (`lib/data/repositories/api_result.dart`).
  `blockedBy` is a separate, unchanged field.
- `CashBlockersList` (`lib/widgets/cash_blockers_list.dart`) renders the rows with
  the guard title, a retry hint, and an "and N more" cap.
- `showVoidRefundDialog` (`lib/features/purchases/void_refund_dialog.dart`) posts
  the void with a mandatory reason and shows the blocker list on `409`. Nothing
  calls it yet.

All three are covered by tests (`cash_blockers_test.dart`,
`cash_blockers_list_test.dart`).

### The follow-up change must cover

1. A **Receipts** section on the refund-claim row showing each receipt against
   the claim.
2. A server **filter** to fetch refunds by claim (`GET /supplier-refunds?claim_id=`
   — no such filter exists today; `SupplierRefundModel.getAll` takes only
   `supplier_id`).
3. The **void dialog** wired to that row, with confirmation, reason, and role
   gating consistent with the claim endpoints (`supplier_refunds` / `void`).
4. The `409` **blocker list** shown in the void dialog — `showVoidRefundDialog`
   already does this; it only needs a caller.

---

## BUG-007 · Released AppImage had no AppRun — `execv error: No such file or directory` on launch

**Status:** `FIXED` (pipeline) — `.github/workflows/release.yml`, "Package AppImage" step
**Found:** 2026-10-30 · **Severity:** high (shipped asset does not launch at all)

### Symptom

`MiniERP-0.2.0-alpha.1-linux-x64.AppImage` failed to launch with
`execv error: No such file or directory`. Extracting the squashfs layer
(`--appimage-extract`) showed only the desktop entry, icon and `usr/`;
`AppRun` — the entry point the AppImage bootloader executes — was absent.
The payload itself (Flutter bundle, libraries, embedded Node server) was intact.

### Root cause

The CI step handed the AppDir to `linuxdeploy --output appimage` and relied on
linuxdeploy's AppRun generation. No AppRun appeared in the built image. The
exact linuxdeploy behaviour that dropped it was not established (the step pins
the *continuous* release, so a moving target); the fix removes the dependence
rather than chase that mystery.

### Fix

- The step now writes an explicit custom `AppRun` script into the AppDir root
  before invoking linuxdeploy. linuxdeploy deploys a custom AppRun as-is
  (documented first-class behaviour), so the image no longer depends on
  linuxdeploy's generation step. The script resolves its own directory,
  defaults `APPDIR` if unset, and execs `usr/bin/minierp_app`.
- The post-build `--appimage-extract` verification now includes
  `test -x squashfs-root/AppRun` — the check the original packaging lacked.

### Verification

Reproduced locally with the CI steps mirrored against the release bundle:

- squashfs built without AppRun → the new check fails (red), matching the
  shipped 0.2.0-alpha.1 defect.
- Fixed flow with linuxdeploy → `squashfs-root/AppRun` present and executable;
  all checks pass. Executing the packaged AppRun launched the Flutter binary
  (Impeller initialised) — the exact chain that previously died with `execv`.

The broken 0.2.0-alpha.1 asset was replaced locally by a repaired build; the
first asset picked up by this workflow fix will not need that repair.

Follow-up hardening (same day): the step previously pulled the *continuous*
linuxdeploy build. It is now pinned to stable release `1-alpha-20251107-1`
with an embedded SHA-256 check, so a bad upstream build cannot silently reach
the pipeline again. Re-verified locally with the pinned binary: checksum OK,
AppRun present, app launches.

---

## BUG-012 · CI fallow gate ran without coverage — red on every push since 2026-10-26

<!-- Renumbered from a duplicate BUG-008 (2026-11-15). The refund-void item
     at BUG-008 above is the one PRET-002/FINDINGS-STATUS refers to, so this
     later, unreferenced item takes the next free number. -->

**Status:** `FIXED` (CI) — `.github/workflows/ci.yml`, fallow job
**Found:** 2026-10-30 · **Severity:** medium (a quality gate silently dead)

### Symptom

Every `CI` run since 2026-10-26 failed `fallow` with
`Error: coverage: failed to read coverage file server/coverage/coverage-final.json`,
while `server` and `flutter` jobs passed. Because the whole workflow shows red,
the gate looked like it was guarding code; it was actually reporting its own
plumbing failure, and no fallow findings were detected in that window.

### Root cause

`fallowrc.json` declares `health.coverage: server/coverage/coverage-final.json`:
health/CRAP metrics are measured against Istanbul coverage, which is **not
committed**. Locally, `scripts/check.sh` had only ever passed because a stale
coverage file remained on disk from the 2026-10-22 CRAP cleanup. CI checked out
a fresh tree and never executed the suite, so the file did not exist and the
audit aborted with exit 2. Local `--base HEAD` audits could also scope to zero
changed files and skip the read — masking the defect further (caught only once
CI used a real base, or when locally auditing `--base HEAD~1`).

### Fix

- The CI fallow job now runs `npm test -- --silent --coverage` first, writing
  the coverage file the audit reads. The server job's command stays
  `npm test`, so `scripts/check.sh` remains byte-identical to it.
- `scripts/check.sh` runs the tests before the fallow audit (full mode only);
  in `--quick` mode the audit still consumes whatever coverage file is on
  disk, documented as stale in the script comment.

### Verification

Red reproduced locally: coverage file hidden → `fallow audit --base HEAD~1`
aborted with the identical CI error. Green: full server suite re-run with
coverage, then the same audit command passed with fresh measured coverage.

---

## BUG-009 · First-run confusion: shipped server shells and an app-id
## preferences folder that looked like lost data

**Status:** `FIXED` — `tool/stage-server.mjs`, `lib/core/app_support_paths.dart`, `lib/main.dart`
**Found:** 2026-10-30 · **Severity:** low (operator confusion, no data loss)

### Symptom

After installing v0.2.0-alpha.1 (.deb / AppImage), an empty `database/`,
`uploads/`, `logs/` tree sat inside the packaged server folder, and a second
install folder `~/.local/share/com.example.minierp_app` appeared next to the
real data home `~/.local/share/minierp`. Together this suggested the package
was carrying its own data (or that the app's data was split/scattered), and an
existing `erp.db` could easily be mistaken for stray "dummy data" that a
fresh install had failed to clear.

### Root cause

Two unrelated looks, one shared cause:

1. `tool/stage-server.mjs` created `server/{database,uploads,logs}` in the
   payload on every release build. The client always launches the bundled
   server with `DATABASE_PATH`/`UPLOADS_DIR`/JWT state pointed at the per-user
   data directory (`BackendPaths.resolveDataDir` →
   `~/.local/share/minierp/data`), so the shipped shells were never read or
   written — they were dead weight that invited the wrong inference.
2. `shared_preferences` on Linux derives its storage folder from the
   application id (`path_provider_linux` → `<data home>/com.example.minierp_app`),
   so the preferences file lived in a second `~/.local/share` folder named
   after the build id, disconnected from the minierp data family.

### Fix

- Release payloads now stage only `dist/`, `package.json`, and
  `package-lock.json`; the runtime data folders are created by the client
  under the per-user data directory, as they always were.
- `lib/core/app_support_paths.dart` (new): on Linux, the shared_preferences
  store is relocated to `~/.local/share/minierp/shared_preferences.json`
  (`AppSupportPaths.installPreferencesOverride`, wired in `main.dart` before
  the first preferences access), and the legacy app-id folders
  (`com.example.minierp_app` from old installs, `com.example.minierp` from
  the id rename below) are migrated in on boot and removed
  (`AppSupportPaths.migratePreferences`, idempotent, leaves the legacy
  folder untouched when it still holds unrelated files).
- Windows/macOS keep their platform-default preferences location.
- Renamed the Linux application id to `com.example.minierp`
  (`linux/CMakeLists.txt`) and the .desktop files built by release.yml
  after it; the deb package, executable name, and install paths are
  unchanged, so upgrades replace the package cleanly (dpkg removes the
  retired `com.example.minierp_app.desktop` when the package updates).
- Set the GTK window/header title to "MiniERP" in
  `linux/runner/my_application.cc` (the bare "minierp_app" titlebar text).

### Verification

- Staging a payload with `node tool/stage-server.mjs --skip-npm --skip-runtime`
  yields no data-shell directories.
- `test/core/app_support_paths_test.dart` (red first, then green): path
  resolution, migration cases (move / stale legacy / unrelated files /
  idempotency), and an end-to-end store write landing in a fake XDG data home.
- `flutter analyze` clean; `flutter test test/core/` green.

---

## BUG-010 · Invoice restore re-consumes stock at today’s FIFO layers while un-voiding the original COGS line

**Status:** `FIXED` — **Severity:** medium (reporting distortion, no data loss ·  found
2026-11-09 during the `period-protection-primitive` change)

The department can delete a paid invoice and later restore it
(`POST /api/invoices/:id/restore`). The restore does two things that do not
agree:

1. Stock comes back from TODAY’s oldest FIFO layers —
   `InvoiceModel.consumeFromOldestBatches(item_id, warehouse, qty, db)` in
   `server/src/controllers/invoiceController.ts` (`restoreInvoice`, step 1)
   takes no date and picks whatever the layers look like at restore time.
2. The GL keeps the ORIGINAL COGS — `restoreJournalLinesByReference` un-voids
   the lines the delete voided; no delta posting reconciles the difference.

When another sale consumes the returned stock between the delete and the
restore, the re-consumption must use a later, differently-costed layer.
Example: buy 10 @ 100 (batch A); sell 10 (COGS 1000); delete (10 returns to
batch A); sell the 10 again (batch A now empty); buy 10 @ 50 (batch B);
restore — stock is consumed from batch B at 50, but COGS still shows 1000.
The stock ledger and the GL then disagree by 500 and no report can explain the
difference.

The delta spec of `period-protection-primitive`
(`specs/closed-period-immutability/spec.md`, “Invoice restore honours the
closed period”) requires the opposite: restore SHALL NOT “re-consume stock at
today’s FIFO layers while un-voiding the original COGS line, and SHALL
re-post COGS consistent with the batches it restores.”

Why it stayed open for a while: the change’s task 1.3 was only the period
guard (which works —
closed-period restore returns 409 and changes nothing; regression green in
`server/src/__tests__/closedPeriodImmutability.test.ts`). Making COGS
batch-faithful on restore meant redesigning the delete/restore stock pairing.

**Fix (2026-11-10).** The delete side already records the exact batches it
returns: `reverseStockForItems` credits each original SALE movement's batch
back by its own quantity (ratio 1 for a full reversal). Restore now replays
those exact batches at their ORIGINAL unit cost —
`InvoiceModel.reconsumeRestoredInvoiceItems(db, invoiceId, invoiceNo, date, userId)`
— instead of re-running generic FIFO (`consumeFromOldestBatches`). So the
restored SALE movements carry the same cost the un-voided COGS lines show.
If another sale consumed the returned batch in the delete→restore window,
re-consumption finds insufficient batch stock and the restore FAILS (the
invoice stays deleted) rather than silently consuming a later, differently
costed layer. Regression:
`server/src/__tests__/invoiceRestoreBatchFaithful.test.ts` (both cases — the
cost-faithful success and the refuse-on-consumed case — fail on the old code).

---

## BUG-011 · Local `jest --coverage` run takes ~11.6 h on three suites

**Status:** `OPEN` — **Priority:** low · **Severity:** low (developer experience only)
**Found:** 2026-11-15 · does not affect CI or production

**Problem.** A local full-suite run with coverage takes ~12 h. Three suites
account for all of it:

| Suite | Local `--coverage` time |
|---|---|
| `src/__tests__/supplierRefund.test.ts` | ~41,873 s |
| `src/__tests__/unappliedCashMigration.test.ts` | ~41,872 s |
| `src/__tests__/unappliedCashGl.test.ts` | ~42,144 s |

Every other suite finishes in minutes.

**Cause.** Not yet investigated. The suites pass; the time looks like jest
failing to exit cleanly while the coverage instrumenter holds the process open
(open handles / timers), not slow assertions.

**Impact.** Local coverage is not CI-equivalent, so a fallow baseline must not
be saved from it (see `audit/DECISIONS.md` D20). CI is unaffected — the same
suites finish normally on GitHub Actions.

**Scope.** Developer experience. No production effect. Low priority.

---

## BUG-013 · Turning on `feature_batch_locations` makes existing stock unsellable

**Status.** FIXED on the working branch (2026-11-16). Flag still ships OFF;
step 5 below (make it the default) remains open.

**What shipped.**

| Part | Where |
|---|---|
| Backfill + stale-row repair migration | `server/src/migrations/127_backfill_batch_stock_by_location.sql` |
| Write location rows regardless of the flag | `StockMovement.syncBatchStockByLocationForNewBatch` (ungated) |
| Keep location rows in step on the flag-OFF consume path | `StockMovement.consumeLegacyBatches` (`MAX(0, physical - ?)`, ungated) |
| Keep them in step on the ACCT-006 backdated fallback | `StockMovement` (~line 1378) |
| Keep them in step on a voided return | `invoiceReturnService.reverseBatchRestore` — **found by the void rehearsal** |
| DEFAULT location on warehouse create | `Warehouse.create` + migration 127 seed |
| Read-path fallback when the mirror lags | `StockMovement.resolveAvailableQuantity` |
| Sellable query keeps batches with no location row | `StockMovement.consumeFromOldestBatches` (merges uncovered batches) |
| Sellable query (flag on) reads covered AND uncovered batches | `StockMovement.sellableAvailabilityByWarehouseSql` (UNION ALL) |
| Transfer void keeps both stock sources in step | `StockMovement.voidTransfer` — **found by the per-path A-J matrix** |
| Drift invariant (over-report) | `batchLocationDriftImbalances` (per batch, per item+warehouse, per bin) |
| Regression: void a return under both flag states | `src/__tests__/batchLocationVoidInvariants.test.ts` |
| Regression: legacy flip, mixed state, idempotency | `src/__tests__/batchLocationBackfill.test.ts` |
| Regression: every flag-branching write path, both flag states, A-J | `src/__tests__/batchLocationPathMatrix.test.ts` |
| Regression: one item split across a covered and an uncovered warehouse | `src/__tests__/batchLocationWarehouseScope.test.ts` |
| Regression: a partly covered batch, a bin in another warehouse, one row per pair | `src/__tests__/batchLocationDoubleCount.test.ts` |
| Guard: no write to the batch tables behind the flag (zero exceptions) | `src/__tests__/batchLocationWriteGuard.test.ts` |
| Regression: invoice delete restores the bin mirror | `src/__tests__/bug014InvoiceDeleteRestore.test.ts` |
| Regression: delete-then-restore draws both sources down | `src/__tests__/bug014ReverseStock.test.ts` |
| Regression: purchase return moves both sources, both flag states | `src/__tests__/bug014PurchaseReturn.test.ts` |
| Regression: a hand-inserted legacy batch is repaired | `src/__tests__/batchLocationBackfill.test.ts` |

**A fifth characteristic, found while rehearsing.** The defect is not only a
*read* problem. The void path `reverseBatchRestore` branched on the flag and
wrote ONE source (flag on → bins, flag off → master batches). With the flag ON,
voiding a return removed units from `stock_balances` while
`stock_batches.quantity_remaining` kept them, breaking invariant E with
`diff: -4`. The flag must never choose WHICH source is written — only which is
READ. Fixed and pinned red-first.

**Mixed-state answer (item 4).** A half-migrated database can hold a batch whose
location row exists but carries the wrong quantity (stale). The insert half of
migration 127 skips an existing row by design, so on its own it would leave that
split in place. Migration 127 therefore also **corrects** any DEFAULT-location
row whose physical quantity disagrees with the batch. After one run every batch
has exactly one DEFAULT row carrying its real remaining quantity, or none —
never a wrong one. `batchLocationBackfill.test.ts` seeds the mixed state on
purpose (two batches with no row, one with a stale zero row) and asserts an
exact match after the migration.

**Drift check granularity.** `batchLocationDriftImbalances` judges at **three
levels**, because each hides a different swap:

| Level | Query compares | Catches |
|---|---|---|
| Per batch | Σ bin `quantity_available` vs `quantity_remaining` | one batch over-reporting |
| Per item+warehouse | Σ bins vs Σ batches for the item in that warehouse | two batches cancelling out |
| Per location bin | `physical` vs `available + reserved` | a bin whose columns disagree |

Only over-report is flagged. Under-report (a hidden batch) is handled by the
read-path fallback, not the invariant, because a legacy batch with no location
row is legitimate history — it must not fail the gate. The per-batch query is
an INNER JOIN: an uncovered batch is simply not judged here.

**A seventh characteristic — the flag-on sellable query, partial coverage.**
The flag-on branch of `sellableAvailabilityByWarehouseSql` read ONLY
`batch_stock_by_location`. That was masked while a whole warehouse had no
location rows (the `batchRows.length === 0` fallback caught it), but a PARTIAL
set — one covered batch, several uncovered — fell through both paths and was
refused. The flag-on branch is now a UNION ALL of location-covered batches and
uncovered batches read from `sb.quantity_remaining`. The residual (unbatched)
deduction subtracts the same two groups the branch counts, split per unit and
per warehouse, so it cannot double-count. Found by
`batchLocationWarehouseScope.test.ts`.

**An eighth characteristic — `voidTransfer` gated its bin writes.** The same
shape as the fifth: `voidTransfer` wrote `batch_stock_by_location` only under
`if (isFeatureEnabled(...))`, but `recordTransfer` creates those rows ungated.
A flag-OFF void therefore removed the master batch quantity and left the
destination bin holding the units. Both location writes are now unconditional.

This one was invisible to the per-batch drift check: the source bin
under-reported by exactly what the destination bin over-reported, so the batch
totals still agreed. That is why the drift check now judges per item+warehouse
and per bin. Found by `batchLocationPathMatrix.test.ts`, and pinned red-first in
`batchLocationVoidInvariants.test.ts`.

**A ninth characteristic — coverage is per unit, and the residual branch must
agree with the branch it deducts from.** The UNION ALL fix above treated
coverage as per batch: one `NOT EXISTS` test asked "does this batch have any bin
row?". A PARTLY covered batch — some units mirrored, the rest not — was
therefore excluded from the uncovered branch, while the residual deducted the
WHOLE batch. The unmirrored units were counted zero times and silently vanished
from sellable stock. The mirror case was worse: the residual deducted
`SUM(quantity_remaining)` grouped by `sb.warehouse_id`, but the bin branch
grouped by the BIN's warehouse, so a batch whose bin points elsewhere was
deducted from the wrong warehouse and the difference was counted TWICE (7 units
reported as 14). A third trap: the residual's deduction mirrored the branch's
eligibility filters, so an expired batch was filtered out of the branch but not
deducted from the residual, and became sellable again.

The deduction is now per unit, split by the same two attributions the branch
uses, and unfiltered so an excluded batch still reduces the residual. Found by
`batchLocationDoubleCount.test.ts`.

**A sixth site — `invoiceReturnService.reverseBatchRestore`.** Same shape as the
fifth: the master batch decremented unconditionally, the bin only when the flag
was on. Found by the structural guard
`batchLocationWriteGuard.test.ts`.

**Structural guard.** `batchLocationWriteGuard.test.ts` reads the source and
fails when an INSERT/UPDATE/DELETE against `stock_batches` or
`batch_stock_by_location` sits inside an
`if (isFeatureEnabled(..., 'feature_batch_locations'))` block — including the
`const on = isFeatureEnabled(...); if (on)` alias form. A second test walks the
tree and fails if a file that mentions the flag is missing from the scanned
list. It passes with ZERO exceptions; every gated write it found was fixed,
never allow-listed.

**Evidence (pre-fix, for the record).** Full server suite with
`TEST_FORCE_BATCH_LOCATIONS=1` (opt-in, never set in CI):

```
flag ON : 38 failed suites, 122 failed tests
flag OFF: all suites pass (the shipped default)
```

All 38 failures shared one signature, `sellable stock N, requested M` with N
lower than M.

**Still open.** Step 5 — make the flag the default — waits on a clean full
flag-ON suite. Flag-ON is opt-in; the shipped default is OFF.

**Problem.** With `feature_batch_locations = '1'`, the sellable-stock query
reads `batch_stock_by_location` instead of `stock_batches`:

```
server/src/models/StockMovement.ts:1082  sellableAvailabilityByWarehouseSql
  ON  : JOIN batch_stock_by_location bsl … SUM(bsl.quantity_available)
  OFF : SUM(sb.quantity_remaining) FROM stock_batches
```

**Cause.** Two facts combine:

1. `syncBatchStockByLocationForNewBatch` (`StockMovement.ts:1040`) seeds a
   `DEFAULT` location row **only when the flag is already on**. Batches created
   while the flag was off get no location row.
2. The migration `add-batch-location-model.sql` creates the table and its
   triggers but **does not backfill** existing batches (no `INSERT … SELECT`
   from `stock_batches`).

So a database with batches but no location rows reports **sellable stock 0**.
A database with partial rows reports a **wrong lower** number.

**Impact.** On a fresh install the flag is seeded `'0'` (off), so the OFF path
is the only one that works. Flipping the flag on **blocks sales**: every sell
tries to consume stock the sellable query cannot see. This is a stock-amnesia
switch, not a safe capability toggle.

**Evidence.** Full server suite with `TEST_FORCE_BATCH_LOCATIONS=1` (opt-in,
never set in CI — see `server/src/__tests__/setup.ts`):

```
flag ON : Test Suites: 38 failed, 234 passed, 272 total
          Tests: 122 failed, 2075 passed, 2197 total
flag OFF: 272/272 suites, 2190/2190 tests passing (the shipped default)
```

All 38 failures share one signature, `sellable stock N, requested M` with N
lower than M:

```
createInvoice failed: 400 … sellable stock 0, requested 3
                      … sellable stock 2, requested 4
```

Failing suites include `accountingInvariants`, `invoiceReturnAcceptance`,
`paymentRecordingMatrix`, `glLifecycle`, `moneyPaths`, `ledgerIntegrity`,
`closedPeriodImmutability`, `supplierRefundClaims`, and `stockTransferVoid`.
All pass with the flag off.

**Fix plan (not applied — plan only).** The user asked for a plan, no code yet.

**Why the dev DB worked with the flag on earlier.** Two different databases:

| Database | Batches | `batch_stock_by_location` rows | Flag | Result |
|---|---|---|---|---|
| live `database/erp.db` (fresh) | 0 | 0 | 0 | nothing to lose |
| archive `/tmp/devdb-archive-20261115/erp.db.stale-verif-drift` | 5 | 5 | 1 | worked |
| a DB with batches created while the flag was **off** | >0 | 0 | 1 | **sellable stock 0 — broken** |

The archived DB worked because its batches were bought while the flag was
**already on**, so `syncBatchStockByLocationForNewBatch` wrote a location row per
batch at purchase time. The live dev DB worked because it holds **no stock at
all**. Neither case exercises the defect. The defect needs batches created while
the flag was off, then a flip to on — which is exactly what the migration does
for every existing install.

**Plan, in order.**

1. **Backfill migration** (`add-batch-location-backfill.sql`, new number). For
every `stock_batches` row with `quantity_remaining > 0` (or non-zero physical)
that has no `batch_stock_by_location` row, insert one against the warehouse's
`DEFAULT` location, with `quantity_physical = quantity_remaining`,
`quantity_reserved = 0`, `quantity_available = quantity_remaining`. Use
`INSERT … SELECT … WHERE NOT EXISTS` so a re-run is safe. Registered in
`config/database.ts`. This is the fix for existing databases.

2. **Write location rows regardless of the flag.** In
`syncBatchStockByLocationForNewBatch` (`StockMovement.ts:1040`), remove the early
`if (!isFeatureEnabled(...)) return`. Writing the row costs one insert and makes
the two sources agree at all times. The flag then controls only which source is
**read**, never whether the second source is **maintained**.

3. **Drift check.** Add an invariant check that, for every warehouse,
`SUM(stock_batches.quantity_remaining)` equals `SUM(batch_stock_by_location.
quantity_available)` over the same batch set. Wire it into the accounting
invariants run so a divergence fails a test, not a customer sale.

4. **Test: legacy DB with batches, flip the flag on, sales still work.** Seed
batches with the flag **off** (the real legacy shape), then set the flag to `'1'`
in the same test, then sell. Assert the sale succeeds and the sellable number
matches the pre-flip number. This is the regression the current suite cannot
see, because `setup.ts` sets the flag **before** any batch exists.

5. **Only after 1–4 pass**: consider making the flag the default. Until then the
shipped default stays **off**.

**Scope.** Latent. No production effect while the flag stays off. The shipped
default must not change until the backfill and step 4 land.

---

## Not bugs — deliberate decisions, recorded so they are not re-litigated

- **PUR-016** — the two live `PURCHASE_ORDER` commitment rows (3,000 supplier 1 /
  1,000 supplier 2) are **not** duplicates: different suppliers. Ruled by the
  owner 2026-10-08; no data repair.
- **SALES-005** — an edit that reduces a paid invoice while keeping the total
  positive is intentionally **allowed**; the balance floors at 0 and the invoice
  stays `Paid`. `moneyPaths` scenario 9.3 pins that boundary. Only a non-positive
  total is refused.
