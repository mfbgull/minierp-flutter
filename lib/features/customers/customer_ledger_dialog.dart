// Customer ledger dialog — thin facade over the shared [LedgerDialog]
// (`lib/widgets/ledger_dialog.dart`): binds the AR ledger provider
// (`GET /customers/:id/ledger`, enveloped array, newest-first by
// transaction_date) and the customers module's l10n keys. Opened from the
// customer detail dialog's Ledger button.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/ledger_dialog.dart' show LedgerDialog, LedgerDialogConfig;
import 'customer_providers.dart' show customerLedgerProvider;

/// Opens the ledger dialog for [customerId]; [customerName] titles it.
Future<void> showCustomerLedgerDialog(
  BuildContext context, {
  required int customerId,
  required String customerName,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => CustomerLedgerDialog(
      customerId: customerId,
      customerName: customerName,
    ),
  );
}

class CustomerLedgerDialog extends StatelessWidget {
  const CustomerLedgerDialog({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  final int customerId;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LedgerDialog(
      entryId: customerId,
      entryName: customerName,
      config: LedgerDialogConfig(
        sectionLabel: l10n.customersLedger,
        debitLabel: l10n.customersLedgerDebit,
        creditLabel: l10n.customersLedgerCredit,
        balanceLabel: l10n.customersBalance,
        closingBalanceLabel: l10n.customersLedgerClosingbalance,
        noEntriesLabel: l10n.customersLedgerNoentries,
        entriesProvider: customerLedgerProvider,
      ),
    );
  }
}
