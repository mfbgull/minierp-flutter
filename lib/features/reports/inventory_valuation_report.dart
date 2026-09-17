// Inventory Valuation Report — shows separated inventory sections
// (sellable, reserved, expired, damaged, written-off) with values at
// cost price via GET /reports/inventory-valuation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart'
    show InventoryValuationReport, WrittenOffBucket;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/report_repository.dart'
    show reportRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';

/// FutureProvider that fetches the inventory valuation report.
final _valuationProvider = FutureProvider<InventoryValuationReport>((ref) async {
  final repo = ref.watch(reportRepositoryProvider);
  final result = await repo.inventoryValuation();
  return result.fold(
    onSuccess: (data) => data,
    onFailure: (error) => throw error,
  );
});

class InventoryValuationScreen extends ConsumerWidget {
  const InventoryValuationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final valuationAsync = ref.watch(_valuationProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inventoryvaluation),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(_valuationProvider),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: valuationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          final message = err is ApiError ? err.message : err.toString();
          return ScreenErrorPanel(
            message: message,
            onRetry: () => ref.invalidate(_valuationProvider),
          );
        },
        data: (report) => _buildContent(context, ref, l10n, scheme, report),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ColorScheme scheme,
    InventoryValuationReport report,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_valuationProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // As-of date
            if (report.asOfDate.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l10n.valuationAsOfDate(report.asOfDate),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),

            // Sellable Inventory
            _valuationSection(
              context,
              l10n.valuationSellable,
              report.sellable.qty,
              report.sellable.value,
              Icons.inventory,
              scheme.primary,
            ),

            // Reserved Inventory
            _valuationSection(
              context,
              l10n.valuationReserved,
              report.reserved.qty,
              report.reserved.value,
              Icons.lock,
              scheme.secondary,
            ),

            // Expired Inventory
            _valuationSection(
              context,
              l10n.valuationExpired,
              report.expired.qty,
              report.expired.value,
              Icons.schedule,
              scheme.error,
            ),

            // Damaged Inventory
            _valuationSection(
              context,
              l10n.valuationDamaged,
              report.damaged.qty,
              report.damaged.value,
              Icons.broken_image,
              scheme.error,
            ),

            const SizedBox(height: 16),

            // Written Off section (different layout — count + qty + value)
            _writtenOffSection(context, l10n, scheme, report.writtenOff),

            const SizedBox(height: 24),

            // Total Physical Inventory
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.valuationTotalPhysical,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      Formatters.currency(report.totalPhysical.value),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Note
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.valuationNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• ${l10n.valuationNote}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• ${l10n.valuationNoteReservedSubset}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _valuationSection(
    BuildContext context,
    String title,
    double qty,
    double value,
    IconData icon,
    Color color,
  ) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Quantity: ${qty.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  Formatters.currency(value),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _writtenOffSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    WrittenOffBucket data,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.delete_outline, color: scheme.error, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.valuationWrittenOff,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${data.count} batches — ${data.qty.toStringAsFixed(0)} units',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  Formatters.currency(data.totalValue),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
