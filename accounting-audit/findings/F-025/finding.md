# F-025 — Correcting one count item silently removes other items' shortages

**Status:** CONFIRMED current mounted API, fresh fixture. **Severity:** High. **Category:** partial update/reversal scope/inventory and expense integrity. **Owner:** backend-controls. No fix applied.

## Independent expectation

A correction request naming itemA should change itemA only. If complete replacement of every counted item is required, the server must reject an incomplete request before mutation. It must not silently undo itemB's valid recorded shortage while retaining a count row that says that shortage remains posted.

Invocation: `node accounting-audit/tests/backend-count-risk.cjs`.

Starting from valid stock itemA2@20, itemB10@10, complete a count with A1 and B8. The new shortages cost20 each. POST `/api/inventory/physical-counts/:id/correct` with only `corrections:[{item_id:A,counted_quantity:2}]` returns200.

Expected: restore A1 unit and its20 loss; B stays8 units with its20 shortage. Actual: B restores to10 units too, but its `physical_count_items` still says counted_quantity8, variance−2, adjustment_posted1 and points at its original movement whose GL was voided. B inventory is overstated20 and shrinkage understated20. Captured aggregate GL before inventory100/loss150, correct expected after120/130, actual140/110. The prior110 loss belongs to a separate valid count and remains unchanged; no earlier corrupt data is needed for this defect.

## Root cause and scope

`server/src/models/PhysicalCount.ts:correctCount` iterates **all** snapshot items through reverseCountAdjustment, then iterates **only data.corrections** through postCorrectedCountItem. Omitted count rows are not cleared or reapplied. `server/src/controllers/inventoryController.ts:914–957` accepts any nonempty array with numeric item/quantity, without requiring full replacement. An authenticated client can submit this body regardless of how the current Flutter form builds its request.

## Evidence

`accounting-audit/evidence/backend-count-risk-run-ZBybHv/results.json`, scenario `BACKEND-COUNT-PARTIAL-CORRECTION`, defectReproduced=true. Full API events plus `03-two-item-count-completed.json` and `04-partial-item-correction.json` show requests, quantities, unchanged omitted-item count row, voided journals and GL balances. Retained erp.db; `backend-count-risk-verified.log`. SQLite integrity/FK checks and journal balance groups remain clean despite the economic defect.

The same run's preceding mixed-batch correction attempt was rejected transactionally (F-024); before/after snapshots establish that it left the valid initial shortage intact. It does not explain or excuse the later omitted-item restoration.

## Remediation direction / regression

Choose explicit correction semantics: reverse/reapply only identified items, or require the complete set and reapply every item with preserved values for unchanged entries. Add a2-item shortage regression correcting one item; assert the other item's batch quantity, count row, GL, loss and movement linkage remain untouched. Also verify a rejected partial request is fully atomic if complete-replacement semantics are chosen. No production changes made.
