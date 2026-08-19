import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show BatchTraceabilityReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../data/models/item.dart' show Item;
import '../../features/inventory/inventory_providers.dart' show allItemsProvider;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../../widgets/searchable_select.dart';
import 'report_providers.dart';

class BatchTraceabilityReportScreen extends ConsumerWidget {
  const BatchTraceabilityReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(batchTraceabilityProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsBatchtraceability,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          onRefresh: () => ref.invalidate(batchTraceabilityProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || report.valueOrNull == null
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('batch-traceability'),
                      csv: buildBatchTraceabilityCsv(l10n, report.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        // Item selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ItemSelector(),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body(context, ref, report)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<BatchTraceabilityReport> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(batchTraceabilityProvider),
      );
    }
    if (report.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = report.valueOrNull;
    if (data == null) {
      return Center(
        child: Text(l10n.reportsSelectitem),
      );
    }

    return _BatchTraceabilityContent(report: data);
  }
}

class _ItemSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selectedId = ref.watch(batchTraceabilityItemIdProvider);
    final itemsAsync = ref.watch(allItemsProvider);
    final items = itemsAsync.valueOrNull ?? const <Item>[];

    return Row(
      children: [
        Icon(Icons.inventory_2_outlined, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('${l10n.fieldsItem}: ', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 8),
        Expanded(
          child: itemsAsync.isLoading
              ? const SizedBox(
                  height: 40,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : SearchableSelect<int>(
                  items: [for (final i in items) i.id],
                  selected: selectedId > 0 ? selectedId : null,
                  labelBuilder: (id) {
                    final match = items.where((i) => i.id == id);
                    final item = match.isEmpty ? null : match.first;
                    return item == null
                        ? l10n.reportsSelectitem
                        : '${item.itemCode} — ${item.itemName}';
                  },
                  decoration: InputDecoration(
                    hintText: l10n.reportsSelectitem,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (value) {
                    ref.read(batchTraceabilityItemIdProvider.notifier).state = value ?? 0;
                    if (value != null && value > 0) {
                      ref.invalidate(batchTraceabilityProvider);
                    }
                  },
                ),
        ),
      ],
    );
  }
}

class _BatchTraceabilityContent extends StatelessWidget {
  const _BatchTraceabilityContent({required this.report});
  final BatchTraceabilityReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final s = report.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Item info + summary strip
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.inventory_2, size: 16),
                label: Text('${report.item.itemName} (${report.item.itemCode})'),
              ),
              _miniMetric('Batches', '${s.totalBatches}', theme),
              _miniMetric('Active', '${s.activeBatches}', theme),
              _miniMetric('Received', Formatters.number(s.totalOriginal), theme),
              _miniMetric('Sold', Formatters.number(s.totalSold), theme),
              _miniMetric('Remaining', Formatters.number(s.totalRemaining), theme),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Batches grid
        Expanded(
          child: report.batches.isEmpty
              ? Center(child: Text(l10n.reportsNodata))
              : PlutoGrid(
                  configuration: const PlutoGridConfiguration(),
                  columns: [
                    PlutoColumn(title: 'Batch No', field: 'batchNo', type: PlutoColumnType.text(), width: 120),
                    PlutoColumn(title: l10n.fieldsWarehouse, field: 'warehouse', type: PlutoColumnType.text(), width: 130),
                    PlutoColumn(title: 'Source', field: 'source', type: PlutoColumnType.text(), width: 120),
                    PlutoColumn(title: l10n.reportsDate, field: 'date', type: PlutoColumnType.text(), width: 110),
                    PlutoColumn(title: 'Unit Cost', field: 'unitCost', type: PlutoColumnType.number(format: '#,###.00'), width: 100, textAlign: PlutoColumnTextAlign.end, titleTextAlign: PlutoColumnTextAlign.end),
                    PlutoColumn(title: 'Original', field: 'original', type: PlutoColumnType.number(format: '#,###.##'), width: 90, textAlign: PlutoColumnTextAlign.end, titleTextAlign: PlutoColumnTextAlign.end),
                    PlutoColumn(title: 'Sold', field: 'sold', type: PlutoColumnType.number(format: '#,###.##'), width: 90, textAlign: PlutoColumnTextAlign.end, titleTextAlign: PlutoColumnTextAlign.end),
                    PlutoColumn(title: 'Remaining', field: 'remaining', type: PlutoColumnType.number(format: '#,###.##'), width: 100, textAlign: PlutoColumnTextAlign.end, titleTextAlign: PlutoColumnTextAlign.end),
                  ],
                  rows: [
                    for (final b in report.batches)
                      PlutoRow(cells: {
                        'batchNo': PlutoCell(value: b.batchNo),
                        'warehouse': PlutoCell(value: b.warehouseName),
                        'source': PlutoCell(value: '${b.sourceType} #${b.sourceId}'),
                        'date': PlutoCell(value: Formatters.date(b.receivedDate)),
                        'unitCost': PlutoCell(value: b.unitCost),
                        'original': PlutoCell(value: b.quantityOriginal),
                        'sold': PlutoCell(value: b.quantitySold),
                        'remaining': PlutoCell(value: b.quantityRemaining),
                      }),
                  ],
                  onLoaded: (e) => e.stateManager.setSelectingMode(PlutoGridSelectingMode.none),
                ),
        ),
      ],
    );
  }

  Widget _miniMetric(String label, String value, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(width: 4),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
