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
    show InvoiceItem, InvoicePaymentRecord;
import '../../data/models/stock_batch.dart' show StockBatch;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
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

  /// Lines that still have something to return, with one qty controller
  /// per line (parallel lists — both rebuilt on load).
  List<InvoiceItem> _returnableItems = const [];
  final List<TextEditingController> _qtyControllers = [];

  /// The warehouse the returned goods are restocked into — required
  /// (invoices never record one, so the user must choose).
  int? _warehouseId;

  String _disposition = 'credit';
  bool _submitting = false;
  bool _loading = true;
  String? _loadError;
  String? _error;

  /// What the customer actually collected on this invoice (paid minus
  /// prior refunds). The server caps any cash refund at this amount —
  /// mirrored here so the preview matches what will actually happen.
  double _refundable = 0;

  /// Live per-line return totals (gross return value of filled lines).
  double _grossReturn = 0;

  /// Per-item batch breakdown (batch → location quantities) for the
  /// collapsible "batches" chip on each line — informational, filled
  /// only when the server feature flag `feature_batch_locations` is on.
  final Map<int, List<StockBatch>> _batchesByItem = {};
  final Map<int, bool> _expandedBatches = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
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
        // Collected cash = Σ payment allocations (refund records carry
        // negative amounts) — same math as the server's cap.
        final paymentsResult = await ref
            .read(invoiceRepositoryProvider)
            .invoicePayments(widget.invoiceId);
        var collected = 0.0;
        if (paymentsResult is ApiSuccess<List<InvoicePaymentRecord>>) {
          for (final p in paymentsResult.data) {
            collected += p.amount;
          }
        }
        if (!mounted) return;
        setState(() {
          _loading = false;
          _refundable = collected.clamp(0.0, double.infinity);
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
          // The server's default when no disposition is sent: refund
          // only when the invoice is paid off, credit otherwise.
          _disposition = data.balanceAmount <= 0 ? 'refund' : 'credit';
        });
        _loadBatches();
      case ApiFailure(:final error):
        setState(() {
          _loading = false;
          _loadError = error.message;
        });
    }
  }

  /// Fire-and-forget batch breakdown per returnable item — powers the
  /// collapsible "batches" chip under each line. Empty (chip hidden)
  /// when the server feature flag is off or the item is unbatched.
  Future<void> _loadBatches() async {
    final repo = ref.read(inventoryRepositoryProvider);
    final itemIds = _returnableItems.map((i) => i.itemId).toSet();
    for (final itemId in itemIds) {
      if (_batchesByItem.containsKey(itemId)) continue;
      final result = await repo.getBatches(itemId: itemId);
      if (!mounted) return;
      switch (result) {
        case ApiSuccess(:final data):
          final withLocations = data
              .where((b) => b.locations != null && b.locations!.isNotEmpty)
              .toList();
          if (withLocations.isNotEmpty) {
            setState(() => _batchesByItem[itemId] = withLocations);
          }
        case ApiFailure():
          break; // Informational only.
      }
    }
  }

  /// Recompute the live return totals from the filled qty fields.
  void _recalcTotals() {
    var gross = 0.0;
    for (var i = 0; i < _returnableItems.length; i++) {
      final qty = double.tryParse(_qtyControllers[i].text.trim()) ?? 0;
      if (qty > 0) {
        gross += qty * _returnableItems[i].unitPrice;
      }
    }
    setState(() => _grossReturn = gross);
  }

  /// Server mirrors this: refundAmount = min(netReturn, refundable).
  /// Returns (refund, retainedCredit) for the disposition refund, else
  /// the whole amount is a credit/adjustment.
  (double, double) get _refundSplit {
    if (_disposition != 'refund') return (0, _grossReturn);
    final refund = _grossReturn <= 0
        ? 0.0
        : (_grossReturn <= _refundable ? _grossReturn : _refundable);
    return (refund, _grossReturn - refund);
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

    final result = await ref
        .read(invoiceRepositoryProvider)
        .processReturn(
          widget.invoiceId,
          items: items,
          reason: _reasonController.text,
          disposition: _disposition,
          warehouseId: _warehouseId,
        );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        ref.invalidate(invoicesProvider);
        ref.invalidate(invoiceReturnsProvider);
        final refund = data.refundAmount;
        final credit = data.retainedCredit;
        final split = refund > 0 && credit > 0
            ? ' — ${l10n.salesreturnsRefundsplit} '
                '${Formatters.currency(refund)}, '
                '${Formatters.currency(credit)} ${l10n.salesreturnsCreditonsplit}'
            : ' — ${Formatters.currency(data.netReturn)}';
        showAppToast(
          context,
          '${l10n.salesreturnsReturnprocessed}$split',
        );
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
                  onChanged: _recalcTotals,
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
            if (_grossReturn > 0) ...[
              const SizedBox(height: 10),
              _RefundSplitSummary(
                grossReturn: _grossReturn,
                refund: _refundSplit.$1,
                retainedCredit: _refundSplit.$2,
                isCapped:
                    _disposition == 'refund' && _grossReturn > _refundable,
              ),
            ],
            const SizedBox(height: 12),
            FormFieldShell(
              label: l10n.salesreturnsReturnreason,
              child: TextFormField(
                controller: _reasonController,
                enabled: !_submitting,
                onFieldSubmitted: submitOnEnter(_submit),
                decoration: formInputDecoration(
                  hintText: l10n.salesreturnsReturnreasonplaceholder,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FormFieldShell(
              label: l10n.salesreturnsDisposition,
              child: SearchableSelect<String>(
                items: const ['refund', 'credit', 'adjust'],
                selected: _disposition,
                labelBuilder: (value) => switch (value) {
                  'refund' => l10n.salesreturnsDispositionrefund,
                  'credit' => l10n.salesreturnsDispositioncredit,
                  _ => l10n.salesreturnsDispositionadjust,
                },
                enabled: !_submitting,
                decoration: formInputDecoration(),
                onChanged: (value) {
                  if (value != null) setState(() => _disposition = value);
                },
              ),
            ),
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

/// Live refund/credit split preview for the return dialog — mirrors the
/// server's cap (reversal-rules #11): cash refund is limited to what the
/// customer actually collected; the remainder stays as customer credit.
class _RefundSplitSummary extends StatelessWidget {
  const _RefundSplitSummary({
    required this.grossReturn,
    required this.refund,
    required this.retainedCredit,
    required this.isCapped,
  });

  final double grossReturn;
  final double refund;
  final double retainedCredit;
  final bool isCapped;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);

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
              Text(l10n.salesreturnsReturnquantity, style: muted),
              Text(Formatters.currency(grossReturn)),
            ],
          ),
          if (refund > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.salesreturnsRefundsplit, style: muted),
                Text(Formatters.currency(refund)),
              ],
            ),
          if (retainedCredit > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.salesreturnsCreditonsplit, style: muted),
                Text(Formatters.currency(retainedCredit)),
              ],
            ),
          if (isCapped) ...[
            const SizedBox(height: 4),
            Text(
              l10n.salesreturnsRefundcapnote,
              style: muted?.copyWith(
                fontStyle: FontStyle.italic,
                color: scheme.tertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
