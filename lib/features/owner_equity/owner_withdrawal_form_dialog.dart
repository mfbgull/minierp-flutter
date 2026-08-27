// Owner withdrawal create/edit form — modal over POST/PUT
// /owner-equity/withdrawals.
//
// Two kinds (fixed after create):
//  - Cash: amount + payment method; posts Dr 3300 / Cr cash-per-method.
//  - Goods: user-entered item/warehouse/quantity lines. The value is
//    ALWAYS server-calculated from actual FIFO/FEFO batch costs — the
//    quote endpoint only previews it, and the client never sends a cost
//    or amount. Insufficient-stock/funds errors surface in the banner.
//
// Void lives here too (edit mode): destructive confirm → DELETE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/expense.dart' show ExpenseOption;
import '../../data/models/item.dart' show Item;
import '../../data/models/owner_equity.dart'
    show OwnerWithdrawal, WithdrawalQuote;
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/owner_equity_repository.dart'
    show ownerEquityRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show warehousesProvider;
import 'owner_equity_providers.dart';

import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the create ([entry] == null) or edit form dialog.
Future<void> showOwnerWithdrawalFormDialog(
  BuildContext context, {
  OwnerWithdrawal? entry,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => OwnerWithdrawalFormDialog(entry: entry),
  );
}

/// One editable goods line: item + warehouse + quantity. [name] keeps the
/// pre-filled edit label visible even before the items list loads.
class _GoodsLine {
  _GoodsLine({this.itemId, this.name, this.warehouseId, String? qtyText})
    : qtyController = TextEditingController(text: qtyText ?? '');
  final TextEditingController qtyController;
  int? itemId;
  String? name;
  int? warehouseId;

  void dispose() => qtyController.dispose();
}

class OwnerWithdrawalFormDialog extends ConsumerStatefulWidget {
  const OwnerWithdrawalFormDialog({super.key, this.entry});

  /// Null → create; otherwise pre-fills and PUTs to `withdrawals/:id`.
  final OwnerWithdrawal? entry;

  @override
  ConsumerState<OwnerWithdrawalFormDialog> createState() =>
      _OwnerWithdrawalFormDialogState();
}

