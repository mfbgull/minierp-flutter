import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../core/utils/idempotency_key.dart';
import '../../data/models/supplier_bill.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/supplier_accounting_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart';
import '../../widgets/movable_dialog.dart';
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'supplier_providers.dart';
import '../payments/payments_providers.dart' show invalidateCashMovementProviders;

class SupplierBillDialog extends ConsumerStatefulWidget {
  const SupplierBillDialog.create({super.key, required this.supplierId})
    : bill = null;
  SupplierBillDialog.payment({super.key, required SupplierBill bill})
    : bill = bill,
      supplierId = bill.supplierId;
  final int supplierId;
  final SupplierBill? bill;

  @override
  ConsumerState<SupplierBillDialog> createState() => _SupplierBillDialogState();
}

class _SupplierBillDialogState extends ConsumerState<SupplierBillDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _number = TextEditingController();
  final _description = TextEditingController();
  final _keys = IdempotencyKeyCache(prefix: 'supplier-bill');
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  DateTime _due = DateUtils.dateOnly(
    DateTime.now(),
  ).add(const Duration(days: 30));
  String _method = 'Cash';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _tax.dispose();
    _number.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(supplierAccountingRepositoryProvider);
    final bill = widget.bill;
    final Map<String, dynamic> body = bill == null
        ? {
            'supplier_id': widget.supplierId,
            'bill_no': _number.text.trim(),
            'description': _description.text.trim(),
            'bill_date': isoDate(_date),
            'due_date': isoDate(_due),
            'net_amount': num.parse(_amount.text.trim()),
            'input_tax_amount': num.parse(_tax.text.trim()),
          }
        : {
            'amount': num.parse(_amount.text.trim()),
            'payment_date': isoDate(_date),
            'payment_method': _method,
          };
    final ApiResult<Object?> result = bill == null
        ? await repo.createBill(body, idempotencyKey: _keys.keyFor(body))
        : await repo.payBill(bill.id, body, idempotencyKey: _keys.keyFor(body));
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        invalidateCashMovementProviders(ref, 'payment');
        ref.invalidate(supplierBillsProvider);
        invalidateSupplierQueries(ref, widget.supplierId);
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  String? _validAmount(String? value, {bool tax = false}) {
    final amount = num.tryParse(value?.trim() ?? '');
    if (amount == null ||
        !amount.isFinite ||
        (tax ? amount < 0 : amount <= 0) ||
        amount > 1e9 ||
        (!tax && widget.bill != null && amount > widget.bill!.balanceAmount)) {
      return AppLocalizations.of(context)!.expensesErrorAmountInvalid;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bill = widget.bill;
    return MovableDialog(
      title: bill == null ? l10n.supplierBillCreate : l10n.expenseRecordPayment,
      maxWidth: 500,
      maxHeight: 600,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              if (bill == null) ...[
                Text(l10n.supplierBillNonStockHint),
                TextFormField(
                  controller: _number,
                  enabled: !_busy,
                  maxLength: 150,
                  decoration: InputDecoration(
                    labelText: l10n.supplierBillNumber,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l10n.messagesRequired
                      : null,
                ),
                TextFormField(
                  controller: _description,
                  enabled: !_busy,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: l10n.fieldsDescription,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l10n.messagesRequired
                      : null,
                ),
              ] else ...[
                Text(bill.billNo),
                Text(
                  '${l10n.expenseOutstanding}: ${Formatters.currency(bill.balanceAmount)}',
                ),
              ],
              TextFormField(
                controller: _amount,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: bill == null
                      ? l10n.supplierBillNetAmount
                      : l10n.fieldsAmount,
                ),
                validator: _validAmount,
              ),
              if (bill == null)
                TextFormField(
                  controller: _tax,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.supplierBillInputTax,
                  ),
                  validator: (value) => _validAmount(value, tax: true),
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
              if (bill == null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final date = await pickDate(
                            context,
                            initialDate: _due,
                          );
                          if (date != null && mounted) {
                            setState(() => _due = date);
                          }
                        },
                  child: Text('${l10n.salesDuedate}: ${isoDate(_due)}'),
                ),
              if (bill != null)
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
                onPressed: _busy ? null : _submit,
                child: Text(
                  bill == null ? l10n.commonSave : l10n.expenseRecordPayment,
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
