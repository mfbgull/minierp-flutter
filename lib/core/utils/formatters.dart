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

  /// Compact range text for the date-picker pill (reference §2.1, en-dashes
  /// exactly like the web prototype — `to` must be `>= from`):
  ///
  /// - same day        → `Aug 13, 2026`
  /// - same month/year → `Aug 7–13, 2026`
  /// - same year       → `Aug 7 – Sep 13, 2026`
  /// - different years → `Aug 7, 2026 – Sep 13, 2027`
  static String compactRange(DateTime from, DateTime to, {String locale = 'en'}) {
    const enDash = '\u2013';
    if (from.year == to.year && from.month == to.month && from.day == to.day) {
      return DateFormat.yMMMd(locale).format(from);
    }
    if (from.year == to.year && from.month == to.month) {
      return '${DateFormat('MMM', locale).format(from)} '
          '${from.day}$enDash${to.day}, ${from.year}';
    }
    if (from.year == to.year) {
      return '${DateFormat('MMM d', locale).format(from)} $enDash '
          '${DateFormat('MMM d, y', locale).format(to)}';
    }
    return '${DateFormat('MMM d, y', locale).format(from)} $enDash '
        '${DateFormat('MMM d, y', locale).format(to)}';
  }

  /// "2026-08-03T10:30:00" → "Aug 3, 2026 10:30 AM".
  static String dateTime(DateTime value, {String locale = 'en'}) {
    return DateFormat.yMMMd(locale).add_jm().format(value);
  }

  /// 1234 → "1,234".
  /// Compact byte size — e.g. `1.2 MB` / `450 KB` (used by the
  /// employee-document upload dialog's picked-file label).
  static String bytes(num value) {
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (value >= 1024) {
      return '${(value / 1024).toStringAsFixed(0)} KB';
    }
    return '$value B';
  }

  static String number(num value, {String locale = 'en'}) {
    return NumberFormat.decimalPattern(locale).format(value);
  }
}
