// Loans tab — shows all loans for an employee with summary card,
// aging buckets, and per-loan actions (View, Repay, Write-off, Delete).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import 'employee_providers.dart';
import 'loan_models.dart' show EmployeeLoan, LoanSummary, LoansListResponse;
import 'loan_providers.dart';
import 'loan_repository.dart' show loanRepositoryProvider;
import 'loan_create_dialog.dart';
import 'loan_detail_dialog.dart';
import 'loan_repay_dialog.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Loans tab for the employee detail dialog.
class LoansTab extends ConsumerWidget {
  const LoansTab({super.key, required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final loans = ref.watch(employeeLoansProvider(employeeId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header with New Loan button ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.employeesLoans,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _createLoan(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.employeesNewLoan),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Body ──
        Expanded(
          child: loans.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => DetailError(
              message: error is ApiError ? error.message : '$error',
              onRetry: () => ref.invalidate(employeeLoansProvider(employeeId)),
            ),
            data: (data) => _LoansBody(data: data, employeeId: employeeId),
          ),
        ),
      ],
    );
  }

  Future<void> _createLoan(BuildContext context, WidgetRef ref) async {
    final result = await showLoanCreateDialog(
      context,
      employeeId: employeeId,
    );
    if (result == true && context.mounted) {
      ref.invalidate(employeeLoansProvider(employeeId));
      ref.invalidate(employeeDetailProvider(employeeId));
    }
  }
}

/// Loans body with summary card, aging buckets, and loan list.
class _LoansBody extends StatelessWidget {
  const _LoansBody({required this.data, required this.employeeId});

  final LoansListResponse data;
  final int employeeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (data.loans.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              l10n.employeesNoLoans,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Sort: overdue first, then by due date
    final sorted = [...data.loans]..sort((a, b) {
      if (a.status == 'overdue' && b.status != 'overdue') return -1;
      if (a.status != 'overdue' && b.status == 'overdue') return 1;
      if (a.dueDate != null && b.dueDate != null) {
        return a.dueDate!.compareTo(b.dueDate!);
      }
      return 0;
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Summary Card ──
          _LoanSummaryCard(summary: data.summary),
          const SizedBox(height: 12),
          // ── Aging Buckets ──
          _LoanAgingBuckets(loans: sorted),
          const SizedBox(height: 12),
          // ── Loan List ──
          for (final loan in sorted)
            _LoanRow(loan: loan, employeeId: employeeId),
        ],
      ),
    );
  }
}

/// Summary card showing totals.
class _LoanSummaryCard extends StatelessWidget {
  const _LoanSummaryCard({required this.summary});

