# F-024 — Multi-batch shortage corrections fail because all stock is restored to one batch

**Status:** CONFIRMED current mounted API, fresh fixture. **Severity:** High workflow/inventory-correction failure. **Category:** batch provenance/reversal. **Owner:** backend-controls. No fix applied.

## Scenario and independent expected accounting

Purchase5 units@10 on1Sep and5 units@20 on2Sep: quantity10, value150. Complete a3Sep physical count of2. FIFO shortage8 correctly consumes5@10+3@20, leaving2@20=value40 and loss110. Recount to8 should reverse original layers, then consume2@10: remaining3@10+5@20=value130, quantity8, loss20.

Invocation: `node accounting-audit/tests/backend-count-risk.cjs`.

Actual POST `/api/inventory/physical-counts/:id/correct` with `corrections:[{item_id:1,counted_quantity:8}]` returns500 and exposes `CHECK constraint failed: quantity_remaining >= 0 AND quantity_remaining <= quantity_original`. The original count remains unchanged at quantity2/value40/loss110; transaction rollback is effective, but the legitimate correction is unavailable.

## Root cause

`server/src/models/PhysicalCount.ts` completeCount records only `consumption[0].batchId` on one aggregate adjustment movement despite possibly consuming several cost layers. In correctCount, local restoreCountShortage deliberately adds the entire absolute original variance to that primary batch. Here it attempts to restore8 into the first batch with quantity_original5. The database constraint catches it. The second batch's3 consumed units have no persisted per-layer reversal provenance.

Graph symbols completeCount/correctCount and exact source paths were inspected and coverage checked. Source comments explicitly acknowledge primary-only provenance; this is not a hypothetical unsupported negative search.

## Evidence

`accounting-audit/evidence/backend-count-risk-run-ZBybHv/results.json`, scenario `BACKEND-COUNT-MIXED-COST-CORRECTION`, defectReproduced=true. Exact requests/responses are in api[]. `01-mixed-count-completed.json` and `02-mixed-count-corrected.json` capture full batches, stock, journal, movements and count rows before/after. Retained erp.db and `backend-count-risk-verified.log`. Full run exit0 means reproducer completed and captured the defect, not that production behavior passed.

## Impact, recommended correction and regression

Any shortage spanning batches can become uncorrectable when total shortage exceeds first-batch capacity. Never relax the batch constraint to make correction succeed; that would move stock into the wrong cost layer and can corrupt valuation. Persist consumed batch allocations at completion and restore exact layers on correction, then reconsume as required. Regression must use different batch prices and assert quantity, layer values, GL inventory, loss and original-count rollback on failure. Also exercise location-enabled batches separately; that branch was not dynamically covered here.
