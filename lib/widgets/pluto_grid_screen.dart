// PlutoGridScreen<T> — the shared read-only grid screen skeleton
// (PORTING.md §6). Every read-only list screen (items, customers,
// suppliers, purchase orders, …) wires the same plumbing: a
// `PlutoGridStateManager` fed by clear+append from a Riverpod provider,
// localized columns built once, F2/Enter/double-tap opening the row's
// detail via `rowDetailShortcutActions`, the hidden-id row pattern, and
// the error-panel-or-grid body. This mixin owns that plumbing; the
// screen supplies the data mapping
// (columns, row mapper, detail opener) and its own toolbar.
//
// `T` is the grid's row type (Item, PurchaseOrder, Customer, …). Most
// providers expose a plain `List<T>`; the server-paginated screens
// (customers/suppliers) expose a `PagedResponse<T>` envelope — those
// screens override [gridRowsFrom] to unwrap it (one line). The mixin's
// provider-taking helpers accept any provider shape (widened to
// `Object?`), so the only type cast lives in [gridRowsFrom], against
// each screen's own known provider type.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../data/repositories/api_result.dart' show ApiError;
import '../l10n/app_localizations.dart';
import 'grid_column_widths.dart';
import 'pluto_grid_shortcuts.dart';
import 'screen_error_panel.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

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
  ..cells['actions'] ??= PlutoCell(value: '')
  // Every column needs a cell (PlutoGrid's initializeRows null-checks
  // `row.cells[column.field]!` for ALL columns, hidden or not) — the
  // bulk-selection checkbox column is opt-in via [GridBulkSelection],
  // so the cell is only guaranteed on rows built through this helper.
  ..cells[kBulkSelectField] ??= PlutoCell(value: false);

/// The bulk-selection checkbox column's field name.
const String kBulkSelectField = '_bulk';

/// Reads the record id a row carries in its hidden `id` cell (the same
/// cell the detail handlers read); null when the cell is missing.
int? _bulkIdOf(PlutoRow row) =>
    (row.cells['id']?.value as num?)?.toInt();

/// Drives checkbox bulk-selection on a grid: a `ValueNotifier<Set<int>>`
/// of the selected record ids that the bulk action bar listens to. The
/// checked state itself lives in PlutoGrid's native row-checkbox
/// mechanism ([PlutoColumn.enableRowChecked] — header select-all +
/// per-row checkboxes, tri-state header), so [syncFromManager] just
/// mirrors the manager's checked rows into [selected]; the screen shows
/// a bulk action bar (see [BulkActionBar]) while [count] > 0.
///
/// [manager] resolves the live [PlutoGridStateManager] (the grid may not
/// be loaded when the column is built).
class GridBulkSelection {
  GridBulkSelection({required this.manager});

  /// Resolves the live grid manager (or null before the grid loads).
  final PlutoGridStateManager? Function() manager;

  /// The currently selected record ids — listen to this to show/hide the
  /// bulk action bar.
  final ValueNotifier<Set<int>> selected = ValueNotifier(<int>{});

  Set<int> get ids => selected.value;
  int get count => selected.value.length;

  /// Rebuild the selection set from the manager's checked rows. Wire this
  /// to the grid's `onRowChecked` (fires for both row and select-all
  /// toggles) and call it after any programmatic [clear].
  void syncFromManager() {
    final manager = this.manager();
    if (manager == null) return;
    selected.value = {
      for (final row in manager.refRows)
        if (row.checked == true) ?_bulkIdOf(row),
    };
  }

  /// Unchecks every row and empties the selection.
  void clear() {
    if (selected.value.isEmpty) return;
    selected.value = <int>{};
    manager()?.toggleAllRowChecked(false);
  }

  void dispose() => selected.dispose();
}

