// BOM detail dialog — opened by double-tapping a BOM row or via the
// F2/Enter keyboard shortcut. Fetches `GET /boms/:id` (bare object
// with the material `items` array) via [bomDetailProvider]. Renders
// the header (BOM no + active badge), an info grid, the material
// cost tile, the materials table, and the row actions: edit, toggle
// active, delete (delete is rejected server-side once the BOM has
// been used by production records).

import 'package:flutter/material.dart';
import '../../core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/bom.dart';
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
import '../../widgets/status_badge.dart';
import 'bom_form_dialog.dart';
import 'production_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the BOM detail dialog for [bomId].
Future<void> showBomDetailDialog(BuildContext context, {required int bomId}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => BomDetailDialog(bomId: bomId),
  );
}

class BomDetailDialog extends ConsumerWidget {
  const BomDetailDialog({super.key, required this.bomId});

  final int bomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(bomDetailProvider(bomId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
        child: switch (detail) {
          AsyncData(:final value) => _DetailBody(bomId: bomId, bom: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(bomDetailProvider(bomId)),
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
  const _DetailBody({required this.bomId, required this.bom});

  final int bomId;
  final BomDetail bom;

  Future<void> _toggleActive(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(productionRepositoryProvider)
        .toggleBomActive(bom.id);
    if (!context.mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(bomsProvider);
        ref.invalidate(bomDetailProvider(bomId));
        showAppToast(
          context,
          result.data.isActive
              ? AppLocalizations.of(context)!.bomActivated
              : AppLocalizations.of(context)!.bomDeactivated,
        );
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.bomDeleteconfirm,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final result = await ref
        .read(productionRepositoryProvider)
        .deleteBom(bom.id);
    if (!context.mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(bomsProvider);
        Navigator.of(context).pop();
        showAppToast(context, l10n.bomDeleted);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  void _edit(BuildContext context) {
    Navigator.of(context).pop();
    showBomFormDialog(context, detail: bom);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

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
                    detailSectionLabel(context, l10n.bomDetailstitle),
                    const SizedBox(height: 2),
                    Text(
                      bom.bomNo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bom.bomName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusBadge(
                status: bom.isActive ? l10n.statusActive : l10n.statusInactive,
                color: StatusColors.of(context).active(bom.isActive),
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
                    (l10n.bomName, bom.bomName),
                    (l10n.bomFinisheditem, detailDash(bom.finishedItemName)),
                    (l10n.commonUom, detailDash(bom.finishedUom)),
                    (l10n.bomQuantity, Formatters.number(bom.quantity)),
                    if (bom.createdAt != null)
                      (l10n.bomCreated, Formatters.date(bom.createdAt!)),
                    if (bom.description != null && bom.description!.isNotEmpty)
                      (l10n.bomDescription, bom.description!),
                  ],
                ),
                DetailTiles(
                  tiles: [
                    DetailTile(l10n.bomItems, '${bom.items.length}'),
                    DetailTile(
                      l10n.bomMaterialcost,
                      Formatters.currency(bom.totalMaterialCost ?? 0),
                      emphasize: true,
                    ),
                  ],
                ),
                if (bom.items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  detailSectionLabel(context, l10n.bomMaterials),
                  const SizedBox(height: 6),
                  _MaterialsTable(items: bom.items),
                ] else ...[
                  const SizedBox(height: 14),
                  Text(l10n.bomNoMaterials),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _toggleActive(context, ref),
                icon: Icon(
                  bom.isActive
                      ? Icons.block_outlined
                      : Icons.check_circle_outline,
                  size: 18,
                ),
                label: Text(
                  bom.isActive ? l10n.bomDeactivate : l10n.bomActivate,
                ),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l10n.commonEdit),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () => _delete(context, ref),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l10n.commonDelete),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String detailDash(String? value) =>
      (value == null || value.isEmpty) ? '—' : value;
}

class _MaterialsTable extends StatelessWidget {
  const _MaterialsTable({required this.items});

  final List<BomItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: AppBorderRadius.smRadius,
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
            DataColumn(label: Text(l10n.productionInputqty)),
            DataColumn(label: Text(l10n.commonUom)),
            DataColumn(label: Text(l10n.bomUnitcost)),
            DataColumn(label: Text(l10n.fieldsAmount)),
            DataColumn(label: Text(l10n.bomCurrentstock)),
          ],
          rows: [
            for (final item in items)
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      item.itemCode.isEmpty
                          ? item.itemName
                          : '${item.itemCode} — ${item.itemName}',
                    ),
                  ),
                  DataCell(Text(Formatters.number(item.quantity))),
                  DataCell(Text(item.unitOfMeasure ?? '—')),
                  DataCell(Text(Formatters.currency(item.standardCost ?? 0))),
                  DataCell(Text(Formatters.currency(item.lineCost ?? 0))),
                  DataCell(
                    Text(
                      item.currentStock == null
                          ? '—'
                          : Formatters.number(item.currentStock!),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
