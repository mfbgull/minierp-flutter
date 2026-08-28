// Interactive line-item cell widgets for the invoice grid — replace
// PlutoGrid's built-in editor with the AG-Grid-style interaction model
// (spec §5). Each cell renders a display value or, when it is the single
// editing cell, a TextField that owns keyboard navigation through
// `GridNavController`. The description cell embeds the client-side
// item-search dropdown (spec §5.5).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/item.dart' show Item;
import '../../l10n/app_localizations.dart';
import 'calculations/invoice_calculations.dart' show calculateItemTotal;
import 'calculations/invoice_line_calc.dart'
    show CalcItemLineInput, lineIssue, LineErrorSeverity;
import 'line_items_grid.dart';
import 'models/sales_forms.dart' show DiscountScope, EditedField;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Re-assert focus on a cell editor after it mounts. A TextField's
/// `autofocus` only registers the enclosing FocusScope's autofocus
/// candidate (`FocusScope.autofocus`) and does NOT focus while the scope
/// is unfocused — the normal state here (the PlutoGrid scope is only ever
/// focused by our own cells), so the editor would render without focus,
/// the IME would never connect, and typing would do nothing. Request the
/// editor node directly, and repeat on the next frame: PlutoGrid's
/// `setKeepFocus` grabs the grid node the first time its FocusScope gains
/// focus (`gridFocusNode.requestFocus`), and the second request lands
/// after `keepFocus` is already true, when the scope no longer steals.
void _assertEditorFocus(FocusNode node, State state) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted) return;
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.mounted) node.requestFocus();
    });
  });
}

