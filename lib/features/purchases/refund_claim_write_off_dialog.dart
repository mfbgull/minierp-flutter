// Write off an uncollected refund claim balance (Dr 7300 Refund Write-offs /
// Cr AP). A reason is mandatory — a silent write-off hides a real loss. Above
// Rs 1,000 the server requires the admin role; this dialog states that up
// front so the user is not surprised by a 403 after typing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/purchase_repository.dart'
    show RefundClaim, purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart' show ErrorBanner, formInputDecoration;

/// Above this amount the server demands the admin role. Kept in step with
/// `CLAIM_WRITE_OFF_APPROVAL_THRESHOLD` in the claim model.
const num kClaimWriteOffAdminThreshold = 1000;

/// Whether writing off [remaining] needs the admin role, and whether
/// [isAdmin] satisfies it. False when the amount is at or below the
/// threshold; the server rounds to currency, so the half-paisa guard matches.
bool writeOffNeedsAdmin(num remaining, {required bool isAdmin}) =>
    remaining > kClaimWriteOffAdminThreshold + 0.005 && !isAdmin;

/// Opens the write-off dialog for [claim]. Returns true when a write-off
/// posted, so the caller can refresh.
Future<bool> showRefundClaimWriteOffDialog(
  BuildContext context, {
  required RefundClaim claim,
  required bool isAdmin,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (dialogContext) =>
        _WriteOffDialog(claim: claim, isAdmin: isAdmin),
  );
  return done ?? false;
}

class _WriteOffDialog extends ConsumerStatefulWidget {
  const _WriteOffDialog({required this.claim, required this.isAdmin});

  final RefundClaim claim;
  final bool isAdmin;

  @override
  ConsumerState<_WriteOffDialog> createState() => _WriteOffDialogState();
}

class _WriteOffDialogState extends ConsumerState<_WriteOffDialog> {
  final _reasonController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _needsAdmin => writeOffNeedsAdmin(
    widget.claim.remaining,
    isAdmin: widget.isAdmin,
  );

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = l10n.refundClaimWriteOffReasonRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(purchaseRepositoryProvider)
        .writeOffClaim(widget.claim.id, reason: reason);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        showAppToast(
          context,
          '${l10n.refundClaimWriteOff} — '
          '${Formatters.currency(widget.claim.remaining)}',
        );
        Navigator.of(context).pop(true);
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // A non-admin cannot write off above the threshold, so the action is
    // disabled with the rule stated rather than failing after submit.
    final blocked = _needsAdmin;

    return AlertDialog(
      title: Text(l10n.refundClaimWriteOffTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.claim.claimNo} · ${widget.claim.supplierName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              l10n.refundClaimRemaining(
                Formatters.currency(widget.claim.remaining),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (blocked) ...[
              const SizedBox(height: 10),
              ErrorBanner(message: l10n.refundClaimWriteOffAdminOnly),
            ] else if (_error != null) ...[
              const SizedBox(height: 10),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 12),
            FormFieldShell(
              label: l10n.refundClaimWriteOffReason,
              required: true,
              child: TextField(
                controller: _reasonController,
                enabled: !_busy && !blocked,
                maxLines: 2,
                onSubmitted: (_) => blocked ? null : _submit(),
                decoration: formInputDecoration(),
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
          onPressed: (_busy || blocked) ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.money_off_csred_outlined, size: 18),
          label: Text(l10n.refundClaimWriteOff),
        ),
      ],
    );
  }
}
