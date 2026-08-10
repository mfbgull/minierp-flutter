// Employee detail dialog — fetched from `GET /employees/:id` with three
// tabs: Overview (contact / HR / bank info), Salary History
// (`GET /employees/:id/salary/history`) and Documents
// (`GET /employees/:id/documents`). The header offers Edit and Pay
// Salary; the tabs use the shared detail-row widgets.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/status_badge.dart';
import 'employee_document_dialog.dart';
import 'employee_form_dialog.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart' show employeeRepositoryProvider;
import 'salary_pay_dialog.dart';

/// Opens the detail dialog for one employee.
Future<void> showEmployeeDetailDialog(
  BuildContext context, {
  required int employeeId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => EmployeeDetailDialog(employeeId: employeeId),
  );
}

class EmployeeDetailDialog extends ConsumerStatefulWidget {
  const EmployeeDetailDialog({super.key, required this.employeeId});

  final int employeeId;

  @override
  ConsumerState<EmployeeDetailDialog> createState() =>
      _EmployeeDetailDialogState();
}

class _EmployeeDetailDialogState extends ConsumerState<EmployeeDetailDialog> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final employee = ref.watch(employeeDetailProvider(widget.employeeId));

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
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
      ),
    );
  }

  Widget _tabChip(String label, int index) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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
              color: employee.isActive ? Colors.green : Colors.blueGrey,
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

/// Salary payment history table.
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
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              horizontalMargin: 8,
              columns: [
              DataColumn(label: detailSectionLabel(context, l10n.fieldsDate)),
              DataColumn(
                label: detailSectionLabel(context, l10n.fieldsAmount),
              ),
              DataColumn(
                label: detailSectionLabel(context, l10n.employeesPaymentmethod),
              ),
              DataColumn(
                label: detailSectionLabel(context, l10n.employeesReferenceno),
              ),
            ],
            rows: [
              for (final p in rows)
                DataRow(
                  cells: [
                    DataCell(Text(Formatters.date(p.paymentDate))),
                    DataCell(
                      Text(
                        Formatters.currency(p.amount),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    DataCell(Text(detailDash(p.paymentMethod))),
                    DataCell(Text(detailDash(p.referenceNo))),
                  ],
                ),
            ],
            ),
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
