# First-deployment checklist

Written 2026-11-15, before the first real (production) data is loaded.

Everything so far ran on **disposable development data**. The statements below
say what is verified and what is still unproven. Read this before the first real
release.

Items marked **MUST** block the release if not done. Items marked **SHOULD**
are important but do not block a first small release.

---

## 1. Release order: client and server ship together

**Verified — no action needed.**

Every release artifact is a complete application: the Flutter client, the
compiled server, its production `node_modules` and a pinned Node runtime
(`.github/workflows/release.yml`). The desktop client supervises the server it
ships with (`lib/core/backend/backend_supervisor.dart`). A user cannot run a new
client against an old server, or the reverse.

So there is **no client-first or server-first order to get wrong**. The server
applies its migrations on first boot, in the same process tree as the client.

**MUST** — check this rule holds if either of these changes:

1. A **web or mobile client** talks to a separately hosted server. Then ship the
   **server and its migrations first**. A server that has not applied
   `126_sales_order_item_tax_discount.sql` silently drops the new order-line tax
   and discount fields (BUG-006 returns).
2. The client stops supervising the server, or the server becomes a shared,
   separately upgraded service.

**MUST** — before tagging a release, confirm the tag matches `pubspec.yaml`
(`release.yml` already fails the build if they differ).

---

## 2. Restore test on the first real backup

**Unproven on real data. MUST run.**

The nightly backup workflow (`nightly-backup.yml`) and the restore-smoke test
were proved on **dummy development data** only, on 2026-11-15. That test found a
clean `integrity_check`, a balanced GL, and two legacy stock-drift rows that
were left unrepaired on purpose (the data was disposable).

On the first real backup:

1. **MUST** take a fresh backup with the nightly workflow, or run the backup
   script by hand.
2. **MUST** restore that backup into a scratch directory. Never over the live
   database.
3. **MUST** confirm on the restored copy:
   - `PRAGMA integrity_check` is `ok`,
   - the GL is balanced (no unbalanced journal entry),
   - every accounting invariant A–J passes,
   - item and stock counts match the live database.
4. **MUST** record the result in `audit/FINDINGS-STATUS.md`.

If the restore shows **any** stock or GL gap, stop. On production every gap is a
defect and must be investigated and repaired through the normal path
(`AGENTS.md` — "Dummy historical data" covers **non-production data only**).

---

## 3. Migration check on the first real snapshot

**Unproven on real data. MUST run.**

No migration has ever run against real data. All migration tests build their own
fixtures.

Before the first migration runs on real data:

1. **MUST** take a backup (section 2).
2. **MUST** run `scripts/check.sh` on the release commit — it must exit 0.
3. **MUST** copy the real snapshot to a scratch directory and boot the server
   against the copy first. Confirm:
   - every migration in `schema_migrations` still matches its file checksum
     (the boot gate fails the process if not),
   - the migration count and `user_version` advance as expected,
   - `PRAGMA integrity_check` is `ok`,
   - the GL stays balanced.
4. **MUST** confirm the new migration is in the ledger exactly once. For
   BUG-006, `server/scripts/verify-bug006-migration.ts` proves this shape on a
   fixture; re-run it, then check the real ledger by hand.
5. **MUST** check the highest migration number on `main` before merge. If two
   branches both take the next number, renumber one. (Checked 2026-11-15:
   `main` reached 125, so `126_sales_order_item_tax_discount.sql` was free.)

**SHOULD** keep the pre-migration snapshot until the first real week of use is
clean.

---

## 4. Role review for write-off and period close

**Default roles are set. MUST review before real money moves.**

Two sensitive operations gate on a role, not on a password prompt:

| Operation | Gate | Source |
|---|---|---|
| Refund-claim write-off above Rs 1,000 | role `admin` | `writeOffNeedsAdmin(remaining, {isAdmin})` in `lib/features/purchases/refund_claim_write_off_dialog.dart:25` |
| Close an accounting period | permission `accounting:update` | `server/src/routes/accounting.ts:73` |

**MUST** confirm on the real user list:

1. Which users hold `admin`. Every one of them can write off any refund claim
   balance above Rs 1,000 without a second approval.
2. Which users hold `accounting:update`. Every one of them can close a period,
   which is a hard lock on that period. After a close, a backdated entry is a
   `409` (D19, ACCT-006).
3. That the number of users in each group is the number you expect. A
   forgotten `admin` is a real risk.
4. That no shared or generic account holds either role.

**SHOULD** add a second approver for write-offs above Rs 1,000 if more than one
user holds `admin`.

---

## 5. Feature flag defaults

**Flags are off by default. MUST check each before go-live.**

`feature_batch_locations` is seeded `'0'` (off) by
`server/src/migrations/add-batch-location-model.sql:24`, and read through
`isFeatureEnabled(db, 'feature_batch_locations')`. When off, batch and location
tracking is skipped in invoices, purchase returns, physical counts and reports.

**MUST** decide, for the real company, whether batch and location tracking is
wanted from day one:

- **If off:** confirm no user expects batch or location tracking. Turning it on
  later means a data-model change, not just a flag flip.
- **If on:** set the flag to `'1'` **before** the first real purchase or sale.
  Then verify a small batch-tracked purchase and sale end to end, and confirm
  the stock layers carry a location.

**MUST** list every other `settings` feature flag and its intended production
value in one place, so the go-live state is not a guess. Check for at least:
`feature_batch_locations`, and any flag added after this document.

---

## 6. Remaining deferred items

These are known, documented and **not** part of the first release. Each has an
owner decision or a trigger.

| Item | State | Trigger / next step |
|---|---|---|
| **POS mandatory Idempotency-Key (stage 2)** | Key optional today. POS logs keyless writes but still accepts them. | Make the key mandatory when the POS client sends it on every financial write. Criterion 2 is in `audit/DECISIONS.md` (D19). |
| **Older-build version-header telemetry** | Not built. `MIN_CLIENT_VERSION` warns but the server never rejects on version. | Build when an old build must be spotted in the field. `server/src/middleware/clientVersion.ts`. |
| **`/api/mobile-invoices/*` keyless** | Keyless by design (D19, 2026-11-14). | Give it keys only if a mobile client is revived. Natural-key dedup was removed on purpose. |
| **Fallow: 64 CRAP-only findings + 72 newly reported** | Documented, out of scope for the 2026-10-22 cleanup. | Work through them as touched. Gate stays `new-only`, no baseline change (D20). |
| **BUG-011 — 3 suites hang ~11.6 h under local `--coverage`** | Pass on CI. | Fix the cover-local hang, or always run those suites without coverage. |
| **DEPLOY-1 historical backfill** | Closed: not needed, the data was disposable. | Re-opened only if `section 2` finds a gap on real data. |
| **Two legacy stock-drift rows (items 1 and 2)** | Found on the 2026-11-15 restore test of dummy data. Left unrepaired. | Gone with the dev reset. Re-check on the first real snapshot (`section 3`). |

---

## One-line sign-off

Before the first real release, every **MUST** above is done, and the result of
each is written in `audit/FINDINGS-STATUS.md`. A green test suite is not proof
that real data is correct; only the restore and migration checks on the first
real snapshot are.
