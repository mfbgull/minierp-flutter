import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/supplier_prepayment.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/supplier_accounting_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_tab_grid.dart';
import '../../widgets/pagination_bar.dart';
import 'supplier_advance_dialog.dart';
import 'supplier_providers.dart';
import '../payments/payments_providers.dart' show invalidateCashMovementProviders;

enum _AdvanceAction { apply, voidAdvance }

class SupplierAdvancesTab extends ConsumerStatefulWidget {
  const SupplierAdvancesTab({super.key, required this.supplierId});
  final int supplierId;
  @override
  ConsumerState<SupplierAdvancesTab> createState() =>
      _SupplierAdvancesTabState();
}

class _SupplierAdvancesTabState extends ConsumerState<SupplierAdvancesTab> {
  int _page = 1;
  int _limit = 25;
  bool _busy = false;

  Future<void> _action(_AdvanceAction action, SupplierPrepayment source) async {
    if (_busy) return;
    if (action == _AdvanceAction.apply) {
      await showDialog<void>(
        context: context,
        builder: (_) => SupplierAdvanceDialog.apply(advance: source),
      );
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    if (!await showConfirmDialog(
      context,
      title: l10n.supplierAdvanceVoid,
      message: l10n.supplierAdvanceVoidConfirm,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final result = await ref
        .read(supplierAccountingRepositoryProvider)
        .voidPrepayment(source.id, 'Supplier advance correction');
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case ApiSuccess():
        invalidateCashMovementProviders(ref, 'supplier_advance');
        invalidateSupplierQueries(ref, widget.supplierId);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  List<PlutoColumn> _columns(AppLocalizations l10n) => [
    PlutoColumn(
      title: l10n.fieldsReference,
      field: 'number',
      type: PlutoColumnType.text(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.fieldsDate,
      field: 'date',
      type: PlutoColumnType.text(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.fieldsAmount,
      field: 'amount',
      type: PlutoColumnType.number(),
      width: 130,
    ),
    PlutoColumn(
      title: l10n.supplierAdvanceApplied,
      field: 'applied',
      type: PlutoColumnType.number(),
      width: 130,
    ),
    PlutoColumn(
      title: l10n.supplierAdvanceAvailable,
      field: 'available',
      type: PlutoColumnType.number(),
      width: 130,
    ),
    PlutoColumn(
      title: l10n.expensesPaymentmethod,
      field: 'method',
      type: PlutoColumnType.text(),
      width: 120,
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
        final source = cell.row.cells['data']!.value as SupplierPrepayment;
        final user = ref.read(authProvider).user;
        return PopupMenuButton<_AdvanceAction>(
          tooltip: l10n.commonActions,
          enabled: !_busy && source.voidedAt == null,
          onSelected: (action) => _action(action, source),
          itemBuilder: (_) => [
            if (source.availableAmount > 0 &&
                (user?.hasPermission('payments', 'create') ?? false))
              PopupMenuItem(
                value: _AdvanceAction.apply,
                child: Text(l10n.supplierAdvanceApply),
              ),
            if (user?.hasPermission('payments', 'delete') ?? false)
              PopupMenuItem(
                value: _AdvanceAction.voidAdvance,
                child: Text(l10n.supplierAdvanceVoid),
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
    final provider = supplierPrepaymentsProvider((
      supplierId: widget.supplierId,
      page: _page,
      limit: _limit,
    ));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              if (user?.hasPermission('payments', 'create') ?? false)
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.supplierAdvanceCreate),
                  onPressed: _busy
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) => SupplierAdvanceDialog.create(
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
          child: ref
              .watch(provider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error is ApiError ? error.message : l10n.errorsFailed,
                      ),
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
                      child: DetailTabGrid<SupplierPrepayment>(
                        data: value.items,
                        buildColumns: _columns,
                        hiddenFields: const ['data'],
                        widthKey: 'supplier_advances',
                        gridRowFor: (source) => PlutoRow(
                          cells: {
                            'id': PlutoCell(value: source.id),
                            'data': PlutoCell(value: source),
                            'number': PlutoCell(value: 'ADV-${source.id}'),
                            'date': PlutoCell(
                              value: Formatters.date(source.prepayDate),
                            ),
                            'amount': PlutoCell(value: source.amount),
                            'applied': PlutoCell(value: source.appliedAmount),
                            'available': PlutoCell(
                              value: source.availableAmount,
                            ),
                            'method': PlutoCell(value: source.paymentMethod),
                            'status': PlutoCell(
                              value: source.voidedAt != null
                                  ? l10n.expensePaymentVoided
                                  : l10n.supplierAdvanceActive,
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
                            itemLabel: l10n.supplierAdvances,
                            onPageChanged: (page) =>
                                setState(() => _page = page),
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
