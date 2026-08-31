// Loan detail dialog — shows full loan info + repayment history.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/movable_dialog.dart';
import 'loan_models.dart' show LoanDetail, LoanRepayment;
import 'loan_providers.dart';
import 'loan_repay_dialog.dart';

/// Opens the loan detail dialog. Returns true if data changed.
Future<bool?> showLoanDetailDialog(
  BuildContext context, {
  required int employeeId,
  required int loanId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _LoanDetailDialog(
      employeeId: employeeId,
      loanId: loanId,
    ),
  );
}

class _LoanDetailDialog extends ConsumerWidget {
  const _LoanDetailDialog({required this.employeeId, required this.loanId});

  final int employeeId;
  final int loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(
        loanDetailProvider((employeeId: employeeId, loanId: loanId)));

    return MovableDialog(
      dialogId: 'loan_detail',
      maxWidth: 500,
      maxHeight: 520,
      child: detail.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => DetailError(
          message: error is ApiError ? error.message : '$error',
          onRetry: () => ref.invalidate(
              loanDetailProvider((employeeId: employeeId, loanId: loanId))),
        ),
        data: (data) => _LoanDetailBody(
          detail: data,
          employeeId: employeeId,
          onChanged: () {
            ref.invalidate(
                loanDetailProvider((employeeId: employeeId, loanId: loanId)));
            Navigator.of(context).pop(true);
          },
        ),
      ),
    );
  }
}

class _LoanDetailBody extends StatelessWidget {
  const _LoanDetailBody({
    required this.detail,
    required this.employeeId,
    required this.onChanged,
  });

  final LoanDetail detail;
  final int employeeId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final isActive = detail.status == 'active' || detail.status == 'overdue';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.purpose ?? l10n.employeesLoanAmount,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Formatters.currency(detail.amount)} → ${Formatters.currency(detail.balance)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.commonClose,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Repayment list
        Expanded(
          child: detail.repayments.isEmpty
              ? Center(
                  child: Text(
                    l10n.employeesNosalaryhistory,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: detail.repayments.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _RepaymentRow(repayment: detail.repayments[index]),
                ),
        ),
        const Divider(height: 1),
        // Footer
        if (isActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${l10n.employeesLoanBalance}: ${Formatters.currency(detail.balance)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final result = await showLoanRepayDialog(
                      context,
                      employeeId: employeeId,
                      loanId: detail.id,
                    );
                    if (result == true) onChanged();
                  },
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: Text(l10n.employeesRepayLoan),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Single repayment row.
class _RepaymentRow extends StatelessWidget {
  const _RepaymentRow({required this.repayment});

  final LoanRepayment repayment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final isDirect = repayment.repaymentType == 'direct';
    final (typeLabel, typeColor) = isDirect
        ? (l10n.employeesLoanRepaymentTypeDirect, scheme.primary)
        : (l10n.employeesLoanRepaymentTypeSalary, scheme.tertiary);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        Formatters.currency(repayment.amount),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(Formatters.date(repayment.paymentDate)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          typeLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: typeColor,
          ),
        ),
      ),
    );
  }
}
