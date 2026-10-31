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

**Status:** `OPEN` — blocked · **Severity:** medium
**Depends on:** `openspec/changes/inventory-batch-lot-spec` (breaking rewrite)

C-04 cannot be remediated until the batch/lot model rewrite lands, because the
finding sits on the layer that rewrite replaces. No code has been touched.

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

**Status:** `OPEN` — **Severity:** medium-high

SALES-016: a sales order cannot carry per-line tax or discount, so converting one
to an invoice either drops those values or hard-codes `discount_type: 'none'`.
This needs a schema migration, so it is separate work and deliberately not folded
into any behaviour-only change.

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

## BUG-008 · CI fallow gate ran without coverage — red on every push since 2026-10-26

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
  the first preferences access), and the legacy
  `com.example.minierp_app/shared_preferences.json` is migrated in on boot
  and removed (`AppSupportPaths.migratePreferences`, idempotent, leaves the
  legacy folder untouched when it still holds unrelated files).
- Windows/macOS keep their platform-default preferences location.

### Verification

- Staging a payload with `node tool/stage-server.mjs --skip-npm --skip-runtime`
  yields no data-shell directories.
- `test/core/app_support_paths_test.dart` (red first, then green): path
  resolution, migration cases (move / stale legacy / unrelated files /
  idempotency), and an end-to-end store write landing in a fake XDG data home.
- `flutter analyze` clean; `flutter test test/core/` green.

---

## Not bugs — deliberate decisions, recorded so they are not re-litigated

- **PUR-016** — the two live `PURCHASE_ORDER` commitment rows (3,000 supplier 1 /
  1,000 supplier 2) are **not** duplicates: different suppliers. Ruled by the
  owner 2026-10-08; no data repair.
- **SALES-005** — an edit that reduces a paid invoice while keeping the total
  positive is intentionally **allowed**; the balance floors at 0 and the invoice
  stays `Paid`. `moneyPaths` scenario 9.3 pins that boundary. Only a non-positive
  total is refused.
