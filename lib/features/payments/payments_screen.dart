// Payments list screen — PORTING.md §5/§6. Server-paginated like
// customers/suppliers: `GET /payments` returns one page plus a
// `pagination` block, so this screen drives page/limit/search/sortBy/
// sortOrder through the provider and renders a [ServerPaginationBar]
// under the grid. Column sort maps to the server's PAYMENT_SORT_COLUMNS
// whitelist.
//
// Built on the shared [PlutoGridScreen] mixin: F2/Enter + double-tap open
// the focused row's detail (payment header + allocations context + Edit/
// Delete), and the keyboard-hint status bar sits beneath the grid. The
// Record Payment action opens the allocation dialog (customer → open
// invoices → per-invoice amounts → POST /payments).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/theme/status_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/payment.dart' show Payment;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'payment_detail_dialog.dart';
import 'payments_providers.dart';
import 'record_payment_dialog.dart';

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen>
    with PlutoGridScreen<Payment, PaymentsScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void openRowDetail(int paymentId) {
    if (!mounted) return;
    showPaymentDetailDialog(context, paymentId: paymentId);
  }

  /// The payments provider returns a `PagedResponse` envelope — unwrap
  /// the current page's items as the grid rows.
  @override
  Iterable<Payment> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Payment>).items;

  /// Opt into the per-row ⋮ actions menu (View detail).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => showPaymentDetailDialog(context, paymentId: id),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(Payment payment) => PlutoRow(
    cells: {
      'id': PlutoCell(value: payment.id),
      'paymentNo': PlutoCell(value: payment.paymentNo),
      // Direction: money in from a customer vs out to a supplier. The
      // server XOR-guarantees exactly one counterparty is set.
      'type': PlutoCell(value: payment.supplierId != null ? 'out' : 'in'),
      'date': PlutoCell(value: payment.paymentDate),
      'amount': PlutoCell(value: payment.amount),
      'method': PlutoCell(value: payment.paymentMethod),
      'reference': PlutoCell(value: payment.referenceNo ?? ''),
      'notes': PlutoCell(value: payment.notes ?? ''),
      'party': PlutoCell(value: payment.customerName ?? payment.supplierName ?? ''),
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
      ref.read(paymentsSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(paymentsPageProvider) != 1) {
        ref.read(paymentsPageProvider.notifier).state = 1;
      }
    });
  }

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'paymentNo' => 'payment_no',
    'date' => 'payment_date',
    'amount' => 'amount',
    'method' => 'payment_method',
    _ => null,
  };

  /// Column sort maps to the server-side sort providers (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(paymentsSortProvider.notifier).state = sort.isNone
        ? null
        : PaymentSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(paymentsPageProvider) != 1) {
      ref.read(paymentsPageProvider.notifier).state = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final payments = ref.watch(paymentsProvider);
    final l10n = AppLocalizations.of(context)!;
    final page = payments.valueOrNull;

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(paymentsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.paymentsSearchplaceholder,
          onSearchChanged: _onSearchChanged,
          onClearSearch: () {
            // Cancel any pending debounce so a stale timer can't
            // resurrect the old term, and reset to page 1 (the
            // server-paginated search re-runs from the first page).
            _debounce?.cancel();
            _searchController.clear();
            ref.read(paymentsSearchProvider.notifier).state = '';
            if (ref.read(paymentsPageProvider) != 1) {
              ref.read(paymentsPageProvider.notifier).state = 1;
            }
          },
          onRefresh: () => ref.invalidate(paymentsProvider),
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showRecordPaymentDialog(context),
              icon: const Icon(Icons.account_balance_wallet, size: 18),
              label: Text(l10n.paymentsRecordpayment),
            ),
          ],
        ),
        Expanded(child: gridScreenBody(payments, provider: paymentsProvider)),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(paymentsLimitProvider),
            itemLabel: l10n.paymentsPayments,
            onPageChanged: (p) =>
                ref.read(paymentsPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(paymentsLimitProvider.notifier).state = limit;
              if (ref.read(paymentsPageProvider) != 1) {
                ref.read(paymentsPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Column set — mirrors the web PaymentsTab columns (Payment No, Date,
  /// Amount, Method, Reference, Notes + the customer for context);
  /// read-only (records are created via the Record Payment dialog).
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
        // Hidden in onLoaded — never reveal it via the column menu.
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('paymentNo', l10n.paymentsPaymentno, 130),
      PlutoColumn(
        title: l10n.fieldsType,
        field: 'type',
        type: PlutoColumnType.text(),
        width: 90,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final isIn = ctx.cell.value?.toString() != 'out';
          return Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: isIn ? l10n.paymentsTypein : l10n.paymentsTypeout,
              color: isIn
                  ? StatusColors.of(context).success
                  : StatusColors.of(context).error,
            ),
          );
        },
      ),
      PlutoColumn(
        title: l10n.fieldsDate,
        field: 'date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
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
      PlutoColumn(
        title: l10n.fieldsAmount,
        field: 'amount',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 110,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.currency(ctx.cell.value as num? ?? 0)),
        ),
      ),
      textColumn('method', l10n.expensesPaymentmethod, 130),
      textColumn('reference', l10n.fieldsReference, 130),
      textColumn('notes', l10n.fieldsNotes, 180),
      textColumn('party', l10n.paymentsParty, 180),
    ];
  }
}
