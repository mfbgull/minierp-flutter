# Customer calculations

1:1 Dart port of `calculations/customerCalculations.ts` (PORTING.md §7) —
customer balance, credit-limit and metrics logic, plus the legacy display
helpers used by the customer Overview/Invoices/Payments tabs.

## Port decisions

- **Consumes the data-layer models**: `Customer`, `Invoice` (data
  models), plus `LedgerEntry` and `Payment`, which were ported as part of
  this work (`data/models/ledger_entry.dart`, `data/models/payment.dart`)
  because the calculations need them and the customer feature will too.
- **`LedgerTotals` is a structural record** `({debit, credit, balance})`
  — value equality in tests for free.
- **`CustomerMetrics` is a plain class** — it's a computed shape, not a
  wire model, so no `fromJson`/`toJson`.
- **Date math matches TS exactly**: day differences use milliseconds
  (`inMilliseconds / (86.4e6)`) so fractional days are preserved before
  the final `.round()`, and `DateTime.parse` on `YYYY-MM-DD` behaves like
  `new Date(...)`.
- **`formatAsCurrency`** delegates to `Formatters.currency`
  (`core/utils/formatters.dart`), which applies the settings-driven
  business symbol. It is kept as a named alias only so the existing
  customer Overview/Invoices/Payments call sites stay unchanged; it is no
  longer a USD/`$`-fixed legacy format.
- **`formatAsFixed`** is the remaining legacy helper: plain 2-decimal
  formatting with no symbol, used for ledger totals.
- **`formatDateString`** delegates to `Formatters.date` (the Flutter
  equivalent of `toLocaleDateString()`); unparseable input returns `''`
  like TS.
