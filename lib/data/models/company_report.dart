/// Company report result models — the `data` payload of
/// GET /reports/company/stock|sales|purchases. The server builds these
/// shapes in `server/src/models/CompanyReport.ts`.
library;

import 'json_helpers.dart';

/// Server pagination block shared by the stock and period reports.
class CompanyReportPagination {
  const CompanyReportPagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory CompanyReportPagination.fromJson(Map<String, dynamic>? json) =>
      CompanyReportPagination(
        page: asInt(json?['page']) ?? 1,
        limit: asInt(json?['limit']) ?? 50,
        total: asInt(json?['total']) ?? 0,
        totalPages: asInt(json?['totalPages']) ?? 0,
      );

  final int page;
  final int limit;
  final int total;
  final int totalPages;
}

/// Current stock and value for one product.
class CompanyStockRow {
  const CompanyStockRow({
    required this.itemId,
    required this.itemCode,
    required this.itemName,
    required this.unitOfMeasure,
    required this.quantity,
    required this.stockValue,
  });

  factory CompanyStockRow.fromJson(Map<String, dynamic> json) =>
      CompanyStockRow(
        itemId: asInt(json['item_id']) ?? 0,
        itemCode: asString(json['item_code']) ?? '',
        itemName: asString(json['item_name']) ?? '',
        unitOfMeasure: asString(json['unit_of_measure']) ?? '',
        quantity: asNum(json['quantity']) ?? 0,
        stockValue: asNum(json['stock_value']) ?? 0,
      );

  final int itemId;
  final String itemCode;
  final String itemName;
  final String unitOfMeasure;
  final num quantity;
  final num stockValue;
}

/// GET /reports/company/stock — current physical stock at batch cost.
class CompanyStockReport {
  const CompanyStockReport({
    required this.companyId,
    required this.asOf,
    required this.valuationBasis,
    required this.rows,
    required this.totalStockValue,
    required this.quantitiesByUom,
    required this.pagination,
  });

  factory CompanyStockReport.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};
    final uom =
        totals['quantities_by_uom'] as Map<String, dynamic>? ?? const {};
    return CompanyStockReport(
      companyId: asInt(json['company_id']) ?? 0,
      asOf: asString(json['as_of']) ?? '',
      valuationBasis: asString(json['valuation_basis']) ?? '',
      rows: [
        for (final row in json['rows'] as List? ?? const [])
          CompanyStockRow.fromJson(row as Map<String, dynamic>),
      ],
      totalStockValue: asNum(totals['stock_value']) ?? 0,
      quantitiesByUom: {
        for (final entry in uom.entries) entry.key: asNum(entry.value) ?? 0,
      },
      pagination: CompanyReportPagination.fromJson(
        json['pagination'] as Map<String, dynamic>?,
      ),
    );
  }

  final int companyId;

  /// ISO timestamp of the current-stock snapshot.
  final String asOf;
  final String valuationBasis;
  final List<CompanyStockRow> rows;
  final num totalStockValue;
  final Map<String, num> quantitiesByUom;
  final CompanyReportPagination pagination;
}

/// One source document line behind a period product row.
class CompanyReportTransaction {
  const CompanyReportTransaction({
    required this.itemId,
    required this.documentId,
    required this.documentNo,
    required this.documentType,
    required this.date,
    required this.quantity,
    required this.amount,
    required this.isReturn,
  });

  factory CompanyReportTransaction.fromJson(Map<String, dynamic> json) =>
      CompanyReportTransaction(
        itemId: asInt(json['item_id']) ?? 0,
        documentId: asInt(json['document_id']) ?? 0,
        documentNo: asString(json['document_no']) ?? '',
        documentType: asString(json['document_type']) ?? '',
        date: asString(json['date']) ?? '',
        quantity: asNum(json['quantity']) ?? 0,
        amount: asNum(json['amount']) ?? 0,
        isReturn: asBool(json['is_return']),
      );

  final int itemId;
  final int documentId;
  final String documentNo;
  final String documentType;
  final String date;
  final num quantity;
  final num amount;
  final bool isReturn;
}

/// Gross, returned, and net figures for one product in a period.
class CompanyPeriodRow {
  const CompanyPeriodRow({
    required this.itemId,
    required this.itemCode,
    required this.itemName,
    required this.unitOfMeasure,
    required this.grossQuantity,
    required this.returnQuantity,
    required this.netQuantity,
    required this.grossValue,
    required this.returnValue,
    required this.netValue,
    required this.transactions,
  });

