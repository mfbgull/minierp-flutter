# Customer 15 — Final Independent Accounting Review

**Status:** Investigation and simulation only. **No live financial data modified.**
**Date:** 2026-10-15

---

## 1. Verdict

**The Rs 1,800 is not a customer liability. It is money the customer owes MiniERP.**

| Measure | Amount |
|---|---:|
| Gross invoices (7 live) | 9,600 |
| Less goods returned | −2,400 |
| Plus return fees charged | +100 |
| **Total obligation** | **7,300** |
| Live non-voided receipts | 6,050 |
| Less refund paid out | −550 |
| **Net cash received** | **5,500** |
| **Net receivable** | **1,800** |

No liability exists and none should be recognised. No account in the chart could carry one:
`1110` is `Customer Credit`, `type=asset`, `normal_balance=credit` — a contra-receivable.

**Recommended correction: Strategy C′, applied through the production reversal primitives.**
All four customer-15 representations reconcile to `1,800`, invariant F goes FAIL → PASS, and no
other invariant, customer, or cash account moves.

---

## 2. Reversal-form ruling

`docs/REVERSAL-RULES.md` is authoritative. Ruling on the previously open question:

> **A bare void IS the compliant form. Paired offsetting journal entries are NOT required.**

Rule 1.7 mandates `voidJournalLinesByReference(...)`, which *flags* lines voided rather than
posting an equal-and-opposite entry. Rule 1.8 (reversal neutrality) holds because voiding removes
the original economic effect without creating a new one.

**But the original Strategy C violated three rules:**

| Rule | Requirement | How Strategy C breached it |
|---|---|---|
| **1.7** | "A reversal that voids only one accounting store is incomplete" | Voided canonical `journal_lines` only; left legacy `journal_entries` headers active |
| **1.6** | "Derived totals must be recomputed from the ledger chain and must never be manually patched" | Patched `customers.current_balance = 1800` directly |
| **1.2** | "Every path must consume the same reversal primitive" | Hand-rolled SQL instead of the production primitives |

**Further finding:** each `CREDIT_OFFSET` entry has **two** legs (`Dr 1110 / Cr 1100`). Voiding
only the `1110` line would leave the reference group unbalanced and break invariant A, so the
correction must void **by reference**, which catches both legs.

---

## 3. Answers to the eight questions

**Q1 — Were invoices 50 and 51 fully settled before 10 October?**
**Yes.** Invoice 50 (1,200) received 600 cash on 17 Sep (`PAY048`) plus a 600 credit offset.
Invoice 51 (1,800) received 600 cash on 17 Sep (`PAY049`) plus a 1,200 credit offset. Both
reached zero balance on 17 September.

**Q2 — Should the September credit applications remain part of the historical record?**
**The original postings must remain; the explicit subledger rows must be reversed.** Ledger
`#104` (600) and `#108` (1,200) reduce the balance a second time — the credit they consumed was
already created by the `RETURN` rows `#102`/`#106` and earlier over-receipts. Reversing them via
`reverseLedgerEntry` retains the originals and their attribution.

**Q3 — Did the October receipts create a real overpayment?**
**No.** `PAY-1026-00060` (2,000) and `PAY-1026-00061` (600) were genuine cash. Their allocations
`#54` (1,200 → inv 51) and `#55` (600 → inv 50) duplicated settlement already completed in
September. The cash was real; only its *assignment* was wrong.

**Q4 — If the customer genuinely had Rs 1,800 of unapplied money, which account would carry it?**
**None that exists.** There is no customer-deposit, unapplied-cash, or advance-payment account.
`paymentValidation.ts:57` and `paymentsController.ts:141` both require at least one invoice
allocation, so unapplied receipts cannot be persisted at all.

**Q5 — Could account 1110 carry that liability?**
**No.** It is typed `asset` and already carries a 5,350 credit balance from the disputed offsets.
Using it as a liability would misclassify the balance and fail the GL-vs-subledger invariant.

