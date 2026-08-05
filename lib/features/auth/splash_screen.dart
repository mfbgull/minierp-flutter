import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Boot screen shown while `AuthNotifier.restoreSession()` runs (GET
/// /auth/me with the stored token) — PORTING.md §3. The router redirects
/// away from here the moment the session state resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text('MiniERP', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              l10n.splashLoading,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
