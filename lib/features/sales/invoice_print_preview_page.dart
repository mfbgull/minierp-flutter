// Invoice print preview — full-page preview of the A4 invoice PDF
// (PORTING.md §12). Opened from the sales grid's row double-tap instead
// of the edit form, per the double-tap → preview requirement. Loads the
// fresh `GET /invoices/:id` detail + payment history (the same source the
// edit form's A4 print uses), renders the PDF with the `printing`
// package's `PdfPreview` widget, and offers explicit Print + Cancel
// actions (Cancel = the app-bar back arrow / system back).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';

import '../../core/utils/print_service.dart' show PrintFormat, PrintService;
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../data/models/invoice.dart'
    show Invoice, InvoicePaymentRecord;
import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/screen_error_panel.dart';
import 'invoice_pdf.dart' show buildA4InvoicePdf;
import 'invoice_return_dialog.dart' show showInvoiceReturnDialog;
import '../../core/utils/formatters.dart' show Formatters;
import 'return_receipt_pdf.dart' show buildReturnReceiptPdf;
import '../../data/models/sales_return.dart'
    show InvoicePosition, ReturnDocument;

/// Print-preview page for one invoice.
class InvoicePrintPreviewPage extends ConsumerStatefulWidget {
  const InvoicePrintPreviewPage({super.key, required this.invoice});

  /// The grid row's invoice — only `id` is used; the full detail is
  /// refetched so the preview always matches the saved document.
  final Invoice invoice;

  @override
  ConsumerState<InvoicePrintPreviewPage> createState() =>
      _InvoicePrintPreviewPageState();
}

