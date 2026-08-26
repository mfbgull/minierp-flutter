// Invoices tab — web `InvoicesTab` parity (customer-module-spec.md §6.5):
// the customer's invoices grid (Invoice No | Date | Due Date | Total |
// Paid | Balance | Status) with a per-row ⋮ menu — View (opens the
// invoice print-preview page), Delete (only when
// `canShowDeleteAction`), Cancel (only when `canCancelInvoice`), guarded
// by the shared `invoice_rules.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/invoice_status.dart' show invoiceStatusColor, invoiceStatusLabel;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/status_badge.dart';
import '../sales/calculations/invoice_rules.dart'
    show canCancelInvoice, canShowDeleteAction;
import '../sales/invoice_providers.dart' show invoicesProvider;
import '../../widgets/detail_tab_grid.dart';
import 'customer_providers.dart';

enum _InvoiceRowAction { view, delete, cancel }

class CustomerInvoicesTab extends ConsumerStatefulWidget {
  const CustomerInvoicesTab({super.key, required this.customerId});

  final int customerId;

  @override
  ConsumerState<CustomerInvoicesTab> createState() =>
      _CustomerInvoicesTabState();
}

class _CustomerInvoicesTabState extends ConsumerState<CustomerInvoicesTab> {
  /// Current page / per-page size for the server-side pagination (same
  /// pattern as the sales screen; the paged provider key carries both).
  int _page = 1;
  int _limit = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final invoices = ref.watch(
      customerInvoicesPagedProvider(
        CustomerInvoicesArgs(
          customerId: widget.customerId,
          page: _page,
          limit: _limit,
        ),
      ),
    );

    // After a delete/cancel the current page can fall past the last
    // page — clamp back so the tab doesn't strand the user on an empty
    // page (the provider then refetches the corrected page).
    ref.listen(
      customerInvoicesPagedProvider(
        CustomerInvoicesArgs(
          customerId: widget.customerId,
          page: _page,
          limit: _limit,
        ),
      ),
      (previous, next) {
        final value = next.valueOrNull;
        if (value == null || value.items.isNotEmpty) return;
        if (value.totalPages > 0 && _page > value.totalPages) {
          setState(() => _page = value.totalPages);
        }
      },
    );

