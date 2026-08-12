// Stock-adjustment dialog — opened from the Stock Movements tab toolbar.
// Records a manual `ADJUSTMENT` movement via
// `POST /inventory/stock-movements` (repo.createStockMovement): positive
// quantity = stock in, negative = stock out (the server validates the
// balance for outgoing and 400s with 'Insufficient stock'). The reason
// maps to the movement's `remarks`.

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
        itemsProvider,
        movementTypeFilterProvider,
        stockBalancesProvider,
        stockMovementsProvider,
        warehousesProvider;

/// Opens the stock-adjustment dialog (create only).
Future<void> showStockAdjustmentDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _StockAdjustmentDialog(),
  );
}

class _StockAdjustmentDialog extends ConsumerStatefulWidget {
  const _StockAdjustmentDialog();

  @override
  ConsumerState<_StockAdjustmentDialog> createState() =>
      _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState
    extends ConsumerState<_StockAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _reasonController = TextEditingController();
  int? _itemId;
  int? _warehouseId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String? _validateQty(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return l10n.commonRequired;
    final qty = num.tryParse(raw);
    if (qty == null) return l10n.stockmovementsAdjustmentinvalid;
    if (qty == 0) return l10n.stockmovementsAdjustmentzero;
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final remarks = _reasonController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(inventoryRepositoryProvider)
        .createStockMovement({
          'item_id': _itemId!,
          'warehouse_id': _warehouseId!,
          'quantity': num.parse(_qtyController.text.trim()),
          'movement_type': 'ADJUSTMENT',
          if (remarks.isNotEmpty) 'remarks': remarks,
        });
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(
          stockMovementsProvider(ref.read(movementTypeFilterProvider)),
        );
        ref.invalidate(stockBalancesProvider);
        showAppToast(context, l10n.stockmovementsAdjustmentmsg);
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
    final items = ref.watch(itemsProvider).valueOrNull ?? const [];
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];

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
                detailSectionLabel(context, l10n.stockmovementsNewadjustment),
                const SizedBox(height: 4),
                Text(
                  l10n.stockmovementsAdjustmentsubtitle,
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
                  label: l10n.fieldsWarehouse,
                  required: true,
                  child: SearchableSelect<int>(
                    items: [for (final w in warehouses) w.id],
                    selected: _warehouseId,
                    labelBuilder: (id) {
                      final match = warehouses.where((w) => w.id == id);
                      return match.isEmpty
                          ? '$id'
                          : match.first.warehouseName ??
                                match.first.warehouseCode;
                    },
                    onChanged: (value) => setState(() => _warehouseId = value),
                    validator: (v) => v == null ? l10n.commonRequired : null,
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
                      signed: true,
                    ),
                    decoration: formInputDecoration(
                      hintText: l10n.stockmovementsAdjustmenthint,
                    ),
                    validator: _validateQty,
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.stockmovementsAdjustmentreason,
                  child: TextFormField(
                    controller: _reasonController,
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
                          : const Icon(Icons.tune, size: 18),
                      label: Text(l10n.stockmovementsAdjustmentsave),
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
