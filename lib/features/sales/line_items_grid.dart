// Line-items grid for the sales invoice form — the Flutter equivalent of
// the web client's `InvoiceItemsTable` (AG-Grid-style keyboard nav, spec
// §5 of pluto-grid-sales-invoice.md).
//
// PlutoGrid provides the scrolling table + row/cell data model; the
// *interaction* is fully custom, mirroring the React reference:
//
// - One cell is in edit mode at a time (`GridNavController.editingKey`),
//   rendered as a real TextField with select-on-focus. Every other cell
//   renders a display value.
// - Navigation (arrows / Enter / Tab / Escape / Ctrl+arrows) is handled
//   per-cell through FocusNode key events — the same shape as the web
//   client's `onKeyDown` on each `<input>`/cell — and runs before
//   PlutoGrid's own editor (all editable columns have
//   `enableEditingMode: false`; PlutoGrid only lays out and scrolls).
// - Moves are sequenced with a navigation token + `Timer.run` (the
//   double-rAF equivalent of `utils/focusCell.ts`) so rapid key presses
//   discard stale focus and never commit twice.
//
// Calc rules (field order, loose driver-field, discount scope) are
// reused from the ported `invoice_calculations.dart` / `invoice_line_calc.dart`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../data/models/invoice.dart' show Discount, DiscountType;
import '../../data/models/item.dart' show SaleType;
import 'calculations/invoice_calculations.dart' show getFieldOrder;
import 'calculations/invoice_line_calc.dart'
    show applyLineFieldUpdate, CalcItemLineInput, LineField;
import 'models/sales_forms.dart' show CalculableLine, DiscountScope, EditedField, FillableLine;

/// The editable columns of a line row, in web-client field-order naming.
/// Mirrors `FIELD_ORDER_ITEM` / `FIELD_ORDER_INVOICE` (invoice_calculations.dart
/// owns the source of truth for ordering).
enum LineColumn {
  description,
  quantity,
  rate,
  discountValue,
  tax,
  amount;

  /// PlutoGrid column/cell field key.
  String get field => switch (this) {
        LineColumn.description => 'description',
        LineColumn.quantity => 'qty',
        LineColumn.rate => 'rate',
        LineColumn.discountValue => 'discount',
        LineColumn.tax => 'tax',
        LineColumn.amount => 'amount',
      };

  bool get isNumber => switch (this) {
        LineColumn.description => false,
        _ => true,
      };

  static LineColumn? fromField(String field) => switch (field) {
        'description' => LineColumn.description,
        'qty' => LineColumn.quantity,
        'rate' => LineColumn.rate,
        'discount' => LineColumn.discountValue,
        'tax' => LineColumn.tax,
        'amount' => LineColumn.amount,
        _ => null,
      };
}

/// Result of a navigation move — target row index + column (`null` = no-op).
typedef NavTarget = ({int rowIdx, LineColumn column});

/// Row-model accessors over live `PlutoCell` values. The grid's row list
/// stays the single source of truth for a line. Implements the calc
/// interfaces so the shared invoice math can read/write a grid line
/// directly.
class LineRowData implements CalculableLine, FillableLine {
  LineRowData(this.row);

  final PlutoRow row;

  dynamic _cell(String field) => row.cells[field]?.value;

  void _setCell(String field, dynamic value) {
    row.cells[field]?.value = value;
  }

  @override
  String get itemId {
    final v = _cell('item');
    return v == null || v == '' ? '' : '$v';
  }

  set itemId(String value) => _setCell('item', value);

  @override
  String get description {
    final v = _cell('description');
    return v == null ? '' : '$v';
  }

  set description(String value) => _setCell('description', value);

  @override
  num get quantity => _num('qty');

  set quantity(num value) => _setCell('qty', value);

  @override
  num get rate => _num('rate');

  set rate(num value) => _setCell('rate', value);

  @override
  num get tax => _num('tax');

  set tax(num value) => _setCell('tax', value);

  num get discountValue => _num('discount');

  set discountValue(num value) => _setCell('discount', value);

  @override
  num get amount => _num('amount');

  set amount(num value) => _setCell('amount', value);

