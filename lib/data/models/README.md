# Models

Dart models ported from the kit's `types/` (PORTING.md §4) and cross-checked
against the **server models** (`server/src/models/*.ts`) and the **live server**
(`test/live_fixtures_test.dart` parses real API payloads from
`test/fixtures/*.json`). One class per interface with `fromJson`/`toJson`;
field names match the API JSON keys exactly.

## Live-validated facts (from the bundled erp.db server)

- List endpoints wrap rows in `{success: true, data: [...]}`; **`GET
  /api/invoices/:id` returns the bare object** (no envelope). Repositories
  must unwrap list envelopes and pass bare detail objects straight to
  `fromJson`.
- `Item` rows carry `rack_no`; `Invoice` rows/detail carry `returned_amount`
  and `return_fee` (both models include them).
- Invoice detail adds `customer_email` / `customer_phone` /
  `customer_address`; `customer_current_balance` / `so_no` /
  `quotation_no` / `created_by_username` appear only when populated (absent
  keys parse to null).
- `is_active` etc. arrive as `1`/`0` ints — the tolerant parsers handle it.

To refresh fixtures against a running server, see the header comment in
`test/live_fixtures_test.dart`.

## Ported (data layer)

| Kit source + server model | Dart file |
|---|---|
| `Customer` | `customer.dart` |
| `Item` + `SaleType` | `item.dart` |
| `Invoice` (superset of server Invoice) | `invoice.dart` |
| `Supplier` | `supplier.dart` |
| `LedgerEntry` (customer AR ledger row) | `ledger_entry.dart` |
| `Payment` (superset of server Payment) | `payment.dart` |
| shared tolerant parsers | `json_helpers.dart` |

`json_helpers.dart` normalises SQLite quirks: `is_active` arrives as `1`/`0`
ints or booleans; ids can be `number | string`. All models parse both.

## Port decisions

- **`InvoiceItem`** (in `invoice.dart`) is the **server response shape**
  (`item_code, unit_price, amount, tax_rate, discount_type,
  discount_value, returned_qty`). The client *form-shape* `InvoiceItem`
  (`description, rate, tax, discount: {type, value}`) is form-state and
  gets ported with the sales feature — do not confuse the two.
- **`Invoice.status` is a `String`** (verbatim `status: string`); use
  `InvoiceStatus.tryParse` for enum semantics.
- **Money/quantities are `num`** (TS `number`); dates stay `YYYY-MM-DD`
  strings — display formatting lives in `core/utils/formatters.dart`.
- `toJson` omits null optionals (server uses `COALESCE` on update and
  `|| ''` defaults on create, so absent keys are safe).
- **Do NOT serialize `Invoice` directly as a create payload.** The nested
  `discount`/`company`/`payment`/`paymentMethods` objects are client-form
  fidelity only; the server create DTO takes flat `discount_scope` /
  `discount_type` / `discount_value`. Repositories build create bodies
  explicitly.
- **No `copyWith`/`==` yet** — added with the sales/invoice form port,
  where the mutation surface is known. Note this includes `Discount`
  (shared data-model class used by the form state): the form port must
  add `copyWith` to it, which crosses the data layer. Unknown status
  strings already return `null` from `InvoiceStatus.tryParse`; the UI
  layer must render a fallback (grey) badge.
- **Form ids are normalized to `String`** (`customerId`, `itemId`). The
  create DTOs (`POST /invoices`, `POST /payments`) want numeric
  `customer_id`/`item_id` — repositories convert with `int.tryParse`
  when building bodies.

## Still to port

`Warehouse`, `BOM`, `Quotation` (+ items), `SalesOrder` (+
items), `Production`/`ProductionRecord`, `Purchase`, `PurchaseOrder` (+
items), `Employee`, `Expense`, `StockMovement`, `StockByWarehouse`,
`User`, `Role`, `Permission`, `TaxRate`, `Activity`,
report result shapes (from `server-reference/Reports.ts`), dashboard
summaries, the `Payment` allocation arrays (server returns grouped
`allocated_*` strings + an `allocations` array — deferred to the
payments feature), and the form-state types (in
`features/sales/models/sales_forms.dart`, see below).

## Form-state models (features layer)

`features/sales/models/sales_forms.dart` holds the **client form shapes**
used by the sales calculations (PORTING.md §7): `InvoiceFormItem`,
`InvoiceFormState`, `QuotationFormItem`, `SOFormItem`, `InvoiceV2*`,
`DiscountScope`, `EditedField`, and the `CalculableLine`/`FillableLine`
interfaces. They are not wire models (no `fromJson`/`toJson`); they reuse
`Discount`/`DiscountType`/`PaymentMethod`/`CompanyInfo`/`SaleType` from
the data models.
