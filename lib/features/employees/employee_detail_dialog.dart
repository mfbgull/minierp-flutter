// Employee detail dialog — fetched from `GET /employees/:id` with three
// tabs: Overview (contact / HR / bank info), Salary History
// (`GET /employees/:id/salary/history`) and Documents
// (`GET /employees/:id/documents`). The header offers Edit and Pay
// Salary; the tabs use the shared detail-row widgets.

import 'package:flutter/material.dart';
import 'package:minierp_app/core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/movable_dialog.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'employee_document_dialog.dart';
import 'employee_form_dialog.dart';
import 'employee_models.dart' show Employee, EmployeeDocument, SalaryMonthSummary, SalaryMonthDetail;
import 'employee_providers.dart';
import 'employee_repository.dart' show employeeRepositoryProvider;
import 'loans_tab.dart';
import 'salary_pay_dialog.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the detail dialog for one employee.
Future<void> showEmployeeDetailDialog(
  BuildContext context, {
  required int employeeId,
  int initialTab = 0,  // 0=Overview, 1=Salary, 2=Documents, 3=Loans
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => EmployeeDetailDialog(
      employeeId: employeeId,
      initialTab: initialTab,
    ),
  );
}

class EmployeeDetailDialog extends ConsumerStatefulWidget {
  const EmployeeDetailDialog({super.key, required this.employeeId, this.initialTab = 0});

  final int employeeId;
  final int initialTab;

  @override
  ConsumerState<EmployeeDetailDialog> createState() =>
      _EmployeeDetailDialogState();
}

class _EmployeeDetailDialogState extends ConsumerState<EmployeeDetailDialog> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final employee = ref.watch(employeeDetailProvider(widget.employeeId));

    return MovableDialog(
      dialogId: 'employee_detail',
      maxWidth: 640,
      maxHeight: 620,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: employee.when(
                data: (e) => _header(l10n, e),
                loading: () => Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l10n.commonLoading)),
                  ],
                ),
                error: (error, _) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        error is ApiError ? error.message : '$error',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(
                        employeeDetailProvider(widget.employeeId),
                      ),
                      child: Text(l10n.commonRefresh),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // Tab bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  _tabChip(l10n.commonDetails, 0),
                  const SizedBox(width: 4),
                  _tabChip(l10n.employeesSalaryhistory, 1),
                  const SizedBox(width: 4),
                  _tabChip(l10n.employeesDocumentsTitle, 2),
                  const SizedBox(width: 4),
                  _tabChip(l10n.employeesLoans, 3),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: employee.when(
                data: (e) => IndexedStack(
                  index: _tab,
                  children: [
                    _OverviewTab(employee: e),
                    _SalaryHistoryTab(employeeId: e.id),
                    _DocumentsTab(employeeId: e.id),
                    LoansTab(employeeId: e.id),
                  ],
                ),
                loading: () => const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => DetailError(
                  message: error is ApiError ? error.message : '$error',
                  onRetry: () => ref.invalidate(
                    employeeDetailProvider(widget.employeeId),
                  ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String label, int index) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      borderRadius: AppBorderRadius.smRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: AppBorderRadius.smRadius,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n, Employee employee) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${employee.employeeCode} · ${employee.fullName}',
                style: Theme.of(context).textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            StatusBadge(
              status: employee.isActive
                  ? l10n.statusActive
                  : l10n.statusInactive,
              color: StatusColors.of(context).active(employee.isActive),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            if (employee.designation != null) employee.designation!,
            if (employee.department != null) employee.department!,
          ].join(' · '),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                await showSalaryPayDialog(context, employee: employee);
                ref.invalidate(employeeDetailProvider(employee.id));
                ref.invalidate(employeeSalaryHistoryProvider(employee.id));
                ref.invalidate(employeesProvider);
              },
              icon: const Icon(Icons.payments_outlined, size: 16),
              label: Text(l10n.employeesPaysalary),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await showEmployeeFormDialog(context, employee: employee);
                ref.invalidate(employeeDetailProvider(employee.id));
                ref.invalidate(employeesProvider);
              },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(l10n.commonEdit),
            ),
            const Spacer(),
            IconButton(
              tooltip: l10n.commonClose,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

/// Contact / HR / bank details as a label:value grid.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final e = employee;
    String dash(String? v) => detailDash(v);

    final rows = <(String, String)>[
      (l10n.employeesFieldsEmail, dash(e.email)),
      (l10n.employeesFieldsPhone, dash(e.phone)),
      (l10n.employeesFieldsMobile, dash(e.mobile)),
      (l10n.employeesFieldsCnic_no, dash(e.cnicNo)),
      (l10n.employeesFieldsDate_of_birth, dash(e.dateOfBirth)),
      (l10n.employeesFieldsGender, dash(e.gender)),
      (l10n.employeesFieldsDepartment, dash(e.department)),
      (l10n.employeesFieldsDesignation, dash(e.designation)),
      (l10n.employeesEmploymenttype, dash(e.employmentType)),
      (l10n.employeesFieldsDate_of_joining, dash(e.dateOfJoining)),
      (l10n.employeesFieldsDate_of_leaving, dash(e.dateOfLeaving)),
      (l10n.employeesFieldsAddress, dash(e.address)),
      (l10n.employeesFieldsCity, dash(e.city)),
      (l10n.employeesFieldsState, dash(e.state)),
      (l10n.employeesFieldsPostal_code, dash(e.postalCode)),
      (l10n.employeesFieldsCountry, dash(e.country)),
      (l10n.employeesFieldsBank_name, dash(e.bankName)),
      (l10n.employeesFieldsBank_account_no, dash(e.bankAccountNo)),
      (l10n.employeesFieldsBank_iban, dash(e.bankIban)),
      (
        l10n.employeesFieldsEmergency_contact_name,
        dash(e.emergencyContactName),
      ),
      (
        l10n.employeesFieldsEmergency_contact_phone,
        dash(e.emergencyContactPhone),
      ),
      (l10n.employeesFieldsNotes, dash(e.notes)),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailTiles(
            tiles: [
              DetailTile(
                l10n.employeesFieldsSalary,
                Formatters.currency(e.salary),
                emphasize: true,
              ),
              DetailTile(l10n.employeesFieldsIs_active, e.isActive ? '✓' : '—'),
            ],
          ),
          DetailInfoRows(rows: rows),
        ],
      ),
    );
  }
}

