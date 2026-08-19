// Ledger tab — web supplier `LedgerTab` parity: the supplier's AP ledger
// grid (Date | Type | Reference | Description | Debit | Credit | Balance)
// with an export toolbar (CSV / PDF / Image / Print) and a totals footer.
// Unlike the customer ledger tab there is no invoice grouping — the web
// supplier ledger is a flat grid.

import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart' show saveCsv;
import '../../core/utils/formatters.dart';
import '../../core/utils/ledger_export.dart'
    show LedgerExportLabels, buildLedgerCsv, buildLedgerPdf;
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/client_paged_grid.dart';
import '../../widgets/detail_error.dart';
import 'supplier_providers.dart';

class SupplierLedgerTab extends ConsumerStatefulWidget {
  const SupplierLedgerTab({super.key, required this.supplierId});

  final int supplierId;

  @override
  ConsumerState<SupplierLedgerTab> createState() => _SupplierLedgerTabState();
}

class _SupplierLedgerTabState extends ConsumerState<SupplierLedgerTab> {
  final GlobalKey _captureKey = GlobalKey();

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ledger = ref.watch(supplierLedgerProvider(widget.supplierId));

    return switch (ledger) {
      AsyncData(:final value) => value.isEmpty
          ? Center(
              child: Text(
                l10n.suppliersLedgerNoentries,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : _buildBody(context, l10n, value),
      AsyncError(:final error) => DetailError(
        message: error is ApiError ? error.message : '$error',
        onRetry: () =>
            ref.invalidate(supplierLedgerProvider(widget.supplierId)),
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
    final totals = _totals(ledger);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Export toolbar (web ledger-export buttons).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(
                l10n.suppliersLedger,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              _ExportButton(
                icon: Icons.file_download_outlined,
                label: 'CSV',
                tooltip: l10n.suppliersExportcsv,
                onPressed: () => _exportCsv(ledger),
              ),
              _ExportButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'PDF',
                tooltip: l10n.suppliersExportpdf,
                onPressed: () => _exportPdf(ledger),
              ),
              _ExportButton(
                icon: Icons.image_outlined,
                label: l10n.suppliersExportimage,
                tooltip: l10n.suppliersExportimage,
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
        // Flat grid — wrapped in a RepaintBoundary so the Image export
        // can capture exactly the visible table. Client-side paging
        // (default 10 rows per page, same as every other grid).
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: RepaintBoundary(
              key: _captureKey,
              child: ClientPagedGrid<LedgerEntry>(
                data: ledger,
                columns: _gridColumns,
                gridRowFor: _gridRowFor,
                itemLabel: l10n.commonEntries,
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
              Text(l10n.suppliersLedgerTotaldebit, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                Formatters.currency(totals.debit),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 24),
              Text(l10n.suppliersLedgerTotalcredit, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                Formatters.currency(totals.credit),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(l10n.suppliersBalance, style: const TextStyle(fontSize: 13)),
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

  /// Web supplier LedgerTab totals: summed debit/credit; balance = the
  /// last entry's running balance (the ledger is newest-first, so the
  /// first row's balance is the closing balance in that orientation — the
  /// web takes `ledger[ledger.length - 1].balance`).
  ({num debit, num credit, num balance}) _totals(List<LedgerEntry> ledger) {
    var debit = 0.0;
    var credit = 0.0;
    for (final entry in ledger) {
      debit += entry.debit;
      credit += entry.credit;
    }
    final balance = ledger.isEmpty ? 0 : ledger.last.balance;
    return (debit: debit, credit: credit, balance: balance);
  }

  PlutoRow _gridRowFor(LedgerEntry entry) => PlutoRow(
    cells: {
      'date': PlutoCell(value: Formatters.date(entry.transactionDate)),
      'type': PlutoCell(value: entry.transactionType),
      'reference': PlutoCell(value: entry.referenceNo),
      'description': PlutoCell(value: entry.description),
      // Web parity: debit/credit blank when 0, all amounts currency-
      // formatted (web `valueFormatter: params.value ? formatCurrency
      // : ''` / `formatAsCurrency(value || 0)`).
      'debit': PlutoCell(
        value: entry.debit > 0 ? Formatters.currency(entry.debit) : '',
      ),
      'credit': PlutoCell(
        value: entry.credit > 0 ? Formatters.currency(entry.credit) : '',
      ),
      'balance': PlutoCell(value: Formatters.currency(entry.balance)),
    },
  );

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
      PlutoColumn(
        title: l10n.suppliersLedgerType,
        field: 'type',
        type: PlutoColumnType.text(),
        width: 120,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final type = '${ctx.cell.value}';
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              type,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        },
      ),
      textCol('reference', l10n.fieldsReference, 130),
      textCol('description', l10n.commonDescription, 240),
      _amountCol('debit', l10n.suppliersLedgerDebit),
      _amountCol('credit', l10n.suppliersLedgerCredit),
      _amountCol('balance', l10n.suppliersBalance),
    ];
  }

  /// Right-aligned amount column that hides empty cells (zero
  /// debit/credit) — web `valueFormatter` parity.
  PlutoColumn _amountCol(String field, String title) => PlutoColumn(
    title: title,
    field: field,
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
        child: Text(value),
      );
    },
  );

  // ── Exports ────────────────────────────────────────────────────────

  String get _nameStem {
    final supplier = ref
        .read(supplierDetailProvider(widget.supplierId))
        .valueOrNull;
    return (supplier?.supplierName ?? 'supplier').replaceAll(RegExp(r'\s+'), '_');
  }

  LedgerExportLabels get _labels =>
      LedgerExportLabels.supplier(AppLocalizations.of(context)!);

  Future<void> _exportCsv(List<LedgerEntry> ledger) async {
    final l10n = AppLocalizations.of(context)!;
    final csv = buildLedgerCsv(
      l10n,
      ledger,
      entityName: _nameStem,
      titleLabel: 'Supplier Ledger',
      labels: _labels,
    );
    await saveCsv(
      context,
      suggestedName:
          'ledger_$_nameStem-${DateTime.now().toIso8601String().split('T').first}.csv',
      csv: csv,
      successMessage: l10n.suppliersExportsuccess,
      errorMessage: l10n.errorsFailed,
    );
  }

  Future<void> _exportPdf(List<LedgerEntry> ledger) async {
    final l10n = AppLocalizations.of(context)!;
    final bytes = await buildLedgerPdf(
      l10n,
      ledger,
      entityName: _nameStem,
      titleLabel: 'Supplier Ledger',
      labels: _labels,
    );
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
    if (mounted) showAppToast(context, l10n.suppliersExportsuccess);
  }

  /// Captures the visible ledger table as a PNG (web html2canvas parity).
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
      if (mounted) showAppToast(context, l10n.suppliersExportsuccess);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    }
  }

  Future<void> _printLedger(List<LedgerEntry> ledger) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final bytes = await buildLedgerPdf(
        l10n,
        ledger,
        entityName: _nameStem,
        titleLabel: 'Supplier Ledger',
        labels: _labels,
      );
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
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }
}
