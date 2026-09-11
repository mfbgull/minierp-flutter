// Unified Payments screen — PORTING.md §5/§6. A single hub for every
// payment-related cash movement (customer payments, supplier payments,
// expenses, salary payments, owner capital, owner withdrawals). The list is
// the server-paginated `GET /payments/unified` projection (see
// [unifiedPaymentsProvider]); the "New Payment" menu launches each source's
// own create flow, so GL posting stays owned by the source module.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart' show authProvider;
import '../../core/theme/money_direction.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/unified_payment.dart' show UnifiedPayment;
import '../../data/repositories/api_result.dart' show ApiResult;
import '../../features/employees/employee_repository.dart' show employeeRepositoryProvider;
import '../../data/repositories/invoice_repository.dart' show invoiceRepositoryProvider;
import '../../data/repositories/owner_equity_repository.dart' show ownerEquityRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../features/employees/salary_pay_dialog.dart'
    show showSalaryPayDialog;
import '../../features/expenses/expense_form_dialog.dart'
    show showExpenseFormDialog;
import '../../features/owner_equity/owner_capital_form_dialog.dart'
    show showOwnerCapitalFormDialog;
import '../../features/owner_equity/owner_withdrawal_form_dialog.dart'
    show showOwnerWithdrawalFormDialog;
import '../../features/suppliers/supplier_payment_modal.dart'
    show showSupplierPaymentModal;
import '../../l10n/app_localizations.dart';
import '../../widgets/bulk_operations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import '../payments/payment_detail_dialog.dart' show showPaymentDetailDialog;
import '../payments/payment_party_picker.dart'
    show showEmployeePickerDialog, showSupplierPickerDialog;
import '../payments/payments_providers.dart'
    show
        PaymentSort,
        invalidateCashMovementProviders,
        unifiedPaymentsFromDateProvider,
        unifiedPaymentsLimitProvider,
        unifiedPaymentsPageProvider,
        unifiedPaymentsProvider,
        unifiedPaymentsSearchProvider,
        unifiedPaymentsSortProvider,
        unifiedPaymentsToDateProvider,
        unifiedPaymentsTypeFilterProvider;
import '../payments/record_payment_dialog.dart' show showRecordPaymentDialog;
import '../payments/unified_payment_detail_sheet.dart'
    show showUnifiedPaymentDetailSheet;
import '../payments/unified_payment_labels.dart';

/// Rank per `source` so the grid's integer id cell is collision-free across
/// sources (a payment id and a salary id can otherwise coincide).
const Map<String, int> _sourceRank = {
  'payment': 1,
  'expense': 2,
  'salary': 3,
  'owner_capital': 4,
  'owner_withdrawal': 5,
};

int _encodeId(String source, int sourceId) =>
    (_sourceRank[source] ?? 0) * 10000000000 + (sourceId >= 0 ? sourceId : 0);

