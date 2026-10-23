import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart';
import '../../data/models/unapplied_cash.dart';
import '../../data/repositories/api_result.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/movable_dialog.dart';
import 'unapplied_cash_operation.dart';
import 'unapplied_cash_providers.dart';

Future<void> showUnappliedCashReceiveDialog(
  BuildContext context, {
  required Customer customer,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => UnappliedCashReceiveDialog(customer: customer),
);

String cashErrorMessage(AppLocalizations l10n, ApiError error) {
  if (error.outcomeUnknown) return l10n.cashPendingNotice;
  if (error.isNetwork) return l10n.cashConnectionRequired;
  return switch (error.code) {
    'CUSTOMER_ALREADY_IN_CREDIT' => l10n.cashAlreadyInCredit,
    'PERIOD_CLOSED' => l10n.cashPeriodClosed,
    'CASH_REPLAY_UNSUPPORTED' => l10n.cashReplayUnsupported,
    'CASH_PENDING_OPERATION' => l10n.cashOtherPending,
    'CASH_RECOVERY_REQUIRED' ||
    'CASH_SCOPE_CHANGED' ||
    'IDEMPOTENCY_CONFLICT' => l10n.cashRecoveryRequired,
    _ => l10n.cashOperationFailed,
  };
}

class UnappliedCashReceiveDialog extends ConsumerStatefulWidget {
  const UnappliedCashReceiveDialog({super.key, required this.customer});
  final Customer customer;

  @override
  ConsumerState<UnappliedCashReceiveDialog> createState() =>
      _UnappliedCashReceiveDialogState();
}

class _UnappliedCashReceiveDialogState
    extends ConsumerState<UnappliedCashReceiveDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _dateText = TextEditingController();
  late DateTime _date;
  CashScope? _scope;
  String _method = 'Cash';
  bool _initializing = true;
  bool _submitting = false;
  CashResult? _result;
  ApiError? _localError;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _dateText.text = isoDate(_date);
    _scope = ref.read(currentCashScopeProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final scope = _scope;
      if (scope != null) {
        await ref.read(cashOperationProvider(scope).notifier).restore();
        if (!mounted) return;
        final pending = ref.read(cashOperationProvider(scope)).pending;
        if (pending?.request.operation == CashOperation.receive &&
            pending?.request.customerId == widget.customer.id) {
          final body = pending!.request.body;
          _amount.text = (cashMinor(body['amount']) / 100).toStringAsFixed(2);
          _date = DateTime.parse(body['operation_date'] as String);
          _dateText.text = isoDate(_date);
          _method = body['payment_method'] as String;
        }
      }
      if (mounted) setState(() => _initializing = false);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _dateText.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(
      context,
      initialDate: _date,
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _dateText.text = isoDate(picked);
      });
    }
  }

  Future<void> _submit(CashScope scope, bool retry) async {
    if (_submitting ||
        _initializing ||
        (!retry && !(_form.currentState?.validate() ?? false))) {
      return;
    }
    setState(() {
      _submitting = true;
      _localError = null;
    });
    try {
      final operation = ref.read(cashOperationProvider(scope).notifier);
      final result = retry
          ? await operation.resume()
          : await operation.start(
              CashRequest.receive(
                customerId: widget.customer.id,
                amountMinor: parseCashMinor(_amount.text),
                date: isoDate(_date),
                method: _method,
              ),
            );
      if (!mounted) return;
      if (result case ApiSuccess(:final data)) setState(() => _result = data);
    } catch (_) {
      if (mounted) {
        setState(
          () => _localError = const ApiError(
            message: '',
            code: 'CASH_RECOVERY_REQUIRED',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final scope = ref.watch(currentCashScopeProvider);
    final allowed =
        ref.watch(authProvider).user?.hasPermission('payments', 'create') ??
        false;
    final operation = _scope == null
        ? const CashOperationState()
        : ref.watch(cashOperationProvider(_scope!));
    final pending = operation.pending;
    final ownPending =
        pending != null &&
        pending.request.operation == CashOperation.receive &&
        pending.request.customerId == widget.customer.id;
    final busy =
        _initializing ||
        _submitting ||
        operation.phase == CashOperationPhase.sending;
    final locked =
        busy ||
        pending != null ||
        operation.phase == CashOperationPhase.recoveryRequired;
    final active = allowed && scope != null && scope == _scope;
    final canRetry =
        ownPending &&
        pending.replayPolicy ==
            CashCapabilities.expected(CashOperation.receive);
    final error = _localError ?? operation.error;
    final result = _result;
    final height =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        80;
    return PopScope(
      canPop: !busy,
      child: MovableDialog(
        dialogId: 'unapplied_receive',
        enableEscapeKey: true,
        autofocusEscape: true,
        maxWidth: 560,
        maxHeight: math.max(160, math.min(720, height)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                AppSpacing.space6,
                AppSpacing.space6,
                AppSpacing.space4,
              ),
              child: Row(
                children: [
                  Icon(
                    result == null
                        ? Icons.savings_outlined
                        : Icons.check_circle_outline,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Text(
                      result == null
                          ? l10n.cashReceiveAdvance
                          : l10n.cashReceived,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space6,
                ),
                child: result != null
                    ? Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.space6,
                          ),
                          child: Text(
                            l10n.cashReceivedDetails(
                              Formatters.currency(
                                (result.amountMinor ??
                                        parseCashMinor(_amount.text)) /
                                    100,
                              ),
                              '${result.paymentId}',
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      )
                    : !active
                    ? Semantics(
                        liveRegion: true,
                        child: ErrorBanner(
                          message: l10n.cashNoCreatePermission,
                        ),
                      )
                    : _initializing
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.space6),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.customer.customerName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              widget.customer.customerCode,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: AppSpacing.space3),
                            Text(l10n.cashReceiveHint),
                            const SizedBox(height: AppSpacing.space6),
                            if (pending != null) ...[
                              Semantics(
                                liveRegion: true,
                                child: ErrorBanner(
                                  message: ownPending
                                      ? (canRetry
                                            ? l10n.cashPendingNotice
                                            : l10n.cashRecoveryRequired)
                                      : l10n.cashOtherPending,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.space4),
                            ],
                            FormFieldShell(
                              label: l10n.cashAmount,
                              required: true,
                              child: Semantics(
                                label: l10n.cashAmount,
                                child: TextFormField(
                                  key: const Key('cash_receive_amount'),
                                  controller: _amount,
                                  enabled: !locked,
                                  autofocus: pending == null,
                                  textDirection: TextDirection.ltr,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: formInputDecoration(
                                    hintText: '0.00',
                                  ),
                                  validator: (value) {
                                    try {
                                      parseCashMinor(value ?? '');
                                      return null;
                                    } on FormatException {
                                      return l10n.cashInvalidAmount;
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space4),
                            FormFieldShell(
                              label: l10n.cashOperationDate,
                              required: true,
                              child: Semantics(
                                label: l10n.cashOperationDate,
                                child: TextFormField(
                                  key: const Key('cash_receive_date'),
                                  controller: _dateText,
                                  readOnly: true,
                                  enabled: !locked,
                                  textDirection: TextDirection.ltr,
                                  onTap: locked ? null : _pickDate,
                                  decoration: formInputDecoration().copyWith(
                                    suffixIcon: IconButton(
                                      tooltip: l10n.cashOperationDate,
                                      onPressed: locked ? null : _pickDate,
                                      icon: const Icon(
                                        Icons.calendar_today_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space4),
                            FormFieldShell(
                              label: l10n.customersMethod,
                              required: true,
                              child: DropdownButtonFormField<String>(
                                key: const Key('cash_receive_method'),
                                initialValue: _method,
                                decoration: formInputDecoration(),
                                isExpanded: true,
                                items: [
                                  for (final method in cashMethods)
                                    DropdownMenuItem(
                                      value: method,
                                      child: Text(switch (method) {
                                        'Cash' => l10n.paymentsMethodCash,
                                        'Bank' => l10n.paymentsMethodBank,
                                        _ => method,
                                      }),
                                    ),
                                ],
                                onChanged: locked
                                    ? null
                                    : (method) {
                                        if (method != null) {
                                          setState(() => _method = method);
                                        }
                                      },
                              ),
                            ),
                            if (error != null &&
                                !(ownPending && error.outcomeUnknown)) ...[
                              const SizedBox(height: AppSpacing.space4),
                              Semantics(
                                liveRegion: true,
                                child: ErrorBanner(
                                  message: cashErrorMessage(l10n, error),
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.space6),
                          ],
                        ),
                      ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.space3,
                runSpacing: AppSpacing.space2,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.commonClose),
                  ),
                  if (active && result == null)
                    FilledButton.icon(
                      key: const Key('cash_receive_submit'),
                      onPressed:
                          busy ||
                              (_localError != null) ||
                              (pending != null ? !canRetry : locked)
                          ? null
                          : () => _submit(scope, ownPending),
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.savings_outlined),
                      label: Text(
                        ownPending ? l10n.commonRetry : l10n.cashReceiveAdvance,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
