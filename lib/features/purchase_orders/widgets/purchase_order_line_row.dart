// Purchase-order line editor row — the item picker plus the quantity,
// unit-price and input-tax fields, the calculated amount, the optional
// expiry date and the remove action.
//
// The parent owns the line state and the text controllers; this widget only
// renders them and reports edits back through callbacks.

import 'package:flutter/material.dart';

import '../../../core/utils/date_utils.dart' show isoDate;
import '../../../core/utils/formatters.dart';
import '../../../data/models/item.dart' show Item;
import '../../../l10n/app_localizations.dart';
import '../../../widgets/form_helpers.dart' show formInputDecoration;
import '../../../widgets/searchable_select.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

class PurchaseOrderLineRow extends StatelessWidget {
  const PurchaseOrderLineRow({
    super.key,
    required this.index,
    required this.items,
    required this.selectedItemId,
    required this.quantityController,
    required this.priceController,
    required this.taxController,
    required this.amount,
    required this.expiryDate,
    required this.submitting,
    required this.canRemove,
    required this.onItemChanged,
    required this.onValueChanged,
    required this.onRemove,
    required this.onPickExpiry,
  });

  /// Position of this line in the form — used for the input-tax field key.
  final int index;

  /// Selectable items offered by the picker.
  final List<Item> items;

  /// Currently selected item id as a string (empty when nothing is picked).
  final String selectedItemId;

  final TextEditingController quantityController;
  final TextEditingController priceController;
  final TextEditingController taxController;

  /// Calculated line amount (quantity × unit price).
  final num amount;

  /// Optional expiry date for expiry-tracked items.
  final DateTime? expiryDate;

  /// True while the form is submitting — fields and actions are disabled.
  final bool submitting;

  /// False for the last remaining line, which cannot be removed.
  final bool canRemove;

  /// Reports the newly selected item id (empty string when cleared).
  final ValueChanged<String> onItemChanged;

  /// Reports that a numeric field changed.
  final VoidCallback onValueChanged;

  final VoidCallback onRemove;
  final VoidCallback onPickExpiry;

  InputDecoration get _fieldDecoration =>
      const InputDecoration(isDense: true, border: OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final selectedItem = items
        .where((i) => i.id.toString() == selectedItemId)
        .firstOrNull;
    final showExpiry = selectedItem?.hasExpiry == true;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: SearchableSelect<int>(
                items: [for (final i in items) i.id],
                selected: selectedItemId.isEmpty
                    ? null
                    : int.tryParse(selectedItemId),
                labelBuilder: (id) {
                  final match = items.where((i) => i.id == id);
                  final item = match.isEmpty ? null : match.first;
                  return item == null
                      ? '$id'
                      : '${item.itemCode} — ${item.itemName}';
                },
                decoration: formInputDecoration(),
                onChanged: (value) => onItemChanged(value?.toString() ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: TextFormField(
                controller: quantityController,
                enabled: !submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _fieldDecoration,
                validator: (value) => (double.tryParse(value ?? '') ?? -1) > 0
                    ? null
                    : l10n.commonRequired,
                onChanged: (_) => onValueChanged(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextFormField(
                controller: priceController,
                enabled: !submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _fieldDecoration,
                validator: (value) => (double.tryParse(value ?? '') ?? -1) > 0
                    ? null
                    : l10n.commonRequired,
                onChanged: (_) => onValueChanged(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: Container(
                height: 42,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: AppBorderRadius.smRadius,
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                child: Text(
                  Formatters.currency(amount),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 34,
              child: IconButton(
                tooltip: l10n.commonRemove,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                onPressed: submitting || !canRemove ? null : onRemove,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey('po-input-tax-$index'),
          controller: taxController,
          enabled: !submitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: formInputDecoration().copyWith(
            labelText: l10n.supplierBillInputTax,
          ),
          validator: (value) {
            final amount = num.tryParse(value?.trim() ?? '');
            return amount == null || !amount.isFinite || amount < 0
                ? l10n.commonRequired
                : null;
          },
          onChanged: (_) => onValueChanged(),
        ),
        if (showExpiry) ...[
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              height: 38,
              child: OutlinedButton.icon(
                onPressed: submitting ? null : onPickExpiry,
                icon: const Icon(Icons.calendar_today_outlined, size: 15),
                label: Text(
                  expiryDate != null
                      ? Formatters.date(isoDate(expiryDate!))
                      : l10n.expirySelectDateOptional,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
