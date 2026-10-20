import '../../l10n/app_localizations.dart';
import '../../data/models/unified_payment.dart';

String paymentKindLabel(AppLocalizations l10n, String kind) => switch (kind) {
  'RECEIPT' => l10n.cashOrdinaryReceipt,
  'UNAPPLIED_RECEIPT' => l10n.cashAdvanceReceipt,
  'REFUND' => l10n.cashRefundPayment,
  _ => l10n.paymentsTypeUnknown,
};

String unifiedPaymentLabel(AppLocalizations l10n, UnifiedPayment payment) =>
    payment.source == 'payment' && payment.type == 'customer'
    ? paymentKindLabel(l10n, payment.paymentKind ?? 'RECEIPT')
    : unifiedTypeLabel(l10n, payment.type);

/// Localized label for a unified-payment `type` value.
String unifiedTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'customer' => l10n.paymentsTypeCustomer,
  'supplier' => l10n.paymentsTypeSupplier,
  'supplier_advance' => l10n.supplierAdvances,
  'expense' => l10n.paymentsTypeExpense,
  'salary' => l10n.paymentsTypeSalary,
  'owner_capital' => l10n.paymentsTypeOwnerCapital,
  'owner_withdrawal' => l10n.paymentsTypeOwnerWithdrawal,
  _ => l10n.paymentsTypeUnknown,
};

/// Localized label for a normalized unified-payment `method` value.
String unifiedMethodLabel(AppLocalizations l10n, String method) =>
    switch (method) {
      'cash' => l10n.paymentsMethodCash,
      'bank' => l10n.paymentsMethodBank,
      'card' => l10n.paymentsMethodCard,
      'mobile_wallet' => l10n.paymentsMethodMobileWallet,
      'credit' => l10n.paymentsMethodCredit,
      'other' => l10n.paymentsMethodOther,
      _ => l10n.paymentsMethodUnknown,
    };
