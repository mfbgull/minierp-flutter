// Void a refund receipt (`POST /supplier-refunds/:id/void`). A void reverses
// the cash receipt, so it is refused with 409 when the cash or bank day would
// go negative; the blocking journal lines arrive as [ApiError.cashBlockers]
// and are listed so the user knows what to reverse first.
//
// Opened from the refund-claim receipts list
// (features/purchases/refund_claim_receipts_dialog.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart';
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/cash_blockers_list.dart';
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart' show ErrorBanner, formInputDecoration;

/// Opens the void dialog for refund receipt [refundId]. Returns true when the
/// void posted.
Future<bool> showVoidRefundDialog(
  BuildContext context, {
  required int refundId,
  required String label,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (dialogContext) =>
        _VoidRefundDialog(refundId: refundId, label: label),
  );
  return done ?? false;
}

class _VoidRefundDialog extends ConsumerStatefulWidget {
  const _VoidRefundDialog({required this.refundId, required this.label});

  final int refundId;

  /// What the receipt is called on screen (number + supplier), shown so the
  /// user voids the right one.
  final String label;

  @override
  ConsumerState<_VoidRefundDialog> createState() => _VoidRefundDialogState();
}

class _VoidRefundDialogState extends ConsumerState<_VoidRefundDialog> {
  final _reasonController = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Set when the guard refuses the void — rendered as a row list, not a
  /// plain message.
  List<CashBlocker> _blockers = const [];

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = l10n.cashInvalidReason);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _blockers = const [];
    });

    final result = await ref
        .read(purchaseRepositoryProvider)
        .voidRefund(widget.refundId, reason: reason);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.purchasesReturnvoided);
        Navigator.of(context).pop(true);
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
          _blockers = error.cashBlockers;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.purchasesVoid),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.label),
            if (_error != null) ...[
              const SizedBox(height: 10),
              ErrorBanner(message: _error!),
            ],
            if (_blockers.isNotEmpty) ...[
              const SizedBox(height: 10),
              CashBlockersList(blockers: _blockers),
            ],
            const SizedBox(height: 12),
            FormFieldShell(
              label: l10n.purchasesVoidreason,
              required: true,
              child: TextField(
                controller: _reasonController,
                enabled: !_busy,
                maxLines: 2,
                onSubmitted: (_) => _submit(),
                decoration: formInputDecoration(
                  hintText: l10n.purchasesVoidreasonplaceholder,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.undo, size: 18),
          label: Text(l10n.purchasesVoid),
        ),
      ],
    );
  }
}
