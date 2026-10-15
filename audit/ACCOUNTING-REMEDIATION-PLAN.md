# Accounting remediation plan (approval-ready)

Derived from the live ledger on 2026-10-15. Every number below was re-read from
`server/database/erp.db` through a readonly + `query_only` connection, not carried
forward from an earlier note.

## How this was measured, and why it can be trusted

Before the DB-INIT-001 fix, verifying these invariants silently advanced the live
database. That is fixed, and the fix is what makes this evidence trustworthy:

```
md5 before : 01359308f37ed33fb506cc42a829c170
md5 after  : 01359308f37ed33fb506cc42a829c170
user_version 107 | integrity_check ok | 107 migration rows | 218 journal entries
```

The read-only diagnostic ran against the live ledger and changed nothing,
byte-for-byte. Reproduce with:

```bash
cd server
DATABASE_PATH="$PWD/database" npx ts-node --transpile-only scripts/verify-invariants-live.ts
```

## Verdict

| Invariant | Result |
|---|---|
| A GL balances | PASS |
| B/C customer subledger + invoice allocations | **FAIL** |
| D supplier subledger | PASS |
| E stock balances vs batches | PASS |
| F GL AR vs customer balances | **FAIL** |
| G GL AP vs supplier balances | **FAIL** |
| H GL inventory vs batch values | **FAIL** |
| I GL cash vs operational flows | **FAIL** |
| J source-typed batches resolve | PASS |

Every failure below is a real inconsistency in the ledger. None of them is an
invariant-detection false positive. No live data was modified in producing this
plan, and nothing in it should be applied without the decisions in the last
section.

---

## B/C — invoice headers under-report collected amounts (drift -3900)

Five invoices fail `paid_amount - (positive allocations + credit_offset)`. Verified
against the database rather than inferred:

| Invoice | Reference | total | `paid_amount` | `credit_offset` | positive allocations | diff |
|---|---|---:|---:|---:|---:|---:|
| 26 | POS-2026-000001 | 1200 | 0 | 0 | 1200 | -1200 |
| 27 | POS-2026-000002 | 600 | 0 | 0 | 600 | -600 |
| 31 | INV-2026-631367 | 1200 | -200 | 0 | 1000 | -1200 |
| 39 | INV-2026-705309 | 600 | 0 | 0 | 500 | -500 |
| 40 | INV-2026-512634 | 600 | 0 | 0 | 400 | -400 |

`credit_offset` is **0 on all five**, so this is not a credit-offset problem. The
invoices carry positive payment allocations — money actually collected — while the
`invoices.paid_amount` header is 0, or negative on invoice 31.

**Correction to an earlier note.** A first pass described these as "negative payments
from the old return path". That is wrong. Netting all allocations gives 0 on four of
them, which is what made them look reversed; the positive-only sum is non-zero. The
drift is a **stale header**, not a reversed payment.

