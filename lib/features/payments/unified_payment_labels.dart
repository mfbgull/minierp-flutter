import '../../l10n/app_localizations.dart';

/// Localized label for a unified-payment `type` value.
String unifiedTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'customer' => l10n.paymentsTypeCustomer,
  'supplier' => l10n.paymentsTypeSupplier,
  'expense' => l10n.paymentsTypeExpense,
  'salary' => l10n.paymentsTypeSalary,
  'owner_capital' => l10n.paymentsTypeOwnerCapital,
  'owner_withdrawal' => l10n.paymentsTypeOwnerWithdrawal,
  _ => l10n.paymentsTypeUnknown,
};

/// Localized label for a normalized unified-payment `method` value.
String unifiedMethodLabel(AppLocalizations l10n, String method) => switch (method) {
  'cash' => l10n.paymentsMethodCash,
  'bank' => l10n.paymentsMethodBank,
  'card' => l10n.paymentsMethodCard,
  'mobile_wallet' => l10n.paymentsMethodMobileWallet,
  'credit' => l10n.paymentsMethodCredit,
  'other' => l10n.paymentsMethodOther,
  _ => l10n.paymentsMethodUnknown,
};
