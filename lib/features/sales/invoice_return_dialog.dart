// Invoice return-processing dialog — the sales-return flow for an
// invoice (`POST /invoices/:id/return`). Opened from the invoice edit
// form's Process Return action. Fetches the fresh invoice detail (so
// `returned_qty` is current), collects a per-line return quantity (capped
// at each line's remaining returnable quantity), an optional reason and
// the disposition (refund/credit/adjust — defaulted to the server's
// rule: refund when paid off, otherwise credit). On success it
// invalidates the invoices list and the returns-history grid — the
// invoice's returned_amount/status refetch, and the new return appears
// in the Returns tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart'
    show Invoice, InvoiceItem;
import '../../data/models/sales_return.dart';
import '../../data/models/stock_batch.dart' show StockBatch;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show InvoiceFilters, invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import '../inventory/inventory_providers.dart' show warehousesProvider;
import 'invoice_providers.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';
import 'invoice_return_providers.dart' show invoiceReturnsProvider;

/// Opens the return-processing dialog for [invoiceId].
Future<void> showInvoiceReturnDialog(
  BuildContext context, {
  required int invoiceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => InvoiceReturnDialog(invoiceId: invoiceId),
  );
}

class InvoiceReturnDialog extends ConsumerStatefulWidget {
  const InvoiceReturnDialog({super.key, required this.invoiceId});

  final int invoiceId;

  @override
  ConsumerState<InvoiceReturnDialog> createState() =>
      _InvoiceReturnDialogState();
}

