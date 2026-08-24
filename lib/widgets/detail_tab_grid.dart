// Self-contained read-only PlutoGrid for the detail tabs (Invoices /
// Ledger / Payments / POs). Each tab owns its provider watch and
// row/action state; this widget owns the grid plumbing: localized columns
// built once, rows synced whenever the parent's [data] identity changes
// (provider refetch), the hidden `data` cell pattern for action menus,
// and the shared `#` serial column (same convention as every other grid
// in the app).
//
// The parent passes a NEW [data] list instance only when the underlying
// provider value changed — the widget compares identity, so parent
// rebuilds that reuse the same provider value never touch the grid.

import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../l10n/app_localizations.dart';
import 'pluto_grid_screen.dart'
    show
        autoFitPlutoColumns,
        plutoGridConfigurationFor,
        serialGridColumn,
        withSerialCell;

/// A read-only PlutoGrid over [data] for the detail tabs.
class DetailTabGrid<T> extends StatefulWidget {
  const DetailTabGrid({
    super.key,
    required this.data,
    required this.buildColumns,
    required this.gridRowFor,
    this.hiddenFields = const [],
    this.rowColorCallback,
    this.noRowsWidget,
  });

  /// The tab's rows. Identity-compared in [State.didUpdateWidget].
  final List<T> data;

  /// Builds the localized column set (called once from
  /// [State.didChangeDependencies]; cells needing theme colors wrap
  /// themselves in a [Builder]).
  final List<PlutoColumn> Function(AppLocalizations l10n) buildColumns;

  /// Maps one row to a [PlutoRow] (cells keyed by the column fields).
  final PlutoRow Function(T row) gridRowFor;

  /// Extra hidden cells in addition to the `id` convention (e.g. a
  /// hidden `data` cell carrying the row object for action menus).
  final List<String> hiddenFields;

  final PlutoRowColorCallback? rowColorCallback;

  final Widget? noRowsWidget;

  @override
  State<DetailTabGrid<T>> createState() => _DetailTabGridState<T>();
}

class _DetailTabGridState<T> extends State<DetailTabGrid<T>> {
  PlutoGridStateManager? _manager;
  late List<PlutoColumn> _columns;
  PlutoGridConfiguration _configuration = const PlutoGridConfiguration();
  Brightness? _configurationBrightness;
  bool _columnsReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsReady) {
      _columns = [
        serialGridColumn(),
        ...widget.buildColumns(AppLocalizations.of(context)!),
      ];
      _columnsReady = true;
    }
    // Rebuild the grid configuration when the theme brightness flips so
    // dark mode is respected (PlutoGrid re-applies it in
    // didUpdateWidget).
    final brightness = Theme.of(context).brightness;
    if (_configurationBrightness != brightness) {
      _configuration = plutoGridConfigurationFor(context, compact: true);
      _configurationBrightness = brightness;
    }
  }

  @override
  void didUpdateWidget(covariant DetailTabGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Provider values are stable instances — only refetch/replace changes
    // the identity, so this never loops on ordinary parent rebuilds.
    if (!identical(widget.data, oldWidget.data)) _sync();
  }

  void _sync() {
    final manager = _manager;
    if (manager == null) return;
    manager.removeAllRows();
    manager.appendRows([
      for (final (index, row) in widget.data.indexed)
        withSerialCell(widget.gridRowFor(row), index),
    ]);
    // Column widths re-fit to the fresh content. Post-frame: resizeColumn
    // notifies listeners and didUpdateWidget runs during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_manager, manager)) return;
      autoFitPlutoColumns(manager);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlutoGrid(
      columns: _columns,
      configuration: _configuration,
      // NOTE: must be a *growable* list — PlutoGrid's FilteredList wraps
      // the passed rows and appends to it.
      rows: <PlutoRow>[],
      onLoaded: (event) {
        _manager = event.stateManager;
        for (final field in widget.hiddenFields) {
          _manager?.hideColumn(
            _columns.firstWhere((c) => c.field == field),
            true,
            notify: false,
          );
        }
        _sync();
      },
      rowColorCallback: widget.rowColorCallback,
      noRowsWidget:
          widget.noRowsWidget ??
          Center(
            child: Text(
              AppLocalizations.of(context)!.commonNoresults,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
    );
  }
}
