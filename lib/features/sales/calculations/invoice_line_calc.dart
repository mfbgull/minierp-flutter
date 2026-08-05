// Invoice line calculation — packed vs loose items (PORTING.md §7).
// 1:1 port of `calculations/invoiceLineCalc.ts`.
//
// packed: quantity drives amount (amount = qty × rate), as it always has.
// loose:  bidirectional — whichever of quantity/amount the user last
//         edited drives the other.
//
// All functions are pure; no UI/state imports. `SaleType` is reused
// from the data models.

import 'dart:math' as math;

import '../../../data/models/item.dart' show SaleType;
import '../models/sales_forms.dart' show EditedField;

/// 'ZERO_RATE' | 'ZERO_QUANTITY' (strings kept for wire/UI fidelity).
enum LineErrorCode {
  zeroRate('ZERO_RATE'),
  zeroQuantity('ZERO_QUANTITY');

  const LineErrorCode(this.value);

  final String value;
}

/// 'error' | 'warning'.
enum LineErrorSeverity {
  error('error'),
  warning('warning');

  const LineErrorSeverity(this.value);

  final String value;
}

class CalcItemLineError {
  const CalcItemLineError({
    required this.code,
    required this.severity,
    required this.message,
  });

  final LineErrorCode code;
  final LineErrorSeverity severity;
  final String message;
}

class CalcItemLineInput {
  const CalcItemLineInput({
    this.saleType,
    this.quantity,
    this.amount,
    this.rate,
    this.qtyDecimalPrecision,
    this.roundingStep,
    this.lastEditedField,
  });

  final SaleType? saleType;
  final num? quantity;
  final num? amount;
  final num? rate;

  /// Decimal places allowed on quantity. Defaults to 0 (whole units).
  final num? qtyDecimalPrecision;

  /// Explicit step overriding the one derived from qtyDecimalPrecision.
  final num? roundingStep;

  final EditedField? lastEditedField;
}

/// Which field an edit targets (`applyLineFieldUpdate`). Broader than
/// `EditedField` because rate edits are possible too.
enum LineField {
  quantity,
  rate,
  amount,
}

/// `({quantity, amount, error?})` — structural type, equality-ready for tests.
typedef CalcItemLineResult = ({
  num quantity,
  num amount,
  CalcItemLineError? error,
});

/// Decimal places in a step value, e.g. 0.001 → 3, 0.5 → 1, 1 → 0.
int _stepDecimals(num step) {
  final s = step.toString();
  final dot = s.indexOf('.');
  return dot == -1 ? 0 : s.length - dot - 1;
}

/// Round to the nearest multiple of `step` (0.001, 0.5, 1, ...).
num roundToStep(num value, num step) {
  if (!(step > 0)) return value;
  final rounded = (value / step).round() * step;
  // Re-fix decimals: float division reintroduces noise (0.6670000000000001)
  return double.parse(rounded.toStringAsFixed(_stepDecimals(step) + 2));
}

num _round2(num value) {
  return double.parse(((value * 100).round() / 100).toStringAsFixed(2));
}

CalcItemLineResult calcItemLine(CalcItemLineInput input) {
  final quantity = input.quantity ?? 0;
  final amount = input.amount ?? 0;
  final rate = input.rate ?? 0;

  if ((input.saleType ?? SaleType.packed) == SaleType.packed) {
    return (quantity: quantity, amount: _round2(quantity * rate), error: null);
  }

  final step = (input.roundingStep != null && input.roundingStep! > 0)
      ? input.roundingStep!
      : math.pow(10, -(input.qtyDecimalPrecision ?? 0)).toDouble();

  if (input.lastEditedField == EditedField.amount) {
    if (rate <= 0) {
      return (
        quantity: quantity,
        amount: amount,
        error: CalcItemLineError(
          code: LineErrorCode.zeroRate,
          severity: LineErrorSeverity.error,
          message: 'Rate must be greater than 0',
        ),
      );
    }
    final derivedQty = roundToStep(amount / rate, step);
    if (amount > 0 && derivedQty == 0) {
      return (
        quantity: derivedQty,
        amount: amount,
        error: CalcItemLineError(
          code: LineErrorCode.zeroQuantity,
          severity: LineErrorSeverity.warning,
          message: 'Amount results in zero quantity',
        ),
      );
    }
    return (quantity: derivedQty, amount: amount, error: null);
  }

  if (input.lastEditedField == EditedField.quantity) {
    return (
      quantity: quantity,
      amount: _round2(quantity * rate),
      error: null,
    );
  }

  // Fresh row — nothing driven yet
  return (quantity: quantity, amount: amount, error: null);
}

/// `({quantity, amount, rate, lastEditedField})` structural result.
typedef LineFieldPatch = ({
  num quantity,
  num amount,
  num rate,
  EditedField? lastEditedField,
});

/// Build the patch for a quantity/rate/amount edit on a line.
/// Editing Quantity or Amount makes it the driver; editing Rate keeps the
/// existing driver fixed and recomputes the other side.
/// Shared by both invoice grids so their behaviour cannot drift.
LineFieldPatch applyLineFieldUpdate(
  CalcItemLineInput item,
  LineField field,
  num value,
) {
  final EditedField? lastEditedField;
  if (field == LineField.rate) {
    lastEditedField = item.lastEditedField ?? EditedField.quantity;
  } else {
    lastEditedField =
        field == LineField.quantity ? EditedField.quantity : EditedField.amount;
  }

  final result = calcItemLine(
    CalcItemLineInput(
      saleType: item.saleType,
      quantity: field == LineField.quantity ? value : item.quantity,
      amount: field == LineField.amount ? value : item.amount,
      rate: field == LineField.rate ? value : item.rate,
      qtyDecimalPrecision: item.qtyDecimalPrecision,
      roundingStep: item.roundingStep,
      lastEditedField: lastEditedField,
    ),
  );

  return (
    quantity: result.quantity,
    amount: result.amount,
    rate: field == LineField.rate ? value : item.rate ?? 0,
    lastEditedField:
        item.saleType == SaleType.loose ? lastEditedField : null,
  );
}

/// Inline validation for a rendered line: re-runs the calculation to surface
/// the zero-rate error / zero-quantity warning without extra component state.
CalcItemLineError? lineIssue(CalcItemLineInput input) {
  if (input.saleType != SaleType.loose) return null;
  if (!(input.amount != null && input.amount! > 0)) return null;
  return calcItemLine(
    CalcItemLineInput(
      saleType: input.saleType,
      quantity: input.quantity,
      amount: input.amount,
      rate: input.rate,
      qtyDecimalPrecision: input.qtyDecimalPrecision,
      roundingStep: input.roundingStep,
      lastEditedField: EditedField.amount,
    ),
  ).error;
}
