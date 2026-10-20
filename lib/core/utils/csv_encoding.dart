import 'package:csv/csv.dart';

/// Strips leading spreadsheet-formula characters (`=`, `+`, `-`, `@`)
/// from a user-controlled cell value (CSV/formula-injection hardening).
/// The rest of the value is preserved verbatim — e.g. `=1+1` → `1+1`,
/// `+HYPERLINK(...)` → `HYPERLINK(...)`. Values not starting with a
/// formula character are returned unchanged.
///
/// Tradeoff (deliberate): a user text that *legitimately* starts with a
/// hyphen, e.g. an item name like `-bolts`, also loses its leading `-`.
/// Stripping — rather than quoting/prefixing — is what the product asked
/// for, and hyphens at the start of doc numbers/names are not a real
/// pattern in this domain; the alternative (prefixing a `'`) would be
/// the choice if that ever becomes a concern.
String sanitizeCsvCell(String value) {
  var start = 0;
  while (start < value.length) {
    final c = value.codeUnitAt(start);
    if (c == 0x3D /* = */ ||
        c == 0x2B /* + */ ||
        c == 0x2D /* - */ ||
        c == 0x40 /* @ */ ) {
      start++;
    } else {
      break;
    }
  }
  return start == 0 ? value : value.substring(start);
}

/// Parameterized grid-style CSV builder shared by every export: emits
/// [headers] followed by one row per [items] entry, mapped by [rowFor].
/// The per-record mapping keeps each builder's type-specific cell
/// logic; the header-row + encode tail is shared here.
String buildGridCsv<T>(
  List<String> headers,
  List<T> items,
  List<dynamic> Function(T) rowFor,
) => Csv().encode([headers, for (final item in items) rowFor(item)]);
