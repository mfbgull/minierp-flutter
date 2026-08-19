// The date-range picker widget — port of the reference web picker
// (date-range-picker-spec.md §4, source `D:/date-range-picker.html`).
//
// A single pill control:
//
//   [‹] [📅 Aug 7 – 13, 2026 | This week] [›]
//
// - Clicking the middle opens an anchored popover (presets sidebar +
//   dual-month calendar) via an OverlayPortal, so it renders above the
//   toolbar/screen and is never clipped by the pane (§4.2, decision #13).
// - The ‹ › arrows shift the active range by one period (§5.4).
// - Instant apply: a preset commits on click; a custom range commits on
//   the end-date click (§5.1). No Apply/Cancel.
// - Preferences (week start, default range, user presets) come from the
//   Phase 2 providers (preference_providers.dart) with write-through
//   persistence.
//
// Drop-in: keeps the legacy `DateRangeFilter` name and the old
// constructor params (`fromProvider`/`toProvider`/`onChanged`/`onClear`/
// `showClear`), so Phase 4 call-site swaps are minimal. `width`/`height`
// are accepted but ignored — the pill self-sizes.
//
// Two modes:
// - [DateRangeMode.range] (default): From/To pair, "All dates" no-filter
//   state on list screens, full preset set.
// - [DateRangeMode.singleDate]: one date (cash-reconciliation screen),
//   reduced presets (Today / Yesterday / This month), tap-a-day commits.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/utils/date_range_math.dart';
import '../core/utils/date_utils.dart' show isoDate;
import '../core/utils/formatters.dart';
import '../data/models/user_preferences.dart' show UserPreset;
import '../features/preferences/preference_providers.dart'
    show
        saveDefaultRange,
        saveUserPresets,
        saveWeekStart,
        userPresetsProvider,
        weekStartProvider;
import '../l10n/app_localizations.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// The picker's selection mode ([DateRangeFilter.mode]).
enum DateRangeMode { range, singleDate }

/// Drop-in date-range filter: a pill-shaped control replacing the legacy
/// two-button From/To row on all ~24 screens (spec §4.1).
class DateRangeFilter extends ConsumerStatefulWidget {
  const DateRangeFilter({
    super.key,
    required this.fromProvider,
    required this.toProvider,
    this.onChanged,
    this.onClear,
    this.showClear,
    this.width,
    this.height,
    this.mode = DateRangeMode.range,
    this.dateProvider,
    this.showAllDates = true,
  }) : assert(
         mode != DateRangeMode.singleDate || dateProvider != null,
         'singleDate mode requires dateProvider',
       );

  /// The From/To provider pair this filter writes (both nullable —
  /// null = "no filter" / "All dates").
  final StateProvider<DateTime?> fromProvider;
  final StateProvider<DateTime?> toProvider;

  /// Called after a commit writes the providers (and after [onClear] runs)
  /// — lets callers react, e.g. the dashboard propagating its global range.
  final VoidCallback? onChanged;

  /// When non-null, renders a clear button beside the pill. Shown when
  /// [showClear] evaluates true, or (when null) whenever a date is set.
  final VoidCallback? onClear;

  /// Optional visibility override for the clear button (tear-off of the
  /// caller's filter-state getter, so it tracks filters beyond the pair).
  final bool Function()? showClear;

  /// Accepted but ignored — the pill self-sizes (kept so the ~19 legacy
  /// call sites that pass these compile untouched).
  final double? width;
  final double? height;

  /// [DateRangeMode.range] (default) or [DateRangeMode.singleDate].
  final DateRangeMode mode;

  /// Used only in [DateRangeMode.singleDate] — the single date provider
  /// (e.g. `reportReconciliationDateProvider`).
  final StateProvider<DateTime?>? dateProvider;

  /// Whether the "All dates" no-filter preset is offered. Report screens
  /// pass false (reports always have a range); list screens default true.
  final bool showAllDates;

  @override
  ConsumerState<DateRangeFilter> createState() => _DateRangeFilterState();
}

class _DateRangeFilterState extends ConsumerState<DateRangeFilter> {
  /// Nominal popover size used for the window-edge clamp math; the actual
  /// panel is ConstrainedBox'd to this and scrolls when the window is
  /// smaller (decision #13 — never clipped, content scrolls).
  static const double _panelWidth = 736;
  static const double _panelHeight = 430;

