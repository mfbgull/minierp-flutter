// Payments tab — web `PaymentsTab` parity (customer-module-spec.md §6.7):
// the customer's payments grid (Payment No | Date | Amount | Method |
// Reference | Notes) with a per-row ⋮ menu — Print Receipt (A4), Edit
// (reuses the shared edit-payment dialog; amount stays read-only), Delete
// (confirm + invalidate every customer query).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../data/models/payment.dart' show Payment;
import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../payments/edit_payment_dialog.dart' show showPaymentEditDialog;
import '../payments/payments_providers.dart' show paymentsProvider;
import 'customer_providers.dart';
import '../../widgets/detail_tab_grid.dart';
import '../../widgets/payment_receipt_pdf.dart' show buildPaymentReceiptPdf;

enum _PaymentRowAction { print, edit, delete }

class CustomerPaymentsTab extends ConsumerStatefulWidget {
  const CustomerPaymentsTab({super.key, required this.customerId});

  final int customerId;

  @override
  ConsumerState<CustomerPaymentsTab> createState() =>
      _CustomerPaymentsTabState();
}

class _CustomerPaymentsTabState extends ConsumerState<CustomerPaymentsTab> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final payments = ref.watch(customerPaymentsProvider(widget.customerId));

    return switch (payments) {
      AsyncData(:final value) => value.isEmpty
          ? _empty(context, l10n.customersNopayments)
          : DetailTabGrid<Payment>(
              data: value,
              buildColumns: (l10n) => _columns(context, l10n),
              gridRowFor: _gridRowFor,
              hiddenFields: const ['data'],
            ),
      AsyncError(:final error) => DetailError(
        message: error is ApiError ? error.message : '$error',
        onRetry: () =>
            ref.invalidate(customerPaymentsProvider(widget.customerId)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _empty(BuildContext context, String message) => Center(
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  List<PlutoColumn> _columns(BuildContext context, AppLocalizations l10n) {
    PlutoColumn textCol(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          width: width,
          readOnly: true,
          enableContextMenu: false,
        );

    return [
      // Hidden cell carrying the row's Payment for the actions menu.
      PlutoColumn(
        title: '',
        field: 'data',
        type: PlutoColumnType.text(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textCol('paymentNo', l10n.customersPaymentno, 130),
      textCol('date', l10n.commonDate, 110),
      PlutoColumn(
        title: l10n.customersAmount,
        field: 'amount',
        type: PlutoColumnType.text(),
        width: 120,
        readOnly: true,
        enableContextMenu: false,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text('${ctx.cell.value}'),
        ),
      ),
      textCol('method', l10n.customersMethod, 130),
      textCol('reference', l10n.customersReference, 140),
      textCol('notes', l10n.customersNotes, 180),
      // ⋮ actions menu (Listener + showMenu — see customers_screen).
      PlutoColumn(
        title: l10n.customersActions,
        field: 'actions',
        type: PlutoColumnType.text(),
        width: 64,
        readOnly: true,
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
        renderer: (ctx) {
          final payment = ctx.cell.row.cells['data']?.value as Payment?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _openRowMenu(cellContext, payment),
              child: Center(
                child: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: Theme.of(cellContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  PlutoRow _gridRowFor(Payment payment) => PlutoRow(
    cells: {
      'data': PlutoCell(value: payment),
      'paymentNo': PlutoCell(value: payment.paymentNo),
      'date': PlutoCell(
        value: payment.paymentDate.isEmpty
            ? ''
            : Formatters.date(payment.paymentDate),
      ),
      'amount': PlutoCell(value: Formatters.currency(payment.amount)),
      'method': PlutoCell(value: payment.paymentMethod),
      'reference': PlutoCell(value: payment.referenceNo ?? ''),
      'notes': PlutoCell(value: payment.notes ?? ''),
      'actions': PlutoCell(value: ''),
    },
  );

  Future<void> _openRowMenu(
    BuildContext cellContext,
    Payment? payment,
  ) async {
    if (payment == null || !mounted) return;
    final l10n = AppLocalizations.of(cellContext)!;
    final box = cellContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(cellContext, rootOverlay: true);

    final action = await showMenu<_PaymentRowAction>(
      context: cellContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        ),
        Offset.zero & overlay.context.size!,
      ),
      items: [
        PopupMenuItem(
          value: _PaymentRowAction.print,
          child: Row(
            children: [
              const Icon(Icons.print_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.customersPrintreceipt),
            ],
          ),
        ),
        PopupMenuItem(
          value: _PaymentRowAction.edit,
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.commonEdit),
            ],
          ),
        ),
        PopupMenuItem(
          value: _PaymentRowAction.delete,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(cellContext).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.customersDeletepayment,
                style: TextStyle(
                  color: Theme.of(cellContext).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (action != null && mounted) {
      switch (action) {
        case _PaymentRowAction.print:
          _printReceipt(payment);
        case _PaymentRowAction.edit:
          _editPayment(payment);
        case _PaymentRowAction.delete:
          _deletePayment(payment);
      }
    }
  }

  Future<void> _printReceipt(Payment payment) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final bytes = await buildPaymentReceiptPdf(payment);
      if (!mounted) return;
      await printPdfBytes(
        bytes,
        '${payment.paymentNo.isEmpty ? 'receipt' : payment.paymentNo}.pdf',
        context,
      );
    } catch (error) {
      if (mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    }
  }

  void _editPayment(Payment payment) {
    showPaymentEditDialog(
      context,
      payment: payment,
      onSaved: () {
        if (!mounted) return;
        invalidateCustomerQueries(ref, widget.customerId);
      },
    );
  }

  Future<void> _deletePayment(Payment payment) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.customersDeletepayment,
      message:
          '${l10n.customersConfirmdeletepayment} "${payment.paymentNo}"?',
      confirmLabel: l10n.customersDeletepayment,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await ref
        .read(invoiceRepositoryProvider)
        .deletePayment(payment.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.customersPaymentdeleted);
        ref.invalidate(paymentsProvider);
        invalidateCustomerQueries(ref, widget.customerId);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }
}
