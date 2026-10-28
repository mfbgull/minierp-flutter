import 'package:flutter/material.dart';

import '../../core/backend/backend_config.dart';
import '../../l10n/app_localizations.dart';

/// First-launch setup for a packaged install: the administrator password is
/// chosen here and passed to the bundled server only through its process
/// environment. Nothing is written to disk.
class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key, required this.onSubmit});

  final Future<void> Function(String password) onSubmit;

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (_submitting) return;
    if (_password.text != _confirm.text) {
      setState(() => _error = l10n.firstRunPasswordMismatch);
      return;
    }
    final policyError = BackendConfig.passwordPolicyError(_password.text);
    if (policyError != null) {
      setState(() => _error = l10n.firstRunPasswordTooShort);
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await widget.onSubmit(_password.text);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.firstRunTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.firstRunIntro,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofocus: true,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    labelText: l10n.firstRunPassword,
                    helperText: l10n.firstRunPasswordHint,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    labelText: l10n.firstRunConfirmPassword,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.firstRunStart),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
