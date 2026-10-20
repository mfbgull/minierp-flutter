// Row views for the supplier payment modal: the allocated lines and the
// available PO / direct-purchase rows they are drawn from.

import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/purchase.dart' show Purchase;
import '../../../data/models/purchase_order.dart' show PurchaseOrder;
import '../../../l10n/app_localizations.dart';

/// One allocated line: PO no + balance, editable amount, remove.
class SupplierPoAllocationRow extends StatelessWidget {
  const SupplierPoAllocationRow({
    super.key,
    required this.po,
    required this.controller,
    required this.onRemove,
    required this.onAmountChanged,
  });

  final PurchaseOrder po;

  /// The borrowed amount controller for this allocation line.
  final TextEditingController controller;

  final VoidCallback onRemove;
  final ValueChanged<String> onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  po.poNo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  Formatters.currency(po.balanceAmount),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: onAmountChanged,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.commonRemove,
            onPressed: onRemove,
            icon: Icon(
              Icons.close,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One available PO: no + balance + an Add button.
class SupplierAvailablePoRow extends StatelessWidget {
  const SupplierAvailablePoRow({
    super.key,
    required this.po,
    required this.onAdd,
  });

  final PurchaseOrder po;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  po.poNo,
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  '${Formatters.currency(po.balanceAmount)} '
                  '${scheme.brightness == Brightness.dark ? '' : ''}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onAdd,
            child: Text('+ ${l10n.commonAdd}'),
          ),
        ],
      ),
    );
  }
}

/// One allocated line: purchase no + balance, editable amount, remove —
/// mirrors [SupplierPoAllocationRow] for direct purchases.
class SupplierPurchaseAllocationRow extends StatelessWidget {
  const SupplierPurchaseAllocationRow({
    super.key,
    required this.purchase,
    required this.controller,
    required this.onRemove,
    required this.onAmountChanged,
  });

  final Purchase purchase;

  /// The borrowed amount controller for this allocation line.
  final TextEditingController controller;

  final VoidCallback onRemove;
  final ValueChanged<String> onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  purchase.purchaseNo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  Formatters.currency(purchase.balanceAmount),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: onAmountChanged,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.commonRemove,
            onPressed: onRemove,
            icon: Icon(
              Icons.close,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One available direct purchase: no + balance + an Add button.
class SupplierAvailablePurchaseRow extends StatelessWidget {
  const SupplierAvailablePurchaseRow({
    super.key,
    required this.purchase,
    required this.onAdd,
  });

  final Purchase purchase;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  purchase.purchaseNo,
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  Formatters.currency(purchase.balanceAmount),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onAdd,
            child: Text('+ ${l10n.commonAdd}'),
          ),
        ],
      ),
    );
  }
}
