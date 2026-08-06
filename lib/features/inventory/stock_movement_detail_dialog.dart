// Stock movement detail dialog — opened by double-tapping/F2 on a row in
// the stock movements grid (PORTING.md §6). Fetches
// `GET /inventory/stock-movements/:id` (bare joined movement) via
// [stockMovementDetailProvider]; the grid row is passed in so the dialog
// renders instantly and falls back to it while the fetch is in flight or
// fails (the list endpoint returns the same joined shape). The refresh
// button re-runs the detail fetch.
//
// ADJUSTMENT movements get a Reverse action: a compensating `ADJUSTMENT`
// movement with the inverse quantity, linked to the original via
// `reference_docno` (void-by-reversal — the server has no delete/cancel
// endpoint for movements).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/stock_movement.dart' show StockMovement;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_labels.dart' show detailDash, detailSectionLabel;
import '../../widgets/detail_rows.dart' show DetailInfoRows;
import 'inventory_providers.dart'
    show
        movementTypeFilterProvider,
        stockBalancesProvider,
        stockMovementDetailProvider,
        stockMovementsProvider;

/// Opens the detail dialog for [movement] — fresh data is fetched for its
/// id (the autoDispose detail provider refetches on every open).
Future<void> showStockMovementDetailDialog(
  BuildContext context, {
  required StockMovement movement,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _StockMovementDetailDialog(movement: movement),
  );
}

/// "code — name" for joined item/warehouse fields, or the em dash when the
/// name is absent (matches the accounting convention elsewhere).
String _codeName(String? code, String? name) {
  final parts = [
    if (code != null && code.isNotEmpty) code,
    if (name != null && name.isNotEmpty) name,
  ];
  return parts.isEmpty ? '—' : parts.join(' — ');
}

class _StockMovementDetailDialog extends ConsumerWidget {
  const _StockMovementDetailDialog({required this.movement});

  /// The row from the grid — instant title/body fallback while the detail
  /// fetch is in flight (or on failure).
  final StockMovement movement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final detail = ref.watch(stockMovementDetailProvider(movement.id));
    final m = switch (detail) {
      AsyncData(:final value) => value,
      _ => movement,
    };
    // The counterpart is looked up in the unfiltered list (the tab's own
    // filter may have hidden it) — see [_findCounterpart]. This can fetch
    // the full list on demand when the tab was opened under a filter; a
    // failed fetch simply shows no link.
    final allMovements = ref.watch(stockMovementsProvider(null));
    final linked = switch (allMovements) {
      AsyncData(:final value) => _findCounterpart(m, value),
      _ => null,
    };

    final rows = <(String, String)>[
      ('Movement No', m.movementNo),
      (l10n.fieldsDate, m.movementDate),
      (l10n.fieldsItem, _codeName(m.itemCode, m.itemName)),
      (l10n.fieldsWarehouse, _codeName(m.warehouseCode, m.warehouseName)),
      ('Movement Type', m.movementType),
      (l10n.commonQuantity, _quantityOf(m)),
      ('Unit Cost', m.unitCost == null ? '—' : '${m.unitCost}'),
      (l10n.fieldsReference, detailDash(m.referenceDocNo)),
      ('Remarks', detailDash(m.remarks)),
      ('Created By', detailDash(m.createdByName)),
      ('Created At', detailDash(m.createdAt)),
    ];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              detailSectionLabel(context, 'Stock Movement'),
              const SizedBox(height: 2),
              Text(m.movementNo, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DetailInfoRows(rows: rows),
              if (linked != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => showStockMovementDetailDialog(
                      context,
                      movement: linked,
                    ),
                    icon: const Icon(Icons.link, size: 16),
                    label: Text(
                      '${l10n.stockmovementsLinkedmovement}: '
                      '${linked.movementNo}',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: l10n.commonRefresh,
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => ref.invalidate(
                      stockMovementDetailProvider(movement.id),
                    ),
                  ),
                  if (m.movementType == 'ADJUSTMENT')
                    _ReverseAdjustmentAction(movement: m),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _quantityOf(StockMovement m) =>
      '${m.quantity}'
      '${(m.unitOfMeasure?.isNotEmpty ?? false) ? ' ${m.unitOfMeasure}' : ''}';

  /// The first movement linked to [m] — either the movement its
  /// `reference_docno` names (the transfer IN → OUT leg, and reversal
  /// pairs), or a movement whose `reference_docno` names [m]'s own
  /// `movement_no` (the transfer OUT → IN leg). Purchase/sale references
  /// are document numbers, never movement numbers, so they never match.
  /// Only the first match is surfaced (a doubly-reversed adjustment would
  /// link to its first reversal only).
  static StockMovement? _findCounterpart(
    StockMovement m,
    List<StockMovement> all,
  ) {
    final refNo = m.referenceDocNo;
    if (refNo != null && refNo.isNotEmpty) {
      for (final other in all) {
        if (other.id != m.id && other.movementNo == refNo) return other;
      }
    }
    for (final other in all) {
      final otherRef = other.referenceDocNo;
      if (other.id != m.id &&
          otherRef != null &&
          otherRef.isNotEmpty &&
          otherRef == m.movementNo) {
        return other;
      }
    }
    return null;
  }
}

/// Reverse Adjustment action for an ADJUSTMENT movement — confirm, then
/// POST a compensating `ADJUSTMENT` movement (inverse quantity, linked to
/// the original via `reference_docno`). The server has no delete/cancel
/// endpoint, so void-by-reversal is the honest flow.
class _ReverseAdjustmentAction extends ConsumerStatefulWidget {
  const _ReverseAdjustmentAction({required this.movement});

  final StockMovement movement;

  @override
  ConsumerState<_ReverseAdjustmentAction> createState() =>
      _ReverseAdjustmentActionState();
}

class _ReverseAdjustmentActionState
    extends ConsumerState<_ReverseAdjustmentAction> {
  bool _busy = false;

  Future<void> _reverse() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.stockmovementsReverse,
      message: l10n.stockmovementsReverseconfirm,
      confirmLabel: l10n.stockmovementsReverse,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);

    final result = await ref
        .read(inventoryRepositoryProvider)
        .createStockMovement({
          'item_id': widget.movement.itemId,
          'warehouse_id': widget.movement.warehouseId,
          'quantity': -widget.movement.quantity,
          'movement_type': 'ADJUSTMENT',
          'remarks': 'Reverse of ${widget.movement.movementNo}',
          'reference_doctype': 'ADJUSTMENT',
          'reference_docno': widget.movement.movementNo,
        });
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(
          stockMovementsProvider(ref.read(movementTypeFilterProvider)),
        );
        ref.invalidate(stockBalancesProvider);
        showAppToast(context, l10n.stockmovementsReversemsg);
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() => _busy = false);
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OutlinedButton.icon(
      onPressed: _busy ? null : _reverse,
      icon: const Icon(Icons.undo, size: 18),
      label: Text(l10n.stockmovementsReverse),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
