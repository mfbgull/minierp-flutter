// Personal loan detail dialog — shows full loan info + repayment history.
// Purely record-keeping — no GL impact.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/print_service.dart' show PrintService;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/movable_dialog.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'personal_loan_models.dart';
import 'personal_loan_repository.dart' show personalLoanRepositoryProvider;
import 'personal_loan_repay_dialog.dart';

/// Opens the personal loan detail dialog. Returns true if data changed.
Future<bool?> showPersonalLoanDetailDialog(
  BuildContext context, {
  required int loanId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _PersonalLoanDetailDialog(loanId: loanId),
  );
}

class _PersonalLoanDetailDialog extends ConsumerStatefulWidget {
  const _PersonalLoanDetailDialog({required this.loanId});

  final int loanId;

  @override
  ConsumerState<_PersonalLoanDetailDialog> createState() =>
      _PersonalLoanDetailDialogState();
}

class _PersonalLoanDetailDialogState
    extends ConsumerState<_PersonalLoanDetailDialog> {
  PersonalLoanDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(personalLoanRepositoryProvider)
        .getLoanDetail(widget.loanId);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _detail = data;
          _loading = false;
        });
      case ApiFailure(:final error):
        setState(() {
          _error = error.message;
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return MovableDialog(
      dialogId: 'personal_loan_detail',
      maxWidth: 500,
      maxHeight: 700,
      showHandle: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.equityPersonalLoanDetail,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(_error!,
                    style: TextStyle(color: scheme.error)),
              ),
            )
          else
            _buildDetail(l10n),
        ],
      ),
    );
  }

  Widget _buildDetail(AppLocalizations l10n) {
    final detail = _detail!;
    final loan = detail.loan;
    final scheme = Theme.of(context).colorScheme;

    final (statusLabel, statusColor) = switch (loan.status) {
      'pending' => (l10n.equityPersonalLoanStatusPending, scheme.primary),
      'partial' => (l10n.equityPersonalLoanStatusPartial, scheme.tertiary),
      'settled' => (l10n.equityPersonalLoanStatusSettled, scheme.outline),
      'written_off' => (
          l10n.equityPersonalLoanStatusWrittenOff,
          scheme.error
        ),
      _ => (loan.status, scheme.outline),
    };

    final canRepay = loan.status == 'pending' || loan.status == 'partial';

    return Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Loan info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          loan.loanNo,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            statusLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _infoRow(
                        l10n.equityPersonalLoanBorrower, loan.borrowerName),
                    if (loan.borrowerType != null)
                      _infoRow('Type', loan.borrowerType == 'customer'
                          ? l10n.equityPersonalLoanBorrowerTypeCustomer
                          : l10n.equityPersonalLoanBorrowerTypeSupplier),
                    _infoRow(
                      l10n.equityPersonalLoanAmount,
                      '${Formatters.currency(loan.amount)} ${loan.currency}',
                    ),
                    _infoRow(
                      l10n.equityPersonalLoanBalance,
                      '${Formatters.currency(loan.balance)} ${loan.currency}',
                    ),
                    _infoRow(
                      l10n.equityPersonalLoanDateGiven,
                      Formatters.date(loan.loanDate),
                    ),
                    if (loan.dueDate != null)
                      _infoRow(
                        l10n.equityPersonalLoanDueDate,
                        Formatters.date(loan.dueDate!),
                      ),
                    if (loan.purpose != null && loan.purpose!.isNotEmpty)
                      _infoRow(l10n.equityPersonalLoanPurpose, loan.purpose!),
                    if (loan.notes != null && loan.notes!.isNotEmpty)
                      _infoRow(l10n.equityPersonalLoanNotes, loan.notes!),
                    const SizedBox(height: 8),
                    // Progress bar
                    ClipRRect(
                      borderRadius: AppBorderRadius.xsRadius,
                      child: LinearProgressIndicator(
                        value: loan.progress,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(
                          loan.status == 'written_off'
                              ? scheme.error
                              : loan.status == 'settled'
                                  ? scheme.outline
                                  : scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Formatters.currency(loan.repaidAmount)} / ${Formatters.currency(loan.amount)} repaid',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Repayments section
            Row(
              children: [
                Text(
                  '${l10n.equityPersonalLoanRepaymentHistory} (${detail.repayments.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                if (canRepay)
                  TextButton.icon(
                    onPressed: () => _addRepayment(context),
                    icon: const Icon(Icons.add, size: 14),
                    label: Text(l10n.equityPersonalLoanAddRepayment),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (detail.repayments.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    l10n.equityPersonalLoanNoRepayments,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              for (final rep in detail.repayments)
                _RepaymentRow(
                  repayment: rep,
                  onPrint: () => _printRepaymentReceipt(rep),
                  onDelete: canRepay ? () => _deleteRepayment(context, rep) : null,
                ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addRepayment(BuildContext context) async {
    final result = await showPersonalLoanRepayDialog(
      context,
      loanId: widget.loanId,
      loan: _detail!.loan,
    );
    if (result == true && mounted) {
      _loadDetail();
    }
  }

  Future<void> _printRepaymentReceipt(PersonalLoanRepayment repayment) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final service = PrintService(context);
      await service.printPersonalLoanRepaymentReceipt(
        _detail!.loan,
        repayment,
        allRepayments: _detail?.repayments,
      );
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          '${l10n.errorsFailed}: $error',
          isError: true,
        );
      }
    }
  }

  Future<void> _deleteRepayment(
      BuildContext context, PersonalLoanRepayment rep) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(
          '${l10n.equityPersonalLoanRepaymentDeleteConfirm} ${Formatters.currency(rep.amount)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(personalLoanRepositoryProvider)
        .deleteRepayment(widget.loanId, rep.id);
    if (!context.mounted) return;

    switch (result) {
      case ApiSuccess():
        _loadDetail();
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }
}

class _RepaymentRow extends StatelessWidget {
  const _RepaymentRow({
    required this.repayment,
    this.onPrint,
    this.onDelete,
  });

  final PersonalLoanRepayment repayment;
  final VoidCallback? onPrint;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.payments_outlined,
                size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Formatters.date(repayment.paymentDate),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (repayment.notes != null && repayment.notes!.isNotEmpty)
                    Text(
                      repayment.notes!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              Formatters.currency(repayment.amount),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (onPrint != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onPrint,
                child: Icon(Icons.print_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
              ),
            ],
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.delete_outline,
                    size: 16, color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