**Q6 — After the correction, does the customer owe Rs 1,800 or is Rs 1,800 owed to them?**
**The customer owes Rs 1,800.** The subledger moves `0 → 1,800`, matching the GL receivable.

**Q7 — Does the correction replace legitimate credits with later cash?**
**In presentation, yes — and that is the correction.** The legitimate September credit *events*
survive in the running-balance history and in the voided original rows. What is removed is the
double-counted offset row; invoices 50/51 are settled by the genuine October cash that was
mis-allocated to them. Nothing is erased, and every reversal carries attribution (rule 1.13).

**Q8 — Could the October cash remain recorded as unapplied?**
**Not under the current model.** That needs an unapplied-cash feature and a liability account,
both out of scope.

---

## 4. Definitive per-invoice position

Balance formula (`calculateInvoiceBalance`, `ledgerUtils.ts:144`):

```
balance = max(0, (total_amount − returned_amount) + return_fee
                 − (positive non-voided allocations + credit_offset))
```

| Inv | Total | Returned | Fee | Positive alloc. | Credit offset | Correct | Stored |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 49 | 1,800 | 1,200 | 0 | 1,800 | 0 | **0** | **−1,200** ✗ |
| 50 | 1,200 | 0 | 0 | 1,200 | 0 | 0 | 0 |
| 51 | 1,800 | 0 | 0 | 1,800 | 0 | 0 | 0 |
| 52 | 1,800 | 1,200 | 100 | 600 | 1,200 | 0 | 0 |
| 54 | 600 | 0 | 0 | 50 | 550 | 0 | 0 |
| 57 | 600 | 0 | 0 | 600 | 0 | 0 | 0 |
| 59 | 1,800 | 0 | 0 | 0 | 1,800 | 0 | 0 |
| | | | | | **Correct total** | **0** | **−1,200** ✗ |

Only invoice 49 is stored wrong — its `−1,200` is stale; the formula floors at 0.

**Two independent defects:**

1. **Subledger** — `#104`/`#108` double-count the September credits → reads `0` instead of `1,800`.
2. **Invoice 59** — carries `credit_offset = 1,800` with **zero** cash allocation and **no**
   subledger row, while its own ledger row `#131` shows it open.

---

## 5. Strategy comparison

| | Subledger | GL AR | Headers | Customer bal. | Invariant F |
|---|---:|---:|---:|---:|---:|
| Baseline | 0 | 1,800 | −1,200 | 0 | **FAIL** (1,800) |
| **A** — reverse offsets only | 1,800 | 1,800 | −1,200 | 1,800 | PASS |
| **B** — void October allocations | 0 | 1,800 | 600 | 0 | **FAIL** (1,800) |
| **C′** — A + clear inv 59 offset | **1,800** | **1,800** | **1,800** | **1,800** | **PASS** |

- **A** is necessary but **not sufficient** — it leaves the invoice headers on the stale sum
  (−1,200) while the other three representations sit at 1,800.
- **B** is **not viable**. Voiding the October allocations leaves invoices 50/51 open (600 and
  1,200 outstanding) and reconciles nothing. It also cannot represent the resulting unapplied
  cash, which has no account (Q4). Rejected.
- **C′** satisfies the success criterion.

**Measured effect of C′ on invariants A–J (baseline → after):**

```
A   PASS -> PASS      F   FAIL -> PASS   <- repaired
B/C FAIL -> FAIL      G   FAIL -> FAIL   (pre-existing)
D   PASS -> PASS      H   FAIL -> FAIL   (pre-existing)
E   PASS -> PASS      I   FAIL -> FAIL   (pre-existing)
J   PASS -> PASS
```

Exactly one invariant changes, and it changes in the right direction. No regression.

**Note on F:** it is a *global* invariant. Customers 1, 12 and 14 still diverge individually and
cancel to zero. F passing does **not** mean the ledger is clean — that masking is pre-existing and
should be tracked separately.

---

## 6. Strategy C′ — exact change set

