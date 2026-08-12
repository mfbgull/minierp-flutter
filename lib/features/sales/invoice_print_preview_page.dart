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

  /// Native print dialog for the previewed bytes; share/save-as-PDF
  /// fallback is handled by [printPdfBytes]. Failures toast (no silent
  /// failures, PORTING.md §9).
  Future<void> _print(Uint8List bytes) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _printing = true);
    try {
      await printPdfBytes(bytes, '${widget.invoice.invoiceNo}.pdf', context);
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
      body = PdfPreview(
        build: _previewBuild,
        pdfFileName: '${widget.invoice.invoiceNo}.pdf',
        // The page owns its actions (Print in the app bar, Cancel via
        // back); the built-in bar would duplicate them.
        useActions: false,
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
              onPressed: !ready || _printing ? null : () => _print(_bytes!),
              icon: _printing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined, size: 18),
              label: Text(l10n.salesPrinta4),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}
