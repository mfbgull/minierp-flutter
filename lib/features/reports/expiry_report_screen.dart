// Expiry report screen — `GET /reports/expiry` with warehouse / status /
// threshold filters, color-coded rows, and CSV export.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show ExpiryReportRow;
import '../../data/models/stock_batch.dart' show BatchStatus;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show warehousesProvider;
import 'report_providers.dart';

class ExpiryReportScreen extends ConsumerStatefulWidget {
  const ExpiryReportScreen({super.key});

  @override
  ConsumerState<ExpiryReportScreen> createState() =>
      _ExpiryReportScreenState();
}

class _ExpiryReportScreenState extends ConsumerState<ExpiryReportScreen> {
  int _currentPage = 1;
  int _pageSize = 50;
  // Replaced on every grid (re)load — the grid is keyed per page.
  GridColumnWidths? _widthTracker;

  static const _pageSizeOptions = [25, 50, 100, 200];

  @override
  void dispose() {
    _widthTracker?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Reset page when filters change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listen(expiryReportWarehouseIdProvider, (_, __) {
        if (mounted) setState(() => _currentPage = 1);
      });
      ref.listen(expiryReportStatusProvider, (_, __) {
        if (mounted) setState(() => _currentPage = 1);
      });
      ref.listen(expiryReportThresholdProvider, (_, __) {
        if (mounted) setState(() => _currentPage = 1);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final report = ref.watch(expiryReportProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.expiryReport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          onRefresh: () {
            setState(() => _currentPage = 1);
            ref.invalidate(expiryReportProvider);
          },
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || report.valueOrNull == null
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('expiry'),
                      csv: buildExpiryReportCsv(l10n, report.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.exportCsv),
            ),
          ],
        ),
        _Filters(),
        const SizedBox(height: 8),
        Expanded(child: _body(context, ref, report)),
        _paginationBar(context, ref, report),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ExpiryReportRow>> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () {
          setState(() => _currentPage = 1);
          ref.invalidate(expiryReportProvider);
        },
      );
    }
    if (report.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = report.valueOrNull;
    if (data == null || data.isEmpty) {
      return Center(child: Text(l10n.reportsNodata));
    }

    // Paginate
    final totalPages = (data.length / _pageSize).ceil().clamp(1, 9999);
    if (_currentPage > totalPages) _currentPage = totalPages;
    final startIdx = (_currentPage - 1) * _pageSize;
    final endIdx = (startIdx + _pageSize).clamp(0, data.length);
    final pageData = data.sublist(startIdx, endIdx);

    return PlutoGrid(
      key: ValueKey('$_currentPage-$_pageSize-${report.hashCode}'),
      configuration: plutoGridConfigurationFor(context, compact: true),
      columns: _columns(context, l10n),
      rows: [for (final r in pageData) _toRow(r)],
      onLoaded: (e) {
        e.stateManager.setSelectingMode(PlutoGridSelectingMode.none);
        autoFitPlutoColumns(e.stateManager);
        _widthTracker?.dispose();
        _widthTracker = GridColumnWidths.attach(
          stateManager: e.stateManager,
          screenKey: 'report_expiry',
        );
      },
      rowColorCallback: (ctx) {
        final status = BatchStatus.fromString(
          ctx.row.cells['status']!.value as String?,
        );
        return switch (status) {
          BatchStatus.expired => const Color(0xFFFEE2E2),
          BatchStatus.nearExpiry => const Color(0xFFFFF1DC),
          BatchStatus.halted => const Color(0xFFEEEEEE),
          BatchStatus.normal => Colors.transparent,
        };
      },
    );
  }

  Widget _paginationBar(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ExpiryReportRow>> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final data = report.valueOrNull;
    final totalRows = data?.length ?? 0;
    final totalPages = (totalRows / _pageSize).ceil().clamp(1, 9999);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (totalRows == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // Row count
          Text(
            l10n.expiryReportPagination(totalRows, _currentPage, totalPages),
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // Page size selector
          Text(
            'Per page: ',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          DropdownButton<int>(
            value: _pageSize,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final size in _pageSizeOptions)
                DropdownMenuItem(value: size, child: Text('$size')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _pageSize = value;
                  _currentPage = 1;
                });
              }
            },
          ),
          const SizedBox(width: 16),
          // Navigation buttons
          IconButton(
            onPressed: _currentPage > 1
                ? () => setState(() => _currentPage = 1)
                : null,
            icon: const Icon(Icons.first_page, size: 20),
            tooltip: l10n.expiryReportFirstPage,
          ),
          IconButton(
            onPressed: _currentPage > 1
                ? () => setState(() => _currentPage--)
                : null,
            icon: const Icon(Icons.chevron_left, size: 20),
            tooltip: l10n.expiryReportPreviousPage,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$_currentPage / $totalPages',
              style: textTheme.bodyMedium,
            ),
          ),
          IconButton(
            onPressed: _currentPage < totalPages
                ? () => setState(() => _currentPage++)
                : null,
            icon: const Icon(Icons.chevron_right, size: 20),
            tooltip: l10n.expiryReportNextPage,
          ),
          IconButton(
            onPressed: _currentPage < totalPages
                ? () => setState(() => _currentPage = totalPages)
                : null,
            icon: const Icon(Icons.last_page, size: 20),
            tooltip: l10n.expiryReportLastPage,
          ),
        ],
      ),
    );
  }

  List<PlutoColumn> _columns(BuildContext context, AppLocalizations l10n) => [
    PlutoColumn(
      title: l10n.inventoryItemcode,
      field: 'itemCode',
      type: PlutoColumnType.text(),
      width: 110,
    ),
    PlutoColumn(
      title: l10n.inventoryItemname,
      field: 'itemName',
      type: PlutoColumnType.text(),
      width: 160,
    ),
    PlutoColumn(
      title: l10n.fieldsBatchno,
      field: 'batchNo',
      type: PlutoColumnType.text(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.fieldsWarehouse,
      field: 'warehouse',
      type: PlutoColumnType.text(),
      width: 130,
    ),
    PlutoColumn(
      title: l10n.inventoryQtyremaining,
      field: 'remaining',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 100,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
    ),
    PlutoColumn(
      title: l10n.fieldsUnitcost,
      field: 'unitCost',
      type: PlutoColumnType.number(format: '#,###.00'),
      width: 100,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
    ),
    PlutoColumn(
      title: l10n.totalValue,
      field: 'totalValue',
      type: PlutoColumnType.number(format: '#,###.00'),
      width: 110,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
    ),
    PlutoColumn(
      title: l10n.fieldsDate,
      field: 'received',
      type: PlutoColumnType.text(),
      width: 110,
    ),
    PlutoColumn(
      title: l10n.expiryDate,
      field: 'expiry',
      type: PlutoColumnType.text(),
      width: 110,
    ),
    PlutoColumn(
      title: l10n.expiryStatus,
      field: 'status',
      type: PlutoColumnType.text(),
      width: 120,
      renderer: (ctx) {
        final status = BatchStatus.fromString(ctx.cell.value as String?);
        final (color, label) = switch (status) {
          BatchStatus.normal => (const Color(0xff16a34a), l10n.statusNormal),
          BatchStatus.nearExpiry =>
            (const Color(0xffd97706), l10n.statusNearExpiry),
          BatchStatus.expired => (Colors.red, l10n.statusExpired),
          BatchStatus.halted => (Colors.grey, l10n.statusHalted),
        };
        return Container(
          alignment: Alignment.centerLeft,
          child: Chip(
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            label: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
              ),
            ),
            backgroundColor: color.withValues(alpha: 0.14),
          ),
        );
      },
    ),
    PlutoColumn(
      title: l10n.daysUntilExpiry,
      field: 'days',
      type: PlutoColumnType.number(format: '#,###'),
      width: 100,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
    ),
    PlutoColumn(
      title: l10n.statusHalted,
      field: 'halted',
      type: PlutoColumnType.text(),
      width: 80,
    ),
  ];

  PlutoRow _toRow(ExpiryReportRow r) {
    final status = r.halted
        ? BatchStatus.halted
        : BatchStatus.fromString(r.status);
    return PlutoRow(
      cells: {
        'itemCode': PlutoCell(value: r.itemCode),
        'itemName': PlutoCell(value: r.itemName),
        'batchNo': PlutoCell(value: r.batchNo),
        'warehouse': PlutoCell(value: r.warehouseName),
        'remaining': PlutoCell(value: r.quantityRemaining),
        'unitCost': PlutoCell(value: r.unitCost),
        'totalValue': PlutoCell(value: r.totalValue),
        'received': PlutoCell(
          value: r.receivedDate.isEmpty ? '' : Formatters.date(r.receivedDate),
        ),
        'expiry': PlutoCell(
          value: r.expiryDate != null ? Formatters.date(r.expiryDate!) : '',
        ),
        'status': PlutoCell(value: status.value),
        'days': PlutoCell(value: r.daysUntilExpiry ?? 0),
        'halted': PlutoCell(value: r.halted ? '✓' : ''),
      },
    );
  }
}

