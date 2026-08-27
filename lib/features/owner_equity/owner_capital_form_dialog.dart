// Owner capital create/edit form — modal over POST/PUT
// /owner-equity/capital. Field set mirrors the server DTO: capital_date,
// amount (required, > 0); payment method + note optional. Saving posts
// immediately to the GL server-side (Dr cash-per-method / Cr 3200).
//
// Void lives here too (edit mode): destructive confirm → DELETE
// /owner-equity/capital/:id → toast + grid refresh.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/expense.dart' show ExpenseOption;
import '../../data/models/owner_equity.dart' show OwnerCapitalEntry;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/owner_equity_repository.dart'
    show ownerEquityRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import 'owner_equity_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Opens the create ([entry] == null) or edit form dialog.
Future<void> showOwnerCapitalFormDialog(
  BuildContext context, {
  OwnerCapitalEntry? entry,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => OwnerCapitalFormDialog(entry: entry),
  );
}

class OwnerCapitalFormDialog extends ConsumerStatefulWidget {
  const OwnerCapitalFormDialog({super.key, this.entry});

  /// Null → create; otherwise pre-fills and PUTs to `capital/:id`.
  final OwnerCapitalEntry? entry;

  @override
  ConsumerState<OwnerCapitalFormDialog> createState() =>
      _OwnerCapitalFormDialogState();
}

class _OwnerCapitalFormDialogState
    extends ConsumerState<OwnerCapitalFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  String? _paymentMethod;
  late DateTime _capitalDate;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _amountController = TextEditingController(
      text: entry == null ? '' : _numText(entry.amount),
    );
    _noteController = TextEditingController(text: entry?.note ?? '');
    _paymentMethod = entry?.paymentMethod;
    _capitalDate =
        DateTime.tryParse(entry?.capitalDate ?? '') ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  static String _numText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  String? _validateAmount(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.equityErrorAmountRequired;
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return l10n.equityErrorAmountInvalid;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initialDate: _capitalDate);
    if (picked == null || !mounted) return;
    setState(() => _capitalDate = picked);
  }

  Map<String, dynamic> _buildBody() => {
    'capital_date': isoDate(_capitalDate),
    'amount': double.parse(_amountController.text),
    'payment_method': _paymentMethod,
    'note': _noteController.text.trim(),
  };

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(ownerEquityRepositoryProvider);
    final result = _isEdit
        ? await repo.updateCapital(widget.entry!.id, _buildBody())
        : await repo.createCapital(_buildBody());
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        _invalidateAll();
        Navigator.of(context).pop();
        showAppToast(context, l10n.equitySaved);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.equityDeleteconfirmdesc,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(ownerEquityRepositoryProvider)
        .voidCapital(widget.entry!.id);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        _invalidateAll();
        Navigator.of(context).pop();
        showAppToast(context, l10n.equityVoided);
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  void _invalidateAll() {
    ref
      ..invalidate(ownerCapitalProvider)
      ..invalidate(allOwnerCapitalProvider)
      ..invalidate(equitySummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final paymentMethods = ref.watch(equityPaymentMethodsProvider);

    final paymentItems = [
      for (final o in paymentMethods.valueOrNull ?? const <ExpenseOption>[])
        o.value,
    ];
    if (_paymentMethod != null && !paymentItems.contains(_paymentMethod)) {
      paymentItems.add(_paymentMethod!);
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEdit ? l10n.equityEditcapital : l10n.equityNewcapital,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.commonClose,
                      icon: const Icon(Icons.close),
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.equityCapitaldate,
                              required: true,
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _submitting ? null : _pickDate,
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    Formatters.date(isoDate(_capitalDate)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FormFieldShell(
                              label: l10n.fieldsAmount,
                              required: true,
                              child: TextFormField(
                                controller: _amountController,
                                onFieldSubmitted: submitOnEnter(_submit),
                                enabled: !_submitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: _decoration(),
                                validator: _validateAmount,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.expensesPaymentmethod,
                        child: SearchableSelect<String?>(
                          items: [null, ...paymentItems],
                          selected: _paymentMethod,
                          labelBuilder: (v) => v ?? l10n.commonNone,
                          onChanged: (v) => setState(() => _paymentMethod = v),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FormFieldShell(
                        label: l10n.fieldsNote,
                        child: TextFormField(
                          controller: _noteController,
                          enabled: !_submitting,
                          minLines: 2,
                          maxLines: 4,
                          decoration: _decoration(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      ErrorBanner(message: _error!),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        if (_isEdit)
                          TextButton.icon(
                            onPressed: _submitting ? null : _delete,
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(l10n.commonDelete),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(l10n.commonCancel),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.commonSave),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration() => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: AppBorderRadius.smRadius),
  );
}
