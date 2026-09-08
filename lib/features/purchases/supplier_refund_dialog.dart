// Supplier refund dialog — issues a cash payout against a purchase
// return's credit note (`POST /supplier-refunds`). Opened from the
// return detail dialog when the return has a POSTED credit note with
// refundable balance remaining. Mirrors the void dialog's structure:
// optimistic busy state, error banner, server re-validation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/purchase_return.dart' show PurchaseReturn;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart' show ErrorBanner, formInputDecoration;
import '../../widgets/searchable_select.dart' show SearchableSelect;
import 'package:minierp_app/widgets/movable_dialog.dart';
import 'purchase_return_providers.dart'
    show filteredPurchaseReturnsProvider, purchaseReturnsProvider;

/// Opens the refund dialog for [purchaseReturn]'s credit note.
Future<void> showSupplierRefundDialog(
  BuildContext context, {
  required PurchaseReturn purchaseReturn,
  required num refundable,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _SupplierRefundDialog(
      purchaseReturn: purchaseReturn,
      refundable: refundable,
    ),
  );
}

class _SupplierRefundDialog extends ConsumerStatefulWidget {
  const _SupplierRefundDialog({
    required this.purchaseReturn,
    required this.refundable,
  });

  final PurchaseReturn purchaseReturn;
  final num refundable;

  @override
  ConsumerState<_SupplierRefundDialog> createState() =>
      _SupplierRefundDialogState();
}

class _SupplierRefundDialogState extends ConsumerState<_SupplierRefundDialog> {
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();

  DateTime _refundDate = DateTime.now();
  String _paymentMethod = 'cash';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _refundDate);
    if (picked != null) setState(() => _refundDate = picked);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final amount = num.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = l10n.purchasesReturnqtyinvalid);
      return;
    }
    if (amount > widget.refundable + 0.005) {
      setState(() => _error = l10n.purchasesReturnqtyexceeds);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref.read(purchaseRepositoryProvider).createRefund(
      refundDate: isoDate(_refundDate),
      creditNoteId: widget.purchaseReturn.creditNoteId!,
      amount: amount,
      paymentMethod: _paymentMethod,
      referenceNo: _referenceController.text.trim(),
    );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(purchaseReturnsProvider);
        ref.invalidate(filteredPurchaseReturnsProvider);
        showAppToast(
          context,
          '${l10n.purchasesRefundprocessed} — ${Formatters.currency(amount)}',
        );
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return MovableDialog(
      dialogId: 'supplier_refund_form',
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.purchasesRefundtitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.purchaseReturn.returnNo} · '
              '${widget.purchaseReturn.creditNo ?? ''} — '
              '${l10n.purchasesRefundrefunded}: '
              '${Formatters.currency(widget.refundable)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 12),
            FormFieldShell(
              label: l10n.purchasesReturndate,
              required: true,
              child: InkWell(
                onTap: _busy ? null : _pickDate,
                child: InputDecorator(
                  decoration: formInputDecoration(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isoDate(_refundDate)),
                      const Icon(Icons.calendar_today, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FormFieldShell(
              label: l10n.purchasesRefundamount,
              required: true,
              child: TextField(
                controller: _amountController,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _submit(),
                decoration: formInputDecoration(
                  hintText: Formatters.number(widget.refundable),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FormFieldShell(
              label: l10n.purchasesRefundmethod,
              child: SearchableSelect<String>(
                items: const ['cash', 'bank', 'easypaisa', 'jazzcash', 'upaisa'],
                selected: _paymentMethod,
                isDense: true,
                enabled: !_busy,
                labelBuilder: (value) => switch (value) {
                  'cash' => l10n.paymentsMethodCash,
                  'bank' => l10n.paymentsMethodBank,
                  'easypaisa' => 'Easypaisa',
                  'jazzcash' => 'JazzCash',
                  _ => 'UPaisa',
                },
                decoration: formInputDecoration(),
                onChanged: (value) {
                  if (value != null) setState(() => _paymentMethod = value);
                },
              ),
            ),
            const SizedBox(height: 10),
            FormFieldShell(
              label: l10n.purchasesRefundreference,
              child: TextField(
                controller: _referenceController,
                enabled: !_busy,
                onSubmitted: (_) => _submit(),
                decoration: formInputDecoration(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payments_outlined, size: 18),
                  label: Text(l10n.purchasesRefund),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
