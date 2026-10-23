import 'package:flutter/material.dart';

import '../../core/theme/app_border_radius.dart';
import '../../l10n/app_localizations.dart';

/// Inline dashboard KPI failure — icon + message + retry, announced to
/// screen readers. Replaces the per-card red dash when the KPI batch fails.
class KpiErrorStrip extends StatelessWidget {
  const KpiErrorStrip({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.errorContainer,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.mdRadius,
          side: BorderSide(color: scheme.error.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n.errorsFailed}: $message',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(l10n.commonRefresh),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
