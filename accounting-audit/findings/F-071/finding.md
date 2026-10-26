# F-071 — Reservation replay reserves the same quantity twice at the location

**Status: Confirmed defect. Severity: Medium.** Proven operational stock-availability corruption; no inventory asset/COGS/cash misstatement demonstrated.

## Reproduction / expected / actual

With `feature_batch_locations` enabled in the disposable fixture, stock10 in a batch/location, POST `/api/inventory/reservations` twice with identical item7/batch7/location1, quantity3, reference SALES_ORDER/SC-RES-REPLAY/line1. Both requests return201 and the same reservation id1. A semantic replay must reserve3 once; releasing it must leave reserved0/available10.

Actual: one ACTIVE reservation row quantity3, but location quantity_reserved6/available4. DELETE `/api/inventory/reservations/1/release` returns200 and marks the row RELEASED, while the location retains reserved3/available7 with no corresponding active reservation. Three units remain falsely unavailable. Physical quantity/value and financial GL remain unchanged. A separate single-create/non-null-line release control restores available10 correctly.

## Root cause / source

`StockReservationModel.create` at `server/src/models/StockReservation.ts:22–82` returns an existing ACTIVE row on duplicate. `server/src/controllers/inventoryController.ts:1330–1355` still unconditionally increments the location reservation by the request quantity. Release at1357–1390 subtracts only the persisted row's3 once. The reservation and location update are not one idempotent primitive.

## Evidence / remediation / regression

Executed `node accounting-audit/tests/sales-channel-extension.cjs`; authoritative run `accounting-audit/evidence/sales-channel-run-AFjr5O`: actual API events plus `22-reservation-replayed.json`, `23-reservation-released.json`, positive control25/26 snapshots and `erp.db`. Independent read-only proof: [final-extension-verification.json](../../evidence/final-extension-verification.json), F071.

Recommended correction: make create/replay/reactivation and location reservation changes one atomic source operation; a replay must not apply a second delta. Do not clear reservations indiscriminately. Regression: duplicate create→release, reactivation, changed-quantity retry and concurrent same-reference attempts; reconcile location reserved quantity to active reservations and physical/available quantities. Test both feature branches. No production fix applied.
