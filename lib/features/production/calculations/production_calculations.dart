// Production & BOM calculations — PORTING.md §7: the client-side
// preview maths that the web app runs for instant UI feedback (the
// server re-validates and re-computes actuals from FIFO consumption).
//
// - [bomMaterialCost] — Σ (line quantity × standard cost) for a BOM's
//   material lines (the server's `total_material_cost` formula).
// - [scaleBomInputs] — a BOM defines quantities *per batch*; scaling
//   to a requested output size multiplies each line by the output /
//   batch ratio.
// - [productionCostPreview] — material cost + overhead + per-unit
//   figure for a production run (matches the web `CostPreview`).
// - [materialShortfalls] — which required lines exceed the stock
//   available per item (client-side feasibility check; the server is
//   authoritative and rejects with 500 on shortage).
// - [allocateJointCost] — D6: splits a production's joint cost across
//   its output lines by relative sales value (mirror of the server's
//   rule, so the form can preview the split).

import '../../../data/models/bom.dart' show BomItem;

/// One required material line of a production run (form preview).
class ProductionInputNeed {
  const ProductionInputNeed({
    required this.itemId,
    required this.quantity,
    this.unitCost = 0,
  });

  final int itemId;
  final num quantity;
  final num unitCost;

  num get lineCost => quantity * unitCost;
}

/// Production cost preview — the web app's `CostPreview` shape.
class ProductionCostPreview {
  const ProductionCostPreview({
    required this.materialCost,
    required this.overhead,
    required this.totalCost,
    required this.costPerUnit,
  });

  final num materialCost;
  final num overhead;
  final num totalCost;
  final num costPerUnit;
}

/// Sum of the BOM material lines: Σ (quantity × standard_cost).
/// Lines without a standard cost contribute 0 (the server treats a
/// missing `standard_cost` the same way).
num bomMaterialCost(List<BomItem> items) => items.fold<num>(
  0,
  (sum, item) => sum + item.quantity * (item.standardCost ?? 0),
);

/// Scales a BOM's per-batch material quantities to [outputQuantity]
/// units of the finished good. Docs: quantity ×
/// outputQuantity / bomQuantity.
///
/// Guards: [bomQuantity] <= 0 falls back to a 1:1 scale (a malformed
/// BOM must never crash the form), and non-positive [outputQuantity]
/// yields zero-sized needs (nothing is consumed for an empty run).
List<ProductionInputNeed> scaleBomInputs({
  required List<BomItem> items,
  required num bomQuantity,
  required num outputQuantity,
}) {
  if (outputQuantity <= 0) return const [];
  final ratio = bomQuantity > 0 ? outputQuantity / bomQuantity : 1;
  return [
    for (final item in items)
      ProductionInputNeed(
        itemId: item.itemId,
        quantity: item.quantity * ratio,
        unitCost: item.standardCost ?? 0,
      ),
  ];
}

/// Builds the run cost preview: material (sum of line costs), fixed
/// overhead, total, and total/output-quantity per-unit cost. A
/// non-positive output quantity leaves the per-unit cost at 0 (no
/// finished goods to spread the batch cost over).
ProductionCostPreview productionCostPreview({
  required List<ProductionInputNeed> inputs,
  required num overhead,
  required num outputQuantity,
}) {
  final material = inputs.fold<num>(0, (sum, line) => sum + line.lineCost);
  final total = material + overhead;
  return ProductionCostPreview(
    materialCost: material,
    overhead: overhead,
    totalCost: total,
    costPerUnit: outputQuantity > 0 ? total / outputQuantity : 0,
  );
}

/// One output line fed to [allocateJointCost] — quantity plus the
/// item's standard selling price (the D6 allocation weight basis).
class ProductionOutputLine {
  const ProductionOutputLine({
    required this.itemId,
    required this.quantity,
    this.salesPrice = 0,
  });

  final int itemId;
  final num quantity;
  final num salesPrice;

