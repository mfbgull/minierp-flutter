// Read-only detail sheet for a unified-payment row whose source is NOT a
// native `payment` record (expense, salary, owner capital, owner
// withdrawal). Payment rows open the editable [showPaymentDetailDialog]
// instead. This sheet shows the transaction itself (not its party); salary
// rows additionally offer a "View Employee" shortcut into the employee
// detail. Read-only is an explicit business rule for these sources — they
// are edited in their own modules.

import 'package:flutter/material.dart';

import '../../core/theme/status_colors.dart';
import '../../core/utils/formatters.dart';
import '../../features/employees/employee_detail_dialog.dart'
    show showEmployeeDetailDialog;
import '../../l10n/app_localizations.dart';
import 'unified_payment_labels.dart';
import '../../data/models/unified_payment.dart' show UnifiedPayment;

/// Opens a read-only transaction-detail bottom sheet for a unified row.
Future<void> showUnifiedPaymentDetailSheet(
  BuildContext context, {
  required UnifiedPayment payment,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _UnifiedPaymentDetailSheet(payment: payment),
  );
}

class _UnifiedPaymentDetailSheet extends StatelessWidget {
  const _UnifiedPaymentDetailSheet({required this.payment});

  final UnifiedPayment payment;

  String _title(AppLocalizations l10n) => switch (payment.source) {
    'expense' => l10n.paymentsExpenseDetail,
    'salary' => l10n.paymentsSalaryPaymentDetail,
    'owner_capital' => l10n.paymentsOwnerCapitalDetail,
    'owner_withdrawal' => l10n.paymentsOwnerWithdrawalDetail,
    _ => l10n.paymentsTransactionDetail,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final statusColors = StatusColors.of(context);
    final directionColor = payment.direction == 'in'
        ? statusColors.success
        : payment.direction == 'out'
            ? statusColors.error
            : statusColors.warning;
    final signedAmount = payment.direction == 'out'
        ? '-${Formatters.currency(payment.amount)}'
        : payment.direction == 'in'
            ? '+${Formatters.currency(payment.amount)}'
            : Formatters.currency(payment.amount);

    return AlertDialog(
      title: Text(_title(l10n)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(context, l10n.paymentsPaymentno, payment.refNo),
            _row(context, l10n.fieldsType, unifiedTypeLabel(l10n, payment.type)),
            _row(context, l10n.paymentsParty, payment.party),
            _row(context, l10n.fieldsDate, Formatters.date(payment.date)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.fieldsAmount,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  Text(
                    signedAmount,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: directionColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _row(context, l10n.expensesPaymentmethod,
                unifiedMethodLabel(l10n, payment.method)),
            _row(context, l10n.fieldsStatus, payment.status),
            if (payment.description != null && payment.description!.isNotEmpty)
              _row(context, l10n.fieldsNotes, payment.description!),
            if (payment.source == 'salary' &&
                payment.partyType == 'employee' &&
                payment.partyId != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showEmployeeDetailDialog(
                      context,
                      employeeId: payment.partyId!,
                    );
                  },
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: Text(l10n.paymentsViewEmployee),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
      backgroundColor: scheme.surface,
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
