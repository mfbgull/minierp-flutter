// Shared full-pane error state for the detail/ledger dialogs — shown when
// the dialog's fetch fails, with a retry that re-runs the provider. Used by
// the item detail, customer detail, and customer ledger dialogs (AGENTS.md
// self-audit: duplicated_logic == false).

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class DetailError extends StatelessWidget {
  const DetailError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 420,
      height: 240,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 36, color: scheme.outline),
            const SizedBox(height: 10),
            Text(message,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.commonRefresh),
            ),
          ],
        ),
      ),
    );
  }
}
