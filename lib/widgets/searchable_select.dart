// SearchableSelect<T> — the app-wide searchable dropdown used by every
// form select and toolbar filter (PORTING.md §6: the Flutter counterpart
// of the web client's type-ahead `GenericSearchableCell`).
//
// Tapping the field opens an anchored popup with a filter TextField on
// top and the matching options below; typing narrows the list, arrow
// keys move the highlight, Enter/Tap selects, Escape or tapping outside
// closes. The selected value is shown in an InputDecorator that looks
// and behaves like the DropdownButtonFormField it replaces (including
// form validation via [validator]).
//
// The widget stays controlled: the parent owns the selection (`selected`
// + `onChanged`), exactly like the DropdownButtonFormField callers it
// replaces.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SearchableSelect<T> extends StatelessWidget {
  const SearchableSelect({
    super.key,
    required this.items,
    this.selected,
    this.onChanged,
    this.labelBuilder,
    this.validator,
    this.enabled = true,
    this.decoration,
    this.isDense = false,
    this.hint,
    this.searchHint,
    this.emptyText,
    this.menuMaxHeight = 280,
    this.textStyle = const TextStyle(fontSize: 14),
  });

  final List<T> items;
  final T? selected;
  final ValueChanged<T?>? onChanged;
  final String Function(T)? labelBuilder;

  /// Form validation for the field (e.g. a required select).
  final FormFieldValidator<T>? validator;

  /// Disabled while a form is submitting (matches the text fields).
  final bool enabled;

  /// Decoration for the trigger field — toolbar filters pass their
  /// compact InputDecoration here; forms keep the default underline look.
  final InputDecoration? decoration;

  final bool isDense;

  /// Shown in the trigger when nothing is selected (e.g. "All statuses").
  final String? hint;

  /// Placeholder for the popup's filter field.
  final String? searchHint;

  /// Label shown when the filter matches no options.
  final String? emptyText;

  final double menuMaxHeight;

  /// Trigger text style — compact screens (toolbars, panels) pass a
  /// smaller size.
  final TextStyle textStyle;

  String _label(T item) => labelBuilder?.call(item) ?? item.toString();

  /// Trigger label: the selected item's label, or [hint] when nothing is
  /// selected (the null-valued "All …" filter options).
  String _triggerLabel() {
    final sel = selected;
    if (sel == null) return hint ?? '';
    return _label(sel);
  }

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      initialValue: selected,
      validator: validator,
      builder: (field) => _SearchableSelectField<T>(
        items: items,
        label: _triggerLabel(),
        labelBuilder: labelBuilder,
        onSelected: (value) {
          field.didChange(value);
          onChanged?.call(value);
        },
        enabled: enabled,
        decoration: decoration,
        isDense: isDense,
        hint: hint,
        searchHint: searchHint,
        emptyText: emptyText,
        errorText: field.errorText,
        menuMaxHeight: menuMaxHeight,
        textStyle: textStyle,
      ),
    );
  }
}

class _SearchableSelectField<T> extends StatefulWidget {
  const _SearchableSelectField({
    required this.items,
    required this.label,
    required this.labelBuilder,
    required this.onSelected,
    required this.enabled,
    required this.decoration,
    required this.isDense,
    required this.hint,
    required this.searchHint,
    required this.emptyText,
    required this.errorText,
    required this.menuMaxHeight,
    required this.textStyle,
  });

  final List<T> items;
  final String label;
  final String Function(T)? labelBuilder;
  final ValueChanged<T?> onSelected;
  final bool enabled;
  final InputDecoration? decoration;
  final bool isDense;
  final String? hint;
  final String? searchHint;
  final String? emptyText;
  final String? errorText;
  final double menuMaxHeight;
  final TextStyle textStyle;

  @override
  State<_SearchableSelectField<T>> createState() =>
      _SearchableSelectFieldState<T>();
}

class _SearchableSelectFieldState<T> extends State<_SearchableSelectField<T>> {
  final GlobalKey _anchorKey = GlobalKey();
  final FocusNode _focus = FocusNode();
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scroll = ScrollController();