/// Serial `#` column (read-only).
class SerialCell extends StatelessWidget {
  const SerialCell({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => Center(
    child: Text('${index + 1}', style: const TextStyle(color: Colors.black54)),
  );
}

/// Read-only remove (trash) cell.
class RemoveCell extends StatelessWidget {
  const RemoveCell({super.key, required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Center(
    child: IconButton(
      tooltip: AppLocalizations.of(context)!.commonRemove,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.remove_circle_outline, size: 18),
      onPressed: onRemove,
    ),
  );
}

/// A number / text line cell (qty, rate, tax, discount, amount).
class LineCell extends StatefulWidget {
  const LineCell({
    super.key,
    required this.nav,
    required this.row,
    required this.column,
    this.onBeginEdit,
    this.overlayBuilder,
  });

  final GridNavController nav;
  final PlutoRow row;
  final LineColumn column;

  /// Fired once when this cell enters edit mode (the rate cell uses it to
  /// kick off the price-history lookup).
  final void Function(PlutoRow row)? onBeginEdit;

  /// Optional overlay anchored under the cell while it is editing
  /// (price-history hint). Returning `null` closes it.
  final Widget? Function()? overlayBuilder;

  @override
  State<LineCell> createState() => _LineCellState();
}

class _LineCellState extends State<LineCell> {
  final FocusNode _focus = FocusNode();
  final GlobalKey _anchorKey = GlobalKey();
  late final FocusNode _editFocus;
  OverlayEntry? _overlay;
  bool _announcedEdit = false;

  /// Set once the hint is dismissed via click-outside; suppresses the
  /// per-frame re-insert of the overlay while this edit session lives.
  bool _dismissed = false;
  TextEditingController? _editor;

  /// Whether the select-all-on-entry was already applied for this edit
  /// session. Re-applying it on later rebuilds would make the next IME
  /// commit *replace* the selected text instead of inserting — the
  /// one-character bug (each keystroke ended up the only character).
  bool _selectedAll = false;

  GridNavController get nav => widget.nav;
  PlutoRow get row => widget.row;
  LineColumn get column => widget.column;
  LineRowData get data => LineRowData(row);
  bool get _editing => nav.isEditing(row, column);

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (node, event) {
      final e = event is KeyDownEvent ? event : null;
      if (e == null) return KeyEventResult.ignored;
      return nav.handleDisplayKey(
        row,
        column,
        e,
        isLastRow: nav.isLastRow(row),
      );
    };
    _editFocus = FocusNode(
      onKeyEvent: (node, event) => _onEditKey(node, event, _editor),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _focus.dispose();
    _editFocus.dispose();
    // Drop the nav's editor reference so it can't read a disposed
    // controller (e.g. a row removed mid-edit).
    if (_editor != null) nav.detachEditor(_editor!);
    _editor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: nav,
      builder: (context, _) {
        _syncEditSideEffects();
        if (column == LineColumn.amount) return _buildAmount(context);
        if (column == LineColumn.quantity &&
            data.unitOfMeasure.isNotEmpty &&
            !_editing) {
          return _withBadge(context);
        }
        return _editing ? _editorInput() : _display(context);
      },
    );
  }

  /// Edit-mode entry/exit hooks: announce the first edit frame and keep
  /// the anchored overlay (price hint) in sync.
  void _syncEditSideEffects() {
    if (_editing && !_announcedEdit) {
      _announcedEdit = true;
      _dismissed = false;
      _selectedAll = false;
      // If the controller is empty (e.g. first edit after a fresh mount or
      // after the row data was updated externally), seed it with the
      // current cell value so the editor doesn't show blank/zero.
      final controller = _editor;
      if (controller != null && controller.text.isEmpty) {
        controller.text = _displayText();
      }
      // `autofocus` alone never focuses this editor inside the PlutoGrid
      // FocusScope — assert focus explicitly (spec §2.3/§5.2).
      _assertEditorFocus(_editFocus, this);
      final notify = widget.onBeginEdit;
      if (notify != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) notify(row);
        });
      }
    } else if (!_editing && _announcedEdit) {
      _announcedEdit = false;
      _removeOverlay();
    }
    if (widget.overlayBuilder == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final content = _editing ? widget.overlayBuilder!() : null;
      if (content == null || _dismissed) {
        _removeOverlay();
      } else if (_overlay == null) {
        _insertOverlay(content);
      } else {
        _overlay!.markNeedsBuild();
      }
    });
  }

  void _insertOverlay(Widget content) {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final topLeft = box.localToGlobal(Offset.zero);
    _overlay = OverlayEntry(
      // Full-screen translucent barrier closes the hint on click-outside
      // without stealing the editor's focus (no focus node; the hint body
      // is IgnorePointer). Taps land on the barrier, so a second click is
      // needed to edit elsewhere — matches the reference's close-on-leave.
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissOverlay,
            ),
          ),
          Positioned(
            left: topLeft.dx,
            top: topLeft.dy + box.size.height + 2,
            child: widget.overlayBuilder?.call() ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  /// User dismissed the hint by tapping outside — remember for this edit
  /// session so the per-frame sync does not re-insert it.
  void _dismissOverlay() {
    _dismissed = true;
    _removeOverlay();
  }

  // ── Editor ─────────────────────────────────────────────────────

  Widget _editorInput() {
    final controller = _editor ??= TextEditingController(text: _displayText());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Select-all exactly once per session: re-applying it on rebuilds
      // would make every subsequent IME commit replace the text.
      if (!_selectedAll) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
        _selectedAll = true;
      }
      nav.attachEditor(controller);
    });
    return Container(
      key: _anchorKey,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextField(
        controller: controller,
        focusNode: _editFocus,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => nav.attachEditor(controller),
      ),
    );
  }

  KeyEventResult _onEditKey(
    FocusNode node,
    KeyEvent event,
    TextEditingController? controller,
  ) {
    final e = event is KeyDownEvent ? event : null;
    // KeyUp / no-editor keys still must not be swallowed by the grid's
    // FocusScope (it returns `handled` for everything) — pass them to the
    // IME path too.
    if (e == null || controller == null) return nav.passToIME();
    final sel = controller.selection;
    return nav.handleEditKey(
      row,
      column,
      e,
      isLastRow: nav.isLastRow(row),
      isTextCaretStart: sel.isValid && sel.start == 0,
      isTextCaretEnd: sel.isValid && sel.end == controller.text.length,
    );
  }

  // ── Display ────────────────────────────────────────────────────

  Widget _display(BuildContext context) {
    final highlight =
        nav.displayFocus != null &&
        nav.displayFocus!.$1 == row &&
        nav.displayFocus!.$2 == column;
    return Focus(
      focusNode: _focus,
      skipTraversal: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => nav.requestEdit(row, column),
          child: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: highlight
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : null,
            ),
            child: Text(_displayText(), style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
    );
  }

  Widget _withBadge(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(child: _display(context)),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: AppBorderRadius.xsRadius,
          ),
          child: Text(data.unitOfMeasure, style: const TextStyle(fontSize: 10)),
        ),
      ],
    );
  }

  Widget _buildAmount(BuildContext context) {
    final loose = data.isLoose;
    if (_editing && loose) return _editorInput();
    final issue = loose
        ? lineIssue(
            CalcItemLineInput(
              saleType: data.saleType,
              quantity: data.quantity,
              amount: data.amount,
              rate: data.rate,
              qtyDecimalPrecision: data.qtyDecimalPrecision,
              roundingStep: data.roundingStep,
              lastEditedField: EditedField.amount,
            ),
          )
        : null;
    final display = _display(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        display,
        if (issue != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              issue.message,
              style: TextStyle(
                fontSize: 10,
                height: 1.0,
                color: issue.severity == LineErrorSeverity.error
                    ? const Color(0xffdc2626)
                    : const Color(0xffd97706),
              ),
            ),
          ),
      ],
    );
  }

  String _displayText() {
    switch (column) {
      case LineColumn.description:
        return data.description;
      case LineColumn.quantity:
        return data.quantity.toStringAsFixed(data.qtyDecimalPrecision.toInt());
      case LineColumn.rate:
        return data.rate.toStringAsFixed(2);
      case LineColumn.tax:
        return _numText(data.tax);
      case LineColumn.discountValue:
        return _numText(data.discountValue);
      case LineColumn.amount:
        return data.isLoose
            ? Formatters.currency(data.amount)
            : Formatters.currency(
                calculateItemTotal(data, discountScope: DiscountScope.item),
              );
    }
  }

  static String _numText(num value) =>
      value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
}

