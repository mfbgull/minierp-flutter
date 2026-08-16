// Quotations list screen — a read-only grid over `GET /quotations`
// (**bare array**; no search/page params, so sorting and filtering stay
// client-side like the items screen). Rendered with PlutoGrid via the
// shared [PlutoGridScreen] mixin: F2/Enter + double-tap open the
// quotation detail, and the keyboard-hint status bar sits beneath the
// grid. Sits in the `/sales` branch's Quotations tab (the web app hosts
// the list at `/quotations` inside the sales module).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../core/utils/quotation_status.dart';
import '../../data/models/quotation.dart' show Quotation;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'quotation_detail_dialog.dart';
import 'quotation_form_dialog.dart';
import 'quotation_providers.dart';

class QuotationsScreen extends ConsumerStatefulWidget {
  const QuotationsScreen({super.key});

  @override
  ConsumerState<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends ConsumerState<QuotationsScreen>
    with PlutoGridScreen<Quotation, QuotationsScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void openRowDetail(int quotationId) {
    if (!mounted) return;
    showQuotationDetailDialog(context, quotationId: quotationId);
  }

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
      ref.read(quotationsSearchProvider.notifier).state = value.trim();
    });
  }

  bool get _hasActiveFilters =>
      ref.read(quotationsStatusProvider) != null ||
      ref.read(quotationsFromDateProvider) != null ||
      ref.read(quotationsToDateProvider) != null ||
      ref.read(quotationsSearchProvider).isNotEmpty;

  void _clearFilters() {
    _searchController.clear();
    ref.read(quotationsStatusProvider.notifier).state = null;
    ref.read(quotationsFromDateProvider.notifier).state = null;
    ref.read(quotationsToDateProvider.notifier).state = null;
    ref.read(quotationsSearchProvider.notifier).state = '';
  }

  /// Client-side filtering (search term + status + date range) over the
  /// loaded rows — the endpoint only serves the full list, so every
  /// filter runs here.
  List<Quotation> _filteredRows(List<Quotation> quotations) {
    final search = ref.read(quotationsSearchProvider).toLowerCase();
    final status = ref.read(quotationsStatusProvider);
    final from = ref.read(quotationsFromDateProvider);
    final to = ref.read(quotationsToDateProvider);
    if (search.isEmpty && status == null && from == null && to == null) {
      return quotations;
    }
    return quotations.where((q) {
      if (search.isNotEmpty &&
          !q.quotationNo.toLowerCase().contains(search) &&
          !q.customerName.toLowerCase().contains(search)) {
        return false;
      }
      if (status != null && q.status != status) return false;
      final iso = q.quotationDate;
      if (from != null && iso.compareTo(isoDate(from)) < 0) return false;
      if (to != null && iso.compareTo(isoDate(to)) > 0) return false;
      return true;
    }).toList();
  }

  /// Provider → grid sync that honours the active client-side filters
  /// (overrides the mixin's unfiltered clear+append).
  @override
  void syncGridRows(AsyncValue<Object?> value) {
    final manager = gridStateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final rows = _filteredRows(value.value as List<Quotation>);
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in rows.indexed)
          withSerialCell(gridRowFor(row), index),
      ]);
    }
  }

  void _refilter() => syncGridRows(ref.read(quotationsProvider));

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
        onTap: () => showQuotationDetailDialog(context, quotationId: id),
      ),
    ];
  }

  @override
  PlutoRow gridRowFor(Quotation quotation) => PlutoRow(
    cells: {
      'id': PlutoCell(value: quotation.id),
      'quotationNo': PlutoCell(value: quotation.quotationNo),
      'date': PlutoCell(value: quotation.quotationDate),
      'customer': PlutoCell(value: quotation.customerName),
      'status': PlutoCell(value: quotation.status),
      'total': PlutoCell(value: quotation.totalAmount),
      'expiry': PlutoCell(value: quotation.expiryDate ?? ''),
    },
  );

  @override
  Widget build(BuildContext context) {
    final quotations = ref.watch(quotationsProvider);
    final l10n = AppLocalizations.of(context)!;

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the overridden syncGridRows, so
    // filtering applies on every load/refresh too.
    watchGridProvider(quotationsProvider);
    // Client-side filters re-run the filter over the loaded rows without
    // refetching.
    ref.listen(quotationsSearchProvider, (previous, next) => _refilter());
    ref.listen(quotationsStatusProvider, (previous, next) => _refilter());
    ref.listen(quotationsFromDateProvider, (previous, next) => _refilter());
    ref.listen(quotationsToDateProvider, (previous, next) => _refilter());

    // The client-side filters drive the search-clear button and the
    // dropdown, so they must be watched here for the build to re-run.
    ref.watch(quotationsSearchProvider);
    ref.watch(quotationsStatusProvider);
    ref.watch(quotationsFromDateProvider);
    ref.watch(quotationsToDateProvider);

    final filteredRows = _filteredRows(quotations.valueOrNull ?? const []);
    // Status filter options — `(label, server value)` pairs with `All` =
    // null (localized, so built per build).
    final statusOptions = <(String, String?)>[
      (l10n.commonAll, null),
      (l10n.quotationsDraft, 'Draft'),
      (l10n.quotationsSent, 'Sent'),
      (l10n.quotationsAccepted, 'Accepted'),
      (l10n.quotationsExpired, 'Expired'),
      (l10n.quotationsConverted, 'Converted'),
      (l10n.quotationsRejected, 'Rejected'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: search + status filter + date range + actions — the
        // same header the invoices tab has.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.quotationsSearchplaceholder,
          onSearchChanged: _onSearchChanged,
          filters: [
            ScreenToolbarDropdown<String?>(
              items: [for (final (_, value) in statusOptions) value],
              value: ref.watch(quotationsStatusProvider),
              hint: statusOptions.first.$1,
              labelBuilder: (value) {
                for (final (label, option) in statusOptions) {
                  if (option == value) return label;
                }
                return value ?? '';
              },
              width: 170,
              onChanged: (v) =>
                  ref.read(quotationsStatusProvider.notifier).state = v,
            ),
            DateRangeFilter(
              width: 120,
              fromProvider: quotationsFromDateProvider,
              toProvider: quotationsToDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(quotationsProvider),
          onClearAll: _clearFilters,
          hasActiveFilters: _hasActiveFilters,
          actions: [
            // CSV export — runs over the currently-filtered rows; the
            // shared save helper owns the FilePicker + toast. Disabled
            // until rows are loaded.
            TextButton.icon(
              onPressed: quotations.isLoading || filteredRows.isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('quotations'),
                      csv: buildQuotationsCsv(
                        l10n,
                        _filteredRows(quotations.valueOrNull ?? const []),
                      ),
                      successMessage: l10n.quotationsExported,
                      errorMessage: l10n.quotationsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.quotationsExportcsv),
            ),
          ],
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showQuotationFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.quotationsNewquotation),
            ),
          ],
        ),
        Expanded(
          child: gridScreenBody(quotations, provider: quotationsProvider),
        ),
      ],
    );
  }

  /// Column set — order/format mirrors the web QuotationsPage grid
  /// (Quotation #, Date, Customer, Status, Total, Expiry); read-only for
  /// now.
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
      textColumn('quotationNo', l10n.quotationsQuotation, 120),
      PlutoColumn(
        title: l10n.quotationsDate,
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
      textColumn('customer', l10n.quotationsCustomer, 220),
      PlutoColumn(
        title: l10n.quotationsStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final status = ctx.cell.value as String? ?? '';
            final (color, darkColor) = quotationStatusColors(status);
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: quotationStatusLabel(
                  AppLocalizations.of(cellContext)!,
                  status,
                ),
                color: color,
                darkColor: darkColor,
              ),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.commonTotal,
        field: 'total',
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
      PlutoColumn(
        title: l10n.quotationsExpiry,
        field: 'expiry',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final value = ctx.cell.value as String? ?? '';
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value.isEmpty ? '—' : Formatters.date(value),
                style: Theme.of(cellContext).textTheme.bodyMedium,
              ),
            );
          },
        ),
      ),
    ];
  }
}
