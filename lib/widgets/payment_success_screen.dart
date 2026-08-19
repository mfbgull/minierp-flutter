// Payment success screen — the green-check dialog shown right after a
// payment is recorded, with a Print Receipt (A4) action and Close.
// Shared by the supplier payment modal and the purchase / purchase-order
// forms (AGENTS.md duplicated_logic == false). [paymentId] is the saved
// payment's id — the receipt is fetched fresh from the server so it
// always shows the committed record (method, reference, allocation).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/print_utils.dart' show printPdfBytes;
import '../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../l10n/app_localizations.dart';
import 'app_toast.dart';
import 'payment_receipt_pdf.dart' show buildPaymentReceiptPdf;

class PaymentSuccessScreen extends ConsumerWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.paymentId,
    this.entityName,
  });

  final String title;
  final String subtitle;
  final int paymentId;

  /// Supplier/customer name for the receipt header — passed when the
  /// payment record itself doesn't carry the name yet.
  final String? entityName;

  Future<void> _printReceipt(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await ref
          .read(invoiceRepositoryProvider)
          .payment(paymentId);
      final payment = switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure() => null,
      };
      if (payment == null) return;
      final bytes = await buildPaymentReceiptPdf(
        payment,
        entityName: entityName,
      );
      if (!context.mounted) return;
      await printPdfBytes(bytes, 'receipt-$paymentId.pdf', context);
    } catch (error) {
      if (context.mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, size: 36, color: scheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _printReceipt(context, ref),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: Text(l10n.suppliersPrintreceipta4),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
