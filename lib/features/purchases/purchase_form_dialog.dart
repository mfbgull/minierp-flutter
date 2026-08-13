// New-purchase dialog — opened from the Purchases tab toolbar. Records a
// direct purchase via `POST /purchases` (repo.create): the server writes
// the purchase row and posts the stock movement. Required fields map 1:1
// to the backend's `recordPurchase` validation (item, warehouse,
// quantity, unit cost, purchase date).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart'
    show ErrorBanner, formInputDecoration, submitOnEnter;
import '../../widgets/searchable_select.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../inventory/inventory_providers.dart'
    show itemsProvider, warehousesProvider;
import 'purchase_providers.dart' show purchasesProvider;

/// Opens the new-purchase dialog (create only).
Future<void> showPurchaseFormDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _PurchaseFormDialog(),
  );
}

class _PurchaseFormDialog extends ConsumerStatefulWidget {
  const _PurchaseFormDialog();

  @override
  ConsumerState<_PurchaseFormDialog> createState() =>
      _PurchaseFormDialogState();
}

class _PurchaseFormDialogState extends ConsumerState<_PurchaseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _costController = TextEditingController();
  int? _itemId;
  int? _warehouseId;
  DateTime _purchaseDate = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _purchaseDate);
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(purchaseRepositoryProvider).create(
          itemId: _itemId!,
          warehouseId: _warehouseId!,
          quantity: num.parse(_qtyController.text.trim()),
          unitCost: num.parse(_costController.text.trim()),
          purchaseDate: isoDate(_purchaseDate),
        );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(purchasesProvider);
        showAppToast(context, l10n.purchasesNewpurchase);
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
                Text(
                  l10n.purchasesRecordnewpurchase,
                  style: Theme.of(context).textTheme.titleMedium,
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
                    ),
                    decoration: formInputDecoration(),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) return l10n.commonRequired;
                      final qty = num.tryParse(raw);
                      if (qty == null || qty <= 0) {
                        return l10n.commonRequired;
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.purchasesUnitcost,
                  required: true,
                  child: TextFormField(
                    controller: _costController,
                    onFieldSubmitted: submitOnEnter(_submit),
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: formInputDecoration(),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) return l10n.commonRequired;
                      final cost = num.tryParse(raw);
                      if (cost == null || cost < 0) return l10n.commonRequired;
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.purchasesPurchasedate,
                  required: true,
                  child: InkWell(
                    onTap: _busy ? null : _pickDate,
                    child: InputDecorator(
                      decoration: formInputDecoration(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isoDate(_purchaseDate)),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
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
                          : const Icon(Icons.add, size: 18),
                      label: Text(l10n.commonSave),
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
