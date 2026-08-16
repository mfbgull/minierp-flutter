// PlutoGridScreen<T> — the shared read-only grid screen skeleton
// (PORTING.md §6). Every read-only list screen (items, customers,
// suppliers, purchase orders, …) wires the same plumbing: a
// `PlutoGridStateManager` fed by clear+append from a Riverpod provider,
// localized columns built once, F2/Enter/double-tap opening the row's
// detail via `rowDetailShortcutActions`, the hidden-id row pattern, the
// error-panel-or-grid body and the [GridStatusBar] beneath the grid.
// This mixin owns that plumbing; the screen supplies the data mapping
// (columns, row mapper, detail opener) and its own toolbar.
//
// `T` is the grid's row type (Item, PurchaseOrder, Customer, …). Most
// providers expose a plain `List<T>`; the server-paginated screens
// (customers/suppliers) expose a `PagedResponse<T>` envelope — those
// screens override [gridRowsFrom] to unwrap it (one line). The mixin's
// provider-taking helpers accept any provider shape (widened to
// `Object?`), so the only type cast lives in [gridRowsFrom], against
// each screen's own known provider type.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../data/repositories/api_result.dart' show ApiError;
import '../l10n/app_localizations.dart';
import 'grid_status_bar.dart';
import 'pluto_grid_shortcuts.dart';
import 'screen_error_panel.dart';

/// The shared `#` serial-number column prepended to every grid (the
/// invoice line grid's `#` column is the in-app convention). The renderer
/// reads the cell's current row index, so the numbers stay correct under
/// client-side sorting/filtering; the `serial` cell value is never read.
PlutoColumn serialGridColumn() => PlutoColumn(
  title: '#',
  field: 'serial',
  type: PlutoColumnType.number(),
  width: 48,
  readOnly: true,
  enableContextMenu: false,
  renderer: (ctx) => Center(
    child: Text(
      '${ctx.rowIdx + 1}',
      style: const TextStyle(color: Colors.black54, fontSize: 13),
    ),
  ),
);

/// Adds the row's `serial` cell (PlutoGrid requires a cell per column;
/// the renderer ignores the value and shows the live row index). Also
/// guarantees the `actions` cell exists — the per-row ⋮ menu column is
/// appended by the mixin when a screen opts in ([PlutoGridScreen.hasRowActions]),
/// and PlutoGrid crashes on a row missing a cell for a declared column.
/// `??=` keeps a screen-supplied `actions` cell (e.g. one already set by
/// a custom grid) intact.
PlutoRow withSerialCell(PlutoRow row, int index) => row
  ..cells['serial'] = PlutoCell(value: index + 1)
  ..cells['actions'] ??= PlutoCell(value: '');

/// A single entry in a grid row's ⋮ actions menu.
class GridRowAction {
  const GridRowAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Optional tint (destructive actions pass `error`).
  final Color? color;
}

/// Theme-aware PlutoGrid configuration: PlutoGrid ships a light default
/// and a separate `PlutoGridConfiguration.dark` — it does *not* follow
/// the ambient Theme brightness on its own. Every grid screen routes
/// through this so dark mode is respected app-wide.
PlutoGridConfiguration plutoGridConfigurationFor(
  BuildContext context, {
  PlutoGridShortcut? shortcut,
}) {
  final sc = shortcut ?? const PlutoGridShortcut();
  return Theme.of(context).brightness == Brightness.dark
      ? PlutoGridConfiguration.dark(shortcut: sc)
      : PlutoGridConfiguration(shortcut: sc);
}

