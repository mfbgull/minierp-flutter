// Batch management screen — list, inline-expiry edit, and halt/unhalt
// for an item's batches (`GET/PATCH /inventory/stock-batches`). Opened
// from the item detail dialog's "Manage Batches" button or the inventory
// sidebar. Expiry editing and halt toggling ride the Actions column.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/item.dart' show Item;
import '../../data/models/stock_batch.dart' show BatchStatus, StockBatch;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor;
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show allItemsProvider;

/// Opens the batch management screen, pre-selected to [itemId] when given.
Future<void> showBatchManagementScreen(
  BuildContext context, {
  int? itemId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BatchManagementScreen(itemId: itemId),
    ),
  );
}

class BatchManagementScreen extends ConsumerStatefulWidget {
  const BatchManagementScreen({super.key, this.itemId});

  final int? itemId;

  @override
  ConsumerState<BatchManagementScreen> createState() =>
      _BatchManagementScreenState();
}

class _BatchManagementScreenState
    extends ConsumerState<BatchManagementScreen> {
  int? _selectedItemId;
  List<StockBatch> _batches = const [];
  bool _loading = false;
  String? _error;
  num _threshold = 30;

  // Replaced on every grid (re)load — the grid is keyed per item.
  GridColumnWidths? _widthTracker;

  @override
  void dispose() {
    _widthTracker?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _selectedItemId = widget.itemId;
    if (_selectedItemId != null) _load();
  }

  Future<void> _load() async {
    if (_selectedItemId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(inventoryRepositoryProvider)
        .getBatches(itemId: _selectedItemId);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        final item = _itemById(_selectedItemId!);
        setState(() {
          _batches = data;
          _threshold = item?.nearExpiryThresholdDays ?? 30;
          _loading = false;
        });
      case ApiFailure(:final error):
        setState(() {
          _error = error.message;
          _loading = false;
        });
    }
  }

  Item? _itemById(int id) {
    final items = ref.read(allItemsProvider).valueOrNull ?? const <Item>[];
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  StockBatch? _batchById(int id) {
    for (final b in _batches) {
      if (b.id == id) return b;
    }
    return null;
  }

  Future<void> _pickExpiry(StockBatch batch) async {
    final picked = await pickDate(
      context,
      initialDate: batch.expiryDate != null
          ? (DateTime.tryParse(batch.expiryDate!) ?? DateTime.now())
          : DateTime.now(),
      firstDate: DateTime(2000),
    );
    if (picked == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final newDate = isoDate(picked);
    final result = await ref
        .read(inventoryRepositoryProvider)
        .updateBatchExpiry(batch.id, newDate);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.commonSaved);
        _load();
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<void> _halt(StockBatch batch) async {
    final l10n = AppLocalizations.of(context)!;
    final reasonController = TextEditingController();
    final reason = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.haltReason),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          decoration:
              formHintDecoration(l10n.haltReasonHint),
          onSubmitted: (_) => Navigator.of(dialogContext).pop(
            reasonController.text.trim(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              reasonController.text.trim(),
            ),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    final result = await ref
        .read(inventoryRepositoryProvider)
        .haltBatch(batch.id, reason: reason);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.statusHalted);
        _load();
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<void> _unhalt(StockBatch batch) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await ref
        .read(inventoryRepositoryProvider)
        .unhaltBatch(batch.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.statusNormal);
        _load();
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Color _statusColor(BuildContext context, BatchStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      BatchStatus.normal => const Color(0xff16a34a),
      BatchStatus.nearExpiry => const Color(0xffd97706),
      BatchStatus.expired => scheme.error,
      BatchStatus.halted => scheme.onSurfaceVariant,
    };
  }

  String _statusLabel(AppLocalizations l10n, BatchStatus status) =>
      switch (status) {
        BatchStatus.normal => l10n.statusNormal,
        BatchStatus.nearExpiry => l10n.statusNearExpiry,
        BatchStatus.expired => l10n.statusExpired,
        BatchStatus.halted => l10n.statusHalted,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final itemsAsync = ref.watch(allItemsProvider);
    final items = itemsAsync.valueOrNull ?? const <Item>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.batchManagement),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: SearchableSelect<int>(
                    items: [for (final i in items) i.id],
                    selected: _selectedItemId,
                    labelBuilder: (id) {
                      final match = items.where((i) => i.id == id);
                      final item = match.isEmpty ? null : match.first;
                      return item == null
                          ? l10n.reportsSelectitem
                          : '${item.itemCode} — ${item.itemName}';
                    },
                    decoration: InputDecoration(
                      labelText: l10n.fieldsItem,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (value) => setState(() {
                      _selectedItemId = value;
                      _batches = const [];
                      if (value != null) _load();
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _body(l10n),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_selectedItemId == null) {
      return Center(child: Text(l10n.reportsSelectitem));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: Text(l10n.commonRetry)),
          ],
        ),
      );
    }
    if (_batches.isEmpty) {
      return Center(child: Text(l10n.reportsNodata));
    }

    return PlutoGrid(
      key: ValueKey(_selectedItemId),
      configuration: plutoGridConfigurationFor(context, compact: true),
      columns: _columns(l10n),
      rows: [
        for (final b in _batches) _toRow(b),
      ],
      onLoaded: (e) {
        e.stateManager.setSelectingMode(
          PlutoGridSelectingMode.none,
        );
        autoFitPlutoColumns(e.stateManager);
        _widthTracker?.dispose();
        _widthTracker = GridColumnWidths.attach(
          stateManager: e.stateManager,
          screenKey: 'batch_management',
        );
      },
    );
  }

  List<PlutoColumn> _columns(AppLocalizations l10n) => [
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
      title: l10n.fieldsSource,
      field: 'source',
      type: PlutoColumnType.text(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.inventoryQtyoriginal,
      field: 'original',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 100,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
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
        return Container(
          alignment: Alignment.centerLeft,
          child: Chip(
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            label: Text(
              _statusLabel(l10n, status),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: _statusColor(context, status)),
            ),
            backgroundColor:
                _statusColor(context, status).withValues(alpha: 0.14),
          ),
        );
      },
    ),
    PlutoColumn(
      title: l10n.commonActions,
      field: 'actions',
      type: PlutoColumnType.text(),
      width: 150,
      enableSorting: false,
      renderer: (ctx) {
        final id = ctx.row.cells['id']!.value as int;
        final batch = _batchById(id);
        if (batch == null) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l10n.expiryDate,
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              onPressed: () => _pickExpiry(batch),
            ),
            if (batch.halted)
              IconButton(
                tooltip: l10n.unhaltBatch,
                icon: const Icon(Icons.play_circle_outline, size: 18),
                onPressed: () => _unhalt(batch),
              )
            else
              IconButton(
                tooltip: l10n.haltBatch,
                icon: const Icon(Icons.pause_circle_outline, size: 18),
                onPressed: () => _halt(batch),
              ),
          ],
        );
      },
    ),
  ];

  PlutoRow _toRow(StockBatch b) {
    final status = b.computeStatus(nearExpiryThresholdDays: _threshold);
    return PlutoRow(
      cells: {
        'id': PlutoCell(value: b.id),
        'batchNo': PlutoCell(value: b.batchNo),
        'warehouse': PlutoCell(value: b.warehouseName ?? b.warehouseCode ?? ''),
        'source': PlutoCell(value: '${b.sourceType} #${b.sourceId}'),
        'original': PlutoCell(value: b.quantityOriginal),
        'remaining': PlutoCell(value: b.quantityRemaining),
        'unitCost': PlutoCell(value: b.unitCost),
        'received': PlutoCell(value: Formatters.date(b.receivedDate)),
        'expiry': PlutoCell(
          value: b.expiryDate != null ? Formatters.date(b.expiryDate!) : '',
        ),
        'status': PlutoCell(
          value: b.halted ? BatchStatus.halted.value : status.value,
        ),
        'actions': PlutoCell(value: ''),
      },
    );
  }
}

/// Lightweight input decoration helper for the halt-reason dialog.
InputDecoration formHintDecoration(String hint) => InputDecoration(
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
