import 'package:flutter/material.dart';
import '../../data/models/customer.dart';
import '../../data/models/unapplied_cash.dart';
import 'unapplied_cash_action_dialog.dart';

Future<void> showUnappliedCashReverseDialog(
  BuildContext context, {
  required Customer customer,
  required CashReceipt receipt,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      UnappliedCashActionDialog(customer: customer, receipt: receipt),
);
