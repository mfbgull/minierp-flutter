import '../../data/models/purchase_order.dart';
import '../../data/models/quotation.dart';
import '../../data/models/sales_order.dart';
import '../../l10n/app_localizations.dart';
import 'csv_encoding.dart';
import 'formatters.dart';
import 'po_status.dart';
import 'quotation_status.dart';
import 'so_status.dart';

/// Builds the CSV text for the sales-orders grid (SO # | Date | Customer
/// | Status | Total | Delivery — mirroring the grid's columns; the
/// Status column uses the same localized label as the grid's badge).
String buildSalesOrdersCsv(AppLocalizations l10n, List<SalesOrder> orders) {
  return buildGridCsv(
    [
      l10n.salesordersSono,
      l10n.salesordersDate,
      l10n.salesordersCustomer,
      l10n.salesordersStatus,
      l10n.commonTotal,
      l10n.salesordersDelivery,
    ],
    orders,
    (o) => [
      sanitizeCsvCell(o.soNo.isEmpty ? '—' : o.soNo),
      o.soDate.isEmpty ? '—' : Formatters.date(o.soDate),
      sanitizeCsvCell(o.customerName.isEmpty ? '—' : o.customerName),
      sanitizeCsvCell(soStatusLabel(l10n, o.status)),
      Formatters.currency(o.totalAmount),
      (o.deliveryDate?.isEmpty ?? true)
          ? '—'
          : Formatters.date(o.deliveryDate!),
    ],
  );
}

/// Builds the CSV text for the purchase-orders grid (PO No | Date |
/// Supplier | Status | Total | Expected Delivery — mirroring the grid's
/// columns; the Status column uses the same localized label as the
/// grid's badge).
String buildPurchaseOrdersCsv(
  AppLocalizations l10n,
  List<PurchaseOrder> orders,
) {
  return buildGridCsv(
    [
      l10n.purchaseordersPono,
      l10n.commonDate,
      l10n.purchasesSuppliercol,
      l10n.commonStatus,
      l10n.commonTotal,
      l10n.purchaseordersExpecteddelivery,
    ],
    orders,
    (o) => [
      sanitizeCsvCell(o.poNo.isEmpty ? '—' : o.poNo),
      o.poDate.isEmpty ? '—' : Formatters.date(o.poDate),
      sanitizeCsvCell(o.supplierName.isEmpty ? '—' : o.supplierName),
      sanitizeCsvCell(poStatusLabel(l10n, o.status)),
      Formatters.currency(o.totalAmount),
      (o.expectedDeliveryDate?.isEmpty ?? true)
          ? '—'
          : Formatters.date(o.expectedDeliveryDate!),
    ],
  );
}

/// Builds the CSV text for the quotations grid (Quotation # | Date |
/// Customer | Status | Total | Expiry — mirroring the grid's columns;
/// the Status column uses the same localized label as the grid's badge).
String buildQuotationsCsv(AppLocalizations l10n, List<Quotation> quotations) {
  return buildGridCsv(
    [
      l10n.quotationsQuotation,
      l10n.quotationsDate,
      l10n.quotationsCustomer,
      l10n.quotationsStatus,
      l10n.commonTotal,
      l10n.quotationsExpiry,
    ],
    quotations,
    (q) => [
      sanitizeCsvCell(q.quotationNo.isEmpty ? '—' : q.quotationNo),
      q.quotationDate.isEmpty ? '—' : Formatters.date(q.quotationDate),
      sanitizeCsvCell(q.customerName.isEmpty ? '—' : q.customerName),
      sanitizeCsvCell(quotationStatusLabel(l10n, q.status)),
      Formatters.currency(q.totalAmount),
      (q.expiryDate?.isEmpty ?? true) ? '—' : Formatters.date(q.expiryDate!),
    ],
  );
}
