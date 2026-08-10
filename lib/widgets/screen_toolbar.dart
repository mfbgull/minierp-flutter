// ScreenToolbar — the shared list-screen toolbar row (PORTING.md §6).
//
// Every read-only PlutoGrid screen used to roll its own header; the
// invoices tab established the reference layout (search field, filter
// dropdown, date range, refresh, secondary actions, primary "New …"
// button) and the other screens each re-implemented smaller variants.
// This is the single parameterized version of that row:
//
//   [search] [filters…] [refresh] [actions…] [primaryActions…]
//
// The screen owns all state (search controller, filter providers,
// debounce) and passes plain callbacks; the widget only arranges the
// row — a [Wrap] so the controls flow to a second line on narrow panes
// exactly like the invoices toolbar. The search suffix shows the
// clear-all icon when [onClearAll] + [hasActiveFilters] are provided
// (the invoices/quotation/returns style), otherwise a text-clear icon
// while the field has content (the customers/items style).

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'searchable_select.dart';

/// Compact bordered searchable-select for the toolbar row — the shared
/// `_filterDropdown` helper the expenses/employees/users screens used to
/// inline. `T` is the filter's value type; the nullable-option convention
/// carries the "All …" choice as `null` (its label via [labelBuilder] or
/// [hint]).
class ScreenToolbarDropdown<T> extends StatelessWidget {
  const ScreenToolbarDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.labelBuilder,
    required this.onChanged,
    this.hint,
    this.width = 160,
    this.height = 40,
    this.prefixIcon,
  });

  final List<T> items;
  final T value;
  final String Function(T) labelBuilder;
  final ValueChanged<T?> onChanged;

  /// Trigger label when [value] is the null "All …" option.
  final String? hint;
  final double width;
  final double height;

  /// Optional leading icon (e.g. the movement-type filter's funnel).
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      // The wrapper owns the widget's [key] (tests tap the dropdown by
      // key); the select fills it, so taps land on the InkWell either way.
      child: SearchableSelect<T>(
        items: items,
        selected: value,
        hint: hint,
        labelBuilder: labelBuilder,
        isDense: true,
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

/// The shared toolbar row described above. All lists are optional — a
/// screen that has no search (e.g. a pure filter bar) simply omits the
/// search params, and read-only logs omit [primaryActions].
class ScreenToolbar extends StatelessWidget {
  const ScreenToolbar({
    super.key,
    this.searchController,
    this.searchHint,
    this.onSearchChanged,
    this.onClearSearch,
    this.searchEnabled = true,
    this.searchWidth = 260,
    this.filters = const [],
    this.actions = const [],
    this.primaryActions = const [],
    this.onRefresh,
    this.onClearAll,
    this.hasActiveFilters = false,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  /// Search field state — omitted to render no search field.
  final TextEditingController? searchController;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;

  /// Clear-button behavior override — screens whose clear must also
  /// reset server pagination to page 1 (customers/suppliers/payments/
  /// employees) pass their own handler; the default clears the field and
  /// re-runs [onSearchChanged] with an empty term.
  final VoidCallback? onClearSearch;

  /// Disabled while a filter makes the search meaningless (e.g. the
  /// items low-stock toggle, whose endpoint has no search param).
  final bool searchEnabled;

  final double searchWidth;

  /// Per-screen filter widgets between the search and refresh: status
  /// dropdowns via [ScreenToolbarDropdown], [DateRangeFilter] rows,
  /// filter chips, … The screen passes its own wired widgets.
  final List<Widget> filters;

  /// Secondary actions after refresh (CSV export buttons, …).
  final List<Widget> actions;

  /// The trailing "New …" buttons (kept as the screens' own widgets so
  /// every FilledButton variant stays exactly as-is).
  final List<Widget> primaryActions;

  final VoidCallback? onRefresh;

  /// When provided, the search field's suffix becomes the clear-all
  /// button (shown while [hasActiveFilters]) — the invoices/quotation/
  /// returns toolbar style. Without it the suffix is a text-clear icon
  /// shown while the field has content.
  final VoidCallback? onClearAll;
  final bool hasActiveFilters;

  final EdgeInsetsGeometry padding;

  Widget _searchField(AppLocalizations l10n) {
    final controller = searchController;
    assert(controller != null);
    return SizedBox(
      width: searchWidth,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller!,
        builder: (context, value, _) => TextField(
          controller: controller,
          enabled: searchEnabled,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: searchHint ?? l10n.commonSearch,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: onClearAll != null && hasActiveFilters
                ? IconButton(
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    tooltip: l10n.commonClear,
                    onPressed: onClearAll,
                  )
                : value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: onClearSearch ??
                        () {
                          // Cancel the screen's pending debounce so a
                          // stale timer can't resurrect the term.
                          controller.clear();
                          onSearchChanged?.call('');
                        },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (searchController != null) _searchField(l10n),
          ...filters,
          if (onRefresh != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.commonRefresh,
              onPressed: onRefresh,
            ),
          ...actions,
          ...primaryActions,
        ],
      ),
    );
  }
}
