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

import '../../core/utils/formatters.dart';
import '../../data/models/payment.dart' show Payment;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
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

  @override
  PlutoRow gridRowFor(Payment payment) => PlutoRow(
    cells: {
      'id': PlutoCell(value: payment.id),
      'paymentNo': PlutoCell(value: payment.paymentNo),
      'date': PlutoCell(value: payment.paymentDate),
      'amount': PlutoCell(value: payment.amount),
      'method': PlutoCell(value: payment.paymentMethod),
      'reference': PlutoCell(value: payment.referenceNo ?? ''),
      'notes': PlutoCell(value: payment.notes ?? ''),
      'customer': PlutoCell(value: payment.customerName ?? ''),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) => TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: l10n.paymentsSearchplaceholder,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: value.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  // Cancel any pending debounce so a stale
                                  // timer can't resurrect the old term.
                                  _debounce?.cancel();
                                  _searchController.clear();
                                  ref
                                          .read(paymentsSearchProvider.notifier)
                                          .state =
                                      '';
                                  if (ref.read(paymentsPageProvider) != 1) {
                                    ref
                                            .read(paymentsPageProvider.notifier)
                                            .state =
                                        1;
                                  }
                                },
                              ),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => showRecordPaymentDialog(context),
                icon: const Icon(Icons.account_balance_wallet, size: 18),
                label: Text(l10n.paymentsRecordpayment),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(paymentsProvider),
              ),
            ],
          ),
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
      textColumn('customer', l10n.fieldsCustomer, 180),
    ];
  }
}
