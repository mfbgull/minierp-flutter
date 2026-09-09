import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/status_colors.dart';

/// Localized label for a cash-movement type
/// ('payment_received' | 'refund' | 'supplier_payment' | 'expense' |
/// 'salary' | 'owner_capital' | 'owner_withdrawal' |
/// 'loan_disbursement' | 'loan_repayment' | 'supplier_refund') — shared by the cash
/// flow report's movement grid and its CSV export so both render
/// identical type names.
String cashMovementLabel(AppLocalizations l10n, String type) => switch (type) {
  'payment_received' => l10n.cashposPaymentreceived,
  'refund' => l10n.cashposRefund,
  'supplier_payment' => l10n.cashposSupplierpayment,
  'expense' => l10n.cashposExpense,
  'salary' => l10n.cashposSalary,
  'owner_capital' => l10n.cashposOwnercapital,
  'owner_withdrawal' => l10n.cashposOwnerwithdrawal,
  'loan_disbursement' => l10n.cashposLoandisbursement,
  'loan_repayment' => l10n.cashposLoanrepayment,
  'supplier_refund' => l10n.cashposSupplierrefund,
  _ => type,
};

/// Badge color for a cash-movement type — inflow green, outflow error.
Color cashMovementColor(BuildContext context, String type) =>
    type == 'payment_received' || type == 'owner_capital' || type == 'loan_repayment'
        || type == 'supplier_refund'
        ? StatusColors.of(context).success
        : StatusColors.of(context).error;
