# F-072 — A reservation with the optional line ID omitted cannot be released

**Status: Confirmed defect. Severity: Medium.** Release workflow/availability failure; no current money/valuation corruption proven. Expected result: the accepted active reservation releases200 and restores its availability; actual400 leaves it active.

Authenticated POST `/api/inventory/reservations` accepts item9/batch9/location1, quantity2, reference SALES_ORDER/SC-RES-NOLINE and no reference_line_id. It returns201, id3, ACTIVE with a SQL NULL line ID. DELETE `/api/inventory/reservations/3/release` should release this accepted reservation by id and restore availability. Actual400 says Reservation is not active; row remains ACTIVE, reserved2/available8, economic snapshot unchanged. A non-null-line positive control releases successfully200.

Root cause: `server/src/models/StockReservation.ts:84–106` searches `reference_line_id = ?` with NULL. SQL equality does not match NULL. `server/src/controllers/inventoryController.ts:1357–1390` first finds the row by id but delegates to this null-sensitive reference lookup, then reports it inactive. The model/type accepts line ID as optional; this is not an invented unsupported body.

Evidence: final `sales-channel-run-AFjr5O/api-events.json`, `27-reservation-noline-before.json`, `28-reservation-noline-after.json` and retained DB. Reproduce with `node accounting-audit/tests/sales-channel-extension.cjs`. Independent read-only proof: [final-extension-verification.json](../../evidence/final-extension-verification.json), F072.

Recommended correction: release the actual identified reservation atomically or use an intentional NULL-aware reference predicate; creation and release must agree about optional identifiers. Regression: omitted/explicit-null/non-null line IDs, duplicate attempts, consumption/expiry release and unchanged state on genuine invalid requests. Do not simply delete the accepted active row or its history. No fix applied.