Executed via the real production primitives, in one transaction (rule 1.3):

```
scripts/apply-customer15-correction.ts
```

| Step | Primitive | Effect |
|---|---|---|
| 1 | `AccountingService.voidJournalLinesByReference(db, 'CREDIT_OFFSET', invId, {voidedBy, voidReason})` | Voids **both** legs of `je#203` (inv 50), `je#209` (inv 51), `je#257` (inv 59) |
| 2 | `StockMovementModel.voidJournalEntry(entryId, db)` | Voids the legacy `journal_entries` headers (rule 1.7) |
| 3 | `reverseLedgerEntry('customer_ledger', 104 / 108, reason)` | Append-only reversal; voids originals with `reversed_by` attribution (rule 1.6) |
| 4 | `UPDATE invoices SET credit_offset = 0 WHERE id = 59` | Removes the offset with no cash and no subledger row behind it |
| 5 | `calculateInvoiceBalance` + `updateInvoiceStatus` per customer-15 invoice | Headers rebuilt by the production formula |
| 6 | `rebuildLedgerBalances` + `recalcCustomerBalanceFromLedger` | Balances rebuilt from the ledger chain, never patched (rule 1.10) |
| 7 | `activity_log` insert | `CREDIT_OFFSET_REVERSAL` trail row |

**Verified result:**

| | Before | After |
|---|---:|---:|
| `customers.current_balance` (c15) | 0 | **1,800** |
| Active subledger (c15) | 0 | **1,800** |
| Invoice header sum (c15) | −1,200 | **1,800** |
| GL AR (c15) | 1,800 | 1,800 (unchanged) |

- Cash unchanged: `1000=24050`, `1010=−8000`, `1020=−2100`; payments table sum `66100`.
- Other customers, suppliers, items, stock batches, payments, allocations, returns: **identical**.
- `integrity_check=ok`, `user_version=107`, all active GL reference groups balanced.
- Invoice 59 correctly ends at `bal=1800 Unpaid`; invoice 49 `bal=0`.

---

## 7. Rollback

```
scripts/rollback-customer15-correction.ts   (restores from the forward path's snapshot)
```

**Rollback must be snapshot-based, not recomputed.** Three reasons, all discovered by test:

1. **Invoice 49's stored `−1,200` is not reproducible.** `calculateInvoiceBalance` floors at 0, so
   no rebuild can recreate a negative stored balance.
2. **Invoice 59's `Unpaid` status** was derived from that stale state and is likewise not derivable.
3. **`AccountingService.restoreJournalLinesByReference` clears `voided`, `voided_by` and
   `void_reason` but not `voided_at`** — so the inverse primitive alone leaves a residual
   timestamp. That gap makes any caller relying on it non-bit-for-bit reversible.

The forward path therefore writes `rollback-snapshot.json` before mutating, recording every
touched row. **Verified end-to-end:**

```
1. FORWARD   0 -> 1800 balance, 0 -> 1800 ledger, -1200 -> 1800 headers, GL balanced
2. ROLLBACK  all financial tables restored
3. COMPARE   customers, invoices, payments, payment_allocations, customer_ledger,
             journal_entries, journal_lines, invoice_returns, items, suppliers,
             stock_batches  ->  ALL BIT-FOR-BIT IDENTICAL to baseline
             activity_log   ->  differs (append-only audit, by design)
             integrity      ->  ok
```

`activity_log` deliberately keeps its row: it is append-only audit, and a reversal that happened
must leave its trail. Deleting it would be the actual violation.

---

## 8. Backup path defect — found and fixed

**Found:** the app's nightly backup wrote to `server/dist/database/backups/`, bypassing the
canonical `server/database/backups/` that holds all ten existing backups. The same bug also
created a stray `server/dist/uploads/`.

