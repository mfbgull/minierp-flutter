// Dashboard layout controller — the working state behind the dashboard
// customizer (spec §6.2–6.3). Loads the user's active dashboard layout
// (or the curated default when none exists), exposes the block list for
// the strip + panels + dialog to render live, and persists visibility +
// order to the server on Save.
//
// Reuses the existing `dashboard_layouts` block system (repository +
// CRUD endpoints, already built but previously unwired).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_layout.dart'
    show
        DashboardBlock,
        DashboardBlockConfig,
        DashboardBlockSize;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/dashboard_layout_repository.dart'
    show DashboardLayoutRepository, dashboardLayoutRepositoryProvider;
import 'dashboard_kpi_catalog.dart' show kpiCardCatalog, kpiCardById;
import 'dashboard_panel_catalog.dart'
    show cashStripDefinition, panelById, panelCatalog;

/// A block's horizontal position in the strip — the layout system is
/// grid-oriented (x/y/width/height), but the KPI strip is a horizontal
/// list. We map strip order to grid coordinates on save (§5.2).
///
/// Card widths per size preset (spec §6.3): Small 148 / Medium 188
/// (current card) / Large 260. Height stays fixed at 84 across sizes.
const double kKpiCardWidth = 188;
const double kKpiCardHeight = 84;
const double kKpiCardWidthSmall = 148;
const double kKpiCardWidthLarge = 260;

/// Card width for a given size preset.
double kKpiCardWidthFor(DashboardBlockSize? size) => switch (size) {
  DashboardBlockSize.small => kKpiCardWidthSmall,
  DashboardBlockSize.large => kKpiCardWidthLarge,
  _ => kKpiCardWidth,
};

/// Panel flex ratio for a given size preset (spec §6.3): Small = 1,
/// Medium = the catalog's default flex, Large = 3.
int panelFlexFor(int catalogFlex, DashboardBlockSize? size) => switch (size) {
  DashboardBlockSize.small => 1,
  DashboardBlockSize.large => 3,
  _ => catalogFlex,
};

/// Working dashboard-layout state shared by the strip and the dialog.
class DashboardLayoutState {
  const DashboardLayoutState({
    required this.blocks,
    this.layoutId,
    this.dirty = false,
    this.saving = false,
    this.saved = false,
  });

  /// All catalog KPI cards as blocks, in display order, with the
  /// user's visibility flags applied. Hidden cards stay in the list so
  /// the dialog can show them; the strip renders only `visible`.
  final List<DashboardBlock> blocks;

  /// Server layout row id — null until the user saves (first save
  /// POSTs a new layout, later saves PUT it).
  final int? layoutId;

  /// True once a layout exists server-side (POST succeeded).
  final bool saved;

  /// Unsaved visibility/order changes made in this session.
  final bool dirty;

  final bool saving;

  DashboardLayoutState copyWith({
    List<DashboardBlock>? blocks,
    int? layoutId,
    bool? dirty,
    bool? saving,
    bool? saved,
  }) => DashboardLayoutState(
    blocks: blocks ?? this.blocks,
    layoutId: layoutId ?? this.layoutId,
    dirty: dirty ?? this.dirty,
    saving: saving ?? this.saving,
    saved: saved ?? this.saved,
  );
}

