// Cash / till reconciliation — GET/POST /reports/cash-reconciliation.
//
// The end-of-day check: for a chosen date, how much cash should be in
// the drawer and each wallet (expected = book balance computed from
// payments, expenses and salaries), how much was actually counted, and
// the short/over variance. Counted amounts + notes are saved per
// (date, account) so the reconciliation history is auditable.
//
// Layout: a header summary (total expected vs total counted + variance)
// over a tabular account grid — one row per account (Cash, Bank,
// Easypaisa, JazzCash, UPaisa) with editable Counted + Notes columns.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart'
    show CashReconciliation, CashReconciliationAccount;
import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/report_repository.dart'
    show reportRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart' show showAppToast;
import '../../widgets/date_range_picker.dart' show DateRangeFilter, DateRangeMode;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

class CashReconciliationScreen extends ConsumerStatefulWidget {
  const CashReconciliationScreen({super.key});

  @override
  ConsumerState<CashReconciliationScreen> createState() =>
      _CashReconciliationScreenState();
}

class _CashReconciliationScreenState
    extends ConsumerState<CashReconciliationScreen> {
  /// Per-account counted/notes controllers, rebuilt whenever the loaded
  /// date changes (so typing is never clobbered by a rebuild).
  final Map<String, TextEditingController> _counted = {};
  final Map<String, TextEditingController> _notes = {};
  String? _loadedDate;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _counted.values) {
      c.dispose();
    }
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers(CashReconciliation report) {
    if (report.date == _loadedDate) return;
    for (final c in _counted.values) {
      c.dispose();
    }
    for (final c in _notes.values) {
      c.dispose();
    }
    _counted.clear();
    _notes.clear();
    for (final a in report.accounts) {
      _counted[a.key] = TextEditingController(
        text: a.countedBalance == null ? '' : _plain(a.countedBalance!),
      );
      _notes[a.key] = TextEditingController(text: a.notes ?? '');
    }
    _loadedDate = report.date;
  }

  Future<void> _save() async {
    final report = ref.read(cashReconciliationProvider).valueOrNull;
    final l10n = AppLocalizations.of(context)!;
    if (report == null || _saving) return;
    setState(() => _saving = true);
    final accounts = [
      for (final a in report.accounts)
        {
          'key': a.key,
          'counted_balance': num.tryParse(_counted[a.key]?.text.trim() ?? ''),
          'notes': _notes[a.key]?.text.trim() ?? '',
        },
    ];
    final result = await ref
        .read(reportRepositoryProvider)
        .saveCashReconciliation(date: report.date, accounts: accounts);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ApiSuccess():
        ref.invalidate(cashReconciliationProvider);
        showAppToast(context, l10n.cashreconSaved);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final report = ref.watch(cashReconciliationProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsCashreconciliation,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            // Single-date mode: the pill shows one date, the presets are
            // Today/Yesterday/This month, and tapping a day commits it.
            // from/to are ignored in this mode (the widget only writes
            // dateProvider), so all three share the same provider.
            DateRangeFilter(
              mode: DateRangeMode.singleDate,
              fromProvider: reportReconciliationDateProvider,
              toProvider: reportReconciliationDateProvider,
              dateProvider: reportReconciliationDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(cashReconciliationProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || report.valueOrNull == null
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('cash-reconciliation'),
                      csv: buildCashReconciliationCsv(l10n, report.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
            FilledButton.icon(
              onPressed: report.isLoading || report.valueOrNull == null
                  ? null
                  : (_saving ? null : _save),
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(l10n.cashreconSave),
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
    AsyncValue<CashReconciliation> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(cashReconciliationProvider),
      );
    }
    if (report.isLoading || !report.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = report.value!;
    _syncControllers(data);
    final countedTotal = data.accounts.fold<num>(
      0,
      (sum, a) => sum + (a.countedBalance ?? 0),
    );
    final varianceTotal = countedTotal - data.totals.closing;
    final allCounted =
        data.accounts.isNotEmpty &&
        data.accounts.every((a) => a.countedBalance != null);
    // Uncounted accounts would read as a zero count → a misleading
    // "short" in the totals; hide the variance until every account is
    // counted and let the header chip say where things stand.
    final varianceLabel = allCounted
        ? Formatters.currency(varianceTotal)
        : l10n.cashreconNotcounted;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Table-like grid scrolls horizontally on narrow windows.
          final width = constraints.maxWidth < 1250 ? 1250.0 : constraints.maxWidth;
          return SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryBanner(
                  expected: data.totals.closing,
                  counted: countedTotal,
                  variance: varianceTotal,
                  varianceLabel: varianceLabel,
                  reconciled: allCounted,
                ),
                const SizedBox(height: 12),
                _row(cells: [
                    _cell(l10n.fieldsAccount, width: 140),
                    _cell(l10n.cashreconOpening, width: 120, alignRight: true),
                    _cell(l10n.cashreconInflow, width: 110, alignRight: true),
                    _cell(l10n.cashreconOutflow, width: 110, alignRight: true),
                    _cell(l10n.cashreconNet, width: 100, alignRight: true),
                    _cell(
                      l10n.cashreconExpected,
                      width: 130,
                      alignRight: true,
                    ),
                    _cell(l10n.cashreconCounted, width: 160, alignRight: true),
                    _cell(l10n.cashreconVariance, width: 130, alignRight: true),
                    _cell(l10n.cashreconNotes, width: 200),
                  ],
                ),
                for (final a in data.accounts)
                  _accountRow(context, a, width: width),
                const Divider(height: 24),
                _totalsRow(
                  context,
                  data,
                  counted: countedTotal,
                  allCounted: allCounted,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _accountRow(
    BuildContext context,
    CashReconciliationAccount a, {
    required double width,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final variance = a.variance;
    final inBalance = variance == null || variance == 0;
    final varianceColor = variance == null
        ? scheme.onSurfaceVariant
        : inBalance
        ? const Color(0xFF16A34A)
        : scheme.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppBorderRadius.smRadius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: _row(
        cells: [
          _cell(
            a.name,
            width: 140,
            bold: true,
            leading: _accountIcon(a.key),
            trailing: a.key == 'unclassified'
                ? Tooltip(
                    // CASH-02 (task 1.3): unrecognized payment methods land
                    // here instead of silently counting as bank.
                    message: 'Payments with an unrecognized method — fix the '
                        'payment method so it reaches the right account.',
                    child: Icon(Icons.warning_amber_rounded,
                        size: 15, color: scheme.error),
                  )
                : null,
          ),
          _cell(Formatters.currency(a.openingBalance), width: 120, alignRight: true),
          _cell(
            Formatters.currency(a.inflow),
            width: 110,
            alignRight: true,
            color: const Color(0xFF16A34A),
          ),
          _cell(
            Formatters.currency(a.outflow),
            width: 110,
            alignRight: true,
            color: scheme.error,
          ),
          _cell(Formatters.currency(a.net), width: 100, alignRight: true),
          _cell(
            Formatters.currency(a.expectedBalance),
            width: 130,
            alignRight: true,
            bold: true,
          ),
          _cellWidget(
            _inputField(_counted[a.key], l10n.cashreconCounted, scheme),
            width: 160,
          ),
          _cell(
            variance == null
                ? l10n.cashreconNotcounted
                : Formatters.currency(variance),
            width: 130,
            alignRight: true,
            color: varianceColor,
            weight: variance == null ? FontWeight.w400 : FontWeight.w700,
          ),
          _cellWidget(
            _inputField(_notes[a.key], l10n.cashreconNotes, scheme),
            width: 200,
          ),
        ],
      ),
    );
  }

  Widget _totalsRow(
    BuildContext context,
    CashReconciliation data, {
    required num counted,
    required bool allCounted,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final variance = counted - data.totals.closing;
    return _row(
      cells: [
        _cell(
          AppLocalizations.of(context)!.commonTotal,
          width: 140,
          bold: true,
        ),
        _cell(Formatters.currency(data.totals.opening), width: 120, alignRight: true),
        _cell(Formatters.currency(data.totals.inflow), width: 110, alignRight: true),
        _cell(Formatters.currency(data.totals.outflow), width: 110, alignRight: true),
        _cell(
          Formatters.currency(data.totals.inflow - data.totals.outflow),
          width: 100,
          alignRight: true,
        ),
        _cell(
          Formatters.currency(data.totals.closing),
          width: 130,
          alignRight: true,
          bold: true,
        ),
        _cell(Formatters.currency(counted), width: 160, alignRight: true),
        _cell(
          allCounted ? Formatters.currency(variance) : '—',
          width: 130,
          alignRight: true,
          bold: true,
          color: allCounted
              ? (variance == 0 ? const Color(0xFF16A34A) : scheme.error)
              : scheme.onSurfaceVariant,
        ),
        _cell('', width: 200),
      ],
    );
  }

  // ── Layout helpers ───────────────────────────────────────────────

  /// Fixed-width cells in a Row — the parent SizedBox is at least
  /// 1250px wide inside a horizontal scroll view, so the columns keep
  /// their widths and narrow windows scroll instead of overflowing.
  Widget _row({required List<Widget> cells}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: cells);
  }

  Widget _cell(
    String text, {
    required double width,
    bool alignRight = false,
    bool bold = false,
    Color? color,
    FontWeight? weight,
    Widget? leading,
    Widget? trailing,
  }) =>
      SizedBox(
        width: width,
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 6)],
            Expanded(
              child: Text(
                text,
                textAlign: alignRight ? TextAlign.right : TextAlign.left,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: bold ? FontWeight.w700 : weight,
                  color: color,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      );

  Widget _cellWidget(Widget child, {required double width}) => SizedBox(
    width: width,
    child: child,
  );

  Widget _inputField(
    TextEditingController? controller,
    String label,
    ColorScheme scheme,
  ) =>
      TextField(
        controller: controller,
        enabled: !_saving,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11),
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
        ),
      );

  Icon _accountIcon(String key) {
    return Icon(
      switch (key) {
        'cash' => Icons.payments_outlined,
        'bank' => Icons.account_balance_outlined,
        'easypaisa' => Icons.phone_android_outlined,
        'jazzcash' => Icons.phone_android_outlined,
        _ => Icons.account_balance_wallet_outlined,
      },
      size: 15,
    );
  }

  static String _plain(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}

/// Header summary: total expected vs total counted and the overall
/// short/over variance, with a reconciled chip when every account has
/// been counted.
class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({
    required this.expected,
    required this.counted,
    required this.variance,
    required this.varianceLabel,
    required this.reconciled,
  });

  final num expected;
  final num counted;
  final num variance;

  /// Pre-formatted variance text — 'Not counted' until every account has
  /// a counted balance (a partial count would read as a big shortage).
  final String varianceLabel;
  final bool reconciled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final color = reconciled
        ? (variance == 0
              ? const Color(0xFF16A34A)
              : scheme.error)
        : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppBorderRadius.mdRadius,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.fact_check_outlined, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 24,
              runSpacing: 4,
              children: [
                _stat(
                  context,
                  l10n.cashreconExpected,
                  Formatters.currency(expected),
                ),
                _stat(
                  context,
                  l10n.cashreconCounted,
                  Formatters.currency(counted),
                ),
                _stat(
                  context,
                  l10n.cashreconVariance,
                  varianceLabel,
                  color: color,
                  bold: true,
                ),
              ],
            ),
          ),
          if (reconciled)
            Chip(
              label: Text(l10n.cashreconReconciled),
              labelStyle: const TextStyle(fontSize: 12),
              visualDensity: VisualDensity.compact,
              backgroundColor: color.withValues(alpha: 0.15),
              side: BorderSide(color: color.withValues(alpha: 0.4)),
            ),
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    String label,
    String value, {
    Color? color,
    bool bold = false,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      );
}