  /// The D6 weight: quantity × selling price, or 0 when the item is
  /// unpriced (mirrors the server — an unpriced line carries no sales
  /// value).
  num get salesValue =>
      salesPrice > 0 && quantity > 0 ? salesPrice * quantity : 0;
}

/// One line's share of a production's joint cost.
class ProductionOutputAllocation {
  const ProductionOutputAllocation({
    required this.itemId,
    required this.quantity,
    required this.weight,
    required this.allocatedCost,
  });

  final int itemId;
  final num quantity;
  final num weight;
  final num allocatedCost;

  /// Allocated cost per unit of this output.
  num get unitCost => quantity > 0 ? allocatedCost / quantity : 0;
}

/// D6 joint-cost allocation — a mirror of the server's rule in
/// `Production.recordProduction`, used to preview the split in the form:
///
/// - each line's weight is its **relative sales value** (quantity ×
///   standard selling price);
/// - when *no* output is priced the split falls back to quantity rather
///   than dividing by zero;
/// - every line but the last is rounded to cents and the **last line
///   absorbs the rounding remainder**, so the shares always sum to
///   exactly [totalCost] (the same guarantee the GL posting relies on).
///
/// The server recomputes this inside its transaction; the preview is
/// advisory only.
List<ProductionOutputAllocation> allocateJointCost({
  required List<ProductionOutputLine> outputs,
  required num totalCost,
}) {
  if (outputs.isEmpty) return const [];

  final salesValues = [for (final o in outputs) o.salesValue];
  final totalSalesValue = salesValues.fold<num>(0, (s, v) => s + v);
  final weights = totalSalesValue > 0
      ? salesValues
      : [for (final o in outputs) o.quantity];
  final totalWeight = weights.fold<num>(0, (s, v) => s + v);
  final divisor = totalWeight > 0 ? totalWeight : 1;

  num allocatedSoFar = 0;
  final allocations = <ProductionOutputAllocation>[];
  for (var i = 0; i < outputs.length; i++) {
    final num share;
    if (i == outputs.length - 1) {
      // Last line absorbs the rounding remainder.
      share = _roundCurrency(totalCost - allocatedSoFar);
      allocatedSoFar = totalCost;
    } else {
      share = _roundCurrency(totalCost * (weights[i] / divisor));
      allocatedSoFar = _roundCurrency(allocatedSoFar + share);
    }
    allocations.add(
      ProductionOutputAllocation(
        itemId: outputs[i].itemId,
        quantity: outputs[i].quantity,
        weight: weights[i],
        allocatedCost: share,
      ),
    );
  }
  return allocations;
}

/// Cents — the same 2-decimal rounding as the server's `roundCurrency`.
num _roundCurrency(num value) => (value * 100).roundToDouble() / 100;

/// One material whose required quantity exceeds available stock.
class MaterialShortfall {
  const MaterialShortfall({
    required this.itemId,
    required this.itemName,
    required this.available,
    required this.required,
  });

  final int itemId;
  final String itemName;
  final num available;
  final num required;

  /// Short by this many units (0 when exactly at the limit).
  num get shortBy => required - available;
}

/// Client-side feasibility check: [available] maps item id → current
/// stock; returns the needs that exceed it. The server is the
/// authority on availability (it locks + re-reads inside its
/// transaction); this exists so the form can flag shortage before
/// submit and enrich the cost preview UX.
List<MaterialShortfall> materialShortfalls({
  required List<ProductionInputNeed> needs,
  required Map<int, num> available,
  String Function(int itemId)? nameOf,
}) {
  final shortfalls = <MaterialShortfall>[];
  for (final need in needs) {
    final stock = available[need.itemId] ?? 0;
    if (stock < need.quantity) {
      shortfalls.add(
        MaterialShortfall(
          itemId: need.itemId,
          itemName: nameOf?.call(need.itemId) ?? need.itemId.toString(),
          available: stock,
          required: need.quantity,
        ),
      );
    }
  }
  return shortfalls;
}