/// Filters bar for the expiry report — warehouse, status, threshold days.
class _Filters extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];
    final warehouseId = ref.watch(expiryReportWarehouseIdProvider);
    final status = ref.watch(expiryReportStatusProvider);
    final threshold = ref.watch(expiryReportThresholdProvider);
    final scheme = Theme.of(context).colorScheme;

    final statusOptions = [
      (l10n.commonAll, 'all'),
      (l10n.statusExpired, 'expired'),
      (l10n.statusNearExpiry, 'near_expiry'),
      (l10n.statusNormal, 'normal'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 200,
            child: SearchableSelect<int>(
              items: [for (final w in warehouses) w.id],
              selected: warehouseId,
              labelBuilder: (id) {
                final match = warehouses.where((w) => w.id == id);
                return match.isEmpty
                    ? l10n.expiryWarehouseLabel
                    : (match.first.warehouseName ??
                        match.first.warehouseCode);
              },
              decoration: InputDecoration(
                labelText: l10n.expiryWarehouseLabel,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: (value) {
                ref.read(expiryReportWarehouseIdProvider.notifier).state = value;
                ref.invalidate(expiryReportProvider);
              },
            ),
          ),
          SizedBox(
            width: 170,
            child: SearchableSelect<String>(
              items: [for (final o in statusOptions) o.$2],
              selected: status,
              labelBuilder: (v) =>
                  statusOptions.firstWhere((o) => o.$2 == v).$1,
              decoration: InputDecoration(
                labelText: l10n.expiryStatus,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: (value) {
                if (value != null) {
                  ref.read(expiryReportStatusProvider.notifier).state = value;
                  ref.invalidate(expiryReportProvider);
                }
              },
            ),
          ),
          SizedBox(
            width: 150,
            child: TextFormField(
              initialValue: threshold?.toString() ?? '',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
              ),
              decoration: InputDecoration(
                labelText: l10n.thresholdDays,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                suffixIcon: threshold != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          ref
                              .read(expiryReportThresholdProvider.notifier)
                              .state = null;
                          ref.invalidate(expiryReportProvider);
                        },
                      )
                    : null,
              ),
              onFieldSubmitted: (v) {
                final n = int.tryParse(v.trim());
                ref.read(expiryReportThresholdProvider.notifier).state = n;
                ref.invalidate(expiryReportProvider);
              },
            ),
          ),
          if (warehouseId != null || status != 'all' || threshold != null)
            TextButton.icon(
              onPressed: () {
                ref.read(expiryReportWarehouseIdProvider.notifier).state = null;
                ref.read(expiryReportStatusProvider.notifier).state = 'all';
                ref.read(expiryReportThresholdProvider.notifier).state = null;
                ref.invalidate(expiryReportProvider);
              },
              icon: Icon(Icons.filter_alt_off_outlined, size: 16, color: scheme.primary),
              label: Text(l10n.filters, style: TextStyle(color: scheme.primary)),
            ),
        ],
      ),
    );
  }
}
