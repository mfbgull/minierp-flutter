import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/print_service.dart' show PrintService;
import '../../data/models/invoice.dart' show Invoice, InvoicePaymentRecord;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import 'calculations/invoice_rules.dart'
    show canReturnInvoice, canShowDeleteAction;
import 'invoice_payment_dialog.dart' show showInvoicePaymentDialog;
import 'invoice_providers.dart';
import 'invoice_return_dialog.dart' show showInvoiceReturnDialog;

/// The per-row ⋮ menu actions for an invoice row.
enum InvoiceRowAction { view, edit, payment, returnItem, print, delete }

/// Opens the row-actions menu anchored at [context] (the ⋮ cell),
/// mirroring the customers grid: a raw Listener receives the tap even
/// though PlutoGrid's gesture handler competes in the arena.
Future<void> openSalesRowMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Invoice? invoice,
}) async {
  if (invoice == null || !context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  final l10n = AppLocalizations.of(context)!;

  // Payment is offered while anything is still owed (Unpaid /
  // Partially Paid / Overdue / Sent / Draft with a balance); Return
  // follows the shared rule (hidden for Draft / Cancelled / fully
  // Returned); Delete follows the shared rule (Draft/Unpaid with no
  // money moved).
  final canPay = invoice.balanceAmount > 0 &&
      invoice.status != 'Cancelled' &&
      invoice.status != 'Returned';
  final canReturn = canReturnInvoice(invoice);
  final canDelete = canShowDeleteAction(invoice);

  final action = await showMenu<InvoiceRowAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      ),
      Offset.zero & overlay.context.size!,
    ),
    items: [
      PopupMenuItem(
        value: InvoiceRowAction.view,
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 18),
            const SizedBox(width: 8),
            Text(l10n.commonView),
          ],
        ),
      ),
      PopupMenuItem(
        value: InvoiceRowAction.edit,
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, size: 18),
            const SizedBox(width: 8),
            Text(l10n.commonEdit),
          ],
        ),
      ),
      if (canPay)
        PopupMenuItem(
          value: InvoiceRowAction.payment,
          child: Row(
            children: [
              const Icon(Icons.payments_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.paymentsRecordpayment),
            ],
          ),
        ),
      if (canReturn)
        PopupMenuItem(
          value: InvoiceRowAction.returnItem,
          child: Row(
            children: [
              const Icon(Icons.assignment_return_outlined, size: 18),
              const SizedBox(width: 8),
              // Flexible so the label shrinks instead of overflowing
              // the popup (same as the shared grid row-action menu).
              Flexible(child: Text(l10n.salesreturnsProcessreturn)),
            ],
          ),
        ),
      PopupMenuItem(
        value: InvoiceRowAction.print,
        child: Row(
          children: [
            const Icon(Icons.print_outlined, size: 18),
            const SizedBox(width: 8),
            Text(l10n.actionsPrint),
          ],
        ),
      ),
      if (canDelete)
        PopupMenuItem(
          value: InvoiceRowAction.delete,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.customersDeleteinvoice,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
    ],
  );
  if (action != null && context.mounted) {
    switch (action) {
      case InvoiceRowAction.view:
        // The read-only document view (same as the customer tab).
        context.push('/sales/print-preview', extra: invoice);
      case InvoiceRowAction.edit:
        context.push('/sales/form', extra: invoice);
      case InvoiceRowAction.payment:
        await showInvoicePaymentDialog(context, invoice: invoice);
      case InvoiceRowAction.returnItem:
        // The return dialog fetches the fresh invoice detail itself
        // (so returned_qty is current) — same entry the print-preview
        // page's Process Return button uses.
        await showInvoiceReturnDialog(context, invoiceId: invoice.id);
      case InvoiceRowAction.print:
        await printSalesInvoice(context, ref, invoice);
      case InvoiceRowAction.delete:
        await deleteSalesInvoice(context, ref, invoice);
    }
  }
}

/// Print invoice from the row menu — reuses the same PDF pipeline as the
/// print-preview page (fresh detail + payments → bytes → native
/// print), without leaving the list. Supports A4 and thermal formats.
Future<void> printSalesInvoice(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice,
) async {
  final l10n = AppLocalizations.of(context)!;
  final service = PrintService(context);
  final format = await service.pickFormat();
  if (format == null) return;
  try {
    final repo = ref.read(invoiceRepositoryProvider);
    final detailResult = await repo.invoice(invoice.id);
    final detail = switch (detailResult) {
      ApiSuccess(:final data) => data,
      ApiFailure(:final error) => throw error,
    };
    final paymentsResult = await repo.invoicePayments(invoice.id);
    final payments = switch (paymentsResult) {
      ApiSuccess(:final data) => data,
      ApiFailure() => const <InvoicePaymentRecord>[],
    };
    await service.printInvoice(detail, payments: payments, format: format);
  } catch (error) {
    if (context.mounted) {
      showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
    }
  }
}

/// Delete with confirm — mirrors the customer tab (guarded by
/// `canShowDeleteAction` above).
Future<void> deleteSalesInvoice(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice,
) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.customersDeleteinvoice,
    message: '${l10n.customersConfirmdeleteinvoice} "${invoice.invoiceNo}"?',
    confirmLabel: l10n.customersDeleteinvoice,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  final result = await ref.read(invoiceRepositoryProvider).delete(invoice.id);
  if (!context.mounted) return;
  switch (result) {
    case ApiSuccess():
      showAppToast(context, l10n.customersInvoicedeleted);
      ref.invalidate(invoicesProvider);
    case ApiFailure(:final error):
      showAppToast(context, error.message, isError: true);
  }
}
