// Record-production form — modal dialog over `POST /productions`
// (PORTING.md §13: "record run against BOM — auto-consumes materials,
// posts stock + GL"). The server derives the batch no and actual unit
// cost from FIFO consumption; the client previews cost from each
// item's standard cost and pre-flights material availability against
// the items' total current stock (the server re-validates inside its
// transaction).
//
// Selecting a BOM (whose finished item is the output item) auto-fills
// the input lines scaled to the entered quantity:
// line qty × outputQuantity / bomQuantity. The lines stay
// "BOM-derived" — the preview rescales on output-qty changes — until
// the user edits a line by hand.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/bom.dart';
import '../../data/models/item.dart' show Item;
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/production_repository.dart'
    show productionRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart'
    show ErrorBanner, formInputDecoration, submitOnEnter;
import '../../widgets/searchable_select.dart';
import 'calculations/production_calculations.dart';
import 'production_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// One read-only material row of the production form — derived from
/// the selected BOM (scaled to the entered output quantity) with the
/// item's availability at query time.
class _BomInputRow {
  const _BomInputRow({
    required this.label,
    this.uom,
    required this.requiredQty,
    required this.available,
  });

  final String label;
  final String? uom;
  final num requiredQty;
  final num available;
}

/// Opens the record-production form dialog.
Future<void> showProductionFormDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const ProductionFormDialog(),
  );
}

class ProductionFormDialog extends ConsumerStatefulWidget {
  const ProductionFormDialog({super.key});

  @override
  ConsumerState<ProductionFormDialog> createState() =>
      _ProductionFormDialogState();
}