  final LoanSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total outstanding
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Formatters.currency(summary.totalOutstanding),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    l10n.employeesLoanOutstanding,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Stats row
            Row(
              children: [
                _StatChip(
                  label: '${summary.activeLoans} ${l10n.dashboardActiveLoansCount}',
                  color: scheme.primary,
                ),
                if (summary.overdueLoans > 0) ...[
                  const SizedBox(width: 8),
                  _StatChip(
                    label: '${summary.overdueLoans} ${l10n.dashboardOverdueCount}',
                    color: scheme.error,
                  ),
                ],
                const Spacer(),
                Text(
                  '${l10n.employeesLoanTotalRepaid}: ${Formatters.currency(summary.totalRepaid)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small colored stat chip.
class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Aging buckets visualization (horizontal bars).
class _LoanAgingBuckets extends StatelessWidget {
  const _LoanAgingBuckets({required this.loans});

  final List<EmployeeLoan> loans;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // Compute buckets
    num current = 0, dueSoon = 0, dueToday = 0, overdue1_30 = 0, overdue30Plus = 0;
    for (final loan in loans) {
      if (loan.dueDate == null) {
        current += loan.balance;
        continue;
      }
      final due = DateTime.tryParse(loan.dueDate!);
      if (due == null) {
        current += loan.balance;
        continue;
      }
      final daysUntilDue = due.difference(DateTime.now()).inDays;
      if (daysUntilDue > 30) {
        current += loan.balance;
      } else if (daysUntilDue >= 1) {
        dueSoon += loan.balance;
      } else if (daysUntilDue == 0) {
        dueToday += loan.balance;
      } else if (daysUntilDue >= -30) {
        overdue1_30 += loan.balance;
      } else {
        overdue30Plus += loan.balance;
      }
    }

    final buckets = [
      (label: l10n.loanAgingCurrent, amount: current, color: const Color(0xFF22C55E)),
      (label: l10n.loanAgingDueSoon, amount: dueSoon, color: const Color(0xFFEAB308)),
      (label: l10n.loanAgingDueToday, amount: dueToday, color: const Color(0xFFF97316)),
      (label: l10n.loanAgingOverdue1_30, amount: overdue1_30, color: const Color(0xFFEF4444)),
      (label: l10n.loanAgingOverdue30Plus, amount: overdue30Plus, color: const Color(0xFFDC2626)),
    ];

    final visibleBuckets = buckets.where((b) => b.amount > 0).toList();
    if (visibleBuckets.isEmpty) return const SizedBox.shrink();

    final maxAmount = visibleBuckets.fold<num>(0, (m, b) => b.amount > m ? b.amount : m);
    final safeMax = maxAmount <= 0 ? 1.0 : maxAmount.toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final bucket in visibleBuckets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        bucket.label,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: AppBorderRadius.xsRadius,
                        child: LinearProgressIndicator(
                          value: (bucket.amount / safeMax).clamp(0, 1).toDouble(),
                          minHeight: 8,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(bucket.color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 80,
                      child: Text(
                        Formatters.currency(bucket.amount),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Single loan row with actions.
class _LoanRow extends ConsumerWidget {
  const _LoanRow({required this.loan, required this.employeeId});

  final EmployeeLoan loan;
  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final isOverdue = loan.status == 'overdue';
    final isCompleted = loan.status == 'completed';
    final (statusLabel, statusColor) = switch (loan.status) {
      'active' => (l10n.employeesLoanStatusActive, scheme.primary),
      'overdue' => (l10n.employeesLoanStatusOverdue, scheme.error),
      'completed' => (l10n.employeesLoanStatusCompleted, scheme.outline),
      'written_off' => (l10n.employeesLoanStatusWrittenOff, scheme.tertiary),
      _ => (loan.status, scheme.outline),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: AppBorderRadius.smRadius,
        onTap: () => _viewDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Purpose + Status badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      loan.purpose ?? l10n.employeesLoanAmount,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Row 2: Amount / Balance + Progress bar
              Row(
                children: [
                  Text(
                    '${Formatters.currency(loan.amount)} → ${Formatters.currency(loan.balance)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (loan.monthlyInstallment > 0)
                    Text(
                      '${l10n.employeesLoanMonthlyInstallment}: ${Formatters.currency(loan.monthlyInstallment)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              // Row 3: Progress bar
              ClipRRect(
                borderRadius: AppBorderRadius.xsRadius,
                child: LinearProgressIndicator(
                  value: loan.progress,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    isOverdue ? scheme.error : isCompleted ? scheme.outline : scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Row 4: Due date + Actions
              Row(
                children: [
                  if (loan.dueDate != null)
                    Text(
                      '${l10n.employeesLoanDueDate}: ${Formatters.date(loan.dueDate!)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isOverdue ? scheme.error : scheme.onSurfaceVariant,
                        fontWeight: isOverdue ? FontWeight.w600 : null,
                      ),
                    ),
                  const Spacer(),
                  // Actions
                  if (!isCompleted && loan.status != 'written_off')
                    TextButton.icon(
                      onPressed: () => _repay(context, ref),
                      icon: const Icon(Icons.payments_outlined, size: 14),
                      label: Text(l10n.employeesRepayLoan),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (!isCompleted && loan.status != 'written_off')
                    TextButton.icon(
                      onPressed: () => _writeOff(context, ref),
                      icon: const Icon(Icons.cancel_outlined, size: 14),
                      label: Text(l10n.employeesLoanStatusWrittenOff),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: scheme.error,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _viewDetail(BuildContext context, WidgetRef ref) async {
    final result = await showLoanDetailDialog(
      context,
      employeeId: employeeId,
      loanId: loan.id,
    );
    if (result == true && context.mounted) {
      ref.invalidate(employeeLoansProvider(employeeId));
      ref.invalidate(employeeDetailProvider(employeeId));
    }
  }

  Future<void> _repay(BuildContext context, WidgetRef ref) async {
    final result = await showLoanRepayDialog(
      context,
      employeeId: employeeId,
      loan: loan,
    );
    if (result == true && context.mounted) {
      ref.invalidate(employeeLoansProvider(employeeId));
      ref.invalidate(employeeDetailProvider(employeeId));
    }
  }

  Future<void> _writeOff(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.employeesLoanStatusWrittenOff,
      message: '${l10n.employeesLoanStatusWrittenOff} ${Formatters.currency(loan.balance)}?',
      confirmLabel: l10n.employeesLoanStatusWrittenOff,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final result = await ref.read(loanRepositoryProvider).writeOffLoan(
      employeeId,
      loan.id,
      {'reason': 'Written off from employee detail'},
    );
    if (!context.mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(employeeLoansProvider(employeeId));
        ref.invalidate(employeeDetailProvider(employeeId));
        showAppToast(context, l10n.employeesLoanWrittenOff);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }
}