  @override
  SaleType get saleType =>
      SaleType.fromString(_cell('sale_type') ?? SaleType.packed.value);

  set saleType(SaleType value) => _setCell('sale_type', value.value);

  String get unitOfMeasure {
    final v = _cell('uom');
    return v == null ? '' : '$v';
  }

  set unitOfMeasure(String value) => _setCell('uom', value);

  num get qtyDecimalPrecision => _num('qty_prec');

  set qtyDecimalPrecision(num value) => _setCell('qty_prec', value);

  num? get roundingStep {
    final v = _cell('round_step');
    if (v == null) return null;
    final parsed = num.tryParse('$v');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  set roundingStep(num? value) => _setCell('round_step', value);

  @override
  EditedField? get lastEditedField {
    final v = _cell('last_edited');
    if (v == null) return null;
    return v == EditedField.amount.value
        ? EditedField.amount
        : EditedField.quantity;
  }

  set lastEditedField(EditedField? value) =>
      _setCell('last_edited', value?.value);

  @override
  Discount get discount =>
      Discount(type: discountType, value: discountValue);

  DiscountType get discountType =>
      DiscountType.fromString(_cell('discount_type') ?? 'flat');

  set discountType(DiscountType value) =>
      _setCell('discount_type', value.value);

  bool get hasItem => itemId.isNotEmpty;

  bool get isLoose => saleType == SaleType.loose;

  num _num(String field) {
    final v = _cell(field);
    if (v is num) return v;
    return num.tryParse('$v') ?? 0;
  }

  /// Writes a driver-field update produced by `applyLineFieldUpdate`.
  void applyPatch({
    required num quantity,
    required num amount,
    required num rate,
    required EditedField? lastEditedField,
  }) {
    this.quantity = quantity;
    this.amount = amount;
    this.rate = rate;
    this.lastEditedField = lastEditedField;
  }
}

/// Shared interaction state for the grid — one instance per grid, passed
/// to every line-cell renderer.
class GridNavController extends ChangeNotifier {
  GridNavController({
    required this.scopeOf,
    required this.rowsOf,
    required this.onGridChanged,
    required this.onMoveResolved,
  });

  /// Current discount scope (decides the discount column's existence).
  final DiscountScope Function() scopeOf;

  /// Live row list (the page's `_rows`, mutated in place by PlutoGrid).
  final List<PlutoRow> Function() rowsOf;

  /// Called after any cell-value write → the page refreshes totals/grid.
  final void Function() onGridChanged;

  /// Called when a sequenced move resolves — the page scrolls the grid to
  /// the target row (`PlutoGridStateManager.setCurrentCell`).
  final void Function(int rowIdx) onMoveResolved;

  /// Appends a new line row (Enter/Tab at the last row, Add Item). The
  /// page appends the row then calls [focusNewRow] to land on its
  /// description cell.
  void Function()? onAppendRow;

  /// Edit-focus a freshly appended row's description cell.
  void focusNewRow(PlutoRow row) {
    if (!rows.contains(row)) return;
    _schedule(row: row, column: LineColumn.description);
  }

  /// Display-focus a freshly appended row's description cell.
  void focusNewRowDisplay(PlutoRow row) {
    if (!rows.contains(row)) return;
    _schedule(row: row, column: LineColumn.description, enterEdit: false);
  }

  PlutoRow? _editingRow;
  LineColumn? _editingColumn;

  /// The cell currently in edit mode (`null` = display mode).
  (PlutoRow, LineColumn)? get editingKey =>
      _editingRow == null || _editingColumn == null
          ? null
          : (_editingRow!, _editingColumn!);

  (PlutoRow, LineColumn)? _displayTarget;

  /// The display-focused cell (highlighted, not editing).
  (PlutoRow, LineColumn)? get displayFocus => _displayTarget;

  /// In-flight text of the editing input (owned by the editing cell).
  TextEditingController? _editor;

  String get activeText => _editor?.text ?? '';

  int get _rowIndex {
    final r = _editingRow;
    return r == null ? -1 : rowsOf().indexOf(r);
  }

  DiscountScope get scope => scopeOf();

  List<PlutoRow> get rows => rowsOf();

