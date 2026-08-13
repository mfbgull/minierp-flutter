// Cash-position account detail dialog — the drill-down behind each card
// on the dashboard's Cash / Bank Position strip. Shows how the balance
// was built up (opening + inflows − outflows) and lists every money
// movement behind it, so a negative figure like "Cash −4,350" can be
// traced back to the exact transactions that caused it.

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/dashboard_summary.dart'
    show CashAccountPosition, CashPositionTransaction;
import '../../l10n/app_localizations.dart';

Future<void> showCashPositionDetailDialog(
  BuildContext context, {
  required CashAccountPosition account,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _CashPositionDetailDialog(account: account),
  );
}

class _CashPositionDetailDialog extends StatelessWidget {
  const _CashPositionDetailDialog({required this.account});

  final CashAccountPosition account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(account.name),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // How the balance is built up: opening + in − out.
            _summaryRow(
              context,
              l10n.cashreconOpening,
              Formatters.currency(account.opening),
            ),
            _summaryRow(
              context,
              l10n.cashreconInflow,
              '+${Formatters.currency(account.inflow)}',
              color: const Color(0xFF16A34A),
            ),
            _summaryRow(
              context,
              l10n.cashreconOutflow,
              '−${Formatters.currency(account.outflow)}',
              color: scheme.error,
            ),
            const Divider(height: 16),
            _summaryRow(
              context,
              l10n.fieldsBalance,
              Formatters.currency(account.balance),
              bold: true,
              color: account.balance < 0 ? scheme.error : const Color(0xFF16A34A),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.cashposTransactions,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: account.transactions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '—',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: account.transactions.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) => _transactionRow(
                        context,
                        account.transactions[index],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _summaryRow(
    BuildContext context,
    String label,
    String value, {
    Color? color,
    bool bold = false,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _transactionRow(
    BuildContext context,
    CashPositionTransaction t,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final label = switch (t.type) {
      'payment_received' => l10n.cashposPaymentreceived,
      'supplier_payment' => l10n.cashposSupplierpayment,
      'expense' => l10n.cashposExpense,
      'salary' => l10n.cashposSalary,
      'refund' => l10n.cashposRefund,
      _ => t.type,
    };
    final detail = [
      if (t.reference != null && t.reference!.isNotEmpty) t.reference,
      if (t.description != null && t.description!.isNotEmpty) t.description!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              t.date,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${t.amount < 0 ? '−' : '+'}${Formatters.currency(t.amount.abs())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: t.amount < 0 ? scheme.error : const Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }
}