  final OverlayPortalController _overlayController = OverlayPortalController();
  final GlobalKey _pillKey = GlobalKey();
  final FocusNode _pillFocusNode = FocusNode();

  /// Left grid's state, so opening the panel can move keyboard focus to
  /// the anchored day cell (arrow-key nav works without a prior click).
  final GlobalKey<_MonthGridState> _gridKey = GlobalKey<_MonthGridState>();

  /// Start-only selection in progress (instant-apply state machine §5.1).
  DateTime? _pendingStart;
  DateTime? _pendingEnd;

  /// First day of the left calendar month (month-pair paging anchor).
  DateTime _anchorMonth = DateTime(DateTime.now().year, DateTime.now().month);

  /// Keyboard-focus day (arrow nav within a grid).
  DateTime? _focusedDay;

  bool get _isSingle => widget.mode == DateRangeMode.singleDate;
  bool get _panelOpen => _overlayController.isShowing;

  DateTime _today() => dateOnly(DateTime.now());

  WeekStart get _weekStart => ref.read(weekStartProvider);

  @override
  void dispose() {
    _pillFocusNode.dispose();
    super.dispose();
  }

  // ── Pill bar ────────────────────────────────────────────────────────

  /// The committed/pending range shown in the pill (null pair = All dates;
  /// a start-only pending selection shows that single day).
  String _barText(AppLocalizations l10n, DateTime? from, DateTime? to) {
    if (_isSingle) {
      final date = ref.read(widget.dateProvider!) ?? _today();
      return Formatters.date(isoDate(date));
    }
    if (_pendingStart != null) {
      final end = _pendingEnd ?? _pendingStart;
      return Formatters.compactRange(_pendingStart!, end!);
    }
    if (from == null && to == null) return l10n.drpPresetAllDates;
    if (from != null && to != null) return Formatters.compactRange(from, to);
    // Mixed state only reachable via legacy writes — show the set side.
    return Formatters.date(isoDate(from ?? to!));
  }

  /// The pill's preset chip label, or null when the bar shows a single
  /// date with no matching preset (spec §5.3).
  String? _chipLabel(
    AppLocalizations l10n,
    DateTime? from,
    DateTime? to,
    DateTime today,
  ) {
    if (_isSingle) {
      final date = ref.read(widget.dateProvider!) ?? today;
      if (dateOnly(date) == dateOnly(today)) return l10n.drpPresetToday;
      if (dateOnly(date) == dateOnly(addDays(today, -1))) {
        return l10n.drpPresetYesterday;
      }
      if (date.year == today.year && date.month == today.month) {
        return l10n.drpPresetThisMonth;
      }
      return l10n.drpPresetCustom;
    }
    if (from == null || to == null) return null;
    final range = (from: dateOnly(from), to: dateOnly(to));
    final builtIn = matchPreset(range, today, _weekStart);
    if (builtIn != null) return _builtInLabel(l10n, builtIn);
    for (final preset in ref.read(userPresetsProvider)) {
      if (dateOnly(preset.from) == range.from &&
          dateOnly(preset.to) == range.to) {
        return preset.name;
      }
    }
    return l10n.drpPresetCustom;
  }

