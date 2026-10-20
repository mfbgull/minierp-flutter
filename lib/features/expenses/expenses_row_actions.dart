import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/expense.dart' show Expense;
import '../../l10n/app_localizations.dart';
import 'expense_form_dialog.dart';
import 'expense_payments_dialog.dart';

/// The per-row ⋮ menu actions for an expense row.
enum ExpenseRowAction { edit, payments }

/// Opens the row-actions menu (Edit) anchored at [context].
Future<void> openExpenseRowMenu({
  required BuildContext context,
  required Expense? expense,
}) async {
  if (expense == null || !context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  final l10n = AppLocalizations.of(context)!;
  final action = await showMenu<ExpenseRowAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      ),
      Offset.zero & overlay.context.size!,
    ),
    items: [
      if (expense.paymentMethod == 'Credit' && expense.status == 'Recorded')
        PopupMenuItem(
          value: ExpenseRowAction.payments,
          child: Text(l10n.expensePayments),
        ),
      PopupMenuItem(
        value: ExpenseRowAction.edit,
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, size: 18),
            const SizedBox(width: 8),
            Text(l10n.commonEdit),
          ],
        ),
      ),
    ],
  );
  if (action != null && context.mounted) {
    if (action == ExpenseRowAction.payments) {
      await showDialog<void>(
        context: context,
        builder: (_) => ExpensePaymentsDialog(expenseId: expense.id),
      );
    } else {
      unawaited(showExpenseFormDialog(context, expense: expense));
    }
  }
}