class _InvoicePrintPreviewPageState
    extends ConsumerState<InvoicePrintPreviewPage> {
  Uint8List? _bytes;
  String? _error;

  /// The fresh `GET /invoices/:id` detail — passed to the edit form so
  /// it opens fully prefilled (falls back to the row when the detail
  /// fetch is still in flight / failed; the form refetches anyway).
  Invoice? _detail;
  bool _printing = false;

  /// Stable PdfPreview document callback. Created once: `PdfPreview`
  /// treats a changed `build` identity as a new document and re-rasterizes
  /// (and rebuilds spuriously change identity, that loops forever), so the
  /// closure must not be re-created per build.
  late final Future<Uint8List> Function(PdfPageFormat) _previewBuild;

  @override
  void initState() {
    super.initState();
    _previewBuild = (format) async => _bytes!;
    _load();
  }

  /// Fresh `GET /invoices/:id` detail + payments, rendered to A4 bytes —
  /// mirrors the edit form's `_printInvoice` so preview and print never
  /// diverge from what's saved. Returns the detail too so [Edit] can
  /// open the form fully prefilled.
  Future<(Uint8List, Invoice)> _buildPdf() async {
    final repo = ref.read(invoiceRepositoryProvider);
    final detailResult = await repo.invoice(widget.invoice.id);
    final invoice = switch (detailResult) {
      ApiSuccess(:final data) => data,
      ApiFailure(:final error) => throw error,
    };
    final paymentsResult = await repo.invoicePayments(widget.invoice.id);
    final payments = switch (paymentsResult) {
      ApiSuccess(:final data) => data,
      ApiFailure() => const <InvoicePaymentRecord>[],
    };
    final bytes = await buildA4InvoicePdf(invoice: invoice, payments: payments);
    return (bytes, invoice);
  }

  Future<void> _load() async {
    if (_bytes != null || _error != null) {
      setState(() {
        _bytes = null;
        _error = null;
      });
    }
    try {
      final (bytes, invoice) = await _buildPdf();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _detail = invoice;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is ApiError ? error.message : '$error');
    }
  }

  /// Opens the edit form for the previewed invoice (same route the grid
  /// used to push on double-tap). The form refetches the detail itself;
  /// passing [_detail] just pre-fills it.
  void _edit() {
    final invoice = _detail ?? widget.invoice;
    context.push('/sales/form', extra: invoice);
  }

  /// Shows a format-picker dialog for printing.
  Future<void> _showPrintFormatPicker() async {
    final service = PrintService(context);
    final result = await service.pickFormatAndView();
    if (result == null) return;

    final (format, viewPdf) = result;

    if (viewPdf) {
      // View A4 PDF only — no printing
      if (!mounted) return;
      await printPdfBytes(_bytes!, '${widget.invoice.invoiceNo}.pdf', context);
      return;
    }
    if (!mounted) return;

    await _printWithFormat(format);
  }

  /// Print with selected format.
  Future<void> _printWithFormat(PrintFormat format) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _printing = true);
    try {
      final service = PrintService(context);
      final repo = ref.read(invoiceRepositoryProvider);
      final paymentsResult = await repo.invoicePayments(widget.invoice.id);
      final payments = switch (paymentsResult) {
        ApiSuccess(:final data) => data,
        ApiFailure() => const <InvoicePaymentRecord>[],
      };
      await service.printInvoice(
        _detail ?? widget.invoice,
        payments: payments,
        format: format,
      );
    } catch (error) {
      if (mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Prints the standalone Return Receipt (spec §6.3 / D10) for one
  /// return of the previewed invoice.
  Future<void> _printReturnReceipt(ReturnDocument ret) async {
    final l10n = AppLocalizations.of(context)!;
    final detail = _detail;
    if (detail == null) return;
    setState(() => _printing = true);
    try {
      final bytes = await buildReturnReceiptPdf(
        returnDoc: ret,
        invoice: detail,
        company: detail.company,
      );
      if (!mounted) return;
      await printPdfBytes(bytes, '${ret.returnNo}.pdf', context);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ready = _bytes != null;

    final Widget body;
    if (_error != null) {
      body = ScreenErrorPanel(message: _error!, onRetry: _load);
    } else if (!ready) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final expiryNotes = _detail?.expiryNotes?.trim();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expiryNotes != null && expiryNotes.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _detail!.items
                            ?.any((i) => i.isExpiredAtSale) ==
                        true
                    ? Colors.red.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _detail!.items
                              ?.any((i) => i.isExpiredAtSale) ==
                          true
                      ? Colors.red.shade200
                      : Colors.orange.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_detail!.overrideSale)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.amber.shade700),
                          const SizedBox(width: 6),
                          Text(
                            'Override Sale',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: Colors.amber.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(expiryNotes),
                ],
              ),
            ),
          if (_detail?.position != null)
            _PositionPanel(
              position: _detail!.position!,
              returns: _detail?.returns ?? const <ReturnDocument>[],
              onPrintReceipt: _printReturnReceipt,
              printing: _printing,
            ),
          Expanded(
            child: PdfPreview(
              build: _previewBuild,
              pdfFileName: '${widget.invoice.invoiceNo}.pdf',
              // The page owns its actions (Print in the app bar, Cancel
              // via back); the built-in bar would duplicate them.
              useActions: false,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        // Title = the document being previewed (the Print A4 action
        // below already labels the action).
        title: Text(widget.invoice.invoiceNo),
        actions: [
          // Edit stays one tap away (the web client's view→edit flow):
          // the double-tap now lands here for preview/print instead of
          // the edit form.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l10n.commonEdit),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: !ready || _printing
                  ? null
                  : () => _showPrintFormatPicker(),
              icon: _printing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined, size: 18),
              label: Text(l10n.actionsPrint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _detail == null
                  ? null
                  : () async {
                      await showInvoiceReturnDialog(
                        context,
                        invoiceId: _detail!.id,
                      );
                      if (!mounted) return;
                      _load();
                    },
              icon: const Icon(Icons.assignment_return_outlined, size: 18),
              label: Text(l10n.salesreturnsProcessreturn),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}

/// Position block (spec §6.2) for the invoice preview: the seven
/// position rows plus the per-return history (RET no, date, fee, and
/// settlement detail). Shown above the PDF preview when the invoice has
/// any return activity.
class _PositionPanel extends StatelessWidget {
  const _PositionPanel({
    required this.position,
    required this.returns,
    this.onPrintReceipt,
    this.printing = false,
  });

  final InvoicePosition position;
  final List<ReturnDocument> returns;
  final Future<void> Function(ReturnDocument)? onPrintReceipt;
  final bool printing;

  Widget _row(
    AppLocalizations l10n,
    String label,
    num value, {
    bool bold = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          Formatters.currency(value),
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.salesreturnsReturns,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(l10n.salesreturnsReturnno),
            ],
          ),
          const Divider(height: 10),
          _row(l10n, l10n.salesreturnsPositionOriginalTotal, position.originalTotal),
          _row(l10n, l10n.salesreturnsPositionTotalReturned, position.totalReturned),
          _row(l10n, l10n.salesreturnsPositionCurrentValue, position.currentInvoiceValue),
          _row(l10n, l10n.salesreturnsPositionOriginalPayments, position.totalPaid),
          _row(l10n, l10n.salesreturnsFee, position.totalFees),
          const Divider(height: 10),
          _row(l10n, l10n.salesreturnsPositionBalanceDue, position.balanceDue, bold: true),
          _row(l10n, l10n.salesreturnsPositionRefundDue, position.refundCreditDue),
          if (position.totalSettled > 0.005)
            _row(l10n, l10n.salesreturnsPositionRefunded, position.totalSettled),
          if (position.remainingRefundDue > 0.005)
            _row(l10n, l10n.salesreturnsPositionRemaining, position.remainingRefundDue),
          for (final ret in returns) ...[
            const Divider(height: 12),
            _ReturnRow(
              ret: ret,
              onPrintReceipt: onPrintReceipt,
              printing: printing,
            ),
          ],
        ],
      ),
    );
  }
}

/// One entry in the per-return history (spec §6.2 returns tab).
class _ReturnRow extends StatelessWidget {
  const _ReturnRow({
    required this.ret,
    this.onPrintReceipt,
    this.printing = false,
  });

  final ReturnDocument ret;
  final Future<void> Function(ReturnDocument)? onPrintReceipt;
  final bool printing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = ret.items;
    final settlements = ret.settlements;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(ret.returnNo,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (onPrintReceipt != null) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: l10n.actionsPrint,
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: printing ? null : () => onPrintReceipt!(ret),
                      icon: const Icon(Icons.print_outlined),
                    ),
                  ],
                ],
              ),
              Text(ret.returnDate),
            ],
          ),
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${l10n.salesItems}: ${items.map((i) => '#${i.itemId}×${i.quantity}').join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.salesreturnsFee),
                Text(Formatters.currency(ret.feeAmount)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.salesreturnsPositionNet),
                Text(Formatters.currency(ret.netAmount)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${l10n.commonStatus}: ${ret.status}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (settlements.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${l10n.salesreturnsSettlement}: '
                '${settlements.map((s) => '${s.type} ${Formatters.currency(s.amount)}'
                    '${s.method != null ? ' (${s.method})' : ''}'
                    '${s.reference != null && s.reference!.isNotEmpty ? ' ${s.reference}' : ''}').join('; ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
