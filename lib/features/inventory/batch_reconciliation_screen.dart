// Batch reconciliation screen — lists drift between master batch qty
// and physical qty per location (`GET /inventory/batch-reconciliation`)
// with inline correction (`POST /inventory/batch-reconciliation/correct`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor;

class BatchReconciliationScreen extends ConsumerStatefulWidget {
  const BatchReconciliationScreen({super.key});

  @override
  ConsumerState<BatchReconciliationScreen> createState() =>
      _BatchReconciliationScreenState();
}

class _BatchReconciliationScreenState
    extends ConsumerState<BatchReconciliationScreen> {
  List<Map<String, dynamic>> _drifts = const [];
  bool _loading = false;
  String? _error;
  GridColumnWidths? _widthTracker;

  @override
  void dispose() {
    _widthTracker?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(inventoryRepositoryProvider)
        .getBatchReconciliation();
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _drifts = data;
          _loading = false;
        });
      case ApiFailure(:final error):
        setState(() {
          _error = error.message;
          _loading = false;
        });
    }
  }

  Future<void> _correct(Map<String, dynamic> drift) async {
    final l10n = AppLocalizations.of(context)!;
    final batchId = drift['batch_id'] as int;
    final locationId = drift['location_id'] as int;
    final masterQty = (drift['master_qty'] as num?) ?? 0;
    final physicalQty = (drift['quantity_physical'] as num?) ?? 0;

    final controller = TextEditingController(text: physicalQty.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Correct Reconciliation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Batch: ${drift['batch_no']}'),
            Text('Location: ${drift['location_code']}'),
            Text('Master qty: ${Formatters.number(masterQty)}'),
            Text('Physical qty: ${Formatters.number(physicalQty)}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'New physical quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final newQty = num.tryParse(controller.text.trim());
    if (newQty == null || newQty < 0) {
      showAppToast(context, 'Invalid quantity', isError: true);
      return;
    }

    final result = await ref
        .read(inventoryRepositoryProvider)
        .correctBatchReconciliation(
          batchId: batchId,
          locationId: locationId,
          newQuantityPhysical: newQty,
        );
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.commonSaved);
        _load();
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Reconciliation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: Text(l10n.commonRetry)),
                    ],
                  ),
                )
              : _drifts.isEmpty
                  ? Center(child: Text(l10n.reportsNodata))
                  : PlutoGrid(
                      configuration: plutoGridConfigurationFor(context, compact: true),
                      columns: _columns(l10n),
                      rows: [
                        for (final d in _drifts) _toRow(d),
                      ],
                      onLoaded: (e) {
                        e.stateManager.setSelectingMode(PlutoGridSelectingMode.none);
                        autoFitPlutoColumns(e.stateManager);
                        _widthTracker?.dispose();
                        _widthTracker = GridColumnWidths.attach(
                          stateManager: e.stateManager,
                          screenKey: 'batch_reconciliation',
                        );
                      },
                    ),
    );
  }

  List<PlutoColumn> _columns(AppLocalizations l10n) => [
    PlutoColumn(
      title: 'Batch',
      field: 'batch_no',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
    ),
    PlutoColumn(
      title: 'Item',
      field: 'item_code',
      type: PlutoColumnType.text(),
      width: 100,
      readOnly: true,
    ),
    PlutoColumn(
      title: 'Location',
      field: 'location_code',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
    ),
    PlutoColumn(
      title: 'Master Qty',
      field: 'master_qty',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 100,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
    ),
    PlutoColumn(
      title: 'Physical',
      field: 'physical',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 100,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
    ),
    PlutoColumn(
      title: 'Reserved',
      field: 'reserved',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 100,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
    ),
    PlutoColumn(
      title: 'Available',
      field: 'available',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 100,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
    ),
    PlutoColumn(
      title: 'Drift',
      field: 'drift',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 100,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
      renderer: (ctx) {
        final drift = ctx.cell.value as num? ?? 0;
        final color = drift < 0 ? Colors.red : drift > 0 ? Colors.green : null;
        return Align(
          alignment: Alignment.centerRight,
          child: Text(
            Formatters.number(drift),
            style: color != null ? TextStyle(color: color) : null,
          ),
        );
      },
    ),
    PlutoColumn(
      title: 'Status',
      field: 'status',
      type: PlutoColumnType.text(),
      width: 110,
      readOnly: true,
      renderer: (ctx) {
        final status = ctx.cell.value as String? ?? '';
        return Center(
          child: Chip(
            visualDensity: VisualDensity.compact,
            label: Text(status, style: const TextStyle(fontSize: 11)),
          ),
        );
      },
    ),
    PlutoColumn(
      title: l10n.commonActions,
      field: 'actions',
      type: PlutoColumnType.text(),
      width: 120,
      enableSorting: false,
      renderer: (ctx) {
        final drift = ctx.row.cells['drift']!.value as Map<String, dynamic>;
        return IconButton(
          tooltip: 'Correct',
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: () => _correct(drift),
        );
      },
    ),
  ];

  PlutoRow _toRow(Map<String, dynamic> d) {
    return PlutoRow(
      cells: {
        'batch_no': PlutoCell(value: d['batch_no']),
        'item_code': PlutoCell(value: d['item_code']),
        'location_code': PlutoCell(value: d['location_code']),
        'master_qty': PlutoCell(value: d['master_qty']),
        'physical': PlutoCell(value: d['quantity_physical']),
        'reserved': PlutoCell(value: d['quantity_reserved']),
        'available': PlutoCell(value: d['quantity_available']),
        'drift': PlutoCell(value: d['drift']),
        'status': PlutoCell(value: d['status_override'] ?? 'ACTIVE'),
        'actions': PlutoCell(value: ''),
      },
    );
  }
}
