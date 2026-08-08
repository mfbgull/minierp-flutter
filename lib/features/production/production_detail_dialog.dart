// Production run detail dialog — opened by double-tapping a row in
// the productions grid or via the F2/Enter shortcut. Fetches
// `GET /productions/:id` (bare object with the `inputs` array) via
// [productionDetailProvider]. Renders the header (production no +
// batch no), an info grid, the batch-cost tiles, and the consumed
// raw-materials table. A delete action reverses the stock + GL
// postings server-side (`DELETE /productions/:id`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/production.dart';
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/production_repository.dart'
    show productionRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import 'production_providers.dart';

/// Opens the read-only detail dialog for [productionId].
Future<void> showProductionDetailDialog(
  BuildContext context, {
  required int productionId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        ProductionDetailDialog(productionId: productionId),
  );
}

class ProductionDetailDialog extends ConsumerWidget {
  const ProductionDetailDialog({super.key, required this.productionId});

  final int productionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(productionDetailProvider(productionId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
        child: switch (detail) {
          AsyncData(:final value) => _DetailBody(
            detail: value,
            productionId: productionId,
          ),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () =>
                ref.invalidate(productionDetailProvider(productionId)),
          ),
          _ => const SizedBox(
            width: 420,
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail, required this.productionId});

  final Production detail;
  final int productionId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.productionDeleteconfirm,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final result = await ref
        .read(productionRepositoryProvider)
        .deleteProduction(detail.id);
    if (!context.mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(productionsProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.productionDeleted);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final d = detail;
    final fg = d.finishedGoodsWarehouseName ?? '';
    final rm = d.rawMaterialsWarehouseName ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    detailSectionLabel(context, l10n.productionDetailstitle),
                    const SizedBox(height: 2),
                    Text(
                      d.productionNo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      d.outputItemName ?? '',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: l10n.commonDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailInfoRows(
                  rows: [
                    (l10n.commonDate, Formatters.date(d.productionDate)),
                    (l10n.productionOutputitem, detailDash(d.outputItemName)),
                    (l10n.productionWarehouse, detailDash(fg)),
                    (l10n.productionRawmaterialsWarehouse, detailDash(rm)),
                    (l10n.productionBatchno, detailDash(d.batchNo)),
                    (l10n.productionCreatedby, detailDash(d.createdByUsername)),
                    if (d.remarks != null && d.remarks!.isNotEmpty)
                      (l10n.purchasesRemarks, d.remarks!),
                  ],
                ),
                DetailTiles(
                  tiles: [
                    DetailTile(
                      l10n.productionMaterialcost,
                      Formatters.currency(d.totalMaterialCost ?? 0),
                    ),
                    DetailTile(
                      l10n.productionOverhead,
                      Formatters.currency(d.overheadCost),
                    ),
                    DetailTile(
                      l10n.productionTotalcost,
                      Formatters.currency(d.totalBatchCost ?? 0),
                      emphasize: true,
                    ),
                    DetailTile(
                      l10n.productionUnitcost,
                      Formatters.currency(d.unitCost ?? 0),
                    ),
                  ],
                ),
                if (d.inputs.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  detailSectionLabel(context, l10n.productionInputs),
                  const SizedBox(height: 6),
                  _InputsTable(inputs: d.inputs),
                ] else ...[
                  const SizedBox(height: 14),
                  Text(l10n.productionNoinputs),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String detailDash(String? value) =>
      (value == null || value.isEmpty) ? '—' : value;

  String detailCash(num? value) => Formatters.currency(value ?? 0);
}

class _InputsTable extends StatelessWidget {
  const _InputsTable({required this.inputs});

  final List<ProductionInput> inputs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columns: [
            DataColumn(label: Text(l10n.fieldsItem)),
            DataColumn(label: Text(l10n.purchasesQuantitycol)),
            DataColumn(label: Text(l10n.commonUom)),
            DataColumn(label: Text(l10n.productionWarehouse)),
          ],
          rows: [
            for (final input in inputs)
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      input.itemCode.isEmpty
                          ? input.itemName
                          : '${input.itemCode} — ${input.itemName}',
                    ),
                  ),
                  DataCell(Text(Formatters.number(input.quantity))),
                  DataCell(Text(input.unitOfMeasure ?? '—')),
                  DataCell(Text(detailDash(input.warehouseName))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String detailDash(String? value) =>
      (value == null || value.isEmpty) ? '—' : value;
}
