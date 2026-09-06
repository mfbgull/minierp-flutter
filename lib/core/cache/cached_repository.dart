// Offline cache decorator (SHORTCOMINGS-FIX 4.1). [CachedRepositoryClient]
// wraps the shared [RepositoryClient] with a [CacheManager] so read-heavy
// endpoints (items, customers, dashboard) keep serving last-known data
// while the server is unreachable. Cache keys are the raw `path?query`
// strings, so a write to `/customers` (or `/customers/5`) invalidates the
// whole list.

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../data/repositories/repository_client.dart' show RepositoryClient;
import 'cache_manager.dart' show CacheManager, cacheManagerProvider;

/// A [RepositoryClient] with the offline read-cache enabled.
///
/// Construction is cheap (it only wires the shared cache manager into the
/// shared Dio client); repositories that should cache reads use this via
/// [cachedRepositoryClientProvider] instead of [repositoryClientProvider].
class CachedRepositoryClient extends RepositoryClient {
  CachedRepositoryClient(
    super.dio, {
    required CacheManager cache,
    super.cacheTtl = const Duration(minutes: 5),
    super.ttlForPath = const {},
  }) : super(cache: cache);
}

/// Shared cached client for read-heavy repositories. Per-path TTLs mirror
/// the spec: items/customers 5 min, dashboard 2 min (the dashboard
/// endpoints refresh more often so a stale summary doesn't linger).
final cachedRepositoryClientProvider = Provider<CachedRepositoryClient>(
  (ref) => CachedRepositoryClient(
    ref.watch(dioProvider),
    cache: ref.watch(cacheManagerProvider),
    ttlForPath: const {
      '/dashboard/summary': Duration(minutes: 2),
      '/dashboard/kpi': Duration(minutes: 2),
      '/dashboard/top-customers': Duration(minutes: 2),
      '/dashboard/sales-summary': Duration(minutes: 2),
      '/dashboard/expense-summary': Duration(minutes: 2),
      '/dashboard/production-status': Duration(minutes: 2),
      '/dashboard/stock-movement-summary': Duration(minutes: 2),
    },
  ),
);

/// The shared cached client's offline flag as a [ValueNotifier] — UI
/// watches this (via [ValueListenableBuilder]) to show the "Offline"
/// badge while reads are served from cache.
final servingCachedNotifierProvider = Provider<ValueNotifier<bool>>(
  (ref) => ref.watch(cachedRepositoryClientProvider).servingCached,
);