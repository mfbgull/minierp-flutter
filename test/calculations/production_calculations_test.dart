// 1:1 Dart port of the production/BOM maths in the server models
// (`server/src/models/Production.ts`, `server/src/models/BOM.ts` —
// PORTING.md §7): material cost from BOM lines, batch scaling, the
// run cost preview (FIFO actuals are server-side; the client previews
// with standard costs), and the stock feasibility check.

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/bom.dart' show BomItem;
import 'package:minierp_app/features/production/calculations/production_calculations.dart';

const _a = BomItem(id: 1, itemId: 1, quantity: 2, standardCost: 5);
const _b = BomItem(id: 2, itemId: 2, quantity: 3, standardCost: 10);
const _noCost = BomItem(id: 3, itemId: 3, quantity: 4);

void main() {
  group('bomMaterialCost', () {
    test('Σ quantity × standard_cost (server total_material_cost)', () {
      expect(bomMaterialCost([_a, _b]), 2 * 5 + 3 * 10);
    });

    test('missing standard cost contributes 0', () {
      expect(bomMaterialCost([_noCost]), 0);
      expect(bomMaterialCost(const []), 0);
    });
  });

  group('scaleBomInputs', () {
    test('scales per-batch quantities by output/batch ratio', () {
      final needs = scaleBomInputs(
        items: const [_a, _b],
        bomQuantity: 10,
        outputQuantity: 25,
      );
      expect(needs.length, 2);
      expect(needs[0].itemId, 1);
      expect(needs[0].quantity, 5); // 2 × 25/10
      expect(needs[0].unitCost, 5);
      expect(needs[1].quantity, 7.5); // 3 × 25/10
    });

    test('1:1 when batch and output quantities match', () {
      final needs = scaleBomInputs(
        items: const [_a],
        bomQuantity: 8,
        outputQuantity: 8,
      );
      expect(needs.single.quantity, 2);
    });

    test('malformed BOM (batch qty <= 0) falls back to 1:1 scale', () {
      final needs = scaleBomInputs(
        items: const [_a],
        bomQuantity: 0,
        outputQuantity: 7,
      );
      expect(needs.single.quantity, 2);
    });

    test('non-positive output quantity yields no needs', () {
      expect(
        scaleBomInputs(items: const [_a], bomQuantity: 10, outputQuantity: 0),
        isEmpty,
      );
    });
  });

  group('productionCostPreview', () {
    test('material + overhead, per-unit spread over output', () {
      final needs = scaleBomInputs(
        items: const [_a, _b],
        bomQuantity: 10,
        outputQuantity: 20,
      );
      // material: 2×5×2 + 3×10×2 = 20 + 60 = 80
      final preview = productionCostPreview(
        inputs: needs,
        overhead: 20,
        outputQuantity: 20,
      );
      expect(preview.materialCost, 80);
      expect(preview.overhead, 20);
      expect(preview.totalCost, 100);
      expect(preview.costPerUnit, 5);
    });

    test('per-unit stays 0 with no output (matches server guard)', () {
      final preview = productionCostPreview(
        inputs: const [],
        overhead: 30,
        outputQuantity: 0,
      );
      expect(preview.totalCost, 30);
      expect(preview.costPerUnit, 0);
    });
  });

  group('materialShortfalls', () {
    test('flags only needs above available stock', () {
      final needs = scaleBomInputs(
        items: const [_a, _b],
        bomQuantity: 10,
        outputQuantity: 20,
      );
      final shortfalls = materialShortfalls(
        needs: needs,
        available: const {1: 10, 2: 50},
        nameOf: (id) => 'item$id',
      );
      expect(shortfalls, isEmpty);
    });

    test('missing stock counts as 0 available', () {
      final needs = scaleBomInputs(
        items: const [_a],
        bomQuantity: 10,
        outputQuantity: 20,
      );
      final shortfalls = materialShortfalls(
        needs: needs,
        available: const {},
        nameOf: (id) => 'material-$id',
      );
      expect(shortfalls.single.itemId, 1);
      expect(shortfalls.single.available, 0);
      expect(shortfalls.single.required, 4);
      expect(shortfalls.single.shortBy, 4);
      expect(shortfalls.single.itemName, 'material-1');
    });

    test('exactly-at-limit is not a shortfall', () {
      final needs = [const ProductionInputNeed(itemId: 9, quantity: 5)];
      final shortfalls = materialShortfalls(
        needs: needs,
        available: const {9: 5},
      );
      expect(shortfalls, isEmpty);
    });

    test('id fallback name when no nameOf given', () {
      final shortfalls = materialShortfalls(
        needs: const [ProductionInputNeed(itemId: 42, quantity: 3)],
        available: const {},
      );
      expect(shortfalls.single.itemName, '42');
    });
  });
}