**Cause:** `backupService.ts` resolved its directories with its own `__dirname` arithmetic
(`'../../database'`), while `config/database.ts` used three `..` segments. Under ts-node
(`src/services/`) two was correct; compiled to `dist/src/services/` it lands one directory too
high. The failure is silent — the backup succeeds and `integrity_check` passes, it just lands
outside the directory that retention, the documented restore procedure, and any external sync
actually look at.

**Fix:**
- `config/database.ts` — exported the already-resolved `dbDir`, giving one source of truth.
- `backupService.ts` — `BACKUP_DIR` derives from that `dbDir`; `UPLOADS_DIR` anchors on the nearest
  ancestor `package.json`, which resolves correctly from every build layout.
- `backupPathResolution.test.ts` — new regression test locking both invariants.

**Verified:** typecheck clean, lint clean, and all three layouts (`src/services`,
`dist/services`, `dist/src/services`) resolve to `server/database/backups` and `server/uploads`.

Regression evidence: **7 suites / 84 tests pass** — `backupPathResolution`, `backupWal`,
`adminBackup`, `adminBackupDotfileDownload`, `auditRegression8`, `auditRegression9`,
`accountingInvariants`.

---

## 9. Outstanding risks

1. **Invoice 49: accounting says 2 units came back, stock says 1.** This is the reason the
   correction is on hold. The invoice sold 3 units @ 600 (`returned_qty=2`, `returned_amount=1,200`),
   and *two* return events are fully posted:

   | Evidence | Count | Detail |
   |---|---|---|
   | GL sales-return entries | 2 | `je#199` (09-16), `je#205` (09-17) — each `Cr 1100 600 / Dr 4100 600` |
   | GL COGS-reversal entries | 2 | `je#200`, `je#206` — each 100 (1 unit × `unit_cost` 100) |
   | Subledger `RETURN` rows | 2 | `#102` (09-16), `#106` (09-17) — 600 each |
   | `invoice_returns` rows | **0** | feature post-dates these events; both existing rows belong to invoice 52 |
   | Stock restock movements | **1** | only `#197` (`ADJUSTMENT`, +1 unit, doctype `RETURN`) |

   COGS was reversed twice, so the accounting records two units returned; only one unit was ever
   physically restocked. No invariant covers this gap — invariant E compares `stock_balances` to
   batch quantities, both of which reflect the same single restock.

   **Consequence for the correction.** Invoice 49's Rs 1,200 return credit is only half-corroborated
   by physical stock. If the second return is spurious, `returned_amount` should be 600, returns
   total 1,800 instead of 2,400, the obligation becomes 7,900 and the receivable 2,400 — not 1,800.
   The recommended Rs 1,800 figure therefore depends on an unverified assumption. Resolving this
   needs the September return paperwork, which the database does not contain.
2. **Invoice 52 asymmetry.** Its Rs 550 refund is excluded from the paid base while its Rs 100
   return fee is added to the obligation. Documented spec behaviour, not a defect, but it means
   invoice 52 reaches zero via a 1,200 credit offset against a 700 obligation.
3. **Customer 14** carries a separate Rs 600.2 divergence (Rs 600 stale header on deleted invoice
   55; Rs 0.2 ledger-vs-GL on invoice 56). Explicitly **not repaired** — out of scope.
4. **`restoreJournalLinesByReference` leaves `voided_at` set.** Harmless for production behaviour,
   but that primitive alone is not a bit-for-bit inverse.
5. **The repo-root `database/erp.db` is a stale database, not a copy.** Confirmed: `user_version 95`
   (live is 107), 3 customers vs 5, 5 invoices vs 35, 1 payment vs 53, newest `activity_log`
   `2026-09-12`. Every table differs from live. It is a live trap for any ts-node path that resolved
   `../../../database` from `src/`. **Not deleted** (per instruction) but no longer reachable — see §8.

---

## 9a. Path resolution hardened (same defect class, wider blast radius)

The backup bug was one instance of a broader problem. Ten sites derived the database or uploads
directory from `__dirname` with a fixed `..` count, which is correct in one build layout and wrong in
the other. Two of them — `src/scripts/fix-duplicate-purchase.ts` and
`src/scripts/reconcile-stock-cash.ts` — tried *three candidate paths* and silently took the first
that existed, so either could have opened the stale repo-root database and reported success.

