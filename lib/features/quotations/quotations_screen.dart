// Quotations list screen — a read-only grid over `GET /quotations`
// (**bare array**; no search/page params, so sorting and filtering stay
// client-side like the items screen). Rendered with PlutoGrid via the
// shared [PlutoGridScreen] mixin: F2/Enter + double-tap open the
// quotation detail, and the keyboard-hint status bar sits beneath the
// grid. Sits in the `/sales` branch's Quotations tab (the web app hosts
// the list at `/quotations` inside the sales module).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/quotation.dart' show Quotation;
import '../../l10n/app_localizations.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/status_badge.dart';
import 'quotation_detail_dialog.dart';
import 'quotation_form_dialog.dart';
import 'quotation_providers.dart';
import 'quotation_status.dart';

class QuotationsScreen extends ConsumerStatefulWidget {
  const QuotationsScreen({super.key});

  @override
  ConsumerState<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends ConsumerState<QuotationsScreen>
    with PlutoGridScreen<Quotation, QuotationsScreen> {
  @override
  void openRowDetail(int quotationId) {
    if (!mounted) return;
    showQuotationDetailDialog(context, quotationId: quotationId);
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
    watchGridProvider(quotationsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showQuotationFormDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.quotationsNewquotation),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(quotationsProvider),
              ),
            ],
          ),
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
