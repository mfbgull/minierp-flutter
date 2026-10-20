import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/supplier_bill.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/supplier_accounting_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_tab_grid.dart';
import '../../widgets/pagination_bar.dart';
import 'supplier_bill_dialog.dart';
import 'supplier_providers.dart';
import '../payments/payments_providers.dart' show invalidateCashMovementProviders;

enum _BillAction { pay, voidBill }

class SupplierBillsTab extends ConsumerStatefulWidget {
  const SupplierBillsTab({super.key, required this.supplierId});
  final int supplierId;

  @override
  ConsumerState<SupplierBillsTab> createState() => _SupplierBillsTabState();
}

class _SupplierBillsTabState extends ConsumerState<SupplierBillsTab> {
  int _page = 1;
  int _limit = 25;
  bool _busy = false;

  Future<void> _action(_BillAction action, SupplierBill bill) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    if (action == _BillAction.pay) {
      await showDialog<void>(
        context: context,
        builder: (_) => SupplierBillDialog.payment(bill: bill),
      );
      return;
    }
    if (!await showConfirmDialog(
      context,
      title: l10n.supplierBillVoid,
      message: l10n.supplierBillVoidConfirm,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final result = await ref
        .read(supplierAccountingRepositoryProvider)
        .voidBill(bill.id, 'Supplier bill correction');
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case ApiSuccess():
        invalidateCashMovementProviders(ref, 'payment');
        invalidateSupplierQueries(ref, widget.supplierId);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  List<PlutoColumn> _columns(AppLocalizations l10n) => [
    PlutoColumn(
      title: l10n.supplierBillNumber,
      field: 'number',
      type: PlutoColumnType.text(),
      width: 170,
    ),
    PlutoColumn(
      title: l10n.fieldsDate,
      field: 'date',
      type: PlutoColumnType.text(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.supplierBillNetAmount,
      field: 'net',
      type: PlutoColumnType.number(),
      width: 150,
    ),
    PlutoColumn(
      title: l10n.supplierBillInputTax,
      field: 'tax',
      type: PlutoColumnType.number(),
      width: 150,
    ),
    PlutoColumn(
      title: l10n.expenseOutstanding,
      field: 'balance',
      type: PlutoColumnType.number(),
      width: 130,
    ),
    PlutoColumn(
      title: l10n.commonStatus,
      field: 'status',
      type: PlutoColumnType.text(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.commonActions,
      field: 'actions',
      type: PlutoColumnType.text(),
      width: 90,
      renderer: (cell) {
        final bill = cell.row.cells['data']!.value as SupplierBill;
        final user = ref.read(authProvider).user;
        return PopupMenuButton<_BillAction>(
          tooltip: l10n.commonActions,
          enabled: !_busy && bill.voidedAt == null,
          onSelected: (action) => _action(action, bill),
          itemBuilder: (_) => [
            if (bill.balanceAmount > 0 &&
                (user?.hasPermission('payments', 'create') ?? false))
              PopupMenuItem(
                value: _BillAction.pay,
                child: Text(l10n.expenseRecordPayment),
              ),
            if (user?.hasPermission('purchases', 'delete') ?? false)
              PopupMenuItem(
                value: _BillAction.voidBill,
                child: Text(l10n.supplierBillVoid),
              ),
          ],
        );
      },
    ),
    PlutoColumn(
      title: '',
      field: 'data',
      type: PlutoColumnType.text(),
      hide: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider).user;
    final provider = supplierBillsProvider((
      supplierId: widget.supplierId,
      page: _page,
      limit: _limit,
    ));
    final bills = ref.watch(provider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
          if ((user?.hasPermission('purchases', 'create') ?? false) && (user?.hasPermission('expenses', 'approve') ?? false))
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.supplierBillCreate),
                  onPressed: _busy
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) => SupplierBillDialog.create(
                            supplierId: widget.supplierId,
                          ),
                        ),
                ),
              IconButton(
                tooltip: l10n.commonRefresh,
                onPressed: () => ref.invalidate(provider),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: bills.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error is ApiError ? error.message : l10n.errorsFailed),
                  TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: Text(l10n.commonRetry),
                  ),
                ],
              ),
            ),
            data: (value) => Column(
              children: [
                Expanded(
                  child: DetailTabGrid<SupplierBill>(
                    data: value.items,
                    buildColumns: _columns,
                    hiddenFields: const ['data'],
                    widthKey: 'supplier_bills',
                    gridRowFor: (bill) => PlutoRow(
                      cells: {
                        'id': PlutoCell(value: bill.id),
                        'data': PlutoCell(value: bill),
                        'number': PlutoCell(value: bill.billNo),
                        'date': PlutoCell(
                          value: Formatters.date(bill.billDate),
                        ),
                        'net': PlutoCell(value: bill.netAmount),
                        'tax': PlutoCell(value: bill.inputTaxAmount),
                        'balance': PlutoCell(value: bill.balanceAmount),
                        'status': PlutoCell(
                          value: bill.voidedAt != null
                              ? l10n.expensePaymentVoided
                              : bill.balanceAmount == 0
                              ? l10n.supplierBillPaid
                              : l10n.supplierBillOpen,
                        ),
                        'actions': PlutoCell(value: ''),
                      },
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (_, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: constraints.maxWidth < 600
                          ? 600
                          : constraints.maxWidth,
                      child: ServerPaginationBar(
                        page: value.currentPage,
                        totalPages: value.totalPages,
                        totalItems: value.totalItems,
                        hasNext: value.hasNext,
                        hasPrev: value.hasPrev,
                        limit: _limit,
                        itemLabel: l10n.supplierBills,
                        onPageChanged: (page) => setState(() => _page = page),
                        onLimitChanged: (limit) => setState(() {
                          _limit = limit;
                          _page = 1;
                        }),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