/// Mixin over any [ConsumerState] providing the read-only grid skeleton.
/// `T` is the provider's row type; `S` the concrete screen widget — the
/// mixin's `on` clause must carry the *same* type argument as the state's
/// own superclass, because the analyzer flags a mixin
/// `on ConsumerState<ConsumerStatefulWidget>` applied to
/// `ConsumerState<ConcreteScreen>` as `conflicting_generic_interfaces`
/// (it treats the `on`-clause interface as distinct from the concrete
/// extends type).
mixin PlutoGridScreen<T, S extends ConsumerStatefulWidget> on ConsumerState<S> {
  PlutoGridStateManager? gridStateManager;
  late List<PlutoColumn> gridColumns;
  bool _columnsReady = false;
  PlutoGridConfiguration _gridConfiguration = const PlutoGridConfiguration();
  Brightness? _configurationBrightness;

  /// The hidden id column field carrying the row's record id.
  static const _idField = 'id';

  /// Build the localized column set once (called from
  /// [didChangeDependencies]).
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n);

  /// F2 / Enter / double-tap handler for a grid row's record id.
  void openRowDetail(int rowId);

  /// Map one provider row to a [PlutoRow] (cells keyed by the column
  /// fields — the record id must live in the `id` cell).
  PlutoRow gridRowFor(T row);

  /// Unwrap the grid rows from a provider value. The default handles the
  /// plain `List<T>` shape; the server-paginated screens
  /// (customers/suppliers) override to unwrap their `PagedResponse<T>`
  /// envelope. This is the single type cast each screen owns, against its
  /// own known provider type.
  Iterable<T> gridRowsFrom(Object? value) => value as List<T>;

  /// Optional hook — server-paginated screens map grid column sorts to
  /// server-side sort providers here (e.g. resetting to page 1). The
  /// default is a no-op: lists sorted client-side need nothing.
  void onGridSorted(PlutoGridOnSortedEvent event) {}

  /// Extra hidden columns in addition to the record-id column — e.g. a
  /// screen that also hides an item/warehouse code column. Defaults to
  /// just the record-id field, which every screen carries.
  List<String> get hiddenGridColumnFields => const [_idField];

  /// Override to `true` to append the per-row ⋮ actions column to the
  /// grid (the last column, like the sales/customers grids).
  bool get hasRowActions => false;

  /// Build the row's ⋮ menu entries. Called when the cell renders (to
  /// decide show/hide) and again when the menu opens, so actions always
  /// reflect fresh row state. Return null/empty to hide the button for
  /// that row. The screen reads its model back from the row's hidden
  /// `data` cell (set in [gridRowFor]).
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) =>
      null;

  /// The ⋮ actions column — Listener + [showMenu] (the same pattern as
  /// the customers/suppliers grids; a raw Listener reliably catches the
  /// tap inside the PlutoGrid cell).
  PlutoColumn _buildActionsColumn(AppLocalizations l10n) => PlutoColumn(
    title: l10n.commonActions,
    field: 'actions',
    type: PlutoColumnType.text(),
    width: 64,
    readOnly: true,
    enableContextMenu: false,
    enableFilterMenuItem: false,
    enableHideColumnMenuItem: false,
    enableSetColumnsMenuItem: false,
    renderer: (ctx) => Builder(
      builder: (cellContext) {
        final actions = gridRowActionsFor(ctx.row, cellContext);
        if (actions == null || actions.isEmpty) {
          return const SizedBox.shrink();
        }
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _openGridRowMenu(cellContext, ctx.row),
          child: Center(
            child: Icon(
              Icons.more_vert,
              size: 18,
              color: Theme.of(cellContext).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    ),
  );

  /// Opens the row-actions menu anchored at [cellContext], running the
  /// selected [GridRowAction.onTap]. Actions are rebuilt fresh from
  /// [gridRowActionsFor] so the menu reflects the current row state.
  Future<void> _openGridRowMenu(
    BuildContext cellContext,
    PlutoRow row,
  ) async {
    final actions = gridRowActionsFor(row, cellContext);
    if (actions == null || actions.isEmpty) return;
    final box = cellContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(cellContext, rootOverlay: true);
    final action = await showMenu<GridRowAction>(
      context: cellContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        ),
        Offset.zero & overlay.context.size!,
      ),
      items: [
        for (final entry in actions)
          PopupMenuItem(
            value: entry,
            child: Row(
              children: [
                Icon(entry.icon, size: 18, color: entry.color),
                const SizedBox(width: 8),
                Text(
                  entry.label,
                  style: entry.color == null
                      ? null
                      : TextStyle(color: entry.color),
                ),
              ],
            ),
          ),
      ],
    );
    if (action != null && mounted) action.onTap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Column titles are localized — build them once here (lookups of
    // inherited widgets are not allowed before initState completes).
    if (!_columnsReady) {
      // The shared `#` column is prepended here so screens don't repeat
      // the plumbing (their `buildGridColumns` stays focused on data).
      // The per-row ⋮ actions column is appended when the screen opts in.
      gridColumns = [
        serialGridColumn(),
        ...buildGridColumns(AppLocalizations.of(context)!),
        if (hasRowActions)
          _buildActionsColumn(AppLocalizations.of(context)!),
      ];
      _columnsReady = true;
    }
    // Same for the grid configuration: F2/Enter open the focused row's
    // detail. Rebuilt when the theme brightness flips so dark mode is
    // respected (PlutoGrid re-applies the configuration in
    // didUpdateWidget). The shortcut map holds a closure over this
    // State's context, so it must not be recreated after the widget is
    // disposed — didChangeDependencies only runs while mounted, so
    // rebuilding here is safe.
    final brightness = Theme.of(context).brightness;
    if (_configurationBrightness != brightness) {
      _gridConfiguration = plutoGridConfigurationFor(
        context,
        shortcut: PlutoGridShortcut(
          actions: rowDetailShortcutActions(openRowDetail),
        ),
      );
      _configurationBrightness = brightness;
    }
  }

  /// Call from `build()` so provider → grid syncing is automatic. Accepts
  /// any provider whose value [gridRowsFrom] can unwrap.
  void watchGridProvider(FutureProvider<Object?> provider) {
    ref.listen(provider, (previous, next) => syncGridRows(next));
  }

  /// Push provider state into the grid manager (clear + append, with the
  /// loading overlay toggled). No-op until the grid reports `onLoaded`.
  void syncGridRows(AsyncValue<Object?> value) {
    final manager = gridStateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in gridRowsFrom(value.value).indexed)
          withSerialCell(gridRowFor(row), index),
      ]);
    }
  }

  /// The standard body: a full-pane error panel on failure (dropping the
  /// manager handle so a later listener callback never touches the
  /// disposed manager), the grid pane otherwise.
  Widget gridScreenBody(
    AsyncValue<Object?> value, {
    required FutureProvider<Object?> provider,
    PlutoRowColorCallback? rowColorCallback,
    Widget Function()? noRowsWidget,
  }) {
    final errorMessage = switch (value) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      gridStateManager = null;
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(provider),
      );
    }
    return _gridPane(
      provider: provider,
      rowColorCallback: rowColorCallback,
      noRowsWidget: noRowsWidget,
    );
  }

  Widget _gridPane({
    required FutureProvider<Object?> provider,
    PlutoRowColorCallback? rowColorCallback,
    Widget Function()? noRowsWidget,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // The grid fills the space; the keyboard-hint status bar sits beneath
    // it (attached via its top border), exactly where AG-Grid draws its
    // status bar. The bar renders only with the grid — the error panel
    // path in gridScreenBody returns before this.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PlutoGrid(
              columns: gridColumns,
              configuration: _gridConfiguration,
              // NOTE: must be a *growable* list — PlutoGrid's FilteredList
              // wraps the passed rows and appends to it.
              rows: <PlutoRow>[],
              onLoaded: (event) {
                gridStateManager = event.stateManager;
                // The id column exists only to carry the row's record id
                // to the detail handlers — hide it (cells stay readable
                // via `row.cells['id']`, so it survives client-side
                // sorting). Screens may hide extra columns too.
                for (final field in hiddenGridColumnFields) {
                  gridStateManager?.hideColumn(
                    gridColumns.firstWhere((c) => c.field == field),
                    true,
                    notify: false,
                  );
                }
                // Sync any provider state that changed before the grid
                // finished mounting (e.g. the first loading flag).
                syncGridRows(ref.read(provider));
              },
              onSorted: onGridSorted,
              onRowDoubleTap: (event) {
                final id = (event.row.cells[_idField]?.value as num?)?.toInt();
                if (id == null || id <= 0) return;
                openRowDetail(id);
              },
              rowColorCallback: rowColorCallback,
              noRowsWidget:
                  noRowsWidget?.call() ??
                  Center(
                    child: Text(
                      l10n.commonNoresults,
                      style: TextStyle(color: scheme.outline),
                    ),
                  ),
            ),
          ),
        ),
        const GridStatusBar(),
      ],
    );
  }
}