  OverlayEntry? _overlay;
  bool _open = false;
  List<T> _filtered = const [];
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space) {
        _toggle();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _searchFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowDown:
          _moveSelection(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _moveSelection(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
          if (_selectedIndex >= 0 && _selectedIndex < _filtered.length) {
            _select(_filtered[_selectedIndex]);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        case LogicalKeyboardKey.tab:
          if (_selectedIndex >= 0 && _selectedIndex < _filtered.length) {
            _select(_filtered[_selectedIndex]);
            return KeyEventResult.handled;
          }
          // No highlight — commit the typed text as-is? No: just close
          // and let Tab move focus to the next form field.
          _close();
          return KeyEventResult.ignored;
        case LogicalKeyboardKey.escape:
          _close();
          return KeyEventResult.handled;
        default:
          return KeyEventResult.ignored;
      }
    };
  }

  @override
  void dispose() {
    _removeOverlay();
    _focus.dispose();
    _searchFocus.dispose();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _labelOf(T item) =>
      widget.labelBuilder?.call(item) ?? item.toString();

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openPopup();
    }
  }

  void _openPopup() {
    if (!mounted) return;
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    // At least as wide as the trigger, clamped to the screen edge.
    final width = math.min(math.max(box.size.width, 240.0), screen.width - 16);
    var left = topLeft.dx;
    if (left + width > screen.width - 8) {
      left = math.max(8.0, screen.width - width - 8);
    }
    // Drop below the trigger; clamp so the tallest menu stays on-screen.
    final maxHeight = widget.menuMaxHeight + 52;
    final top = math.min(
      topLeft.dy + box.size.height + 2,
      math.max(8.0, screen.height - maxHeight),
    );
    setState(() {
      _open = true;
      _filtered = [...widget.items];
      _selectedIndex = -1;
    });
    _overlay = OverlayEntry(
      builder: (overlayContext) => _popup(overlayContext, left, top, width),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _close() {
    _removeOverlay();
    if (mounted) setState(() => _open = false);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _moveSelection(int delta) {
    if (_filtered.isEmpty) return;
    final count = _filtered.length;
    setState(() {
      _selectedIndex = _selectedIndex < 0
          ? (delta > 0 ? 0 : count - 1)
          : (_selectedIndex + delta + count) % count;
    });
    _overlay?.markNeedsBuild(); // the popup lives in a separate overlay tree
    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (!_scroll.hasClients || _selectedIndex < 0) return;
    const extent = 40.0;
    final target = _selectedIndex * extent;
    final position = _scroll.position;
    if (target < position.pixels) {
      _scroll.jumpTo(target);
    } else if (target + extent > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(target - position.viewportDimension + extent);
    }
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? [...widget.items]
          : [
              for (final item in widget.items)
                if (_labelOf(item).toLowerCase().contains(q)) item,
            ];
      _selectedIndex = _filtered.isEmpty ? -1 : 0;
    });
    // The popup is a separate overlay tree — mark it dirty so the
    // filtered list actually re-renders as the user types.
    _overlay?.markNeedsBuild();
  }

  void _select(T value) {
    _close();
    widget.onSelected(value);
  }

  /// Popup built inside the overlay's own tree — never touches this
  /// state's `context` after the entry is live.
  Widget _popup(
    BuildContext overlayContext,
    double left,
    double top,
    double width,
  ) {
    final theme = Theme.of(overlayContext);
    return Stack(
      children: [
        // Full-screen barrier closes on outside tap.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: _filter,
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.menuMaxHeight),
                  child: _filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            widget.emptyText ?? 'No results',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) => _option(
                            overlayContext,
                            _filtered[index],
                            index,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _option(BuildContext overlayContext, T item, int index) {
    final theme = Theme.of(overlayContext);
    final selected = index == _selectedIndex;
    return InkWell(
      onTap: () => _select(item),
      onHover: (_) {
        if (!mounted || _selectedIndex == index) return;
        setState(() => _selectedIndex = index);
        _overlay?.markNeedsBuild();
      },
      child: Container(
        height: 40,
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Text(
          _labelOf(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = (widget.decoration ?? const InputDecoration()).copyWith(
      isDense: widget.isDense || (widget.decoration?.isDense ?? false),
      enabled: widget.enabled,
      errorText: widget.errorText,
      suffixIcon: const Icon(Icons.arrow_drop_down, size: 22),
    );
    return Focus(
      focusNode: _focus,
      child: InkWell(
        key: _anchorKey,
        onTap: widget.enabled ? _toggle : null,
        child: InputDecorator(
          decoration: decoration,
          isEmpty: widget.label.isEmpty,
        child: Text(
          widget.label.isEmpty ? (widget.hint ?? '') : widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.label.isEmpty
              ? widget.textStyle.copyWith(color: scheme.outline)
              : widget.textStyle,
        ),
        ),
      ),
    );
  }
}
