// Physical count detail dialog — opened by double-tapping/F2 on a row in
// the physical counts grid. Fetches `GET /inventory/physical-counts/:id`
// (header + item lines) via [physicalCountDetailProvider]; the grid row's
// hidden `id` cell supplies the count id.

import 'package:flutter/material.dart';
import '../../core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/physical_count.dart'
    show PhysicalCount, PhysicalCountItem;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiResult, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show PhysicalCountDetail, inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart' show detailDash, detailSectionLabel;
import '../../widgets/detail_rows.dart' show DetailInfoRows;
import '../../widgets/status_badge.dart';
import 'inventory_providers.dart';
import 'record_count_dialog.dart';

/// Opens the read-only detail dialog for the count [countId].
Future<void> showPhysicalCountDetailDialog(
  BuildContext context, {
  required int countId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _PhysicalCountDetailDialog(countId: countId),
  );
}

class _PhysicalCountDetailDialog extends ConsumerWidget {
  const _PhysicalCountDetailDialog({required this.countId});

  final int countId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(physicalCountDetailProvider(countId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: switch (detail) {
          AsyncData(:final value) => _DetailBody(detail: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(physicalCountDetailProvider(countId)),
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

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final PhysicalCountDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = detail.count;

    final headerRows = <(String, String)>[
      ('Count No', c.countNo),
      (l10n.fieldsDate, c.countDate),
      (l10n.fieldsWarehouse, detailDash(c.warehouseName)),
      ('Total Items', '${c.totalItems ?? 0}'),
      ('Counted', '${c.countedItems ?? 0}'),
      ('Variance', '${c.varianceItems ?? 0}'),
      if (c.notes != null && c.notes!.isNotEmpty) ('Notes', c.notes!),
    ];

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
                    detailSectionLabel(context, 'Physical Count'),
                    const SizedBox(height: 2),
                    Text(
                      c.countNo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              StatusBadge(
                status: c.status,
                color: StatusColors.of(context).physicalCount(c.status),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailInfoRows(rows: headerRows),
                const SizedBox(height: 16),
                detailSectionLabel(context, 'Counted Items'),
                const SizedBox(height: 8),
                _ItemsTable(items: detail.items),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Non-terminal counts can record items, then be completed
              // or cancelled (the server rejects both terminal statuses).
              if (!c.isCompleted && !c.isCancelled) ...[
                FilledButton.tonalIcon(
                  onPressed: () => showRecordCountDialog(
                    context,
                    countId: c.id,
                    items: detail.items,
                  ),
                  icon: const Icon(Icons.edit_note_outlined, size: 18),
                  label: Text(l10n.physicalcountsRecorditems),
                ),
                _CountActions(count: c),
              ],
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonClose),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Complete / Cancel actions for a non-terminal count — confirm, POST the
/// workflow transition, then invalidate the list + detail providers (the
/// dialog refetches, the badge flips and these actions disappear).
class _CountActions extends ConsumerStatefulWidget {
  const _CountActions({required this.count});

  final PhysicalCount count;

  @override
  ConsumerState<_CountActions> createState() => _CountActionsState();
}

class _CountActionsState extends ConsumerState<_CountActions> {
  bool _busy = false;

  Future<void> _complete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.physicalcountsCompletecount,
      message: l10n.physicalcountsCompleteconfirm,
      confirmLabel: l10n.physicalcountsCompletecount,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref
          .read(inventoryRepositoryProvider)
          .completePhysicalCount(widget.count.id),
      l10n.physicalcountsCompletedmsg,
    );
  }

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.physicalcountsCancelcount,
      message: l10n.physicalcountsCancelconfirm,
      confirmLabel: l10n.physicalcountsCancelcount,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref
          .read(inventoryRepositoryProvider)
          .cancelPhysicalCount(widget.count.id),
      l10n.physicalcountsCancelledmsg,
    );
  }

  Future<void> _run(
    Future<ApiResult<PhysicalCount>> Function() action,
    String successMessage,
  ) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        // The invalidate refetches the detail (badge flips, actions
        // disappear) — no setState after it, the actions are removed
        // on rebuild.
        ref.invalidate(physicalCountsProvider);
        ref.invalidate(physicalCountDetailProvider(widget.count.id));
        showAppToast(context, successMessage);
      case ApiFailure(:final error):
        setState(() => _busy = false);
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _cancel,
          icon: const Icon(Icons.block_outlined, size: 18),
          label: Text(l10n.physicalcountsCancelcount),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _complete,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline, size: 18),
          label: Text(l10n.physicalcountsCompletecount),
        ),
      ],
    );
  }
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.items});

  final List<PhysicalCountItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Text('No items counted', style: TextStyle(color: scheme.outline));
    }

    TextStyle? cell(bool emphasize) => Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400);

    Widget headerCell(String text, {TextAlign? align}) => Text(
      text,
      textAlign: align,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
        letterSpacing: 0.4,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: headerCell('Item')),
            Expanded(child: headerCell('System', align: TextAlign.end)),
            Expanded(child: headerCell('Counted', align: TextAlign.end)),
            Expanded(child: headerCell('Variance', align: TextAlign.end)),
          ],
        ),
        const SizedBox(height: 4),
        for (final (index, item) in items.indexed) ...[
          if (index > 0) Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    _itemLabel(item),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${item.systemQuantity}',
                    textAlign: TextAlign.end,
                    style: cell(false),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${item.countedQuantity ?? '—'}',
                    textAlign: TextAlign.end,
                    style: cell(false),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${item.variance ?? '—'}',
                    textAlign: TextAlign.end,
                    style: cell((item.variance ?? 0) != 0),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _itemLabel(PhysicalCountItem item) => [
    item.itemCode,
    item.itemName,
  ].where((s) => s != null && s.isNotEmpty).join(' — ');
}