  String _builtInLabel(AppLocalizations l10n, DatePreset preset) =>
      switch (preset) {
        DatePreset.today => l10n.drpPresetToday,
        DatePreset.yesterday => l10n.drpPresetYesterday,
        DatePreset.thisWeek => l10n.drpPresetThisWeek,
        DatePreset.lastWeek => l10n.drpPresetLastWeek,
        DatePreset.last7 => l10n.drpPresetLast7,
        DatePreset.last30 => l10n.drpPresetLast30,
        DatePreset.last90 => l10n.drpPresetLast90,
        DatePreset.thisMonth => l10n.drpPresetThisMonth,
        DatePreset.lastMonth => l10n.drpPresetLastMonth,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final from = ref.watch(widget.fromProvider);
    final to = ref.watch(widget.toProvider);
    // Single-date mode: watch the date so the pill bar (arrows included)
    // rebuilds when the committed date changes (e.g. via shift arrows).
    if (_isSingle) ref.watch(widget.dateProvider!);
    // Watch prefs so the chip/label re-match when the week start or user
    // presets change (e.g. via the open panel's footer / sidebar).
    ref.watch(weekStartProvider);
    ref.watch(userPresetsProvider);
    final today = _today();
    final barText = _barText(l10n, from, to);
    final chipLabel = _chipLabel(l10n, from, to, today);

    final clearVisible = widget.onClear != null &&
        (widget.showClear?.call() ?? (from != null || to != null));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (context) => _buildPanel(context, l10n),
          // Positioning is computed from the pill's GlobalKey render box
          // (see _buildPanel) rather than a CompositedTransformFollower,
          // because the spec's clamp-to-window rule (decision #13)
          // requires measuring the pill against the overlay — the
          // follower only does fixed-anchor alignment. The popover still
          // renders above the toolbar/screen via the OverlayPortal.
          child: Container(
            key: _pillKey,
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outline),
              borderRadius: AppBorderRadius.badge,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pillArrow(
                  tooltip: l10n.drpPrevPeriod,
                  icon: Icons.chevron_left,
                  onPressed: _canShift(-1) ? () => _shift(-1) : null,
                ),
                Tooltip(
                  message: barText,
                  child: Focus(
                    focusNode: _pillFocusNode,
                    child: InkWell(
                      onTap: _togglePanel,
                      customBorder: const StadiumBorder(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 15,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              barText,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                            if (chipLabel != null) ...[
                              const SizedBox(width: 8),
                              _chip(l10n, chipLabel, scheme),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _pillArrow(
                  tooltip: l10n.drpNextPeriod,
                  icon: Icons.chevron_right,
                  onPressed: _canShift(1) ? () => _shift(1) : null,
                ),
              ],
            ),
          ),
        ),
        if (clearVisible) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: l10n.commonClear,
            icon: Icon(
              Icons.filter_alt_off_outlined,
              size: 20,
              color: scheme.outline,
            ),
            onPressed: () {
              widget.onClear?.call();
              widget.onChanged?.call();
            },
          ),
        ],
      ],
    );
  }

  /// The ‹ › step button (reference `.drp-step`).
  Widget _pillArrow({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  /// The preset chip (reference `.preset-tag`): primaryContainer pill,
  /// uppercase label.
  Widget _chip(AppLocalizations l10n, String label, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: AppBorderRadius.badge,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  // ── Shift arrows ────────────────────────────────────────────────────

  /// Forward shift is disabled when it would move the range start past
  /// today (`shiftRangeClamped`); backward always allowed. Both disabled
  /// while a start-only selection is pending or on "All dates".
  bool _canShift(int dir) {
    if (_pendingStart != null) return false;
    if (_isSingle) {
      final date = ref.read(widget.dateProvider!) ?? _today();
      return !(dir > 0 && dateOnly(date) == dateOnly(_today()));
    }
    final from = ref.read(widget.fromProvider);
    final to = ref.read(widget.toProvider);
    if (from == null || to == null) return false;
    final today = _today();
    final type = shiftTypeForRange((from: from, to: to), today, _weekStart);
    return shiftRangeClamped((from: from, to: to), type, dir, today) != null;
  }

  void _shift(int dir) {
    if (_isSingle) {
      final date = ref.read(widget.dateProvider!) ?? _today();
      final next = addDays(date, dir);
      if (next.isAfter(_today())) return; // clamped at today
      ref.read(widget.dateProvider!.notifier).state = next;
      widget.onChanged?.call();
      return;
    }
    final from = ref.read(widget.fromProvider);
    final to = ref.read(widget.toProvider);
    if (from == null || to == null) return;
    final today = _today();
    final range = (from: from, to: to);
    final type = shiftTypeForRange(range, today, _weekStart);
    final shifted = shiftRangeClamped(range, type, dir, today);
    if (shifted == null) return;
    _commit(shifted.from, shifted.to, closePanel: false);
  }

  // ── Panel open/close ────────────────────────────────────────────────

  void _togglePanel() => _panelOpen ? _closePanel() : _openPanel();

  void _openPanel() {
    final today = _today();
    final anchor = _isSingle
        ? (ref.read(widget.dateProvider!) ?? today)
        : (ref.read(widget.fromProvider) ?? today);
    setState(() {
      _pendingStart = null;
      _pendingEnd = null;
      _anchorMonth = DateTime(anchor.year, anchor.month);
      _focusedDay = anchor;
    });
    _overlayController.show();
    // The grid cells own the arrow-key focus, so hand the initial
    // keyboard focus to the anchored day once the overlay has built
    // (the panel-level Focus only handles Escape).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_panelOpen) return;
      _gridKey.currentState?.requestFocusForDay(anchor);
    });
  }

  void _closePanel({bool returnFocus = false}) {
    if (_panelOpen) _overlayController.hide();
    setState(() {
      _pendingStart = null;
      _pendingEnd = null;
    });
    if (returnFocus) _pillFocusNode.requestFocus();
  }

  // ── Commits (instant apply) ─────────────────────────────────────────

  void _commit(DateTime from, DateTime to, {bool closePanel = true}) {
    ref.read(widget.fromProvider.notifier).state = dateOnly(from);
    ref.read(widget.toProvider.notifier).state = dateOnly(to);
    widget.onChanged?.call();
    if (closePanel) _closePanel();
  }

  void _commitSingle(DateTime day) {
    ref.read(widget.dateProvider!.notifier).state = dateOnly(day);
    widget.onChanged?.call();
    _closePanel();
  }

  /// Day-click state machine (spec §5.1). Range mode: first click is the
  /// start (bar updates immediately); second commits (swapping if the end
  /// precedes the start; same day twice = single-day range). Single-date
  /// mode commits on the first click.
  void _onDayTap(DateTime day) {
    final d = dateOnly(day);
    if (_isSingle) {
      _commitSingle(d);
      return;
    }
    if (_pendingStart == null) {
      setState(() {
        _pendingStart = d;
        _pendingEnd = null;
        _focusedDay = d;
      });
      return;
    }
    final start = d.isBefore(_pendingStart!) ? d : _pendingStart!;
    final end = d.isBefore(_pendingStart!) ? _pendingStart! : d;
    setState(() {
      _pendingStart = null;
      _pendingEnd = null;
    });
    _commit(start, end);
  }

  void _applyPreset(DatePreset preset) {
    final range = presetRange(preset, _today(), _weekStart);
    _commit(range.from, range.to);
  }

  void _applyAllDates() {
    ref.read(widget.fromProvider.notifier).state = null;
    ref.read(widget.toProvider.notifier).state = null;
    widget.onChanged?.call();
    _closePanel();
  }

  // ── Panel: popover positioning ──────────────────────────────────────

  /// Positions the popover below the pill, clamped to the window edges
  /// (decision #13): horizontally clamped, vertically flipped upward when
  /// there isn't room below, content scrolls when the window is smaller
  /// than the nominal panel.
  Widget _buildPanel(BuildContext context, AppLocalizations l10n) {
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final targetBox = _pillKey.currentContext!.findRenderObject()! as RenderBox;
    final overlaySize = overlayBox.size;
    final targetTopLeft =
        targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);

    var left = targetTopLeft.dx;
    var top = targetTopLeft.dy + targetBox.size.height + 8;
    if (left + _panelWidth > overlaySize.width) {
      left = math.max(8, overlaySize.width - _panelWidth - 8);
    }
    if (top + _panelHeight > overlaySize.height) {
      top = math.max(8, targetTopLeft.dy - _panelHeight - 8); // flip up
    }

    return Stack(
      children: [
        // Tap-anywhere-else barrier (also covers the pill → toggle closes).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _closePanel(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _closePanel(returnFocus: true);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(_panelWidth, overlaySize.width - 16),
                maxHeight: math.min(_panelHeight, overlaySize.height - 16),
              ),
              child: _RangePopover(
                l10n: l10n,
                mode: widget.mode,
                showAllDates: widget.showAllDates,
                weekStart: _weekStart,
                today: _today(),
                gridKey: _gridKey,
                from: ref.watch(widget.fromProvider),
                to: ref.watch(widget.toProvider),
                pendingStart: _pendingStart,
                pendingEnd: _pendingEnd,
                anchorMonth: _anchorMonth,
                focusedDay: _focusedDay,
                onWeekStartChanged: _setWeekStart,
                onDayTap: _onDayTap,
                onFocusDayChanged: (d) => setState(() => _focusedDay = d),
                onPageMonths: (dir) => setState(
                  () => _anchorMonth = DateTime(
                    _anchorMonth.year,
                    _anchorMonth.month + dir,
                  ),
                ),
                onPresetTap: _applyPreset,
                onAllDates: _applyAllDates,
                onUserPresetTap: (p) => _commit(p.from, p.to),
                onUserPresetRemove: _removeUserPreset,
                onAddPreset: _addUserPreset,
                onSetDefault: _setDefaultRange,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Preferences writes (write-through) ──────────────────────────────

  void _setWeekStart(WeekStart value) {
    ref.read(weekStartProvider.notifier).state = value;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    saveWeekStart(ref, value).then((error) {
      if (!mounted || error == null) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.drpWeekStartFailed)));
    });
  }

  Future<void> _setDefaultRange() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final today = _today();
    final DateRange? range;
    if (_isSingle) {
      final d = ref.read(widget.dateProvider!) ?? today;
      range = (from: d, to: d);
    } else {
      final from = ref.read(widget.fromProvider);
      final to = ref.read(widget.toProvider);
      range = (from != null && to != null) ? (from: from, to: to) : null;
    }
    if (range == null) return;
    final error = await saveDefaultRange(ref, range);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error == null ? l10n.drpDefaultSet : l10n.drpDefaultFailed,
        ),
      ),
    );
  }

  Future<void> _addUserPreset() async {
    final from = ref.read(widget.fromProvider);
    final to = ref.read(widget.toProvider);
    if (from == null || to == null) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.drpAddPreset),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.drpPresetName),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final preset = UserPreset(
      id: 'u${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      from: from,
      to: to,
    );
    final error = await saveUserPresets(
      ref,
      [...ref.read(userPresetsProvider), preset],
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error == null ? l10n.drpPresetAdded : l10n.drpPresetAddFailed,
        ),
      ),
    );
  }

  Future<void> _removeUserPreset(UserPreset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final error = await saveUserPresets(
      ref,
      [
        for (final p in ref.read(userPresetsProvider))
          if (p.id != preset.id) p,
      ],
    );
    if (!mounted || error == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.drpPresetRemoveFailed)),
    );
  }
}

