// ACCT-013 — the cash guard refuses a void or edit that would make a cash or
// bank day negative. The 409 carries the journal lines landing on the first
// deficit date, so the user can see what to reverse first. The server sends
// them under `details`; [ApiError.cashBlockers] parses them.
//
// A long list is truncated: the point is to identify the earliest blockers,
// and a wall of rows in a dialog helps nobody. The remainder is counted.

import 'package:flutter/material.dart';

import '../core/utils/formatters.dart';
import '../data/repositories/api_result.dart';
import '../l10n/app_localizations.dart';

/// How many blocker rows to show before collapsing into "and N more".
const int kCashBlockerPreviewCount = 5;

/// Maps a journal `reference_type` to a localized label. Unknown values are
/// humanized (`receipt_overpayment` → `Receipt overpayment`) so the UI never
/// leaks the raw enum or a snake_case token.
String cashBlockerTypeLabel(AppLocalizations l10n, String type) {
  switch (type) {
    case 'EXPENSE_PAYMENT':
      return l10n.cashBlockerTypeExpensepayment;
    case 'EXPENSE':
      return l10n.cashBlockerTypeExpense;
    case 'SUPPLIER_REFUND':
      return l10n.cashBlockerTypeSupplierrefund;
    case 'REFUND_RECEIPT':
      return l10n.cashBlockerTypeRefundreceipt;
    case 'REFUND_CLAIM_WRITE_OFF':
      return l10n.cashBlockerTypeRefundclaimwriteoff;
    case 'OWNER_WITHDRAWAL':
      return l10n.cashBlockerTypeOwnerwithdrawal;
    case 'OWNER_CAPITAL':
      return l10n.cashBlockerTypeOwnercapital;
    case 'PAYMENT':
      return l10n.cashBlockerTypeSupplierpayment;
    case 'SUPPLIER_PAYMENT':
      return l10n.cashBlockerTypeSupplierpayment;
    case 'CUSTOMER_REFUND':
      return l10n.cashBlockerTypeCustomerrefund;
    case 'SALARY_PAYMENT':
      return l10n.cashBlockerTypeSalarypayment;
    case 'SUPPLIER_PREPAYMENT':
      return l10n.cashBlockerTypeSupplierprepayment;
    case 'LOAN_DISBURSEMENT':
      return l10n.cashBlockerTypeLoandisbursement;
    case 'LOAN_REPAYMENT':
      return l10n.cashBlockerTypeLoanrepayment;
    case 'PURCHASE':
      return l10n.cashBlockerTypePurchase;
    case 'OPENING_BALANCE':
      return l10n.cashBlockerTypeOpeningbalance;
    case 'MANUAL_JOURNAL':
      return l10n.cashBlockerTypeManualjournal;
    case 'CREDIT_OFFSET':
      return l10n.cashBlockerTypeCreditoffset;
    case 'OTHER':
      return l10n.cashBlockerTypeOther;
    default:
      return _humanizeReferenceType(type);
  }
}

/// `receipt_overpayment` → `Receipt overpayment`; a value with no separators
/// is returned as-is (it is already readable). Never returns snake_case.
String _humanizeReferenceType(String type) {
  final cleaned = type.replaceAll('_', ' ').trim();
  if (cleaned.isEmpty) return type;
  final lower = cleaned.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

class CashBlockersList extends StatelessWidget {
  const CashBlockersList({
    super.key,
    required this.blockers,
    this.previewCount = kCashBlockerPreviewCount,
  });

  final List<CashBlocker> blockers;
  final int previewCount;

  @override
  Widget build(BuildContext context) {
    if (blockers.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final shown = blockers.take(previewCount).toList();
    final hidden = blockers.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.refundBlockedTitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.refundBlockedHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        for (final blocker in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              l10n.refundBlockedRow(
                cashBlockerTypeLabel(l10n, blocker.type),
                Formatters.date(
                  blocker.date,
                  locale: Localizations.localeOf(context).languageCode,
                ),
                Formatters.currency(blocker.amount),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (hidden > 0)
          Text(
            l10n.refundBlockedMore(hidden),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
