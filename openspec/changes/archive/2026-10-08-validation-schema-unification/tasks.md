# Validation Schema Unification — Tasks

## Phase 0 — Measure reachability before fixing

- [x] 0.1 Read the route, the controller and the validator end to end.
      **done-when:** confirmed
      `routes/forecasts.ts:26` → `validateZodBody(zodBodySchemas.modelConfig)` →
      `forecastsController.setModelConfigHandler:157` spreads `req.body` →
      `forecastService.setModelConfig` splices `Object.entries(config)` keys.
- [x] 0.2 Execute candidate payloads against a replica of the production
      statement shape rather than reasoning about them.
      **done-when:** the boolean oracle is measured. A key of
      `model_type = (SELECT password_hash FROM users LIMIT 1) = 'SECRET'` stores
      `1`; the same key with `= 'WRONG'` stores `0`.
- [x] 0.3 Record which payloads are *rejected*, so the report does not overstate.
      **done-when:** `WHERE 1=1 --` and `--` truncation fail on parameter arity,
      and `better-sqlite3.prepare()` refuses stacked statements. This was a read
      oracle, not a drop-table primitive.

## Phase 1 — Close the sink

- [x] 1.1 Replace `Object.entries(config)` in `setModelConfig` with a hardcoded
      `MODEL_CONFIG_COLUMNS` allowlist, covering both the UPDATE and INSERT
      branches.
      **done-when:** `the service layer drops an unknown key even when the schema
      is bypassed` passes.
- [x] 1.2 Handle a config with no recognised field by updating `updated_at`
      alone, so an empty body does not produce invalid SQL.
      **done-when:** `a legitimate config still saves` passes and no test throws
      on an empty body.
- [x] 1.3 Keep values as bound parameters throughout.
      **done-when:** `tsc --noEmit` clean; no template literal in the statement
      contains a caller-supplied identifier.

## Phase 2 — Close the enabler

- [x] 2.1 Replace `modelConfig: z.object({}).passthrough()` with a real schema
      using `.strict()`.
      **done-when:** `an injected column name is rejected with 400 and writes
      nothing` passes.
- [x] 2.2 Bound the numerics to their domain and enum `model_type`.
      **done-when:** a body with an out-of-range smoothing factor fails 400.
- [x] 2.3 Verify a legitimate multi-field config still saves.
      **done-when:** `a legitimate config still saves` passes.

## Phase 3 — SEC-002 inventory and structural guard

- [x] 3.1 Check whether any other passthrough schema reaches a key-splice sink.
      **done-when:** measured. `Settings.ts:147` uses a hardcoded `keys.others`
      map; `entityRegistry` is a hardcoded registry; `createSeasonalEvent` writes
      explicit columns. `modelConfig` was the only sink.
- [x] 3.2 Pin the seven remaining passthrough schemas in an inventory so adding an
      eighth fails a test.
      **done-when:** `every remaining z.object({}).passthrough() schema is listed
      in KNOWN_PASSTHROUGH` passes.
- [x] 3.3 Add a structural scan for SQL built from `Object.keys`/`Object.entries`
      over `services/`, `models/`, `controllers/`, `middleware/`.
- [x] 3.4 **Prove the guard fires.** Reintroduce the original
      `setModelConfig`.
      **done-when:** `sqlKeyInjectionGuard.test.ts` fails and names
      `services/forecastService.ts:1192` and `:1199`. Verified — a guard never
      seen to fail is not a guard.

## Phase 4 — Anti-vacuity

- [x] 4.1 Revert both the service and the schema.
      **done-when:** 4 of 5 in `forecastConfigInjection` fail, including the oracle
      test, which receives HTTP 200 instead of 400.
- [x] 4.2 Restore both.
      **done-when:** 5 of 5 and 4 of 4 pass.

## Phase 5 — Verification

- [x] 5.1 `npx tsc --noEmit` — exit 0.
- [x] 5.2 `npx eslint` on the four touched files — exit 0. The 2 warnings in
      `forecastService.ts` are pre-existing at HEAD (verified by stashing the file
      and re-linting).
- [x] 5.3 `npx jest --silent` — 120 suites / 1043 tests green.
- [x] 5.4 `openspec validate --all` — 0 failed.
- [x] 5.5 No database was written to. The payload probe used an in-memory
      replica; the regression tests create and delete their own item.
- [x] 5.6 Archive via the gate — every box above is ticked.

## Recorded, not done

- Rewriting the seven remaining passthrough schemas (SEC-002 residue, ~48 route
  bindings) is deliberately not attempted here. Each handler filters explicitly
  today and no second sink was found; the inventory plus the structural scan
  prevent a silent recurrence.
- `CODE-005`, the shared typed invoice-item schema, is the same instinct applied
  to the invoice path. It remains `planned` in the coverage ledger.
