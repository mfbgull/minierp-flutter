// Per item+customer selling-price history (`GET /sales/item-customer-history`)
// consumed by the invoice rate cell's advisory hint.

/// Per item+customer selling-price history (server response shape).
class ItemPriceHistory {
  const ItemPriceHistory({
    required this.lastPrice,
    required this.lowestPrice,
    required this.highestPrice,
    required this.avgPrice,
    required this.transactionCount,
    this.customerName,
    this.invoiceDate,
  });

  factory ItemPriceHistory.fromJson(Map<String, dynamic> json) =>
      ItemPriceHistory(
        lastPrice: _num(json['last_price']),
        lowestPrice: _num(json['lowest_price']),
        highestPrice: _num(json['highest_price']),
        avgPrice: _num(json['avg_price']),
        transactionCount: _num(json['transaction_count']).toInt(),
        customerName: json['customer_name'] as String?,
        invoiceDate: json['invoice_date'] as String?,
      );

  final num lastPrice;
  final num lowestPrice;
  final num highestPrice;
  final num avgPrice;
  final int transactionCount;
  final String? customerName;
  final String? invoiceDate;

  bool get hasHistory => transactionCount > 0;

  static num _num(Object? value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }
}
