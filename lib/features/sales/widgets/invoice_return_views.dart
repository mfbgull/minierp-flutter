// Views for the invoice return dialog: the per-line return-quantity row and
// the live position preview.

import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/invoice.dart' show InvoiceItem;
import '../../../data/models/sales_return.dart' show InvoicePosition;
import '../../../data/models/stock_batch.dart' show StockBatch;
import '../../../l10n/app_localizations.dart';
import '../../../widgets/form_field.dart';
import '../../../widgets/form_helpers.dart';

/// One returnable invoice line: item name/code + available qty on the
/// left, return-quantity input on the right.
class InvoiceReturnLineRow extends StatelessWidget {
  const InvoiceReturnLineRow({
    super.key,
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
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
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
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
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
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
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

/// Live position preview for the return dialog (spec §6.1 / §3.2):
/// Returned Value, Restocking Fee, Net, and the POST-return Balance
/// Due and Refund/Credit Due — both always shown, mirroring the
/// server's `computePosition` exactly (D12).
class InvoiceReturnPositionPreview extends StatelessWidget {
  const InvoiceReturnPositionPreview({
    super.key,
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
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final bold = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

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
                  color: position.balanceDue > 0.005
                      ? scheme.error
                      : muted?.color,
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