/// The checkbox column for bulk selection — a narrow first column with
/// PlutoGrid's native select-all header checkbox + per-row checkboxes
/// ([PlutoColumn.enableRowChecked]). The checked state lives in the
/// grid's rows; [bulk.syncFromManager] mirrors it into the notifier the
/// bulk action bar listens to. `readOnly` keeps the cell non-editable
/// while PlutoGrid still renders the checkbox.
PlutoColumn bulkSelectColumn(GridBulkSelection bulk) => PlutoColumn(
  title: '',
  field: kBulkSelectField,
  type: PlutoColumnType.text(),
  // PlutoGrid's native checkbox is a 48px widget (its 0.86 scale is
  // visual-only via Transform), so the column must fit it — tightened
  // paddings keep it narrow.
  width: 56,
  cellPadding: const EdgeInsets.symmetric(horizontal: 2),
  titlePadding: const EdgeInsets.symmetric(horizontal: 2),
  readOnly: true,
  enableRowChecked: true,
  enableSorting: false,
  enableContextMenu: false,
  enableFilterMenuItem: false,
  enableHideColumnMenuItem: false,
  enableSetColumnsMenuItem: false,
);

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

/// Theme-aware PlutoGrid configuration: maps M3 [ColorScheme] tokens
/// into PlutoGrid's [PlutoGridStyleConfig] so the grid visually matches
/// the rest of the app.
///
/// `compact: true` renders the denser report-grid variant — 34px rows
/// instead of PlutoGrid's 45px default, a slimmer header, tighter cell
/// padding and 13px cell text. Read-only financial reports fit far more
/// rows per screen; CRUD list screens keep the roomier default.
PlutoGridConfiguration plutoGridConfigurationFor(
  BuildContext context, {
  PlutoGridShortcut? shortcut,
  bool compact = false,
}) {
  final sc = shortcut ?? const PlutoGridShortcut();
  final scheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;

  return PlutoGridConfiguration(
    shortcut: sc,
    style: PlutoGridStyleConfig(
      gridBackgroundColor: scheme.surface,
      rowColor: scheme.surface,
      evenRowColor: scheme.surfaceContainerLow,
      oddRowColor: scheme.surface,
      activatedColor: scheme.primaryContainer.withValues(alpha: 0.3),
      checkedColor: scheme.primaryContainer.withValues(alpha: 0.2),
      cellColorInEditState: scheme.surfaceContainerHighest,
      cellColorInReadOnlyState: scheme.surfaceContainerLow,
      dragTargetColumnColor: scheme.primaryContainer.withValues(alpha: 0.3),
      menuBackgroundColor: scheme.surface,
      gridBorderColor: scheme.outlineVariant,
      borderColor: scheme.outlineVariant,
      activatedBorderColor: scheme.primary,
      inactivatedBorderColor: scheme.outlineVariant,
      iconColor: scheme.onSurfaceVariant,
      disabledIconColor: scheme.onSurface.withValues(alpha: 0.12),
      iconSize: compact ? 16 : 18,
      rowHeight:
          compact ? kCompactGridRowHeight : PlutoGridSettings.rowHeight,
      columnHeight:
          compact ? kCompactGridHeaderHeight : PlutoGridSettings.rowHeight,
      columnFilterHeight:
          compact ? kCompactGridHeaderHeight : PlutoGridSettings.rowHeight,
      defaultCellPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 8)
          : PlutoGridSettings.cellPadding,
      columnTextStyle: textTheme.titleSmall?.copyWith(
        color: scheme.onSurface,
        decoration: TextDecoration.none,
        fontWeight: FontWeight.w600,
      ) ?? const TextStyle(),
      cellTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
        fontSize: compact ? 13 : null,
      ) ?? const TextStyle(),
      gridBorderRadius: AppBorderRadius.smRadius,
      gridPopupBorderRadius: AppBorderRadius.smRadius,
    ),
  );
}

/// Row/header heights for the compact (`compact: true`) grid style —
/// denser than [PlutoGridSettings.rowHeight] (45px).
const double kCompactGridRowHeight = 34;
const double kCompactGridHeaderHeight = 40;

