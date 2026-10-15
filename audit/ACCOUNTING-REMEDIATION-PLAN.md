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

**Corrected 2026-10-15 — this finding was wrong.** It was previously recorded here
as an open defect that reproduced on every new credit offset. Investigation of the
actual posting paths shows the opposite: the subledger and the GL already move
together, and there is no missing write.

Two callers post a GL credit offset, and they differ on purpose:

- `PaymentRecordingService` (`CREDIT_APPLICATION`) posts GL only, with no ledger row,
  because the originating return already wrote a `RETURN` credit row. Its comment
  says so: "the return already credited the ledger."
- `InvoiceCreationService` writes a `CREDIT` ledger row, but only for the part drawn
  from the `customers.credit_balance` **pool** — `poolApplied = min(creditOffset, credit_balance)`.
  Credit that lives on the ledger as a negative `current_balance` is extinguished by
  the new invoice's own `INVOICE` row and correctly gets no extra row.

Verified end to end against a live test database (`server/src/__tests__/creditOffsetSubledger.test.ts`):
a 200 offset drawn from ledger credit posts `Dr 1110 / Cr 1100`, moves no cash, leaves
exactly one economic credit event, and settles the invoice to 0; a 200 offset drawn from
the pool writes one `CREDIT` row and draws the pool down. Neither path double-credits.

**The originally proposed fix — writing a `CREDIT_OFFSET` ledger row on every offset —
was not implemented.** It would have credited each invoice settled by ledger credit a
second time and corrupted customer balances. `CREDIT_OFFSET` exists in the live database
only as two historical rows (customer 15, invoices 50 and 51) whose writers no longer exist.

**Classification: historical-data reconciliation issue. Not an ongoing production defect.**
`docs/ACCOUNTING-REMEDIATION-PLAN.md` section F remains OPEN until live reconciliation passes.

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

**D2 — customer credit sub-ledger (F). RECLASSIFIED 2026-10-15: historical data, not a
code defect.** No code change is required or proposed. The live database carries five GL
credit-offset groups totalling 5350, of which the sub-ledger represents 1800:

| Invoice | `credit_offset` header | GL `Dr 1110` | Sub-ledger row | Status |
|---|---:|---:|---:|---|
| 50 `INV-0926-00008` | 0 | 600 | 600 | present, but header disagrees |
| 51 `INV-0926-00009` | 0 | 1200 | 1200 | present, but header disagrees |
| 52 `INV-0926-00010` | 1200 | 1200 | none | absent |
| 54 `INV-1026-00002` | 550 | 550 | none | absent |
| 59 `INV-1026-00007` | 1800 | 1800 | none | absent |

GL total 5350 less sub-ledger 1800 leaves 3550 unrepresented, while F reports a net
1800. The two are not equal because invoices 50 and 51 record `credit_offset = 0` on
the header while carrying a sub-ledger row anyway. The historical records are internally
inconsistent in more than one direction, so this is not a mechanical missing-row gap.

An append-only reversal of the two `CREDIT_OFFSET` rows was prototyped on an isolated
copy and **rejected**: it moved F from +1800 to −3600 and left customer 15 showing a
+5400 receivable, because those rows agree with the GL at 1800 and removing them
desynchronises the sub-ledger instead of repairing it. See D2b.

**D2b — how to reconcile F, if it is reconciled at all.** This is a data decision, not a
code one, and it is explicitly out of scope for the current pass. Options, none yet chosen:
(a) leave the history and accept F stays red, recording why; (b) rebuild customer 15's
sub-ledger from source documents; (c) restate the three invoices whose headers claim a
credit offset the ledger never recorded. Each rewrites recorded financial history and
needs its own approval. **Not started.**

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

Reordered 2026-10-15 after F was reclassified. D2 no longer leads: it is historical
data with no code defect behind it, so nothing can be fixed forward.

1. **D3** is now the only item with a clean non-destructive resolution — scoping the
   invariant resolves the red without touching data or changing accounting policy.
2. **D2b**, if reconciliation is wanted, is a separate data exercise requiring its own
   approval. The prototyped reversal was tested and rejected on the numbers.
3. **D1 and D4** both rewrite historical financial/inventory rows and need explicit
   go-ahead; per the project rules a genuinely open product call is recorded in
   `audit/DECISIONS.md` as `OPEN-DECISION` rather than guessed.
4. **D5** stays separate.

## Regression coverage added

`server/src/__tests__/creditOffsetSubledger.test.ts` pins the corrected contract for
both credit sources — a ledger-credit offset (one credit event, no extra row, invoice
settles to 0) and a store-credit-pool offset (one `CREDIT` row, pool drawn down) — and
asserts no cash account is touched by a `CREDIT_OFFSET` group. It exists to stop the
"missing sub-ledger row" reading from being reintroduced as a code fix.