All ten now use one shared resolver, `src/utils/serverRoot.ts`, which anchors on the nearest ancestor
`package.json` and therefore resolves identically from `src/`, `dist/src/` and `dist/`:

| Site | Was | Now |
|---|---|---|
| `config/database.ts` | `'../../../database'` | `defaultDbDir()` |
| `services/backupService.ts` | `'../../database'`, `'../../uploads'` | `dbDir` / `defaultUploadsDir()` |
| `middleware/upload.ts` | `'../../uploads'` | `defaultUploadsDir()` |
| `controllers/employeeController.ts` | `'../../uploads/employees'` | `defaultUploadsDir()` |
| `scripts/backfill-batches.ts` | `'../../../database'` | `defaultDbDir()` |
| `scripts/fix-duplicate-purchase.ts` | 3 candidates, first-match | `defaultDbDir()` |
| `scripts/reconcile-stock-cash.ts` | 3 candidates, first-match | `defaultDbDir()` |
| `scripts/check-gl-integrity.ts` | `'../database'` | `defaultDbDir()` |
| `scripts/check-historical-data-integrity.ts` | `'../database'` | `defaultDbDir()` |
| `scripts/void-orphaned-salary-gl.ts` | `'../database'` | `defaultDbDir()` |

`MIGRATIONS_DIR` is left alone: it is compiled to a sibling directory by `npm run build`, which
copies it explicitly, so it is correct by construction.

The employee-document fix matters beyond tidiness — `upload.ts` and `employeeController.ts` would
have written and deleted HR files under `dist/uploads/employees` in a compiled build, i.e. files the
restore procedure never captures.

Covered by `src/__tests__/serverPathResolution.test.ts`, which runs from `src/` — precisely the
layout where the old arithmetic picked the wrong directory, so the assertions genuinely fail against it.

---

## 10. Backup relocated

The 20:01 backup the path bug displaced has been verified and moved into the canonical directory:

```
source      server/dist/database/backups/erp-2026-10-15T15-01-20.db
integrity   ok          user_version 107
sha256      c94bdce4beb3d0a196ac5001773c06d5e39c4d8867ad010955bbe9e362df6d14   (before move)
sha256      c94bdce4beb3d0a196ac5001773c06d5e39c4d8867ad010955bbe9e362df6d14   (after move)
destination server/database/backups/erp-2026-10-15T15-01-20.db   (+ paired .uploads)
```

Moved with `mv -n` after a collision check, so nothing was overwritten. `server/dist/database` and
`server/dist/uploads` were then removed — both were git-ignored build artifacts and, after the move,
contained no database files, no user data and nothing but a 24-byte `.last_backup` staleness marker.

---

## 11. Current status — correction is ON HOLD

**No live data has been changed, and the correction will not be applied.**

The Strategy C′ implementation is complete, verified and reversible, but the invoice-49 finding in
§9 materially undermines its headline figure. Strategy C′ reconciles everything to **1,800**, which
assumes invoice 49's Rs 1,200 return credit is sound. The accounting supports that assumption; the
stock ledger contradicts it for one of the two units.

Applying the correction now would encode an unverified number into the subledger, the GL and the
customer balance. That is the one outcome worse than leaving the divergence in place, because a
reconciliation is far harder to unwind later than a known-wrong number is to identify.

**Unblocked by** either of:

1. The September return paperwork for invoice 49 confirming both 600-unit returns are genuine, or
2. A decision to treat the second return as spurious, which moves the receivable to **2,400** and
   requires Strategy C′ to be re-simulated against that figure.

The scripts remain ready: `scripts/apply-customer15-correction.ts` and
`scripts/rollback-customer15-correction.ts` have both been executed end-to-end against isolated
copies, with the rollback proven bit-for-bit exact.
