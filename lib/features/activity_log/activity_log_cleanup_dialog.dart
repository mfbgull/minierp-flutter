// Admin cleanup dialog — the last documented activity-log endpoint
// (`POST /activity-logs/cleanup`, API.md §Activity Logs, admin only).
//
// Deliberately a dedicated dialog rather than the shared confirm dialog:
// cleanup needs a retention-period number input, which showConfirmDialog
// (text-only) can't carry. The dialog owns the post + toast + invalidation
// so the toolbar button stays a one-liner; the confirm button is styled
// destructive because the delete is permanent.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/activity_log_repository.dart'
    show activityLogRepositoryProvider;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import 'activity_log_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the cleanup dialog (admin users only — the caller gates the
/// button on `auth.user.isAdmin`).
Future<void> showActivityLogCleanupDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _CleanupDialog(),
  );
}

class _CleanupDialog extends ConsumerStatefulWidget {
  const _CleanupDialog();

  @override
  ConsumerState<_CleanupDialog> createState() => _CleanupDialogState();
}

class _CleanupDialogState extends ConsumerState<_CleanupDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _daysController = TextEditingController(
    text: '90',
  );
  bool _busy = false;

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final days = int.parse(_daysController.text.trim());

    setState(() => _busy = true);
    final result = await ref
        .read(activityLogRepositoryProvider)
        .cleanup(days: days);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        ref.invalidate(activityLogsProvider);
        ref.invalidate(activityStatsProvider);
        showAppToast(context, l10n.activitylogCleanupsuccess(data));
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() => _busy = false);
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.activitylogCleanuptitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.activitylogCleanupdesc,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _daysController,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.activitylogCleanupdays,
                border: OutlineInputBorder(
                  borderRadius: AppBorderRadius.smRadius,
                ),
                isDense: true,
              ),
              validator: (value) {
                final days = int.tryParse(value?.trim() ?? '');
                if (days == null || days < 1) {
                  return l10n.activitylogCleanupinvalid;
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.activitylogCleanup),
        ),
      ],
    );
  }
}
