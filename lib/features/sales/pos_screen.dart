// POS (Point of Sale) screen — PORTING.md §5. A split-layout retail
// register: catalog browse on the left, cart + checkout on the right.
// The catalog reuses the inventory items endpoint; the sale commit and
// transaction history go through [PosRepository].
//
// Layout:
//   ┌────────────────────────┬──────────────────┐
//   │  Search + catalog grid │  Cart + checkout  │
//   │  (flex 3)              │  (flex 2)         │
//   └────────────────────────┴──────────────────┘

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/print_service.dart' show PrintService;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/searchable_select.dart' show SearchableSelect;
import 'pos_models.dart';
import 'pos_providers.dart';
import 'pos_repository.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  // Barcode-scanner capture (SHORTCOMINGS-FIX 4.3): a hardware scanner
  // behaves like a very fast keyboard — it types the code (≈50 chars/sec)
  // and finishes with Enter. We watch raw key events on a hidden focus
  // node, accumulate characters while they arrive faster than 100ms
  // apart (the human-typing threshold), and treat Enter as scan-complete.
  final _scannerFocusNode = FocusNode(debugLabel: 'pos-scanner');
  final _scanBuffer = StringBuffer();
  DateTime? _lastScanKeyAt;
  DateTime? _scanStartedAt;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onScannerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Enter = scan complete → resolve the buffered code in the catalog.
    // Only treated as a scan when the whole code arrived in one fast
    // burst (<1s from first keystroke): a human typing a search term
    // then pressing Enter leaves an old/partial buffer and must keep
    // the normal Enter behavior.
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final code = _scanBuffer.toString();
      final isFastScan = _scanStartedAt != null &&
          DateTime.now().difference(_scanStartedAt!) <
              const Duration(seconds: 1);
      _scanBuffer.clear();
      _lastScanKeyAt = null;
      _scanStartedAt = null;
      if (code.isNotEmpty && isFastScan) {
        _completeScan(code);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // plain Enter in a field
    }

    final char = event.character;
    if (char == null || char.isEmpty) return KeyEventResult.ignored;

    final now = DateTime.now();
    final gap = _lastScanKeyAt == null
        ? Duration.zero
        : now.difference(_lastScanKeyAt!);
    _lastScanKeyAt = now;
    // Gap > 100ms → a human is typing (or a new scan started) — reset.
    if (gap > const Duration(milliseconds: 100)) {
      _scanBuffer.clear();
      _scanStartedAt = now;
    } else {
      _scanStartedAt ??= now;
    }
    _scanBuffer.write(char);
    // Never swallow the key: manual search must keep working — the same
    // characters land in the focused TextField via normal input.
    return KeyEventResult.ignored;
  }

  Future<void> _completeScan(String code) async {
    final l10n = AppLocalizations.of(context)!;
    final item = await ref.read(posScannerLookupProvider)(code);
    if (!mounted) return;
    if (item == null) {
      showAppToast(
        context,
        '${l10n.posItemNotFound} "${code.trim()}"',
        isError: true,
      );
      return;
    }
    _addToCart(item);
    // Leave the scan out of the manual search box.
    if (_searchController.text.trim() == code.trim()) {
      _searchController.clear();
      ref.invalidate(posCatalogProvider);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      // Force rebuild with the new search — the catalog is client-filtered.
      ref.invalidate(posCatalogProvider);
    });
  }

  // ── Cart actions ────────────────────────────────────────────────────────

  void _addToCart(PosItem item) {
    final cart = ref.read(posCartProvider);
    final existing = cart.indexWhere((c) => c.item.id == item.id);
    if (existing >= 0) {
      final old = cart[existing];
      if (old.quantity >= item.currentStock) return; // out of stock
      final updated = [...cart];
      updated[existing] = PosCartItem(
        item: old.item,
        quantity: old.quantity + 1,
        unitPrice: old.unitPrice,
      );
      ref.read(posCartProvider.notifier).state = updated;
    } else {
      ref.read(posCartProvider.notifier).state = [
        ...cart,
        PosCartItem(
          item: item,
          quantity: 1,
          unitPrice: item.standardSellingPrice?.toDouble() ?? 0,
        ),
      ];
    }
  }

  void _removeFromCart(int index) {
    final cart = ref.read(posCartProvider);
    final updated = [...cart]..removeAt(index);
    ref.read(posCartProvider.notifier).state = updated;
  }

  void _updateQty(int index, int delta) {
    final cart = ref.read(posCartProvider);
    final old = cart[index];
    final newQty = old.quantity + delta;
    if (newQty <= 0) {
      _removeFromCart(index);
      return;
    }
    if (newQty > old.item.currentStock) return;
    final updated = [...cart];
    updated[index] = PosCartItem(
      item: old.item,
      quantity: newQty,
      unitPrice: old.unitPrice,
    );
    ref.read(posCartProvider.notifier).state = updated;
  }

  void _updatePrice(int index, double price) {
    final cart = ref.read(posCartProvider);
    final old = cart[index];
    final updated = [...cart];
    updated[index] = PosCartItem(
      item: old.item,
      quantity: old.quantity,
      unitPrice: price,
    );
    ref.read(posCartProvider.notifier).state = updated;
  }

  void _clearCart() {
    ref.read(posCartProvider.notifier).state = const [];
    ref.read(posCashReceivedProvider.notifier).state = 0;
    ref.read(posCustomerNameProvider.notifier).state = '';
  }

  num get _subtotal =>
      ref.read(posCartProvider).fold(0, (sum, c) => sum + c.lineTotal);

  // ── Sale commit ────────────────────────────────────────────────────────

  Future<void> _commitSale() async {      final cart = ref.read(posCartProvider);
    final warehouseId = ref.read(posWarehouseProvider);
    final cashReceived = ref.read(posCashReceivedProvider);

    if (cart.isEmpty) {
      showAppToast(context, 'Cart is empty', isError: true);
      return;
    }
    if (warehouseId == null) {
      showAppToast(context, 'Select a warehouse', isError: true);
      return;
    }
    if (cashReceived < _subtotal) {
      showAppToast(context, 'Cash received is less than total', isError: true);
      return;
    }

    ref.read(posSubmittingProvider.notifier).state = true;
    try {
      final repo = ref.watch(posRepositoryProvider);
      final saleDate = ref.watch(posSaleDateProvider) ?? DateTime.now();
      final result = await repo.createSale(
        warehouseId: warehouseId,
        saleDate: DateFormat('yyyy-MM-dd').format(saleDate),
        items: [
          for (final c in cart)
            {
              'item_id': c.item.id,
              'quantity': c.quantity,
              'unit_price': c.unitPrice,
            },
        ],
        cashReceived: cashReceived,
        customerName: ref.read(posCustomerNameProvider),
      );

      if (!mounted) return;

      switch (result) {
        case ApiSuccess(:final data):
          ref.read(posLastSaleProvider.notifier).state = data;
          showAppToast(context, 'Sale completed: ${data.transactionNo}');
          _clearCart();
          ref.invalidate(posTransactionsProvider);
          // Offer print receipt.
          _showReceiptDialog(data);
        case ApiFailure(:final error):
          showAppToast(context, error.message, isError: true);
      }
    } finally {
      ref.read(posSubmittingProvider.notifier).state = false;
    }
  }

  void _showReceiptDialog(PosSale sale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sale Completed'),
        content: Text('Transaction: ${sale.transactionNo}\n'
            'Total: ${Formatters.currency(sale.total)}\n'
            'Change: ${Formatters.currency(sale.change)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await PrintService(context).printPosReceipt(sale);
            },
            child: Text('Print Receipt'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // A Focus that wraps the whole POS pane and holds the scanner capture:
    // key events bubble to it from whichever field is focused, so hardware
    // scans work even while the search box has focus.
    return Focus(
      focusNode: _scannerFocusNode,
      // Holds focus when the POS pane is active so a hardware scanner's
      // keystrokes land here (spec 4.3: captured when the POS screen is
      // focused). Clicking a field moves focus there — manual typing
      // still works, and scans finish with Enter in either case because
      // key events bubble to this ancestor Focus.
      autofocus: true,
      onKeyEvent: _onScannerKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Toolbar row: warehouse + date + customer + actions.
          _buildToolbar(l10n, scheme),
          const SizedBox(height: 8),
          // Main split layout.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: catalog search + grid.
                Expanded(flex: 3, child: _buildCatalog(l10n, scheme)),
                const SizedBox(width: 8),
                // Right: cart + checkout.
                SizedBox(width: 380, child: _buildCartPanel(l10n, scheme)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────────

  Widget _buildToolbar(AppLocalizations l10n, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.point_of_sale, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            'Point of Sale',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          // Warehouse picker.
          SizedBox(
            width: 180,
            child: _WarehousePicker(),
          ),
          const SizedBox(width: 12),
          // Sale date.
          SizedBox(
            width: 140,
            child: _DateField(),
          ),
          const SizedBox(width: 12),
          // Customer name.
          SizedBox(
            width: 180,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Customer (optional)',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) =>
                  ref.read(posCustomerNameProvider.notifier).state = v,
            ),
          ),
        ],
      ),
    );
  }

  // ── Catalog ────────────────────────────────────────────────────────────

  Widget _buildCatalog(AppLocalizations l10n, ColorScheme scheme) {
    final catalogAsync = ref.watch(posCatalogProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search field.
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search items...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 10),
          // Item grid.
          Expanded(
            child: catalogAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load catalog',
                        style: TextStyle(color: scheme.error)),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => ref.invalidate(posCatalogProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) {
                final query = _searchController.text.trim().toLowerCase();
                final filtered = query.isEmpty
                    ? items
                    : items
                        .where((i) =>
                            i.itemName.toLowerCase().contains(query) ||
                            i.itemCode.toLowerCase().contains(query))
                        .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(l10n.commonNoresults,
                        style: TextStyle(color: scheme.outline)),
                  );
                }
                return GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) =>
                      _ItemCard(item: filtered[i], onTap: () => _addToCart(filtered[i])),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Cart panel ─────────────────────────────────────────────────────────

  Widget _buildCartPanel(AppLocalizations l10n, ColorScheme scheme) {
    final cart = ref.watch(posCartProvider);
    final submitting = ref.watch(posSubmittingProvider);
    final total = cart.fold<num>(0, (sum, c) => sum + c.lineTotal);
    final cashReceived = ref.watch(posCashReceivedProvider);
    final change = cashReceived - total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cart header.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: scheme.primaryContainer,
              child: Row(
                children: [
                  Icon(Icons.shopping_cart, size: 20, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Text(
                    'Cart (${cart.length} items)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  if (cart.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      tooltip: 'Clear cart',
                      onPressed: _clearCart,
                    ),
                ],
              ),
            ),
            // Cart items list.
            Expanded(
              child: cart.isEmpty
                  ? Center(
                      child: Text(
                        'Add items from the catalog',
                        style: TextStyle(color: scheme.outline),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: cart.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (ctx, i) => _CartRow(
                        item: cart[i],
                        index: i,
                        onRemove: () => _removeFromCart(i),
                        onIncrement: () => _updateQty(i, 1),
                        onDecrement: () => _updateQty(i, -1),
                        onPriceChanged: (p) => _updatePrice(i, p),
                      ),
                    ),
            ),
            const Divider(height: 1),
            // Totals.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  _totalRow('Subtotal', Formatters.currency(total)),
                  const SizedBox(height: 8),
                  TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Cash received',
                      prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) {
                      final amount = double.tryParse(v) ?? 0;
                      ref.read(posCashReceivedProvider.notifier).state = amount;
                    },
                  ),
                  const SizedBox(height: 4),
                  _totalRow(
                    'Change',
                    Formatters.currency(change < 0 ? 0 : change),
                    bold: true,
                    color: change < 0 ? scheme.error : scheme.primary,
                  ),
                ],
              ),
            ),
            // Checkout button.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                onPressed: (cart.isEmpty || submitting) ? null : _commitSale,
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 20),
                label: Text(submitting ? 'Processing...' : 'Complete Sale'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: color)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onTap});
  final PosItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outOfStock = item.currentStock <= 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.itemName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Text(
                Formatters.currency(item.standardSellingPrice ?? 0),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                outOfStock ? 'Out of stock' : 'Stock: ${item.currentStock}',
                style: TextStyle(
                  fontSize: 11,
                  color: outOfStock ? scheme.error : scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.item,
    required this.index,
    required this.onRemove,
    required this.onIncrement,
    required this.onDecrement,
    required this.onPriceChanged,
  });

  final PosCartItem item;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<double> onPriceChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        item.item.itemName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Row(
        children: [
          // Qty controls.
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onDecrement,
          ),
          Text('${item.quantity}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onIncrement,
          ),
          const SizedBox(width: 8),
          Text(
            Formatters.currency(item.lineTotal),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(Icons.close, size: 16, color: scheme.error),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: onRemove,
      ),
    );
  }
}

// ── Warehouse picker ──────────────────────────────────────────────────────

class _WarehousePicker extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(posWarehousesProvider);
    final selectedId = ref.watch(posWarehouseProvider);

    return warehousesAsync.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (e, _) => Text('Warehouses: $e',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
      data: (warehouses) {
        if (warehouses.isEmpty) {
          return const Text('No warehouses');
        }
        final selected = warehouses
            .cast<PosWarehouse?>()
            .firstWhere((w) => w?.id == selectedId, orElse: () => null);
        return SearchableSelect<PosWarehouse>(
          items: warehouses,
          selected: selected,
          hint: 'Warehouse',
          labelBuilder: (w) => w.warehouseName ?? w.warehouseCode,
          onChanged: (w) {
            ref.read(posWarehouseProvider.notifier).state = w?.id;
          },
        );
      },
    );
  }
}

// ── Date field ────────────────────────────────────────────────────────────

class _DateField extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(posSaleDateProvider) ?? DateTime.now();
    final formatted = DateFormat('yyyy-MM-dd').format(date);

    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) {
          ref.read(posSaleDateProvider.notifier).state = picked;
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: 'Date',
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(formatted, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
