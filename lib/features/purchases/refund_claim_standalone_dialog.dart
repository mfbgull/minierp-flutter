// UX-5 — record a standalone refund claim.
//
// A supplier can owe money with no purchase return behind it: a short payment,
// an agreed charge, a credit the supplier accepted verbally. Until this dialog
// existed the server endpoint (`POST /supplier-refunds/claims`) and the
// repository method (`createClaim`) had no caller, so the app could not reach
// the capability at all. Gull chose to build the screen (2026-11-26).
//
// A claim is a receivable MEMO, not money: it posts no GL and moves no cash.
// Cash appears only when a REFUND_RECEIPT is recorded against it. The dialog
// therefore asks for the expected amount and the date the expectation arose,
// and nothing else.
//
// The request is keyed from the exact body sent, so a retry after a timeout
// replays on the server instead of recording a second claim, while editing the
// amount or date is a genuinely new claim and rotates the key.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/idempotency_key.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart';
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart' show ErrorBanner, formInputDecoration;
import '../payments/payment_party_picker.dart' show showSupplierPickerDialog;

/// Opens the standalone refund-claim dialog. Returns true when a claim was
/// recorded, so the caller can refresh the list and the refunds-due memo.
Future<bool> showRefundClaimStandaloneDialog(BuildContext context) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => const _StandaloneClaimDialog(),
  );
  return done ?? false;
}

class _StandaloneClaimDialog extends ConsumerStatefulWidget {
  const _StandaloneClaimDialog();

  @override
  ConsumerState<_StandaloneClaimDialog> createState() =>
      _StandaloneClaimDialogState();
}

class _StandaloneClaimDialogState
    extends ConsumerState<_StandaloneClaimDialog> {
  final _idemKeys = IdempotencyKeyCache(prefix: 'claim-standalone');
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();

  Supplier? _supplier;
  late DateTime _claimDate;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The claim arises on the day the expectation is recognised, which is
    // normally today. The user can move it earlier; the server refuses a
    // date inside a closed accounting period.
    _claimDate = DateTime.now();
    _dateController.text = isoDate(_claimDate);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _pickSupplier() async {
    final picked = await showSupplierPickerDialog(context);
    if (picked == null || !mounted) return;
    setState(() {
      _supplier = picked;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _claimDate);
    if (picked == null) return;
    setState(() {
      _claimDate = picked;
      _dateController.text = isoDate(_claimDate);
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (_supplier == null) {
      setState(() => _error = l10n.refundClaimStandaloneSupplierRequired);
      return;
    }
    final amount = num.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = l10n.refundClaimStandaloneAmountRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final claimDate = isoDate(_claimDate);
    final body = <String, dynamic>{
      'supplier_id': _supplier!.id,
      'claim_date': claimDate,
      'amount': amount,
    };
    final result = await ref
        .read(purchaseRepositoryProvider)
        .createClaim(
          supplierId: _supplier!.id,
          claimDate: claimDate,
          amount: amount,
          // Derived from the exact body: an unchanged retry replays, an edit
          // is a new claim.
          idempotencyKey: _idemKeys.keyFor(body),
        );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        _idemKeys.reset();
        showAppToast(context, l10n.refundClaimStandaloneRecorded);
        Navigator.of(context).pop(true);
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
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.refundClaimStandalone),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.refundClaimStandaloneHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 12),
            FormFieldShell(
              label: l10n.refundClaimStandaloneSupplier,
              required: true,
              child: OutlinedButton(
                onPressed: _busy ? null : _pickSupplier,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _supplier?.supplierName ??
                        l10n.refundClaimStandaloneSelectSupplier,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FormFieldShell(
              label: l10n.refundClaimStandaloneAmount,
              required: true,
              child: TextField(
                key: const Key('claim-standalone-amount'),
                controller: _amountController,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onSubmitted: (_) => _submit(),
                decoration: formInputDecoration(),
              ),
            ),
            const SizedBox(height: 12),
            FormFieldShell(
              label: l10n.fieldsDate,
              child: TextField(
                controller: _dateController,
                enabled: !_busy,
                readOnly: true,
                onTap: _busy ? null : _pickDate,
                decoration: formInputDecoration(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