class _InvoiceReturnDialogState extends ConsumerState<InvoiceReturnDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _feeValueController = TextEditingController();

  /// Lines that still have something to return, with one qty controller
  /// per line (parallel lists — both rebuilt on load).
  List<InvoiceItem> _returnableItems = const [];
  final List<TextEditingController> _qtyControllers = [];

  /// The warehouse the returned goods are restocked into — required
  /// (invoices never record one, so the user must choose).
  int? _warehouseId;

  /// Return date (spec §5.1 / D14) — `yyyy-MM-dd`, defaults to today
  /// and the server posts ledger entries dated today regardless.
  String _returnDate = DateTime.now().toIso8601String().substring(0, 10);

  /// Restocking-fee selector (spec §3.6 / D5 — always charged, clamped
  /// to the returned value by the server).
  String _feeType = 'none';

  /// The invoice's live position (spec §4.2) — the starting point the
  /// preview adds this return's figures onto.
  InvoicePosition? _position;

  /// Settlement builder (spec §5.2 / D4): allocate the net return now,
  /// or leave the return Unsettled for later ("record return only").
  bool _settleNow = false;
  final List<_SettlementDraft> _allocations = [];

  /// Open invoices of the same customer — pickers for `adjust`
  /// allocations (D7 — the server auto-picks the oldest unpaid when
  /// none is supplied, but the user may target one explicitly).
  List<Invoice> _targetOptions = const [];

  bool _submitting = false;
  bool _loading = true;
  String? _loadError;
  String? _error;

  /// Per-item batch breakdown (batch → location quantities) for the
  /// collapsible "batches" chip on each line — informational, filled
  /// only when the server feature flag `feature_batch_locations` is on.
  final Map<int, List<StockBatch>> _batchesByItem = {};
  final Map<int, bool> _expandedBatches = {};

  /// Cached invoice (customer id for adjust-target loading).
  Invoice? _customer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _feeValueController.dispose();
    for (final a in _allocations) {
      a.amountController.dispose();
    }
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ref
        .read(invoiceRepositoryProvider)
        .invoice(widget.invoiceId);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _loading = false;
          final items = data.items ?? const <InvoiceItem>[];
          _returnableItems = [
            for (final item in items)
              if (item.quantity - item.returnedQty > 0) item,
          ];
          for (final c in _qtyControllers) {
            c.dispose();
          }
          _qtyControllers
            ..clear()
            ..addAll([
              for (final _ in _returnableItems) TextEditingController(),
            ]);
          _customer = data;
          _position = data.position;
          // Default the settlement step to "unsettled" unless this
          // return actually creates a refund/credit entitlement (spec
          _settleNow = _postRefundDue > 0;
        });
        _loadTargets();
      case ApiFailure(:final error):
        setState(() {
          _loading = false;
          _loadError = error.message;
        });
    }
  }


  /// Open invoices of the same customer — pickers for `adjust`
  /// allocations. Fire-and-forget; the server auto-picks the oldest
  /// unpaid invoice when none is supplied (D7), so this is optional.
  Future<void> _loadTargets() async {
    final customerId = _customer?.customerId;
    if (customerId == null) return;
    final result = await ref
        .read(invoiceRepositoryProvider)
        .invoices(filters: InvoiceFilters(customerId: customerId));

    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        setState(() => _targetOptions = data);
      case ApiFailure():
        break; // Informational — adjust falls back to auto-pick.
    }
  }
  /// Gross (tax-inclusive) returned value of the filled lines —
  /// `computeReturnedLine` on the server: proportional split of the
  /// line's net and tax, full-return snapped to ratio 1.
  double _lineReturnedGross(InvoiceItem item, num qty) {
    final q = item.quantity;
    if (q <= 0 || qty <= 0) return 0;
    final ratio = qty >= q - 1e-9 ? 1.0 : qty / q;
    final net = item.amount.toDouble();
    final tax = (net * item.taxRate.toDouble() / 100).roundToDouble();
    return (ratio * net).roundToDouble() + (ratio * tax).roundToDouble();
  }

  double get _grossReturnNow {
    var total = 0.0;
    for (var i = 0; i < _returnableItems.length; i++) {
      final item = _returnableItems[i];
      final qty = double.tryParse(_qtyControllers[i].text.trim()) ?? 0;
      total += _lineReturnedGross(item, qty);
    }
    return total;
  }

  /// `resolveFee` on the server: percentage fees take the tax-inclusive
  /// returned value as base; everything clamps to the returned value.
  double get _feeAmount {
    final base = _grossReturnNow;
    final value = double.tryParse(_feeValueController.text.trim()) ?? 0;
    if (_feeType == 'none' || value <= 0) return 0;
    final raw = _feeType == 'percentage' ? base * (value / 100) : value;
    return raw < base ? raw : base;
  }

  double get _netAmount => _grossReturnNow - _feeAmount;

  /// Post-return position (spec §3.2) — this return's figures added on
  /// top of the invoice's live `position` (server is authoritative).
  InvoicePosition _postPosition() {
    final p = _position;
    final originalTotal = p?.originalTotal ?? 0;
    final totalPaid = p?.totalPaid ?? 0;
    final totalSettled = p?.totalSettled ?? 0;
    final totalReturned = (p?.totalReturned ?? 0) + _grossReturnNow;
    final totalFees = (p?.totalFees ?? 0) + _feeAmount;
    final currentInvoiceValue =
        originalTotal - totalReturned < 0 ? 0.0 : originalTotal - totalReturned;
    final netPosition = totalPaid - currentInvoiceValue - totalFees;
    final refundCreditDue = netPosition > 0 ? netPosition : 0.0;
    final balanceDue = netPosition < 0 ? -netPosition : 0.0;
    final remainingRefundDue =
        refundCreditDue - totalSettled < 0 ? 0.0 : refundCreditDue - totalSettled;
    return InvoicePosition(
      originalTotal: originalTotal,
      totalReturned: totalReturned,
      currentInvoiceValue: currentInvoiceValue,
      totalPaid: totalPaid,
      totalFees: totalFees,
      netPosition: netPosition,
      refundCreditDue: refundCreditDue,
      totalSettled: totalSettled,
      remainingRefundDue: remainingRefundDue,
      balanceDue: balanceDue,
      remainingSettlementCapacity: remainingRefundDue,
      settledAmount: totalSettled,
    );
  }

  num get _postRefundDue => _postPosition().refundCreditDue;
  num get _postBalanceDue => _postPosition().balanceDue;

  /// Σ allocation amounts in the settlement builder.
  double get _allocationsTotal {
    var total = 0.0;
    for (final a in _allocations) {
      total += double.tryParse(a.amountController.text.trim()) ?? 0;
    }
    return total;
  }

  /// True when the batch fits both limits the server enforces: the
  /// return's own net remainder and the invoice's cumulative cap
  /// (spec §3.4 / D18 — all types share one pool).
  bool get _allocationsFit =>
      _allocationsTotal <= _netAmount + 0.005 &&
      _allocationsTotal <= _postPosition().remainingSettlementCapacity + 0.005;

  /// Recompute the live return totals from the filled qty fields.
  /// Rebuild the live position preview (the getters read the qty
  /// controllers directly, so only a repaint is needed).
  void _recalc() => setState(() {});

  /// Add one settlement allocation to the builder, prefilled with the
  /// remaining net amount so the common case (single full refund) is
  /// one click (§6.1 Option A).
  void _addAllocation() {
    final remainder = _netAmount - _allocationsTotal;
    setState(() {
      _allocations.add(
        _SettlementDraft(
          type: 'refund',
          amountController: TextEditingController(
            text: remainder > 0.005
                ? remainder.toStringAsFixed(2)
                : '',
          ),
        ),
      );
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_warehouseId == null) {
      setState(() => _error = l10n.salesreturnsReturnwarehouserequired);
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _returnableItems.length; i++) {
      final qty = double.tryParse(_qtyControllers[i].text.trim()) ?? 0;
      if (qty > 0) {
        items.add({
          'invoice_item_id': _returnableItems[i].id,
          'return_quantity': qty,
        });
      }
    }
    if (items.isEmpty) {
      setState(() => _error = l10n.salesreturnsReturnqtyinvalid);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final settlements = <Map<String, dynamic>>[];
    if (_settleNow && _postRefundDue > 0) {
      for (final a in _allocations) {
        final amount = double.tryParse(a.amountController.text.trim()) ?? 0;
        if (amount <= 0) continue;
        settlements.add({
          'type': a.type,
          'amount': amount,
          if (a.type == 'refund' && a.method != null) 'method': a.method,
          if (a.type == 'adjust' && a.targetInvoiceId != null)
            'target_invoice_id': a.targetInvoiceId,
        });
      }
    }

    final result = await ref
        .read(invoiceRepositoryProvider)
        .processReturn(
          widget.invoiceId,
          items: items,
          feeType: _feeType,
          feeValue: double.tryParse(_feeValueController.text.trim()),
          returnDate: _returnDate,
          reason: _reasonController.text,
          warehouseId: _warehouseId,
          settlements: settlements,
        );
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        ref.invalidate(invoicesProvider);
        ref.invalidate(invoiceReturnsProvider);

        showAppToast(
          context,
          '${l10n.salesreturnsReturnprocessed} — '
          '${Formatters.currency(data.netAmount)}',
        );
        if (data.returnNo != null) {
          showAppToast(context, '${l10n.salesreturnsReturnno}: ${data.returnNo}');
        }
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
    final scheme = Theme.of(context).colorScheme;

    return MovableDialog(
      dialogId: 'invoice_return',
      maxWidth: 560,
      maxHeight: 640,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.salesreturnsReturntitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.salesreturnsReturnsubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Flexible(child: _buildBody(l10n)),
            ],
          ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          ErrorBanner(message: _loadError!),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonClose),
            ),
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Restock warehouse — the returned goods come back into the
            // warehouse the user picks (invoices don't track one).
            FormFieldShell(
              label: l10n.salesreturnsReturnwarehouse,
              required: true,
              child: _WarehousePicker(
                selected: _warehouseId,
                enabled: !_submitting,
                onChanged: (id) => setState(() => _warehouseId = id),
              ),
            ),
            // Batch-aware restock note — shown only when the server
            // sends per-location batch data (feature flag on): the
            // server restocks the returned quantity into the chosen
            // warehouse's DEFAULT location row for each original batch.
            if (_batchesByItem.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Returned stock is restocked into the chosen '
                'warehouse\'s DEFAULT location for each original '
                'batch.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_returnableItems.isEmpty) ...[
              Text(
                l10n.salesreturnsReturnnoitems,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              for (var i = 0; i < _returnableItems.length; i++) ...[
                if (i > 0) const Divider(height: 12),
                _ReturnLineRow(
                  item: _returnableItems[i],
                  controller: _qtyControllers[i],
                  autofocus: i == 0,
                  enabled: !_submitting,
                  onChanged: _recalc,
                  onSubmit: _submit,
                  batches: _batchesByItem[_returnableItems[i].itemId],
                  expanded: _expandedBatches[_returnableItems[i].id] ?? false,
                  onToggleExpanded: () => setState(() {
                    final lineId = _returnableItems[i].id;
                    _expandedBatches[lineId] =
                        !(_expandedBatches[lineId] ?? false);
                  }),
                ),
              ],
            ],
            if (_grossReturnNow > 0) ...[
              const SizedBox(height: 10),
              _PositionPreview(
                grossReturn: _grossReturnNow,
                fee: _feeAmount,
                net: _netAmount,
                position: _postPosition(),
              ),
              const SizedBox(height: 12),
              // Settlement (§5.2 / D4): allocate the net return now, or
              // leave it Unsettled — the server auto-marks Not Required
              // when there is nothing to refund (unpaid invoice).
              FormFieldShell(
                label: l10n.salesreturnsSettlement,
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.salesreturnsSettleNow),
                  subtitle: Text(
                    _postRefundDue > 0.005
                        ? l10n.salesreturnsRefundsplit
                        : l10n.salesreturnsRecordOnlyHint,
                  ),
                  value: _settleNow,
                  onChanged: _submitting || _postRefundDue <= 0.005
                      ? null
                      : (v) => setState(() => _settleNow = v),
                ),
              ),
              if (_settleNow) ...[
                if (!_allocationsFit) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.salesreturnsSettleExceeds,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                for (var i = 0; i < _allocations.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _SettlementRow(
                    draft: _allocations[i],
                    enabled: !_submitting,
                    targetOptions: _targetOptions,
                    onRemove: () => setState(() {
                      _allocations[i].amountController.dispose();
                      _allocations.removeAt(i);
                    }),
                    onChanged: _recalc,
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _submitting ? null : _addAllocation,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(l10n.salesreturnsSettleAdd),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            // Return date (§5.1 / D14): today by default; back-dated
            // returns inside a CLOSED accounting period are rejected by
            // the server (D23) — today is always allowed.
            FormFieldShell(
              label: l10n.salesreturnsReturndate,
              child: InkWell(
                onTap: _submitting
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.tryParse(_returnDate) ??
                              DateTime.now(),
                          firstDate:
                              DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now(),
                        );
                        if (picked == null) return;
                        setState(() =>
                            _returnDate = picked.toIso8601String().substring(0, 10));
                      },
                child: InputDecorator(
                  decoration: formInputDecoration(),
                  child: Row(
                    children: [
                      const Icon(Icons.event, size: 16),
                      const SizedBox(width: 6),
                      Text(_returnDate),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Restocking fee (§3.6 / D5 — always charged, clamped to the
            // returned value server-side; on an unpaid invoice it just
            // increases the Balance Due).
            FormFieldShell(
              label: l10n.salesreturnsFee,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SearchableSelect<String>(
                      items: const ['none', 'fixed', 'percentage'],
                      selected: _feeType,
                      labelBuilder: (value) => switch (value) {
                        'fixed' => l10n.salesreturnsFeeFixed,
                        'percentage' => l10n.salesreturnsFeePercentage,
                        _ => l10n.salesreturnsFeeNone,
                      },
                      enabled: !_submitting,
                      decoration: formInputDecoration(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _feeType = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _feeValueController,
                      enabled: !_submitting && _feeType != 'none',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _recalc(),
                      onFieldSubmitted: submitOnEnter(_submit),
                      decoration: formInputDecoration(
                        hintText: l10n.salesreturnsFeeValue,
                      ).copyWith(
                        suffixText: _feeType == 'percentage' ? '%' : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_postBalanceDue > 0.005 && _feeAmount > 0) ...[
              const SizedBox(height: 6),
              Text(
                l10n.salesreturnsFeeNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton.icon(
                  onPressed: _submitting || _returnableItems.isEmpty
                      ? null
                      : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.assignment_return_outlined, size: 18),
                  label: Text(l10n.salesreturnsReturn),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One returnable invoice line: item name/code + available qty on the
/// left, return-quantity input on the right.
class _ReturnLineRow extends StatelessWidget {
  const _ReturnLineRow({
    required this.item,
    required this.controller,
    required this.autofocus,
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
    this.batches,
    this.expanded = false,
    this.onToggleExpanded,
  });

  final InvoiceItem item;
  final TextEditingController controller;

  /// Batch-location breakdown for this line's item — shown via the
  /// collapsible "batches" chip when non-empty (feature flag).
  final List<StockBatch>? batches;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  /// Focuses the first return-qty field on open — the quantities are the
  /// dialog's primary input.
  final bool autofocus;
  final bool enabled;

  /// Fired on every edit so the parent can recompute the refund/credit
  /// split summary.
  final VoidCallback onChanged;

  /// Enter-to-submit: pressing Enter on a filled line processes the
  /// return (same [submitOnEnter] contract as the other dialogs).
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final available = item.quantity - item.returnedQty;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final hasBatches = batches != null && batches!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.itemName ?? '',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      if (hasBatches) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: onToggleExpanded,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  expanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                                Text(
                                  'batches',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if ((item.itemCode ?? '').isNotEmpty)
                    Text(item.itemCode!, style: muted),
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.salesreturnsAvailableqty}: '
                    '${Formatters.number(available)}',
                    style: muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
        SizedBox(
          width: 130,
          child: FormFieldShell(
            label: l10n.salesreturnsReturnquantity,
            child: TextFormField(
              controller: controller,
              autofocus: autofocus,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onChanged(),
              onFieldSubmitted: submitOnEnter(onSubmit),
              decoration: formInputDecoration(
                hintText: Formatters.number(available),
              ),
              // Empty lines are optional; a filled line must be a valid,
              // non-negative quantity within the available amount.
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return null;
                final qty = double.tryParse(text);
                if (qty == null || qty <= 0) {
                  return l10n.salesreturnsReturnqtyinvalid;
                }
                if (qty > available) {
                  return l10n.salesreturnsReturnqtyexceeds;
                }
                return null;
              },
            ),
          ),
        ),
          ],
        ),
        if (hasBatches && expanded) ...[
          const SizedBox(height: 4),
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final batch in batches!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch.batchNo,
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        for (final loc in batch.locations!)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 1),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    loc.locationCode,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Phys: ${Formatters.number(loc.quantityPhysical)}',
                                    textAlign: TextAlign.end,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Avail: ${Formatters.number(loc.quantityAvailable)}',
                                    textAlign: TextAlign.end,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Restock-warehouse select for the return dialog — a required picker
/// over `GET /inventory/warehouses` with a hint until the user chooses.
class _WarehousePicker extends ConsumerWidget {
  const _WarehousePicker({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final int? selected;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];
    return SearchableSelect<int>(
      items: [for (final w in warehouses) w.id],
      selected: selected,
      hint: l10n.salesreturnsReturnwarehouserequired,
      isDense: true,
      enabled: enabled,
      labelBuilder: (id) {
        final match = warehouses.where((w) => w.id == id);
        return match.isEmpty
            ? '$id'
            : match.first.warehouseName ?? match.first.warehouseCode;
      },
      decoration: formInputDecoration(),
      onChanged: onChanged,
    );
  }
}

/// Live position preview for the return dialog (spec §6.1 / §3.2):
/// Returned Value, Restocking Fee, Net, and the POST-return Balance
/// Due and Refund/Credit Due — both always shown, mirroring the
/// server's `computePosition` exactly (D12).
class _PositionPreview extends StatelessWidget {
  const _PositionPreview({
    required this.grossReturn,
    required this.fee,
    required this.net,
    required this.position,
  });

  final double grossReturn;
  final double fee;
  final double net;
  final InvoicePosition position;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    final bold =
        Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.salesreturnsPositionReturned, style: muted),
              Text(Formatters.currency(grossReturn), style: bold),
            ],
          ),
          if (fee > 0.005)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.salesreturnsFee, style: muted),
                Text(Formatters.currency(fee), style: bold),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.salesreturnsPositionNet, style: muted),
              Text(Formatters.currency(net), style: bold),
            ],
          ),
          const Divider(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.salesreturnsPositionBalanceDue, style: muted),
              Text(
                Formatters.currency(position.balanceDue),
                style: bold?.copyWith(
                  color: position.balanceDue > 0.005 ? scheme.error : muted?.color,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.salesreturnsPositionRefundDue, style: muted),
              Text(
                Formatters.currency(position.refundCreditDue),
                style: bold?.copyWith(
                  color: position.refundCreditDue > 0.005
                      ? scheme.tertiary
                      : muted?.color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One editable settlement allocation (spec §5.2): type picker, amount,
/// and per-type context — method for refunds, target invoice for
/// adjustments (D7 — the server auto-picks the oldest unpaid when
/// omitted; credit needs nothing extra).
class _SettlementRow extends StatelessWidget {
  const _SettlementRow({
    required this.draft,
    required this.enabled,
    required this.targetOptions,
    required this.onRemove,
    required this.onChanged,
  });

  final _SettlementDraft draft;
  final bool enabled;
  final List<Invoice> targetOptions;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: SearchableSelect<String>(
            items: const ['refund', 'credit', 'adjust'],
            selected: draft.type,
            labelBuilder: (value) => switch (value) {
              'refund' => l10n.salesreturnsDispositionrefund,
              'credit' => l10n.salesreturnsDispositioncredit,
              _ => l10n.salesreturnsDispositionadjust,
            },
            enabled: enabled,
            decoration: formInputDecoration(),
            onChanged: (value) {
              if (value != null) {
                draft.type = value;
                onChanged();
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: draft.amountController,
            enabled: enabled,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onChanged(),
            decoration: formInputDecoration(hintText: l10n.salesreturnsFeeValue),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: draft.type == 'refund'
              ? SearchableSelect<String>(
                  items: const ['cash', 'bank', 'card'],
                  selected: draft.method ?? 'cash',
                  labelBuilder: (value) => value.toUpperCase(),
                  enabled: enabled,
                  decoration: formInputDecoration(
                    hintText: l10n.salesreturnsSettleMethod,
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      draft.method = value;
                      onChanged();
                    }
                  },
                )
              : draft.type == 'adjust'
                  ? SearchableSelect<int>(
                      items: [for (final inv in targetOptions) inv.id],
                      selected: draft.targetInvoiceId,
                      labelBuilder: (id) {
                        final match =
                            targetOptions.where((inv) => inv.id == id);
                        return match.isEmpty
                            ? '#$id'
                            : '${match.first.invoiceNo} '
                                '· ${Formatters.currency(match.first.balanceAmount)}';
                      },
                      enabled: enabled,
                      decoration: formInputDecoration(
                        hintText: l10n.salesreturnsSettleTarget,
                      ),
                      onChanged: (value) {
                        draft.targetInvoiceId = value;
                        onChanged();
                      },
                    )
                  : const SizedBox.shrink(),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          onPressed: enabled ? onRemove : null,
        ),
      ],
    );
  }
}

/// Mutable settlement-allocation draft for the dialog's builder.
class _SettlementDraft {
  _SettlementDraft({required this.type, required this.amountController});

  /// 'refund' | 'credit' | 'adjust' (spec §5.2).
  String type;

  /// Refund method — 'cash' | 'bank' | 'card' (D8), refunds only.
  String? method;

  /// Explicit target for adjustments (D7 — null = oldest unpaid auto).
  int? targetInvoiceId;
  final TextEditingController amountController;
}
