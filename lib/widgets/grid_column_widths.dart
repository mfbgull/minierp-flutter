// Local persistence of user-adjusted PlutoGrid column widths.
//
// pluto_grid exposes no on-column-resize callback, but its state manager
// publishes a dedicated `resizingChangeNotifier` that fires on every width
// change — including programmatic ones (auto-fit, restore). A boolean guard
// separates the two: widths written by code are never persisted, so only
// genuine user drags are remembered, keyed by screen name and column field
// in a single SharedPreferences JSON blob (the same local-blob pattern as
// `RecentItems`). Untouched columns have no entry and keep the content
// auto-fit behaviour on every load.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GridColumnWidths {
  GridColumnWidths._(this._stateManager, this._screenKey);

  final PlutoGridStateManager _stateManager;
  final String _screenKey;

  Timer? _debounce;
  bool _applying = false;
  bool _disposed = false;

  /// Widths at the last point the app finished sizing the grid (initial
  /// auto-fit/restore or a post-refresh re-fit). A later notifier event
  /// whose column drifted from this baseline is a user edit.
  Map<String, double> _baseline = const {};

  static const _storageKey = 'grid_column_widths';

  static const _debounceDuration = Duration(milliseconds: 600);
  static const _epsilon = 0.5;

  /// Starts tracking [stateManager] for [screenKey]: restores previously
  /// dragged widths once the pending auto-fit pass settles, then persists
  /// further user drags (debounced). Call [dispose] when the grid goes
  /// away — the tracker must be replaced whenever a screen swaps its
  /// grid/stateManager (e.g. a keyed grid rebuilt per selection).
  static GridColumnWidths attach({
    required PlutoGridStateManager stateManager,
    required String screenKey,
  }) {
    final tracker = GridColumnWidths._(stateManager, screenKey);
    stateManager.resizingChangeNotifier.addListener(tracker._onResized);
    // Queue behind the caller's post-frame auto-fit so restoration lands
    // on the fitted layout instead of racing it.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => tracker.restoreSaved(),
    );
    return tracker;
  }

  /// Runs [sizing] (typically `autoFitPlutoColumns`) without recording its
  /// resizes as user edits, then re-applies saved widths so a data refresh
  /// cannot stomp what the user dragged earlier.
  void programmaticPass(void Function() sizing) {
    if (_disposed) {
      sizing();
      return;
    }
    _applying = true;
    try {
      sizing();
    } finally {
      _applying = false;
    }
    restoreSaved();
  }

  /// Re-applies persisted widths (if any) and re-baselines, ignoring the
  /// resizes this causes.
  Future<void> restoreSaved() async {
    final saved = await _loadFor(_screenKey);
    if (_disposed) return;
    if (saved.isNotEmpty) {
      _applying = true;
      for (final column in _stateManager.columns) {
        if (!_isTrackable(column)) continue;
        final width = saved[column.field];
        if (width == null) continue;
        if ((column.width - width).abs() < _epsilon) continue;
        _stateManager.resizeColumn(column, width - column.width);
      }
      _applying = false;
    }
    _baseline = _currentWidths();
  }

  void _onResized() {
    if (_disposed || _applying) return;
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _captureUserEdits);
  }

  /// Reads current widths and persists the ones that drifted from the
  /// baseline. Safe to run after [dispose] — it touches only column data
  /// and SharedPreferences, so a flush initiated during teardown still
  /// lands its write.
  Future<void> _captureUserEdits() async {
    final current = _currentWidths();
    final edits = <String, double>{
      for (final entry in current.entries)
        if (_baseline[entry.key] == null ||
            (_baseline[entry.key]! - entry.value).abs() >= _epsilon)
          entry.key: entry.value,
    };
    _baseline = current;
    if (edits.isEmpty) return;
    await _mergeSave(edits);
  }

  Map<String, double> _currentWidths() => {
    for (final column in _stateManager.columns)
      if (_isTrackable(column)) column.field: column.width,
  };

  /// Every visible column qualifies — including custom-rendered ones
  /// (link/badge cells): whatever the user can drag, they expect to be
  /// remembered. Hidden carrier cells (`id`, `data`) cannot be dragged
  /// and are excluded.
  bool _isTrackable(PlutoColumn column) => !column.hide;

  Future<Map<String, double>> _loadFor(String screenKey) async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return const {};
    final raw = prefs.getString(_storageKey);
    if (raw == null) return const {};
    try {
      final all = (jsonDecode(raw) as Map<String, dynamic>).cast<String, Object?>();
      final screen = all[screenKey] as Map<String, dynamic>?;
      // Decode eagerly (not .cast) — JSON widths arrive as num and the
      // lazy view would throw outside this catch.
      return screen?.map(
            (field, value) => MapEntry(field, (value as num).toDouble()),
          ) ??
          const {};
    } catch (_) {
      // Corrupt blob — fall back to auto-fit everywhere; the next user
      // edit overwrites it wholesale.
      return const {};
    }
  }

  Future<void> _mergeSave(Map<String, double> edits) async {
    final prefs = await SharedPreferences.getInstance();
    // Fresh growable map — `const {}` is unmodifiable and would throw on
    // the merge below (first-ever save has no stored blob).
    Map<String, dynamic> all = {};
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          // Rebuilt entry-by-entry (not .cast): guarantees a writable map
          // with String keys regardless of what jsonDecode produced.
          all = decoded.map((k, v) => MapEntry('$k', v));
        }
      } catch (_) {}
    }
    // Merge into the screen's map, dropping entries for fields the grid
    // no longer has (renamed/removed columns), then overlay this round's
    // edits — they win over whatever was stored.
    final rawScreen = all[_screenKey];
    final previous = <String, dynamic>{
      if (rawScreen is Map)
        for (final entry in rawScreen.entries) '${entry.key}': entry.value,
    };
    final liveFields = _currentWidths();
    final merged = <String, double>{
      for (final entry in previous.entries)
        if (liveFields.containsKey(entry.key))
          entry.key: (entry.value as num).toDouble(),
      ...edits,
    };
    all[_screenKey] = merged;
    await prefs.setString(_storageKey, jsonEncode(all));
  }

  /// Stops listening and cancels pending saves. A drag captured moments
  /// before teardown — e.g. the user resized and immediately navigated
  /// away — is flushed rather than dropped: the capture only reads column
  /// data and SharedPreferences, both safe past this point. Safe to call
  /// after the owning grid's state manager was disposed.
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(_captureUserEdits());
    } else {
      _debounce?.cancel();
    }
    _disposed = true;
    _stateManager.resizingChangeNotifier.removeListener(_onResized);
  }
}