Note also that the positive/negative allocation pairs on these invoices are consistent
with the deliberate REFUND path in `invoiceReturnService.ts` (line 964: "REFUND: negative
payment + negative allocation"), which by design does not shrink `paid_amount`. The
`invoice_returns` table holds only **2 rows in the entire database**, so the modern
return path is barely represented here and the two regimes coexist.

**Classification: legacy header drift.** The allocation rows and the invoice header
disagree; nothing in current code evidently rewrites `paid_amount` for these.

**Not repaired here.** Repair means writing historical financial rows, which is
explicitly out of scope. See decision D1.

## F — GL AR exceeds the customer sub-ledger by 1800

GL AR 3499.8 vs customer balances 1699.8. The credit-offset trail:

- `customer_ledger` holds two `CREDIT_OFFSET` rows totalling 1800
  (`CREDIT-INV-0926-00008` = 600, `CREDIT-INV-0926-00009` = 1200).
- GL holds **five** `CREDIT_OFFSET` journal groups, keyed to invoices 50, 51, 52, 54, 59.

So the GL recognised credit offsets against five invoices while the sub-ledger
recorded only two of them.

**Verified against current code (2026-10-15).** `grep` across `src/` finds **no
current writer of `customer_ledger` rows with `transaction_type='CREDIT_OFFSET'`.
The only writers of `customer_ledger` at all are `Customer.ts:245`, `Invoice.ts:926`
and `ledgerUtils.ts:41`, and none emits `CREDIT_OFFSET`. The two existing ledger rows
pre-date the current code.

So this is **not merely legacy drift — it is an open defect that reproduces.** Every
credit offset posted by current code moves the GL and leaves the sub-ledger behind.
Invoices 52, 54 and 59 already carry `credit_offset` of 1200, 550 and 1800.

**Classification: current-code defect (sub-ledger write missing).**

The docstring defect noted above is the documentation half of the same bug; it is now
corrected. The missing `customer_ledger` write is the behavioural half and is **not**
fixed here, because every candidate fix writes historical financial rows.

See decision D2.

## G — supplier ledger carries 4000 of purchase-order commitments with no GL

| Supplier ledger `PURCHASE_ORDER` | Amount |
|---|---:|
| PO-2026-0004 | 3000 |
| PO-0926-0001 | 1000 |
| **Total** | **4000** |

GL contains **zero** entries with `reference_type='PURCHASE_ORDER'`. GL does contain
4 `SUPPLIER_REFUND` and 4 `PURCHASE_RETURN` groups.

The gap is therefore structural, not a rounding artifact: purchase-order commitments
are recorded as supplier-ledger debits but never reach the GL.

**Correction to an earlier note.** An earlier working note claimed
`postPurchaseReturnEntry` (`accountingService.ts:1348`) has an AP sign error — it
debits AP where the description "AP reduced" implies a credit. **That claim is wrong
and no fix should be made there.** For a purchase return, goods leave inventory
(`Cr 1200`) and the payable is relieved (`Dr 2000`); reducing a credit-balance
liability requires a debit. The code is correct.

**Classification: design gap — PO commitments have no GL representation.**

GL recognition happens at goods receipt (`postGoodsReceiptEntry`, documented as
"Dr 1200 Inventory Asset / Cr 2000 Accounts Payable ... Posted at receipt time, not at
PO submission"). So the GL policy is deliberate. The supplier ledger, however, records
the commitment at PO time. The two ledgers are on different clocks.

**Not a bug to fix in posting code without a decision.** See decision D3.

## H — 8250.4 of stock adjustments never became batches

32 `ADJUSTMENT` movements carry no `batch_id`:

| Item | Rows | Quantity | Value |
|---|---:|---:|---:|
| 1 | 19 | 2 | 750 |
| 2 | 13 | 18.751 | 7500.4 |
| **Total** | **32** | **20.751** | **8250.4** |

GL inventory is 6629.65 against batch value 14346.45. Invariant H reports GL
12813.25 vs expected 14346.45, diff -1533.2.

Note the numbers above do not by themselves explain the -1533.2: GL inventory and
batch value differ from the figures the invariant compares. **The -1533.2 has not
been fully isolated** and is deliberately not explained here rather than guessed.

**Verified against current code (2026-10-15).** `StockMovement.create`
(`src/models/StockMovement.ts:136-159`) already contains an explicit H10 fix: when a
movement has `quantity > 0` and no explicit `batch_id`, it creates a costed
`stock_batches` row, mapping `ADJUSTMENT` to `source_type='ADJUSTMENT'`. Current code
therefore **cannot** reproduce this defect. (Outbound movements are correctly excluded
— `qty > 0` is the guard, since a negative movement has no cost layer to create.)

**Classification: legacy data.** The 32 rows pre-date that fix. **The -1533.2 residue
is still not isolated** and is deliberately left unexplained rather than guessed.

See decision D4.

## I — GL cash differs from operational flows by -24100

GL entries touching account 1000:

| Reference type | Groups | Net |
|---|---:|---:|
| OWNER_CAPITAL | 4 | +110000 |
| SALARY_PAYMENT | 2 | -11000 |
| REFUND | 5 | -3900 |
| LOAN_DISBURSEMENT | 1 | -3000 |
| SUPPLIER_REFUND | 4 | -1800 |
| PURCHASE | 1 | -500 |
| PAYMENT | 46 | -400 |
| EXPENSE | 1 | -50 |

Owner capital contributes 110000 against a much smaller operational opening figure, and
several outflow types are thin or absent. **The -24100 has not been decomposed here.**
An earlier note proposed a decomposition; it was not reproduced during this pass and is
not carried forward.

**Verified against current code (2026-10-15).** The capability exists and is tested:
`backfillGlPreposting.ts` posts a `BACKFILL_OPENING` group (line 247), `cashService.ts:392`
voids stale ones, and `glBackfill.test.ts:103` asserts the expected `Dr 1000 / Cr 3000`
shape. The live database simply has no such row, so the backfill has never been run there.

Owner capital is posted at **110000** against four groups, while the operational opening
figure is far smaller — that asymmetry is the most likely origin of the gap, but it is
**not isolated here**.

**Classification: capability exists, never applied to this database; decomposition
unresolved.** Needs its own trace before any decision. See decision D5.

---

## What is safe to do without a product decision

1. **Fix the `postCreditOffsetEntry` docstring** so it stops claiming a
   `customer_ledger` write it does not perform. Documentation only.
2. **Keep the read-only diagnostics read-only.** Already done in 4d36c621.

## Decisions needed before anything else

**D1 — stale `paid_amount` headers (B/C).** Should the five invoice headers be
repaired so `paid_amount` reflects the positive allocations actually collected
(1200, 600, 1000, 500, 400), or left as legacy drift? Repair writes historical
financial rows. Leaving them means invariant B/C stays red permanently.

Note this is *not* a missing-`invoice_returns` question — that table holds only 2 rows
in the whole database, and the negative allocations on these invoices are the
deliberate REFUND path, which by design does not shrink `paid_amount`.

**D2 — customer credit sub-ledger (F). This is now the most urgent item, because
the defect reproduces.** Verified: no current code writes a `customer_ledger` row with
`transaction_type='CREDIT_OFFSET'`. Every credit offset posted from now on widens the
GL/sub-ledger gap. Three questions, in order:

1. Should current code write a `customer_ledger` row inside the same transaction as
   the GL entry? (Code-only for *future* offsets; does not repair history.)
2. Should the three existing offsets on invoices 52, 54 and 59 (1200, 550, 1800) be
   backfilled? (Historical write.)
3. If the sub-ledger is not intended to track credit offsets, what should invariant F
   actually compare?

**D3 — purchase-order commitments (G).** Should a PO commitment appear in the
supplier ledger at all, given GL recognises payables only at receipt? Options:
(a) accept the difference and scope invariant G to posted documents, (b) recognise a
PO commitment in the GL, which changes the balance-sheet timing, (c) stop writing
`PURCHASE_ORDER` rows to the supplier ledger. Each is a product call.

**D4 — unbatched adjustments (H).** Backfill batches for the 32 historical
adjustments, or accept them as legacy? Current code cannot reproduce them —
`StockMovement.create` batches every `qty > 0` movement — so this is cleanup, not a
bug fix. Backfilling touches live inventory quantities, prohibited for this pass.

**D5 — GL cash (I).** The backfill capability exists and is tested but has never run
on this database. Needs its own trace; recommend not bundling it with D1–D4.

## Recommendation

Priority order, on verified evidence rather than magnitude alone:

1. **D2, part 1.** It is the only confirmed defect that *keeps producing wrong data*.
   Writing the sub-ledger row in the same transaction is forward-only, changes no
   historical figure, and needs no product decision about what the sub-ledger means —
   only confirmation that a credit offset is a sub-ledger event.
2. **D3.** The cheapest fully non-destructive resolution: scoping the invariant resolves
   the red without touching data or changing accounting policy.
3. **D1 and D4** both rewrite historical financial/inventory rows. Both need an explicit
   go-ahead, and per the project rules a genuinely open product call is recorded in
   `audit/DECISIONS.md` as `OPEN-DECISION` rather than guessed.
4. **D5** stays separate.
