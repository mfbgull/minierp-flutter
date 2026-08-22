// Stock-transfer dialog — opened from the Stock Movements tab toolbar.
// INV-02: a transfer is ONE atomic server operation (`POST
// /inventory/stock-transfers`). The server consumes FIFO cost layers at
// the source warehouse, mirrors a TRANSFER batch at the destination and
// writes both movements inside a single transaction — a failure leaves no
// partial-transfer state behind.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/detail_labels.dart' show detailSectionLabel;
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart'
    show ErrorBanner, formInputDecoration, submitOnEnter;
import '../../widgets/searchable_select.dart';
import 'inventory_providers.dart'
    show
        allItemsProvider,
        movementTypeFilterProvider,
        stockBalancesProvider,
        stockMovementsProvider,
        warehousesProvider;

/// Opens the stock-transfer dialog (create only).
Future<void> showStockTransferDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _StockTransferDialog(),
  );
}

class _StockTransferDialog extends ConsumerStatefulWidget {
  const _StockTransferDialog();

  @override
  ConsumerState<_StockTransferDialog> createState() =>
      _StockTransferDialogState();
}

class _StockTransferDialogState extends ConsumerState<_StockTransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _remarksController = TextEditingController();
  int? _itemId;
  int? _sourceId;
  int? _destId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String? _validateQty(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return l10n.commonRequired;
    final qty = num.tryParse(raw);
    if (qty == null) return l10n.stockmovementsAdjustmentinvalid;
    if (qty <= 0) return l10n.stockmovementsTransferpositive;
    return null;
  }

  String? _validateDest(int? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null) return l10n.commonRequired;
    if (value == _sourceId) return l10n.stockmovementsTransferdiff;
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final remarks = _remarksController.text.trim();
    final qty = num.parse(_qtyController.text.trim());
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(inventoryRepositoryProvider);

    // INV-02: one atomic server call. FIFO consumption at the source, a
    // mirrored TRANSFER batch at the destination and both movements are
    // written inside a single transaction — no partial-transfer state.
    final result = await repo.createStockTransfer({
      'item_id': _itemId!,
      'from_warehouse_id': _sourceId!,
      'to_warehouse_id': _destId!,
      'quantity': qty,
      if (remarks.isNotEmpty) 'remarks': remarks,
    });
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(
          stockMovementsProvider(ref.read(movementTypeFilterProvider)),
        );
        ref.invalidate(stockBalancesProvider);
        showAppToast(context, l10n.stockmovementsTransfermsg);
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(allItemsProvider).valueOrNull ?? const [];
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];

    String warehouseLabel(int id) {
      final match = warehouses.where((w) => w.id == id);
      final name = match.isEmpty ? null : match.first.warehouseName;
      return name ?? '$id';
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                detailSectionLabel(context, l10n.stockmovementsNewtransfer),
                const SizedBox(height: 4),
                Text(
                  l10n.stockmovementsTransfersubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                FormFieldShell(
                  label: l10n.fieldsItem,
                  required: true,
                  child: SearchableSelect<int>(
                    items: [for (final item in items) item.id],
                    selected: _itemId,
                    labelBuilder: (id) {
                      final match = items.where((i) => i.id == id);
                      return match.isEmpty
                          ? '$id'
                          : '${match.first.itemCode} — ${match.first.itemName}';
                    },
                    onChanged: (value) => setState(() => _itemId = value),
                    validator: (v) => v == null ? l10n.commonRequired : null,
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.stockmovementsTransferfrom,
                  required: true,
                  child: SearchableSelect<int>(
                    items: [for (final w in warehouses) w.id],
                    selected: _sourceId,
                    labelBuilder: warehouseLabel,
                    onChanged: (value) => setState(() => _sourceId = value),
                    validator: (v) => v == null ? l10n.commonRequired : null,
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.stockmovementsTransferto,
                  required: true,
                  child: SearchableSelect<int>(
                    items: [for (final w in warehouses) w.id],
                    selected: _destId,
                    labelBuilder: warehouseLabel,
                    onChanged: (value) => setState(() => _destId = value),
                    validator: _validateDest,
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.fieldsQuantity,
                  required: true,
                  child: TextFormField(
                    controller: _qtyController,
                    onFieldSubmitted: submitOnEnter(_submit),
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: formInputDecoration(),
                    validator: _validateQty,
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.stockmovementsAdjustmentreason,
                  child: TextFormField(
                    controller: _remarksController,
                    enabled: !_busy,
                    maxLines: 2,
                    decoration: formInputDecoration(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.swap_horiz, size: 18),
                      label: Text(l10n.stockmovementsTransfersave),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
