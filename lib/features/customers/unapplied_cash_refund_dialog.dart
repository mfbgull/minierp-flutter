import 'package:flutter/material.dart';
import '../../data/models/customer.dart';
import 'unapplied_cash_action_dialog.dart';

Future<void> showUnappliedCashRefundDialog(
  BuildContext context, {
  required Customer customer,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => UnappliedCashActionDialog(customer: customer),
);
