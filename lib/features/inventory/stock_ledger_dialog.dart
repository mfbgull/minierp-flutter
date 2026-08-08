// Stock ledger dialog — per-item movement history (`GET
// /inventory/stock-ledger/:itemId`). The endpoint returns the item's
// stock_movements newest-first (bare array, warehouse join only — the
// item fields are absent and parse as null). Each row is a signed
// quantity (positive = stock in, negative = stock out); the Balance
// column is a running total computed client-side by walking the rows
// oldest-first, so every row shows the stock level after that movement.
//
// A warehouse filter (local dialog state) narrows the ledger via the
// `warehouse_id` query param the endpoint already accepts; the table's
// Warehouse column then repeats the selected code across every row.
//
// Unlike the accounting ledgers (customer/supplier LedgerDialog) this is
// a quantity table, so it renders its own compact header/rows instead of
// reusing the LedgerTable debit/credit primitives.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/movement_type_label.dart';
import '../../data/models/stock_movement.dart' show StockMovement;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_error.dart';
import '../../widgets/detail_labels.dart';
import 'inventory_providers.dart';

/// Opens the stock ledger for [itemId]; [itemLabel] is the item
/// code/name shown in the header.
Future<void> showStockLedgerDialog(
  BuildContext context, {
  required int itemId,
  required String itemLabel,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _StockLedgerDialog(itemId: itemId, itemLabel: itemLabel),
  );
}

class _StockLedgerDialog extends ConsumerStatefulWidget {
  const _StockLedgerDialog({required this.itemId, required this.itemLabel});

  final int itemId;
  final String itemLabel;

  @override
  ConsumerState<_StockLedgerDialog> createState() => _StockLedgerDialogState();
}

class _StockLedgerDialogState extends ConsumerState<_StockLedgerDialog> {
  /// Null = all warehouses; otherwise the selected warehouse's id.
  int? _warehouseId;

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(
      stockLedgerProvider((widget.itemId, _warehouseId)),
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 600),
        child: switch (ledger) {
          AsyncData(:final value) => _LedgerBody(
            itemLabel: widget.itemLabel,
            movements: value,
            warehouseId: _warehouseId,
            onWarehouseChanged: (id) => setState(() => _warehouseId = id),
          ),
          AsyncError(:final error) => DetailError(
            message: error is ApiError ? error.message : '$error',
            onRetry: () => ref.invalidate(
              stockLedgerProvider((widget.itemId, _warehouseId)),
            ),
          ),
          _ => const SizedBox(
            width: 560,
            height: 280,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ),
    );
  }
}

class _LedgerBody extends ConsumerWidget {
  const _LedgerBody({
    required this.itemLabel,
    required this.movements,
    required this.warehouseId,
    required this.onWarehouseChanged,
  });

  final String itemLabel;
  final List<StockMovement> movements;

  /// The active filter (null = all warehouses); owned by the dialog state
  /// so the provider family key changes and refetches on selection.
  final int? warehouseId;

