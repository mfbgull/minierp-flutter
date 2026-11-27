import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../core/utils/idempotency_key.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/production_repository.dart'
    show productionRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart';
import '../../widgets/movable_dialog.dart';
import '../payments/payments_providers.dart' show invalidateCashMovementProviders;
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'production_providers.dart' show productionsProvider;

/// D30 — "Settle overhead" (Gull, 2026-11-27).
///
/// Production capitalises the labour/electricity/gas typed into a run into
/// the stock batches and credits 2200 Accrued Production Overhead. This
/// dialog pays that bill: the server posts Dr 2200 for the accrued part,
/// Dr 6000 for any excess above it (Gull's Q3 answer B) and Cr Cash/Bank
/// for the whole payment. Nothing about a production run changes.
class SettleOverheadDialog extends ConsumerStatefulWidget {
  const SettleOverheadDialog({
    super.key,
    required this.messengerContext,
  });

  /// The context that opened the dialog. The success toast is shown from it,
  /// because once this dialog pops its own context is gone.
  final BuildContext messengerContext;

  /// Opens the dialog and refreshes the production grid if a payment landed.
  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => SettleOverheadDialog(messengerContext: context),
  );

  @override
  ConsumerState<SettleOverheadDialog> createState() =>
      _SettleOverheadDialogState();
}

class _SettleOverheadDialogState extends ConsumerState<SettleOverheadDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _keys = IdempotencyKeyCache(prefix: 'overhead-settle');
  String? _error;
  bool _busy = false;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String _method = 'Cash';

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final reference = _reference.text.trim();
    final date = isoDate(_date);
    // The key is derived from the whole body, so a retry after a lost
    // response replays on the server instead of paying the bill twice.
    final keyBody = <String, dynamic>{
      'settlement_date': date,
      'amount': num.parse(_amount.text.trim()),
      'payment_method': _method,
      if (reference.isNotEmpty) 'reference_note': reference,
    };
    final key = _keys.keyFor(keyBody);

    final result = await ref
        .read(productionRepositoryProvider)
        .settleOverhead(keyBody, idempotencyKey: key);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        _keys.reset();
        ref.invalidate(productionsProvider);
        invalidateCashMovementProviders(ref, 'overhead_settlement');
        final l10n = AppLocalizations.of(context)!;
        final message = l10n.productionSettleOverheadPaid(
          Formatters.currency(data.accruedAmount),
          Formatters.currency(data.excessAmount),
        );
        Navigator.of(context).pop();
        // The toast belongs to the screen behind the dialog, so it is shown
        // from the ancestor context that opened the dialog.
        showAppToast(widget.messengerContext, message);
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  /// Shows a text field. Every keystroke only rebuilds that leaf, so typing
  /// does not rebuild the whole dialog (focus and cursor survive).
  Widget _typedField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    bool numeric = false,
    bool autofocus = false,
    int? maxLength,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    autofocus: autofocus,
    maxLength: maxLength,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : null,
    onFieldSubmitted: numeric ? (_) => _submit() : null,
    decoration: InputDecoration(labelText: label),
    validator: validator,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MovableDialog(
      title: l10n.productionSettleOverheadTitle,
      maxWidth: 480,
      maxHeight: 560,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.productionSettleOverheadHint),
              const SizedBox(height: 12),
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
              _typedField(
                controller: _amount,
                label: l10n.productionSettleOverheadAmount,
                numeric: true,
                autofocus: true,
                validator: (value) {
                  final amount = num.tryParse(value?.trim() ?? '');
                  return amount == null || !amount.isFinite || amount <= 0
                      ? l10n.productionSettleOverheadError
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
              const SizedBox(height: 8),
              _typedField(
                controller: _reference,
                label: l10n.productionSettleOverheadReference,
                maxLength: 200,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(l10n.productionSettleOverhead),
              ),
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
