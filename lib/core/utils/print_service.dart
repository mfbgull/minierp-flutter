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
import 'package:shared_preferences/shared_preferences.dart';

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
import '../../features/sales/pos_thermal_receipt_pdf.dart'
    show buildPosThermalReceiptPdf;

/// Print format options.
enum PrintFormat {
  a4('A4'),
  thermal('Thermal (80mm)');

  const PrintFormat(this.label);
  final String label;
}

/// Remembered-format persistence (SHORTCOMINGS-FIX 4.5).
///
/// The user's last print choice is stored locally (SharedPreferences) so
/// the format picker is not shown on every print. A storage failure
/// simply degrades to "no memory" — the picker shows as usual.
abstract class PrintFormatMemory {
  static const String _key = 'pref_print_format';

  /// The remembered format, or null when unset / unavailable.
  static Future<PrintFormat?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      for (final format in PrintFormat.values) {
        if (format.name == raw) return format;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(PrintFormat format) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, format.name);
    } catch (_) {
      // Storage unavailable — in-session behavior is unaffected.
    }
  }

  /// Cleared on logout so the next user starts unpinned.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}

/// Unified print service for all document types.
class PrintService {
  PrintService(this.context);

  final BuildContext context;

  /// Returns the user's print format. The first call (or after logout)
  /// shows the picker and remembers the choice; later calls reuse it
  /// directly so printing is one tap (SHORTCOMINGS-FIX 4.5). Returns
  /// null if the user cancels the picker.
  Future<PrintFormat?> pickFormat() async {
    final remembered = await PrintFormatMemory.read();
    if (remembered != null) return remembered;
    if (!context.mounted) return null;
    final chosen = await showDialog<PrintFormat>(
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
    if (chosen != null) await PrintFormatMemory.write(chosen);
    return chosen;
  }

  /// Shows a format-picker dialog that includes a "View PDF" option
  /// for A4 documents. Returns (format, viewPdf) tuple.
  ///
  /// A remembered format short-circuits the dialog (the "View A4 PDF"
  /// option is only offered when nothing is remembered — the preview is
  /// already rendered on screen at that point).
  Future<(PrintFormat, bool)?> pickFormatAndView() async {
    final remembered = await PrintFormatMemory.read();
    if (remembered != null) {
      return (remembered, false);
    }
    if (!context.mounted) return null;
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
    // Only actual print choices are remembered — viewing the PDF is a
    // deliberate preview and must not pin the format.
    if (!result.viewPdf) await PrintFormatMemory.write(result.format);
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

  /// Prints a POS thermal (80mm) receipt. POS receipts are roll-paper
  /// only — there is no A4 variant, so no format picker.
  Future<void> printPosReceipt(
    dynamic sale, {
    CompanyInfo? company,
  }) async {
    final bytes = await buildPosThermalReceiptPdf(sale);
    await _printBytes(bytes, '${sale.transactionNo}-pos.pdf');
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
