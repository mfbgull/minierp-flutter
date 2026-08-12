// Supplier detail page — web `SupplierDetailPage` parity (same treatment
// as the customer module). Full screen under the shell's `/suppliers/:id`
// branch: header (name + contact + Record Payment), quick-stats bar
// (Balance / Payment Terms, the web SupplierHeader's stats) and 5 tabs —
// Overview, POs, Ledger, Payments, Statement. Every tab owns its provider
// watch; the page only watches detail + balance for the stats bar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';
import 'supplier_ledger_tab.dart';
import 'supplier_overview_tab.dart';
import 'supplier_payment_modal.dart' show showSupplierPaymentModal;
import 'supplier_payments_tab.dart';
import 'supplier_pos_tab.dart';
import 'supplier_providers.dart';
import 'supplier_statement_tab.dart';

class SupplierDetailScreen extends ConsumerStatefulWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final int supplierId;

  @override
  ConsumerState<SupplierDetailScreen> createState() =>
      _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends ConsumerState<SupplierDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openRecordPayment(Supplier supplier) {
    showSupplierPaymentModal(context, supplier: supplier);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final detail = ref.watch(supplierDetailProvider(widget.supplierId));

    return switch (detail) {
      AsyncData(:final value) => _buildPage(context, l10n, value),
      AsyncError(:final error) => ScreenErrorPanel(
        message: error is ApiError ? error.message : '$error',
        onRetry: () =>
            ref.invalidate(supplierDetailProvider(widget.supplierId)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _buildPage(
    BuildContext context,
    AppLocalizations l10n,
    Supplier supplier,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // Balance quick-stat source (web SupplierHeader's balanceData).
    final balance = ref.watch(supplierBalanceProvider(widget.supplierId));
    final currentBalance =
        balance.valueOrNull?.currentBalance ??
        supplier.currentBalance ??
        0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Page header (web SupplierHeader): back + identity + Record
        // Payment. The shell's app bar already labels the module; this
        // block carries the supplier context.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.suppliersBacktosuppliers,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            supplier.supplierName,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        if (supplier.contactPerson?.isNotEmpty ?? false) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '(${supplier.contactPerson})',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        supplier.supplierCode,
                        if (supplier.phone?.isNotEmpty ?? false)
                          supplier.phone!,
                        if (supplier.email?.isNotEmpty ?? false)
                          supplier.email!,
                      ].join('  ·  '),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _openRecordPayment(supplier),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.suppliersRecordpayment),
              ),
            ],
          ),
        ),
        // Quick stats bar (web quick-stats-bar): Balance / Payment Terms.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  _QuickStat(
                    icon: Icons.account_balance_wallet_outlined,
                    label: l10n.suppliersBalance,
                    value: Formatters.currency(currentBalance),
                    color: currentBalance > 0 ? scheme.error : null,
                  ),
                  _statDivider(scheme),
                  _QuickStat(
                    icon: Icons.credit_card_outlined,
                    label: l10n.suppliersPaymentterms,
                    value: supplier.paymentTerms?.isNotEmpty == true
                        ? supplier.paymentTerms!
                        : 'Net 30',
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: l10n.suppliersOverview),
            Tab(text: l10n.suppliersPos),
            Tab(text: l10n.suppliersLedger),
            Tab(text: l10n.suppliersPayments),
            Tab(text: l10n.suppliersStatement),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              SupplierOverviewTab(supplierId: widget.supplierId),
              SupplierPosTab(supplierId: widget.supplierId),
              SupplierLedgerTab(supplierId: widget.supplierId),
              SupplierPaymentsTab(supplierId: widget.supplierId),
              SupplierStatementTab(supplierId: widget.supplierId),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statDivider(ColorScheme scheme) => Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: scheme.outlineVariant,
  );
}

/// One quick-stat tile: icon + value + label.
class _QuickStat extends StatelessWidget {
  const _QuickStat({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.onSurface;
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: effectiveColor),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: effectiveColor),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
