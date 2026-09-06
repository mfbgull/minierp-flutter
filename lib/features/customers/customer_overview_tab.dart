// Overview tab — web `OverviewTab` parity (customer-module-spec.md §6.4):
// Financial Summary cards (Total Invoiced / Total Received / Outstanding /
// Avg. Days to Pay), the Invoice Status breakdown (Paid / Pending / Overdue
// / Total with proportional bars) and collapsible Contact Information +
// Account Settings sections. All metrics come from the ported
// `computeCustomerMetrics`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import 'calculations/customer_calculations.dart'
    show calculateTotalInvoiced, calculateTotalPaid, computeCustomerMetrics;
import 'customer_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

class CustomerOverviewTab extends ConsumerWidget {
  const CustomerOverviewTab({
    super.key,
    required this.customerId,
    required this.sessionId,
  });

  final int customerId;

  /// The detail-page instance's range-session id — only the two
  /// period-scoped figures react to it (spec §6.1); everything else
  /// stays lifetime.
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final detail = ref.watch(customerDetailProvider(customerId));
    final invoices = ref.watch(customerInvoicesProvider(customerId));
    final ledger = ref.watch(customerLedgerProvider(customerId));
    final range = customerDetailRangeIso(ref, sessionId);

    if (detail case AsyncError(:final error)) {
      return DetailError(
        message: error is ApiError ? error.message : '$error',
        onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
      );
    }
    final customer = detail.valueOrNull;
    if (customer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final allInvoices = invoices.valueOrNull ?? const <Invoice>[];
    // Period cohort — spec §6.1: invoices whose invoiceDate falls inside
    // the active inclusive range. Only Total Invoiced / Total Received
    // react to it. Deliberately built from the ALREADY-fetched full list
    // (no new endpoint): Total Received sums each cohort invoice's
    // paidAmount, so payments made OUTSIDE the period still count toward
    // it when they belong to a cohort invoice (intentional — §6.1). All
    // other Overview figures (Outstanding, credit footer, status bars,
    // Avg. Days to Pay) stay lifetime.
    final cohort = range.from == null
        ? allInvoices
        : allInvoices
              .where(
                (inv) =>
                    inv.invoiceDate.isNotEmpty &&
                    inv.invoiceDate.compareTo(range.from!) >= 0 &&
                    inv.invoiceDate.compareTo(range.to!) <= 0,
              )
              .toList();
    final cohortEmpty = range.from != null && cohort.isEmpty;

    final metrics = computeCustomerMetrics(
      allInvoices,
      ledger.valueOrNull ?? const <LedgerEntry>[],
      customer,
    );
    final totalInvoices = metrics.paidInvoicesCount +
        metrics.unpaidInvoicesCount +
        metrics.overdueInvoicesCount;

    // Compact period annotation for the two range-scoped cards (spec
    // §6.1 Active-range annotation; hidden on All dates).
    final periodNote = range.from == null
        ? null
        : '${Formatters.date(range.from!)} – ${Formatters.date(range.to!)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Financial Summary — 4 cards.
          _sectionTitle(context, l10n.customersFinancialsummary),
          const SizedBox(height: 8),
          Row(
            children: [
              _SummaryCard(
                label: l10n.customersTotalinvoiced,
                value: Formatters.currency(calculateTotalInvoiced(cohort)),
                icon: Icons.receipt_long_outlined,
                annotation: periodNote,
              ),
              const SizedBox(width: 12),
              _SummaryCard(
                label: l10n.customersTotalreceived,
                value: Formatters.currency(calculateTotalPaid(cohort)),
                icon: Icons.savings_outlined,
                annotation: periodNote,
              ),
              const SizedBox(width: 12),
              _SummaryCard(
                label: l10n.customersOutstanding,
                value: Formatters.currency(metrics.totalOutstanding),
                icon: Icons.account_balance_wallet_outlined,
                valueColor: metrics.totalOutstanding > 0
                    ? scheme.error
                    : null,
                // A negative ledger net is money we owe the customer
                // (return credits / advances) — surface it next to the
                // outstanding figure so the two never look contradictory.
                footer: metrics.currentBalance < 0
                    ? '${l10n.customersCredit}: ${Formatters.currency(-metrics.currentBalance)}'
                    : null,
              ),
              const SizedBox(width: 12),
              _SummaryCard(
                label: l10n.customersAvgdaystopay,
                value: metrics.avgDaysToPay.toStringAsFixed(1),
                icon: Icons.schedule_outlined,
              ),
            ],
          ),
          // Empty-cohort line — spec §6.1/§10.2: only the title, never
          // the hint, because the rest of the Overview still carries
          // standing lifetime data.
          if (cohortEmpty) ...[
            const SizedBox(height: 10),
            Text(
              l10n.commonNoRecordsInPeriod,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Invoice Status — 4 tiles with proportional bars.
          _sectionTitle(context, l10n.customersInvoicestatus),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: AppBorderRadius.mdRadius,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _StatusBar(
                    label: l10n.customersPaid,
                    count: metrics.paidInvoicesCount,
                    total: totalInvoices,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 14),
                  _StatusBar(
                    label: l10n.customersPending,
                    count: metrics.unpaidInvoicesCount,
                    total: totalInvoices,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(height: 14),
                  _StatusBar(
                    label: l10n.customersOverdue,
                    count: metrics.overdueInvoicesCount,
                    total: totalInvoices,
                    color: scheme.error,
                  ),
                  const SizedBox(height: 14),
                  _StatusBar(
                    label: l10n.customersTotal,
                    count: totalInvoices,
                    total: totalInvoices == 0 ? 1 : totalInvoices,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Collapsible Contact Information.
          _collapsible(
            context,
            icon: Icons.phone_outlined,
            title: l10n.customersContactinfo,
            children: [
              _infoRow(context, l10n.fieldsPhone, customer.phone ?? '—'),
              _infoRow(context, l10n.fieldsEmail, customer.email ?? '—'),
              _infoRow(
                context,
                l10n.customersBillingaddress,
                customer.billingAddress ?? '—',
              ),
              _infoRow(
                context,
                l10n.customersShippingaddress,
                customer.shippingAddress ?? '—',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Collapsible Account Settings.
          _collapsible(
            context,
            icon: Icons.tune_outlined,
            title: l10n.customersAccountsettings,
            children: [
              _infoRow(
                context,
                l10n.customersPaymentterms,
                customer.paymentTerms?.isNotEmpty == true
                    ? customer.paymentTerms!
                    : customer.paymentTermsDays != null
                    ? l10n.customersDays(customer.paymentTermsDays!)
                    : '—',
              ),
              _infoRow(
                context,
                l10n.customersCreditlimit,
                Formatters.currency(customer.creditLimit ?? 0),
              ),
              _infoRow(
                context,
                l10n.customersOpeningbalance,
                Formatters.currency(customer.openingBalance ?? 0),
              ),
              _infoRow(
                context,
                l10n.customersCustomersince,
                customer.createdAt == null
                    ? '—'
                    : Formatters.date(customer.createdAt!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w600),
  );

  Widget _collapsible(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.mdRadius,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, size: 20),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: children,
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.footer,
    this.annotation,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  /// Optional small note under the label (e.g. available credit).
  final String? footer;

  /// Compact period annotation for range-scoped figures (spec §6.1).
  final String? annotation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.mdRadius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(height: 10),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (annotation != null) ...[
                const SizedBox(height: 2),
                Text(
                  annotation!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (footer != null) ...[
                const SizedBox(height: 4),
                Text(
                  footer!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = total == 0 ? 0.0 : count / total;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: AppBorderRadius.xsRadius,
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 36,
          child: Text(
            '$count',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