/// The searchable description cell (spec §5.5): typing opens a filtered
/// dropdown of sellable items; Enter/Tab selects and moves to quantity.
class DescriptionCell extends StatefulWidget {
  const DescriptionCell({
    super.key,
    required this.nav,
    required this.row,
    required this.items,
    required this.formatCurrency,
    required this.onItemSelected,
  });

  final GridNavController nav;
  final PlutoRow row;

  /// Precomputed search pool (finished_good OR purchased items).
  final List<Item> items;

  final String Function(num) formatCurrency;

  /// Writes the selected item into the row and moves to quantity.
  final void Function(PlutoRow row, Item item) onItemSelected;

  @override
  State<DescriptionCell> createState() => _DescriptionCellState();
}

class _DescriptionCellState extends State<DescriptionCell> {
  static const double _itemExtent = 52;

  final FocusNode _focus = FocusNode();
  late final FocusNode _editFocus;
  final GlobalKey _anchorKey = GlobalKey();
  final ScrollController _scroll = ScrollController();
  TextEditingController? _controller;
  OverlayEntry? _overlay;
  List<Item> _filtered = const [];
  int _selectedIndex = -1;
  bool _open = false;

  /// Whether this cell was in edit mode on the last build — used to
  /// detect edit-session boundaries (reset the editor, close the
  /// dropdown) without rebuilding during the build phase.
  bool _wasEditing = false;

