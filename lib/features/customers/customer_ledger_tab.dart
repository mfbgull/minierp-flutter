// Ledger tab — web `LedgerTab` parity (customer-module-spec.md §6.6):
// the AR ledger grouped by invoice (expandable group headers with
// "N payments — Balance", child payment/cancellation rows, ungrouped
// entries), a totals footer (Total Debit / Total Credit / Current
// Balance, excluding returned-invoice entries) and an export toolbar —
// CSV / PDF / Image / Print (web ledgerExport.ts equivalents).

import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart' show saveCsv;
import '../../core/utils/formatters.dart';
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/client_paged_grid.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/filtered_empty_state.dart';
import 'calculations/customer_calculations.dart'
    show calculateLedgerTotals;
import '../../core/utils/ledger_export.dart'
    show buildLedgerCsv, buildLedgerPdf;
import 'calculations/ledger_grouping.dart'
    show
        InvoiceGroup,
        InvoiceGroupNode,
        UngroupedNode,
        groupLedgerByInvoice;
import 'customer_providers.dart';

/// One grid row model: either a group header or a ledger entry.
class _LedgerGridRow {
  _LedgerGridRow.entry(this.entry, {this.isChild = false})
    : isGroup = false,
      group = null,
      groupKey = null,
      groupTitle = null;

  /// True when the entry is a payment/cancellation grouped under an
  /// expanded invoice header (web `_isChild` — indented "—" marker).
  final bool isChild;

  _LedgerGridRow.group(this.group, this.groupKey, this.groupTitle)
    : entry = null,
      isGroup = true,
      isChild = false;

  final LedgerEntry? entry;
  final InvoiceGroup? group;
  final bool isGroup;

  /// The group's invoice reference (toggle key); null for entry rows.
  final String? groupKey;

  /// The group header's display title.
  final String? groupTitle;
}

class CustomerLedgerTab extends ConsumerStatefulWidget {
  const CustomerLedgerTab({
    super.key,
    required this.customerId,
    required this.sessionId,
  });

  final int customerId;

  /// The detail-page instance's range-session id — this tab derives its
  /// fetch args from the header pill's pair (spec §3.1/§9).
  final int sessionId;

  @override
  ConsumerState<CustomerLedgerTab> createState() => _CustomerLedgerTabState();
}

class _CustomerLedgerTabState extends ConsumerState<CustomerLedgerTab> {
  final GlobalKey _captureKey = GlobalKey();
  final Set<String> _expanded = <String>{};

