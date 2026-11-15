# Validation Schema Unification — SEC-001, SEC-002

## What Changes

- `services/forecastService.ts` — `setModelConfig` builds its column list from a
  hardcoded `MODEL_CONFIG_COLUMNS` allowlist instead of `Object.entries(config)`.
  Values are still bound.
- `middleware/validation.ts` — `modelConfig` becomes a real schema with
  `.strict()`, a `model_type` enum, and range-bounded numerics.
- `__tests__/forecastConfigInjection.test.ts` — new; proves the oracle and its fix.
- `__tests__/sqlKeyInjectionGuard.test.ts` — new; structural guards against the
  pattern recurring.
- `specs/authz-hardening/spec.md` — the delta.

## Why

`PUT /api/forecasts/models/:itemId` bound `zodBodySchemas.modelConfig`, which was
`z.object({}).passthrough()` — it validated nothing. The controller spread the
body over the route's `itemId`, and `setModelConfig` built its SQL column list
from `Object.entries(config)`:

```ts
sets.push(`${key} = ?`);                                                   // raw
db.prepare(`UPDATE forecast_model_config SET ${sets.join(', ')} …`)        // spliced
```

So a caller could put arbitrary SQL where a column name belongs.

## The measured exploit

Not theoretical. Every payload below was executed against a replica of the
production statement shape:

| key sent | resulting SQL | outcome |
|---|---|---|
| `model_type` | `SET model_type = ?` | legitimate |
| `created_at` | `SET created_at = ?` | arbitrary column write |
| `model_type = 'holt'` | `SET model_type = 'holt' = ?` | stored `0` |
| **`model_type = (SELECT password_hash FROM users LIMIT 1) = 'SECRET'`** | `SET model_type = (SELECT …) = 'SECRET' = ?` | **stored `1`** |
| same, `= 'WRONG'` | as above | **stored `0`** |

That is a **blind boolean oracle**. `GET /api/forecasts/models/:itemId` runs
`SELECT *`, so the stored bit is readable. Any user holding only
`forecasts:create` could extract `users.password_hash` — or any other table's
contents — one string comparison at a time.

Two payload shapes were *rejected*, and the report should say so:
`WHERE 1=1 --` and a `--` truncation both fail on parameter arity, and
`better-sqlite3.prepare()` refuses stacked statements. So this was a read
oracle, not a drop-table primitive.

## Defence in depth, both layers

Schema alone is insufficient — any non-HTTP caller bypasses it. Both are fixed:

1. `.strict()` schema, so an unknown field is a 400 rather than a silent write.
2. A hardcoded allowlist in the service, so a bypassed schema still cannot name
   a column.

## SEC-002 scope — measured, not assumed

Seven `z.object({}).passthrough()` schemas remain, bound to ~48 routes
(`inventory.ts` 7, `purchaseOrders.ts` 4, `customReports.ts` 4, and so on). I
checked whether any other site reaches a key-splice sink:

- `models/Settings.ts:147` — iterates a hardcoded `keys.others` map, values
  bound. **Safe.**
- `services/entityRegistry.ts` — a hardcoded `ENTITY_REGISTRY`. **Safe.**
- `createSeasonalEvent` — explicit column list in the INSERT. **Safe.**

So `modelConfig` was the only injection sink. Rather than rewrite 48 schemas
speculatively, this change pins the remaining seven in a test inventory and adds
a structural scan, so the next instance fails a test instead of shipping.

## Anti-vacuity, both directions

| state | forecastConfigInjection | sqlKeyInjectionGuard |
|---|---|---|
| both fixes reverted | **4 of 5 fail** | **2 of 4 fail**, naming `forecastService.ts:1192` and `:1199` |
| both fixes applied | 5 pass | 4 pass |

The structural guard was verified to *fire*: reintroducing the original
implementation makes it report the offending file and line, so it is a real
detector rather than a restatement of the fix.

## Out of scope

- Rewriting the seven remaining passthrough schemas. Each handler filters
  explicitly today; changing 48 route bindings blind is riskier than the
  measured benefit. Tracked as the residue of SEC-002.
- `CODE-005` (a shared typed invoice-item schema) closes SALES-002, -003, -009,
  -012, -018 and -019. It is the same *instinct* applied to the invoice path and
  is listed separately in the coverage ledger under this change.

## Risk and rollback

Low. The allowlist makes previously-writable-but-unintended columns
(`created_at`, `updated_at`, `id`) unwritable, which is the intent. Clients that
legitimately set them would now receive 400; no such caller was found —
`getModelConfig` is the only reader.

Rollback: revert two files. No migration, no schema change, no data change.