class _ProductionFormDialogState extends ConsumerState<ProductionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _overheadController = TextEditingController();
  final _remarksController = TextEditingController();

  int? _outputItemId;
  int? _warehouseId;
  int? _rawMaterialsWarehouseId;
  int? _bomId;

  /// The selected BOM's detail (material lines) — fetched on pick.
  BomDetail? _bomDetail;
  late DateTime _productionDate;

  bool _submitting = false;
  String? _error;
  String? _bomWarning;

  @override
  void initState() {
    super.initState();
    _productionDate = DateTime.now();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _overheadController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  List<Item> get _items =>
      ref.watch(productionAllItemsProvider).valueOrNull ?? const <Item>[];

  Item? _itemById(int id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  num get _overhead => double.tryParse(_overheadController.text) ?? 0;

  num get _outputQuantity => double.tryParse(_quantityController.text) ?? 0;

  /// The BOM-derived material needs, scaled to [outputQuantity]
  /// (empty until a BOM is selected).
  List<ProductionInputNeed> get _needs {
    final bom = _bomDetail;
    if (bom == null) return const [];
    return scaleBomInputs(
      items: bom.items,
      bomQuantity: bom.quantity,
      outputQuantity: _outputQuantity,
    );
  }

  /// Item id → available stock: the BOM detail's join wins (it was
  /// read at fetch time), the items list is the fallback.
  Map<int, num> get _availableByItem {
    final map = <int, num>{
      for (final item in _items) item.id: item.currentStock,
    };
    for (final it in _bomDetail?.items ?? const <BomItem>[]) {
      map[it.itemId] = it.currentStock ?? map[it.itemId] ?? 0;
    }
    return map;
  }

  /// Read-only rows for the inputs table — the BOM's material lines
  /// scaled to the entered output quantity, with availability.
  List<_BomInputRow> get _inputRows {
    final bom = _bomDetail;
    if (bom == null) return const [];
    final byId = {for (final it in bom.items) it.itemId: it};
    return [
      for (final need in _needs)
        _BomInputRow(
          label: _bomItemLabel(byId[need.itemId]),
          uom: byId[need.itemId]?.unitOfMeasure,
          requiredQty: need.quantity,
          available: _availableByItem[need.itemId] ?? 0,
        ),
    ];
  }

  String _bomItemLabel(BomItem? item) {
    if (item == null) return '';
    if (item.itemCode.isNotEmpty) return '${item.itemCode} — ${item.itemName}';
    final fallback = _itemById(item.itemId);
    return fallback == null
        ? (item.itemName.isEmpty ? '${item.itemId}' : item.itemName)
        : _itemLabel(fallback);
  }

  /// Live cost preview from the BOM lines + overhead (the web app's
  /// [CostPreview]; the server recomputes from actual FIFO).
  ProductionCostPreview get _preview {
    final unitCosts = <int, num>{};
    for (final it in _bomDetail?.items ?? const <BomItem>[]) {
      if (it.standardCost != null) unitCosts[it.itemId] = it.standardCost!;
    }
    for (final item in _items) {
      unitCosts.putIfAbsent(item.id, () => item.standardCost ?? 0);
    }
    return productionCostPreview(
      inputs: [
        for (final need in _needs)
          ProductionInputNeed(
            itemId: need.itemId,
            quantity: need.quantity,
            unitCost: unitCosts[need.itemId] ?? 0,
          ),
      ],
      overhead: _overhead,
      outputQuantity: _outputQuantity,
    );
  }

  /// Pre-flight availability check against each item's stock; the
  /// server re-checks per-warehouse inside its transaction and is the
  /// source of truth.
  List<MaterialShortfall> get _shortfalls => materialShortfalls(
    needs: _needs,
    available: _availableByItem,
    nameOf: (id) => _itemById(id)?.itemName ?? '$id',
  );

  /// Loads the selected BOM's detail (`GET /boms/:id` — the list rows
  /// carry only aggregates) and applies it when its output matches the
  /// chosen output item; otherwise warns and keeps the lines untouched.
  Future<void> _applyBom(int? bomId) async {
    if (bomId == null) {
      setState(() {
        _bomId = null;
        _bomDetail = null;
        _bomWarning = null;
      });
      return;
    }
    setState(() {
      _bomId = bomId;
      _bomDetail = null;
      _bomWarning = null;
    });
    final result = await ref.read(productionRepositoryProvider).bom(bomId);
    if (!mounted || _bomId != bomId) return;
    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _bomDetail = data;
          final outputOk =
              _outputItemId != null && data.finishedItemId == _outputItemId;
          if (!outputOk) {
            _bomWarning = _outputItemId == null
                ? _l10n.productionBomwarningPickoutput
                : _l10n.productionBomwarningMismatch;
          }
        });
      case ApiFailure(:final error):
        setState(() => _bomWarning = error.message);
    }
  }

  Future<void> _onBomIdChanged(int? value) => _applyBom(value);

  void _onOutputItemChanged(int? itemId) {
    setState(() {
      _outputItemId = itemId;
      final bom = _bomDetail;
      if (bom != null && bom.finishedItemId != itemId) {
        // Drop the stale BOM (its output no longer matches).
        _bomId = null;
        _bomDetail = null;
        _bomWarning = null;
      }
    });
  }

  void _onOutputQuantityChanged() {
    // The input rows and cost preview derive from the output qty —
    // just rebuild.
    setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _productionDate);
    if (picked == null || !mounted) return;
    setState(() => _productionDate = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_outputItemId == null) {
      setState(() => _error = _l10n.productionErrorOutputrequired);
      return;
    }
    if (_warehouseId == null) {
      setState(() => _error = _l10n.productionErrorWarehouserequired);
      return;
    }
    final bom = _bomDetail;
    if (bom == null) {
      setState(() => _error = _l10n.productionErrorBomrequired);
      return;
    }
    final needs = _needs;
    if (needs.isEmpty) {
      setState(() => _error = _l10n.productionErrorInputsrequired);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final remarks = _remarksController.text.trim();
    final payload = <String, dynamic>{
      'output_item_id': _outputItemId,
      'output_quantity': _outputQuantity,
      'warehouse_id': _warehouseId,
      if (_rawMaterialsWarehouseId != null)
        'raw_materials_warehouse_id': _rawMaterialsWarehouseId,
      'production_date': isoDate(_productionDate),
      'bom_id': bom.id,
      if (remarks.isNotEmpty) 'remarks': remarks,
      'overhead_cost': _overhead,
      'input_items': [
        for (final need in needs)
          {'item_id': need.itemId, 'quantity': need.quantity},
      ],
    };

    final result = await ref
        .read(productionRepositoryProvider)
        .createProduction(payload);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(productionsProvider);
        Navigator.of(context).pop();
        showAppToast(context, _l10n.productionSaved);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  String _itemLabel(Item item) => '${item.itemCode} — ${item.itemName}';

  String _warehouseLabel(Warehouse w) => w.warehouseName ?? w.warehouseCode;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final warehouses =
        ref.watch(productionWarehousesProvider).valueOrNull ??
        const <Warehouse>[];
    final outputItems =
        ref.watch(productionOutputItemsProvider).valueOrNull ?? const <Item>[];
    final boms =
        ref.watch(productionBomOptionsProvider).valueOrNull ?? const <Bom>[];
    final shortfalls = _shortfalls;
    final preview = _preview;

    InputDecoration deco() => formInputDecoration();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
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
                        l10n.productionNewproduction,
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
                      if (_bomWarning != null) ...[
                        ErrorBanner(message: _bomWarning!),
                        const SizedBox(height: 12),
                      ],
                      // ── Header: output item / qty / date ──────
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.productionOutputitem,
                              required: true,
                              child: SearchableSelect<int>(
                                items: [for (final i in outputItems) i.id],
                                selected: _outputItemId,
                                labelBuilder: (id) {
                                  for (final i in outputItems) {
                                    if (i.id == id) return _itemLabel(i);
                                  }
                                  return '$id';
                                },
                                validator: (v) => v == null
                                    ? l10n.productionErrorOutputrequired
                                    : null,
                                onChanged: _onOutputItemChanged,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 150,
                            child: FormFieldShell(
                              label: l10n.productionOutputquantity,
                              required: true,
                              child: TextFormField(
                                controller: _quantityController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: deco(),
                                validator: (v) =>
                                    (double.tryParse(v ?? '') ?? -1) > 0
                                    ? null
                                    : l10n.commonRequired,
                                onChanged: (_) =>
                                    setState(_onOutputQuantityChanged),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.commonDate,
                              required: true,
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _submitting ? null : _pickDate,
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    Formatters.date(isoDate(_productionDate)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // ── Warehouses + BOM ───────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.productionWarehouse,
                              required: true,
                              child: SearchableSelect<int>(
                                items: [for (final w in warehouses) w.id],
                                selected: _warehouseId,
                                labelBuilder: (id) {
                                  for (final w in warehouses) {
                                    if (w.id == id) {
                                      return _warehouseLabel(w);
                                    }
                                  }
                                  return '$id';
                                },
                                validator: (v) =>
                                    v == null ? l10n.commonRequired : null,
                                onChanged: (value) =>
                                    setState(() => _warehouseId = value),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.productionRawmaterialsWarehouse,
                              child: SearchableSelect<int>(
                                items: [for (final w in warehouses) w.id],
                                selected: _rawMaterialsWarehouseId,
                                labelBuilder: (id) {
                                  for (final w in warehouses) {
                                    if (w.id == id) {
                                      return _warehouseLabel(w);
                                    }
                                  }
                                  return '$id';
                                },
                                onChanged: (value) => setState(
                                  () => _rawMaterialsWarehouseId = value,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.productionBom,
                              required: true,
                              child: SearchableSelect<int>(
                                items: [for (final b in boms) b.id],
                                selected: _bomId,
                                labelBuilder: (id) {
                                  for (final b in boms) {
                                    if (b.id == id) {
                                      return '${b.bomNo} — ${b.finishedItemName}';
                                    }
                                  }
                                  return '$id';
                                },
                                validator: (v) => v == null
                                    ? l10n.productionErrorBomrequired
                                    : null,
                                onChanged: _onBomIdChanged,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // ── Overhead + remarks ─────────────────────
                      Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: FormFieldShell(
                              label: l10n.productionOverhead,
                              child: TextFormField(
                                controller: _overheadController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: deco(),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FormFieldShell(
                              label: l10n.purchasesRemarks,
                              child: TextFormField(
                                controller: _remarksController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                decoration: deco(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // ── Inputs (read-only, from the selected BOM) ─────
                      const SizedBox(height: 16),
                      Text(
                        l10n.productionInputs,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (_bomDetail == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.productionInputsBomhint,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        _BomInputsTable(rows: _inputRows, l10n: l10n),
                        if (shortfalls.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _ShortfallPanel(shortfalls: shortfalls, l10n: l10n),
                        ],
                      ],
                      const SizedBox(height: 16),
                      Text(
                        l10n.productionCostpreview,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      _CostPreviewRow(preview: preview, l10n: l10n),
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
}

/// The read-only BOM inputs table — item, scaled quantity, UOM, and
/// availability. The material lines are defined by the selected BOM,
/// so the form only displays them (editing happens in the BOM editor).
class _BomInputsTable extends StatelessWidget {
  const _BomInputsTable({required this.rows, required this.l10n});

  final List<_BomInputRow> rows;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: AppBorderRadius.smRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 38,
          dataRowMaxHeight: 44,
          columnSpacing: 28,
          columns: [
            DataColumn(
              label: Text(l10n.fieldsItem),
              columnWidth: const FixedColumnWidth(220),
            ),
            DataColumn(label: Text(l10n.productionInputqty), numeric: true),
            DataColumn(label: Text(l10n.commonUom)),
            DataColumn(label: Text(l10n.productionAvailable), numeric: true),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  DataCell(Text(row.label, overflow: TextOverflow.ellipsis)),
                  DataCell(Text(Formatters.number(row.requiredQty))),
                  DataCell(Text(row.uom ?? '\u2014')),
                  DataCell(
                    Text(
                      Formatters.number(row.available),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: row.available < row.requiredQty
                            ? scheme.error
                            : null,
                      ),
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

/// Material-shortage banner for the production form — informational
/// only; the server re-validates stock inside its transaction.
class _ShortfallPanel extends StatelessWidget {
  const _ShortfallPanel({required this.shortfalls, required this.l10n});

  final List<MaterialShortfall> shortfalls;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: AppBorderRadius.smRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.productionShortfallTitle,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in shortfalls)
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 2),
              child: Text(
                l10n.productionShortfallLine(
                  s.itemName,
                  Formatters.number(s.available),
                  Formatters.number(s.required),
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
        ],
      ),
    );
  }
}

/// The live cost preview tile row (material | overhead | total |
/// per-unit) — the web app's CostPreview panel.
class _CostPreviewRow extends StatelessWidget {
  const _CostPreviewRow({required this.preview, required this.l10n});

  final ProductionCostPreview preview;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String value, {bool emphasize = false}) =>
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: AppBorderRadius.smRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile(
          l10n.productionMaterialcost,
          Formatters.currency(preview.materialCost),
        ),
        tile(l10n.productionOverhead, Formatters.currency(preview.overhead)),
        tile(
          l10n.productionTotalcost,
          Formatters.currency(preview.totalCost),
          emphasize: true,
        ),
        tile(
          l10n.productionCostperunit,
          Formatters.currency(preview.costPerUnit),
        ),
      ],
    );
  }
}
