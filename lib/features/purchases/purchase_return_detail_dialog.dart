// Purchase return detail dialog — opened by double-tapping a return row
// (or F2/Enter). Fetches the full return from `GET /purchase-returns/:id`
// (header + embedded `items`) and renders both the header fields and the
// returned-items table.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/purchase_return_type.dart';
import '../../data/models/purchase_return.dart'
    show PurchaseReturn, PurchaseReturnItem;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

/// Provider that fetches the full return detail (header + items).
final _returnDetailProvider =
    FutureProvider.autoDispose.family<PurchaseReturn, int>((ref, id) async {
      final result =
          await ref.watch(purchaseRepositoryProvider).returnDetail(id);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Opens the detail dialog for a return header. Uses the in-memory model
/// for the header (fast), but fetches the full detail (with line items)
/// from the server.
Future<void> showPurchaseReturnDetailDialog(
  BuildContext context, {
  required PurchaseReturn purchaseReturn,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _PurchaseReturnDetailDialog(
      fallback: purchaseReturn,
    ),
  );
}

class _PurchaseReturnDetailDialog extends ConsumerWidget {
  const _PurchaseReturnDetailDialog({required this.fallback});

  /// The in-memory header from the grid row — used as a fast fallback
  /// while the full detail loads.
  final PurchaseReturn fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final detailAsync = ref.watch(_returnDetailProvider(fallback.id));

    return MovableDialog(
      dialogId: 'purchase_return_detail',
      maxWidth: 620,
      maxHeight: 680,
      child: detailAsync.when(
          loading: () => const SizedBox(
            width: 380,
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) {
            // Fall back to the in-memory header if the fetch fails.
            return _buildContent(context, l10n, fallback);
          },
          data: (full) => _buildContent(context, l10n, full),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    PurchaseReturn pr,
  ) {
    final color = returnTypeColors(Theme.of(context).colorScheme, pr.returnType);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    detailSectionLabel(context, l10n.purchasesReturntitle),
                    const SizedBox(height: 2),
                    Text(
                      pr.returnNo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              StatusBadge(
                status: returnTypeLabel(l10n, pr.returnType),
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Summary tiles
          DetailTiles(
            tiles: [
              DetailTile(
                l10n.purchasesReturnqty,
                Formatters.number(pr.totalQty),
                emphasize: true,
              ),
              DetailTile(
                l10n.purchasesReturnvalue,
                Formatters.currency(pr.totalAmount),
                emphasize: true,
              ),
              DetailTile(
                l10n.purchasesReturnitems,
                '${pr.items.length} ${l10n.purchasesReturnitems.toLowerCase()}',
              ),
            ],
          ),

          // Info rows
          DetailInfoRows(
            rows: [
              (l10n.purchasesReturndate, Formatters.date(pr.returnDate)),
              (l10n.fieldsReference, pr.sourceNo),
              (l10n.fieldsWarehouse, pr.warehouseName),
              (l10n.fieldsStatus, pr.status),
              if (pr.creditNo != null && pr.creditNo!.isNotEmpty)
                (l10n.suppliersLedgerCredit, pr.creditNo!),
              if (pr.reason != null && pr.reason!.isNotEmpty)
                (l10n.fieldsNotes, pr.reason!),
            ],
          ),

          // Returned items table
          if (pr.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              l10n.purchasesReturnitems,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _ItemsTable(items: pr.items),
            ),
          ],

          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonClose),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact table showing the returned line items.
class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.items});

  final List<PurchaseReturnItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: AppBorderRadius.smRadius,
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    l10n.fieldsItem,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.purchasesUnitcost,
                    textAlign: TextAlign.end,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.purchasesReturnqty,
                    textAlign: TextAlign.end,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.commonTotal,
                    textAlign: TextAlign.end,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Data rows
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].itemName,
                          style: textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (items[i].itemCode.isNotEmpty)
                          Text(
                            items[i].itemCode,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      Formatters.currency(items[i].unitCost),
                      textAlign: TextAlign.end,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      Formatters.number(items[i].quantity),
                      textAlign: TextAlign.end,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      Formatters.currency(items[i].amount),
                      textAlign: TextAlign.end,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
