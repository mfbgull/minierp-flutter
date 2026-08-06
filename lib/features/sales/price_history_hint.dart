// Price-history hint shown under the rate cell while it is being edited
// (spec §price-history; port of `PriceHistoryHint.tsx`). Fetched from
// `GET /sales/item-customer-history?item_id=&customer_id=`; the hint is
// advisory only — any failure, a missing item/customer, or
// `transaction_count == 0` simply means no hint (never a toast, never a
// blocked edit).

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/price_history.dart' show ItemPriceHistory;

/// Compact anchored card: last price + delta vs the price being typed,
/// lowest/highest, and the transaction count. Purely informational — it
/// never takes focus (no focusable children), so the rate editor keeps
/// the caret while the hint is visible.
class PriceHistoryHint extends StatelessWidget {
  const PriceHistoryHint({
    super.key,
    required this.history,
    required this.currentPrice,
  });

  final ItemPriceHistory history;
  final num currentPrice;

  @override
  Widget build(BuildContext context) {
    final delta = currentPrice - history.lastPrice;
    final below = currentPrice > 0 && currentPrice < history.lowestPrice;
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 232,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, size: 13),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      history.customerName == null
                          ? 'Price history'
                          : 'Price history · ${history.customerName}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${history.transactionCount}×',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _line(
                'Last',
                Formatters.currency(history.lastPrice),
                trailing: currentPrice > 0 && delta != 0
                    ? Text(
                        '${delta > 0 ? '+' : ''}${Formatters.currency(delta)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: delta > 0
                              ? const Color(0xff16a34a)
                              : theme.colorScheme.error,
                        ),
                      )
                    : null,
                subtitle: history.invoiceDate,
              ),
              _line('Lowest', Formatters.currency(history.lowestPrice)),
              _line('Highest', Formatters.currency(history.highestPrice)),
              _line('Average', Formatters.currency(history.avgPrice)),
              if (below) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 13, color: theme.colorScheme.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Below the lowest price sold',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(
    String label,
    String value, {
    Widget? trailing,
    String? subtitle,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 11)),
            if (subtitle != null && subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  Formatters.date(subtitle),
                  style: const TextStyle(fontSize: 9, color: Colors.black54),
                ),
              ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      );
}
