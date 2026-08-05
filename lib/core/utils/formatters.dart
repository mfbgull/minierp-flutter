import 'package:intl/intl.dart';

/// Shared value formatters — port of the web app's currency/date utils.
/// Dates travel as `YYYY-MM-DD` strings (PORTING.md §2).
///
/// Note: the customer feature has a legacy USD-fixed `formatAsCurrency`
/// (in `features/customers/calculations/`); prefer this class for new code.
abstract final class Formatters {
  /// 1234.5 → "1,234.50" (no symbol; the UI renders the currency symbol).
  static String currency(num value, {String locale = 'en'}) {
    return NumberFormat.currency(locale: locale, symbol: '').format(value);
  }

  /// "2026-08-03" → "Aug 3, 2026" (locale-aware; Urdu renders RTL).
  static String date(String isoDate, {String locale = 'en'}) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    return DateFormat.yMMMd(locale).format(parsed);
  }

  /// "2026-08-03T10:30:00" → "Aug 3, 2026 10:30 AM".
  static String dateTime(DateTime value, {String locale = 'en'}) {
    return DateFormat.yMMMd(locale).add_jm().format(value);
  }

  /// 1234 → "1,234".
  static String number(num value, {String locale = 'en'}) {
    return NumberFormat.decimalPattern(locale).format(value);
  }
}
