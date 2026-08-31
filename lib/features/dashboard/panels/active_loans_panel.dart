// Active Loans panel — dashboard panel showing active loans across all
// employees with aging buckets and per-loan rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/repositories/api_result.dart' show ApiError;
import '../../../l10n/app_localizations.dart';
import '../../employees/employee_detail_dialog.dart' show showEmployeeDetailDialog;
import '../../employees/loan_models.dart' show ActiveLoanRow, ActiveLoansResult;
import '../../employees/loan_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Dashboard panel showing active loans across all employees.
/// Fetches GET /dashboard/active-loans.
class ActiveLoansPanel extends ConsumerWidget {
  const ActiveLoansPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final loans = ref.watch(dashboardActiveLoansProvider2);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dashboardcardPanelActiveloans,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loans.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _PanelError(
                  message: error is ApiError ? error.message : error.toString(),
                  onRetry: () => ref.invalidate(dashboardActiveLoansProvider2),
                ),
                data: (data) => _ActiveLoansBody(data: data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error widget with retry button.
class _PanelError extends StatelessWidget {
  const _PanelError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(AppLocalizations.of(context)!.commonRefresh),
          ),
        ],
      ),
    );
  }
}

/// Body widget with summary strip, aging buckets, and loan list.
class _ActiveLoansBody extends StatelessWidget {
  const _ActiveLoansBody({required this.data});

  final ActiveLoansResult data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (data.loans.isEmpty) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: scheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.employeesNoLoans,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    // Sort: overdue first, then by days until due
    final sorted = [...data.loans]..sort((a, b) {
      if (a.status == 'overdue' && b.status != 'overdue') return -1;
      if (a.status != 'overdue' && b.status == 'overdue') return 1;
      return a.daysUntilDue.compareTo(b.daysUntilDue);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryStrip(data: data),
        const SizedBox(height: 10),
        _LoanAgingBuckets(loans: sorted),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _LoanRow(loan: sorted[index]),
          ),
        ),
      ],
    );
  }
}

/// Summary strip showing total outstanding and counts.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.data});

  final ActiveLoansResult data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final activeCount = data.totalLoans - data.overdueCount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.currency(data.totalOutstanding),
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
            '$activeCount ${l10n.dashboardActiveLoansCount}'
            '${data.overdueCount > 0 ? ' · ${data.overdueCount} ${l10n.dashboardOverdueCount}' : ''}',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Aging buckets visualization (horizontal bars).
class _LoanAgingBuckets extends StatelessWidget {
  const _LoanAgingBuckets({required this.loans});

  final List<ActiveLoanRow> loans;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // Compute buckets from loan data
    num current = 0, dueSoon = 0, dueToday = 0, overdue1_30 = 0, overdue30Plus = 0;
    for (final loan in loans) {
      final d = loan.daysUntilDue;
      if (d > 30) {
        current += loan.balance;
      } else if (d >= 1) {
        dueSoon += loan.balance;
      } else if (d == 0) {
        dueToday += loan.balance;
      } else if (d >= -30) {
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

    return Column(
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
    );
  }
}

/// Single loan row with click behavior.
class _LoanRow extends StatelessWidget {
  const _LoanRow({required this.loan});

  final ActiveLoanRow loan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final isOverdue = loan.status == 'overdue';
    final (statusLabel, statusColor) = isOverdue
        ? (l10n.employeesLoanStatusOverdue, scheme.error)
        : (l10n.employeesLoanStatusActive, scheme.primary);

    final dueLabel = isOverdue
        ? '${-loan.daysUntilDue} ${l10n.dashboardOverdueCount}'
        : loan.daysUntilDue == 0
            ? l10n.employeesLoanDueDate
            : '${loan.daysUntilDue} ${l10n.dashboardActiveLoansCount}';

    return InkWell(
      borderRadius: AppBorderRadius.smRadius,
      onTap: () => _openEmployeeDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${loan.employeeCode} · ${loan.employeeName}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (loan.purpose != null) ...[
                        Text(
                          loan.purpose!,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: ClipRRect(
                          borderRadius: AppBorderRadius.xsRadius,
                          child: LinearProgressIndicator(
                            value: loan.progress,
                            minHeight: 4,
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              isOverdue ? scheme.error : scheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dueLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isOverdue ? scheme.error : scheme.onSurfaceVariant,
                      fontWeight: isOverdue ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Formatters.currency(loan.balance),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ],
        ),
      ),
    );
  }

  void _openEmployeeDetail(BuildContext context) {
    showEmployeeDetailDialog(
      context,
      employeeId: loan.employeeId,
      initialTab: 3,  // Loans tab
    );
  }
}