/// Loads + mutates the dashboard layout. State is driven by the
/// repository (server), not local prefs — a user's layout follows them
/// across devices (spec: per-user on server).
class DashboardLayoutController
    extends StateNotifier<DashboardLayoutState> {
  DashboardLayoutController(this._repo)
    : super(DashboardLayoutState(blocks: _curatedDefault())) {
    _load();
  }

  final DashboardLayoutRepository _repo;

  /// The curated default layout (§3) — 4 KPI cards + 3 panels + the
  /// cash strip visible, everything else available but off.
  static List<DashboardBlock> _curatedDefault() => [
    // KPI cards first (catalog/dialog order).
    for (var i = 0; i < kpiCardCatalog.length; i++)
      _kpiBlock(
        id: kpiCardCatalog[i].id,
        metric: kpiCardCatalog[i].metric,
        title: kpiCardCatalog[i].labelKey,
        visible: kpiCardCatalog[i].defaultVisible,
        index: i,
      ),
    // Then the 5 panels (row 1 first, then row 2, in dialog order).
    for (var i = 0; i < panelCatalog.length; i++)
      _panelBlock(
        id: panelCatalog[i].id,
        title: panelCatalog[i].labelKey,
        visible: panelCatalog[i].defaultVisible,
        row: panelCatalog[i].row,
        flex: panelCatalog[i].flex,
        index: i,
      ),
    // Cash & bank strip — fixed at the top, show/hide only.
    DashboardBlock(
      id: cashStripDefinition.id,
      type: 'cash',
      title: cashStripDefinition.labelKey,
      x: 0,
      y: 1,
      width: 1,
      height: 1,
      visible: cashStripDefinition.defaultVisible,
      version: 1,
      config: const DashboardBlockConfig(),
    ),
  ];

  static DashboardBlock _kpiBlock({
    required String id,
    required String metric,
    required String title,
    required bool visible,
    required int index,
  }) => DashboardBlock(
    id: id,
    type: 'kpi',
    title: title,
    x: index,
    y: 0,
    width: kKpiCardWidth,
    height: kKpiCardHeight,
    visible: visible,
    version: 1,
    config: DashboardBlockConfig(metric: metric),
  );

  static DashboardBlock _panelBlock({
    required String id,
    required String title,
    required bool visible,
    required int row,
    required int flex,
    required int index,
  }) => DashboardBlock(
    id: id,
    type: 'panel',
    title: title,
    x: index,
    y: row,
    width: flex,
    height: 1,
    visible: visible,
    version: 1,
    config: const DashboardBlockConfig(),
  );

  /// Fetches the user's active layout; falls back to the curated
  /// default when none exists (404 → repository returns `null`).
  Future<void> _load() async {
    final result = await _repo.activeLayout();
    if (!mounted) return;
    state = switch (result) {
      ApiSuccess(:final data) when data != null =>
        DashboardLayoutState(
          blocks: _mergeSaved(data.blocks),
          layoutId: data.id,
          saved: true,
        ),
      _ => DashboardLayoutState(blocks: _curatedDefault()),
    };
  }

  /// Merges a saved layout's blocks onto the catalog: known blocks keep
  /// their saved order + visibility; unknown ids are dropped
  /// (forward-compat, spec §8); catalog blocks missing from the saved
  /// layout are appended at the end, hidden (available to enable).
  List<DashboardBlock> _mergeSaved(List<DashboardBlock> saved) {
    final merged = <DashboardBlock>[];
    final seen = <String>{};
    for (final block in saved) {
      if (!_isKnown(block.id)) continue;
      seen.add(block.id);
      merged.add(block);
    }
    for (var i = 0; i < kpiCardCatalog.length; i++) {
      final def = kpiCardCatalog[i];
      if (seen.contains(def.id)) continue;
      merged.add(
        _kpiBlock(
          id: def.id,
          metric: def.metric,
          title: def.labelKey,
          visible: false,
          index: merged.length,
        ),
      );
    }
    for (var i = 0; i < panelCatalog.length; i++) {
      final def = panelCatalog[i];
      if (seen.contains(def.id)) continue;
      merged.add(
        _panelBlock(
          id: def.id,
          title: def.labelKey,
          visible: false,
          row: def.row,
          flex: def.flex,
          index: merged.length,
        ),
      );
    }
    if (!seen.contains(cashStripDefinition.id)) {
      merged.add(
        DashboardBlock(
          id: cashStripDefinition.id,
          type: 'cash',
          title: cashStripDefinition.labelKey,
          x: 0,
          y: 1,
          width: 1,
          height: 1,
          visible: cashStripDefinition.defaultVisible,
          version: 1,
          config: const DashboardBlockConfig(),
        ),
      );
    }
    return merged;
  }

  /// Known block ids: KPI cards + panels + cash strip (anything else in
  /// a saved layout is dropped, spec §8 forward-compat).
  static bool _isKnown(String id) =>
      kpiCardById.containsKey(id) ||
      panelById.containsKey(id) ||
      id == cashStripDefinition.id;

  /// Toggles a card's visibility (live — the strip behind the dialog
  /// updates immediately; persisted on Save).
  void toggle(String id, bool visible) {
    state = state.copyWith(
      blocks: [
        for (final block in state.blocks)
          if (block.id == id)
            _withVisible(block, visible)
          else
            block,
      ],
      dirty: true,
    );
  }

  /// Sets every card's visibility at once (Select All / Clear All).
  void setAllVisible(bool visible) {
    state = state.copyWith(
      blocks: [
        for (final block in state.blocks) _withVisible(block, visible),
      ],
      dirty: true,
    );
  }

  /// Sets a block's size preset (spec §6.3) — live in the dialog +
  /// strip, persisted on Save. The cash strip is fixed and has no size
  /// control, but the method is harmless for it.
  void setSize(String id, DashboardBlockSize size) {
    state = state.copyWith(
      blocks: [
        for (final block in state.blocks)
          if (block.id == id) _withSize(block, size) else block,
      ],
      dirty: true,
    );
  }

  /// Reorders the KPI strip. `oldIndex`/`newIndex` follow the
  /// `ReorderableListView.onReorderItem` contract (newIndex is already
  /// adjusted for the removed item). Indices are into the *visible KPI
  /// cards*; hidden cards + panels keep their positions (spec §6.3:
  /// reorder happens on the strip itself).
  void reorder(int oldIndex, int newIndex) {
    final visible = [
      for (final b in state.blocks)
        if (b.visible && kpiCardById.containsKey(b.id)) b,
    ];
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex.clamp(0, visible.length), moved);

    // Walk the full list, replacing visible KPI slots in the new order
    // and leaving hidden cards + panels in place.
    final blocks = <DashboardBlock>[];
    var vi = 0;
    for (final block in state.blocks) {
      if (block.visible && kpiCardById.containsKey(block.id)) {
        blocks.add(visible[vi++]);
      } else {
        blocks.add(block);
      }
    }
    state = state.copyWith(blocks: blocks, dirty: true);
  }

  /// Reorders the visible panels within one row (spec §6.5: panels
  /// reorder within their rows only). Indices are into the visible
  /// panels of that row; hidden panels + other rows stay put.
  void reorderPanels(int row, int oldIndex, int newIndex) {
    final visible = [
      for (final b in state.blocks)
        if (b.visible && panelById[b.id]?.row == row) b,
    ];
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex.clamp(0, visible.length), moved);

    final blocks = <DashboardBlock>[];
    var vi = 0;
    for (final block in state.blocks) {
      if (block.visible && panelById[block.id]?.row == row) {
        blocks.add(visible[vi++]);
      } else {
        blocks.add(block);
      }
    }
    state = state.copyWith(blocks: blocks, dirty: true);
  }

  /// Reorders the KPI cards *in the dialog's flat KPI list* (visible +
  /// hidden, in layout order) — the dialog lists every card, so its
  /// drag handles work on the full catalog order, not just the visible
  /// strip. Indices follow `ReorderableListView.onReorderItem`
  /// (newIndex pre-adjusted for the removed item).
  void reorderDialogKpis(int oldIndex, int newIndex) {
    final kpis = [
      for (final b in state.blocks)
        if (kpiCardById.containsKey(b.id)) b,
    ];
    if (oldIndex < 0 || oldIndex >= kpis.length) return;
    final moved = kpis.removeAt(oldIndex);
    kpis.insert(newIndex.clamp(0, kpis.length), moved);
    state = state.copyWith(
      blocks: _replaceSection(
        state.blocks,
        kpis,
        (b) => kpiCardById.containsKey(b.id),
      ),
      dirty: true,
    );
  }

  /// Reorders the panels of one row *in the dialog's flat panel list*
  /// (visible + hidden). Row-scoped like the strip reorder (spec §6.5):
  /// the dialog computes the row-local indices and calls this with them.
  void reorderDialogPanels(int row, int oldIndex, int newIndex) {
    final panels = [
      for (final b in state.blocks) if (panelById[b.id]?.row == row) b,
    ];
    if (oldIndex < 0 || oldIndex >= panels.length) return;
    final moved = panels.removeAt(oldIndex);
    panels.insert(newIndex.clamp(0, panels.length), moved);
    state = state.copyWith(
      blocks: _replaceSection(
        state.blocks,
        panels,
        (b) => panelById[b.id]?.row == row,
      ),
      dirty: true,
    );
  }

  /// Walks [blocks] replacing every slot that [inSection] matches with
  /// the next item from [section] (which holds that kind's new order).
  static List<DashboardBlock> _replaceSection(
    List<DashboardBlock> blocks,
    List<DashboardBlock> section,
    bool Function(DashboardBlock) inSection,
  ) {
    final result = <DashboardBlock>[];
    var si = 0;
    for (final block in blocks) {
      if (inSection(block)) {
        result.add(section[si++]);
      } else {
        result.add(block);
      }
    }
    return result;
  }

  /// Resets the working layout to the curated default (spec §6.2
  /// Revert). Marks dirty — the user confirms and then Save persists
  /// (mirrors the web app: revert → confirm → save).
  void revertToDefault() {
    state = DashboardLayoutState(blocks: _curatedDefault(), dirty: true);
  }

  /// Persists the current visibility + order. First save POSTs a new
  /// layout (the repository returns it with its server id); later
  /// saves PUT the existing one. Grid coords are derived from strip/row
  /// order on save (spec §5.2): KPI cards map to x = order, y = 0;
  /// panels keep their row and flex.
  Future<ApiError?> save() async {
    if (state.saving) return null;
    state = state.copyWith(saving: true);
    final blocks = _persistBlocks();

    if (state.layoutId == null) {
      final result = await _repo.createLayout(blocks: blocks);
      if (!mounted) return null;
      state = state.copyWith(saving: false);
      return switch (result) {
        ApiSuccess(:final data) => _markSaved(data.id),
        ApiFailure(:final error) => error,
      };
    }

    final result = await _repo.updateLayout(state.layoutId!, blocks: blocks);
    if (!mounted) return null;
    state = state.copyWith(saving: false);
    return switch (result) {
      ApiSuccess() => _markSaved(state.layoutId),
      ApiFailure(:final error) => error,
    };
  }

  ApiError? _markSaved(int? layoutId) {
    state = state.copyWith(
      layoutId: layoutId,
      saved: true,
      dirty: false,
    );
    return null;
  }

  DashboardBlock _withVisible(DashboardBlock block, bool visible) {
    return DashboardBlock(
      id: block.id,
      type: block.type,
      title: block.title,
      x: block.x,
      y: block.y,
      width: block.width,
      height: block.height,
      visible: visible,
      version: block.version,
      config: block.config,
    );
  }

  DashboardBlock _withSize(DashboardBlock block, DashboardBlockSize size) {
    return DashboardBlock(
      id: block.id,
      type: block.type,
      title: block.title,
      x: block.x,
      y: block.y,
      width: block.width,
      height: block.height,
      visible: block.visible,
      version: block.version,
      config: DashboardBlockConfig(
        refreshInterval: block.config.refreshInterval,
        text: block.config.text,
        metric: block.config.metric,
        limit: block.config.limit,
        period: block.config.period,
        days: block.config.days,
        size: size,
        extras: block.config.extras,
      ),
    );
  }

  /// Applies the persisted-grid mapping for the current visibility +
  /// order (spec §5.2): KPI cards x = order within the strip (y = 0);
  /// panels keep row + flex and get x = order within their row; cash
  /// strip stays fixed. Hidden blocks still occupy their logical slot so
  /// order is round-trippable.
  List<DashboardBlock> _persistBlocks() {
    final blocks = <DashboardBlock>[];
    var kpiIndex = 0;
    var row1Index = 0;
    var row2Index = 0;
    for (final block in state.blocks) {
      if (kpiCardById.containsKey(block.id)) {
        blocks.add(_reposition(block, y: 0, x: kpiIndex++));
      } else if (panelById[block.id]?.row == 1) {
        blocks.add(
          _reposition(block, y: 1, x: row1Index++, keepFlex: true),
        );
      } else if (panelById[block.id]?.row == 2) {
        blocks.add(
          _reposition(block, y: 2, x: row2Index++, keepFlex: true),
        );
      } else {
        // Cash strip — fixed at x=0, y=1.
        blocks.add(_reposition(block, y: 1, x: 0));
      }
    }
    return blocks;
  }

  DashboardBlock _reposition(
    DashboardBlock block, {
    required int y,
    required int x,
    bool keepFlex = false,
  }) {
    return DashboardBlock(
      id: block.id,
      type: block.type,
      title: block.title,
      x: x,
      y: y,
      width: keepFlex ? block.width : kKpiCardWidth,
      height: keepFlex ? block.height : kKpiCardHeight,
      visible: block.visible,
      version: block.version,
      config: block.config,
    );
  }
}

/// The single layout controller the dashboard strip and the customizer
/// dialog both watch — live edits in one are instantly reflected in the
/// other.
final dashboardLayoutControllerProvider =
    StateNotifierProvider<DashboardLayoutController, DashboardLayoutState>(
      (ref) => DashboardLayoutController(
        ref.watch(dashboardLayoutRepositoryProvider),
      ),
    );