/// The anchored popover body: presets sidebar + calendar area (header,
/// dual-month grids, footer with hint / week-start / set-default).
class _RangePopover extends ConsumerWidget {
  const _RangePopover({
    required this.l10n,
    required this.mode,
    required this.showAllDates,
    required this.weekStart,
    required this.today,
    required this.gridKey,
    required this.from,
    required this.to,
    required this.pendingStart,
    required this.pendingEnd,
    required this.anchorMonth,
    required this.focusedDay,
    required this.onWeekStartChanged,
    required this.onDayTap,
    required this.onFocusDayChanged,
    required this.onPageMonths,
    required this.onPresetTap,
    required this.onAllDates,
    required this.onUserPresetTap,
    required this.onUserPresetRemove,
    required this.onAddPreset,
    required this.onSetDefault,
  });

  final AppLocalizations l10n;
  final DateRangeMode mode;
  final bool showAllDates;
  final WeekStart weekStart;
  final DateTime today;

  /// Key to the left month grid's state — lets the parent move initial
  /// keyboard focus to the anchored day cell when the panel opens.
  final GlobalKey<_MonthGridState> gridKey;

  /// The committed provider values (null pair = "All dates").
  final DateTime? from;
  final DateTime? to;

  final DateTime? pendingStart;
  final DateTime? pendingEnd;
  final DateTime anchorMonth;
  final DateTime? focusedDay;
  final ValueChanged<WeekStart> onWeekStartChanged;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<DateTime> onFocusDayChanged;
  final ValueChanged<int> onPageMonths;
  final ValueChanged<DatePreset> onPresetTap;
  final VoidCallback onAllDates;
  final ValueChanged<UserPreset> onUserPresetTap;
  final ValueChanged<UserPreset> onUserPresetRemove;
  final VoidCallback onAddPreset;
  final VoidCallback onSetDefault;