  /// Field order for the current scope, as columns (the "walk" order).
  List<LineColumn> fieldOrder() {
    final result = <LineColumn>[];
    for (final f in getFieldOrder(scope)) {
      final c = LineColumn.fromField(f);
      if (c != null) result.add(c);
    }
    return result;
  }

  bool navigable(PlutoRow row, LineColumn column) {
    if (column == LineColumn.discountValue) return scope == DiscountScope.item;
    if (column == LineColumn.amount) return LineRowData(row).isLoose;
    return true;
  }

  LineColumn? nextField(LineColumn column) {
    final order = fieldOrder();
    final i = order.indexOf(column);
    return (i >= 0 && i + 1 < order.length) ? order[i + 1] : null;
  }

  bool isEditing(PlutoRow row, LineColumn column) =>
      _editingRow == row && _editingColumn == column;

  bool isLastRow(PlutoRow row) => rows.indexOf(row) == rows.length - 1;

  // ── Editing lifecycle ─────────────────────────────────────────

  void beginEdit(PlutoRow row, LineColumn column) {
    _editingRow = row;
    _editingColumn = column;
    _displayTarget = null;
    _bump();
  }

  void endEdit() {
    _editingRow = null;
    _editingColumn = null;
    _bump();
  }

  void _setDisplayFocus(PlutoRow row, LineColumn column) {
    _displayTarget = (row, column);
    _bump();
  }

  void attachEditor(TextEditingController controller) => _editor = controller;

  void detachEditor(TextEditingController controller) {
    if (_editor == controller) _editor = null;
  }

  // ── Commit ────────────────────────────────────────────────────

  /// Commit the editing cell's in-flight value into its line, then leave
  /// edit mode. Loose-line amount edits route through the driver-field
  /// rule so the driven side stays consistent.
  void commitCurrent() {
    final key = editingKey;
    if (key == null) return;
    final (row, column) = key;
    final data = LineRowData(row);
    final text = activeText;

    switch (column) {
      case LineColumn.description:
        data.description = text;
        break;
      case LineColumn.quantity:
        _applyDriver(row, LineField.quantity, _parseNum(text));
        break;
      case LineColumn.rate:
        _applyDriver(row, LineField.rate, _parseNum(text));
        break;
      case LineColumn.tax:
        data.tax = _parseNum(text);
        break;
      case LineColumn.discountValue:
        data.discountValue = _parseNum(text);
        break;
      case LineColumn.amount:
        if (data.isLoose) {
          _applyDriver(row, LineField.amount, _parseNum(text));
        }
        break;
    }
    endEdit();
    _bump();
  }

  void _applyDriver(PlutoRow row, LineField field, num value) {
    final data = LineRowData(row);
    final patch = applyLineFieldUpdate(
      CalcItemLineInput(
        saleType: data.saleType,
        quantity: data.quantity,
        amount: data.amount,
        rate: data.rate,
        qtyDecimalPrecision: data.qtyDecimalPrecision,
        roundingStep: data.roundingStep,
        lastEditedField: data.lastEditedField,
      ),
      field,
      value,
    );
    data.applyPatch(
      quantity: patch.quantity,
      amount: patch.amount,
      rate: patch.rate,
      lastEditedField: patch.lastEditedField,
    );
    _bump();
  }

  /// Escape — revert the in-flight value and exit edit mode.
  void revertCurrent() {
    endEdit();
    _bump();
  }

  // ── Navigation ────────────────────────────────────────────────

