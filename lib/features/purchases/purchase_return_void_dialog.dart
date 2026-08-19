// Void-return dialog — the confirmation step of the returns grid's Void
// action (§8.4). Explains the full reversal (stock + GL + supplier credit
// note), collects an optional reason, then posts
// `POST /purchase-returns/:id/void`. On success the returns grid + CSV
// list invalidate and the row shows the VOIDED badge; the server rejects
// (400) any return that is not POSTED.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase_return.dart' show PurchaseReturn;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart'
    show ErrorBanner, formInputDecoration, submitOnEnter;
import 'purchase_return_providers.dart'
    show filteredPurchaseReturnsProvider, purchaseReturnsProvider;

/// Opens the void-confirmation dialog for [purchaseReturn].
Future<void> showVoidReturnDialog(
  BuildContext context, {
  required PurchaseReturn purchaseReturn,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _VoidReturnDialog(purchaseReturn: purchaseReturn),
  );
}

class _VoidReturnDialog extends ConsumerStatefulWidget {
  const _VoidReturnDialog({required this.purchaseReturn});

  final PurchaseReturn purchaseReturn;

  @override
  ConsumerState<_VoidReturnDialog> createState() => _VoidReturnDialogState();
}

class _VoidReturnDialogState extends ConsumerState<_VoidReturnDialog> {
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref.read(purchaseRepositoryProvider).voidReturn(
      widget.purchaseReturn.id,
      reason: _reasonController.text.trim(),
    );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(purchaseReturnsProvider);
        ref.invalidate(filteredPurchaseReturnsProvider);
        showAppToast(context, l10n.purchasesReturnvoided);
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final purchaseReturn = widget.purchaseReturn;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.purchasesVoidreturn,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                '${purchaseReturn.returnNo} · '
                '${l10n.purchasesReturnvalue}: '
                '${Formatters.currency(purchaseReturn.totalAmount)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.purchasesVoidreturnsure,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 12),
              FormFieldShell(
                label: l10n.purchasesVoidreason,
                child: TextField(
                  controller: _reasonController,
                  enabled: !_submitting,
                  onSubmitted: submitOnEnter(_submit),
                  decoration: formInputDecoration(
                    hintText: l10n.purchasesVoidreasonplaceholder,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.block, size: 18),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    label: Text(l10n.purchasesVoid),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
