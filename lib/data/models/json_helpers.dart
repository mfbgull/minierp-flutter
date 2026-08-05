/// Tolerant JSON parsing helpers shared by the data models.
///
/// The backend returns SQLite values directly, so one field can arrive as
/// different JSON types across endpoints — e.g. `is_active` as `true`/`false`
/// or `1`/`0`, and ids as numbers or strings (see `types/client-types.ts`
/// `boolean | number` / `number | string` unions). These parsers normalise
/// everything to the model's Dart type instead of crashing on a mismatch.
library;

/// Parses a JSON number (int or double) or a numeric string.
num? asNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

/// Parses an integer id, accepting JSON numbers and numeric strings.
int? asInt(Object? value) => asNum(value)?.toInt();

/// Parses a boolean, accepting JSON booleans, `1`/`0` (SQLite), and
/// `'true'`/`'false'` strings.
bool asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      case 'false':
      case '0':
      case 'no':
        return false;
    }
  }
  return fallback;
}

/// Returns the string value, or null when the key is absent/null.
String? asString(Object? value) => value is String ? value : null;