  final ValueChanged<int?> onWarehouseChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final warehouses = ref.watch(warehousesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    detailSectionLabel(context, l10n.inventoryStockledger),
                    const SizedBox(height: 2),
                    Text(
                      itemLabel,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Warehouse filter — narrows the ledger server-side via the
              // `warehouse_id` query param. Sentinel -1 = all warehouses
              // (matches the movement-type filter's empty-string
              // convention; null items are ambiguous in dropdowns).
              SizedBox(
                width: 220,
                height: 44,
                child: DropdownButtonFormField<int>(
                  initialValue: warehouseId ?? -1,
                  isExpanded: true,
                  isDense: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.warehouse_outlined, size: 20),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: [
                    DropdownMenuItem<int>(
                      value: -1,
                      child: Text(l10n.inventoryStockledgerAllwarehouses),
                    ),
                    // Inactive warehouses are intentionally included — a
                    // historical ledger may reference a deactivated one.
                    if (warehouses case AsyncData(:final value))
                      for (final w in value)
                        DropdownMenuItem<int>(
                          value: w.id,
                          child: Text(
                            w.warehouseName?.isNotEmpty ?? false
                                ? '${w.warehouseCode} · ${w.warehouseName}'
                                : w.warehouseCode,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: (value) =>
                      onWarehouseChanged(value == -1 ? null : value),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: movements.isEmpty
              ? _EmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: _LedgerTable(movements: movements),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: movements.isEmpty
                    ? null
                    : () => saveCsv(
                        context,
                        suggestedName: '${_fileNameBase(itemLabel)}.csv',
                        csv: buildStockLedgerCsv(l10n, movements),
                        successMessage: l10n.inventoryStockledgerExported,
                        errorMessage: l10n.inventoryStockledgerExportfailed,
                      ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(l10n.inventoryStockledgerExportcsv),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonClose),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared column widths — keep header and rows aligned.
const double _ledgerDateWidth = 104;
const double _ledgerTypeWidth = 104;
const double _ledgerWarehouseWidth = 108;
const double _ledgerQtyWidth = 64;
const double _ledgerBalanceWidth = 92;

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.movements});

  final List<StockMovement> movements;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.3,
    );

    // The endpoint is newest-first; walk the reversed (oldest-first)
    // list so each row's Balance is the level after that movement.
    // Note: the running total only covers the returned history — it does
    // not necessarily reconcile to the item's current_stock.
    final balances = <int, num>{};
    var running = 0.0;
    for (final m in movements.reversed) {
      running += m.quantity;
      balances[m.id] = running;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: _ledgerDateWidth,
                child: Text(l10n.commonDate, style: style),
              ),
              SizedBox(
                width: _ledgerTypeWidth,
                child: Text(l10n.inventoryStockledgerType, style: style),
              ),
              Expanded(child: Text(l10n.fieldsReference, style: style)),
              SizedBox(
                width: _ledgerWarehouseWidth,
                child: Text(l10n.fieldsWarehouse, style: style),
              ),
              SizedBox(
                width: _ledgerQtyWidth,
                child: Text(
                  l10n.inventoryStockledgerIn,
                  style: style,
                  textAlign: TextAlign.end,
                ),
              ),
              SizedBox(
                width: _ledgerQtyWidth,
                child: Text(
                  l10n.inventoryStockledgerOut,
                  style: style,
                  textAlign: TextAlign.end,
                ),
              ),
              SizedBox(
                width: _ledgerBalanceWidth,
                child: Text(
                  l10n.inventoryStockledgerBalance,
                  style: style,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        for (final m in movements)
          _LedgerRow(movement: m, balance: balances[m.id] ?? 0),
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.movement, required this.balance});

  final StockMovement movement;
  final num balance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final amount = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final qty = movement.quantity;
    final inQty = qty > 0 ? qty : null;
    final outQty = qty < 0 ? -qty : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _ledgerDateWidth,
            child: Text(
              movement.movementDate.isEmpty
                  ? '—'
                  : Formatters.date(movement.movementDate),
              style: muted,
            ),
          ),
          SizedBox(
            width: _ledgerTypeWidth,
            child: Text(
              movementTypeLabel(
                AppLocalizations.of(context)!,
                movement.movementType,
              ),
              style: amount,
            ),
          ),
          Expanded(
            child: Text(
              movement.referenceDocNo ?? '—',
              style: muted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: _ledgerWarehouseWidth,
            child: Text(
              movement.warehouseCode ?? '—',
              style: muted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: _ledgerQtyWidth,
            child: Text(
              inQty == null ? '—' : Formatters.number(inQty),
              style: amount?.copyWith(color: scheme.primary),
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ledgerQtyWidth,
            child: Text(
              outQty == null ? '—' : Formatters.number(outQty),
              style: amount?.copyWith(color: scheme.error),
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: _ledgerBalanceWidth,
            child: Text(
              Formatters.number(balance),
              style: amount?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// File-name base derived from the item label (`FG001 · Widget A` →
/// `FG001-Widget-A`); used for the suggested CSV name.
String _fileNameBase(String itemLabel) {
  final cleaned = itemLabel
      .replaceAll('·', '-')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  return cleaned.isEmpty ? 'stock-ledger' : cleaned;
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 220,
      child: Center(
        child: Text(
          l10n.inventoryStockledgerNoentries,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
