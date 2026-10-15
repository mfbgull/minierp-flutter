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

## B/C — fully returned invoices carry negative payments (drift -3900)

Five invoices report `paid_amount` that disagrees with their payment allocations:

| Invoice | Reference | Diff |
|---|---|---:|
| 26 | POS-2026-000001 | -1200 |
| 27 | POS-2026-000002 | -600 |
| 31 | INV-2026-631367 | -1200 |
| 39 | INV-2026-705309 | -500 |
| 40 | INV-2026-512634 | -400 |

These are fully-returned POS/manual invoices created through the **old** return path,
which reversed the payment by writing a negative payment row instead of creating an
`invoice_returns` record. Current code takes the modern path.

**Classification: legacy data, not a current-code defect.** The five invoices
predate the `invoice_returns` table.

**Not repaired here.** Repair means writing historical financial rows, which is
explicitly out of scope. See decision D1.

## F — GL AR exceeds the customer sub-ledger by 1800

GL AR 3499.8 vs customer balances 1699.8. The credit-offset trail:

- `customer_ledger` holds two `CREDIT_OFFSET` rows totalling 1800
  (`CREDIT-INV-0926-00008` = 600, `CREDIT-INV-0926-00009` = 1200).
- GL holds **five** `CREDIT_OFFSET` journal groups, keyed to invoices 50, 51, 52, 54, 59.

So the GL recognised credit offsets against five invoices while the sub-ledger
recorded only two of them.

There is also a documentation defect in the current code.
`AccountingService.postCreditOffsetEntry` (`src/services/accountingService.ts:627`)
states:

> The customer credit balance is also tracked in customer_ledger/customers.current_balance for sub-ledger reporting.

The function posts **only** `Dr 1110 Customer Credit / Cr 1100 AR`. It writes no
`customer_ledger` row and touches no `current_balance`. Either the docstring
describes behaviour that lives in a caller, or the sub-ledger write was lost. The
live data suggests some path does write it, since two `CREDIT_OFFSET` ledger rows
exist — but the two are not reconciled by invoice id in the data inspected here.

**Classification: partly current-code (misleading contract), partly legacy
(sub-ledger incompleteness).** The missing sub-ledger rows may be exactly the
1800 drift.

**Safe without touching data:** correct the docstring to describe what the function
actually does. See decision D2.

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

**Classification: legacy data plus an unresolved residue.** Unbatched adjustments are
historical; the residual difference needs a separate trace.

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

`backfillGlPreposting.ts` implements a `BACKFILL_OPENING` posting, but no live
`BACKFILL_OPENING` row exists.

**Classification: unresolved.** Needs its own trace before any remediation.

---

## What is safe to do without a product decision

1. **Fix the `postCreditOffsetEntry` docstring** so it stops claiming a
   `customer_ledger` write it does not perform. Documentation only.
2. **Keep the read-only diagnostics read-only.** Already done in 4d36c621.

## Decisions needed before anything else

**D1 — legacy negative-payment returns (B/C).** Should the five invoices be
migrated to real `invoice_returns` records, or left as-is and documented as legacy?
Migrating rewrites historical financial rows and changes reported AR for those
customers. Leaving them means invariant B/C stays red forever.

**D2 — customer credit sub-ledger (F).** What is authoritative: the GL credit-offset
groups, or the `customer_ledger` rows? If the sub-ledger is meant to be complete, the
missing three invoice offsets (52, 54, 59) must be written — that is a historical data
write. If the docstring was simply aspirational, it should be corrected and F
re-baselined.

**D3 — purchase-order commitments (G).** Should a PO commitment appear in the
supplier ledger at all, given GL recognises payables only at receipt? Options:
(a) accept the difference and scope invariant G to posted documents, (b) recognise a
PO commitment in the GL, which changes the balance-sheet timing, (c) stop writing
`PURCHASE_ORDER` rows to the supplier ledger. Each is a product call.

**D4 — unbatched adjustments (H).** Backfill batches for the 32 historical
adjustments, or accept them as legacy? Backfilling touches live inventory quantities,
which is explicitly prohibited for this pass.

**D5 — GL cash (I).** Requires its own investigation before it can be decided. I
recommend not bundling it with D1–D4.

## Recommendation

D1 and D4 both rewrite financial or inventory history. Both need an explicit go-ahead,
and per the project rules a genuinely open product call is recorded in
`audit/DECISIONS.md` as `OPEN-DECISION` rather than guessed. D3 is the only one with a
clean non-destructive resolution (scoping the invariant), so it is the cheapest place
to start.