  bool get _isSingle => mode == DateRangeMode.singleDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final userPresets = ref.watch(userPresetsProvider);

    return Material(
      color: scheme.surface,
      elevation: 16,
      shadowColor: scheme.shadow,
      borderRadius: AppBorderRadius.lgRadius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: AppBorderRadius.lgRadius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Presets sidebar ──
            Container(
              width: 168,
              color: scheme.surfaceContainerLow,
              padding: const EdgeInsets.all(10),
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (!_isSingle && showAllDates)
                    _presetTile(
                      context,
                      label: l10n.drpPresetAllDates,
                      active: from == null && to == null,
                      onTap: onAllDates,
                    ),
                  for (final preset in _builtInPresets())
                    _presetTile(
                      context,
                      label: _builtInLabel(l10n, preset),
                      active: _builtInActive(preset),
                      onTap: () => onPresetTap(preset),
                    ),
                  if (!_isSingle) ...[
                    _presetTile(
                      context,
                      label: l10n.drpPresetCustomRange,
                      active: _customActive(userPresets),
                      onTap: () {}, // Custom = tap a day; no direct action
                    ),
                    for (final preset in userPresets)
                      _presetTile(
                        context,
                        label: preset.name,
                        active: _userPresetActive(preset),
                        onTap: () => onUserPresetTap(preset),
                        trailing: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _confirmRemovePreset(
                            context,
                            preset,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.error,
                              borderRadius: AppBorderRadius.xsRadius,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: scheme.onError,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (from != null && to != null)
                      TextButton.icon(
                        onPressed: onAddPreset,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(l10n.drpAddPreset),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            // ── Calendar area ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CalendarHeader(
                      anchorMonth: anchorMonth,
                      l10n: l10n,
                      onPageMonths: onPageMonths,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _MonthGrid(
                            key: gridKey,
                            month: anchorMonth,
                            weekStart: weekStart,
                            today: today,
                            pendingStart: pendingStart,
                            pendingEnd: pendingEnd,
                            focusedDay: focusedDay,
                            onDayTap: onDayTap,
                            onFocusDayChanged: onFocusDayChanged,
                            onPageMonths: onPageMonths,
                            semanticLabelBuilder: _semanticDayLabel,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _MonthGrid(
                            month: DateTime(
                              anchorMonth.year,
                              anchorMonth.month + 1,
                            ),
                            weekStart: weekStart,
                            today: today,
                            pendingStart: pendingStart,
                            pendingEnd: pendingEnd,
                            focusedDay: focusedDay,
                            onDayTap: onDayTap,
                            onFocusDayChanged: onFocusDayChanged,
                            onPageMonths: onPageMonths,
                            semanticLabelBuilder: _semanticDayLabel,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: 8),
                    _buildFooter(context, scheme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _semanticDayLabel(DateTime day) =>
      DateFormat('EEEE, MMMM d', l10n.localeName).format(day);

  // ── Preset matching ─────────────────────────────────────────────────

  bool get _hasCommittedRange => from != null && to != null;

  bool _customActive(List<UserPreset> userPresets) {
    if (!_hasCommittedRange) return false;
    final range = (from: dateOnly(from!), to: dateOnly(to!));
    if (matchPreset(range, today, weekStart) != null) return false;
    for (final preset in userPresets) {
      if (dateOnly(preset.from) == range.from &&
          dateOnly(preset.to) == range.to) {
        return false;
      }
    }
    return true;
  }

  bool _builtInActive(DatePreset preset) {
    if (!_hasCommittedRange) return false;
    return matchPreset((from: from!, to: to!), today, weekStart) == preset;
  }

  bool _userPresetActive(UserPreset preset) {
    if (!_hasCommittedRange) return false;
    return dateOnly(from!) == dateOnly(preset.from) &&
        dateOnly(to!) == dateOnly(preset.to);
  }

  /// Built-in presets for the current mode (§2.3 / §5.5).
  List<DatePreset> _builtInPresets() {
    if (_isSingle) {
      return const [
        DatePreset.today,
        DatePreset.yesterday,
        DatePreset.thisMonth,
      ];
    }
    return const [
      DatePreset.today,
      DatePreset.yesterday,
      DatePreset.thisWeek,
      DatePreset.lastWeek,
      DatePreset.last7,
      DatePreset.last30,
      DatePreset.last90,
      DatePreset.thisMonth,
      DatePreset.lastMonth,
    ];
  }

  String _builtInLabel(AppLocalizations l10n, DatePreset preset) =>
      switch (preset) {
        DatePreset.today => l10n.drpPresetToday,
        DatePreset.yesterday => l10n.drpPresetYesterday,
        DatePreset.thisWeek => l10n.drpPresetThisWeek,
        DatePreset.lastWeek => l10n.drpPresetLastWeek,
        DatePreset.last7 => l10n.drpPresetLast7,
        DatePreset.last30 => l10n.drpPresetLast30,
        DatePreset.last90 => l10n.drpPresetLast90,
        DatePreset.thisMonth => l10n.drpPresetThisMonth,
        DatePreset.lastMonth => l10n.drpPresetLastMonth,
      };

  String _hintText() {
    if (_isSingle) return l10n.drpPickDate;
    if (pendingStart == null) return l10n.drpPickStart;
    if (pendingEnd == null) return l10n.drpPickEnd;
    final n = daysInRange(pendingStart!, pendingEnd!);
    return n == 1 ? l10n.drpOneDay : l10n.drpDaysSelected(n);
  }

  Future<void> _confirmRemovePreset(
    BuildContext context,
    UserPreset preset,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.drpPresetRemove),
        content: Text(preset.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      onUserPresetRemove(preset);
    }
  }

  Widget _presetTile(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active ? scheme.inverseSurface : Colors.transparent,
        borderRadius: AppBorderRadius.smRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppBorderRadius.smRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active
                          ? scheme.onInverseSurface
                          : scheme.onSurface,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Footer: hint + Set-as-default on the left; week-start segmented
  /// control below.
  Widget _buildFooter(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _hintText(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _hasCommittedRange ? onSetDefault : null,
              icon: const Icon(Icons.bookmark_outline, size: 16),
              label: Text(l10n.drpSetDefault),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Week start row — the segmented control can outgrow narrow
        // panes, so the label wraps and the control stays on one line
        // (decision #13: content scrolls rather than clipping).
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                l10n.drpWeekStartsOn,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SegmentedButton<WeekStart>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(
                  value: WeekStart.monday,
                  label: Text(l10n.drpWeekdayMonday),
                ),
                ButtonSegment(
                  value: WeekStart.saturday,
                  label: Text(l10n.drpWeekdaySaturday),
                ),
                ButtonSegment(
                  value: WeekStart.sunday,
                  label: Text(l10n.drpWeekdaySunday),
                ),
              ],
              selected: {weekStart},
              onSelectionChanged: (selection) =>
                  onWeekStartChanged(selection.first),
            ),
          ],
        ),
      ],
    );
  }
}

/// The `‹ Aug – Sep 2026 ›` month-pair pager header (reference
/// `.drp-cal-head`).
class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.anchorMonth,
    required this.l10n,
    required this.onPageMonths,
  });

