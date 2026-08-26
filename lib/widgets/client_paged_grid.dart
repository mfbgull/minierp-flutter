// ClientPagedGrid<T> — a read-only PlutoGrid with **client-side** paging
// for screens whose endpoints return the full row set (report grids,
// ledger tabs with grouped rows, …). The grid shows one page at a time
// and a [ServerPaginationBar] renders beneath it — the same "Page X of Y
// · N <label>" chrome as the server-paginated screens (sales, suppliers,
// …), but the page math is computed here over the full [data] list.
//
// This is the client-side counterpart to the mixin/`ServerPaginationBar`
// pair used by server-paginated screens: the bar itself is identical, so
// paging feels the same everywhere. Server-paginated tabs (invoices,
// payments, POs) keep the server bar wired to their paged providers; this
// widget serves the reports and the grouped ledger tabs where the data
// arrives as one array.
//
// Rows are fed through the PlutoGridStateManager (clear + append) so the
// grid only reads its `rows` prop in initState; the widget re-syncs when
// the parent passes a NEW [data] list identity (provider refetch) and
// clamps the current page when the list shrinks (e.g. a refiltered
// report drops pages).

import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../l10n/app_localizations.dart';
import 'grid_column_widths.dart';
import 'pagination_bar.dart' show ServerPaginationBar;
import 'pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor, withSerialCell;

/// A read-only, client-paginated PlutoGrid over [data].
class ClientPagedGrid<T> extends StatefulWidget {
  const ClientPagedGrid({
    super.key,
    required this.data,
    required this.columns,
    required this.gridRowFor,
    required this.itemLabel,
    this.hiddenFields = const [],
    this.onRowDoubleTap,
    this.rowColorCallback,
    this.isLoading,
    this.noRowsWidget,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
    this.compact = true,
    this.autoFitColumns = true,
    this.widthKey,
  });

  /// The full row set. Identity-compared in [State.didUpdateWidget] so
  /// parent rebuilds reusing the same list never touch the grid.
  final List<T> data;

  /// The localized column set (built once by the caller).
  final List<PlutoColumn> columns;

  /// Maps one row to a [PlutoRow] (cells keyed by the column fields).
  /// The row model is additionally stored in a hidden `data` cell for
  /// [onRowDoubleTap] — callers don't need to add it themselves.
  final PlutoRow Function(T row) gridRowFor;

  /// Localized plural label for the bar's item count (e.g.
  /// `l10n.customreportsRows` / `l10n.commonEntries`).
  final String itemLabel;

  /// Extra hidden cells (besides the hidden `data` model cell), e.g. a
  /// lookup `key` column for a double-tap dialog.
  final List<String> hiddenFields;

  /// Double-tap handler receiving the tapped row's model.
  final ValueChanged<T>? onRowDoubleTap;

  final PlutoRowColorCallback? rowColorCallback;

  /// Optional loading flag — toggles the grid's loading overlay when the
  /// parent refetches (PlutoGrid has no other way to show loading).
  final bool? isLoading;

  final Widget? noRowsWidget;

  /// Padding around the grid itself (the bar sits below it, flush).
  final EdgeInsets padding;

  /// Denser grid variant (34px rows, 13px cell text) — see
  /// [plutoGridConfigurationFor].
  final bool compact;

  /// Size every column to its content when a new dataset lands (first
  /// load and provider refetches; paging alone keeps widths stable).
  /// Pass `compact: false` to restore PlutoGrid's roomier defaults.
  final bool autoFitColumns;

  /// Storage key for persisted dragged column widths
  /// ([GridColumnWidths]) — null disables persistence. Must be unique
  /// per grid usage (e.g. `'report_ar_aging'`).
  final String? widthKey;

  @override
  State<ClientPagedGrid<T>> createState() => _ClientPagedGridState<T>();
}

class _ClientPagedGridState<T> extends State<ClientPagedGrid<T>> {
  PlutoGridStateManager? _manager;
  int _page = 1;
  int _limit = 10;
  GridColumnWidths? _widthTracker;

