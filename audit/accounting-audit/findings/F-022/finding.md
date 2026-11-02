# F-022 — Joint production can create a negative-cost output and overstate inventory GL

> Current assessment, 2026-10-26: this report preserves its historical audit snapshot. See [remediation status](../../remediation/STATUS.md) for current source verification, fixes, tests and remaining limits.

**Status:** CONFIRMED, current mounted API, fresh DB. **Severity:** High integrity defect (minimal example is one cent). **Category:** allocation rounding / batch valuation / GL completeness. **Owner:** backend-controls. No fix applied.

## Independent expected accounting

A production consumes a single raw-material unit costing0.02 and produces four distinct outputs, quantity1 each, each with selling price1. Total pool=0.02. All output allocations must be nonnegative and sum0.02; any deterministic residual policy may assign two cents to two of the products and zero to the other two. Net inventory valuation must remain0.02 and production clearing must return0.

Actual algorithm independently rounds each of the first three0.005 shares upward to0.01, then gives the last product the remainder−0.01. The sum still equals0.02, but one batch is negative-valued. Its posting helper skips nonpositive amounts, so GL recognizes three positive0.01 outputs without the fourth balancing economic reduction. Final inventory GL0.03 versus costed-batch sum0.02; clearing credit residual0.01.

## Reproduction

Invocation from repo root: `node accounting-audit/tests/backend-controls.cjs`.

Fresh authenticated admin; create raw material and four manufactured outputs with equal selling price1. POST `/api/purchases` quantity1, unit_cost0.02, date2026-09-01. POST `/api/productions` warehouse id, date2026-09-20, input_items raw quantity1 and outputs four different item ids quantity1. Status201.

Observed `production_outputs` allocated_cost/unit_cost: `[0.01,0.01,0.01,-0.01]`; before inventory0.02/clearing0, after inventory0.03/clearing−0.01. Database integrity_check=ok and foreign_key_check=[]; balancing constraints do not prevent incorrect value allocation. This was reproduced from new data only. Initial probes using singular `/api/production` returned404 and were harness failures, not evidence of this finding.

## Source

- `server/src/models/Production.ts:405–415` independently rounds first n−1 shares; last output receives unbounded residual.
- `Production.ts:426–468` persists negative allocated/unit costs into new stock batches and production_outputs.
- `server/src/models/StockMovement.ts:879–882` skips GL posting when total_batch_cost<=0, silently diverging from persisted negative output.
- Authenticated mounted route `server/src/routes/production.ts:11`, mounted at `/api/productions` in app.ts.

Graph discovery and exact path coverage checked; no recorded gaps in these TypeScript paths. SQL schema dump in results.json confirms relevant table definitions; no negative allocation safeguard rejected the POST.

## Evidence

`accounting-audit/evidence/backend-run-Lbw3la/results.json`, scenario `BACKEND-PRODUCTION-ROUNDING`: status201, four exact output rows, before/after account balances, defectReproduced=true. Same artifact captures authenticated request body, response and canonical journal. Retained SQLite `backend-run-Lbw3la/erp.db` contains stock_batches/production_outputs for inspection. `accounting-audit/evidence/backend-probes-verified.log` records completed run. All four consolidated scenarios reproduced in this run.

## Recommended correction and regression requirements

Allocate integer currency minor units with a nonnegative remainder algorithm (for example floor shares and distribute leftover cents by a deterministic largest-remainder order). Enforce nonnegative output allocation before any batch persistence. Do not fix merely by posting a negative journal amount or ignoring the final output. Test four equal outputs/pool2c, many outputs with tiny last weight, order changes, zero-priced outputs, positive overhead, reversal and sale of the affected outputs; assert nonnegative costs, exact pool sum, inventory=GL and clearing0.
