import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart';
import '../../data/models/invoice.dart';
import '../../data/models/unapplied_cash.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/unapplied_cash_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart';
import 'unapplied_cash_providers.dart';

Future<void> showStoreCreditApplyDialog(
  BuildContext context, {
  required Customer customer,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => StoreCreditApplyDialog(customer: customer),
);

class StoreCreditApplyDialog extends ConsumerStatefulWidget {
  const StoreCreditApplyDialog({super.key, required this.customer});
  final Customer customer;

  @override
  ConsumerState<StoreCreditApplyDialog> createState() =>
      _StoreCreditApplyDialogState();
}

class _StoreCreditApplyDialogState
    extends ConsumerState<StoreCreditApplyDialog> {
  final _amounts = <int, TextEditingController>{};
  final _dateText = TextEditingController();
  DateTime _date = DateTime.now();
  List<Invoice> _invoices = const [];
  bool _loading = true;
  bool _submitting = false;
  bool _invalid = false;
  ApiError? _error;
  CashResult? _result;

  int get _poolMinor => cashMinor(widget.customer.creditBalance);

  int get _selectedMinor => _amounts.entries.fold(0, (total, entry) {
    final value = double.tryParse(entry.value.text.replaceAll(',', '')) ?? 0;
    return total + cashMinor(value);
  });

  int _balanceMinor(Invoice invoice) => cashMinor(invoice.balanceAmount);

  @override
  void initState() {
    super.initState();
    _dateText.text = isoDate(_date);
    _load();
  }

  @override
  void dispose() {
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    _dateText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(unappliedCashRepositoryProvider)
        .eligibleInvoices(widget.customer.id, isoDate(_date));
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case ApiSuccess(:final data):
          _invoices = data;
        case ApiFailure(:final error):
          _error = error;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(
      context,
      initialDate: _date,
      lastDate: DateTime.now(),
    );
    if (picked == null || picked == _date || !mounted) return;
    setState(() {
      _date = picked;
      _dateText.text = isoDate(picked);
    });
    await _load();
  }

  Future<void> _submit(bool retry) async {
    if (_submitting) return;
    CashRequest? request;
    if (!retry) {
      final allocations = <CashAllocation>[];
      for (final invoice in _invoices) {
        final controller = _amounts[invoice.id];
        if (controller == null || controller.text.trim().isEmpty) continue;
        final value = double.tryParse(controller.text.replaceAll(',', ''));
        final minor = value == null ? -1 : cashMinor(value);
        if (minor <= 0 || minor > _balanceMinor(invoice)) {
          setState(() => _invalid = true);
          return;
        }
        allocations.add(
          CashAllocation(invoiceId: invoice.id, amountMinor: minor),
        );
      }
      final total = allocations.fold<int>(
        0,
        (sum, line) => sum + line.amountMinor,
      );
      if (allocations.isEmpty || total > _poolMinor) {
        setState(() => _invalid = true);
        return;
      }
      request = CashRequest.storeCreditApply(
        customerId: widget.customer.id,
        date: isoDate(_date),
        allocations: allocations,
      );
    }
    final scope = ref.read(currentCashScopeProvider);
    if (scope == null) return;
    setState(() {
      _submitting = true;
      _invalid = false;
      _error = null;
    });
    try {
      final controller = ref.read(cashOperationProvider(scope).notifier);
      final result = retry
          ? await controller.resume()
          : await controller.start(request!);
      if (!mounted) return;
      switch (result) {
        case ApiSuccess(:final data):
          setState(() => _result = data);
        case ApiFailure(:final error):
          setState(() => _error = error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _close() => Navigator.of(context).pop();

  Widget _invoiceRow(Invoice invoice) {
    final controller = _amounts.putIfAbsent(
      invoice.id,
      TextEditingController.new,
    );
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoice.invoiceNo),
                Text(
                  '${Formatters.date(invoice.invoiceDate)} · '
                  '${l10n.cashInvoiceBalance} ${Formatters.currency(_balanceMinor(invoice) / 100)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              key: Key('credit_apply_${invoice.id}'),
              controller: controller,
              enabled: !_submitting && _result == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(isDense: true, labelText: l10n.cashAllocation),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: AppSpacing.space2),
          TextButton(
            onPressed: _submitting || _result != null
                ? null
                : () {
                    controller.text = (_balanceMinor(invoice) / 100)
                        .toStringAsFixed(2);
                    setState(() {});
                  },
            child: Text(l10n.cashAutoAllocate),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedMinor = _selectedMinor;
    if (_result case final data?) {
      return AlertDialog(
        title: Text(l10n.cashCreditAppliedSuccess),
        content: Text(
          l10n.cashCreditAppliedDetails(
            Formatters.currency((data.amountMinor ?? 0) / 100),
            '${data.applicationId ?? 0}',
          ),
        ),
        actions: [
          FilledButton(onPressed: _close, child: Text(l10n.commonClose)),
        ],
      );
    }
    return AlertDialog(
      title: Text(l10n.cashCreditApply),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.cashCreditApplyHint),
            const SizedBox(height: AppSpacing.space3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.cashCreditEligible}: '
                    '${Formatters.currency(_poolMinor / 100)}',
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _dateText,
                    readOnly: true,
                    onTap: _pickDate,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.cashOperationDate,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error case final error?)
              Text(
                error.message,

                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              )
            else if (_invoices.isEmpty)
              Text(l10n.cashNoOpenInvoices)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(children: _invoices.map(_invoiceRow).toList()),
                ),
              ),
            if (_invalid)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.space2),
                child: Text(
                  l10n.cashInvalidAllocations,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              '${l10n.cashSelected}: '
              '${Formatters.currency(selectedMinor / 100)}',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _close, child: Text(l10n.commonCancel)),
        if (_error != null && _result == null)
          TextButton(
            onPressed: _submitting ? null : () => _submit(true),
            child: Text(l10n.commonRetry),
          ),
        FilledButton(
          key: const Key('credit_apply_submit'),
          onPressed: _submitting || _loading || selectedMinor <= 0
              ? null
              : () => _submit(false),
          child: Text(l10n.cashApplyLabel),
        ),
      ],
    );
  }
}
