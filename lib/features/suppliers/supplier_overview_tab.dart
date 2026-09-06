// Overview tab — web supplier `OverviewTab` parity: Financial Summary
// cards (Current Balance / Total PO Value / Total POs), the PO Status
// breakdown (Draft / Submitted / Partial / Completed with proportional
// bars) and collapsible Contact Information + Account Settings sections.
// Data comes from the detail, balance and PO-summary providers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/purchase_order_repository.dart' show POSummary;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import 'supplier_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

class SupplierOverviewTab extends ConsumerWidget {
  const SupplierOverviewTab({
    super.key,
    required this.supplierId,
    required this.sessionId,
  });

  final int supplierId;

  /// The detail-page instance's range-session id — the PO-derived figures
  /// react to it (spec §7.1); Current Balance stays lifetime.
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final detail = ref.watch(supplierDetailProvider(supplierId));
    final balance = ref.watch(supplierBalanceProvider(supplierId));
    final range = supplierDetailRangeIso(ref, sessionId);
    final poSummary = ref.watch(
      supplierPOSummaryProvider(
        SupplierPOSummaryArgs(
          supplierId: supplierId,
          fromDate: range.from,
          toDate: range.to,
        ),
      ),
    );

    if (detail case AsyncError(:final error)) {
      return DetailError(
        message: error is ApiError ? error.message : '$error',
        onRetry: () => ref.invalidate(supplierDetailProvider(supplierId)),
      );
    }
    final supplier = detail.valueOrNull;
    if (supplier == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Current Balance is as-of-now and unfiltered (spec §7.1) — it must
    // keep matching the top quick-stats bar's standing supplier balance.
    final currentBalance =
        balance.valueOrNull?.currentBalance ??
        supplier.currentBalance ??
        0;
    final summary =
        poSummary.valueOrNull ??
        // Zeroed defaults while loading (web returns a zeroed object when
        // the supplier has no POs).
        const POSummary(
          totalPos: 0,
          totalValue: 0,
          draftPos: 0,
          submittedPos: 0,
          partiallyReceivedPos: 0,
          completedPos: 0,
        );
    final totalPos = summary.totalPos;
    // Zero-PO ranged summary (spec §10.3): PO-derived values show zero,
    // Current Balance stays, and a filtered-period line replaces any
    // global "supplier has no data" message.
    final zeroPoPeriod = range.from != null && totalPos == 0;
    // Compact period annotation for the two range-scoped cards (spec
    // §6.1 mirror; hidden on All dates).
    final periodNote = range.from == null
        ? null
        : '${Formatters.date(range.from!)} – ${Formatters.date(range.to!)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Financial Summary — 3 cards.
          _sectionTitle(context, l10n.suppliersFinancialsummary),
          const SizedBox(height: 8),
          Row(
            children: [
              _SummaryCard(
                label: l10n.suppliersCurrentbalance,
                value: Formatters.currency(currentBalance),
                icon: Icons.account_balance_wallet_outlined,
                valueColor: currentBalance > 0 ? scheme.error : null,
              ),
              const SizedBox(width: 12),
              _SummaryCard(
                label: l10n.suppliersTotalpovalue,
                value: Formatters.currency(summary.totalValue),
                icon: Icons.receipt_long_outlined,
                annotation: periodNote,
              ),
              const SizedBox(width: 12),
              _SummaryCard(
                label: l10n.suppliersTotalpos,
                value: '$totalPos',
                icon: Icons.inventory_2_outlined,
                annotation: periodNote,
              ),
            ],
          ),
          // Zero-PO period line — spec §10.3: only the title, never the
          // hint, because Current Balance and the contact/account
          // sections still carry standing data.
          if (zeroPoPeriod) ...[
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
          // PO Status — 4 tiles with proportional bars.
          _sectionTitle(context, l10n.suppliersPostatus),
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
                    label: l10n.suppliersDraft,
                    count: summary.draftPos,
                    total: totalPos,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(height: 14),
                  _StatusBar(
                    label: l10n.suppliersSubmitted,
                    count: summary.submittedPos,
                    total: totalPos,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 14),
                  _StatusBar(
                    label: l10n.suppliersPartial,
                    count: summary.partiallyReceivedPos,
                    total: totalPos,
                    color: scheme.secondary,
                  ),
                  const SizedBox(height: 14),
                  _StatusBar(
                    label: l10n.suppliersCompleted,
                    count: summary.completedPos,
                    total: totalPos,
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
            title: l10n.suppliersContactinfo,
            children: [
              _infoRow(
                context,
                l10n.suppliersContactperson,
                supplier.contactPerson ?? '—',
              ),
              _infoRow(context, l10n.suppliersPhone, supplier.phone ?? '—'),
              _infoRow(context, l10n.suppliersEmail, supplier.email ?? '—'),
              _infoRow(context, l10n.suppliersAddress, supplier.address ?? '—'),
            ],
          ),
          const SizedBox(height: 12),
          // Collapsible Account Settings.
          _collapsible(
            context,
            icon: Icons.tune_outlined,
            title: l10n.suppliersAccountsettings,
            children: [
              _infoRow(
                context,
                l10n.suppliersPaymentterms,
                supplier.paymentTerms?.isNotEmpty == true
                    ? supplier.paymentTerms!
                    : 'Net 30',
              ),
              _infoRow(
                context,
                l10n.suppliersBalance,
                Formatters.currency(currentBalance),
              ),
              _infoRow(
                context,
                l10n.suppliersSincesupplier,
                supplier.createdAt == null
                    ? '—'
                    : Formatters.date(supplier.createdAt!),
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
    this.annotation,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  /// Compact period annotation for range-scoped figures (spec §7.1).
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
