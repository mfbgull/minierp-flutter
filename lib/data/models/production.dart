import 'json_helpers.dart';

/// Port of the production types (`ProductionRecord` /
/// `ProductionInput` in types/client-types.ts) against the server
/// `ProductionModel` shapes:
///
/// - `GET /productions` → bare `[Production]` (list rows)
/// - `GET /productions/:id` → bare `Production` (adds `inputs` + `outputs`)
/// - `POST /productions` → bare `Production` (201)
/// - `DELETE /productions/:id` → `{success, message}`
///
/// The list/detail payloads include the joined output-item, warehouse
/// and creator fields; the financials (`unit_cost`,
/// `total_material_cost`, `total_batch_cost`, `batch_no`) are filled
/// by the server from the actual FIFO consumption — the client never
/// computes them.

/// One raw-material line consumed by a production run
/// (`production_inputs` row joined with item + warehouse).
class ProductionInput {
  const ProductionInput({
    required this.id,
    required this.productionId,
    required this.itemId,
    required this.quantity,
    required this.warehouseId,
    this.itemCode = '',
    this.itemName = '',
    this.unitOfMeasure,
    this.warehouseCode,
    this.warehouseName,
  });

  factory ProductionInput.fromJson(Map<String, dynamic> json) =>
      ProductionInput(
        id: asInt(json['id']) ?? 0,
        productionId: asInt(json['production_id']) ?? 0,
        itemId: asInt(json['item_id']) ?? 0,
        quantity: asNum(json['quantity']) ?? 0,
        warehouseId: asInt(json['warehouse_id']) ?? 0,
        itemCode: asString(json['item_code']) ?? '',
        itemName: asString(json['item_name']) ?? '',
        unitOfMeasure: asString(json['unit_of_measure']),
        warehouseCode: asString(json['warehouse_code']),
        warehouseName: asString(json['warehouse_name']),
      );

  final int id;
  final int productionId;
  final int itemId;
  final num quantity;
  final int warehouseId;
  final String itemCode;
  final String itemName;
  final String? unitOfMeasure;
  final String? warehouseCode;
  final String? warehouseName;
}

/// One output line of a production run (`production_outputs` row joined
/// with item) — D6 joint products.
///
/// A legacy single-output production carries exactly one line; the
/// server backfilled those rows in the migration, so `outputs` is never
/// empty on the detail payload. The joint cost (materials + overhead)
/// is allocated server-side by relative sales value; `allocatedCost` /
/// `unitCost` are actuals, never client-computed.
class ProductionOutput {
  const ProductionOutput({
    required this.id,
    required this.productionId,
    required this.itemId,
    required this.quantity,
    this.unitCost = 0,
    this.allocatedCost = 0,
    this.itemCode = '',
    this.itemName = '',
    this.unitOfMeasure,
  });

  factory ProductionOutput.fromJson(Map<String, dynamic> json) =>
      ProductionOutput(
        id: asInt(json['id']) ?? 0,
        productionId: asInt(json['production_id']) ?? 0,
        itemId: asInt(json['item_id']) ?? 0,
        quantity: asNum(json['quantity']) ?? 0,
        unitCost: asNum(json['unit_cost']) ?? 0,
        allocatedCost: asNum(json['allocated_cost']) ?? 0,
        itemCode: asString(json['item_code']) ?? '',
        itemName: asString(json['item_name']) ?? '',
        unitOfMeasure: asString(json['unit_of_measure']),
      );

  final int id;
  final int productionId;
  final int itemId;
  final num quantity;

  /// This line's share of the joint cost (`allocated_cost / quantity`).
  final num unitCost;

  /// Share of the joint cost allocated by relative sales value.
  final num allocatedCost;
  final String itemCode;
  final String itemName;
  final String? unitOfMeasure;
}