    return switch (invoices) {
      AsyncData(:final value) => value.items.isEmpty
          ? _empty(context, l10n.customersNoinvoices)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: DetailTabGrid<Invoice>(
                    data: value.items,
                    buildColumns: (l10n) => _columns(context, l10n),
                    gridRowFor: _gridRowFor,
                    hiddenFields: const ['data'],
                    widthKey: 'customer_invoices',
                  ),
                ),
                ServerPaginationBar(
                  page: value.currentPage,
                  totalPages: value.totalPages,
                  totalItems: value.totalItems,
                  hasNext: value.hasNext,
                  hasPrev: value.hasPrev,
                  limit: _limit,
                  itemLabel: l10n.salesInvoices,
                  onPageChanged: (p) => setState(() => _page = p),
                  onLimitChanged: (limit) => setState(() {
                    _limit = limit;
                    _page = 1;
                  }),
                ),
                const SizedBox(height: 12),
              ],
            ),
      AsyncError(:final error) => DetailError(
        message: error is ApiError ? error.message : '$error',
        onRetry: () => ref.invalidate(
          customerInvoicesPagedProvider(
            CustomerInvoicesArgs(
              customerId: widget.customerId,
              page: _page,
              limit: _limit,
            ),
          ),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _empty(BuildContext context, String message) => Center(
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  List<PlutoColumn> _columns(BuildContext context, AppLocalizations l10n) {
    PlutoColumn textCol(
      String field,
      String title,
      double width, {
      PlutoColumnTextAlign align = PlutoColumnTextAlign.start,
    }) => PlutoColumn(
      title: title,
      field: field,
      type: PlutoColumnType.text(),
      width: width,
      readOnly: true,
      enableContextMenu: false,
      textAlign: align,
      titleTextAlign: align,
    );

    return [
      // Hidden cell carrying the row's Invoice for the actions menu.
      PlutoColumn(
        title: '',
        field: 'data',
        type: PlutoColumnType.text(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      PlutoColumn(
        title: l10n.customersInvoiceno,
        field: 'invoiceNo',
        type: PlutoColumnType.text(),
        width: 130,
        readOnly: true,
        enableContextMenu: false,
        // Link-style like the web's invoice-link column.
        renderer: (ctx) => Builder(
          builder: (cellContext) => GestureDetector(
            onTap: () => _viewInvoice(
              ctx.cell.row.cells['data']?.value as Invoice?,
            ),
            child: Text(
              '${ctx.cell.value}',
              style: TextStyle(
                color: Theme.of(cellContext).colorScheme.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: Theme.of(cellContext).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
      textCol('date', l10n.commonDate, 110),
      textCol('dueDate', l10n.customersDuedate, 110),
      textCol('total', l10n.salesTotalsales, 120, align: PlutoColumnTextAlign.end),
      textCol('paid', l10n.salesTotalpaid, 120, align: PlutoColumnTextAlign.end),
      PlutoColumn(
        title: l10n.customersBalance,
        field: 'balance',
        type: PlutoColumnType.text(),
        width: 120,
        readOnly: true,
        enableContextMenu: false,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        renderer: (ctx) {
          final balance = (ctx.cell.value as num?) ?? 0;
          return Builder(
            builder: (cellContext) {
              final isDark =
                  Theme.of(cellContext).brightness == Brightness.dark;
              final color = balance > 0
                  ? (isDark
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFFD97706))
                  : (isDark
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFF15803D));
              return Align(
                alignment: Alignment.centerRight,
                child: Text(
                  Formatters.currency(balance),
                  style: TextStyle(color: color),
                ),
              );
            },
          );
        },
      ),
      PlutoColumn(
        title: l10n.commonStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 130,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final status = '${ctx.cell.value}';
          return Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: invoiceStatusLabel(l10n, status),
              color: invoiceStatusColor(Theme.of(context).colorScheme, status),
            ),
          );
        },
      ),
      // ⋮ actions menu (Listener + showMenu — see customers_screen).
      PlutoColumn(
        title: l10n.customersActions,
        field: 'actions',
        // Pinned to the right edge — stays reachable when the grid scrolls.
        frozen: PlutoColumnFrozen.end,
        type: PlutoColumnType.text(),
        width: 64,
        readOnly: true,
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
        renderer: (ctx) {
          final invoice = ctx.cell.row.cells['data']?.value as Invoice?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _openRowMenu(cellContext, invoice),
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

  PlutoRow _gridRowFor(Invoice invoice) => PlutoRow(
    cells: {
      'data': PlutoCell(value: invoice),
      'invoiceNo': PlutoCell(value: invoice.invoiceNo),
      'date': PlutoCell(
        value: invoice.invoiceDate.isEmpty ? '' : Formatters.date(invoice.invoiceDate),
      ),
      'dueDate': PlutoCell(
        value: (invoice.dueDate?.isEmpty ?? true)
            ? ''
            : Formatters.date(invoice.dueDate!),
      ),
      'total': PlutoCell(value: Formatters.currency(invoice.totalAmount)),
      'paid': PlutoCell(value: Formatters.currency(invoice.paidAmount)),
      'balance': PlutoCell(value: invoice.balanceAmount),
      'status': PlutoCell(value: invoice.status),
      'actions': PlutoCell(value: ''),
    },
  );

  void _viewInvoice(Invoice? invoice) {
    if (invoice == null || !mounted) return;
    // Web parity: the row's view action opens the A4 print preview (the
    // Flutter equivalent of the web's read-only invoice view).
    context.push('/sales/print-preview', extra: invoice);
  }

  Future<void> _openRowMenu(
    BuildContext cellContext,
    Invoice? invoice,
  ) async {
    if (invoice == null || !mounted) return;
    final l10n = AppLocalizations.of(cellContext)!;
    final box = cellContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(cellContext, rootOverlay: true);

    final action = await showMenu<_InvoiceRowAction>(
      context: cellContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        ),
        Offset.zero & overlay.context.size!,
      ),
      items: [
        PopupMenuItem(
          value: _InvoiceRowAction.view,
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.commonView),
            ],
          ),
        ),
        if (canShowDeleteAction(invoice))
          PopupMenuItem(
            value: _InvoiceRowAction.delete,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Theme.of(cellContext).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.customersDeleteinvoice,
                  style: TextStyle(
                    color: Theme.of(cellContext).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        if (canCancelInvoice(invoice))
          PopupMenuItem(
            value: _InvoiceRowAction.cancel,
            child: Row(
              children: [
                const Icon(Icons.cancel_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l10n.customersCancelinvoice),
              ],
            ),
          ),
      ],
    );
    if (action != null && mounted) {
      switch (action) {
        case _InvoiceRowAction.view:
          _viewInvoice(invoice);
        case _InvoiceRowAction.delete:
          _deleteInvoice(invoice);
        case _InvoiceRowAction.cancel:
          _cancelInvoice(invoice);
      }
    }
  }

  Future<void> _deleteInvoice(Invoice invoice) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.customersDeleteinvoice,
      message: '${l10n.customersConfirmdeleteinvoice} "${invoice.invoiceNo}"?',
      confirmLabel: l10n.customersDeleteinvoice,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await ref.read(invoiceRepositoryProvider).delete(invoice.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.customersInvoicedeleted);
        ref.invalidate(invoicesProvider);
        invalidateCustomerQueries(ref, widget.customerId);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<void> _cancelInvoice(Invoice invoice) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.customersCancelinvoice,
      message: l10n.customersCancelinvoiceconfirm,
      confirmLabel: l10n.customersCancelinvoice,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await ref.read(invoiceRepositoryProvider).cancel(invoice.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.customersInvoicecancelled);
        ref.invalidate(invoicesProvider);
        invalidateCustomerQueries(ref, widget.customerId);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }
}