  /// Whether the select-all-on-entry was already applied for this edit
  /// session. Re-applying it on later rebuilds (the per-keystroke
  /// `_filter` setState) would make the next IME commit *replace* the
  /// selected text instead of inserting — the one-character bug.
  bool _selectedAll = false;

  GridNavController get nav => widget.nav;
  PlutoRow get row => widget.row;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (node, event) {
      final e = event is KeyDownEvent ? event : null;
      if (e == null) return KeyEventResult.ignored;
      return nav.handleDisplayKey(
        row,
        LineColumn.description,
        e,
        isLastRow: nav.isLastRow(row),
      );
    };
    _editFocus = FocusNode(
      onKeyEvent: (node, event) => _onEditKey(node, event, _controller),
    );
  }

  @override
  void dispose() {
    _closeOverlay();
    _focus.dispose();
    _editFocus.dispose();
    _scroll.dispose();
    // Drop the nav's editor reference so it can't read a disposed
    // controller (e.g. a row removed mid-edit).
    if (_controller != null) nav.detachEditor(_controller!);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DescriptionCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Item pool arrives late (spec §4.5): re-run the in-flight query so
    // matches appear without re-typing. The refilter must wait for the
    // build phase to finish — `_filter` marks the dropdown overlay
    // dirty, and calling that synchronously here crashes with
    // "markNeedsBuild() called during build" (the page memoizes the pool
    // so `!=` only fires on genuine content changes).
    if (oldWidget.items != widget.items &&
        nav.isEditing(row, LineColumn.description) &&
        _controller != null &&
        _controller!.text.trim().isNotEmpty) {
      final query = _controller!.text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Skip when the dropdown was closed in the meantime (e.g. Escape)
        // — refiltering would reopen it against the user's intent.
        if (!mounted || _controller == null || !_open) return;
        _filter(query);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: nav,
      builder: (context, _) {
        final editing = nav.isEditing(row, LineColumn.description);
        if (editing && !_wasEditing) {
          // Fresh edit session: drop any stale query from a previous
          // session and re-sync with the row's value (imported lines
          // carry no `description` cell — show the item-name fallback,
          // spec §8.19). Safe to write `c.text` here: no TextField is
          // attached to the controller during the display→edit frame,
          // so the notify has no listeners.
          final c = _controller;
          if (c != null && c.text != _displayDescription) {
            c.text = _displayDescription;
            _filtered = const [];
            _selectedIndex = -1;
          }
          _selectedAll = false;
          // `autofocus` alone never focuses this editor inside the
          // PlutoGrid FocusScope — assert focus explicitly (spec §2.3).
          _assertEditorFocus(_editFocus, this);
        } else if (!editing && _wasEditing) {
          // Left edit mode (navigation commit / Escape / selection):
          // drop the dropdown overlay. Deferred — removing an overlay
          // entry marks its ancestor dirty, which crashes during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _closeOverlay();
          });
        }
        _wasEditing = editing;
        if (!editing) return _display();
        return _editor();
      },
    );
  }

  // ── Display ────────────────────────────────────────────────────

  /// What the cell shows: the stored description, or (edit prefill — the
  /// imported `InvoiceItem` has no description) a fallback item name
  /// resolved from the search pool by `item_id`, else the hint.
  String get _displayDescription {
    final data = LineRowData(row);
    if (data.description.isNotEmpty) return data.description;
    final id = int.tryParse(data.itemId);
    if (id != null) {
      for (final it in widget.items) {
        if (it.id == id) return it.itemName;
      }
    }
    return '';
  }

  Widget _display() {
    final highlight =
        nav.displayFocus != null &&
        nav.displayFocus!.$1 == row &&
        nav.displayFocus!.$2 == LineColumn.description;
    final isEmpty = _displayDescription.isEmpty;
    return Focus(
      focusNode: _focus,
      skipTraversal: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => nav.requestEdit(row, LineColumn.description),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: highlight
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : null,
            ),
            child: Text(
              isEmpty ? l10n.salesClicktoadditem : _displayDescription,
              style: TextStyle(
                fontSize: 13,
                color: isEmpty ? Theme.of(context).colorScheme.outline : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  // ── Editor + dropdown ──────────────────────────────────────────

  Widget _editor() {
    final controller = _controller ??= TextEditingController(
      text: _displayDescription,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Select-all exactly once per session: re-applying it on rebuilds
      // (each keystroke re-runs `_filter` → setState) would make every
      // subsequent IME commit replace the typed text.
      if (!_selectedAll) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
        _selectedAll = true;
      }
      nav.attachEditor(controller);
    });
    return Container(
      key: _anchorKey,
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        focusNode: _editFocus,
        autofocus: true,
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8),
        ),
        onChanged: (text) {
          nav.attachEditor(controller);
          _filter(text);
        },
      ),
    );
  }

  KeyEventResult _onEditKey(
    FocusNode node,
    KeyEvent event,
    TextEditingController? controller,
  ) {
    final e = event is KeyDownEvent ? event : null;
    // KeyUp / no-editor keys still must not be swallowed by the grid's
    // FocusScope — pass them to the IME path too.
    if (e == null || controller == null) return nav.passToIME();
    final key = e.logicalKey;

    // Dropdown open with matching options — navigate/select (spec §4.4).
    if (_open && _filtered.isNotEmpty) {
      switch (key) {
        case LogicalKeyboardKey.arrowDown:
          _selectedIndex = (_selectedIndex + 1) % _filtered.length;
          setState(() {});
          // The dropdown lives in a separate overlay tree — `setState`
          // alone never re-renders it, so without this the highlight
          // stays put and the list never scrolls (the customer popup
          // marks its overlay dirty the same way).
          _refreshOverlay();
          _scrollToSelected();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _selectedIndex = _selectedIndex <= 0
              ? _filtered.length - 1
              : _selectedIndex - 1;
          setState(() {});
          _refreshOverlay();
          _scrollToSelected();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.tab:
        case LogicalKeyboardKey.arrowRight:
          // Right behaves like Enter/Tab while the dropdown is open:
          // select the highlighted item and hand off to quantity (the
          // reference's ArrowRight → save + focus quantity).
          if (_selectedIndex >= 0 && _selectedIndex < _filtered.length) {
            _selectItem(_filtered[_selectedIndex]);
            return KeyEventResult.handled;
          }
        case LogicalKeyboardKey.escape:
          _closeOverlay();
          setState(() {});
          return KeyEventResult.handled;
        default:
          break;
      }
    }

    // Dropdown open with no matches — "No products found". Enter/Tab/
    // ArrowRight are blocked (a real item is required, spec §4.4); ↑/↓
    // still navigate (discarding the unmatched text on commit); Escape
    // closes the dropdown and stays editing.
    if (_open && _filtered.isEmpty) {
      switch (key) {
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.tab:
        case LogicalKeyboardKey.arrowRight:
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          _closeOverlay();
          setState(() {});
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          nav.commitMoveDown(row, LineColumn.description);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          nav.commitMoveUp(row, LineColumn.description);
          return KeyEventResult.handled;
        default:
          break;
      }
    }

    switch (key) {
      case LogicalKeyboardKey.arrowDown:
        nav.commitMoveDown(row, LineColumn.description);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        nav.commitMoveUp(row, LineColumn.description);
        return KeyEventResult.handled;
      // Dropdown closed. Right moves forward once an item is already on
      // the row (commit + next field → qty, mirroring the number cells);
      // with no item it stays blocked — no free-text lines (spec §4.4).
      case LogicalKeyboardKey.arrowRight:
        if (LineRowData(row).hasItem) {
          nav.commitMoveRight(row, LineColumn.description);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.tab:
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        nav.revertCurrent();
        return KeyEventResult.handled;
      default:
        // Character keys (e.g. continuing to type while the dropdown is
        // open) must reach the IME, not the grid's FocusScope (spec §4.4).
        return nav.passToIME();
    }
  }

  void _filter(String text) {
    final query = text.trim().toLowerCase();
    // Empty query → close the dropdown (no first-10 fallback, spec §4.2).
    if (query.isEmpty) {
      setState(() {
        _filtered = const [];
        _selectedIndex = -1;
      });
      _closeOverlay();
      return;
    }
    final pool = widget.items;
    final matches = [
      for (final it in pool)
        if (it.itemName.toLowerCase().contains(query) ||
            it.itemCode.toLowerCase().contains(query))
          it,
    ];
    setState(() {
      _filtered = matches;
      _selectedIndex = matches.isEmpty ? -1 : 0;
    });
    _openDropdown();
    _refreshOverlay();
  }

  /// Opens the overlay once (positioned below the cell). The filtered
  /// list is owned by [_filter] — this never resets it.
  void _openDropdown() {
    if (!mounted || _open) return;
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    if (box == null) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final width = math.max(box.size.width, 260.0);
    setState(() => _open = true);
    _overlay = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: topLeft.dx,
        top: topLeft.dy + box.size.height + 2,
        width: width,
        child: _dropdown(overlayContext),
      ),
    );
    overlay.insert(_overlay!);
  }

  void _refreshOverlay() => _overlay?.markNeedsBuild();

  void _closeOverlay() {
    _overlay?.remove();
    _overlay = null;
    _open = false;
  }

  /// Built inside the overlay's own tree — never touches this state's
  /// `context` (the overlay can outlive the cell during route pops / grid
  /// rebuilds, and a defunct `State.context` throws).
  Widget _dropdown(BuildContext overlayContext) {
    final theme = Theme.of(overlayContext);
    final texts = AppLocalizations.of(overlayContext)!;
    return Material(
      elevation: 6,
      borderRadius: AppBorderRadius.xsRadius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: AppBorderRadius.xsRadius,
        ),
        child: _filtered.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  texts.salesNoproductsfound,
                  style: const TextStyle(fontSize: 13),
                ),
              )
            : ListView.builder(
                controller: _scroll,
                itemExtent: _itemExtent,
                itemCount: _filtered.length,
                itemBuilder: (context, index) =>
                    _option(overlayContext, _filtered[index], index),
              ),
      ),
    );
  }

  Widget _option(BuildContext overlayContext, Item item, int index) {
    final theme = Theme.of(overlayContext);
    final selected = index == _selectedIndex;
    return InkWell(
      onTap: () => _selectItem(item),
      onHover: (_) {
        if (!mounted) return;
        if (_selectedIndex != index) {
          setState(() => _selectedIndex = index);
          _refreshOverlay();
        }
      },
      child: Container(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    item.itemName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item.itemCode,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  'Stock: ${item.currentStock}',
                  style: const TextStyle(fontSize: 11),
                ),
                const Spacer(),
                Text(
                  widget.formatCurrency(item.standardSellingPrice ?? 0),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToSelected() {
    if (!_scroll.hasClients) return;
    final target = _selectedIndex * _itemExtent;
    final position = _scroll.position;
    if (target < position.pixels) {
      _scroll.jumpTo(target);
    } else if (target + _itemExtent >
        position.pixels + position.viewportDimension) {
      _scroll.jumpTo(target - position.viewportDimension + _itemExtent);
    }
  }

  void _selectItem(Item item) {
    // Idempotent (spec §4.5): a second activation after the overlay is
    // already closed is a no-op — no double-fire on double-tap/Enter.
    if (!mounted || !_open) return;
    _closeOverlay();
    setState(() {
      _filtered = const [];
      _selectedIndex = -1;
    });
    widget.onItemSelected(row, item);
  }
}
