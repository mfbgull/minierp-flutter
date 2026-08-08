// Shared full-pane error state for the grid screens — shown when a list
// provider fails (so the grid never renders stale rows), with a retry that
// re-runs the provider. Used by the items, customers, expenses, sales and
// suppliers screens (AGENTS.md self-audit: duplicated_logic == false).

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class ScreenErrorPanel extends StatelessWidget {
  const ScreenErrorPanel({
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
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text(l10n.errorsFailed, style: textTheme.titleSmall),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.commonRefresh),
          ),
        ],
      ),
    );
  }
}
