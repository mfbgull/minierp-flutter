// Unified print service — PORTING.md §12. Provides a single entry point
// for all print actions across the app, routing to A4 or thermal PDF
// builders based on the user's format choice. Replaces the scattered
// `printPdfBytes` calls with a structured service that handles:
//   - Format selection (A4 vs Thermal) with a picker dialog
//   - PDF generation (delegates to the appropriate builder)
//   - Native print dialog (via the `printing` package)
//   - Fallback to share/save-as-PDF when no print backend is available
//
// Usage:
//   final service = PrintService(context);
//   await service.printInvoice(invoice, payments: payments);

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../data/models/invoice.dart' show CompanyInfo, Invoice, InvoicePaymentRecord;
import '../../data/models/payment.dart' show Payment;
import '../../features/customers/thermal_payment_receipt_pdf.dart'
    show buildThermalPaymentReceiptPdf, PaymentAllocation;
import '../../features/owner_equity/personal_loan_models.dart'
    show PersonalLoan, PersonalLoanRepayment;
import '../../widgets/payment_receipt_pdf.dart'
    show buildPaymentReceiptPdf;
import '../../features/quotations/quotation_pdf.dart' show buildA4QuotationPdf;
import '../../features/sales/invoice_pdf.dart' show buildA4InvoicePdf;
import '../../features/sales/thermal_invoice_pdf.dart' show buildThermalInvoicePdf;
import '../../features/sales_orders/sales_order_pdf.dart' show buildA4SalesOrderPdf;
import '../../features/purchase_orders/purchase_order_pdf.dart' show buildA4PurchaseOrderPdf;
import '../../features/owner_equity/thermal_repayment_receipt_pdf.dart'
    show buildThermalRepaymentReceiptPdf;

/// Print format options.
enum PrintFormat {
  a4('A4'),
  thermal('Thermal (80mm)');

  const PrintFormat(this.label);
  final String label;
}

/// Unified print service for all document types.
class PrintService {
  PrintService(this.context);

  final BuildContext context;

  /// Shows a format-picker dialog and returns the user's choice.
  /// Returns null if the user cancels.
  Future<PrintFormat?> pickFormat() async {
    return showDialog<PrintFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Print Format'),
        children: PrintFormat.values
            .map(
              (f) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(f),
                child: Row(
                  children: [
                    Icon(
                      f == PrintFormat.a4
                          ? Icons.description_outlined
                          : Icons.receipt_long_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(f.label),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  /// Shows a format-picker dialog that includes a "View PDF" option
  /// for A4 documents. Returns (format, viewPdf) tuple.
  Future<(PrintFormat, bool)?> pickFormatAndView() async {
    final result = await showDialog<_FormatChoice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Print Options'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(
              _FormatChoice(PrintFormat.a4, viewPdf: true),
            ),
            child: const Row(
              children: [
                Icon(Icons.preview_outlined, size: 20),
                SizedBox(width: 12),
                Text('View A4 PDF'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(
              _FormatChoice(PrintFormat.a4, viewPdf: false),
            ),
            child: const Row(
              children: [
                Icon(Icons.description_outlined, size: 20),
                SizedBox(width: 12),
                Text('Print A4'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(
              _FormatChoice(PrintFormat.thermal, viewPdf: false),
            ),
            child: const Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 20),
                SizedBox(width: 12),
                Text('Print Thermal (80mm)'),
              ],
            ),
          ),
        ],
      ),
    );
    if (result == null) return null;
    return (result.format, result.viewPdf);
  }

  /// Prints an invoice in the given [format].
  Future<void> printInvoice(
    Invoice invoice, {
    List<InvoicePaymentRecord> payments = const [],
    CompanyInfo? company,
    PrintFormat format = PrintFormat.a4,
  }) async {
    final bytes = switch (format) {
      PrintFormat.a4 => await buildA4InvoicePdf(
          invoice: invoice,
          payments: payments,
          company: company,
        ),
      PrintFormat.thermal => await buildThermalInvoicePdf(
          invoice: invoice,
          company: company,
        ),
    };
    final suffix = format == PrintFormat.thermal ? '-thermal' : '';
    await _printBytes(bytes, '${invoice.invoiceNo}$suffix.pdf');
  }

  /// Prints a payment receipt in the given [format].
  Future<void> printPaymentReceipt(
    Payment payment, {
    CompanyInfo? company,
    String? entityName,
    num previousBalance = 0,
    List<PaymentAllocation>? allocations,
    PrintFormat format = PrintFormat.a4,
  }) async {
    final bytes = switch (format) {
      PrintFormat.a4 => await buildPaymentReceiptPdf(
          payment,
          company: company,
          entityName: entityName,
        ),
      PrintFormat.thermal => await buildThermalPaymentReceiptPdf(
          payment,
          company: company,
          entityName: entityName,
          previousBalance: previousBalance,
          allocations: allocations,
        ),
    };
    final suffix = format == PrintFormat.thermal ? '-thermal' : '';
    final name = payment.paymentNo.isEmpty ? 'receipt' : payment.paymentNo;
    await _printBytes(bytes, '$name$suffix.pdf');
  }

  /// Prints a quotation (A4 only for now).
  Future<void> printQuotation(dynamic quotation) async {
    final bytes = await buildA4QuotationPdf(quotation: quotation);
    final no = quotation.quotationNo ?? 'quotation';
    await _printBytes(bytes, '$no.pdf');
  }

  /// Prints a sales order (A4 only for now).
  Future<void> printSalesOrder(dynamic salesOrder) async {
    final bytes = await buildA4SalesOrderPdf(salesOrder: salesOrder);
    final no = salesOrder.soNo ?? 'sales-order';
    await _printBytes(bytes, '$no.pdf');
  }

  /// Prints a purchase order (A4 only for now).
  Future<void> printPurchaseOrder(dynamic purchaseOrder) async {
    final bytes = await buildA4PurchaseOrderPdf(purchaseOrder: purchaseOrder);
    final no = purchaseOrder.poNo ?? 'purchase-order';
    await _printBytes(bytes, '$no.pdf');
  }

  /// Prints a personal-loan repayment receipt (thermal).
  Future<void> printPersonalLoanRepaymentReceipt(
    PersonalLoan loan,
    PersonalLoanRepayment repayment, {
    CompanyInfo? company,
    List<PersonalLoanRepayment>? allRepayments,
  }) async {
    final bytes = await buildThermalRepaymentReceiptPdf(
      loan,
      repayment,
      company: company,
      allRepayments: allRepayments,
    );
    await _printBytes(bytes, '${loan.loanNo}-receipt.pdf');
  }

  /// Core print logic — shows the native print dialog, falling back to
  /// share/save-as-PDF when the platform has no print backend.
  Future<void> _printBytes(Uint8List bytes, String filename) async {
    try {
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (_) {
      if (!context.mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: filename);
    }
  }
}

/// Internal helper for the format-picker dialog.
class _FormatChoice {
  _FormatChoice(this.format, {this.viewPdf = false});
  final PrintFormat format;
  final bool viewPdf;
}