/// Salary payment history — aggregated monthly rows.
class _SalaryHistoryTab extends ConsumerWidget {
  const _SalaryHistoryTab({required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final history = ref.watch(employeeSalaryHistoryProvider(employeeId));

    return history.when(
      data: (rows) {
        if (rows.isEmpty) {
          return Center(child: Text(l10n.employeesNosalaryhistory));
        }

        // Compute advance summary
        final advanceRows = rows.where((r) => r.advanceCarryover > 0).toList();
        final totalAdvance = advanceRows.fold<num>(0, (s, r) => s + r.advanceCarryover);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (totalAdvance > 0) _AdvanceSummary(
                totalAdvance: totalAdvance,
                advanceRows: advanceRows,
              ),
              for (final row in rows)
                _MonthRow(
                  summary: row,
                  employeeId: employeeId,
                ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => DetailError(
        message: error is ApiError ? error.message : '$error',
        onRetry: () => ref.invalidate(
          employeeSalaryHistoryProvider(employeeId),
        ),
      ),
    );
  }
}

/// Summary card showing total advance carryover across all months.
class _AdvanceSummary extends StatelessWidget {
  const _AdvanceSummary({
    required this.totalAdvance,
    required this.advanceRows,
  });

  final num totalAdvance;
  final List<SalaryMonthSummary> advanceRows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // Build source months list, e.g. "August 2026, October 2026"
    final sources = advanceRows
        .where((r) => r.displaySourceMonth != null)
        .map((r) => r.displaySourceMonth!)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.tertiary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 20,
            color: scheme.tertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.employeesTotaladvance}: ${Formatters.currency(totalAdvance)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${l10n.employeesAdvanceFrom}: ${sources.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single month row showing paid of salary + status.
class _MonthRow extends StatelessWidget {
  const _MonthRow({required this.summary, required this.employeeId});

  final SalaryMonthSummary summary;
  final int employeeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final (statusLabel, statusColor) = switch (summary.status) {
      'paid' => (l10n.employeesSalarystatusPaid, scheme.primary),
      'partial' => (l10n.employeesSalarystatusPartial, scheme.tertiary),
      'advance' => (l10n.employeesSalarystatusAdvance, scheme.secondary),
      _ => (summary.status, scheme.outline),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: AppBorderRadius.smRadius,
        onTap: () => _openMonthDetail(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Month + payment count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.displayMonth,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Formatters.currency(summary.totalPaid > summary.employeeSalary ? summary.employeeSalary : summary.totalPaid)} / ${Formatters.currency(summary.employeeSalary)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (summary.advanceCarryover > 0)
                      Text(
                        summary.displaySourceMonth != null
                          ? '${l10n.employeesAdvanceFrom} ${summary.displaySourceMonth}: ${Formatters.currency(summary.advanceCarryover)}'
                          : '${l10n.employeesAdvanceFromPrevious}: ${Formatters.currency(summary.advanceCarryover)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.tertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              const SizedBox(width: 8),
              // Payment count + arrow
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${summary.paymentCount}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMonthDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _SalaryMonthDetailDialog(
        employeeId: employeeId,
        summary: summary,
      ),
    );
  }
}

/// Drill-down dialog showing individual payments for a specific month.
class _SalaryMonthDetailDialog extends ConsumerStatefulWidget {
  const _SalaryMonthDetailDialog({
    required this.employeeId,
    required this.summary,
  });

  final int employeeId;
  final SalaryMonthSummary summary;

  @override
  ConsumerState<_SalaryMonthDetailDialog> createState() =>
      _SalaryMonthDetailDialogState();
}

class _SalaryMonthDetailDialogState
    extends ConsumerState<_SalaryMonthDetailDialog> {
  late Future<SalaryMonthDetail?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref
        .read(employeeRepositoryProvider)
        .salaryMonthDetail(widget.employeeId, widget.summary.payPeriod)
        .then((r) => switch (r) {
              ApiSuccess(:final data) => data,
              _ => null,
            });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return MovableDialog(
      dialogId: 'salary_month_detail',
      maxWidth: 500,
      maxHeight: 480,
      child: FutureBuilder<SalaryMonthDetail?>(
        future: _future,
          builder: (context, snapshot) {
            final detail = snapshot.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l10n.employeesMonthdetail} — ${widget.summary.displayMonth}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.commonClose,
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${l10n.employeesAlreadyPaid}: ${Formatters.currency(detail.totalPaid)} / ${Formatters.currency(detail.employeeSalary)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (detail.advanceCarryover > 0 && widget.summary.displaySourceMonth != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${l10n.employeesAdvanceFrom} ${widget.summary.displaySourceMonth}: ${Formatters.currency(detail.advanceCarryover)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.tertiary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Payment list
                Expanded(
                  child: detail == null
                      ? const Center(child: CircularProgressIndicator())
                      : detail.payments.isEmpty
                          ? Center(child: Text(l10n.employeesNosalaryhistory))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: detail.payments.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final p = detail.payments[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    Formatters.currency(p.amount),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(Formatters.date(p.paymentDate)),
                                  trailing: _paymentTypeBadge(context, p.paymentType),
                                );
                              },
                            ),
                ),
                const Divider(height: 1),
                // Footer with Pay More button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (detail != null && detail.remaining > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '${l10n.employeesRemainingbalance}: ${Formatters.currency(detail.remaining)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.tertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          Navigator.of(context).pop(); // close drill-down
                          // Find the employee to open pay dialog
                          final employee = await ref
                              .read(employeeRepositoryProvider)
                              .get(widget.employeeId);
                          if (context.mounted) {
                            switch (employee) {
                              case ApiSuccess(:final data):
                                await showSalaryPayDialog(context, employee: data);
                                ref.invalidate(employeeSalaryHistoryProvider(widget.employeeId));
                                ref.invalidate(employeeDetailProvider(widget.employeeId));
                              case ApiFailure():
                                break;
                            }
                          }
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(l10n.employeesPaymore),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
  }

  Widget _paymentTypeBadge(BuildContext context, String type) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (type) {
      'full' => ('Full', scheme.primary),
      'advance' => ('Advance', scheme.tertiary),
      'partial' => ('Partial', scheme.secondary),
      _ => (type, scheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// Document list with upload (multipart `POST /employees/:id/documents`
/// via [showEmployeeDocumentDialog]) + delete.
class _DocumentsTab extends ConsumerStatefulWidget {
  const _DocumentsTab({required this.employeeId});

  final int employeeId;

  @override
  ConsumerState<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<_DocumentsTab> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final documents = ref.watch(employeeDocumentsProvider(widget.employeeId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.employeesDocumentsTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await showEmployeeDocumentDialog(
                    context,
                    employeeId: widget.employeeId,
                  );
                  ref.invalidate(
                    employeeDocumentsProvider(widget.employeeId),
                  );
                },
                icon: const Icon(Icons.upload_file, size: 16),
                label: Text(l10n.employeesDocumentsAdd),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: documents.when(
            data: (rows) {
              if (rows.isEmpty) {
                return Center(
                  child: Text(l10n.employeesDocumentsNodocuments),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final doc in rows)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(doc.documentName),
                        subtitle: Text(
                          [
                            if (doc.documentType != null) doc.documentType!,
                            if (doc.documentNumber != null)
                              doc.documentNumber!,
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: l10n.commonDelete,
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => _removeDocument(doc),
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => DetailError(
              message: error is ApiError ? error.message : '$error',
              onRetry: () => ref.invalidate(
                employeeDocumentsProvider(widget.employeeId),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _removeDocument(EmployeeDocument doc) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: '${l10n.commonDelete} "${doc.documentName}"?',
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final result = await ref
        .read(employeeRepositoryProvider)
        .removeDocument(widget.employeeId, doc.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(employeeDocumentsProvider(widget.employeeId));
        showAppToast(context, l10n.employeesDocumentsDeleted);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }
}
