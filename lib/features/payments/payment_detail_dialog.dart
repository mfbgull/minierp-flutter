// Payment detail dialog — opened by double-tapping a row in the payments
// grid or via the F2/Enter keyboard shortcut. Fetches `GET /payments/:id`
// (enveloped object) via [paymentDetailProvider]; the grid row's hidden
// `id` cell supplies the payment id.
//
// Edit opens the small [PaymentEditDialog] (date/method/reference/notes —
// the amount is immutable, matching the web EditPaymentForm); Delete
// confirms then `DELETE /payments/:id` and refreshes the list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/status_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/payment.dart' show Payment;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'edit_payment_dialog.dart';
import 'payments_providers.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

/// Opens the read-only detail dialog for [paymentId].
Future<void> showPaymentDetailDialog(
  BuildContext context, {
  required int paymentId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _PaymentDetailDialog(paymentId: paymentId),
  );
}

class _PaymentDetailDialog extends ConsumerWidget {
  const _PaymentDetailDialog({required this.paymentId});

  final int paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(paymentDetailProvider(paymentId));
    return MovableDialog(
      dialogId: 'payment_detail',
      maxWidth: 520,
      maxHeight: 560,
      child: switch (detail) {
          AsyncData(:final value) => _DetailBody(
            payment: value,
            paymentId: paymentId,
          ),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(paymentDetailProvider(paymentId)),
          ),
          _ => const SizedBox(
            width: 420,
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.payment, required this.paymentId});

  final Payment payment;
  final int paymentId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.paymentsDeleteconfirm,
      message: '${l10n.paymentsPaymentno}: ${payment.paymentNo}',
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final result = await ref
        .read(invoiceRepositoryProvider)
        .deletePayment(paymentId);
    if (!context.mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(paymentsProvider);
        showAppToast(context, l10n.paymentsDeleted);
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    detailSectionLabel(context, l10n.paymentsPaymentdetails),
                    const SizedBox(height: 2),
                    Text(
                      payment.paymentNo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (payment.customerName != null ||
                        payment.supplierName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        payment.customerName ?? payment.supplierName!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Direction first — In (from customer) vs Out (to supplier).
              StatusBadge(
                status: payment.supplierId != null
                    ? l10n.paymentsTypeout
                    : l10n.paymentsTypein,
                color: payment.supplierId != null
                    ? StatusColors.of(context).error
                    : StatusColors.of(context).success,
              ),
              const SizedBox(width: 6),
              StatusBadge(status: payment.paymentMethod, color: Theme.of(context).colorScheme.tertiary),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailTiles(
                  tiles: [
                    DetailTile(
                      l10n.fieldsAmount,
                      Formatters.currency(payment.amount),
                      emphasize: true,
                    ),
                    DetailTile(
                      l10n.salesPaymentdate,
                      Formatters.date(payment.paymentDate),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DetailInfoRows(
                  rows: [
                    // The party name also heads the dialog — label which
                    // side of the transaction it is.
                    if (payment.supplierName != null)
                      (l10n.fieldsSupplier, payment.supplierName!)
                    else if (payment.customerName != null)
                      (l10n.fieldsCustomer, payment.customerName!),
                    (l10n.expensesPaymentmethod, payment.paymentMethod),
                    if (payment.invoiceNo != null)
                      (l10n.fieldsInvoice, payment.invoiceNo!),
                    if (payment.referenceNo?.isNotEmpty ?? false)
                      (l10n.fieldsReference, payment.referenceNo!),
                    if (payment.notes?.isNotEmpty ?? false)
                      (l10n.fieldsNotes, payment.notes!),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => showPaymentEditDialog(
                  context,
                  payment: payment,
                  onSaved: () {
                    ref.invalidate(paymentDetailProvider(paymentId));
                    ref.invalidate(paymentsProvider);
                  },
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l10n.salesEditpayment),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => _delete(context, ref),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l10n.commonDelete),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonClose),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
