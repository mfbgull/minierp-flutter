// Calendar building blocks for the date-range picker: the month-pair pager
// header and the focusable 7×6 day grid.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:intl/intl.dart';

import '../core/utils/date_range_math.dart';
import '../core/utils/date_utils.dart' show isoDate;
import '../l10n/app_localizations.dart';

/// The `‹ Aug – Sep 2026 ›` month-pair pager header (reference
/// `.drp-cal-head`).
class DateRangeCalendarHeader extends StatelessWidget {
  const DateRangeCalendarHeader({
    super.key,
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
class DateRangeMonthGrid extends StatefulWidget {
  const DateRangeMonthGrid({
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
  State<DateRangeMonthGrid> createState() => DateRangeMonthGridState();
}

class DateRangeMonthGridState extends State<DateRangeMonthGrid> {
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
  void didUpdateWidget(DateRangeMonthGrid oldWidget) {
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