/// Menu key → unified `source` used for list invalidation after a write.
const Map<String, String> _menuSource = {
  'customer': 'payment',
  'supplier': 'payment',
  'expense': 'expense',
  'salary': 'salary',
  'owner_capital': 'owner_capital',
  'owner_withdrawal': 'owner_withdrawal',
};

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen>
    with PlutoGridScreen<UnifiedPayment, PaymentsScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  bool _bulkBusy = false;

  Map<int, UnifiedPayment> get _paymentsById => {
    for (final p
        in ref.read(unifiedPaymentsProvider).valueOrNull?.items ??
            const <UnifiedPayment>[])
      _encodeId(p.source, p.sourceId): p,
  };

  @override
  bool get enableBulkSelection => true;

  @override
  String get filterSignature {
    final search = ref.read(unifiedPaymentsSearchProvider);
    final type = ref.read(unifiedPaymentsTypeFilterProvider);
    final from = ref.read(unifiedPaymentsFromDateProvider);
    final to = ref.read(unifiedPaymentsToDateProvider);
    return '$search|$type|$from|$to';
  }

  @override
  void openRowDetail(int rowId) {
    if (!mounted) return;
    final row = gridStateManager?.rows.firstWhere(
      (r) => (r.cells['id']?.value as int? ?? -1) == rowId,
      orElse: () => PlutoRow(cells: const {}),
    );
    final payment = row?.cells['data']?.value as UnifiedPayment?;
    if (payment == null) return;
    _openDetail(payment);
  }

  void _openDetail(UnifiedPayment payment) {
    if (!mounted) return;
    if (payment.source == 'payment') {
      showPaymentDetailDialog(context, paymentId: payment.sourceId);
    } else {
      showUnifiedPaymentDetailSheet(context, payment: payment);
    }
  }

  @override
  Iterable<UnifiedPayment> gridRowsFrom(Object? value) =>
      (value as PagedResponse<UnifiedPayment>).items;

  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final payment = row.cells['data']?.value as UnifiedPayment?;
    if (payment == null) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => _openDetail(payment),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(UnifiedPayment p) => PlutoRow(
    cells: {
      'id': PlutoCell(value: _encodeId(p.source, p.sourceId)),
      'source': PlutoCell(value: p.source),
      'data': PlutoCell(value: p),
      'type': PlutoCell(value: p.type),
      'ref_no': PlutoCell(value: p.refNo),
      'date': PlutoCell(value: p.date),
      'party': PlutoCell(value: p.party),
      'amount': PlutoCell(value: p.amount),
      'method': PlutoCell(value: p.method),
      'status': PlutoCell(value: p.status),
      'description': PlutoCell(value: p.description ?? ''),
    },
  );

  @override
  List<String> get hiddenGridColumnFields => const ['id'];

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
      ref.read(unifiedPaymentsSearchProvider.notifier).state = value.trim();
      if (ref.read(unifiedPaymentsPageProvider) != 1) {
        ref.read(unifiedPaymentsPageProvider.notifier).state = 1;
      }
    });
  }

  /// Delete a single payment by routing to the correct source endpoint.
  Future<ApiResult<void>> _deletePayment(UnifiedPayment p) async {
    switch (p.source) {
      case 'payment':
        return ref.read(invoiceRepositoryProvider).deletePayment(p.sourceId);
      case 'salary':
        return ref
            .read(employeeRepositoryProvider)
            .deleteSalaryPayment(p.partyId ?? 0, p.sourceId);
      case 'owner_capital':
        return ref.read(ownerEquityRepositoryProvider).voidCapital(p.sourceId);
      case 'owner_withdrawal':
        return ref
            .read(ownerEquityRepositoryProvider)
            .voidWithdrawal(p.sourceId);
      default:
        // Expenses are immutable (D20) — should not reach here.
        throw UnsupportedError('Cannot delete ${p.source} payments');
    }
  }

  /// Bulk delete with typed `DELETE` confirm (D23) for the unified
  /// payments view. Routes each payment to its source-specific endpoint.
  /// Expenses are skipped (immutable, D20).
  Future<void> _bulkDelete(Set<int> ids) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await _showTypedDeleteConfirm(
      context,
      count: ids.length,
    );
    if (!confirmed || !mounted) return;

    setState(() => _bulkBusy = true);
    final succeeded = <int>[];
    final failures = <BulkFailure>[];
    for (final encodedId in ids) {
      final payment = _paymentsById[encodedId];
      if (payment == null) {
        failures.add(BulkFailure(label: '#$encodedId', reason: 'Not found'));
        continue;
      }
      if (payment.source == 'expense') {
        failures.add(
          BulkFailure(
            label: payment.refNo.isNotEmpty ? payment.refNo : '#${payment.sourceId}',
            reason: 'Expenses are immutable',
          ),
        );
        continue;
      }
      try {
        final result = await _deletePayment(payment);
        result.fold(
          onSuccess: (_) => succeeded.add(encodedId),
          onFailure: (error) => failures.add(
            BulkFailure(
              label: payment.refNo.isNotEmpty ? payment.refNo : '#${payment.sourceId}',
              reason: error.message,
            ),
          ),
        );
      } catch (e) {
        failures.add(
          BulkFailure(
            label: payment.refNo.isNotEmpty ? payment.refNo : '#${payment.sourceId}',
            reason: e.toString(),
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() => _bulkBusy = false);

    final result = BulkOperationResult(
      succeeded: succeeded,
      failures: failures,
    );
    await finishBulkOperation(
      context,
      bulk: bulkSelection,
      result: result,
      successMessage: l10n.bulkDeleted,
      onComplete: () => ref.invalidate(unifiedPaymentsProvider),
    );
  }

  /// D23 typed confirm — the user must type `DELETE` before the button
  /// enables. Expenses are also listed as excluded in the message.
  Future<bool> _showTypedDeleteConfirm(
    BuildContext context, {
    required int count,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    var typed = false;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.commonDelete),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.bulkDeleteSelected} ($count)?'),
              const SizedBox(height: 4),
              Text(
                'Expenses are immutable and will be skipped.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type DELETE to confirm',
                ),
                onChanged: (v) {
                  final matches = v == 'DELETE';
                  if (matches != typed) {
                    typed = matches;
                    setDialogState(() {});
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: typed
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: Text(l10n.commonDelete),
            ),
          ],
        ),
      ),
    ).then((v) => v ?? false);
  }

  void _bulkExport(Set<int> ids) {
    final l10n = AppLocalizations.of(context)!;
    final selected = [
      for (final p in _paymentsById.values)
        if (ids.contains(_encodeId(p.source, p.sourceId))) p,
    ];
    if (selected.isEmpty) return;
    saveCsv(
      context,
      suggestedName: csvSuggestedName('payments'),
      csv: buildPaymentsCsv(l10n, selected),
      successMessage: l10n.bulkExportSelected,
      errorMessage: l10n.bulkDeleteFailed,
    );
  }

  /// Grid field → server sort column (whitelist in
  /// `PaymentModel.getUnifiedPayments`; only these columns sort).
  String? _sortColumnFor(String field) => switch (field) {
    'ref_no' => 'ref_no',
    'date' => 'date',
    'amount' => 'amount',
    'type' => 'type',
    'party' => 'party',
    _ => null,
  };

  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(unifiedPaymentsSortProvider.notifier).state = sort.isNone
        ? null
        : PaymentSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(unifiedPaymentsPageProvider) != 1) {
      ref.read(unifiedPaymentsPageProvider.notifier).state = 1;
    }
  }

  Future<void> _onPickPayment(String kind) async {
    switch (kind) {
      case 'customer':
        await showRecordPaymentDialog(context);
      case 'supplier':
        final supplier = await showSupplierPickerDialog(context);
        if (supplier == null) return;
        if (!mounted) return;
        await showSupplierPaymentModal(context, supplier: supplier);
      case 'expense':
        await showExpenseFormDialog(context);
      case 'salary':
        final employee = await showEmployeePickerDialog(context);
        if (employee == null) return;
        if (!mounted) return;
        await showSalaryPayDialog(context, employee: employee);
      case 'owner_capital':
        await showOwnerCapitalFormDialog(context);
      case 'owner_withdrawal':
        await showOwnerWithdrawalFormDialog(context);
    }
    // Refresh every list the new transaction could appear in. Runs after the
    // dialog closes (create or cancel) so the hub always reflects latest.
    invalidateCashMovementProviders(ref, _menuSource[kind] ?? 'payment');
  }

  @override
  Widget build(BuildContext context) {
    final payments = ref.watch(unifiedPaymentsProvider);
    final l10n = AppLocalizations.of(context)!;
    final page = payments.valueOrNull;

    watchGridProvider(unifiedPaymentsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.paymentsSearchplaceholder,
          onSearchChanged: _onSearchChanged,
          onClearSearch: () {
            _debounce?.cancel();
            _searchController.clear();
            ref.read(unifiedPaymentsSearchProvider.notifier).state = '';
            if (ref.read(unifiedPaymentsPageProvider) != 1) {
              ref.read(unifiedPaymentsPageProvider.notifier).state = 1;
            }
          },
          onRefresh: () => ref.invalidate(unifiedPaymentsProvider),
          filters: [
            DateRangeFilter(
              fromProvider: unifiedPaymentsFromDateProvider,
              toProvider: unifiedPaymentsToDateProvider,
              onChanged: () {
                if (ref.read(unifiedPaymentsPageProvider) != 1) {
                  ref.read(unifiedPaymentsPageProvider.notifier).state = 1;
                }
              },
            ),
            moneyTintFilterChip(context, ref, l10n: l10n),
          ],
          primaryActions: [
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  onPressed: () => _onPickPayment('customer'),
                  child: Text(l10n.paymentsReceiveFromCustomer),
                ),
                MenuItemButton(
                  onPressed: () => _onPickPayment('supplier'),
                  child: Text(l10n.paymentsPayToSupplier),
                ),
                MenuItemButton(
                  onPressed: () => _onPickPayment('expense'),
                  child: Text(l10n.paymentsRecordExpense),
                ),
                MenuItemButton(
                  onPressed: () => _onPickPayment('salary'),
                  child: Text(l10n.paymentsPaySalary),
                ),
                MenuItemButton(
                  onPressed: () => _onPickPayment('owner_capital'),
                  child: Text(l10n.paymentsOwnerCapital),
                ),
                MenuItemButton(
                  onPressed: () => _onPickPayment('owner_withdrawal'),
                  child: Text(l10n.paymentsOwnerWithdrawal),
                ),
              ],
              builder: (ctx, controller, child) => FilledButton.tonalIcon(
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                label: Text(l10n.paymentsNewpayment),
              ),
            ),
          ],
        ),
        ValueListenableBuilder<Set<int>>(
          valueListenable: bulkSelection.selected,
          builder: (context, sel, _) {
            if (sel.isEmpty) return const SizedBox.shrink();
            final user = ref.watch(authProvider).user;
            return BulkActionBar(
              count: sel.length,
              onClearSelection: bulkSelection.clear,
              busy: _bulkBusy,
              actions: [
                if (user?.hasPermission('payments', 'read') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkExport(sel),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(l10n.bulkExportSelected),
                  ),
                if (user?.hasPermission('payments', 'delete') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkDelete(sel),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(l10n.bulkDeleteSelected),
                  ),
              ],
            );
          },
        ),
        _TypeFilterChips(l10n: l10n, ref: ref),
        Expanded(
          child: gridScreenBody(
            payments,
            provider: unifiedPaymentsProvider,
            rowColorCallback: moneyRowColorCallback(
              context,
              ref,
              // Money in when direction == 'in' (customer payment /
              // refund to us); money out when 'out' (we pay a supplier,
              // expense or salary). Unknown directions stay neutral.
              (row) {
                final direction =
                    (row.cells['data']?.value as UnifiedPayment?)
                        ?.direction ??
                    'unknown';
                return switch (direction) {
                  'in' => MoneyDirection.inflow,
                  'out' => MoneyDirection.outflow,
                  _ => MoneyDirection.neutral,
                };
              },
            ),
          ),
        ),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(unifiedPaymentsLimitProvider),
            itemLabel: l10n.paymentsPayments,
            onPageChanged: (p) =>
                ref.read(unifiedPaymentsPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(unifiedPaymentsLimitProvider.notifier).state = limit;
              if (ref.read(unifiedPaymentsPageProvider) != 1) {
                ref.read(unifiedPaymentsPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) {
    PlutoColumn textColumn(String field, String title, double width,
            {bool sortable = false}) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          width: width,
          readOnly: true,
          enableContextMenu: false,
          enableSorting: sortable,
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
      PlutoColumn(
        title: l10n.fieldsType,
        field: 'type',
        type: PlutoColumnType.text(),
        width: 150,
        readOnly: true,
        enableContextMenu: false,
        enableSorting: true,
        renderer: (ctx) {
          final type = ctx.cell.value?.toString() ?? 'unknown';
          final direction = ctx.row.cells['data']?.value is UnifiedPayment
              ? (ctx.row.cells['data']!.value as UnifiedPayment).direction
              : 'unknown';
          final isIn = direction == 'in';
          final isUnknown = direction == 'unknown';
          final color = isUnknown
              ? StatusColors.of(context).warning
              : isIn
                  ? StatusColors.of(context).success
                  : StatusColors.of(context).error;
          return Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: unifiedTypeLabel(l10n, type),
              color: color,
            ),
          );
        },
      ),
      textColumn('ref_no', l10n.paymentsPaymentno, 140, sortable: true),
      PlutoColumn(
        title: l10n.fieldsDate,
        field: 'date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        enableSorting: true,
        renderer: (ctx) => Builder(
          builder: (cellContext) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.date(ctx.cell.value as String? ?? ''),
              style: Theme.of(cellContext).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
      textColumn('party', l10n.paymentsParty, 180, sortable: true),
      PlutoColumn(
        title: l10n.fieldsAmount,
        field: 'amount',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 120,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        enableSorting: true,
        renderer: (ctx) {
          final payment = ctx.row.cells['data']?.value;
          final direction = payment is UnifiedPayment ? payment.direction : 'unknown';
          final color = direction == 'in'
              ? StatusColors.of(context).success
              : direction == 'out'
                  ? StatusColors.of(context).error
                  : StatusColors.of(context).warning;
          final prefix = direction == 'out'
              ? '- '
              : direction == 'in'
                  ? '+ '
                  : '';
          return Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$prefix${Formatters.currency(ctx.cell.value as num? ?? 0)}',
              style: TextStyle(color: color),
            ),
          );
        },
      ),
      PlutoColumn(
        title: l10n.expensesPaymentmethod,
        field: 'method',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        enableSorting: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerLeft,
          child: Text(unifiedMethodLabel(l10n, ctx.cell.value?.toString() ?? 'unknown')),
        ),
      ),
      textColumn('status', l10n.fieldsStatus, 110),
      textColumn('description', l10n.fieldsNotes, 200),
    ];
  }
}

/// Type filter chips above the grid — bound to
/// [unifiedPaymentsTypeFilterProvider] and resetting the page to 1.
class _TypeFilterChips extends ConsumerWidget {
  const _TypeFilterChips({required this.l10n, required this.ref});

  final AppLocalizations l10n;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(unifiedPaymentsTypeFilterProvider);
    final chips = [
      ('all', l10n.paymentsFilterAll),
      ('customer', l10n.paymentsTypeCustomer),
      ('supplier', l10n.paymentsTypeSupplier),
      ('expense', l10n.paymentsTypeExpense),
      ('salary', l10n.paymentsTypeSalary),
      ('owner_capital', l10n.paymentsTypeOwnerCapital),
      ('owner_withdrawal', l10n.paymentsTypeOwnerWithdrawal),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (value, label) in chips)
            ChoiceChip(
              label: Text(label),
              selected: selected == value,
              onSelected: (_) {
                ref.read(unifiedPaymentsTypeFilterProvider.notifier).state = value;
                if (ref.read(unifiedPaymentsPageProvider) != 1) {
                  ref.read(unifiedPaymentsPageProvider.notifier).state = 1;
                }
              },
            ),
        ],
      ),
    );
  }
}
