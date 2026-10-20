import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../core/utils/idempotency_key.dart';
import '../../data/models/expense.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/expense_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/date_picker.dart';
import '../../widgets/movable_dialog.dart';
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'expense_providers.dart';
import '../payments/payments_providers.dart' show invalidateCashMovementProviders;

class ExpensePaymentsDialog extends ConsumerStatefulWidget {
  const ExpensePaymentsDialog({super.key, required this.expenseId});
  final int expenseId;

  @override
  ConsumerState<ExpensePaymentsDialog> createState() =>
      _ExpensePaymentsDialogState();
}

class _ExpensePaymentsDialogState extends ConsumerState<ExpensePaymentsDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _keys = IdempotencyKeyCache(prefix: 'expense-payment');
  Expense? _expense;
  String? _error;
  bool _busy = false;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String _method = 'Cash';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ref
        .read(expenseRepositoryProvider)
        .expense(widget.expenseId);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case ApiSuccess(:final data):
          _expense = data;
          _error = null;
        case ApiFailure(:final error):
          _error = error.message;
      }
    });
  }

  Future<void> _pay() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {
      'amount': num.parse(_amount.text.trim()),
      'payment_date': isoDate(_date),
      'payment_method': _method,
    };
    final result = await ref
        .read(expenseRepositoryProvider)
        .pay(widget.expenseId, body, idempotencyKey: _keys.keyFor(body));
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(expensesProvider);
        invalidateCashMovementProviders(ref, 'expense_payment');
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  Future<void> _void(ExpensePayment payment) async {
    final l10n = AppLocalizations.of(context)!;
    if (!await showConfirmDialog(
      context,
      title: l10n.expenseReversePayment,
      message: l10n.expenseReversePaymentConfirm,
    )) {
      return;
    }
    if (!mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(expenseRepositoryProvider)
        .voidPayment(
          widget.expenseId,
          payment.id,
          reason: 'Expense payment correction',
        );
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(expensesProvider);
        invalidateCashMovementProviders(ref, 'expense_payment');
        await _load();
      case ApiFailure(:final error):
        setState(() => _error = error.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final expense = _expense;
    return MovableDialog(
      title: l10n.expensePayments,
      maxWidth: 500,
      maxHeight: 600,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (expense == null) ...[
                if (_error == null)
                  const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  TextButton(onPressed: _load, child: Text(l10n.commonRetry)),
              ] else ...[
                Text(expense.expenseNo),
                Text(
                  '${l10n.expenseOutstanding}: ${Formatters.currency(expense.outstandingAmount)}',
                ),
                for (final payment in expense.payments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${Formatters.currency(payment.amount)} · ${payment.paymentMethod}',
                    ),
                    subtitle: Text(
                      '${Formatters.date(payment.paymentDate)}${payment.voidedAt == null ? '' : ' · ${l10n.expensePaymentVoided}'}',
                    ),
                    trailing: payment.voidedAt == null
                        ? IconButton(
                            tooltip: l10n.expenseReversePayment,
                            onPressed: _busy ? null : () => _void(payment),
                            icon: const Icon(Icons.undo),
                          )
                        : null,
                  ),
                if (expense.status == 'Recorded' &&
                    expense.paymentMethod == 'Credit' &&
                    expense.outstandingAmount > 0) ...[
                  TextFormField(
                    controller: _amount,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: l10n.fieldsAmount),
                    validator: (value) {
                      final amount = num.tryParse(value?.trim() ?? '');
                      return amount == null ||
                              !amount.isFinite ||
                              amount <= 0 ||
                              amount > expense.outstandingAmount
                          ? l10n.expensesErrorAmountInvalid
                          : null;
                    },
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final date = await pickDate(
                              context,
                              initialDate: _date,
                            );
                            if (date != null && mounted) {
                              setState(() => _date = date);
                            }
                          },
                    child: Text('${l10n.fieldsDate}: ${isoDate(_date)}'),
                  ),
                  DropdownButtonFormField<String>(
                  isExpanded: true,
                    initialValue: _method,
                    decoration: InputDecoration(
                      labelText: l10n.expensesPaymentmethod,
                    ),
                    items: [
                      for (final method in kPaymentMethods)
                        DropdownMenuItem(value: method, child: Text(method)),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _method = value ?? 'Cash'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _pay,
                    child: Text(l10n.expenseRecordPayment),
                  ),
                ],
              ],
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.commonClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
