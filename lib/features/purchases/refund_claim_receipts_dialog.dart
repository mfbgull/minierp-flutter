// BUG-008 — the receipts behind a refund claim. A claim row opens this list
// so the user can see what settled it and void a receipt that was wrong.
//
// A void reverses the cash receipt (Dr AP / Cr cash), so the server refuses
// it with 409 when the cash or bank day would go negative; the blocking
// journal lines arrive as [ApiError.cashBlockers] and the void dialog lists
// them. Void needs the `supplier_refunds.void` permission — the button is
// hidden without it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/paged_request.dart';
import '../../data/repositories/purchase_repository.dart'
    show
        RefundClaim,
        SupplierRefundReceipt,
        purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/form_helpers.dart' show ErrorBanner;
import '../../widgets/status_badge.dart';
import 'void_refund_dialog.dart';

/// Opens the receipt list for [claim]. Returns true when at least one void
/// posted, so the caller can refresh the claim.
Future<bool> showRefundClaimReceiptsDialog(
  BuildContext context, {
  required RefundClaim claim,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _RefundClaimReceiptsDialog(claim: claim),
  );
  return changed ?? false;
}

class _RefundClaimReceiptsDialog extends ConsumerStatefulWidget {
  const _RefundClaimReceiptsDialog({required this.claim});

  final RefundClaim claim;

  @override
  ConsumerState<_RefundClaimReceiptsDialog> createState() =>
      _RefundClaimReceiptsDialogState();
}

class _RefundClaimReceiptsDialogState
    extends ConsumerState<_RefundClaimReceiptsDialog> {
  late Future<ApiResult<PagedResponse<SupplierRefundReceipt>>> _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ApiResult<PagedResponse<SupplierRefundReceipt>>> _load() => ref
      .read(purchaseRepositoryProvider)
      .refundReceipts(
        const PagedRequest(page: 1, limit: 100),
        claimId: widget.claim.id,
      );

  void _reload() => setState(() => _future = _load());

  Future<void> _void(SupplierRefundReceipt receipt) async {
    final label = '${receipt.refundNo} — ${receipt.supplierName}';
    final done = await showVoidRefundDialog(
      context,
      refundId: receipt.id,
      label: label,
    );
    if (!mounted || !done) return;
    _changed = true;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canVoid =
        ref.watch(authProvider).user?.hasPermission(
          'supplier_refunds',
          'void',
        ) ??
        false;

    return AlertDialog(
      title: Text(l10n.refundClaimReceiptsTitle),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<ApiResult<PagedResponse<SupplierRefundReceipt>>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final result = snapshot.data!;
            switch (result) {
              case ApiFailure(:final error):
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ErrorBanner(message: error.message),
                    TextButton(
                      onPressed: _reload,
                      child: Text(l10n.commonRetry),
                    ),
                  ],
                );
              case ApiSuccess(:final data):
                if (data.items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.refundClaimNoReceipts),
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final receipt in data.items)
                        _ReceiptRow(
                          receipt: receipt,
                          canVoid: canVoid,
                          onVoid: () => _void(receipt),
                        ),
                    ],
                  ),
                );
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_changed),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.receipt,
    required this.canVoid,
    required this.onVoid,
  });

  final SupplierRefundReceipt receipt;
  final bool canVoid;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ListTile(
      title: Text(receipt.refundNo),
      subtitle: Text(
        '${Formatters.date(receipt.refundDate)} — '
        '${Formatters.currency(receipt.amount)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(
            status: receipt.isPosted
                ? l10n.refundClaimReceiptStatusPOSTED
                : l10n.refundClaimReceiptStatusVOIDED,
            color: receipt.isPosted
                ? Colors.green.shade600
                : theme.colorScheme.outline,
          ),
          if (canVoid && receipt.isPosted)
            IconButton(
              tooltip: l10n.refundClaimVoidReceipt,
              onPressed: onVoid,
              icon: const Icon(Icons.undo),
            ),
        ],
      ),
    );
  }
}
