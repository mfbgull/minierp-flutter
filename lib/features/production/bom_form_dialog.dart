// BOM create/edit form — modal dialog over the boms API. Create
// posts the header plus the material `items` array in one call (the
// server generates `bom_no` and computes totals). Edit PUTs the
// header; passing `items` makes the server replace the material
// lines wholesale, so there is no per-line reconciliation.
//
// The finished-item picker offers the finished-goods catalog; the
// material pickers offer the full item catalog (BOMs may consume raw
// materials, components or semi-finished goods).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/bom.dart';
import '../../data/models/item.dart' show Item;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/production_repository.dart'
    show productionRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart'
    show ErrorBanner, formInputDecoration, numText, submitOnEnter;
import '../../widgets/searchable_select.dart';
import 'calculations/production_calculations.dart' show bomMaterialCost;
import 'production_providers.dart';

/// Mutable BOM material line.
class _BomLine {
  _BomLine() : quantityController = TextEditingController();

  String itemId = '';
  final TextEditingController quantityController;

  num get quantity => double.tryParse(quantityController.text) ?? 0;

  void dispose() => quantityController.dispose();
}

/// Opens the create ([detail] == null) or edit BOM form dialog.
Future<void> showBomFormDialog(BuildContext context, {BomDetail? detail}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => BomFormDialog(detail: detail),
  );
}

class BomFormDialog extends ConsumerStatefulWidget {
  const BomFormDialog({super.key, this.detail});

  /// Null → create; otherwise pre-fills and edits.
  final BomDetail? detail;

  @override
  ConsumerState<BomFormDialog> createState() => _BomFormDialogState();
}

