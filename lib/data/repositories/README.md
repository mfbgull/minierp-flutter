# Repositories

One repository per module, typed against `docs/API.md` (PORTING.md §2).
They wrap the shared `dio` client (`core/api/api_client.dart`) via
`RepositoryClient` and return `ApiResult<T>` (sealed: `ApiSuccess` with
`data`, or `ApiFailure` with a structured `ApiError`).

## Shared machinery

| File | Purpose |
|---|---|
| `api_result.dart` | Sealed `ApiResult<T>` / `ApiSuccess<T>` / `ApiFailure<T>` / `ApiError` (message, `statusCode`, `isNetwork`). `fold`/`map`/`requireData` helpers. |
| `paged_request.dart` | `PagedRequest` (page/limit/search/sortBy/sortOrder + endpoint `extra`) → query map; `PagedResponse<T>` with the server `pagination` block. |
| `repository_client.dart` | Typed envelope-aware wrapper over Dio. |

`RepositoryClient` understands the server's **three response variants**
(verified against the controllers — do not assume a uniform envelope):

| Variant | Example endpoints | Client method |
|---|---|---|
| Enveloped `{success, data}` | `GET /customers/:id`, balance, ledger | `get` / `getList` |
| Enveloped + `pagination` block | `GET /customers`, payments | `getPaged` |
| Bare object (no envelope) | item detail/create/update, `GET /invoices/:id` | `getRaw` / `postRaw` / `putRaw` |
| Bare array | `items-categories`, `items-uom` | `getRawList` |
| Enveloped, no data | deletes (`{success, message}`) | `delete` |

Failures reuse `core/utils/error_mapper.dart` (`mapError`) so 4xx/5xx
`{error}` bodies surface the server's message; transport failures are
flagged `isNetwork` (the UI can toast "server not reachable").
Malformed payloads (non-map rows, `data: null` on a typed get) are
caught by `_tryParse` and returned as `ApiFailure` — never an uncaught
`TypeError`. Note that failures on **bare** endpoints (e.g. a 404
`{error: 'Item not found'}` on `getRaw`) arrive as `DioException` and are
mapped by the same `_toError` path — don't reach for envelope unwrapping
on `getRaw`/`postRaw` calls.

## Ported

| Module | File | Endpoints |
|---|---|---|
| Customers | `customer_repository.dart` (+ `CustomerBalance` DTO) | list (paged), get, create, update, delete, ledger, balance |
| Inventory (items) | `inventory_repository.dart` | items (filtered list), item, create, update, delete, categories, uom, low-stock |

Riverpod providers (`customerRepositoryProvider`,
`inventoryRepositoryProvider`) wrap `dioProvider`.

## Port notes / deferred

- `POST /customers` auto-generates `customer_code` server-side; bodies
  use snake_case API keys. `PagedRequest.extra` carries endpoint-specific
  filters (`status` for customers, etc.).
- Item detail returns `stock_by_warehouse` — the `StockByWarehouse` model
  is on the models "still to port" list; `Item.fromJson` tolerantly
  ignores the key until then.
- Customer statement (`GET /customers/:id/statement`) needs a statement
  DTO (period/opening/closing/transactions) — deferred with the customer
  detail screen.
- Remaining modules (suppliers, invoices, payments, purchase orders,
  production, reports, settings…) follow the same pattern once their
  models are ported.
