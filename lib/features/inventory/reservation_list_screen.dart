// Reservation list screen — shows active stock reservations
// (`GET /inventory/reservations`) with release action.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../data/models/stock_reservation.dart' show ReservationStatus, StockReservation;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor;

class ReservationListScreen extends ConsumerStatefulWidget {
  const ReservationListScreen({super.key});

  @override
  ConsumerState<ReservationListScreen> createState() =>
      _ReservationListScreenState();
}

class _ReservationListScreenState extends ConsumerState<ReservationListScreen> {
  List<StockReservation> _reservations = const [];
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
        .getReservations();
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _reservations = data;
          _loading = false;
        });
      case ApiFailure(:final error):
        setState(() {
          _error = error.message;
          _loading = false;
        });
    }
  }

  Future<void> _release(StockReservation reservation) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await ref
        .read(inventoryRepositoryProvider)
        .releaseReservation(reservation.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.commonSaved);
        _load();
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (ReservationStatus.fromString(status)) {
      ReservationStatus.active => const Color(0xff16a34a),
      ReservationStatus.released => scheme.onSurfaceVariant,
      ReservationStatus.consumed => scheme.primary,
      ReservationStatus.expired => scheme.error,
      
    };
  }

  String _statusLabel(AppLocalizations l10n, String status) => switch (ReservationStatus.fromString(status)) {
    ReservationStatus.active => 'Active',
    ReservationStatus.released => 'Released',
    ReservationStatus.consumed => 'Consumed',
    ReservationStatus.expired => 'Expired',
    
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Reservations'),
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
              : _reservations.isEmpty
                  ? Center(child: Text(l10n.reportsNodata))
                  : PlutoGrid(
                      configuration: plutoGridConfigurationFor(context, compact: true),
                      columns: _columns(l10n),
                      rows: [
                        for (final r in _reservations) _toRow(r),
                      ],
                      onLoaded: (e) {
                        e.stateManager.setSelectingMode(PlutoGridSelectingMode.none);
                        autoFitPlutoColumns(e.stateManager);
                        _widthTracker?.dispose();
                        _widthTracker = GridColumnWidths.attach(
                          stateManager: e.stateManager,
                          screenKey: 'reservation_list',
                        );
                      },
                    ),
    );
  }

  List<PlutoColumn> _columns(AppLocalizations l10n) => [
    PlutoColumn(
      title: 'Item',
      field: 'item_code',
      type: PlutoColumnType.text(),
      width: 100,
      readOnly: true,
    ),
    PlutoColumn(
      title: 'Item Name',
      field: 'item_name',
      type: PlutoColumnType.text(),
      width: 200,
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
      title: 'Batch',
      field: 'batch_no',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
    ),
    PlutoColumn(
      title: 'Qty Reserved',
      field: 'qty',
      type: PlutoColumnType.number(format: '#,###.##'),
      width: 100,
      readOnly: true,
      textAlign: PlutoColumnTextAlign.end,
      titleTextAlign: PlutoColumnTextAlign.end,
    ),
    PlutoColumn(
      title: 'Reference',
      field: 'ref',
      type: PlutoColumnType.text(),
      width: 140,
      readOnly: true,
      renderer: (ctx) {
        final r = ctx.row.cells['_reservation']!.value as StockReservation;
        return Text('${r.referenceDocType} #${r.referenceDocNo}');
      },
    ),
    PlutoColumn(
      title: 'Status',
      field: 'status',
      type: PlutoColumnType.text(),
      width: 100,
      readOnly: true,
      renderer: (ctx) {
        final status = ctx.cell.value as String? ?? '';
        return Center(
          child: Chip(
            visualDensity: VisualDensity.compact,
            label: Text(
              _statusLabel(l10n, status),
              style: TextStyle(color: _statusColor(context, status), fontSize: 11),
            ),
          ),
        );
      },
    ),
    PlutoColumn(
      title: 'Created',
      field: 'created',
      type: PlutoColumnType.text(),
      width: 120,
      readOnly: true,
    ),
    PlutoColumn(
      title: l10n.commonActions,
      field: 'actions',
      type: PlutoColumnType.text(),
      width: 100,
      enableSorting: false,
      renderer: (ctx) {
        final r = ctx.row.cells['_reservation']!.value as StockReservation;
        if (!r.isActive) return const SizedBox.shrink();
        return IconButton(
          tooltip: 'Release',
          icon: const Icon(Icons.lock_open_outlined, size: 18),
          onPressed: () => _release(r),
        );
      },
    ),
  ];

  PlutoRow _toRow(StockReservation r) {
    return PlutoRow(
      cells: {
        'item_code': PlutoCell(value: r.itemCode ?? ''),
        'item_name': PlutoCell(value: r.itemName ?? ''),
        'location_code': PlutoCell(value: r.locationCode ?? ''),
        'batch_no': PlutoCell(value: r.batchNo ?? ''),
        'qty': PlutoCell(value: r.quantityReserved),
        '_reservation': PlutoCell(value: r),
        'ref': PlutoCell(value: ''),
        'status': PlutoCell(value: r.status),
        'created': PlutoCell(value: r.createdAt),
        'actions': PlutoCell(value: ''),
      },
    );
  }
}
