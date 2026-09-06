// Offline-cache indicator (SHORTCOMINGS-FIX 4.1 step 4). Shown in screen
// toolbars while the repository layer is serving last-known data because
// the server is unreachable — a quiet visual cue that rows may be stale.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache/cached_repository.dart'
    show servingCachedNotifierProvider;

/// Renders a compact "Offline" chip while the shared cached client is
/// serving snapshots instead of live responses; collapses to nothing
/// when the server is reachable.
class OfflineCacheBadge extends ConsumerWidget {
  const OfflineCacheBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(servingCachedNotifierProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, isOffline, _) {
        if (!isOffline) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Tooltip(
          message: 'Showing saved data — server unreachable',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 16,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  'Offline',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}