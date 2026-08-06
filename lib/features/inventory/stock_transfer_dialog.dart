// Stock-transfer dialog — opened from the Stock Movements tab toolbar.
// The server has no two-warehouse transfer endpoint: a transfer is two
// `TRANSFER` movements (the schema keeps one signed `warehouse_id` per
// row) — a negative OUT from the source warehouse, then a positive IN to
// the destination. The incoming leg's `reference_docno` carries the
// outgoing movement's server-generated number, linking the pair.
//
//   POST /inventory/stock-movements  {warehouse_id: source, quantity: -q}
//   POST /inventory/stock-movements  {warehouse_id: dest,   quantity: +q,
//                                     reference_docno: <out movement_no>}
//
// If the OUT leg fails (e.g. 'Insufficient stock') nothing is recorded;
// if the IN leg fails the OUT leg is already on the server, so the error
// banner prefixes that fact (the retry must not re-post the OUT leg).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/detail_labels.dart' show detailSectionLabel;
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart' show ErrorBanner, formInputDecoration;
import '../../widgets/searchable_select.dart';
import 'inventory_providers.dart'
    show
        itemsProvider,
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

  /// The outgoing leg's movement number once it is on the server. Kept
  /// across an incoming-leg failure so a retry re-posts only the IN leg
  /// (never a second OUT).
  String? _outMovementNo;

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

    // Leg 1 — OUT of the source warehouse. Nothing is recorded if this
    // fails (the server validates the balance for negative quantities).
    // Skipped on retry after an incoming-leg failure: [_outMovementNo]
    // is already set, so only the IN leg re-posts.
    if (_outMovementNo == null) {
      final out = await repo.createStockMovement({
        'item_id': _itemId!,
        'warehouse_id': _sourceId!,
        'quantity': -qty,
        'movement_type': 'TRANSFER',
        'reference_doctype': 'TRANSFER',
        if (remarks.isNotEmpty) 'remarks': remarks,
      });
      if (!mounted) return;

      switch (out) {
        case ApiSuccess(:final data):
          _outMovementNo = data.movementNo;
        case ApiFailure(:final error):
          setState(() {
            _busy = false;
            _error = error.message;
          });
          return;
      }
    }

    // Leg 2 — IN to the destination, linked to the outgoing movement.
    final incoming = await repo.createStockMovement({
      'item_id': _itemId!,
      'warehouse_id': _destId!,
      'quantity': qty,
      'movement_type': 'TRANSFER',
      'reference_doctype': 'TRANSFER',
      'reference_docno': _outMovementNo!,
      if (remarks.isNotEmpty) 'remarks': remarks,
    });
    if (!mounted) return;

    switch (incoming) {
      case ApiSuccess():
        ref.invalidate(
          stockMovementsProvider(ref.read(movementTypeFilterProvider)),
        );
        ref.invalidate(stockBalancesProvider);
        showAppToast(context, l10n.stockmovementsTransfermsg);
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        // The OUT leg is already on the server; flag it so a retry
        // doesn't silently re-post the outgoing movement.
        setState(() {
          _busy = false;
          _error = '${l10n.stockmovementsTransferpartialfail} ${error.message}';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(itemsProvider).valueOrNull ?? const [];
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