  KeyEventResult handleEditKey(
    PlutoRow row,
    LineColumn column,
    KeyDownEvent event, {
    required bool isLastRow,
    required bool isTextCaretStart,
    required bool isTextCaretEnd,
  }) {
    final key = event.logicalKey;
    final data = LineRowData(row);

    // Ctrl+Arrow steppers — number cells only, never navigation.
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        if (!column.isNumber || column == LineColumn.amount) {
          return KeyEventResult.handled;
        }
        final current = _parseNum(_editor?.text ?? '');
        var newValue =
            key == LogicalKeyboardKey.arrowUp ? current + 1 : current - 1;
        if (column == LineColumn.tax && newValue > 100) newValue = 100;
        if (newValue < 0) newValue = 0;
        if (column == LineColumn.tax) {
          data.tax = newValue;
        } else {
          _applyDriver(row, _driverFor(column), newValue);
        }
        _editor?.text = newValue.toString();
        _bump();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        // First row — do nothing (reference behavior; value stays in-flight).
        if (_rowIndex > 0) {
          _commitThen(row, column, rowOffset: -1, colOffset: 0);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        // Last row — do nothing; only Enter appends a row.
        if (_rowIndex < rows.length - 1) {
          _commitThen(row, column, rowOffset: 1, colOffset: 0);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowLeft:
        if (column.isNumber || isTextCaretStart) {
          _commitThen(row, column, rowOffset: 0, colOffset: -1);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        if (column.isNumber || isTextCaretEnd) {
          _commitThen(row, column, rowOffset: 0, colOffset: 1);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.enter:
        final isLast = _rowIndex == rows.length - 1;
        if (isLast) {
          commitCurrent();
          onAppendRow?.call();
        } else if (_rowIndex >= 0) {
          _commitThen(row, column, rowOffset: 1, colOffset: 0);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.tab:
        commitCurrent();
        final next = nextField(column);
        if (next != null) {
          _schedule(row: row, column: next);
        } else if (_rowIndex == rows.length - 1) {
          onAppendRow?.call();
        } else if (_rowIndex >= 0) {
          final first = firstNavigable(rows[_rowIndex + 1]);
          if (first != null) {
            _schedule(row: rows[_rowIndex + 1], column: first);
          }
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.escape:
        revertCurrent();
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  /// Display-mode nav — cell focused but not editing.
  KeyEventResult handleDisplayKey(
    PlutoRow row,
    LineColumn column,
    KeyDownEvent event, {
    required bool isLastRow,
  }) {
    final key = event.logicalKey;
    final rowIdx = rows.indexOf(row);
    switch (key) {
      case LogicalKeyboardKey.enter:
        beginEdit(row, column);
        _bump();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowUp:
        if (rowIdx > 0) {
          _schedule(row: rows[rowIdx - 1], column: column, enterEdit: false);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        if (rowIdx >= 0 && rowIdx < rows.length - 1) {
          _schedule(row: rows[rowIdx + 1], column: column, enterEdit: false);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.tab:
        final next = nextField(column);
        if (next != null) {
          _schedule(row: row, column: next, enterEdit: false);
        } else if (isLastRow) {
          onAppendRow?.call();
        } else if (rowIdx >= 0 && rowIdx < rows.length - 1) {
          final target = firstNavigable(rows[rowIdx + 1]);
          if (target != null) {
            _schedule(row: rows[rowIdx + 1], column: target, enterEdit: false);
          }
        }
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  /// Called when a row is removed (trash button) — drop stale targets.
  void handleRowRemoved(PlutoRow removed) {
    if (_editingRow == removed) {
      _editingRow = null;
      _editingColumn = null;
    }
    if (_displayTarget != null && _displayTarget!.$1 == removed) {
      _displayTarget = null;
    }
  }

  // ── Navigation internals ──────────────────────────────────────

  LineColumn? firstNavigable(PlutoRow row) {
    for (final c in fieldOrder()) {
      if (navigable(row, c)) return c;
    }
    return null;
  }

  // ── Public move primitives (used by the searchable description cell, whose
  //    key handling differs from the generic number cell) ──────────

  /// Click-to-edit: commit any in-flight cell first (blur commit), then
  /// begin editing the clicked cell.
  void requestEdit(PlutoRow row, LineColumn column) {
    if (isEditing(row, column)) return;
    if (_editingRow != null) commitCurrent();
    beginEdit(row, column);
  }

  /// Commit current, then move to an explicit target cell (no commit of
  /// the target — used after an item selection writes the row).
  void moveToCell(PlutoRow row, LineColumn column) {
    _schedule(row: row, column: column);
  }

  /// Commit + move down/up to the same column of the next/previous row.
  void commitMoveDown(PlutoRow row, LineColumn column) =>
      _commitThen(row, column, rowOffset: 1, colOffset: 0);

  void commitMoveUp(PlutoRow row, LineColumn column) =>
      _commitThen(row, column, rowOffset: -1, colOffset: 0);

  /// Commit + Enter semantics of the searchable cell: next field, else
  /// append (last row) / next row's first field.
  void commitEnterSearchable(PlutoRow row, LineColumn column) {
    commitCurrent();
    final next = nextField(column);
    if (next != null) {
      _schedule(row: row, column: next);
    } else if (_rowIndex == rows.length - 1) {
      onAppendRow?.call();
    } else if (_rowIndex >= 0) {
      final first = firstNavigable(rows[_rowIndex + 1]);
      if (first != null) _schedule(row: rows[_rowIndex + 1], column: first);
    }
  }

  /// Commit + Tab semantics of the searchable cell (same as Enter here:
  /// next field → append / next row).
  void commitTabSearchable(PlutoRow row, LineColumn column) =>
      commitEnterSearchable(row, column);

  /// Commit the current cell, then resolve a row/column move with the
  /// token/Timer sequencing (`enterEdit:false` = display-focus move).
  void _commitThen(
    PlutoRow row,
    LineColumn column, {
    required int rowOffset,
    required int colOffset,
  }) {
    commitCurrent();
    final target = resolveTarget(
      rows: rows,
      fromRowIdx: rows.indexOf(row),
      fromColumn: column,
      rowOffset: rowOffset,
      colOffset: colOffset,
      navigableOf: navigable,
      order: fieldOrder(),
    );
    if (target == null) return;
    _schedule(row: rows[target.rowIdx], column: target.column);
  }

  void _schedule({
    required PlutoRow row,
    required LineColumn column,
    bool enterEdit = true,
  }) {
    if (!rows.contains(row)) return;
    final token = ++_navToken;
    _isNavigating = true;
    _bump();
    Timer.run(() {
      if (token != _navToken) return; // stale — discarded
      _isNavigating = false;
      if (enterEdit) {
        beginEdit(row, column);
      } else {
        _setDisplayFocus(row, column);
      }
      final idx = rows.indexOf(row);
      if (idx >= 0) onMoveResolved(idx);
    });
  }

  int _navToken = 0;
  bool _isNavigating = false;

  /// True while a sequenced move is pending (suppresses stray commits).
  bool get isNavigating => _isNavigating;

  void _bump() => notifyListeners();

  static num _parseNum(String text) => num.tryParse(text.trim()) ?? 0;

  static LineField _driverFor(LineColumn column) => switch (column) {
        LineColumn.quantity => LineField.quantity,
        LineColumn.rate => LineField.rate,
        LineColumn.amount => LineField.amount,
        _ => LineField.quantity,
      };
}

/// Pure target resolution (spec §5.2). `null` = no-op direction.
NavTarget? resolveTarget({
  required List<PlutoRow> rows,
  required int fromRowIdx,
  required LineColumn fromColumn,
  required int rowOffset,
  required int colOffset,
  required bool Function(PlutoRow, LineColumn) navigableOf,
  required List<LineColumn> order,
}) {
  if (rowOffset != 0) {
    final targetIdx = fromRowIdx + rowOffset;
    if (targetIdx < 0 || targetIdx >= rows.length) return null;
    final row = rows[targetIdx];
    if (navigableOf(row, fromColumn)) {
      return (rowIdx: targetIdx, column: fromColumn);
    }
    // Column absent in the target row — walk forward to the first
    // navigable column (spec §5.2 "column-walk").
    for (final c in order) {
      if (navigableOf(row, c)) return (rowIdx: targetIdx, column: c);
    }
    return null;
  }

  if (colOffset != 0) {
    final currentIndex = order.indexOf(fromColumn);
    var i = currentIndex + colOffset;
    while (i >= 0 && i < order.length) {
      if (navigableOf(rows[fromRowIdx], order[i])) {
        return (rowIdx: fromRowIdx, column: order[i]);
      }
      i += colOffset;
    }
    // ArrowLeft past the first column → row up, same column (the
    // reference implements row-up; keeping that observable behavior).
    if (colOffset < 0 && fromRowIdx > 0) {
      return (rowIdx: fromRowIdx - 1, column: fromColumn);
    }
    return null; // ArrowRight past the last navigable column — no-op
  }

  return null;
}
