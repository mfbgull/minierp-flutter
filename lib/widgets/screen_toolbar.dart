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
//
// Keyboard shortcuts (screen_shortcuts.dart): the shell's
// ScreenShortcutScope dispatches Ctrl+F / Ctrl+N / Ctrl+R / Ctrl+E to
// the visible shell branch's toolbar (resolved at keypress time from
// the element tree — hidden branches are TickerMode-disabled), via
// [ScreenToolbarState.focusSearch], [ScreenToolbarState.triggerNew],
// [ScreenToolbarState.triggerRefresh] and
// [ScreenToolbarState.triggerExport] — the first [primaryActions]
// entry's onPressed becomes the Ctrl+N callback and the first enabled
// [actions] entry (the CSV-export slot) the Ctrl+E callback, so the
// 40+ screens need no per-screen wiring. The same affordances are
// advertised in the UI: the search hint shows the Ctrl+F chord, the
// first primary action is wrapped in a Ctrl+N tooltip (its own label
// already says what it creates), the refresh button's tooltip shows
// Ctrl+R, and the first enabled export action a Ctrl+E tooltip.

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'searchable_select.dart';

/// The Ctrl+F / Ctrl+N / Ctrl+R / Ctrl+E chords as shown in the UI
/// (universal key names, so not localized). These must stay in sync with
/// the key bindings in screen_shortcuts.dart.
const String kShortcutFindChord = 'Ctrl+F';
const String kShortcutNewChord = 'Ctrl+N';
const String kShortcutRefreshChord = 'Ctrl+R';
const String kShortcutExportChord = 'Ctrl+E';

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
class ScreenToolbar extends StatefulWidget {
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
    // Labeled actions that sit between the refresh button and the
    // export/primary slots — rendered but never treated as the Ctrl+E
    // export target or the Ctrl+N primary target (the dashboard's
    // "Customize" button is the first user).
    this.trailingActions = const [],
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

  /// Labeled actions after the export slot but before the primary
  /// "New …" buttons — e.g. the dashboard's Customize button. Unlike
  /// [actions], never picked as the Ctrl+E export target.
  final List<Widget> trailingActions;

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

  @override
  ScreenToolbarState createState() => ScreenToolbarState();
}

/// The toolbar's state — public so the shell's [ScreenShortcutScope] can
/// resolve the visible screen's toolbar and dispatch Ctrl+F / Ctrl+N to
/// it (see screen_shortcuts.dart).
class ScreenToolbarState extends State<ScreenToolbar> {
  /// The search field's focus node — the Ctrl+F target. Created here so
  /// the 40+ screens don't each have to own one.
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Ctrl+F — focus the search field (no-op when the screen has no search
  /// field or a filter has disabled it).
  void focusSearch() {
    if (widget.searchController == null || !widget.searchEnabled) return;
    _searchFocusNode.requestFocus();
  }

  /// Ctrl+N — fire the first primary action (the "New …" button); no-op
  /// on screens without one (read-only logs, reports).
  void triggerNew() => _onNewShortcut?.call();

  /// Ctrl+R — fire the screen's refresh callback; no-op on screens whose
  /// toolbar has no refresh button ([onRefresh] omitted).
  void triggerRefresh() => widget.onRefresh?.call();

  /// Ctrl+E — fire the first enabled secondary action (the CSV-export
  /// button slot, [actions]); no-op on screens without one.
  void triggerExport() => _exportAction?.onPressed?.call();

  /// The secondary action the Ctrl+E shortcut targets — the first
  /// [ButtonStyleButton] with a live onPressed in [widget.actions].
  /// Every screen uses [actions] for its CSV-export button
  /// (TextButton.icon), and those are disabled while loading/empty, so
  /// the live callback is read off the widget rather than re-passed by
  /// the ~25 screens. The UI hint ([_chordLabelled]) wraps exactly this
  /// same action so the advertised chord and the shortcut can never
  /// drift apart.
  ButtonStyleButton? get _exportAction {
    for (final action in widget.actions) {
      if (action is ButtonStyleButton && action.onPressed != null) {
        return action;
      }
    }
    return null;
  }

  /// The primary action the Ctrl+N shortcut targets — the first
  /// [ButtonStyleButton] with a live onPressed. Primary actions are the
  /// screens' own "New …" buttons (today FilledButton.icon / .tonalIcon,
  /// both [ButtonStyleButton] subtypes), so the callback is read off the
  /// widget rather than re-passed by 40 screens. The UI hint
  /// ([_shortcutLabelledActions]) wraps exactly this same action so the
  /// advertised chord and the shortcut can never drift apart.
  ButtonStyleButton? get _shortcutAction {
    for (final action in widget.primaryActions) {
      if (action is ButtonStyleButton && action.onPressed != null) {
        return action;
      }
    }
    return null;
  }

  /// The Ctrl+N target's onPressed.
  VoidCallback? get _onNewShortcut => _shortcutAction?.onPressed;

  Widget _searchField(AppLocalizations l10n) {
    final controller = widget.searchController;
    assert(controller != null);
    return SizedBox(
      width: widget.searchWidth,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller!,
        builder: (context, value, _) => TextField(
          controller: controller,
          focusNode: _searchFocusNode,
          enabled: widget.searchEnabled,
          onChanged: widget.onSearchChanged,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            // Advertise the Ctrl+F shortcut in the hint — the chord is
            // omitted while a filter has disabled the search (Ctrl+F is
            // inert then).
            hintText: widget.searchEnabled
                ? '${widget.searchHint ?? l10n.commonSearch}'
                    ' ($kShortcutFindChord)'
                : widget.searchHint ?? l10n.commonSearch,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: widget.onClearAll != null && widget.hasActiveFilters
                ? IconButton(
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    tooltip: l10n.commonClear,
                    onPressed: widget.onClearAll,
                  )
                : value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: l10n.commonClear,
                    onPressed: widget.onClearSearch ??
                        () {
                          // Cancel the screen's pending debounce so a
                          // stale timer can't resurrect the term.
                          controller.clear();
                          widget.onSearchChanged?.call('');
                        },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// Wraps the [target] entry of [actions] in a Tooltip showing [chord] —
  /// the action the matching shortcut fires ([_shortcutAction] for
  /// Ctrl+N, [_exportAction] for Ctrl+E). The action's own label says
  /// what it does, so the tooltip only adds the key chord; the other
  /// actions stay unwrapped.
  List<Widget> _chordLabelled(
    List<Widget> actions,
    ButtonStyleButton? target,
    String chord,
  ) {
    if (target == null) return actions;
    return [
      for (final action in actions)
        identical(action, target)
            ? Tooltip(message: chord, child: action)
            : action,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: widget.padding,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.searchController != null) _searchField(l10n),
          ...widget.filters,
          if (widget.onRefresh != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              // Advertise the Ctrl+R shortcut in the tooltip — the button
              // (and the shortcut) only exist when onRefresh is wired.
              tooltip: '${l10n.commonRefresh} ($kShortcutRefreshChord)',
              onPressed: widget.onRefresh,
            ),
          ..._chordLabelled(
            widget.actions,
            _exportAction,
            kShortcutExportChord,
          ),
          ...widget.trailingActions,
          ..._chordLabelled(
            widget.primaryActions,
            _shortcutAction,
            kShortcutNewChord,
          ),
        ],
      ),
    );
  }
}
