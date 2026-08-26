import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show GeneralLedgerRow;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';

class GeneralLedgerReportScreen extends ConsumerStatefulWidget {
  const GeneralLedgerReportScreen({super.key});

  @override
  ConsumerState<GeneralLedgerReportScreen> createState() =>
      _GeneralLedgerReportScreenState();
}

class _GeneralLedgerReportScreenState
    extends ConsumerState<GeneralLedgerReportScreen> {
  GridColumnWidths? _widthTracker;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(generalLedgerProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsGeneralledger,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportGeneralLedgerFromDateProvider,
              toProvider: reportGeneralLedgerToDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(generalLedgerProvider),
          actions: [
            TextButton.icon(
              onPressed: entries.isLoading || entries.valueOrNull == null
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('general-ledger'),
                      csv: buildGeneralLedgerCsv(l10n, entries.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        Expanded(child: _body(context, ref, entries)),
      ],
    );
  }

  @override
  void dispose() {
    _widthTracker?.dispose();
    super.dispose();
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<GeneralLedgerRow>> entries,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (entries) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(generalLedgerProvider),
      );
    }
    if (entries.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = entries.valueOrNull;
    if (rows == null || rows.isEmpty) {
      return Center(child: Text(l10n.reportsNodata));
    }

    return PlutoGrid(
      configuration: plutoGridConfigurationFor(context, compact: true),
      columns: [
        PlutoColumn(title: l10n.reportsDate, field: 'date', type: PlutoColumnType.text(), width: 110),
        PlutoColumn(title: 'Account', field: 'account', type: PlutoColumnType.text(), width: 170),
        PlutoColumn(title: l10n.reportsTransactiontype, field: 'type', type: PlutoColumnType.text(), width: 120),
        PlutoColumn(title: l10n.reportsReferenceno, field: 'ref', type: PlutoColumnType.text(), width: 120),
        PlutoColumn(title: l10n.reportsDebit, field: 'debit', type: PlutoColumnType.number(format: '#,###.00'), width: 120, textAlign: PlutoColumnTextAlign.end, titleTextAlign: PlutoColumnTextAlign.end),
        PlutoColumn(title: l10n.reportsCredit, field: 'credit', type: PlutoColumnType.number(format: '#,###.00'), width: 120, textAlign: PlutoColumnTextAlign.end, titleTextAlign: PlutoColumnTextAlign.end),
        PlutoColumn(title: l10n.reportsBalance, field: 'balance', type: PlutoColumnType.number(format: '#,###.00'), width: 120, textAlign: PlutoColumnTextAlign.end, titleTextAlign: PlutoColumnTextAlign.end),
        PlutoColumn(title: l10n.fieldsNotes, field: 'remarks', type: PlutoColumnType.text(), width: 150),
      ],
      rows: [
        for (final r in rows)
          PlutoRow(cells: {
            'date': PlutoCell(value: Formatters.date(r.transactionDate)),
            'account': PlutoCell(value: r.accountCode == null ? '' : '${r.accountCode} — ${r.accountName ?? ''}'),
            'type': PlutoCell(value: r.transactionType),
            'ref': PlutoCell(value: r.referenceNo),
            'debit': PlutoCell(value: r.debit),
            'credit': PlutoCell(value: r.credit),
            'balance': PlutoCell(value: r.balance),
            'remarks': PlutoCell(value: r.remarks ?? ''),
          }),
      ],
      onLoaded: (e) {
        e.stateManager.setSelectingMode(PlutoGridSelectingMode.none);
        autoFitPlutoColumns(e.stateManager);
        _widthTracker?.dispose();
        _widthTracker = GridColumnWidths.attach(
          stateManager: e.stateManager,
          screenKey: 'report_general_ledger',
        );
      },
    );
  }
}
