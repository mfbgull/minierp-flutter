import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show TrialBalanceReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter, DateRangeMode;
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';

class TrialBalanceReportScreen extends ConsumerWidget {
  const TrialBalanceReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(trialBalanceProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsTrialbalance,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportTrialBalanceAsOfDateProvider,
              toProvider: reportTrialBalanceAsOfDateProvider,
              mode: DateRangeMode.singleDate,
              dateProvider: reportTrialBalanceAsOfDateProvider,
              showAllDates: false,
            ),
          ],
          onRefresh: () => ref.invalidate(trialBalanceProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || report.valueOrNull == null
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('trial-balance'),
                      csv: buildTrialBalanceCsv(l10n, report.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        Expanded(child: _body(context, ref, report)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<TrialBalanceReport> report,
  ) {
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(trialBalanceProvider),
      );
    }
    if (report.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = report.valueOrNull;
    if (data == null) return const SizedBox.shrink();

    return Column(
      children: [
        // Summary strip
        _SummaryStrip(report: data),
        const SizedBox(height: 8),
        // Grid
        Expanded(
          child: _TrialBalanceGrid(report: data),
        ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.report});
  final TrialBalanceReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        children: [
          _metric(l10n.reportsTotaldebit, Formatters.currency(report.totalDebit), theme),
          _metric(l10n.reportsTotalcredit, Formatters.currency(report.totalCredit), theme),
          _metric(
            report.balanced ? '✓ ${l10n.reportsBalanced}' : '✗ Not Balanced',
            '',
            theme,
            color: report.balanced ? theme.colorScheme.primary : theme.colorScheme.error,
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, ThemeData theme, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        if (value.isNotEmpty)
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        if (value.isEmpty && color != null)
          Icon(
            report.balanced ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 20,
          ),
      ],
    );
  }
}

class _TrialBalanceGrid extends StatefulWidget {
  const _TrialBalanceGrid({required this.report});
  final TrialBalanceReport report;

  @override
  State<_TrialBalanceGrid> createState() => _TrialBalanceGridState();
}

class _TrialBalanceGridState extends State<_TrialBalanceGrid> {
  late final PlutoGridStateManager stateManager;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PlutoGrid(
      configuration: plutoGridConfigurationFor(context, compact: true),
      columns: [
        PlutoColumn(title: l10n.reportsAccountcode, field: 'code', type: PlutoColumnType.text(), width: 100),
        PlutoColumn(title: l10n.reportsAccountname, field: 'name', type: PlutoColumnType.text(), width: 200),
        PlutoColumn(title: l10n.reportsAccounttype, field: 'type', type: PlutoColumnType.text(), width: 100),
        PlutoColumn(
          title: l10n.reportsDebit,
          field: 'debit',
          type: PlutoColumnType.number(format: '#,###.00'),
          width: 120,
          textAlign: PlutoColumnTextAlign.end,
          titleTextAlign: PlutoColumnTextAlign.end,
        ),
        PlutoColumn(
          title: l10n.reportsCredit,
          field: 'credit',
          type: PlutoColumnType.number(format: '#,###.00'),
          width: 120,
          textAlign: PlutoColumnTextAlign.end,
          titleTextAlign: PlutoColumnTextAlign.end,
        ),
        PlutoColumn(
          title: l10n.reportsBalance,
          field: 'balance',
          type: PlutoColumnType.number(format: '#,###.00'),
          width: 120,
          textAlign: PlutoColumnTextAlign.end,
          titleTextAlign: PlutoColumnTextAlign.end,
        ),
      ],
      rows: [
        for (final a in widget.report.accounts)
          PlutoRow(cells: {
            'code': PlutoCell(value: a.accountCode),
            'name': PlutoCell(value: a.accountName),
            'type': PlutoCell(value: a.accountType),
            'debit': PlutoCell(value: a.totalDebit),
            'credit': PlutoCell(value: a.totalCredit),
            'balance': PlutoCell(value: a.balance),
          }),
      ],
      onLoaded: (e) {
        stateManager = e.stateManager;
        stateManager.setSelectingMode(PlutoGridSelectingMode.none);
        autoFitPlutoColumns(stateManager);
      },
    );
  }
}
