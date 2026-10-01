import 'dart:convert';
import 'dart:math';

/// Client half of the retry-key contract (audit-3 task 08, decision 8.2).
///
/// A write can time out *after* the server committed. The client cannot tell
/// that apart from a genuine failure, so the safe move is to retry — but only
/// safe if the retry carries the same `Idempotency-Key`, which lets the server
/// replay the original result instead of writing the money twice.
///
/// The key is therefore derived from the exact body being sent: an unchanged
/// retry reuses it, while any edit to the payload rotates it and is treated as
/// a new operation. That is the property the invoice form already relies on,
/// extracted so every keyed write shares one implementation.
///
/// Server scopes this is used with: `payments.customer`, `payments.supplier`,
/// `payments.allocate`, `expenses.create`, `purchases.record`.
class IdempotencyKeyCache {
  IdempotencyKeyCache({this.prefix = 'idem'});

  /// Short namespace prefix, so a key is identifiable in logs and in the
  /// `idempotency_keys` table.
  final String prefix;

  final _random = Random();

  String? _cached;
  String? _cachedBody;

  /// The key for [body], stable across calls while the body is unchanged.
  ///
  /// Compare with [rotate] semantics: a caller that mutates its body between
  /// calls gets a new key, which is what makes a genuine second payment
  /// possible while a plain retry replays.
  String keyFor(Map<String, dynamic> body) {
    final encoded = jsonEncode(body);
    if (_cached == null || _cachedBody != encoded) {
      _cached = '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '-${_random.nextInt(1 << 32).toRadixString(36)}';
      _cachedBody = encoded;
    }
    return _cached!;
  }

  /// Forget the cached key, so the next [keyFor] mints a fresh one. Call this
  /// after a *successful* write: the operation is done, and a later
  /// intentional repeat must not replay the old one.
  void reset() {
    _cached = null;
    _cachedBody = null;
    _byBody.clear();
  }

  final Map<String, String> _byBody = {};

  /// A key that stays stable for [body] even when other bodies are keyed in
  /// between.
  ///
  /// A single-slot [keyFor] is wrong for a loop that posts several payments:
  /// each iteration would rotate the slot, so a retry of the whole loop would
  /// present fresh keys and duplicate every payment except the last. This
  /// keeps one key per distinct body, so re-running the loop replays.
  ///
  /// Bodies are dropped by [reset] once the operation they belong to has
  /// committed, so this cannot grow without bound.
  String stableKeyFor(Map<String, dynamic> body) {
    final encoded = jsonEncode(body);
    return _byBody.putIfAbsent(encoded, () => _mint());
  }

  String _mint() =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_random.nextInt(1 << 32).toRadixString(36)}';
}
