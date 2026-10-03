# strictNullChecks rollout — working notes

Enabling `strictNullChecks` is the highest-leverage remaining item: it is the
check that would have caught the never-populated `customer_credit_limit`
client field structurally, rather than by grep, and it is what makes the
row types added during the `any` removal actually enforced.

## Baseline (commit a18087e9, before any fix)

    tsc --noEmit --strictNullChecks  ->  34 errors across 19 files

    TS2322  19   assignment, target excludes null/undefined
    TS2345   5   arg of type T|null passed to T
    TS18047   4   'x' is possibly null
    TS2339   3   property does not exist on type never
    TS2783   1   'asOfDate' specified more than once -> overwritten
    TS2454   1   'mergedLoans' used before being assigned
    TS2366   1   function lacks ending return, type excludes undefined

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

## Sequencing

Strictest-first is wrong here: Batch A fixes 11 of 34 in one place, and
those lines are easy to revert if the diagnosis turns out to be wrong.
Bugs get fixed first regardless.

| Batch | Scope | Errors |
|---|---|---|
| A | `PhysicalCount.variance` nullable root cause | 11 |
| B | `getSalesCycleChain` return types (regression from the `any` sweep) | 6 |
| C | 3 latent-bug shapes — read as bugs, not types | 3 |
| D | Nullable DECIMAL columns — widen **and** annotate the schema intent | 12 |
| E | Tests + migration script, then flip the flag | 3 |

## Commit policy

The flag flips in the same commit as the final fix batch, so the tree is
never strict-null-clean-but-unenforced for longer than one commit.

An advisory (non-gating) CI job runs `tsc --noEmit --strictNullChecks` so
the count is visible per-PR and regressions surface before the flip.