  final DateTime anchorMonth;
  final AppLocalizations l10n;
  final ValueChanged<int> onPageMonths;

  @override
  Widget build(BuildContext context) {
    final right = DateTime(anchorMonth.year, anchorMonth.month + 1);
    final monthFormat = DateFormat('MMM', l10n.localeName);
    final yearFormat = DateFormat('y', l10n.localeName);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () => onPageMonths(-1),
        ),
        Expanded(
          child: Text(
            '${monthFormat.format(anchorMonth)} – '
            '${monthFormat.format(right)} ${yearFormat.format(right)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () => onPageMonths(1),
        ),
      ],
    );
  }
}

/// One month's 7×6 day grid (reference `.drp-grid`), Monday/Saturday/
/// Sunday-first per the saved week start. Each day cell is a real
/// focusable button with arrow-key navigation (§4.6).
class _MonthGrid extends StatefulWidget {
  const _MonthGrid({
    super.key,
    required this.month,
    required this.weekStart,
    required this.today,
    required this.pendingStart,
    required this.pendingEnd,
    required this.focusedDay,
    required this.onDayTap,
    required this.onFocusDayChanged,
    required this.onPageMonths,
    required this.semanticLabelBuilder,
  });

  /// First day of the month to render.
  final DateTime month;
  final WeekStart weekStart;
  final DateTime today;
  final DateTime? pendingStart;
  final DateTime? pendingEnd;
  final DateTime? focusedDay;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<DateTime> onFocusDayChanged;
  final ValueChanged<int> onPageMonths;
  final String Function(DateTime) semanticLabelBuilder;

