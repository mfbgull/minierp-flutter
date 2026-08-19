import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/auth_repository.dart'
    show authRepositoryProvider;
import '../../l10n/app_localizations.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Change-password screen — completes the auth module (PORTING.md §3).
///
/// POST /auth/change-password (rate-limited 3/hour). A 401 from this
/// endpoint means "wrong current password", NOT an expired session — the
/// dio interceptor leaves the session alone for this path, so the user
/// stays logged in after a failed attempt.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(authRepositoryProvider)
        .changePassword(
          currentPassword: _current.text,
          newPassword: _newPassword.text,
        );
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.changePasswordSuccess)));
        // go('/') rather than pop(): the screen is deep-linkable (the auth
        // redirect permits it), so pop() on the initial route would leave a
        // blank navigator. Session stays valid either way.
        context.go('/');
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = _messageFor(error);
        });
    }
  }

  String _messageFor(ApiError error) {
    final l10n = AppLocalizations.of(context)!;
    if (error.isNetwork) return l10n.loginServerUnreachable;
    if (error.statusCode == 401) return l10n.changePasswordWrongCurrent;
    return error.message; // 400/429/500 — the server's own message
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.changePasswordTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.key_outlined, size: 48, color: scheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        l10n.changePasswordTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      _passwordField(
                        controller: _current,
                        label: l10n.changePasswordCurrent,
                        visible: _showCurrent,
                        onToggle: () =>
                            setState(() => _showCurrent = !_showCurrent),
                        validator: (value) => (value == null || value.isEmpty)
                            ? l10n.commonRequired
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _passwordField(
                        controller: _newPassword,
                        label: l10n.changePasswordNew,
                        visible: _showNew,
                        onToggle: () => setState(() => _showNew = !_showNew),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.commonRequired;
                          }
                          if (value.length < 6) {
                            return l10n.changePasswordTooShort;
                          }
                          if (value == _current.text) {
                            return l10n.changePasswordSameAsCurrent;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _passwordField(
                        controller: _confirm,
                        label: l10n.changePasswordConfirm,
                        visible: _showConfirm,
                        onToggle: () =>
                            setState(() => _showConfirm = !_showConfirm),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.commonRequired;
                          }
                          if (value != _newPassword.text) {
                            return l10n.changePasswordMismatch;
                          }
                          return null;
                        },
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_reset),
                        label: Text(
                          _busy
                              ? l10n.changePasswordUpdating
                              : l10n.changePasswordButton,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    ValueChanged<String>? onSubmitted,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return TextFormField(
      controller: controller,
      enabled: !_busy,
      obscureText: !visible,
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: visible ? l10n.commonHide : l10n.commonShow,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
      onFieldSubmitted: onSubmitted,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: AppBorderRadius.smRadius,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
