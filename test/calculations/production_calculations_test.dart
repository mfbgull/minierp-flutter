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

  // D6 — mirror of the server's `Production.recordProduction` allocation
  // (`server/src/models/Production.ts`): joint cost split by relative
  // sales value, quantity-split fallback, last line absorbs rounding.
  group('allocateJointCost', () {
    // The server's canonical D6 fixture: materials 1,000 + overhead 500
    // = 1,500; oil 10 × 100 = 1,000, cake 50 × 10 = 500 → 2:1.
    const oil = ProductionOutputLine(
      itemId: 1,
      quantity: 10,
      salesPrice: 100,
    );
    const cake = ProductionOutputLine(
      itemId: 2,
      quantity: 50,
      salesPrice: 10,
    );

    test('splits by relative sales value (2:1 → 1,000 / 500)', () {
      final allocations = allocateJointCost(
        outputs: [oil, cake],
        totalCost: 1500,
      );
      expect(allocations, hasLength(2));
      expect(allocations[0].itemId, 1);
      expect(allocations[0].allocatedCost, 1000);
      expect(allocations[1].itemId, 2);
      expect(allocations[1].allocatedCost, 500);
    });

    test('unit cost derives from the allocated share', () {
      final allocations = allocateJointCost(
        outputs: [oil, cake],
        totalCost: 1500,
      );
      expect(allocations[0].unitCost, 100); // 1000 / 10
      expect(allocations[1].unitCost, 10); // 500 / 50
    });

    test('falls back to a quantity split when nothing is priced', () {
      final allocations = allocateJointCost(
        outputs: const [
          ProductionOutputLine(itemId: 1, quantity: 10),
          ProductionOutputLine(itemId: 2, quantity: 30),
        ],
        totalCost: 400,
      );
      expect(allocations[0].allocatedCost, 100); // 10/40
      expect(allocations[1].allocatedCost, 300); // 30/40
    });

    test('an unpriced line carries no sales value', () {
      final allocations = allocateJointCost(
        outputs: const [
          ProductionOutputLine(itemId: 1, quantity: 10, salesPrice: 100),
          ProductionOutputLine(itemId: 2, quantity: 50), // unpriced
        ],
        totalCost: 1000,
      );
      expect(allocations[0].allocatedCost, 1000);
      expect(allocations[1].allocatedCost, 0);
    });

    test('a zero-quantity line is not a pricing basis', () {
      // Mirrors the server guard: qty must be > 0 to count as sales value.
      final allocations = allocateJointCost(
        outputs: const [
          ProductionOutputLine(itemId: 1, quantity: 0, salesPrice: 100),
          ProductionOutputLine(itemId: 2, quantity: 4, salesPrice: 25),
        ],
        totalCost: 100,
      );
      expect(allocations[0].allocatedCost, 0);
      expect(allocations[1].allocatedCost, 100);
    });

    test('shares sum to exactly totalCost after rounding', () {
      // 1:1:1 of 100 → 33.33, 33.33, last absorbs 33.34.
      final allocations = allocateJointCost(
        outputs: const [
          ProductionOutputLine(itemId: 1, quantity: 1, salesPrice: 10),
          ProductionOutputLine(itemId: 2, quantity: 1, salesPrice: 10),
          ProductionOutputLine(itemId: 3, quantity: 1, salesPrice: 10),
        ],
        totalCost: 100,
      );
      expect(allocations[0].allocatedCost, 33.33);
      expect(allocations[1].allocatedCost, 33.33);
      expect(allocations[2].allocatedCost, 33.34);
      final sum = allocations.fold<num>(0, (s, a) => s + a.allocatedCost);
      expect(sum, 100);
    });

    test('single output takes the whole cost', () {
      final allocations = allocateJointCost(
        outputs: const [
          ProductionOutputLine(itemId: 1, quantity: 7, salesPrice: 3),
        ],
        totalCost: 123.45,
      );
      expect(allocations.single.allocatedCost, 123.45);
    });

    test('no outputs → no allocations', () {
      expect(
        allocateJointCost(outputs: const [], totalCost: 500),
        isEmpty,
      );
    });
  });
}