  @override
  State<_MonthGrid> createState() => _MonthGridState();
}

class _MonthGridState extends State<_MonthGrid> {
  static const List<String> _dow = [
    'Mo',
    'Tu',
    'We',
    'Th',
    'Fr',
    'Sa',
    'Su',
  ];

  /// The 42 day cells of this grid (leading/trailing adjacent-month days
  /// muted, reference `.drp-day.muted`).
  late List<DateTime> _days;

  /// One real [FocusNode] per cell so arrow keys move actual keyboard
  /// focus (§4.6) — created once in [initState], disposed in [dispose].
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _days = _buildDays();
    _nodes = [for (var i = 0; i < 42; i++) FocusNode()];
  }

  @override
  void didUpdateWidget(_MonthGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month ||
        oldWidget.weekStart != widget.weekStart) {
      _days = _buildDays();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  List<DateTime> _buildDays() {
    final first = DateTime(widget.month.year, widget.month.month);
    final gridStart = startOfWeek(first, widget.weekStart);
    return [for (var i = 0; i < 42; i++) addDays(gridStart, i)];
  }

  /// The weekday header order for the saved week start (spec §4.5).
  List<String> get _weekdayRow {
    final offset = weekStartIndex(widget.weekStart);
    return [for (var i = 0; i < 7; i++) _dow[(i + offset) % 7]];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final monthTitle = DateFormat('MMMM y', locale).format(widget.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          monthTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final dow in _weekdayRow)
              Expanded(
                child: Text(
                  dow,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var row = 0; row < 6; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: _buildDayCell(context, row * 7 + col)),
            ],
          ),
      ],
    );
  }

  Widget _buildDayCell(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    final day = _days[index];
    final muted = day.month != widget.month.month;
    final isToday = dateOnly(day) == dateOnly(widget.today);
    final inRange = widget.pendingStart != null &&
        widget.pendingEnd != null &&
        !day.isBefore(widget.pendingStart!) &&
        !day.isAfter(widget.pendingEnd!);
    final isStart =
        widget.pendingStart != null &&
        dateOnly(day) == dateOnly(widget.pendingStart!);
    final isEnd =
        widget.pendingEnd != null &&
        dateOnly(day) == dateOnly(widget.pendingEnd!);
    final isFocused =
        widget.focusedDay != null &&
        dateOnly(day) == dateOnly(widget.focusedDay!);

    final Color fill;
    final Color textColor;
    if (isStart || isEnd) {
      fill = scheme.primary;
      textColor = scheme.onPrimary;
    } else if (inRange) {
      fill = scheme.primaryContainer;
      textColor = scheme.onPrimaryContainer;
    } else {
      fill = Colors.transparent;
      textColor = muted ? scheme.outline : scheme.onSurface;
    }

    final radius = BorderRadius.only(
      topLeft: Radius.circular(isStart ? 6 : 0),
      bottomLeft: Radius.circular(isStart ? 6 : 0),
      topRight: Radius.circular(isEnd ? 6 : 0),
      bottomRight: Radius.circular(isEnd ? 6 : 0),
    );

    return Semantics(
      label: widget.semanticLabelBuilder(day),
      button: true,
      child: Focus(
        focusNode: _nodes[index],
        onFocusChange: (focused) {
          if (focused) widget.onFocusDayChanged(day);
        },
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            return _moveFocus(index, -1);
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            return _moveFocus(index, 1);
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            return _moveFocus(index, -7);
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            return _moveFocus(index, 7);
          }
          if (key == LogicalKeyboardKey.home) {
            _nodes[0].requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.end) {
            _nodes[41].requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.pageUp) {
            widget.onPageMonths(-1);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.pageDown) {
            widget.onPageMonths(1);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            widget.onDayTap(day);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: InkWell(
          // Stable per-day key (`drp-day-YYYY-MM-DD`) so tests and
          // automation can target a cell across the month pair without
          // ambiguity (e.g. day 11 exists in both visible months).
          key: ValueKey('drp-day-${isoDate(day)}'),
          onTap: () => widget.onDayTap(day),
          borderRadius: radius,
          child: Container(
            height: 30,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: isToday && !isStart && !isEnd
                  ? Border.all(color: scheme.primary, width: 1)
                  : null,
            ),
            child: Center(
              child: Text(
                '${day.day}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: textColor,
                  fontWeight: isFocused ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Requests keyboard focus for the cell matching [day] (used when the
  /// panel opens, so arrow-key nav works immediately without a click).
  void requestFocusForDay(DateTime day) {
    final index = _days.indexWhere((d) => dateOnly(d) == dateOnly(day));
    if (index >= 0) _nodes[index].requestFocus();
  }

  /// Moves keyboard focus by [delta] cells within the 42-cell grid
  /// (clamped — no wrap). Returns handled so unhandled keys bubble.
  KeyEventResult _moveFocus(int index, int delta) {
    final next = math.max(0, math.min(41, index + delta));
    if (next == index) return KeyEventResult.handled;
    _nodes[next].requestFocus();
    return KeyEventResult.handled;
  }
}