  late List<PlutoColumn> _gridColumns;
  bool _columnsReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsReady) {
      _gridColumns = _columns(context, AppLocalizations.of(context)!);
      _columnsReady = true;
    }
  }

  /// Grid rows are cached (see [_buildBody]) so the DetailTabGrid doesn't
  /// clear+reappend on every parent rebuild — only when the ledger or the
  /// expanded set actually changed.
  List<_LedgerGridRow>? _rows;
  List<LedgerEntry>? _lastLedger;
  Object? _cacheKey;
  int _expandedVersion = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The page's unified range — part of the fetch identity (§9); null =
    // All dates = the full-history ledger.
    final range = customerDetailRangeIso(ref, widget.sessionId);
    final args = CustomerLedgerArgs(
      customerId: widget.customerId,
      fromDate: range.from,
      toDate: range.to,
    );
    final ledger = ref.watch(customerLedgerRangedProvider(args));

    return switch (ledger) {
      AsyncData(:final value) => value.isEmpty
          ? (range.from != null
                ? const FilteredEmptyState()
                : Center(
                    child: Text(
                      l10n.customersLedgerNoentries,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ))
          : _buildBody(context, l10n, value),
      AsyncError(:final error) => DetailError(
        message: error is ApiError ? error.message : '$error',
        onRetry: () =>
            ref.invalidate(customerLedgerRangedProvider(args)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    List<LedgerEntry> ledger,
  ) {
    final scheme = Theme.of(context).colorScheme;

    // Rebuild grid rows only when the ledger identity or the expanded set
    // changed; the parent's DetailTabGrid identity-compares this list, so
    // a fresh instance on every rebuild would reset the grid's scroll.
    final ledgerChanged = !identical(ledger, _lastLedger);
    final cacheKey = Object.hash(ledgerChanged, _expandedVersion);
    if (ledgerChanged || cacheKey != _cacheKey) {
      _cacheKey = cacheKey;
      _lastLedger = ledger;
      _rows = _buildRows(l10n, ledger, _expanded);
    }

    // Totals exclude RETURN/REFUND entries and entries of fully returned
    // invoices (ported calculateLedgerTotals).
    final returnedNos = (ref
            .watch(customerInvoicesProvider(widget.customerId))
            .valueOrNull ??
        const <Invoice>[])
        .where((inv) => inv.status == 'Returned')
        .map((inv) => inv.invoiceNo)
        .toSet();
    final totals = calculateLedgerTotals(
      ledger,
      returnedInvoiceNos: returnedNos,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Export toolbar (web ledger-export buttons).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(
                l10n.customersLedger,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              _ExportButton(
                icon: Icons.file_download_outlined,
                label: 'CSV',
                tooltip: l10n.customersExportcsv,
                onPressed: () => _exportCsv(ledger),
              ),
              _ExportButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'PDF',
                tooltip: l10n.customersExportpdf,
                onPressed: () => _exportPdf(ledger),
              ),
              _ExportButton(
                icon: Icons.image_outlined,
                label: l10n.customersExportimage,
                tooltip: l10n.customersExportimage,
                onPressed: _exportImage,
              ),
              _ExportButton(
                icon: Icons.print_outlined,
                label: l10n.commonPrint,
                tooltip: l10n.commonPrint,
                onPressed: () => _printLedger(ledger),
              ),
            ],
          ),
        ),
        // Grouped grid — wrapped in a RepaintBoundary so the Image export
        // can capture exactly the visible table. Client-side paging keeps
        // the expandable group structure intact (a page boundary can fall
        // between a header and its child rows — the header stays on the
        // page with whatever children fit).
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: RepaintBoundary(
              key: _captureKey,
              child: ClientPagedGrid<_LedgerGridRow>(
                data: _rows!,
                columns: _gridColumns,
                gridRowFor: _gridRowFor,
                itemLabel: l10n.commonEntries,
                rowColorCallback: _rowColorCallback,
                widthKey: 'customer_ledger',
              ),
            ),
          ),
        ),
        // Totals footer.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
            color: scheme.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Text(l10n.customersLedgerTotaldebit, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                Formatters.currency(totals.debit),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 24),
              Text(l10n.customersLedgerTotalcredit, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                Formatters.currency(totals.credit),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(l10n.customersBalance, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                Formatters.currency(totals.balance),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: totals.balance > 0 ? scheme.error : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  List<_LedgerGridRow> _buildRows(
    AppLocalizations l10n,
    List<LedgerEntry> ledger,
    Set<String> expanded,
  ) {
    final rows = <_LedgerGridRow>[];
    for (final node in groupLedgerByInvoice(ledger)) {
      switch (node) {
        case InvoiceGroupNode(:final group):
          // Web parity: the header row carries the invoice's own date /
          // type / reference / debit columns plus the summed credit and
          // remaining balance; the description just summarizes the
          // children ("N payments · Balance: X").
          final title =
              '${group.children.length} ${l10n.customersLedgerPayments} · '
              '${l10n.customersBalance}: '
              '${Formatters.currency(group.balance)}';
          rows.add(
            _LedgerGridRow.group(
              group,
              group.invoice.referenceNo,
              title,
            ),
          );
          if (expanded.contains(group.invoice.referenceNo)) {
            rows.addAll([
              for (final c in group.children)
                _LedgerGridRow.entry(c, isChild: true),
            ]);
          }
        case UngroupedNode(:final entry):
          rows.add(_LedgerGridRow.entry(entry.entry));
      }
    }
    return rows;
  }

  Color _rowColorCallback(PlutoRowColorContext rowColorContext) {
    final row = rowColorContext.row;
    if (row.cells['isGroup']?.value == true) {
      return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
    return Colors.transparent;
  }

  List<PlutoColumn> _columns(BuildContext context, AppLocalizations l10n) {
    PlutoColumn textCol(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          width: width,
          readOnly: true,
          enableContextMenu: false,
        );

    return [
      textCol('date', l10n.commonDate, 110),
      textCol('type', l10n.customersLedgerType, 120),
      textCol('reference', l10n.fieldsReference, 130),
      PlutoColumn(
        title: l10n.commonDescription,
        field: 'description',
        type: PlutoColumnType.text(),
        width: 260,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final row = ctx.cell.row;
          if (row.cells['isGroup']?.value == true) {
            final key = '${row.cells['groupKey']?.value ?? ''}';
            final title = '${row.cells['groupTitle']?.value ?? ''}';
            final expanded = _expanded.contains(key);
            return Builder(
              builder: (cellContext) => Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _toggleGroup(key),
                child: Row(
                  children: [
                    Icon(
                      expanded
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 18,
                      color: Theme.of(cellContext).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(cellContext).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          // Web parity: grouped child rows are indented with a "—"
          // marker so payments/cancellations under an expanded invoice
          // header read as belonging to that group (web `_isChild`).
          if (row.cells['isChild']?.value == true) {
            return Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Row(
                children: [
                  Text(
                    '—',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${ctx.cell.value}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }
          return Text('${ctx.cell.value}');
        },
      ),
      PlutoColumn(
        title: l10n.customersLedgerDebit,
        field: 'debit',
        type: PlutoColumnType.text(),
        width: 120,
        readOnly: true,
        enableContextMenu: false,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        renderer: (ctx) {
          final value = '${ctx.cell.value}';
          if (value.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: ctx.cell.row.cells['isGroup']?.value == true
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
            ),
          );
        },
      ),
      PlutoColumn(
        title: l10n.customersLedgerCredit,
        field: 'credit',
        type: PlutoColumnType.text(),
        width: 120,
        readOnly: true,
        enableContextMenu: false,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        renderer: (ctx) {
          final value = '${ctx.cell.value}';
          if (value.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: ctx.cell.row.cells['isGroup']?.value == true
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
            ),
          );
        },
      ),
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
          final value = '${ctx.cell.value}';
          if (value.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: ctx.cell.row.cells['isGroup']?.value == true
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
            ),
          );
        },
      ),
    ];
  }

  PlutoRow _gridRowFor(_LedgerGridRow row) {
    if (row.isGroup) {
      final group = row.group!;
      return PlutoRow(
        cells: {
          'isGroup': PlutoCell(value: true),
          'groupKey': PlutoCell(value: row.groupKey ?? ''),
          'groupTitle': PlutoCell(value: row.groupTitle ?? ''),
          'date': PlutoCell(
            value: group.invoice.transactionDate.isEmpty
                ? ''
                : Formatters.date(group.invoice.transactionDate),
          ),
          'type': PlutoCell(value: group.invoice.transactionType),
          'reference': PlutoCell(value: group.invoice.referenceNo),
          'description': PlutoCell(value: row.groupTitle ?? ''),
          'debit': PlutoCell(
            value: group.invoice.debit > 0
                ? Formatters.currency(group.invoice.debit)
                : '',
          ),
          'credit': PlutoCell(
            value: group.totalPaid > 0
                ? Formatters.currency(group.totalPaid)
                : '',
          ),
          'balance': PlutoCell(value: Formatters.currency(group.balance)),
        },
      );
    }
    final entry = row.entry!;
    return PlutoRow(
      cells: {
        'isGroup': PlutoCell(value: false),
        'isChild': PlutoCell(value: row.isChild),
        'groupKey': PlutoCell(value: ''),
        'groupTitle': PlutoCell(value: ''),
        'date': PlutoCell(
          value: entry.transactionDate.isEmpty
              ? ''
              : Formatters.date(entry.transactionDate),
        ),
        'type': PlutoCell(value: entry.transactionType),
        'reference': PlutoCell(value: entry.referenceNo),
        'description': PlutoCell(value: entry.description),
        'debit': PlutoCell(
          value: entry.debit > 0 ? Formatters.currency(entry.debit) : '',
        ),
        'credit': PlutoCell(
          value: entry.credit > 0 ? Formatters.currency(entry.credit) : '',
        ),
        'balance': PlutoCell(value: Formatters.currency(entry.balance)),
      },
    );
  }

  void _toggleGroup(String referenceNo) {
    setState(() {
      if (!_expanded.remove(referenceNo)) {
        _expanded.add(referenceNo);
      }
      _expandedVersion++;
    });
  }

  // ── Exports ────────────────────────────────────────────────────────

  String get _nameStem {
    final customer = ref
        .read(customerDetailProvider(widget.customerId))
        .valueOrNull;
    return (customer?.customerName ?? 'customer').replaceAll(RegExp(r'\s+'), '_');
  }

  Future<void> _exportCsv(List<LedgerEntry> ledger) async {
    final l10n = AppLocalizations.of(context)!;
    final csv = buildLedgerCsv(l10n, ledger, entityName: _nameStem);
    await saveCsv(
      context,
      suggestedName:
          'ledger_$_nameStem-${DateTime.now().toIso8601String().split('T').first}.csv',
      csv: csv,
      successMessage: l10n.customersExportsuccess,
      errorMessage: l10n.errorsFailed,
    );
  }

  Future<void> _exportPdf(List<LedgerEntry> ledger) async {
    final l10n = AppLocalizations.of(context)!;
    final bytes = await buildLedgerPdf(l10n, ledger, entityName: _nameStem);
    final name =
        'ledger_$_nameStem-${DateTime.now().toIso8601String().split('T').first}.pdf';
    final path = await FilePicker.saveFile(
      dialogTitle: name,
      fileName: name,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: bytes,
    );
    if (path == null) return;
    if (mounted) showAppToast(context, l10n.customersExportsuccess);
  }

  /// Captures the visible ledger table as a PNG (web html2canvas parity).
  /// Long ledgers export the on-screen viewport — the CSV/PDF/Print
  /// exports cover the full set.
  Future<void> _exportImage() async {
    final l10n = AppLocalizations.of(context)!;
    final boundary = _captureKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    try {
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return;
      final name =
          'ledger-${DateTime.now().toIso8601String().split('T').first}.png';
      final path = await FilePicker.saveFile(
        dialogTitle: name,
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['png'],
        bytes: byteData.buffer.asUint8List(),
      );
      if (path == null) return;
      if (mounted) showAppToast(context, l10n.customersExportsuccess);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    }
  }

  Future<void> _printLedger(List<LedgerEntry> ledger) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final bytes = await buildLedgerPdf(l10n, ledger, entityName: _nameStem);
      if (!mounted) return;
      await printPdfBytes(bytes, 'ledger.pdf', context);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    }
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      ),
    );
  }
}
