import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart';
import '../../data/models/unapplied_cash.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/invoice_repository.dart';
import '../../data/repositories/unapplied_cash_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/movable_dialog.dart';
import 'unapplied_cash_operation.dart';
import 'unapplied_cash_providers.dart';
import 'unapplied_cash_receive_dialog.dart';

class UnappliedCashActionDialog extends ConsumerStatefulWidget {
  const UnappliedCashActionDialog({
    super.key,
    required this.customer,
    this.receipt,
  });
  final Customer customer;
  final CashReceipt? receipt;
  @override
  ConsumerState<UnappliedCashActionDialog> createState() =>
      _UnappliedCashActionDialogState();
}

class _UnappliedCashActionDialogState
    extends ConsumerState<UnappliedCashActionDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _dateText = TextEditingController();
  final _reason = TextEditingController();
  DateTime _date = DateTime.now();
  String _method = 'Cash';
  CashScope? _scope;
  CashReceipt? _liveReceipt;
  CashRequest? _review;
  CashResult? _result;
  ApiError? _readError;
  ApiError? _localError;
  bool _initializing = true;
  bool _loading = false;
  bool _submitting = false;
  bool _eligible = false;
  bool _fatal = false;
  int _available = 0;

  bool get _reverse => widget.receipt != null;
  CashOperation get _kind =>
      _reverse ? CashOperation.reverse : CashOperation.refund;
  CashReceipt? get _receipt => _liveReceipt ?? widget.receipt;
  CashOperationState get _operation => _scope == null
      ? const CashOperationState()
      : ref.read(cashOperationProvider(_scope!));
  bool get _allowed {
    final user = ref.read(authProvider).user;
    return _scope != null &&
        ref.read(currentCashScopeProvider) == _scope &&
        (user?.hasPermission('payments', _reverse ? 'delete' : 'create') ??
            false) &&
        (user?.hasPermission('payments', 'read') ?? false);
  }

  bool get _busy =>
      _initializing ||
      _submitting ||
      _operation.phase == CashOperationPhase.sending;
  bool get _locked =>
      _busy ||
      _loading ||
      _review != null ||
      _operation.pending != null ||
      _fatal ||
      _operation.phase == CashOperationPhase.recoveryRequired;

  @override
  void initState() {
    super.initState();
    _scope = ref.read(currentCashScopeProvider);
    _dateText.text = isoDate(_date);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_allowed) {
        await ref.read(cashOperationProvider(_scope!).notifier).restore();
        if (!mounted) return;
        final pending = _operation.pending;
        if (_owns(pending)) {
          final body = pending!.request.body;
          if (_reverse) {
            _reason.text = body['reason'] as String;
          } else {
            _amount.text = (cashMinor(body['amount']) / 100).toStringAsFixed(2);
            _date = DateTime.parse(body['operation_date'] as String);
            _dateText.text = isoDate(_date);
            _method = body['payment_method'] as String;
          }
        }
        await _load();
      }
      if (mounted) setState(() => _initializing = false);
    });
  }

  bool _owns(PendingCashOperation? pending) =>
      pending != null &&
      pending.request.operation == _kind &&
      pending.request.customerId == widget.customer.id &&
      (!_reverse || pending.request.paymentId == widget.receipt!.paymentId);

  @override
  void dispose() {
    _amount.dispose();
    _dateText.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_allowed || !mounted) return;
    setState(() {
      _loading = true;
      _eligible = false;
      _readError = null;
    });
    try {
      final repository = ref.read(unappliedCashRepositoryProvider);
      if (_reverse) {
        final result = await repository.reversibleReceipt(
          widget.customer.id,
          widget.receipt!.paymentId,
        );
        if (result case ApiFailure(:final error)) throw error;
        if (!mounted || !_allowed) return;
        setState(() {
          _liveReceipt = result.requireData;
          _eligible = true;
        });
      } else {
        final result = await repository.summary(
          widget.customer.id,
          date: isoDate(_date),
          limit: 1,
        );
        if (result case ApiFailure(:final error)) throw error;
        if (!mounted || !_allowed) return;
        setState(() {
          _available = result.requireData.refundableMinor;
          _eligible = true;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => _readError = failure is ApiError
              ? failure
              : const ApiError(message: '', code: 'CASH_RECOVERY_REQUIRED'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(
      context,
      initialDate: _date,
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null || !mounted || _locked) return;
    setState(() {
      _date = picked;
      _dateText.text = isoDate(picked);
    });
    await _load();
  }

  void _prepare() {
    if (_locked ||
        !_allowed ||
        !_eligible ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final request = _reverse
        ? CashRequest.reverse(
            customerId: widget.customer.id,
            paymentId: widget.receipt!.paymentId,
            reason: _reason.text,
          )
        : CashRequest.refund(
            customerId: widget.customer.id,
            amountMinor: parseCashMinor(_amount.text),
            date: isoDate(_date),
            method: _method,
          );
    setState(() {
      _review = request;
      _localError = null;
    });
  }

  Future<void> _submit(bool retry) async {
    if (_busy ||
        !_allowed ||
        _fatal ||
        (!retry && (_review == null || !_eligible || _loading))) {
      return;
    }
    setState(() {
      _submitting = true;
      _localError = null;
    });
    try {
      final controller = ref.read(cashOperationProvider(_scope!).notifier);
      final result = retry
          ? await controller.resume()
          : await controller.start(_review!);
      if (!mounted) return;
      if (result case ApiSuccess(:final data)) {
        setState(() => _result = data);
      }
      if (result case ApiFailure()) {
        setState(() => _review = null);
        if (_operation.pending == null) await _load();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _fatal = true;
          _localError = const ApiError(
            message: '',
            code: 'CASH_RECOVERY_REQUIRED',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _methodLabel(AppLocalizations l10n, String method) => switch (method) {
    'Cash' => l10n.paymentsMethodCash,
    'Bank' => l10n.paymentsMethodBank,
    _ => method,
  };

  Future<void> _openInvoice(int invoiceId) async {
    final result = await ref.read(invoiceRepositoryProvider).invoice(invoiceId);
    if (!mounted) return;
    if (result case ApiSuccess(:final data)) {
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push('/sales/print-preview', extra: data);
    } else if (result case ApiFailure(:final error)) {
      setState(() => _localError = error);
    }
  }

  String _message(AppLocalizations l10n, ApiError error) =>
      switch (error.code) {
        'INSUFFICIENT_CASH' => l10n.cashInsufficientFunds,
        'INSUFFICIENT_UNAPPLIED_CASH' => l10n.cashInvalidRefund,
        'UNAPPLIED_ALREADY_APPLIED' ||
        'CASH_RECEIPT_NOT_REVERSIBLE' ||
        'RECEIPT_NOT_FOUND' ||
        'INVALID_SOURCE' => l10n.cashReverseUnavailable,
        'ALREADY_VOIDED' => l10n.cashAlreadyReversed,
        _ => cashErrorMessage(l10n, error),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.watch(authProvider);
    ref.watch(currentCashScopeProvider);
    if (_scope != null) ref.watch(cashOperationProvider(_scope!));
    final operation = _operation;
    final pending = operation.pending;
    final own = _owns(pending);
    final canRetry =
        own && pending!.replayPolicy == CashCapabilities.expected(_kind);
    final error = _localError ?? operation.error ?? _readError;
    final success = _result;
    final title = success != null
        ? (_reverse ? l10n.cashReversedSuccess : l10n.cashRefundedSuccess)
        : (_reverse ? l10n.cashReverse : l10n.cashRefund);
    final denied =
        !(ref
                .read(authProvider)
                .user
                ?.hasPermission('payments', _reverse ? 'delete' : 'create') ??
            false)
        ? (_reverse
              ? l10n.cashNoReversePermission
              : l10n.cashNoCreatePermission)
        : l10n.cashNoReadPermission;
    final height = math.max(
      160.0,
      math.min(
        760.0,
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            80,
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: MovableDialog(
        dialogId: _reverse ? 'unapplied_reverse' : 'unapplied_refund',
        enableEscapeKey: true,
        maxWidth: 560,
        maxHeight: height,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Row(
                children: [
                  Icon(
                    success != null
                        ? Icons.check_circle_outline
                        : (_reverse
                              ? Icons.undo_outlined
                              : Icons.payments_outlined),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Text(
                      title,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (success != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.space6,
                          ),
                          child: Text(
                            _reverse
                                ? (operation.phase ==
                                          CashOperationPhase.alreadyVoided
                                      ? l10n.cashAlreadyReversed
                                      : l10n.cashReversedDetails(
                                          _receipt!.paymentNo,
                                        ))
                                : l10n.cashRefundedDetails(
                                    Formatters.currency(
                                      (success.amountMinor ??
                                              parseCashMinor(_amount.text)) /
                                          100,
                                    ),
                                    '${success.paymentId}',
                                  ),
                          ),
                        ),
                      )
                    else if (!_allowed)
                      ErrorBanner(message: denied)
                    else ...[
                      Text(
                        widget.customer.customerName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(widget.customer.customerCode),
                      const SizedBox(height: AppSpacing.space3),
                      Text(
                        _reverse ? l10n.cashReverseHint : l10n.cashRefundHint,
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      if (_reverse) ...[
                        Text(
                          _receipt!.paymentNo,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${l10n.cashOriginal}: ${Formatters.currency(_receipt!.originalMinor / 100)}',
                        ),
                        Text(
                          '${l10n.cashOperationDate}: ${Formatters.date(_receipt!.date)}',
                        ),
                        const SizedBox(height: AppSpacing.space4),
                      ],
                      if (pending != null)
                        Semantics(
                          liveRegion: true,
                          child: ErrorBanner(
                            message: own
                                ? (canRetry
                                      ? l10n.cashPendingNotice
                                      : l10n.cashRecoveryRequired)
                                : l10n.cashOtherPending,
                          ),
                        ),
                      if (error != null && !(own && error.outcomeUnknown)) ...[
                        Semantics(
                          liveRegion: true,
                          child: ErrorBanner(message: _message(l10n, error)),
                        ),
                        for (final blocker in error.blockedBy) ...[
                          Text(
                            l10n.cashDependencySource(
                              '${blocker.sourceId}',
                              Formatters.currency(blocker.consumed),
                            ),
                          ),
                          for (final invoiceId in blocker.invoices)
                            if (ref
                                    .read(authProvider)
                                    .user
                                    ?.hasPermission('invoices', 'read') ??
                                false)
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _openInvoice(invoiceId),
                                  child: Text(
                                    l10n.cashDependencyInvoice('$invoiceId'),
                                  ),
                                ),
                              )
                            else
                              Text(l10n.cashDependencyInvoice('$invoiceId')),
                        ],
                        const SizedBox(height: AppSpacing.space4),
                      ],
                      if (_initializing || _loading)
                        const Padding(
                          padding: EdgeInsets.all(AppSpacing.space6),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        if (_readError != null)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              onPressed: _busy ? null : _load,
                              child: Text(l10n.commonRetry),
                            ),
                          ),
                        if (!_reverse && _eligible) ...[
                          Text(
                            l10n.cashRefundable,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            Formatters.currency(_available / 100),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.space4),
                        ],
                        Form(
                          key: _form,
                          child: Column(
                            children: [
                              if (_reverse)
                                TextFormField(
                                  key: const Key('cash_action_reason'),
                                  controller: _reason,
                                  enabled: !_locked,
                                  maxLength: 500,
                                  minLines: 2,
                                  maxLines: 3,
                                  decoration: formInputDecoration().copyWith(
                                    labelText: l10n.cashReverseReason,
                                  ),
                                  validator: (value) =>
                                      (value?.trim().isEmpty ?? true) ||
                                          value!.trim().length > 500
                                      ? l10n.cashInvalidReason
                                      : null,
                                )
                              else ...[
                                TextFormField(
                                  key: const Key('cash_action_amount'),
                                  controller: _amount,
                                  enabled: !_locked,
                                  textDirection: TextDirection.ltr,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: formInputDecoration(
                                    hintText: '0.00',
                                  ).copyWith(labelText: l10n.cashAmount),
                                  validator: (value) {
                                    try {
                                      if (parseCashMinor(value ?? '') >
                                          _available) {
                                        return l10n.cashInvalidRefund;
                                      }
                                      return null;
                                    } on FormatException {
                                      return l10n.cashInvalidRefund;
                                    }
                                  },
                                ),
                                const SizedBox(height: AppSpacing.space4),
                                TextFormField(
                                  key: const Key('cash_action_date'),
                                  controller: _dateText,
                                  enabled: !_locked,
                                  readOnly: true,
                                  textDirection: TextDirection.ltr,
                                  onTap: _locked ? null : _pickDate,
                                  decoration: formInputDecoration().copyWith(
                                    labelText: l10n.cashOperationDate,
                                    suffixIcon: IconButton(
                                      tooltip: l10n.cashOperationDate,
                                      onPressed: _locked ? null : _pickDate,
                                      icon: const Icon(
                                        Icons.calendar_today_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.space4),
                                DropdownButtonFormField<String>(
                                  key: const Key('cash_action_method'),
                                  initialValue: _method,
                                  isExpanded: true,
                                  decoration: formInputDecoration().copyWith(
                                    labelText: l10n.customersMethod,
                                  ),
                                  items: [
                                    for (final method in cashMethods)
                                      DropdownMenuItem(
                                        value: method,
                                        child: Text(_methodLabel(l10n, method)),
                                      ),
                                  ],
                                  onChanged: _locked
                                      ? null
                                      : (method) {
                                          if (method != null) {
                                            setState(() => _method = method);
                                          }
                                        },
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_review != null && !_reverse) ...[
                          const SizedBox(height: AppSpacing.space4),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              '${l10n.cashConfirmRefund}: ${Formatters.currency(cashMinor(_review!.body['amount']) / 100)} · ${_methodLabel(l10n, _review!.body['payment_method'] as String)} · ${_review!.body['operation_date']}',
                            ),
                          ),
                        ],
                      ],
                    ],
                    const SizedBox(height: AppSpacing.space6),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Wrap(
                spacing: AppSpacing.space3,
                runSpacing: AppSpacing.space2,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.commonClose),
                  ),
                  if (_allowed && success == null) ...[
                    if (pending != null)
                      FilledButton.icon(
                        key: const Key('cash_action_retry'),
                        onPressed: _busy || !canRetry || _fatal
                            ? null
                            : () => _submit(true),
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.commonRetry),
                      )
                    else if (_review != null) ...[
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _review = null),
                        child: Text(l10n.cashEditReview),
                      ),
                      FilledButton.icon(
                        key: const Key('cash_action_confirm'),
                        onPressed: _busy ? null : () => _submit(false),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        style: _reverse
                            ? FilledButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onError,
                              )
                            : null,
                        label: Text(
                          _reverse
                              ? l10n.cashConfirmReverse
                              : l10n.cashConfirmRefund,
                        ),
                      ),
                    ] else
                      FilledButton(
                        key: const Key('cash_action_review'),
                        onPressed: _locked || !_eligible || _readError != null
                            ? null
                            : _prepare,
                        child: Text(
                          _reverse
                              ? l10n.cashReviewReverse
                              : l10n.cashReviewRefund,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