  void _autoFit(PlutoGridStateManager manager) {
    final tracker = _widthTracker;
    if (tracker != null) {
      // Guarded: auto-fit must not record as user edits, and dragged
      // widths are re-applied over the fitted result.
      tracker.programmaticPass(() => autoFitPlutoColumns(manager));
    } else {
      autoFitPlutoColumns(manager);
    }
  }

  @override
  void dispose() {
    _widthTracker?.dispose();
    super.dispose();
  }

  int get _totalPages =>
      widget.data.isEmpty ? 1 : (widget.data.length + _limit - 1) ~/ _limit;

  List<T> get _pageRows {
    final start = (_page - 1) * _limit;
    if (start >= widget.data.length) return <T>[];
    final end = (start + _limit).clamp(0, widget.data.length);
    return widget.data.sublist(start, end);
  }

  PlutoRow _rowFor(T row, int index) {
    final plutoRow = widget.gridRowFor(row);
    // Carry the model in a hidden cell so double-tap can hand it back
    // without a lookup map (same convention as the detail-tab grids).
    plutoRow.cells['data'] = PlutoCell(value: row);
    return withSerialCell(plutoRow, index);
  }

  void _sync() {
    final manager = _manager;
    if (manager == null) return;
    manager.removeAllRows();
    manager.appendRows([
      for (final (index, row) in _pageRows.indexed) _rowFor(row, index),
    ]);
  }

  @override
  void didUpdateWidget(covariant ClientPagedGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.data, oldWidget.data)) {
      // The list shrank or grew — clamp the page so a refiltered report
      // doesn't leave the user stranded past the last page.
      if (_page > _totalPages) _page = _totalPages < 1 ? 1 : _totalPages;
      _sync();
      // Resize runs post-frame: didUpdateWidget is inside build, and
      // resizeColumn notifies listeners.
      if (widget.autoFitColumns && _manager != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _manager != null) _autoFit(_manager!);
        });
      }
    }
    if (widget.isLoading != oldWidget.isLoading) {
      _manager?.setShowLoading(widget.isLoading ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: widget.padding,
            child: PlutoGrid(
              columns: widget.columns,
              configuration: plutoGridConfigurationFor(
                context,
                compact: widget.compact,
              ),
              // NOTE: must be a *growable* list — PlutoGrid's FilteredList
              // wraps the passed rows and appends to it.
              rows: <PlutoRow>[],
              onLoaded: (event) {
                _manager = event.stateManager;
                // Hide the extra lookup cells (the `data` model cell is
                // not a declared column, so it needs no hiding).
                for (final field in widget.hiddenFields) {
                  _manager?.hideColumn(
                    widget.columns.firstWhere((c) => c.field == field),
                    true,
                    notify: false,
                  );
                }
                _manager?.setShowLoading(widget.isLoading ?? false);
                _sync();
                if (widget.autoFitColumns) _autoFit(_manager!);
                // Attach last so the restore pass queues behind the
                // initial fit above.
                if (widget.widthKey != null) {
                  _widthTracker?.dispose();
                  _widthTracker = GridColumnWidths.attach(
                    stateManager: event.stateManager,
                    screenKey: widget.widthKey!,
                  );
                }
              },
              onRowDoubleTap: widget.onRowDoubleTap == null
                  ? null
                  : (event) {
                      final row = event.row.cells['data']?.value as T?;
                      if (row != null) widget.onRowDoubleTap!(row);
                    },
              rowColorCallback: widget.rowColorCallback,
              noRowsWidget:
                  widget.noRowsWidget ??
                  Center(
                    child: Text(
                      l10n.commonNoresults,
                      style: TextStyle(color: scheme.outline),
                    ),
                  ),
            ),
          ),
        ),
        if (widget.data.isNotEmpty)
          ServerPaginationBar(
            page: _page,
            totalPages: _totalPages,
            totalItems: widget.data.length,
            hasNext: _page < _totalPages,
            hasPrev: _page > 1,
            limit: _limit,
            itemLabel: widget.itemLabel,
            onPageChanged: (page) {
              setState(() => _page = page);
              _sync();
            },
            onLimitChanged: (limit) {
              setState(() {
                _limit = limit;
                _page = 1;
              });
              _sync();
            },
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
