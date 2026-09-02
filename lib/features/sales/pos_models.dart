// POS models — the server `POST /api/pos/sale` contract (types/client-types.ts
// `POSItem` / `CartItem` / `POSPaymentMethod` / `POSTransaction`) plus the
// Flutter-side sale result. The controller computes line totals and change
// server-side; the client only sends `items` (item_id, quantity, unit_price)
// plus `warehouse_id`, `sale_date`, `cash_received`, `customer_name`.

/// A saleable item for the POS catalog — the server's `POSItem` shape,
/// filtered to active, non-raw-material sellables with a selling price.
class PosItem {
  const PosItem({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.unitOfMeasure,
    this.standardSellingPrice,
    required this.currentStock,
    this.category,
  });

  factory PosItem.fromJson(Map<String, dynamic> json) => PosItem(
        id: (json['id'] as num).toInt(),
        itemCode: (json['item_code'] as String?) ?? '',
        itemName: (json['item_name'] as String?) ?? '',
        unitOfMeasure: (json['unit_of_measure'] as String?) ?? 'Nos',
        standardSellingPrice: (json['standard_selling_price'] as num?),
        currentStock: (json['current_stock'] as num?)?.toInt() ?? 0,
        category: json['category'] as String?,
      );

  final int id;
  final String itemCode;
  final String itemName;
  final String unitOfMeasure;
  final num? standardSellingPrice;
  final int currentStock;
  final String? category;

  Map<String, dynamic> toJson() => {
        'id': id,
        'item_code': itemCode,
        'item_name': itemName,
        'unit_of_measure': unitOfMeasure,
        'standard_selling_price': standardSellingPrice,
        'current_stock': currentStock,
        if (category != null) 'category': category,
      };
}

/// One line in the POS shopping cart (client-side state).
class PosCartItem {
  const PosCartItem({
    required this.item,
    required this.quantity,
    required this.unitPrice,
  });

  factory PosCartItem.fromJson(Map<String, dynamic> json) => PosCartItem(
        item: PosItem.fromJson(json['item'] as Map<String, dynamic>),
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unit_price'] as num).toDouble(),
      );

  final PosItem item;
  final int quantity;
  final double unitPrice;

  num get lineTotal => quantity * unitPrice;
  int get availableStock => item.currentStock;

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}

/// A warehouse selectable on the POS screen.
class PosWarehouse {
  const PosWarehouse({
    required this.id,
    required this.warehouseCode,
    this.warehouseName,
  });

  factory PosWarehouse.fromJson(Map<String, dynamic> json) => PosWarehouse(
        id: (json['id'] as num).toInt(),
        warehouseCode: (json['warehouse_code'] as String?) ?? '',
        warehouseName: json['warehouse_name'] as String?,
      );

  final int id;
  final String warehouseCode;
  final String? warehouseName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'warehouse_code': warehouseCode,
        if (warehouseName != null) 'warehouse_name': warehouseName,
      };
}

/// One line of the completed sale as returned by `POST /api/pos/sale`.
class PosSaleLine {
  const PosSaleLine({
    required this.saleId,
    required this.saleNo,
    required this.itemCode,
    required this.itemName,
    required this.unitOfMeasure,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory PosSaleLine.fromJson(Map<String, dynamic> json) => PosSaleLine(
        saleId: (json['sale_id'] as num?)?.toInt() ?? 0,
        saleNo: (json['sale_no'] as String?) ?? '',
        itemCode: (json['item_code'] as String?) ?? '',
        itemName: (json['item_name'] as String?) ?? '',
        unitOfMeasure: (json['unit_of_measure'] as String?) ?? 'Nos',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
        lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0,
      );

  final int saleId;
  final String saleNo;
  final String itemCode;
  final String itemName;
  final String unitOfMeasure;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
}

/// The completed POS sale — the `data` envelope of `POST /api/pos/sale`.
class PosSale {
  const PosSale({
    required this.transactionNo,
    required this.saleDate,
    required this.warehouseId,
    required this.warehouseName,
    required this.customerName,
    required this.items,
    required this.subtotal,
    required this.total,
    required this.cashReceived,
    required this.change,
    required this.itemsCount,
    required this.saleIds,
  });

  factory PosSale.fromJson(Map<String, dynamic> json) => PosSale(
        transactionNo: (json['transaction_no'] as String?) ?? '',
        saleDate: (json['sale_date'] as String?) ?? '',
        warehouseId: (json['warehouse_id'] as num?)?.toInt() ?? 0,
        warehouseName: (json['warehouse_name'] as String?) ?? '',
        customerName: (json['customer_name'] as String?) ?? '',
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => PosSaleLine.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        cashReceived: (json['cash_received'] as num?)?.toDouble() ?? 0,
        change: (json['change'] as num?)?.toDouble() ?? 0,
        itemsCount: (json['items_count'] as num?)?.toInt() ?? 0,
        saleIds: (json['sale_ids'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
      );

  final String transactionNo;
  final String saleDate;
  final int warehouseId;
  final String warehouseName;
  final String customerName;
  final List<PosSaleLine> items;
  final double subtotal;
  final double total;
  final double cashReceived;
  final double change;
  final int itemsCount;
  final List<int> saleIds;
}

/// One row of `GET /api/pos/transactions` (recent POS sales history).
class PosTransaction {
  const PosTransaction({
    required this.transactionNo,
    required this.saleDate,
    required this.customerName,
    required this.warehouseName,
    required this.itemsCount,
    required this.total,
    required this.paidAmount,
    required this.balanceAmount,
  });

  factory PosTransaction.fromJson(Map<String, dynamic> json) => PosTransaction(
        transactionNo: (json['transaction_no'] as String?) ?? '',
        saleDate: (json['sale_date'] as String?) ?? '',
        customerName: (json['customer_name'] as String?) ?? '',
        warehouseName: (json['warehouse_name'] as String?) ?? '',
        itemsCount: (json['items_count'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
        balanceAmount: (json['balance_amount'] as num?)?.toDouble() ?? 0,
      );

  final String transactionNo;
  final String saleDate;
  final String customerName;
  final String warehouseName;
  final int itemsCount;
  final double total;
  final double paidAmount;
  final double balanceAmount;
}