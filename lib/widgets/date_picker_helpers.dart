import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/date_utils.dart' show isoDate;
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';

/// Shared date-picker helpers — the single home for the app's
/// `showDatePicker` wiring (PORTING.md §2). Previously each list
/// screen, form dialog and report screen rolled its own copy:
///
/// - `pickDate`        — single-field pickers (form dialogs).
/// - `pickFilterDate`  — From/To filter buttons writing nullable
///   `StateProvider<DateTime?>`s (all list + report screens; null
///   means "no filter", and report callers fall back to defaults).
/// - `DateFilterButton`— the compact calendar button both list screens
///   previously built inline as `_dateButton`.
/// - `DateRangeFilter` — the complete From/To filter row (two
///   [DateFilterButton]s + optional clear) that every screen with a
///   date-range filter renders in its toolbar.

/// Shows the app-standard date picker (2000 → 2100 by default) and
/// returns the picked [DateTime], or null when dismissed.
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate ?? DateTime(2000),
    lastDate: lastDate ?? DateTime(2100),
  );
}

/// From/To filter picker for a nullable provider pair. `null` means "no
/// filter", so the initial date falls back to today. Writes the picked
/// date back (refetching whatever provider watches the pair).
///
/// Filters cap the picker at today — filtering historical records by a
/// future date is meaningless (the form-date pickers keep the 2100
/// upper bound via [pickDate]'s default).
Future<void> pickFilterDate(
  BuildContext context,
  WidgetRef ref, {
  required StateProvider<DateTime?> fromProvider,
  required StateProvider<DateTime?> toProvider,
  required bool isFrom,
}) async {
  final current = isFrom ? ref.read(fromProvider) : ref.read(toProvider);
  final picked = await pickDate(
    context,
    initialDate: current ?? DateTime.now(),
    lastDate: DateTime.now(),
  );
  if (picked == null) return;
  ref.read((isFrom ? fromProvider : toProvider).notifier).state = picked;
}

/// Compact calendar button used on the list-screen toolbars (the
/// previous per-screen `_dateButton`). `width`/`height` are optional —
/// screens wrap it in a fixed-size [SizedBox] when the toolbar layout
/// needs one.
class DateFilterButton extends StatelessWidget {
  const DateFilterButton({
    super.key,
    required this.label,
    required this.onTap,
    this.width,
    this.height,
  });

  final String label;
  final VoidCallback onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.calendar_today_outlined, size: 15),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// Complete From/To date-range filter row for the list-screen toolbars:
/// two [DateFilterButton]s wired to a nullable provider pair via
/// [pickFilterDate], plus an optional trailing clear button. Replaces
/// the per-screen `DateFilterButton` pairs + clear buttons that the
/// sales/expenses screens previously inlined.
///
/// [showClear] is evaluated on every rebuild (a tear-off of the
/// screen's own `_hasActiveFilters` getter, or null to default to
/// "either date is set").
class DateRangeFilter extends ConsumerWidget {
  const DateRangeFilter({
    super.key,
    required this.fromProvider,
    required this.toProvider,
    this.onChanged,
    this.onClear,
    this.showClear,
    this.width,
    this.height,
  });

  final StateProvider<DateTime?> fromProvider;
  final StateProvider<DateTime?> toProvider;

  /// Called after a From/To pick writes its provider (and after the
  /// clear button runs [onClear]) — lets callers react to the new
  /// range, e.g. the dashboard propagating its global range to every
  /// report page.
  final VoidCallback? onChanged;

  /// When non-null, renders a clear button after the To button. Shown
  /// when [showClear] evaluates true, or (when null) whenever either
  /// date is set.
  final VoidCallback? onClear;

  /// Optional visibility override for the clear button — a tear-off of
  /// the caller's filter-state getter, so it tracks filters outside the
  /// date pair too (e.g. category/status on the expenses screen).
  final bool Function()? showClear;

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final from = ref.watch(fromProvider);
    final to = ref.watch(toProvider);
    final clearVisible =
        onClear != null && (showClear?.call() ?? (from != null || to != null));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DateFilterButton(
          width: width,
          height: height,
          label: from == null
              ? l10n.commonFrom
              : Formatters.date(isoDate(from)),
          onTap: () async {
            await pickFilterDate(
              context,
              ref,
              fromProvider: fromProvider,
              toProvider: toProvider,
              isFrom: true,
            );
            onChanged?.call();
          },
        ),
        const SizedBox(width: 8),
        DateFilterButton(
          width: width,
          height: height,
          label: to == null ? l10n.commonTo : Formatters.date(isoDate(to)),
          onTap: () async {
            await pickFilterDate(
              context,
              ref,
              fromProvider: fromProvider,
              toProvider: toProvider,
              isFrom: false,
            );
            onChanged?.call();
          },
        ),
        if (clearVisible) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: l10n.commonClear,
            icon: Icon(
              Icons.filter_alt_off_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.outline,
            ),
            onPressed: () {
              onClear?.call();
              onChanged?.call();
            },
          ),
        ],
      ],
    );
  }
}
