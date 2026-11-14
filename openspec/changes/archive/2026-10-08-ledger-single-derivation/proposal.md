# Ledger Single Derivation — PUR-002, PUR-004, PUR-006, SALES-007, ACCT-004, SALES-021

## What Changes

- `models/Reports.ts` — `computeAPAging` gains `reversed_by IS NULL` and an
  as-of filter on both queries; `getGLReconciliation`'s AP row switches from
  reading the highest-id row's `balance` to `SUM(debit) − SUM(credit)`;
  `getARAgingReport` and `getReceivablesSummary` assign a NULL `due_date` to
  `current_amount` instead of to no bucket.
- `models/SupplierLedger.ts` — `getBalance` orders by `id DESC`, matching
  `rebuildBalances`.
- `utils/reportSql.ts` — `AR_OUTSTANDING` includes `deleted_at IS NULL`.
- `models/Invoice.ts` — `createLedgerEntry` seeds from the last non-voided,
  non-reversal row in `id` order.
- `__tests__/apSingleDerivation.test.ts` — new.
- `__tests__/arSurfaceConsistency.test.ts` — new.

Deltas recorded against `ledger-append-only`, `balance-truth-sources` and
`report-query-integrity`.

## Why

Six findings, one cause: **the same ledger was derived six different ways**, and
the ways disagreed. Each disagreement was invisible because every one of them
returned a number that looked plausible.

## The live error, measured

`server/database/erp.db`, read-only, comparing the as-coded query with the fixed
one over the real rows:

```
supplier | as-coded AP | corrected AP | current_balance | delta
       1 |      -4000  |        1000  |           1000  |  5000  <-- AS-CODED WRONG
       2 |       5000  |        5000  |           5000  |     0
```

Supplier 1 reported **−4,000** — a negative payable — where the truth is
**+1,000**, and the corrected figure ties to `suppliers.current_balance` exactly.
That is the audit's number, reproduced and fixed. No data repair is needed: the
*report* was wrong, not the books.

## The six

| # | Finding | Defect |
|---|---|---|
| 1 | PUR-002 | credit side omitted `reversed_by IS NULL`, so a void was charged twice |
| 2 | PUR-006 | neither side filtered on `asOfDate` |
| 3 | PUR-004 / H-04 | `getBalance` ordered by `transaction_date`, `rebuildBalances` by `id`; `getGLReconciliation` read a column undefined after any void |
| 4 | SALES-007 | `AR_OUTSTANDING` filtered on status only; a soft-deleted invoice counted as live AR |
| 5 | ACCT-004 | a NULL `due_date` landed in no bucket, so the aging did not foot |
| 6 | SALES-021 | `createLedgerEntry` seeded from a reversal row's unmaintained balance |

SALES-017 (SO→invoice drops `due_date`) is **not** fixed here. `SalesOrder.ts:645`
passes `invoiceData?.due_date ?? null`, and the correct target — whether the
default should apply to an explicit `null` — is a product decision about payment
terms, not a derived-balance defect. It stays `planned` rather than being
guessed at.

## Anti-vacuity, both directions

| state | apSingleDerivation + arSurfaceConsistency |
|---|---|
| all fixes reverted | **12 of 12 fail** |
| all fixes applied | 12 of 12 pass |

## Full verification

- `npx jest --silent` — 122 suites / 1055 tests green
- `npx tsc --noEmit` — exit 0
- `openspec validate --all` — 0 failed
- `server/database/erp.db` opened read-only; `git status` shows no change under
  `database/` or `server/database/`

## Out of scope

- SALES-017, as above.
- The live-data repair of the PUR-001 phantom 5,000 remains in
  `live-data-repair`, gated on `reversal-symmetry` — which has now landed.

## Risk and rollback

Low. `AR_OUTSTANDING` is the widest change: any AR surface that intentionally
included soft-deleted invoices would now exclude them. That is the intent — none
should — and the reconciliation delta is the check.

`getBalance` ordering changes which row a backdated ledger reads. Since
`rebuildBalances` maintains `balance` in `id` order, reading in `id` order is the
first time the reader and writer have agreed.

Rollback: revert five files. No migration, no schema change, no data change.