  factory CompanyPeriodRow.fromJson(Map<String, dynamic> json) =>
      CompanyPeriodRow(
        itemId: asInt(json['item_id']) ?? 0,
        itemCode: asString(json['item_code']) ?? '',
        itemName: asString(json['item_name']) ?? '',
        unitOfMeasure: asString(json['unit_of_measure']) ?? '',
        grossQuantity: asNum(json['gross_quantity']) ?? 0,
        returnQuantity: asNum(json['return_quantity']) ?? 0,
        netQuantity: asNum(json['net_quantity']) ?? 0,
        grossValue: asNum(json['gross_value']) ?? 0,
        returnValue: asNum(json['return_value']) ?? 0,
        netValue: asNum(json['net_value']) ?? 0,
        transactions: [
          for (final line in json['transactions'] as List? ?? const [])
            CompanyReportTransaction.fromJson(line as Map<String, dynamic>),
        ],
      );

  final int itemId;
  final String itemCode;
  final String itemName;
  final String unitOfMeasure;
  final num grossQuantity;
  final num returnQuantity;
  final num netQuantity;
  final num grossValue;
  final num returnValue;
  final num netValue;
  final List<CompanyReportTransaction> transactions;
}

class CompanyUomTotals {
  const CompanyUomTotals({
    required this.gross,
    required this.returns,
    required this.net,
  });

  factory CompanyUomTotals.fromJson(Map<String, dynamic> json) =>
      CompanyUomTotals(
        gross: asNum(json['gross']) ?? 0,
        returns: asNum(json['returns']) ?? 0,
        net: asNum(json['net']) ?? 0,
      );

  final num gross;
  final num returns;
  final num net;
}

class CompanyPeriodTotals {
  const CompanyPeriodTotals({
    required this.grossValue,
    required this.returnValue,
    required this.netValue,
    required this.quantitiesByUom,
  });

  factory CompanyPeriodTotals.fromJson(Map<String, dynamic> json) {
    final uom = json['quantities_by_uom'] as Map<String, dynamic>? ?? const {};
    return CompanyPeriodTotals(
      grossValue: asNum(json['gross_value']) ?? 0,
      returnValue: asNum(json['return_value']) ?? 0,
      netValue: asNum(json['net_value']) ?? 0,
      quantitiesByUom: {
        for (final entry in uom.entries)
          entry.key: CompanyUomTotals.fromJson(
            entry.value as Map<String, dynamic>? ?? const {},
          ),
      },
    );
  }

  final num grossValue;
  final num returnValue;
  final num netValue;
  final Map<String, CompanyUomTotals> quantitiesByUom;
}

/// GET /reports/company/sales|purchases — per-product period totals with
/// display-only transaction detail. Values are tax-inclusive after
/// discounts; returns are separate and already reduce net values.
class CompanyPeriodReport {
  const CompanyPeriodReport({
    required this.companyId,
    required this.view,
    required this.startDate,
    required this.endDate,
    required this.amountBasis,
    required this.rows,
    required this.totals,
    required this.pagination,
  });

  factory CompanyPeriodReport.fromJson(Map<String, dynamic> json) =>
      CompanyPeriodReport(
        companyId: asInt(json['company_id']) ?? 0,
        view: asString(json['view']) ?? '',
        startDate: asString(json['startDate']) ?? '',
        endDate: asString(json['endDate']) ?? '',
        amountBasis: asString(json['amount_basis']) ?? '',
        rows: [
          for (final row in json['rows'] as List? ?? const [])
            CompanyPeriodRow.fromJson(row as Map<String, dynamic>),
        ],
        totals: CompanyPeriodTotals.fromJson(
          json['totals'] as Map<String, dynamic>? ?? const {},
        ),
        pagination: CompanyReportPagination.fromJson(
          json['pagination'] as Map<String, dynamic>?,
        ),
      );

  final int companyId;

  /// `'sales'` or `'purchases'`.
  final String view;
  final String startDate;
  final String endDate;
  final String amountBasis;
  final List<CompanyPeriodRow> rows;
  final CompanyPeriodTotals totals;
  final CompanyReportPagination pagination;
}
