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
- **`formatAsCurrency`** replicates JS `toLocaleString(undefined,
  {min/max 2})` for en-US via `NumberFormat.currency`. It is deliberately
  USD/`$`-fixed (the legacy customer-tab format); shared/currency-aware
  formatting lives in `core/utils/formatters.dart` (the settings-driven
  symbol is applied by the UI layer).
- **`formatDateString`** delegates to `Formatters.date` (the Flutter
  equivalent of `toLocaleDateString()`); unparseable input returns `''`
  like TS.