/// Upper bound for content auto-fitting: a very long free-text cell
/// (remarks, narration) must not swallow the whole grid width — it
/// ellipsizes past this and can be widened by dragging.
const double kAutoFitMaxColumnWidth = 480;

/// Resizes every visible, default-rendered column of [stateManager] to
/// fit its content: the widest of the header title and the current rows'
/// formatted cell values (number/date formats applied), plus padding and
/// a small gutter. PlutoGrid's built-in [PlutoAutoSizeMode] only shares
/// the viewport between columns (equal/scale) — it never measures
/// content, which is what read-only report grids need.
///
/// Safe to call from `onLoaded` (PlutoGrid fires it post-frame) or after
/// appending a new dataset. Skips hidden columns and custom-rendered
/// ones (the `#` / ⋮ renderer columns don't measure reliably), clamps to
/// [kAutoFitMaxColumnWidth], and no-ops per column within 1px so calling
/// it repeatedly is cheap.
///
/// Auto-fit only grows columns when there is slack in the viewport so
/// that the total width never pushes right-hand columns
/// (status badges, actions) past the grid edge where PlutoGrid's
/// horizontal virtualization would never build them.
void autoFitPlutoColumns(PlutoGridStateManager stateManager) {
  final style = stateManager.configuration.style;

  /// Rows measured per column: measuring every row × every column is
  /// O(rows × cols) TextPainter layouts (10k layouts for 1000×10), which
  /// stalls the UI on every data refresh. A 50-row sample keeps the
  /// worst case at ~500 layouts while still reflecting typical content
  /// widths (SHORTCOMINGS-FIX 7.2).
  const int sampleLimit = 50;
  final sampleRows = stateManager.refRows.length <= sampleLimit
      ? stateManager.refRows
      : stateManager.refRows.take(sampleLimit);

  // Text width memo — formatted cell values repeat heavily (statuses,
  // numbers, dates), so each unique string is laid out once per pass.
  final measuredCache = <String, double>{};

  double measuredWidth(String text, TextStyle textStyle) {
    final key = '${textStyle.fontSize}|${textStyle.fontWeight}|$text';
    final cached = measuredCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    measuredCache[key] = width;
    return width;
  }

  // Snapshot current widths and compute ideal content-based widths.
  final widths = <PlutoColumn, double>{};
  final ideals = <PlutoColumn, double>{};
  for (final column in stateManager.columns) {
    if (column.hide) continue;
    final current = column.width;
    widths[column] = current;
    if (column.renderer != null) {
      ideals[column] = current;
      continue;
    }
    var widest = measuredWidth(column.title, style.columnTextStyle);
    for (final row in sampleRows) {
      final value = row.cells[column.field]?.value;
      if (value == null) continue;
      widest = math.max(
        widest,
        measuredWidth(
          column.formattedValueForDisplay(value),
          style.cellTextStyle,
        ),
      );
    }
    final padding = column.cellPadding ?? style.defaultCellPadding;
    ideals[column] =
        (widest + padding.horizontal + 12).clamp(column.minWidth, kAutoFitMaxColumnWidth);
  }

  // Compute the viewport budget: maxWidth is the grid's available width;
  // bodyPadding adds the left/right inset.  Null → fall back to
  // unbounded behaviour (current: no constraint, wider columns OK).
  final vp = stateManager.maxWidth;
  if (vp == null || vp <= 0) {
    // Viewport unknown — fall back to unbounded per-column resize.
    for (final entry in ideals.entries) {
      final column = entry.key;
      final target = entry.value;
      if ((target - column.width).abs() < 1) continue;
      stateManager.resizeColumn(column, target - column.width);
    }
    return;
  }

  // Only grow within available slack so the total never exceeds the
  // viewport (which would push non-renderer columns off-screen).
  final currentTotal = widths.values.fold<double>(0, (s, w) => s + w);
  final slack = vp - currentTotal;
  if (slack <= 0) return; // no free space — leave hand-tuned widths

  final requests = <PlutoColumn, double>{};
  for (final entry in ideals.entries) {
    final delta = entry.value - widths[entry.key]!;
    if (delta > 1) requests[entry.key] = delta;
  }
  if (requests.isEmpty) return;

  final totalRequested = requests.values.fold<double>(0, (s, d) => s + d);
  final factor = math.min(1.0, slack / totalRequested);

  for (final entry in requests.entries) {
    final grow = entry.value * factor;
    if (grow < 1) continue;
    stateManager.resizeColumn(entry.key, grow);
  }
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
  GridColumnWidths? _widthTracker;

  /// The hidden id column field carrying the row's record id.
  static const _idField = 'id';

  /// Storage key under which this screen's dragged column widths are
  /// persisted ([GridColumnWidths]). Defaults to the concrete State's
  /// runtime type; override with a stable string if the class may be
  /// renamed.
  String get gridColumnKey => runtimeType.toString();

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

  /// Override to `true` to prepend the bulk-selection checkbox column
  /// (with a select-all header checkbox) and enable the bulk action bar
  /// (SHORTCOMINGS-FIX 4.4). The screen watches [bulkSelection] to show
  /// the bar; selection resets whenever the grid rows are replaced
  /// (page/filter/refresh).
  bool get enableBulkSelection => false;

  /// The bulk-selection state for this grid ([GridBulkSelection]). Only
  /// meaningful when [enableBulkSelection] is true; always disposed with
  /// the State.
  late final GridBulkSelection bulkSelection = GridBulkSelection(
    manager: () => gridStateManager,
  );

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
    // Pinned to the right edge — the ⋮ menu stays reachable when the
    // grid scrolls horizontally (PlutoGrid unfreezes automatically only
    // when the non-frozen columns total ≤ 200px, its built-in guard).
    frozen: PlutoColumnFrozen.end,
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
                // Flexible so longer action labels (e.g. "Return to
                // Supplier") shrink instead of overflowing the popup.
                Flexible(
                  child: Text(
                    entry.label,
                    overflow: TextOverflow.ellipsis,
                    style: entry.color == null
                        ? null
                        : TextStyle(color: entry.color),
                  ),
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
        if (enableBulkSelection) bulkSelectColumn(bulkSelection),
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
        compact: true,
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
      // Rows are being replaced wholesale — a selection made against the
      // previous page/filter no longer maps to visible rows, so reset it.
      bulkSelection.clear();
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in gridRowsFrom(value.value).indexed)
          withSerialCell(gridRowFor(row), index),
      ]);
      scheduleColumnAutoFit(manager);
    }
  }

  /// Re-fit column widths after fresh rows land (post-frame:
  /// resizeColumn notifies listeners and provider callbacks can fire
  /// during build). Runs under the width tracker's programmatic guard and
  /// re-applies saved widths afterwards, so a refresh never overwrites
  /// what the user dragged.
  void scheduleColumnAutoFit(PlutoGridStateManager manager) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(gridStateManager, manager)) return;
      final tracker = _widthTracker;
      if (tracker != null) {
        tracker.programmaticPass(() => autoFitPlutoColumns(manager));
      } else {
        autoFitPlutoColumns(manager);
      }
    });
  }

  @override
  void dispose() {
    bulkSelection.dispose();
    _widthTracker?.dispose();
    super.dispose();
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

    // The grid fills the space. The error-panel path in gridScreenBody
    // returns before this.
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
                if (!mounted) return;
                setState(() {});
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
                // Start persisting/restoring dragged widths — attached
                // last so its restore pass queues behind the auto-fit
                // this sync just scheduled.
                _widthTracker?.dispose();
                _widthTracker = GridColumnWidths.attach(
                  stateManager: event.stateManager,
                  screenKey: gridColumnKey,
                );
              },
              onSorted: onGridSorted,
              onRowChecked: (_) => bulkSelection.syncFromManager(),
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
      ],
    );
  }
}
