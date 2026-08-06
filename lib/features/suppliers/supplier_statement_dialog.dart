// Supplier statement dialog — thin facade over the shared [StatementDialog]
// (`lib/widgets/statement_dialog.dart`): binds the AP statement provider
// (`GET /suppliers/:id/statement`, enveloped object with opening/closing
// balance + oldest-first transactions) and the suppliers module's l10n
// keys. Opened from the supplier ledger dialog's Statement button.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/statement_dialog.dart'
    show StatementDialog, StatementDialogConfig;
import 'supplier_providers.dart' show supplierStatementProvider;

/// Opens the statement dialog for [supplierId]; [supplierName] titles it.
Future<void> showSupplierStatementDialog(
  BuildContext context, {
  required int supplierId,
  required String supplierName,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => SupplierStatementDialog(
      supplierId: supplierId,
      supplierName: supplierName,
    ),
  );
}

class SupplierStatementDialog extends StatelessWidget {
  const SupplierStatementDialog({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  final int supplierId;
  final String supplierName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StatementDialog(
      entryId: supplierId,
      entryName: supplierName,
      config: StatementDialogConfig(
        sectionLabel: l10n.suppliersStatement,
        debitLabel: l10n.suppliersLedgerDebit,
        creditLabel: l10n.suppliersLedgerCredit,
        balanceLabel: l10n.suppliersBalance,
        openingBalanceLabel: l10n.suppliersOpeningbalance,
        closingBalanceLabel: l10n.suppliersLedgerClosingbalance,
        noEntriesLabel: l10n.suppliersLedgerNoentries,
        statementProvider: supplierStatementProvider,
      ),
    );
  }
}
