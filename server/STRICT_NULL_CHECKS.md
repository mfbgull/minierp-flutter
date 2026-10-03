# strictNullChecks rollout — working notes

`strictNullChecks` is now **enabled** in `tsconfig.json`. The gating
`npm run typecheck` CI step is the regression gate; the old advisory-counting
job was removed at the flip.

Enabling it was the highest-leverage remaining item: it is the check that
would have caught the never-populated `customer_credit_limit` client field
structurally, rather than by grep, and it is what makes the row types added
during the `any` removal actually enforced.

## Baseline (commit a18087e9, before any fix)

    tsc --noEmit --strictNullChecks  ->  34 errors across 19 files

    TS2322  19   assignment, target excludes null/undefined
    TS2345   5   arg of type T|null passed to T
    TS18047   4   'x' is possibly null
    TS2339   3   property does not exist on type never
    TS2783   1   'asOfDate' specified more than once -> overwritten
    TS2454   1   'mergedLoans' used before being assigned
    TS2366   1   function lacks ending return, type excludes undefined

## Result

    34 -> 27   Batch A   PhysicalCount.variance nullable root cause
    27 -> 24   Batch C   3 latent bugs, fixed as bugs
    24 -> 16   Batch B   getSalesCycleChain return types
    16 ->  8   Batch D   nullable DECIMAL/TEXT columns
     8 ->  0   Batch E   migration script, supplier refunds, tests

Batch A was planned at 11 but the file only had 7; the other 4 were
TS2345 argument errors from the same root cause and were counted in the
already-fixed lines.

`npm run typecheck`, `npx eslint . --quiet` and `npx jest` (958 tests) all
pass with the flag on.

## Why currency.ts and quantity.ts contribute zero

Not because earlier passes cleaned them — they never touch the database.
Both have zero `db.prepare` / `.get(` / `.all(` occurrences; they are pure
computation, so a nullable SQL column cannot reach them.

DB reads that need arithmetic are funnelled through
`parseCurrency(value: unknown)`, which absorbs null and NaN explicitly:

    if (value === null || value === undefined) return 0;

106 call sites across 19 files use it. That funnel is why the
"silently null forever" class never appeared in these modules. The 34
errors are the calls that bypass it — which is why the fix is to route
through the parser or widen with intent, never to blanket-widen.

`noImplicitAny` needs no work at all: the `no-explicit-any` sweep
(407 -> 0) already cleared it.

## The three real bugs (Batch C)

These were type errors that turned out to be defects, and are the reason
this work was worth doing beyond type coverage:

- **`activityLogger.flush()` never returned on the success path.** Declared
  `flush(): boolean`, but the `try` block fell through to the end of the
  function, so a successful flush returned `undefined` — falsy, and
  indistinguishable from failure to any caller checking the return. There
  was also dead code after the `return false` in the `catch`. Callers
  ignore the return today, so nothing was observably broken yet.
- **`getReceivablesSummary` response double-specified `asOfDate`.** The
  controller spread the model result *after* an explicit `asOfDate` key, so
  the model value silently overwrote the query-derived one. They happened to
  agree, which is why it was invisible; the explicit key is now gone and the
  model result is returned as-is.
- **Borrower merge returned an uninitialized `mergedLoans`.** The value was
  assigned inside a `db.transaction` callback and read after, with a
  `mergedLoans!` non-null assertion hiding the definite-assignment error.
  The transaction now returns the row count, so the assertion is unnecessary.

Additionally, `supplierRefundController` never validated `amount`, so
`Number(undefined)` produced `NaN` that surfaced as a 500 from the model
layer instead of a 400.

## Batch D: widening at the schema boundary

Every widening in this batch was made at the interface that represents a
nullable SQL column, not at the call site, and each one was checked against
how the value is actually written:

- `voidJournalLinesByReference` / `voidOwnInvoiceReturnLines` attribution,
  `PostEntryInput.created_by` / `reference_id`, and
  `postLegacyStockEntry.createdBy` — all `| null`. The columns are nullable
  and the code already wrote `|| null`; the types were simply narrower than
  the schema. This also matches the sibling void APIs (Employee, EmployeeLoan,
  OwnerCapital), which were already `number | null`.
- `PostEntryInput.reference_id` is nullable because a GL-only or
  system-originated entry legitimately has no source document.
- `StockMovement.postFinancialEntryForAdjustment.created_by` — `recordMovement`
  already accepted `userId: number | null`.
- `InvoiceReturn.createReturn.reason` and `CustomReport` duplicate's
  `description` — row `null` mapped onto the DTO's optional, since `create()`
  already normalizes `undefined` to `NULL`.

## Batch B: `let x = undefined` does not infer a type

`let salesOrder = undefined;` has no inferred type for TypeScript to evolve,
so the later assignment collapsed the variable to `never` and the property
reads on it failed. Four sites (Invoice, Quotation, SalesOrder) now carry
explicit `T | undefined` annotations.
