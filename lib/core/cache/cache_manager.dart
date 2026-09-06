// Offline cache for read-heavy data (SHORTCOMINGS-FIX 4.1). Backed by
// `shared_preferences` with a per-entry TTL, so a killed server still
// leaves the last-known inventory/customers/dashboard data available
// until the cache expires.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple TTL key-value cache over `shared_preferences`.
///
/// Keys are namespaced with [keyPrefix] (default `offline_cache/`) so
/// unrelated preferences never collide. `invalidate` treats its argument
/// as a prefix — `invalidate('inventory/items')` drops every entry under
/// that path, which is what the repository client needs after a write.
class CacheManager {
  CacheManager({this.keyPrefix = 'offline_cache/'});

  final String keyPrefix;

  static const _expirySuffix = '.exp';

  /// Writes [json] under [key] with a [ttl]; expired entries behave as
  /// missing (and are pruned on read).
  Future<void> put(
    String key,
    String json, {
    Duration ttl = const Duration(minutes: 5),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = DateTime.now().add(ttl).millisecondsSinceEpoch;
    await prefs.setString('$keyPrefix$key', json);
    await prefs.setInt('$keyPrefix$key$_expirySuffix', expiresAt);
  }

  /// Returns the stored JSON, or null when absent/expired.
  Future<String?> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$keyPrefix$key');
    if (raw == null) return null;
    final expiresAt = prefs.getInt('$keyPrefix$key$_expirySuffix');
    if (expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt) {
      await invalidate(key);
      return null;
    }
    return raw;
  }

  /// Removes every entry whose key starts with [keyPrefixArg] (a path
  /// prefix). Used after writes to drop the affected read caches.
  Future<void> invalidate(String keyPrefixArg) async {
    final prefs = await SharedPreferences.getInstance();
    final doomed = prefs
        .getKeys()
        .where((k) => k.startsWith('$keyPrefix$keyPrefixArg'))
        .toList();
    for (final key in doomed) {
      await prefs.remove(key);
    }
  }

  /// Drops every cached entry.
  Future<void> invalidateAll() async {
    final prefs = await SharedPreferences.getInstance();
    final doomed = prefs
        .getKeys()
        .where((k) => k.startsWith(keyPrefix))
        .toList();
    for (final key in doomed) {
      await prefs.remove(key);
    }
  }
}

/// Single shared [CacheManager] for the offline-cache layer.
final cacheManagerProvider = Provider<CacheManager>((ref) => CacheManager());