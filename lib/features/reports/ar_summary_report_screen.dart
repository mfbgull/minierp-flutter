// AR Summary (Receivables Summary) report — GET /reports/ar-summary
// (PORTING.md §11). Port of the web `ReceivablesSummary` component:
// a summary dashboard with KPI cards, aging buckets, and a status
// breakdown panel. No grid — the server returns a single aggregate
// object (no per-customer rows).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show ArSummaryReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart'
    show DateRangeFilter, DateRangeMode;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import 'report_providers.dart'
    show arSummaryAsOfDateProvider, arSummaryProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';

class ArSummaryReportScreen extends ConsumerWidget {
  const ArSummaryReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(arSummaryProvider);
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsTabsReceivables_summary,
            style: textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          onRefresh: () => ref.invalidate(arSummaryProvider),
          filters: [
            DateRangeFilter(
              mode: DateRangeMode.singleDate,
              fromProvider: arSummaryAsOfDateProvider,
              toProvider: arSummaryAsOfDateProvider,
              dateProvider: arSummaryAsOfDateProvider,
              showAllDates: false,
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
    AsyncValue<ArSummaryReport> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(arSummaryProvider),
      );
    }
    if (report.isLoading || !report.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final r = report.value!;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // As-of date line.
          if (r.asOfDate.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${l10n.reportsAsOf} ${Formatters.date(r.asOfDate)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          // KPI cards row (2x2 grid on narrow windows, row on wider).
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 600;
              final cards = [
                _kpiCard(
                  context,
                  l10n.reportsTotalreceivables,
                  Formatters.currency(r.totalOutstanding),
                  Icons.account_balance_wallet_outlined,
                  accent: true,
                ),
                _kpiCard(
                  context,
                  l10n.reportsTotalinvoiced,
                  Formatters.currency(r.totalInvoiced),
                  Icons.receipt_long_outlined,
                ),
                _kpiCard(
                  context,
                  l10n.salesTotalpaid,
                  Formatters.currency(r.totalPaid),
                  Icons.paid_outlined,
                ),
                _kpiCard(
                  context,
                  l10n.reportsTotalinvoices,
                  Formatters.number(r.totalInvoices),
                  Icons.description_outlined,
                ),
              ];
              if (wide) {
                return Row(
                  children: [
                    for (final c in cards) ...[
                      Expanded(child: c),
                      const SizedBox(width: 8),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Row(children: [Expanded(child: cards[0]), const SizedBox(width: 8), Expanded(child: cards[1])]),
                  const SizedBox(height: 8),
                  Row(children: [Expanded(child: cards[2]), const SizedBox(width: 8), Expanded(child: cards[3])]),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Aging buckets strip.
          _sectionLabel(context, l10n.reportsTabsAr_aging),
          const SizedBox(height: 8),
          _agingStrip(context, r),
          const SizedBox(height: 16),
          // Status breakdown.
          _sectionLabel(context, l10n.fieldsStatus),
          const SizedBox(height: 8),
          _statusBreakdown(context, r),
        ],
      ),
    );
  }

  // ── KPI card ─────────────────────────────────────────────────────

  Widget _kpiCard(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    bool accent = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent
            ? scheme.primaryContainer.withValues(alpha: 0.3)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppBorderRadius.mdRadius,
        border: Border.all(
          color: accent ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accent ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent ? scheme.primary : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Aging buckets ─────────────────────────────────────────────────

  Widget _agingStrip(BuildContext context, ArSummaryReport report) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final buckets = [
      (label: l10n.reportsCurrent, amount: report.totalCurrent),
      (label: l10n.reportsDays1_30, amount: report.total130),
      (label: l10n.reportsDays31_60, amount: report.total3160),
      (label: l10n.reportsDays61_90, amount: report.total6190),
      (label: l10n.reportsDays90plus, amount: report.totalOver90),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final bucket in buckets) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: AppBorderRadius.smRadius,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bucket.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    Formatters.currency(bucket.amount),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ── Status breakdown ──────────────────────────────────────────────

  Widget _statusBreakdown(BuildContext context, ArSummaryReport report) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final sb = report.statusBreakdown;
    final maxAmount = [
      sb.unpaid.amount,
      sb.partiallyPaid.amount,
      sb.overdue.amount,
    ].fold<num>(0, (m, v) => v > m ? v : m);
    final safeMax = maxAmount > 0 ? maxAmount.toDouble() : 1.0;

    Widget statusRow(
      String label,
      num count,
      num amount,
      Color color, {
      bool alert = false,
    }) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: alert ? scheme.error : null,
                      ),
                    ),
                  ),
                  Text(
                    Formatters.number(count),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: Text(
                      Formatters.currency(amount),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: alert ? scheme.error : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: AppBorderRadius.xsRadius,
                child: LinearProgressIndicator(
                  value: (amount / safeMax).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statusRow(
              l10n.statusUnpaid,
              sb.unpaid.count,
              sb.unpaid.amount,
              const Color(0xFFF97316),
            ),
            const Divider(height: 1),
            statusRow(
              l10n.statusPartiallypaid,
              sb.partiallyPaid.count,
              sb.partiallyPaid.amount,
              const Color(0xFFEAB308),
            ),
            const Divider(height: 1),
            statusRow(
              l10n.statusOverdue,
              sb.overdue.count,
              sb.overdue.amount,
              const Color(0xFFEF4444),
              alert: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall,
  );
}