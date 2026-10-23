import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart';
import '../../data/models/invoice.dart';
import '../../data/models/unapplied_cash.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/unapplied_cash_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart';
import '../../widgets/detail_tab_grid.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/movable_dialog.dart';
import 'unapplied_cash_operation.dart';
import 'unapplied_cash_providers.dart';
import 'unapplied_cash_receive_dialog.dart';

Future<void> showUnappliedCashApplyDialog(
  BuildContext context, {
  required Customer customer,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => UnappliedCashApplyDialog(customer: customer),
);

class UnappliedCashApplyDialog extends ConsumerStatefulWidget {
  const UnappliedCashApplyDialog({super.key, required this.customer});
  final Customer customer;
  @override
  ConsumerState<UnappliedCashApplyDialog> createState() =>
      _UnappliedCashApplyDialogState();
}

class _UnappliedCashApplyDialogState
    extends ConsumerState<UnappliedCashApplyDialog> {
  final _amounts = <int, TextEditingController>{};
  final _known = <int, Invoice>{};
  Map<int, Invoice> _eligible = {};
  List<Invoice> _shown = [];
  final _dateText = TextEditingController();
  final _search = TextEditingController();
  DateTime _date = DateTime.now();
  CashScope? _scope;
  bool _initializing = true;
  bool _loading = false;
  bool _submitting = false;
  bool _invalid = false;
  bool _changed = false;
  bool _unsafe = false;
  int _capacity = 0;
  ApiError? _readError;
  ApiError? _localError;
  CashResult? _result;

  bool get _allowed {
    final user = ref.read(authProvider).user;
    return _scope != null &&
        ref.read(currentCashScopeProvider) == _scope &&
        (user?.hasPermission('payments', 'update') ?? false) &&
        (user?.hasPermission('payments', 'read') ?? false) &&
        (user?.hasPermission('invoices', 'read') ?? false);
  }

  CashOperationState get _operation => _scope == null
      ? const CashOperationState()
      : ref.read(cashOperationProvider(_scope!));
  bool get _busy =>
      _initializing ||
      _submitting ||
      _operation.phase == CashOperationPhase.sending;
  bool get _locked =>
      _busy ||
      _loading ||
      _operation.pending != null ||
      _unsafe ||
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
        if (pending?.request.operation == CashOperation.apply &&
            pending?.request.customerId == widget.customer.id) {
          final body = pending!.request.body;
          _date = DateTime.parse(body['operation_date'] as String);
          _dateText.text = isoDate(_date);
          for (final raw in body['allocations'] as List) {
            final line = cashObject(raw);
            _amounts[cashId(line['invoice_id'])] = TextEditingController(
              text: (cashMinor(line['amount']) / 100).toStringAsFixed(2),
            );
          }
        }
        await _load();
      }
      if (mounted) setState(() => _initializing = false);
    });
  }

  @override
  void dispose() {
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    _dateText.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_allowed || !mounted) return;
    setState(() {
      _loading = true;
      _readError = null;
    });
    try {
      final repository = ref.read(unappliedCashRepositoryProvider);
      final summary = await repository.summary(
        widget.customer.id,
        date: isoDate(_date),
        limit: 1,
      );
      if (summary case ApiFailure(:final error)) throw error;
      final invoices = await repository.eligibleInvoices(
        widget.customer.id,
        isoDate(_date),
      );
      if (invoices case ApiFailure(:final error)) throw error;
      if (!mounted || !_allowed) return;
      setState(() {
        _capacity = summary.requireData.availableMinor;
        _eligible = {
          for (final invoice in invoices.requireData) invoice.id: invoice,
        };
        _known.addAll(_eligible);
        for (final invoice in _eligible.values) {
          _amounts.putIfAbsent(invoice.id, () => TextEditingController());
        }
        _filter();
      });
    } catch (failure) {
      if (mounted) {
        setState(
          () => _readError = failure is ApiError
              ? failure
              : const ApiError(message: '', code: 'CASH_INVOICE_READ_FAILED'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final query = _search.text.trim().toLowerCase();
    final ids = {
      ..._eligible.keys,
      ..._amounts.entries
          .where((entry) => entry.value.text.trim().isNotEmpty)
          .map((entry) => entry.key),
    };
    _shown =
        [
          for (final id in ids)
            if (_known[id] case final Invoice invoice)
              if (query.isEmpty ||
                  invoice.invoiceNo.toLowerCase().contains(query))
                invoice,
        ]..sort((left, right) {
          final byDate = left.invoiceDate.compareTo(right.invoiceDate);
          return byDate != 0 ? byDate : left.id.compareTo(right.id);
        });
  }

  List<CashAllocation> _allocations() => [
    for (final entry in _amounts.entries)
      if (entry.value.text.trim().isNotEmpty)
        CashAllocation(
          invoiceId: entry.key,
          amountMinor: parseCashMinor(entry.value.text),
        ),
  ];
  int get _total {
    var total = 0;
    for (final controller in _amounts.values) {
      if (controller.text.trim().isEmpty) continue;
      try {
        total += parseCashMinor(controller.text);
      } on FormatException {
        return 0;
      }
    }
    return total;
  }

  void _auto() {
    var remaining = _capacity;
    for (final controller in _amounts.values) {
      controller.clear();
    }
    for (final invoice in _eligible.values.take(1000)) {
      final amount = math.min(remaining, cashMinor(invoice.balanceAmount));
      if (amount > 0) {
        _amounts[invoice.id]!.text = (amount / 100).toStringAsFixed(2);
        remaining -= amount;
      }
    }
    setState(() {
      _invalid = false;
      _filter();
    });
  }

  Future<void> _pickDate() async {
    final date = await pickDate(
      context,
      initialDate: _date,
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (date == null || !mounted || _locked) return;
    setState(() {
      _date = date;
      _dateText.text = isoDate(date);
    });
    await _load();
  }

  Future<void> _submit(bool retry) async {
    if (_busy || !_allowed || (!retry && _locked)) return;
    CashRequest? request;
    if (!retry) {
      try {
        final allocations = _allocations();
        final total = allocations.fold<int>(
          0,
          (sum, line) => sum + line.amountMinor,
        );
        if (_readError != null ||
            total > _capacity ||
            allocations.any(
              (line) =>
                  !_eligible.containsKey(line.invoiceId) ||
                  line.amountMinor >
                      cashMinor(_eligible[line.invoiceId]!.balanceAmount),
            )) {
          throw const FormatException();
        }
        request = CashRequest.apply(
          customerId: widget.customer.id,
          date: isoDate(_date),
          allocations: allocations,
        );
      } on FormatException {
        setState(() => _invalid = true);
        return;
      }
    }
    setState(() {
      _submitting = true;
      _invalid = false;
      _localError = null;
    });
    try {
      final controller = ref.read(cashOperationProvider(_scope!).notifier);
      final result = retry
          ? await controller.resume()
          : await controller.start(request!);
      if (!mounted) return;
      if (result case ApiSuccess(:final data)) {
        setState(() => _result = data);
      }
      if (result case ApiFailure(:final error)) {
        if (error.statusCode == 409 && _operation.pending == null) {
          setState(() => _changed = error.code != 'PERIOD_CLOSED');
          await _load();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unsafe = true;
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

  Widget _amount(Invoice invoice) => Semantics(
    label:
        '${invoice.invoiceNo} ${AppLocalizations.of(context)!.cashAllocation}',
    child: Focus(
      skipTraversal: true,
      onKeyEvent: (node, event) =>
          kIsWeb &&
              event.logicalKey != LogicalKeyboardKey.tab &&
              event.logicalKey != LogicalKeyboardKey.escape
          ? KeyEventResult.skipRemainingHandlers
          : KeyEventResult.ignored,
      child: DefaultTextEditingShortcuts(
        child: TextFormField(
          key: Key('cash_apply_${invoice.id}'),
          controller: _amounts[invoice.id],
          enabled: !_locked,
          textDirection: TextDirection.ltr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: formInputDecoration(hintText: '0.00'),
          onChanged: (_) => setState(() => _invalid = false),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.watch(authProvider);
    ref.watch(currentCashScopeProvider);
    if (_scope != null) ref.watch(cashOperationProvider(_scope!));
    final operation = _operation;
    final pending = operation.pending;
    final own =
        pending?.request.operation == CashOperation.apply &&
        pending?.request.customerId == widget.customer.id;
    final canRetry =
        own &&
        pending!.replayPolicy == CashCapabilities.expected(CashOperation.apply);
    final user = ref.read(authProvider).user;
    final denied = !(user?.hasPermission('payments', 'update') ?? false)
        ? l10n.cashNoUpdatePermission
        : !(user?.hasPermission('invoices', 'read') ?? false)
        ? l10n.cashNoInvoicePermission
        : !(user?.hasPermission('payments', 'read') ?? false)
        ? l10n.cashNoReadPermission
        : l10n.cashRecoveryRequired;
    final height = math.max(
      160.0,
      math.min(
        800.0,
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            80,
      ),
    );
    final error = _localError ?? operation.error;
    return PopScope(
      canPop: !_busy,
      child: MovableDialog(
        dialogId: 'unapplied_apply',
        enableEscapeKey: true,
        autofocusEscape: true,
        maxWidth: 960,
        maxHeight: height,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Row(
                children: [
                  Icon(
                    _result == null
                        ? Icons.account_balance_wallet_outlined
                        : Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Text(
                      _result == null
                          ? l10n.cashApply
                          : l10n.cashAppliedSuccess,
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
                    if (_result case final CashResult result)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.space6,
                          ),
                          child: Text(
                            l10n.cashAppliedDetails(
                              Formatters.currency(
                                (result.amountMinor ?? _total) / 100,
                              ),
                              '${result.applicationId}',
                            ),
                          ),
                        ),
                      )
                    else if (!_allowed)
                      Semantics(
                        liveRegion: true,
                        child: ErrorBanner(message: denied),
                      )
                    else ...[
                      Text(
                        widget.customer.customerName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(widget.customer.customerCode),
                      const SizedBox(height: AppSpacing.space3),
                      Text(l10n.cashApplyHint),
                      const SizedBox(height: AppSpacing.space4),
                      TextFormField(
                        key: const Key('cash_apply_date'),
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
                            icon: const Icon(Icons.calendar_today_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space4),
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
                      if (_changed)
                        Semantics(
                          liveRegion: true,
                          child: ErrorBanner(message: l10n.cashChangedBalances),
                        ),
                      if (_invalid)
                        Semantics(
                          liveRegion: true,
                          child: ErrorBanner(
                            message: l10n.cashInvalidAllocations,
                          ),
                        ),
                      if (error != null &&
                          !_changed &&
                          !(own && error.outcomeUnknown))
                        Semantics(
                          liveRegion: true,
                          child: ErrorBanner(
                            message: cashErrorMessage(l10n, error),
                          ),
                        ),
                      if (own)
                        for (final raw
                            in pending!.request.body['allocations'] as List)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.space1,
                            ),
                            child: Text(
                              '${l10n.customersInvoices} #${cashObject(raw)['invoice_id']}: ${Formatters.currency(cashMinor(cashObject(raw)['amount']) / 100)}',
                            ),
                          ),
                      if (_initializing || _loading)
                        const Padding(
                          padding: EdgeInsets.all(AppSpacing.space6),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_readError != null)
                        Column(
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: ErrorBanner(
                                message: cashErrorMessage(l10n, _readError!),
                              ),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _load,
                              child: Text(l10n.commonRetry),
                            ),
                          ],
                        )
                      else if (pending == null) ...[
                        Wrap(
                          spacing: AppSpacing.space6,
                          runSpacing: AppSpacing.space3,
                          children: [
                            _metric(l10n.cashEligible, _capacity),
                            _metric(l10n.cashSelected, _total),
                            _metric(l10n.cashAfterApply, _capacity - _total),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.space4),
                        TextField(
                          key: const Key('cash_apply_search'),
                          controller: _search,
                          enabled: !_locked,
                          decoration: formInputDecoration().copyWith(
                            labelText: l10n.cashSearchInvoices,
                            prefixIcon: const Icon(Icons.search),
                          ),
                          onChanged: (_) => setState(_filter),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            key: const Key('cash_apply_auto'),
                            onPressed: _locked ? null : _auto,
                            icon: const Icon(Icons.auto_fix_high_outlined),
                            label: Text(l10n.cashAutoAllocate),
                          ),
                        ),
                        LayoutBuilder(
                          builder: (context, constraints) => _shown.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(
                                    AppSpacing.space6,
                                  ),
                                  child: Text(l10n.cashNoOpenInvoices),
                                )
                              : constraints.maxWidth < 640
                              ? Column(
                                  children: [
                                    for (final invoice in _shown)
                                      Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(
                                            AppSpacing.space4,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(invoice.invoiceNo),
                                              Text(
                                                Formatters.date(
                                                  invoice.invoiceDate,
                                                ),
                                              ),
                                              Text(
                                                '${l10n.cashInvoiceBalance}: ${Formatters.currency((_eligible[invoice.id]?.balanceAmount ?? 0))}',
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.space2,
                                              ),
                                              _amount(invoice),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                )
                              : SizedBox(
                                  height: 320,
                                  child: DetailTabGrid<Invoice>(
                                    key: ValueKey((
                                      Localizations.localeOf(context),
                                      Theme.of(context).brightness,
                                      _locked,
                                    )),
                                    data: _shown,
                                    widthKey: 'customer_cash_apply',
                                    buildColumns: (_) => [
                                      PlutoColumn(
                                        title: l10n.customersInvoices,
                                        field: 'number',
                                        type: PlutoColumnType.text(),
                                        readOnly: true,
                                        width: 180,
                                      ),
                                      PlutoColumn(
                                        title: l10n.commonDate,
                                        field: 'date',
                                        type: PlutoColumnType.text(),
                                        readOnly: true,
                                        width: 150,
                                      ),
                                      PlutoColumn(
                                        title: l10n.cashInvoiceBalance,
                                        field: 'balance',
                                        type: PlutoColumnType.text(),
                                        readOnly: true,
                                        width: 180,
                                      ),
                                      PlutoColumn(
                                        title: l10n.cashAllocation,
                                        field: 'allocation',
                                        type: PlutoColumnType.text(),
                                        readOnly: true,
                                        width: 210,
                                        renderer: (cell) => _amount(
                                          _known[cell.row.cells['id']!.value
                                              as int]!,
                                        ),
                                      ),
                                      PlutoColumn(
                                        title: '',
                                        field: 'id',
                                        type: PlutoColumnType.number(),
                                        hide: true,
                                      ),
                                    ],
                                    gridRowFor: (invoice) => PlutoRow(
                                      cells: {
                                        'number': PlutoCell(
                                          value: invoice.invoiceNo,
                                        ),
                                        'date': PlutoCell(
                                          value: Formatters.date(
                                            invoice.invoiceDate,
                                          ),
                                        ),
                                        'balance': PlutoCell(
                                          value: Formatters.currency(
                                            _eligible[invoice.id]
                                                    ?.balanceAmount ??
                                                0,
                                          ),
                                        ),
                                        'allocation': PlutoCell(value: ''),
                                        'id': PlutoCell(value: invoice.id),
                                      },
                                    ),
                                  ),
                                ),
                        ),
                      ],
                      if (own)
                        Text(
                          '${l10n.cashSelected}: ${Formatters.currency(_total / 100)}',
                        ),
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
                  if (_allowed && _result == null)
                    FilledButton.icon(
                      key: const Key('cash_apply_submit'),
                      onPressed:
                          _busy ||
                              _unsafe ||
                              (pending != null
                                  ? !canRetry
                                  : (_locked || _readError != null))
                          ? null
                          : () => _submit(own),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(own ? l10n.commonRetry : l10n.cashApply),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, int minor) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(
        Formatters.currency(minor / 100),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  );
}
