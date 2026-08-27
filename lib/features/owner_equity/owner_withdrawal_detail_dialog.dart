// Read-only breakdown of a goods withdrawal — the user-entered item lines
// plus the immutable FIFO/FEFO batch-consumption movements (and their
// reversals) fetched from GET /owner-equity/withdrawals/:id.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/owner_equity.dart'
    show OwnerWithdrawalDetail, WithdrawalMovement;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/owner_equity_repository.dart'
    show ownerEquityRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

Future<void> showOwnerWithdrawalDetailDialog(
  BuildContext context,
  int withdrawalId,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _OwnerWithdrawalDetailDialog(withdrawalId: withdrawalId),
  );
}

class _OwnerWithdrawalDetailDialog extends ConsumerStatefulWidget {
  const _OwnerWithdrawalDetailDialog({required this.withdrawalId});

  final int withdrawalId;

  @override
  ConsumerState<_OwnerWithdrawalDetailDialog> createState() =>
      _OwnerWithdrawalDetailDialogState();
}

class _OwnerWithdrawalDetailDialogState
    extends ConsumerState<_OwnerWithdrawalDetailDialog> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final detail = ref.watch(_detailProvider(widget.withdrawalId));

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.equityBreakdownTitle(
                        detail.valueOrNull?.withdrawal.withdrawalNo ?? '',
                      ),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.commonClose,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: detail.when(
                skipLoadingOnReload: true,
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => ScreenErrorPanel(
                  message: error is ApiError
                      ? error.message
                      : l10n.equityExportfailed,
                  onRetry: () =>
                      ref.invalidate(_detailProvider(widget.withdrawalId)),
                ),
                data: (data) => _body(l10n, scheme, data),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    AppLocalizations l10n,
    ColorScheme scheme,
    OwnerWithdrawalDetail data,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.equityItemstaken,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          for (final item in data.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.itemCode ?? ''} ${item.itemName ?? ''}'
                          .trim(),
                    ),
                  ),
                  Text(item.warehouseName ?? ''),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 90,
                    child: Text(
                      '${item.quantity}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (data.items.isEmpty)
            Text('—', style: TextStyle(color: scheme.outline)),
          const Divider(height: 24),
          Text(
            l10n.equityMovements,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: AppBorderRadius.smRadius,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in data.movements) _movementRow(l10n, scheme, m),
                if (data.movements.isEmpty)
                  Text('—', style: TextStyle(color: scheme.outline)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.equityCostatcostnote,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _movementRow(
    AppLocalizations l10n,
    ColorScheme scheme,
    WithdrawalMovement m,
  ) {
    final outbound = m.isOutbound;
    final qty = outbound ? -m.quantity : m.quantity; // display positive
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            outbound ? Icons.call_made : Icons.call_received,
            size: 15,
            color: outbound ? scheme.primary : scheme.tertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${m.movementNo} · ${m.itemName ?? ''}${m.batchNo == null ? '' : ' · ${m.batchNo}'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$qty × ${Formatters.currency(m.unitCost ?? 0)}'),
          const SizedBox(width: 12),
          SizedBox(
            width: 86,
            child: Text(
              outbound ? l10n.equityTakenout : l10n.equityReturned,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: outbound ? scheme.primary : scheme.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// autoDispose family: each open dialog owns its fetch.
final _detailProvider = FutureProvider.autoDispose
    .family<OwnerWithdrawalDetail, int>((ref, id) async {
      final result = await ref
          .watch(ownerEquityRepositoryProvider)
          .withdrawalDetail(id);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