class _BomFormDialogState extends ConsumerState<BomFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController();
  final List<_BomLine> _lines = [];

  int? _finishedItemId;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.detail != null;

  @override
  void initState() {
    super.initState();
    final detail = widget.detail;
    _nameController.text = detail?.bomName ?? '';
    _descriptionController.text = detail?.description ?? '';
    _quantityController.text = detail == null ? '1' : numText(detail.quantity);
    _finishedItemId = detail?.finishedItemId;
    if (detail != null) {
      for (final item in detail.items) {
        _lines.add(
          _BomLine()
            ..itemId = item.itemId.toString()
            ..quantityController.text = numText(item.quantity),
        );
      }
    }
    if (_lines.isEmpty) _lines.add(_BomLine());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  List<_BomLine> get _filledLines =>
      _lines.where((line) => line.itemId.isNotEmpty).toList();

  List<Item> get _allItems =>
      ref.watch(productionAllItemsProvider).valueOrNull ?? const <Item>[];

  Item? _itemById(int id) {
    for (final item in _allItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Material cost preview — the same formula the server applies to
  /// `total_material_cost` (Σ quantity × standard_cost).
  num get _materialCost => bomMaterialCost([
    for (final line in _filledLines)
      BomItem(
        id: 0,
        itemId: int.parse(line.itemId),
        quantity: line.quantity,
        standardCost: _itemById(int.parse(line.itemId))?.standardCost,
      ),
  ]);

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_finishedItemId == null) {
      setState(() => _error = _l10n.bomErrorFinisheditem);
      return;
    }
    if (_filledLines.isEmpty) {
      setState(() => _error = _l10n.bomErrorItemsrequired);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final description = _descriptionController.text.trim();
    final body = <String, dynamic>{
      'bom_name': _nameController.text.trim(),
      'finished_item_id': _finishedItemId,
      'quantity': double.parse(_quantityController.text.trim()),
      if (description.isNotEmpty) 'description': description,
      'is_active': _isEdit && widget.detail!.isActive ? 1 : 0,
      'items': [
        for (final line in _filledLines)
          {'item_id': int.parse(line.itemId), 'quantity': line.quantity},
      ],
    };

    final repo = ref.read(productionRepositoryProvider);
    final result = _isEdit
        ? await repo.updateBom(widget.detail!.id, body)
        : await repo.createBom(body);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(bomsProvider);
        if (_isEdit) {
          ref.invalidate(bomDetailProvider(widget.detail!.id));
        }
        Navigator.of(context).pop();
        showAppToast(context, _l10n.bomSaved);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final finishedItems =
        ref.watch(productionOutputItemsProvider).valueOrNull ?? const <Item>[];
    final materialCost = _materialCost;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 680),
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
                        _isEdit ? l10n.bomEdittitle : l10n.bomNewbom,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
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
                      if (_error != null) ...[
                        ErrorBanner(message: _error!),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.bomName,
                              required: true,
                              child: TextFormField(
                                controller: _nameController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                autofocus: true,
                                enabled: !_submitting,
                                decoration: formInputDecoration(),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? l10n.commonRequired
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.bomFinisheditem,
                              required: true,
                              child: SearchableSelect<int>(
                                items: [for (final i in finishedItems) i.id],
                                selected: _finishedItemId,
                                labelBuilder: (id) {
                                  for (final i in finishedItems) {
                                    if (i.id == id) {
                                      return '${i.itemCode} — ${i.itemName}';
                                    }
                                  }
                                  return '$id';
                                },
                                validator: (v) =>
                                    v == null ? l10n.commonRequired : null,
                                onChanged: (value) =>
                                    setState(() => _finishedItemId = value),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 130,
                            child: FormFieldShell(
                              label: l10n.bomQuantity,
                              required: true,
                              child: TextFormField(
                                controller: _quantityController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: formInputDecoration(),
                                validator: (v) =>
                                    (double.tryParse(v ?? '') ?? -1) > 0
                                    ? null
                                    : l10n.commonRequired,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FormFieldShell(
                        label: l10n.bomDescription,
                        child: TextFormField(
                          controller: _descriptionController,
                          enabled: !_submitting,
                          decoration: formInputDecoration(),
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.bomMaterials,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _submitting
                                ? null
                                : () => setState(() => _lines.add(_BomLine())),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(l10n.bomAddmaterial),
                          ),
                        ],
                      ),
                      for (var i = 0; i < _lines.length; i++) _lineRow(l10n, i),
                      const SizedBox(height: 12),
                      _MaterialCostBar(l10n: l10n, cost: materialCost),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check, size: 18),
                      label: Text(l10n.commonSave),
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

  Widget _lineRow(AppLocalizations l10n, int index) {
    final line = _lines[index];
    final item = line.itemId.isEmpty ? null : _itemById(int.parse(line.itemId));
    final lineCost = line.quantity * (item?.standardCost ?? 0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: FormFieldShell(
              label: l10n.fieldsItem,
              child: SearchableSelect<int>(
                items: [for (final i in _allItems) i.id],
                selected: line.itemId.isEmpty ? null : int.parse(line.itemId),
                labelBuilder: (id) {
                  final match = _itemById(id);
                  return match == null
                      ? '$id'
                      : '${match.itemCode} — ${match.itemName}';
                },
                onChanged: (value) =>
                    setState(() => line.itemId = value?.toString() ?? ''),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: FormFieldShell(
              label: l10n.productionInputqty,
              required: true,
              child: TextFormField(
                controller: line.quantityController,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: formInputDecoration(),
                validator: (value) {
                  final v = double.tryParse(value ?? '');
                  if (v == null || v <= 0) return l10n.commonRequired;
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FormFieldShell(
              label: l10n.bomUnitcost,
              child: Container(
                height: 44,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  Formatters.currency(item?.standardCost ?? 0),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FormFieldShell(
              label: l10n.fieldsAmount,
              child: Container(
                height: 44,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  Formatters.currency(lineCost),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 34,
            child: IconButton(
              tooltip: l10n.commonRemove,
              icon: const Icon(Icons.close, size: 16),
              onPressed: _submitting || _lines.length <= 1
                  ? null
                  : () => setState(() {
                      line.dispose();
                      _lines.removeAt(index);
                    }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live material-cost bar under the BOM materials table.
class _MaterialCostBar extends StatelessWidget {
  const _MaterialCostBar({required this.l10n, required this.cost});

  final AppLocalizations l10n;
  final num cost;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            l10n.bomMaterialcost,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const Spacer(),
          Text(
            Formatters.currency(cost),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
