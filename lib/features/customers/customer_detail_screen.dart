// Customer detail page — web parity (customer-module-spec.md §6). Full
// screen under the shell's `/customers/:id` branch: header (name +
// contact + Record Payment), quick-stats bar (Balance / Credit Limit /
// Utilization / Overdue) and 5 tabs — Overview, Invoices, Ledger,
// Payments, Statement. Every tab owns its provider watch; the page only
// watches detail + the metrics inputs (invoices + ledger) for the stats
// bar, all shared with the Overview tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';
import 'calculations/customer_calculations.dart'
    show computeCustomerMetrics;
import 'customer_invoices_tab.dart';
import 'customer_ledger_tab.dart';
import 'customer_overview_tab.dart';
import 'customer_payment_modal.dart' show showCustomerPaymentModal;
import 'customer_payments_tab.dart';
import 'customer_providers.dart';
import 'customer_statement_tab.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final int customerId;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen>
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

  void _openRecordPayment(Customer customer) {
    showCustomerPaymentModal(context, customer: customer);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final detail = ref.watch(customerDetailProvider(widget.customerId));

    return switch (detail) {
      AsyncData(:final value) => _buildPage(context, l10n, value),
      AsyncError(:final error) => ScreenErrorPanel(
        message: error is ApiError ? error.message : '$error',
        onRetry: () =>
            ref.invalidate(customerDetailProvider(widget.customerId)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _buildPage(
    BuildContext context,
    AppLocalizations l10n,
    Customer customer,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // Metrics inputs — shared with the Overview tab (default tab).
    final invoices = ref.watch(customerInvoicesProvider(widget.customerId));
    final ledger = ref.watch(customerLedgerProvider(widget.customerId));
    final metrics = computeCustomerMetrics(
      invoices.valueOrNull ?? const <Invoice>[],
      ledger.valueOrNull ?? const <LedgerEntry>[],
      customer,
    );

    final utilization = metrics.creditUtilization;
    final utilizationDanger = utilization > 90;
    final utilizationWarn = !utilizationDanger && utilization > 75;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Page header (web CustomerHeader): back + identity + Record
        // Payment. The shell's app bar already labels the module; this
        // block carries the customer context.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.customersBacktocustomers,
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
                            customer.customerName,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        if (customer.contactPerson?.isNotEmpty ?? false) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '(${customer.contactPerson})',
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
                        customer.customerCode,
                        if (customer.phone?.isNotEmpty ?? false)
                          customer.phone!,
                        if (customer.email?.isNotEmpty ?? false)
                          customer.email!,
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
                onPressed: () => _openRecordPayment(customer),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.customersRecordpayment),
              ),
            ],
          ),
        ),
        // Quick stats bar (web quick-stats-bar): Balance / Credit Limit /
        // Utilization / Overdue.
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
                    label: l10n.customersBalance,
                    value: Formatters.currency(metrics.currentBalance),
                    color: metrics.currentBalance > 0
                        ? scheme.error
                        : null,
                  ),
                  _statDivider(scheme),
                  _QuickStat(
                    icon: Icons.credit_card_outlined,
                    label: l10n.customersCreditlimit,
                    value: Formatters.currency(customer.creditLimit ?? 0),
                  ),
                  _statDivider(scheme),
                  _QuickStat(
                    icon: Icons.trending_up,
                    label: l10n.customersUtilization,
                    value:
                        '${metrics.creditUtilization.toStringAsFixed(2)}%',
                    color: utilizationDanger
                        ? scheme.error
                        : utilizationWarn
                        ? scheme.tertiary
                        : null,
                  ),
                  _statDivider(scheme),
                  _QuickStat(
                    icon: Icons.warning_amber_outlined,
                    label: l10n.customersOverdue,
                    value: '${metrics.overdueInvoicesCount}',
                    color: metrics.overdueInvoicesCount > 0
                        ? scheme.error
                        : null,
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
            Tab(text: l10n.customersOverview),
            Tab(text: l10n.customersInvoices),
            Tab(text: l10n.customersLedger),
            Tab(text: l10n.customersPayments),
            Tab(text: l10n.customersStatement),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              CustomerOverviewTab(customerId: widget.customerId),
              CustomerInvoicesTab(customerId: widget.customerId),
              CustomerLedgerTab(customerId: widget.customerId),
              CustomerPaymentsTab(customerId: widget.customerId),
              CustomerStatementTab(customerId: widget.customerId),
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
