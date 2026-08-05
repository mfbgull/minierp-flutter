// Shared PlutoGrid keyboard shortcuts — the Flutter counterpart of the web
// app's `useInvoiceV2Keyboard` hooks. F2 / Enter on a focused row opens
// that row's detail view (the same path as a double tap). Registered
// through PlutoGrid's own `configuration.shortcut` extension point
// (checked before the default actions), so arrow / Tab navigation and all
// other default bindings keep working. Used by the read-only items and
// customers grids (PORTING.md §6).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pluto_grid/pluto_grid.dart';

/// Opens the focused row's detail — shared by the read-only grids. Reads
/// the row's hidden `id` cell; the caller's grid must carry the record id
/// in a cell named `id` (the screens hide that column after load).
class OpenRowDetailAction extends PlutoGridShortcutAction {
  const OpenRowDetailAction(this.onOpenDetail);

  /// Invoked with the focused row's id when the shortcut fires.
  final void Function(int rowId) onOpenDetail;

  @override
  void execute({
    required PlutoKeyManagerEvent keyEvent,
    required PlutoGridStateManager stateManager,
  }) {
    // While a cell is being edited, Enter belongs to the editor (commit),
    // not to detail navigation — keeps the action safe for a future
    // editable grid.
    if (stateManager.isEditing) return;
    // Read the hidden id cell defensively (a `num?` read keeps the cast
    // from ever throwing if a future column change stores a double).
    final id = (stateManager.currentRow?.cells['id']?.value as num?)?.toInt();
    if (id == null || id <= 0) return;
    onOpenDetail(id);
  }
}

/// The shortcut map for the read-only grids: F2 / Enter / NumpadEnter open
/// the focused row's detail; every default binding (arrows, Tab, Home/End,
/// Ctrl+C/V, F3/F4 …) is preserved. `PlutoGridShortcut.handle()` executes
/// the first matching entry, so the detail actions must both precede and
/// survive the defaults merge — a map-literal spread would let the
/// defaults overwrite the same-key entries, hence the explicit
/// re-assertion afterwards.
Map<ShortcutActivator, PlutoGridShortcutAction> rowDetailShortcutActions(
  void Function(int rowId) onOpenDetail,
) {
  final open = OpenRowDetailAction(onOpenDetail);
  final actions = <ShortcutActivator, PlutoGridShortcutAction>{
    LogicalKeySet(LogicalKeyboardKey.f2): open,
    LogicalKeySet(LogicalKeyboardKey.enter): open,
    LogicalKeySet(LogicalKeyboardKey.numpadEnter): open,
    ...PlutoGridShortcut.defaultActions,
  };
  actions[LogicalKeySet(LogicalKeyboardKey.f2)] = open;
  actions[LogicalKeySet(LogicalKeyboardKey.enter)] = open;
  actions[LogicalKeySet(LogicalKeyboardKey.numpadEnter)] = open;
  return actions;
}
