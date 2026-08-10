// Employees list screen — PORTING.md §5/§6. Server-paginated PlutoGrid
// over `GET /employees` (the endpoint returns a `{page, limit, total,
// totalPages}` pagination block, so like customers this screen drives
// page/limit/search through providers and renders a ServerPaginationBar).
//
// Toolbar: search (debounced), department + status filter dropdowns (the
// department options come from the loaded page — there is no reference
// endpoint), Add Employee, refresh. Double-tapping a row opens the
// employee detail dialog (overview + salary history + documents); the
// per-row actions menu offers Pay Salary, Edit and Delete.
//
// Summary strip: active count + total salary computed from the *loaded*
// rows, so it always matches the active filters/pagination.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'employee_form_dialog.dart';
import 'employee_detail_dialog.dart';
import 'employee_models.dart';
import 'employee_providers.dart';
import 'employee_repository.dart' show employeeRepositoryProvider;
import 'salary_pay_dialog.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen>
    with PlutoGridScreen<Employee, EmployeesScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void openRowDetail(int employeeId) {
    if (!mounted) return;
    showEmployeeDetailDialog(context, employeeId: employeeId);
  }

  /// The employees provider returns a `PagedResponse` envelope — unwrap
  /// the current page's items as the grid rows.
  @override
  Iterable<Employee> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Employee>).items;

  @override
  PlutoRow gridRowFor(Employee employee) => PlutoRow(
    cells: {
      'id': PlutoCell(value: employee.id),
      'code': PlutoCell(value: employee.employeeCode),
      'name': PlutoCell(value: employee.fullName),
      'department': PlutoCell(value: employee.department ?? ''),
      'designation': PlutoCell(value: employee.designation ?? ''),
      'employment_type': PlutoCell(value: employee.employmentType ?? ''),
      'phone': PlutoCell(value: employee.phone ?? ''),
      'email': PlutoCell(value: employee.email ?? ''),
      'salary': PlutoCell(value: employee.salary),
      'active': PlutoCell(value: employee.isActive),
      'actions': PlutoCell(value: ''),
    },
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(employeesSearchProvider.notifier).state = value.trim();
      if (ref.read(employeesPageProvider) != 1) {
        ref.read(employeesPageProvider.notifier).state = 1;
      }
    });
  }

  bool get _hasActiveFilters =>
      ref.read(employeesDepartmentProvider) != null ||
      ref.read(employeesStatusProvider) != null;

  void _clearFilters() {
    ref.read(employeesDepartmentProvider.notifier).state = null;
    ref.read(employeesStatusProvider.notifier).state = null;
  }

  Future<void> _deleteEmployee(Employee employee) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDeleteEmployeeConfirm(context);
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(employeeRepositoryProvider)
        .delete(employee.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(employeesProvider);
        showAppToast(context, l10n.employeesMessagesDeleted);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesProvider);
    final l10n = AppLocalizations.of(context)!;
    final page = employees.valueOrNull;

    watchGridProvider(employeesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _toolbar(l10n),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _summaryStrip(l10n, employees),
        ),
        Expanded(child: gridScreenBody(employees, provider: employeesProvider)),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(employeesLimitProvider),
            itemLabel: l10n.employeesCount,
            onPageChanged: (p) =>
                ref.read(employeesPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(employeesLimitProvider.notifier).state = limit;
              if (ref.read(employeesPageProvider) != 1) {
                ref.read(employeesPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _toolbar(AppLocalizations l10n) {
    return ScreenToolbar(
      searchController: _searchController,
      searchHint: l10n.employeesSearch,
      onSearchChanged: _onSearchChanged,
      onClearSearch: () {
        _debounce?.cancel();
        _searchController.clear();
        ref.read(employeesSearchProvider.notifier).state = '';
        if (ref.read(employeesPageProvider) != 1) {
          ref.read(employeesPageProvider.notifier).state = 1;
        }
      },
      filters: [
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('employee-department-filter'),
          value: ref.watch(employeesDepartmentProvider),
          items: [null, ...ref.watch(employeesDepartmentsProvider)],
          labelBuilder: (v) => v ?? l10n.employeesAlldepartments,
          width: 180,
          onChanged: (v) {
            ref.read(employeesDepartmentProvider.notifier).state = v;
            if (ref.read(employeesPageProvider) != 1) {
              ref.read(employeesPageProvider.notifier).state = 1;
            }
          },
        ),
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('employee-status-filter'),
          value: ref.watch(employeesStatusProvider),
          items: const [null, 'active', 'inactive'],
          labelBuilder: (v) => switch (v) {
            null => l10n.employeesAllstatus,
            'active' => l10n.statusActive,
            _ => l10n.statusInactive,
          },
          width: 150,
          onChanged: (v) {
            ref.read(employeesStatusProvider.notifier).state = v;
            if (ref.read(employeesPageProvider) != 1) {
              ref.read(employeesPageProvider.notifier).state = 1;
            }
          },
        ),
      ],
      onRefresh: () => ref.invalidate(employeesProvider),
      onClearAll: _clearFilters,
      hasActiveFilters: _hasActiveFilters,
      primaryActions: [
        FilledButton.tonalIcon(
          onPressed: () => showEmployeeFormDialog(context),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: Text(l10n.employeesAddnew),
        ),
      ],
    );
  }

  Widget _summaryStrip(
    AppLocalizations l10n,
    AsyncValue<PagedResponse<Employee>> employees,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final rows = employees.valueOrNull?.items ?? const <Employee>[];
    final active = rows.where((e) => e.isActive).length;
    final totalSalary = rows.fold<num>(0, (sum, e) => sum + e.salary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            '${rows.length} ${l10n.employeesCount}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 14),
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: Colors.green.shade600,
          ),
          const SizedBox(width: 4),
          Text('$active ${l10n.employeesActivecount}'),
          const SizedBox(width: 14),
          Icon(
            Icons.payments_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(l10n.employeesTotalsalary),
          const SizedBox(width: 6),
          Text(
            Formatters.currency(totalSalary),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// Per-row actions menu — Pay Salary / Edit / Delete.
  Widget _rowActions(Employee employee) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.center,
      child: PopupMenuButton<String>(
        tooltip: l10n.commonActions,
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (action) => switch (action) {
          'pay' => showSalaryPayDialog(context, employee: employee),
          'edit' => showEmployeeFormDialog(context, employee: employee),
          'delete' => _deleteEmployee(employee),
          _ => null,
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'pay',
            child: Row(
              children: [
                const Icon(Icons.payments_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l10n.employeesPaysalary),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l10n.commonEdit),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(l10n.commonDelete),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) {
    PlutoColumn textColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          width: width,
          readOnly: true,
          enableContextMenu: false,
        );

    return [
      PlutoColumn(
        title: '',
        field: 'id',
        type: PlutoColumnType.number(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('code', 'Code', 110),
      textColumn('name', l10n.employeesFullname, 200),
      textColumn('department', l10n.employeesFieldsDepartment, 140),
      textColumn('designation', l10n.employeesFieldsDesignation, 140),
      textColumn('employment_type', l10n.employeesEmploymenttype, 120),
      textColumn('phone', l10n.employeesFieldsPhone, 130),
      textColumn('email', l10n.employeesFieldsEmail, 170),
      PlutoColumn(
        title: l10n.employeesFieldsSalary,
        field: 'salary',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 120,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(
            Formatters.currency(ctx.cell.value as num? ?? 0),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      PlutoColumn(
        title: l10n.fieldsStatus,
        field: 'active',
        type: PlutoColumnType.text(),
        width: 100,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final active = ctx.cell.value == true;
            final l10n = AppLocalizations.of(cellContext)!;
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: active ? l10n.statusActive : l10n.statusInactive,
                color: active ? Colors.green : Colors.blueGrey,
              ),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.commonActions,
        field: 'actions',
        type: PlutoColumnType.text(),
        width: 80,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final id = (ctx.row.cells['id']?.value as num?)?.toInt() ?? 0;
          final rows =
              ref.read(employeesProvider).valueOrNull?.items ?? const [];
          final employee = rows.where((e) => e.id == id).firstOrNull;
          if (employee == null) return const SizedBox.shrink();
          return _rowActions(employee);
        },
      ),
    ];
  }
}

Future<bool?> showDeleteEmployeeConfirm(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.commonDelete),
      content: Text(l10n.employeesDeleteconfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.commonDelete),
        ),
      ],
    ),
  );
}
