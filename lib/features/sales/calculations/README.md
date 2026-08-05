# Sales calculations

1:1 Dart ports of the kit's `calculations/` modules (PORTING.md §7), with
the `.test.ts` cases ported to `test/calculations/`.

| Kit file | Dart file |
|---|---|
| `invoiceCalculations.ts` | `invoice_calculations.dart` |
| `invoiceLineCalc.ts` | `invoice_line_calc.dart` |
| `invoiceV2Calculations.ts` | `invoice_v2_calculations.dart` |
| `invoiceRules.ts` | `invoice_rules.dart` |
| `quotationCalculations.ts` | `quotation_calculations.dart` |
| `salesOrderCalculations.ts` | `sales_order_calculations.dart` |

All functions are pure — no UI, state, or theme imports.

## Port decisions

- **Typed against `CalculableLine` instead of casts.** The TS V2 module
  re-exports the shared math via `as unknown as InvoiceFormItem` casts.
  In Dart both `InvoiceFormItem` and `InvoiceV2FormItem` implement the
  `CalculableLine` interface (`../models/sales_forms.dart`), so the
  aggregate math accepts either line type type-safely. `invoice_v2_calculations.dart`
  is just a re-export + the V2 default-state factories.
- **Results are structural records** (`({quantity, amount, error?})`,
  `LineFieldPatch`), giving value equality in tests for free.
- **`filterFilledItems` is shared** (defined once in
  `../models/sales_forms.dart` via the `FillableLine` interface) instead
  of being duplicated in `invoiceRules.ts` and `quotationCalculations.ts`.
- **Item ids normalized to `String`.** TS form lines use
  `item_id: number | string` (`''` for invoice/SO rows, `0` for quotation
  rows). Dart uses `''` for all fresh rows — same falsy semantics for
  `filterFilledItems`, since the calculations never branch on the id type.
- **`getStatusColor` (statusColors.ts) is NOT ported.** It returns CSS
  class strings for AG-Grid cells; the Flutter equivalent is the
  `StatusBadge` widget (`widgets/status_badge.dart`). Same for
  `getInvoiceStatusBadgeClass` in `invoice_rules.ts`.
- **`canDeleteInvoice` / `canCancelInvoice` operate on the server
  `Invoice` model** (data layer), matching the TS call sites which pass
  server invoice rows (with `returned_amount`), not the form state.
- **`preparePaymentData`** returns `List<Map<String, dynamic>>` — the
  exact body shape `POST /payments` expects (snake_case + nested
  `invoice_allocations`).
- **Rounding**: `roundToStep`/`_round2` replicate JS `toFixed`/`parseFloat`
  via `toStringAsFixed`/`double.parse`. Note `double.round()` rounds
  half away from zero (JS `Math.round` rounds `-2.5` to `-2`) — irrelevant
  for positive prices/quantities, relevant if negative lines ever appear.
- **`num` returns (not `double`).** TS functions always return `number`;
  Dart returns `num` (int when inputs are ints, e.g. `2 * 50` → `100`).
  This is deliberate — the data models store `num` — but the V2-grid
  port will need `.toDouble()` at the PlutoGrid cell boundary.
- Shared defaults (`flatZeroDiscount`, `isoDate`, `defaultCompany`) live
  in `../models/sales_forms.dart` so the three invoice modules don't
  re-declare them.

## Status colors

See `widgets/status_badge.dart` for the status → color mapping (ported
from `references/utils/statusColors.ts` + `styles/ag-grid-status-cells.css`).
