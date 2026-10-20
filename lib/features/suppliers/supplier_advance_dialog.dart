import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../core/utils/idempotency_key.dart';
import '../../data/models/supplier_prepayment.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/supplier_accounting_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart';
import '../../widgets/movable_dialog.dart';
import '../sales/payment_panel.dart' show kPaymentMethods;
import 'supplier_providers.dart';
import '../payments/payments_providers.dart' show invalidateCashMovementProviders;

class SupplierAdvanceDialog extends ConsumerStatefulWidget {
  const SupplierAdvanceDialog.create({super.key, required this.supplierId})
    : advance = null;
  SupplierAdvanceDialog.apply({super.key, required SupplierPrepayment advance})
    : advance = advance,
      supplierId = advance.supplierId;
  final int supplierId;
  final SupplierPrepayment? advance;

  @override
  ConsumerState<SupplierAdvanceDialog> createState() =>
      _SupplierAdvanceDialogState();
}

class _SupplierAdvanceDialogState extends ConsumerState<SupplierAdvanceDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _search = TextEditingController();
  final _keys = IdempotencyKeyCache(prefix: 'supplier-advance');
  List<SupplierPaymentTarget> _targets = const [];
  SupplierPaymentTarget? _target;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String _method = 'Cash';
  bool _busy = false;
  bool _loading = false;
  int _targetVersion = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.advance != null) unawaited(_loadTargets());
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    if (_busy || _loading) return;
    final source = widget.advance;
    if (source == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _target = null;
      _targets = const [];
      _targetVersion++;
    });
    final result = await ref
        .read(supplierAccountingRepositoryProvider)
        .prepaymentTargets(source.id, search: _search.text.trim());
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case ApiSuccess(:final data):
          _targets = data;
        case ApiFailure(:final error):
          _error = error.message;
      }
    });
  }

  Future<void> _submit() async {
    if (_busy || _loading || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final source = widget.advance;
    final amount = num.parse(_amount.text.trim());
    final target = _target;
    final Map<String, dynamic> body = source == null
        ? {
            'supplier_id': widget.supplierId,
            'prepay_date': isoDate(_date),
            'amount': amount,
            'payment_method': _method,
            if (_reference.text.trim().isNotEmpty)
              'reference_no': _reference.text.trim(),
          }
        : {
            'applied_at': isoDate(_date),
            'allocations': [
              {'kind': target!.kind.value, 'id': target.id, 'amount': amount},
            ],
          };
    final repo = ref.read(supplierAccountingRepositoryProvider);
    final ApiResult<Object?> result = source == null
        ? await repo.createPrepayment(body, idempotencyKey: _keys.keyFor(body))
        : await repo.applyPrepayment(
            source.id,
            body,
            idempotencyKey: _keys.keyFor(body),
          );
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        invalidateCashMovementProviders(ref, 'supplier_advance');
        invalidateSupplierQueries(ref, widget.supplierId);
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
    final source = widget.advance;
    return MovableDialog(
      title: source == null
          ? l10n.supplierAdvanceCreate
          : l10n.supplierAdvanceApply,
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
              if (source == null)
                Text(l10n.supplierAdvanceCreateHint)
              else ...[
                Text(
                  '${l10n.supplierAdvanceAvailable}: ${Formatters.currency(source.availableAmount)}',
                ),
                Text(l10n.supplierAdvanceSearchHint),
                TextField(
                  controller: _search,
                  enabled: !_busy && !_loading,
                  decoration: InputDecoration(
                    labelText: l10n.commonSearch,
                    suffixIcon: IconButton(
                      tooltip: l10n.commonSearch,
                      onPressed: _busy || _loading ? null : _loadTargets,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => _loadTargets(),
                ),
                if (_loading) const LinearProgressIndicator(),
                DropdownButtonFormField<SupplierPaymentTarget>(
                  key: ValueKey(_targetVersion),
                  initialValue: _target,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.supplierAdvanceDocument,
                  ),
                  items: [
                    for (final target in _targets)
                      DropdownMenuItem(
                        value: target,
                        child: Text(
                          '${switch (target.kind) {
                            SupplierPaymentTargetKind.purchase => l10n.suppliersPurchases,
                            SupplierPaymentTargetKind.purchaseOrder => l10n.suppliersPos,
                            SupplierPaymentTargetKind.supplierBill => l10n.supplierBills,
                          }} · ${target.reference} · ${Formatters.currency(target.balanceAmount)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (value) =>
                      value == null ? l10n.messagesRequired : null,
                  onChanged: _busy || _loading
                      ? null
                      : (value) => setState(() => _target = value),
                ),
              ],
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
                          amount > 1e9 ||
                          (source != null &&
                              (amount > source.availableAmount ||
                                  amount > (_target?.balanceAmount ?? 0)))
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
              if (source == null) ...[
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
                TextFormField(
                  controller: _reference,
                  enabled: !_busy,
                  maxLength: 100,
                  decoration: InputDecoration(labelText: l10n.fieldsReference),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || _loading ? null : _submit,
                child: Text(
                  source == null ? l10n.commonSave : l10n.supplierAdvanceApply,
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
