// Item create/edit form — modal dialog over POST/PUT /inventory/items.
//
// Field set + defaults port the zod `itemSchema`
// (schemas/validation-schemas.ts): code/name/UOM required, numeric fields
// coerced and clamped to >= 0, `is_purchased` defaults true, `sale_type`
// is packed|loose. `item_code` is create-only — the server's
// UpdateItemDTO has no code field and create enforces uniqueness with a
// 400 ("Item code already exists") that the form surfaces verbatim.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/item.dart' show Item, SaleType;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import 'inventory_providers.dart';

/// Opens the create ([item] == null) or edit form dialog.
Future<void> showItemFormDialog(BuildContext context, {Item? item}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => ItemFormDialog(item: item),
  );
}

class ItemFormDialog extends ConsumerStatefulWidget {
  const ItemFormDialog({super.key, this.item});

  /// Null → create; otherwise pre-fills and PUTs to `items/:id`.
  final Item? item;

  @override
  ConsumerState<ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends ConsumerState<ItemFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _reorderController;
  late final TextEditingController _costController;
  late final TextEditingController _priceController;

  String? _category;
  String? _uom;
  SaleType _saleType = SaleType.packed;
  bool _isRawMaterial = false;
  bool _isFinishedGood = false;
  bool _isPurchased = true;
  bool _isManufactured = false;
  bool _hasExpiry = false;
  late TextEditingController _thresholdController;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _codeController = TextEditingController(text: item?.itemCode ?? '');
    _nameController = TextEditingController(text: item?.itemName ?? '');
    _descriptionController = TextEditingController(
      text: item?.description ?? '',
    );
    _reorderController = TextEditingController(
      text: numText(item?.reorderLevel ?? 0),
    );
    _costController = TextEditingController(
      text: numText(item?.standardCost ?? 0),
    );
    _priceController = TextEditingController(
      text: numText(item?.standardSellingPrice ?? 0),
    );
    _category = item?.category;
    _uom = item?.unitOfMeasure;
    _saleType = item?.saleType ?? SaleType.packed;
    _isRawMaterial = item?.isRawMaterial ?? false;
    _isFinishedGood = item?.isFinishedGood ?? false;
    _isPurchased = item?.isPurchased ?? true;
    _isManufactured = item?.isManufactured ?? false;
    _hasExpiry = item?.hasExpiry ?? false;
    _thresholdController = TextEditingController(
      text: numText(item?.nearExpiryThresholdDays ?? 30),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _reorderController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  /// The dropdowns' items always include the current value so a pre-filled
  /// edit form never loses a value the loaded list doesn't contain.
  List<String> _withCurrent(List<String> loaded, String? current) {
    if (current == null || loaded.contains(current)) return loaded;
    return [...loaded, current];
  }

  Map<String, dynamic> _buildBody() {
    return {
      if (!_isEdit) 'item_code': _codeController.text.trim(),
      'item_name': _nameController.text.trim(),
      if (_descriptionController.text.trim().isNotEmpty)
        'description': _descriptionController.text.trim(),
      if (_category != null && _category!.isNotEmpty) 'category': _category,
      // Guaranteed non-null: the field's required validator runs before
      // the body is built.
      'unit_of_measure': _uom!,
      'reorder_level': double.parse(_reorderController.text),
      'standard_cost': double.parse(_costController.text),
      'standard_selling_price': double.parse(_priceController.text),
      'is_raw_material': _isRawMaterial,
      'is_finished_good': _isFinishedGood,
      'is_purchased': _isPurchased,
      'is_manufactured': _isManufactured,
      'sale_type': _saleType.value,
      'has_expiry': _hasExpiry,
      if (_hasExpiry && _thresholdController.text.isNotEmpty)
        'near_expiry_threshold_days': int.parse(_thresholdController.text),
    };
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(inventoryRepositoryProvider);
    final result = _isEdit
        ? await repo.update(widget.item!.id, _buildBody())
        : await repo.create(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        // Refresh the grid; if editing, also refresh the (possibly open)
        // detail dialog's data for this item.
        if (_isEdit) ref.invalidate(itemDetailProvider(widget.item!.id));
        ref.invalidate(itemsProvider);
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final categories = ref.watch(itemCategoriesProvider);
    final uoms = ref.watch(itemUomsProvider);
    String? validateNumber(String? v) => nonNegativeNumberValidator(
      v,
      emptyMessage: l10n.inventoryRequired,
      invalidMessage: l10n.inventoryErrorNumber,
      nonNegativeMessage: l10n.inventoryErrorNonnegative,
    );

    final categoryItems = _withCurrent(
      categories.valueOrNull ?? const [],
      _category,
    );
    final uomItems = _withCurrent(uoms.valueOrNull ?? const [], _uom);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEdit
                            ? l10n.inventoryEdititem
                            : l10n.inventoryNewitem,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_isEdit)
                        FormFieldShell(
                          label: l10n.inventoryItemcode,
                          required: true,
                          child: TextFormField(
                            controller: _codeController,
                            onFieldSubmitted: submitOnEnter(_submit),
                            autofocus: true,
                            enabled: !_submitting,
                            decoration: formInputDecoration(),
                            validator: (v) => requiredValidator(
                              v,
                              l10n.inventoryErrorCodeRequired,
                            ),
                          ),
                        ),
                      FormFieldShell(
                        label: l10n.inventoryItemname,
                        required: true,
                        child: TextFormField(
                          controller: _nameController,
                          onFieldSubmitted: submitOnEnter(_submit),
                          enabled: !_submitting,
                          decoration: formInputDecoration(),
                          validator: (v) => requiredValidator(
                            v,
                            l10n.inventoryErrorNameRequired,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.inventoryCategory,
                              child: SearchableSelect<String>(
                                items: categoryItems,
                                selected: _category,
                                labelBuilder: (v) => v,
                                enabled: !_submitting,
                                onChanged: (v) => setState(() => _category = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.inventoryUom,
                              required: true,
                              child: SearchableSelect<String>(
                                items: uomItems,
                                selected: _uom,
                                labelBuilder: (v) => v,
                                enabled: !_submitting,
                                onChanged: (v) => setState(() => _uom = v),
                                validator: (v) => requiredValidator(
                                  v,
                                  l10n.inventoryErrorUomRequired,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.inventoryReorderlevel,
                              child: TextFormField(
                                controller: _reorderController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: formInputDecoration(),
                                validator: validateNumber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.inventoryStandardcost,
                              child: TextFormField(
                                controller: _costController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: formInputDecoration(),
                                validator: validateNumber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.inventorySellingprice,
                              child: TextFormField(
                                controller: _priceController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: formInputDecoration(),
                                validator: validateNumber,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.inventorySaletype,
                        child: SearchableSelect<String>(
                          items: const ['packed', 'loose'],
                          selected: _saleType.value,
                          labelBuilder: (v) => v == 'packed'
                              ? l10n.inventorySaletypePacked
                              : l10n.inventorySaletypeLoose,
                          enabled: !_submitting,
                          onChanged: (v) => setState(() {
                            _saleType = SaleType.fromString(v);
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FormFieldShell(
                        label: l10n.inventoryItemtype,
                        child: Column(
                          children: [
                            _flagRow(
                              l10n.inventoryRawmaterials,
                              _isRawMaterial,
                              (v) => setState(() => _isRawMaterial = v),
                              l10n.inventoryFinishedgoods,
                              _isFinishedGood,
                              (v) => setState(() => _isFinishedGood = v),
                            ),
                            const SizedBox(height: 4),
                            _flagRow(
                              l10n.inventoryPurchased,
                              _isPurchased,
                              (v) => setState(() => _isPurchased = v),
                              l10n.inventoryManufacturedproducts,
                              _isManufactured,
                              (v) => setState(() => _isManufactured = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.expiryTracking,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                l10n.trackExpiryDates,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              value: _hasExpiry,
                              onChanged: _submitting
                                  ? null
                                  : (v) => setState(() => _hasExpiry = v),
                            ),
                            if (_hasExpiry) ...[
                              const SizedBox(height: 8),
                              FormFieldShell(
                                label: l10n.nearExpiryThreshold,
                                child: TextFormField(
                                  controller: _thresholdController,
                                  enabled: !_submitting,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: false,
                                  ),
                                  decoration: formInputDecoration(),
                                  validator: (v) {
                                    if (!_hasExpiry) return null;
                                    final n = int.tryParse(v?.trim() ?? '');
                                    if (n == null || n <= 0) {
                                      return l10n.inventoryErrorNonnegative;
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.commonDescription,
                        child: TextFormField(
                          controller: _descriptionController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 4,
                          decoration: formInputDecoration(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      ErrorBanner(message: _error!),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(l10n.commonCancel),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.commonSave),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flagRow(
    String leftLabel,
    bool leftValue,
    ValueChanged<bool> onLeft,
    String rightLabel,
    bool rightValue,
    ValueChanged<bool> onRight,
  ) {
    Widget checkbox(String label, bool value, ValueChanged<bool> onChanged) =>
        Expanded(
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            value: value,
            onChanged: _submitting ? null : (v) => onChanged(v ?? false),
          ),
        );
    return Row(
      children: [
        checkbox(leftLabel, leftValue, onLeft),
        checkbox(rightLabel, rightValue, onRight),
      ],
    );
  }
}