/// One production run — the row of `GET /productions` / detail.
class Production {
  const Production({
    required this.id,
    required this.productionNo,
    required this.outputItemId,
    required this.outputQuantity,
    required this.warehouseId,
    required this.productionDate,
    this.rawMaterialsWarehouseId,
    this.bomId,
    this.remarks,
    this.overheadCost = 0,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.batchId,
    this.batchNo,
    this.unitCost,
    this.totalMaterialCost,
    this.totalBatchCost,
    this.outputItemCode,
    this.outputItemName,
    this.outputUom,
    this.finishedGoodsWarehouseCode,
    this.finishedGoodsWarehouseName,
    this.rawMaterialsWarehouseCode,
    this.rawMaterialsWarehouseName,
    this.createdByUsername,
    this.inputs = const [],
    this.outputs = const [],
  });

  factory Production.fromJson(Map<String, dynamic> json) => Production(
    id: asInt(json['id']) ?? 0,
    productionNo: asString(json['production_no']) ?? '',
    outputItemId: asInt(json['output_item_id']) ?? 0,
    outputQuantity: asNum(json['output_quantity']) ?? 0,
    warehouseId: asInt(json['warehouse_id']) ?? 0,
    productionDate: asString(json['production_date']) ?? '',
    rawMaterialsWarehouseId: asInt(json['raw_materials_warehouse_id']),
    bomId: asInt(json['bom_id']),
    remarks: asString(json['remarks']),
    overheadCost: asNum(json['overhead_cost']) ?? 0,
    createdBy: asInt(json['created_by']),
    createdAt: asString(json['created_at']),
    updatedAt: asString(json['updated_at']),
    batchId: asInt(json['batch_id']),
    batchNo: asString(json['batch_no']),
    unitCost: asNum(json['unit_cost']),
    totalMaterialCost: asNum(json['total_material_cost']),
    totalBatchCost: asNum(json['total_batch_cost']),
    outputItemCode: asString(json['output_item_code']),
    outputItemName: asString(json['output_item_name']),
    outputUom: asString(json['output_uom']),
    finishedGoodsWarehouseCode: asString(json['finished_goods_warehouse_code']),
    finishedGoodsWarehouseName: asString(json['finished_goods_warehouse_name']),
    rawMaterialsWarehouseCode: asString(json['raw_materials_warehouse_code']),
    rawMaterialsWarehouseName: asString(json['raw_materials_warehouse_name']),
    createdByUsername: asString(json['created_by_username']),
    inputs: json['inputs'] is List
        ? [
            for (final row in json['inputs'] as List)
              if (row is Map<String, dynamic>) ProductionInput.fromJson(row),
          ]
        : const [],
    outputs: json['outputs'] is List
        ? [
            for (final row in json['outputs'] as List)
              if (row is Map<String, dynamic>) ProductionOutput.fromJson(row),
          ]
        : const [],
  );

  final int id;
  final String productionNo;
  final int outputItemId;
  final num outputQuantity;

  /// Finished-goods warehouse id (`warehouse_id`).
  final int warehouseId;
  final String productionDate;
  final int? rawMaterialsWarehouseId;
  final int? bomId;
  final String? remarks;
  final num overheadCost;
  final int? createdBy;
  final String? createdAt;
  final String? updatedAt;
  final int? batchId;
  final String? batchNo;
  final num? unitCost;
  final num? totalMaterialCost;
  final num? totalBatchCost;
  final String? outputItemCode;
  final String? outputItemName;
  final String? outputUom;
  final String? finishedGoodsWarehouseCode;
  final String? finishedGoodsWarehouseName;
  final String? rawMaterialsWarehouseCode;
  final String? rawMaterialsWarehouseName;
  final String? createdByUsername;

  /// Detail payload only — raw material consumption lines.
  final List<ProductionInput> inputs;

  /// Detail payload only — the output split (D6). One line for a
  /// single-output production, one per joint product otherwise.
  final List<ProductionOutput> outputs;
}
