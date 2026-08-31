// Personal Loans tab — shows summary cards, loan list with search/filter/sort,
// and CSV export. Purely record-keeping — no GL impact.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/theme/app_border_radius.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart'
    show
        autoFitPlutoColumns,
        plutoGridConfigurationFor,
        serialGridColumn,
        withSerialCell;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart';
import 'personal_loan_models.dart';
import 'personal_loan_providers.dart';
import 'personal_loan_repository.dart' show personalLoanRepositoryProvider;
import 'personal_loan_create_dialog.dart';
import 'personal_loan_detail_dialog.dart';
import 'personal_loan_borrower_list_dialog.dart';

class PersonalLoansTab extends ConsumerStatefulWidget {
  const PersonalLoansTab({super.key});

  @override
  ConsumerState<PersonalLoansTab> createState() => _PersonalLoansTabState();
}

class _PersonalLoansTabState extends ConsumerState<PersonalLoansTab> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  PlutoGridStateManager? _stateManager;
  late List<PlutoColumn> _columns;
  bool _columnsReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsReady) {
      _columns = _buildColumns(AppLocalizations.of(context)!);
      _columnsReady = true;
    }
  }

  GridColumnWidths? _widthTracker;

  @override
  void dispose() {
    _widthTracker?.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(personalLoansSearchProvider.notifier).state = value.trim();
    });
  }

  void _applyRows(AsyncValue<PagedResponse<PersonalLoan>> value) {
    final manager = _stateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in (value.value!.items).indexed)
          _rowFor(row, index),
      ]);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(_stateManager, manager)) return;
        final tracker = _widthTracker;
        if (tracker != null) {
          tracker.programmaticPass(() => autoFitPlutoColumns(manager));
        } else {
          autoFitPlutoColumns(manager);
        }
      });
    }
  }

  PlutoRow _rowFor(PersonalLoan row, int index) => withSerialCell(
        PlutoRow(
          cells: {
            'data': PlutoCell(value: row),
            'id': PlutoCell(value: row.id),
            'loan_no': PlutoCell(value: row.loanNo),
            'borrower_name': PlutoCell(value: row.borrowerName),
            'borrower_type': PlutoCell(value: row.borrowerType ?? ''),
            'amount': PlutoCell(value: row.amount),
            'balance': PlutoCell(value: row.balance),
            'currency': PlutoCell(value: row.currency),
            'loan_date': PlutoCell(value: row.loanDate),
            'due_date': PlutoCell(value: row.dueDate ?? ''),
            'purpose': PlutoCell(value: row.purpose ?? ''),
            'status': PlutoCell(value: row.status),
            'repayment_count': PlutoCell(value: row.repaymentCount),
            'created_by': PlutoCell(value: row.createdByName ?? ''),
          },
        ),
        index,
      );

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(personalLoansProvider);
    final page = loans.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    ref.listen(personalLoansProvider, (previous, next) => _applyRows(next));

    // Also apply rows directly on build — covers the case where the
    // provider resolved between the previous build and this one.
    if (_stateManager != null && loans.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyRows(ref.read(personalLoansProvider));
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _loanSummaryCards(l10n),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _toolbar(l10n),
        ),
        Expanded(child: _buildBody(loans)),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(personalLoansLimitProvider),
            itemLabel: l10n.equityPersonalLoans,
            onPageChanged: (p) =>
                ref.read(personalLoansPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(personalLoansLimitProvider.notifier).state = limit;
              if (ref.read(personalLoansPageProvider) != 1) {
                ref.read(personalLoansPageProvider.notifier).state = 1;
              }
            },
          ),
      ],
    );
  }

  Widget _loanSummaryCards(AppLocalizations l10n) {
    final loanSummary = ref.watch(personalLoanSummaryProvider);
    final scheme = Theme.of(context).colorScheme;
    final data = loanSummary.valueOrNull;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.smRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: _LoanStat(
                icon: Icons.handshake_outlined,
                label: l10n.equityPersonalLoanTotalLent,
                value: Formatters.currency(data?.totalLent ?? 0),
                color: scheme.primary,
              ),
            ),
            _loanStatDivider(scheme),
            Expanded(
              child: _LoanStat(
                icon: Icons.payments_outlined,
                label: l10n.equityPersonalLoanTotalRepaid,
                value: Formatters.currency(data?.totalRepaid ?? 0),
                color: scheme.tertiary,
              ),
            ),
            _loanStatDivider(scheme),
            Expanded(
              child: _LoanStat(
                icon: Icons.pending_outlined,
                label: l10n.equityPersonalLoanTotalPending,
                value: Formatters.currency(data?.totalPending ?? 0),
                color: scheme.error,
              ),
            ),
            _loanStatDivider(scheme),
            Expanded(
              child: _LoanStat(
                icon: Icons.list_alt_outlined,
                label: l10n.equityPersonalLoanActiveCount,
                value: '${data?.activeCount ?? 0}',
                color: scheme.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loanStatDivider(ColorScheme scheme) => Container(
    width: 1,
    height: 36,
    color: scheme.outlineVariant,
  );

  Widget _toolbar(AppLocalizations l10n) {
    return ScreenToolbar(
      searchController: _searchController,
      searchHint: l10n.commonSearch,
      onSearchChanged: _onSearchChanged,
      onClearSearch: () {
        _searchController.clear();
        ref.read(personalLoansSearchProvider.notifier).state = '';
      },
      filters: [
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('personal-loans-status'),
          value: ref.watch(personalLoansStatusProvider),
          hint: l10n.equityPersonalLoanFilterAll,
          items: const [null, 'pending', 'partial', 'settled', 'written_off'],
          labelBuilder: (v) => switch (v) {
            'pending' => l10n.equityPersonalLoanStatusPending,
            'partial' => l10n.equityPersonalLoanStatusPartial,
            'settled' => l10n.equityPersonalLoanStatusSettled,
            'written_off' => l10n.equityPersonalLoanStatusWrittenOff,
            _ => l10n.equityPersonalLoanFilterAll,
          },
          width: 130,
          onChanged: (v) {
            ref.read(personalLoansStatusProvider.notifier).state = v;
            if (ref.read(personalLoansPageProvider) != 1) {
              ref.read(personalLoansPageProvider.notifier).state = 1;
            }
          },
        ),
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('personal-loans-sort'),
          value: ref.watch(personalLoansSortProvider)?.column,
          hint: 'Sort',
          items: const [
            null,
            'loan_date',
            'amount',
            'balance',
            'status',
            'loan_no',
          ],
          labelBuilder: (v) => switch (v) {
            'loan_date' => 'Date',
            'amount' => 'Amount',
            'balance' => 'Balance',
            'status' => 'Status',
            'loan_no' => 'Loan No',
            _ => 'Sort',
          },
          width: 130,
          onChanged: (v) {
            final current = ref.read(personalLoansSortProvider);
            final next = v == null
                ? null
                : PersonalLoansSort(
                    v,
                    current == null || current.column != v
                        ? 'DESC'
                        : (current.order == 'ASC' ? 'DESC' : 'ASC'),
                  );
            ref.read(personalLoansSortProvider.notifier).state = next;
            if (ref.read(personalLoansPageProvider) != 1) {
              ref.read(personalLoansPageProvider.notifier).state = 1;
            }
          },
        ),
      ],
      onRefresh: () => ref.invalidate(personalLoansProvider),
      actions: [
        TextButton.icon(
          onPressed: () {
            final rows = ref.read(allPersonalLoansProvider).valueOrNull;
            if (rows == null || rows.isEmpty) return;
            saveCsv(
              context,
              suggestedName: csvSuggestedName('personal-loans'),
              csv: _buildCsv(l10n, rows),
              successMessage: l10n.equityPersonalLoanExported,
              errorMessage: l10n.equityPersonalLoanExportFailed,
            );
          },
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: Text(l10n.expensesExportcsv),
        ),
        TextButton.icon(
          onPressed: () => _manageBorrowers(context),
          icon: const Icon(Icons.people_outline, size: 18),
          label: Text(l10n.equityPersonalLoanManageBorrowers),
        ),
      ],
      primaryActions: [
        FilledButton.tonalIcon(
          onPressed: () => _createLoan(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.equityPersonalLoanNew),
        ),
      ],
    );
  }

  Widget _buildBody(AsyncValue<PagedResponse<PersonalLoan>> loans) {
    final errorMessage = switch (loans) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      _stateManager = null;
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(personalLoansProvider),
      );
    }
    return _grid();
  }

  Widget _grid() {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: PlutoGrid(
        configuration: plutoGridConfigurationFor(context, compact: true),
        columns: _columns,
        rows: <PlutoRow>[],
        onLoaded: (event) {
          _stateManager = event.stateManager;
          _stateManager?.hideColumn(
            _columns.firstWhere((c) => c.field == 'id'),
            true,
            notify: false,
          );
          _applyRows(ref.read(personalLoansProvider));
          // Safety net: re-apply after the current frame in case the
          // provider resolved before onLoaded fired.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _applyRows(ref.read(personalLoansProvider));
          });
          _widthTracker?.dispose();
          _widthTracker = GridColumnWidths.attach(
            stateManager: event.stateManager,
            screenKey: 'personal_loans',
          );
        },
        onRowDoubleTap: (event) {
          final id = event.row.cells['id']?.value as int?;
          if (id == null || id <= 0) return;
          final rows = ref.read(personalLoansProvider).valueOrNull?.items ??
              const <PersonalLoan>[];
          for (final row in rows) {
            if (row.id == id) {
              _viewDetail(context, row);
              break;
            }
          }
        },
        onSorted: _onGridSorted,
        noRowsWidget: Center(
          child: Text(
            l10n.equityPersonalLoanNoLoans,
            style: TextStyle(color: scheme.outline),
          ),
        ),
      ),
    );
  }

  String? _sortColumnFor(String field) {
    switch (field) {
      case 'loan_no':
        return 'loan_no';
      case 'loan_date':
        return 'loan_date';
      case 'borrower_name':
        return 'borrower_name';
      case 'amount':
        return 'amount';
      case 'balance':
        return 'balance';
      case 'status':
        return 'status';
      default:
        return null;
    }
  }

  void _onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    final order = sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC';
    ref.read(personalLoansSortProvider.notifier).state =
        PersonalLoansSort(sortBy, order);
    if (ref.read(personalLoansPageProvider) != 1) {
      ref.read(personalLoansPageProvider.notifier).state = 1;
    }
  }

  List<PlutoColumn> _buildColumns(AppLocalizations l10n) {
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
      serialGridColumn(),
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
      textColumn('loan_no', l10n.equityPersonalLoanLoanNo, 140),
      textColumn('borrower_name', l10n.equityPersonalLoanBorrower, 160),
      PlutoColumn(
        title: '',
        field: 'borrower_type',
        type: PlutoColumnType.text(),
        width: 90,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final type = ctx.cell.value as String? ?? '';
          if (type.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                type == 'customer'
                    ? l10n.equityPersonalLoanBorrowerTypeCustomer
                    : l10n.equityPersonalLoanBorrowerTypeSupplier,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          );
        },
      ),
      PlutoColumn(
        title: l10n.equityPersonalLoanAmount,
        field: 'amount',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 130,
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
        title: l10n.equityPersonalLoanBalance,
        field: 'balance',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 130,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) {
          final balance = ctx.cell.value as num? ?? 0;
          final row = ctx.cell.row.cells['data']?.value as PersonalLoan?;
          final isSettled = row?.status == 'settled';
          return Align(
            alignment: Alignment.centerRight,
            child: Text(
              Formatters.currency(balance),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSettled ? Theme.of(context).colorScheme.outline : null,
              ),
            ),
          );
        },
      ),
      textColumn('currency', 'Cur', 60),
      PlutoColumn(
        title: l10n.fieldsDate,
        field: 'loan_date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerLeft,
          child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
        ),
      ),
      PlutoColumn(
        title: l10n.equityPersonalLoanDueDate,
        field: 'due_date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final due = ctx.cell.value as String? ?? '';
          if (due.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(Formatters.date(due)),
          );
        },
      ),
      textColumn('purpose', l10n.equityPersonalLoanPurpose, 120),
      PlutoColumn(
        title: l10n.fieldsStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 100,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final status = ctx.cell.value as String? ?? '';
          final (label, color) = switch (status) {
            'pending' => (
                l10n.equityPersonalLoanStatusPending,
                Theme.of(context).colorScheme.primary
              ),
            'partial' => (
                l10n.equityPersonalLoanStatusPartial,
                Theme.of(context).colorScheme.tertiary
              ),
            'settled' => (
                l10n.equityPersonalLoanStatusSettled,
                Theme.of(context).colorScheme.outline
              ),
            'written_off' => (
                l10n.equityPersonalLoanStatusWrittenOff,
                Theme.of(context).colorScheme.error
              ),
            _ => (status, Theme.of(context).colorScheme.outline),
          };
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            ),
          );
        },
      ),
      textColumn('created_by', l10n.expensesCreatedby, 130),
      PlutoColumn(
        title: l10n.commonActions,
        field: 'actions',
        frozen: PlutoColumnFrozen.end,
        type: PlutoColumnType.text(),
        width: 64,
        readOnly: true,
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
        renderer: (ctx) {
          final row = ctx.cell.row.cells['data']?.value as PersonalLoan?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                if (row != null && mounted) {
                  _showRowActions(context, row);
                }
              },
              child: Center(
                child: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: Theme.of(cellContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  // ── Actions ─────────────────────────────────────────────────

  Future<void> _createLoan(BuildContext context) async {
    final result = await showPersonalLoanCreateDialog(context);
    if (result == true && context.mounted) {
      ref.invalidate(personalLoansProvider);
      ref.invalidate(personalLoanSummaryProvider);
    }
  }

  Future<void> _viewDetail(BuildContext context, PersonalLoan loan) async {
    final result = await showPersonalLoanDetailDialog(
      context,
      loanId: loan.id,
    );
    if (result == true && context.mounted) {
      ref.invalidate(personalLoansProvider);
      ref.invalidate(personalLoanSummaryProvider);
    }
  }

  Future<void> _manageBorrowers(BuildContext context) async {
    final result = await showBorrowerListDialog(context);
    if (result == true && context.mounted) {
      ref.invalidate(borrowersProvider);
    }
  }

  void _showRowActions(BuildContext context, PersonalLoan loan) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final isSettled = loan.status == 'settled';
    final isWrittenOff = loan.status == 'written_off';
    final canEdit = !isSettled && !isWrittenOff;
    final canDelete = !loan.hasRepayments;
    final canWriteOff = loan.status == 'pending' || loan.status == 'partial';

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: Text(l10n.commonView),
              onTap: () {
                Navigator.pop(ctx);
                _viewDetail(context, loan);
              },
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.equityPersonalLoanEdit),
                onTap: () async {
                  Navigator.pop(ctx);
                  final result = await showPersonalLoanCreateDialog(
                    context,
                    loan: loan,
                  );
                  if (result == true && context.mounted) {
                    ref.invalidate(personalLoansProvider);
                    ref.invalidate(personalLoanSummaryProvider);
                  }
                },
              ),
            if (canWriteOff)
              ListTile(
                leading: Icon(Icons.cancel_outlined, color: scheme.error),
                title: Text(
                  l10n.equityPersonalLoanStatusWrittenOff,
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _writeOff(context, loan);
                },
              ),
            if (canDelete)
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteLoan(context, loan);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _writeOff(BuildContext context, PersonalLoan loan) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.equityPersonalLoanStatusWrittenOff),
        content: Text(
          '${l10n.equityPersonalLoanStatusWrittenOff} ${Formatters.currency(loan.balance)}?',
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
            child: Text(l10n.equityPersonalLoanStatusWrittenOff),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(personalLoanRepositoryProvider)
        .updateLoan(loan.id, {'status': 'written_off', 'balance': 0});
    if (!context.mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(personalLoansProvider);
        ref.invalidate(personalLoanSummaryProvider);
      case ApiFailure(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
    }
  }

  Future<void> _deleteLoan(BuildContext context, PersonalLoan loan) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text('${l10n.equityPersonalLoanDeleteConfirm} ${loan.loanNo}?'),
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
        .deleteLoan(loan.id);
    if (!context.mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(personalLoansProvider);
        ref.invalidate(personalLoanSummaryProvider);
      case ApiFailure(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
    }
  }

  String _buildCsv(AppLocalizations l10n, List<PersonalLoan> loans) {
    final buffer = StringBuffer();
    buffer.writeln([
      'Loan No',
      l10n.equityPersonalLoanBorrower,
      l10n.equityPersonalLoanAmount,
      'Currency',
      'Balance',
      'Repaid',
      l10n.equityPersonalLoanDateGiven,
      l10n.equityPersonalLoanDueDate,
      l10n.equityPersonalLoanPurpose,
      l10n.fieldsStatus,
      l10n.expensesCreatedby,
    ].join(','));

    for (final loan in loans) {
      buffer.writeln([
        loan.loanNo,
        '"${loan.borrowerName.replaceAll('"', '""')}"',
        loan.amount,
        loan.currency,
        loan.balance,
        loan.repaidAmount,
        loan.loanDate,
        loan.dueDate ?? '',
        '"${(loan.purpose ?? '').replaceAll('"', '""')}"',
        loan.status,
        '"${(loan.createdByName ?? '').replaceAll('"', '""')}"',
      ].join(','));
    }
    return buffer.toString();
  }
}

class _LoanStat extends StatelessWidget {
  const _LoanStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
