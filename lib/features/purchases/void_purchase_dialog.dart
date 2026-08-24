// Void-purchase dialog — the row-menu Void action of the purchases grid
// (financial-audit-p0-remediation task 3.5). Purchases are voided, never
// hard-deleted (PUR-03): explains the reversal, requires a non-empty
// reason, then posts `POST /purchases/:id/void`. The server rejects (400)
// when stock was already sold/returned or payments exist against it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart'
    show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart'
    show ErrorBanner, formInputDecoration;

/// Opens the void-confirmation dialog for purchase [id].
Future<void> showVoidPurchaseDialog(
  BuildContext context, {
  required int id,
  required String purchaseNo,
  required VoidCallback onVoided,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _VoidPurchaseDialog(id: id, purchaseNo: purchaseNo, onVoided: onVoided),
  );
}

class _VoidPurchaseDialog extends ConsumerStatefulWidget {
  const _VoidPurchaseDialog({
    required this.id,
    required this.purchaseNo,
    required this.onVoided,
  });

  final int id;
  final String purchaseNo;
  final VoidCallback onVoided;

  @override
  ConsumerState<_VoidPurchaseDialog> createState() =>
      _VoidPurchaseDialogState();
}

class _VoidPurchaseDialogState extends ConsumerState<_VoidPurchaseDialog> {
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'A void reason is required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(purchaseRepositoryProvider)
        .voidPurchase(widget.id, reason: reason);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        widget.onVoided();
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
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.purchasesVoid,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                widget.purchaseNo,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        // PUR-03: the void reverses ledger + GL and removes
                        // only unsold remaining stock; the record is kept.
                        'Reverses the supplier balance and GL entry. Stock '
                        'already sold blocks this action.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FormFieldShell(
                label: l10n.purchasesVoidreason,
                required: true,
                child: TextField(
                  controller: _reasonController,
                  maxLines: 2,
                  autofocus: true,
                  decoration: formInputDecoration(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _submitting ? null : _submit,
                    icon: const Icon(Icons.block_outlined, size: 16),
                    label: Text(_submitting
                        ? l10n.commonLoading
                        : l10n.purchasesVoid),
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
