// Payment-history section for the PO / purchase detail dialogs — a
// labelled "Payment History" table (Payment No | Date | Method | Amount)
// fed by the per-document payments endpoints. Shared by both detail
// dialogs (AGENTS.md duplicated_logic == false). The parent watches its
// payments provider and passes the async value in, so the retry hook can
// invalidate the right provider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/formatters.dart';
import '../data/models/invoice.dart' show InvoicePaymentRecord;
import '../data/repositories/api_result.dart' show ApiError;
import '../l10n/app_localizations.dart';
import 'detail_error.dart';
import 'detail_labels.dart' show detailSectionLabel;
import 'package:minierp_app/core/theme/app_border_radius.dart';

class PaymentHistorySection extends ConsumerWidget {
  const PaymentHistorySection({
    super.key,
    required this.payments,
    required this.onRetry,
  });

  final AsyncValue<List<InvoicePaymentRecord>> payments;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        detailSectionLabel(context, l10n.salesPaymenthistory),
        const SizedBox(height: 6),
        switch (payments) {
          AsyncData(:final value) => value.isEmpty
              ? Text(
                  l10n.suppliersNopayments,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : _PaymentsTable(payments: value),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: onRetry,
          ),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        },
      ],
    );
  }
}

class _PaymentsTable extends StatelessWidget {
  const _PaymentsTable({required this.payments});

  final List<InvoicePaymentRecord> payments;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.3,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: AppBorderRadius.smRadius,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(l10n.suppliersPaymentno, style: style)),
                SizedBox(
                  width: 100,
                  child: Text(
                    l10n.commonDate,
                    style: style,
                    textAlign: TextAlign.end,
                  ),
                ),
                SizedBox(
                  width: 112,
                  child: Text(
                    l10n.suppliersMethod,
                    style: style,
                    textAlign: TextAlign.end,
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    l10n.suppliersAmount,
                    style: style,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
          for (final payment in payments) ...[
            const Divider(height: 1),
            _PaymentRow(payment: payment),
          ],
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final InvoicePaymentRecord payment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amountStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final paymentDate = payment.paymentDate ?? '';
    final referenceNo = payment.referenceNo ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.paymentNo ?? '', style: amountStyle),
                if (referenceNo.isNotEmpty) Text(referenceNo, style: muted),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              paymentDate.isEmpty ? '—' : Formatters.date(paymentDate),
              style: amountStyle,
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: 112,
            child: Text(
              payment.method,
              style: amountStyle,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              Formatters.currency(payment.amount),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
