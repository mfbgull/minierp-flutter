// Supplier ledger dialog — thin facade over the shared [LedgerDialog]
// (`lib/widgets/ledger_dialog.dart`): binds the AP ledger provider
// (`GET /suppliers/:id/ledger`, enveloped array, newest-first by
// transaction_date) and the suppliers module's l10n keys. Opened from the
// supplier detail dialog's Ledger button.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/ledger_dialog.dart' show LedgerDialog, LedgerDialogConfig;
import 'supplier_providers.dart' show supplierLedgerProvider;

/// Opens the ledger dialog for [supplierId]; [supplierName] titles it.
Future<void> showSupplierLedgerDialog(
  BuildContext context, {
  required int supplierId,
  required String supplierName,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => SupplierLedgerDialog(
      supplierId: supplierId,
      supplierName: supplierName,
    ),
  );
}

class SupplierLedgerDialog extends StatelessWidget {
  const SupplierLedgerDialog({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  final int supplierId;
  final String supplierName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LedgerDialog(
      entryId: supplierId,
      entryName: supplierName,
      config: LedgerDialogConfig(
        sectionLabel: l10n.suppliersLedger,
        debitLabel: l10n.suppliersLedgerDebit,
        creditLabel: l10n.suppliersLedgerCredit,
        balanceLabel: l10n.suppliersBalance,
        closingBalanceLabel: l10n.suppliersLedgerClosingbalance,
        noEntriesLabel: l10n.suppliersLedgerNoentries,
        entriesProvider: supplierLedgerProvider,
      ),
    );
  }
}