class _OwnerWithdrawalFormDialogState
    extends ConsumerState<OwnerWithdrawalFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  late bool _isGoodsKind;
  String? _paymentMethod;
  late DateTime _withdrawalDate;
  List<_GoodsLine> _goodsLines = [];

  Timer? _quoteDebounce;
  WithdrawalQuote? _quote;
  bool _quoting = false;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _amountController = TextEditingController(
      text: entry == null ? '' : _numText(entry.amount),
    );
    _noteController = TextEditingController(text: entry?.note ?? '');
    _paymentMethod = entry?.paymentMethod;
    _withdrawalDate =
        DateTime.tryParse(entry?.withdrawalDate ?? '') ?? DateTime.now();
    _isGoodsKind = entry?.kind == 'goods';

    if (_isEdit && _isGoodsKind) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEditLines());
    }
  }

  Future<void> _loadEditLines() async {
    final repo = ref.read(ownerEquityRepositoryProvider);
    final result = await repo.withdrawalDetail(widget.entry!.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _goodsLines = [
            for (final item in data.items)
              _GoodsLine(
                itemId: item.itemId,
                name: item.itemName,
                warehouseId: item.warehouseId,
                qtyText: _numText(item.quantity),
              ),
          ];
        });
        _scheduleQuote();
      case ApiFailure(:final error):
        setState(() => _error = error.message);
    }
  }

  @override
  void dispose() {
    _quoteDebounce?.cancel();
    _amountController.dispose();
    _noteController.dispose();
    for (final line in _goodsLines) {
      line.dispose();
    }
    super.dispose();
  }

  static String _numText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  String? _validateAmount(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.equityErrorAmountRequired;
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return l10n.equityErrorAmountInvalid;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _withdrawalDate);
    if (picked == null || !mounted) return;
    setState(() => _withdrawalDate = picked);
  }

  void _scheduleQuote() {
    if (!_isGoodsKind) return;
    _quoteDebounce?.cancel();
    _quoteDebounce = Timer(const Duration(milliseconds: 400), _runQuote);
  }

  Future<void> _runQuote() async {
    final lines = _validLines();
    if (!mounted) return;
    if (lines.isEmpty) {
      setState(() {
        _quote = null;
        _quoting = false;
      });
      return;
    }
    setState(() => _quoting = true);
    final result =
        await ref.read(ownerEquityRepositoryProvider).quoteWithdrawal(lines);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _quote = data;
          _quoting = false;
        });
      case ApiFailure(:final error):
        // Quote failures (e.g. insufficient stock) are informational too —
        // shown via the banner but never block editing.
        setState(() {
          _quote = null;
          _quoting = false;
          _error = error.message;
        });
    }
  }

  List<Map<String, dynamic>> _validLines() => [
    for (final line in _goodsLines)
      if (line.itemId != null &&
          line.warehouseId != null &&
          (double.tryParse(line.qtyController.text) ?? 0) > 0)
        {
          'item_id': line.itemId,
          'warehouse_id': line.warehouseId,
          'quantity': double.parse(line.qtyController.text),
        },
  ];

  Map<String, dynamic> _buildBody() => _isGoodsKind
      ? {
          'withdrawal_date': isoDate(_withdrawalDate),
          'kind': 'goods',
          'items': _validLines(),
          'note': _noteController.text.trim(),
          // `amount` deliberately absent — server-calculated from batch
          // consumption; a client-supplied value is rejected with 400.
        }
      : {
          'withdrawal_date': isoDate(_withdrawalDate),
          'kind': 'cash',
          'amount': double.parse(_amountController.text),
          'payment_method': _paymentMethod,
          'note': _noteController.text.trim(),
        };

  void _invalidateAll() {
    ref
      ..invalidate(ownerWithdrawalsProvider)
      ..invalidate(allOwnerWithdrawalsProvider)
      ..invalidate(equitySummaryProvider);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isGoodsKind && _validLines().isEmpty) {
      setState(() => _error = l10n.equityErrorItemsRequired);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(ownerEquityRepositoryProvider);
    final result = _isEdit
        ? await repo.updateWithdrawal(widget.entry!.id, _buildBody())
        : await repo.createWithdrawal(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        _invalidateAll();
        Navigator.of(context).pop();
        showAppToast(context, l10n.equitySaved);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.equityDeleteconfirmdesc,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(ownerEquityRepositoryProvider)
        .voidWithdrawal(widget.entry!.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        _invalidateAll();
        Navigator.of(context).pop();
        showAppToast(context, l10n.equityVoided);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  // ---- lookups ----------------------------------------------------------

  Item? _itemById(List<Item> list, int? id) {
    for (final i in list) {
      if (i.id == id) return i;
    }
    return null;
  }

  Item? _itemByName(List<Item> list, String? name) {
    if (name == null || name.isEmpty) return null;
    for (final i in list) {
      if (i.itemName == name) return i;
    }
    return null;
  }

  Warehouse? _warehouseById(List<Warehouse> list, int? id) {
    for (final w in list) {
      if (w.id == id) return w;
    }
    return null;
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final paymentMethods = ref.watch(equityPaymentMethodsProvider);
    final items = ref.watch(equityItemsProvider);
    final warehouses = ref.watch(warehousesProvider);

    final paymentItems = [
      for (final o in paymentMethods.valueOrNull ?? const <ExpenseOption>[])
        o.value,
    ];
    if (_paymentMethod != null && !paymentItems.contains(_paymentMethod)) {
      paymentItems.add(_paymentMethod!);
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
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
                            ? l10n.equityEditwithdrawal
                            : l10n.equityNewwithdrawal,
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
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: false,
                            icon: const Icon(Icons.payments_outlined),
                            label: Text(l10n.equityKindcash),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: Text(l10n.equityKindgoods),
                          ),
                        ],
                        selected: {_isGoodsKind},
                        onSelectionChanged: _isEdit
                            ? null // kind is fixed once created
                            : (selection) {
                                setState(() {
                                  _isGoodsKind = selection.first;
                                  _quote = null;
                                  _error = null;
                                });
                                if (_isGoodsKind && _goodsLines.isEmpty) {
                                  _addLine(warehouses.valueOrNull);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.fieldsDate,
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
                                    Formatters.date(isoDate(_withdrawalDate)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.expensesPaymentmethod,
                              child: SearchableSelect<String?>(
                                items: [null, ...paymentItems],
                                selected: _paymentMethod,
                                labelBuilder: (v) => v ?? l10n.commonNone,
                                onChanged: _isGoodsKind
                                    ? null // goods withdrawals move no cash
                                    : (v) =>
                                          setState(() => _paymentMethod = v),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (!_isGoodsKind)
                        FormFieldShell(
                          label: l10n.fieldsAmount,
                          required: true,
                          child: TextFormField(
                            controller: _amountController,
                            onFieldSubmitted: submitOnEnter(_submit),
                            enabled: !_submitting,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _decoration(),
                            validator: _validateAmount,
                          ),
                        )
                      else ...[
                        _goodsLinesHeader(l10n),
                        for (var i = 0; i < _goodsLines.length; i++)
                          _goodsLineRow(l10n, i, items, warehouses),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _submitting
                                  ? null
                                  : () =>
                                        _addLine(warehouses.valueOrNull),
                              icon: const Icon(Icons.add, size: 18),
                              label: Text(l10n.equityAdditem),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _quotePreview(l10n),
                      ],
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.fieldsNote,
                        child: TextFormField(
                          controller: _noteController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 4,
                          decoration: _decoration(),
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
                      children: [
                        if (_isEdit)
                          TextButton.icon(
                            onPressed: _submitting ? null : _delete,
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(l10n.commonDelete),
                          ),
                        const Spacer(),
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

  // ---- goods lines ------------------------------------------------------

  Widget _goodsLinesHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              l10n.equityItemstaken,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: 100,
            child: Text(
              l10n.fieldsQuantity,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _goodsLineRow(
    AppLocalizations l10n,
    int index,
    AsyncValue<List<Item>> items,
    AsyncValue<List<Warehouse>> warehouses,
  ) {
    final line = _goodsLines[index];
    final itemList = items.valueOrNull ?? const <Item>[];
    final warehouseList = warehouses.valueOrNull ?? const <Warehouse>[];
    final selectedName =
        line.itemId != null ? (_itemById(itemList, line.itemId)?.itemName ?? line.name) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: FormFieldShell(
              label: l10n.equityItem,
              required: index == 0,
              child: SearchableSelect<String>(
                key: ValueKey('wd-item-$index-${line.itemId}'),
                items: [
                  for (final i in itemList) i.itemName,
                  if (selectedName != null &&
                      itemList.where((i) => i.itemName == selectedName).isEmpty)
                    selectedName,
                ],
                selected: selectedName,
                labelBuilder: (v) => v,
                onChanged: (name) {
                  final match = _itemByName(itemList, name);
                  setState(() {
                    line.itemId = match?.id;
                    line.name = name;
                    _scheduleQuote();
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FormFieldShell(
              label: l10n.equityWarehouse,
              required: index == 0,
              child: SearchableSelect<int>(
                key: ValueKey('wd-wh-$index'),
                items: [for (final w in warehouseList) w.id],
                selected: line.warehouseId,
                labelBuilder: (id) =>
                    _warehouseById(warehouseList, id)?.warehouseName ?? '#$id',
                onChanged: (id) {
                  setState(() {
                    line.warehouseId = id;
                    _scheduleQuote();
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: FormFieldShell(
              label: l10n.fieldsQuantity,
              required: index == 0,
              child: TextFormField(
                controller: line.qtyController,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => _scheduleQuote(),
                decoration: _decoration(),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.commonDelete,
            onPressed: _submitting
                ? null
                : () {
                    setState(() {
                      line.dispose();
                      _goodsLines.removeAt(index);
                      _scheduleQuote();
                    });
                  },
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
        ],
      ),
    );
  }

  void _addLine(List<Warehouse>? warehouses) {
    // No hard-coded default warehouse: preselect only when exactly one
    // exists, otherwise the user chooses explicitly.
    int? wh;
    if (warehouses != null && warehouses.length == 1) {
      wh = warehouses.first.id;
    }
    setState(() => _goodsLines.add(_GoodsLine(warehouseId: wh)));
  }

  Widget _quotePreview(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final quote = _quote;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppBorderRadius.smRadius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                l10n.equityCostpreview,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (_quoting) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (quote == null)
            Text(
              l10n.equityCostpreviewempty,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            )
          else ...[
            for (final line in quote.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${line.batches.fold<num>(0, (s, b) => s + b.quantity)} × '
                  '${line.batches.map((b) => Formatters.currency(b.unitCost)).join(' → ')}'
                  '   =   ${Formatters.currency(line.total)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Divider(height: 12),
            Row(
              children: [
                Text(
                  l10n.equityCosttotal,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                Text(
                  Formatters.currency(quote.totalCost),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.equityCostatcostnote,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _decoration() => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: AppBorderRadius.smRadius),
  );
}
