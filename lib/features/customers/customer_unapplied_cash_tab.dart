import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/customer.dart';
import '../../data/models/unapplied_cash.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/invoice_repository.dart';
import '../../widgets/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../payments/unified_payment_labels.dart';
import '../../widgets/detail_tab_grid.dart';
import '../../widgets/form_helpers.dart';
import 'customer_providers.dart';
import 'unapplied_cash_providers.dart';
import 'unapplied_cash_receive_dialog.dart';
import 'unapplied_cash_apply_dialog.dart';
import 'unapplied_cash_refund_dialog.dart';
import 'unapplied_cash_reverse_dialog.dart';

class CustomerUnappliedCashTab extends ConsumerStatefulWidget {
  const CustomerUnappliedCashTab({
    super.key,
    required this.customer,
    required this.sessionId,
  });
  final Customer customer;
  final int sessionId;

  @override
  ConsumerState<CustomerUnappliedCashTab> createState() =>
      _CustomerUnappliedCashTabState();
}

class _CustomerUnappliedCashTabState
    extends ConsumerState<CustomerUnappliedCashTab> {
  bool _activity = false;
  int _receiptPage = 1;
  int _activityPage = 1;
  int? _openingInvoice;
  static const _limit = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!(ref.watch(authProvider).user?.hasPermission('payments', 'read') ??
        false)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: Text(l10n.cashNoReadPermission),
        ),
      );
    }
    ref.listen(customerDetailFromDateProvider(widget.sessionId), (
      previous,
      next,
    ) {
      if (previous != next && _activityPage != 1) {
        setState(() => _activityPage = 1);
      }
    });
    ref.listen(customerDetailToDateProvider(widget.sessionId), (
      previous,
      next,
    ) {
      if (previous != next && _activityPage != 1) {
        setState(() => _activityPage = 1);
      }
    });
    final args = (
      customerId: widget.customer.id,
      date: isoDate(DateTime.now()),
      page: _receiptPage,
      limit: _limit,
    );
    final summary = ref.watch(customerCashSummaryProvider(args));
    return switch (summary) {
      AsyncData(:final value) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          final header = <Widget>[
            Wrap(
              spacing: AppSpacing.space3,
              runSpacing: AppSpacing.space3,
              children: [
                _balance(
                  l10n.cashInvoiceBalance,
                  widget.customer.currentBalance,
                  narrow
                      ? constraints.maxWidth - 32
                      : (constraints.maxWidth - 56) / 3,
                ),
                _balance(
                  l10n.cashStoreCredit,
                  widget.customer.creditBalance,
                  narrow
                      ? constraints.maxWidth - 32
                      : (constraints.maxWidth - 56) / 3,
                ),
                _balance(
                  l10n.cashHeld,
                  value.remainingMinor / 100,
                  narrow
                      ? constraints.maxWidth - 32
                      : (constraints.maxWidth - 56) / 3,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              l10n.cashSummaryHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.space3),
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: Text(l10n.cashReceipts),
                  selected: !_activity,
                  onSelected: (_) => setState(() => _activity = false),
                ),
                if (ref
                        .watch(authProvider)
                        .user
                        ?.hasPermission('payments', 'update') ??
                    false)
                  OutlinedButton.icon(
                    onPressed: () => showUnappliedCashApplyDialog(
                      context,
                      customer: widget.customer,
                    ),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: Text(l10n.cashApply),
                  ),
                ChoiceChip(
                  label: Text(l10n.cashActivity),
                  selected: _activity,
                  onSelected: (_) => setState(() => _activity = true),
                ),
                if (ref
                        .watch(authProvider)
                        .user
                        ?.hasPermission('payments', 'create') ??
                    false)
                  OutlinedButton.icon(
                    onPressed: () => showUnappliedCashRefundDialog(
                      context,
                      customer: widget.customer,
                    ),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(l10n.cashRefund),
                  ),
                IconButton(
                  tooltip: l10n.commonRefresh,
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.invalidate(customerCashSummaryProvider(args));
                    ref.invalidate(customerCashActivityProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
          ];
          final history = _activity
              ? _activityPanel(narrow)
              : _receipts(value.receipts, narrow);
          return narrow
              ? ListView(
                  padding: const EdgeInsets.all(AppSpacing.space4),
                  children: [...header, history],
                )
              : Padding(
                  padding: const EdgeInsets.all(AppSpacing.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...header,
                      Expanded(child: history),
                    ],
                  ),
                );
        },
      ),
      AsyncError(:final error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: _error(
            error,
            () => ref.invalidate(customerCashSummaryProvider(args)),
          ),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _balance(String label, num? amount, double width) => SizedBox(
    width: math.max(0, width),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.space2),
            Text(
              amount == null
                  ? AppLocalizations.of(context)!.cashUnavailable
                  : Formatters.currency(amount),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _error(Object error, VoidCallback retry) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ErrorBanner(
          message: error is ApiError
              ? cashErrorMessage(l10n, error)
              : l10n.cashOperationFailed,
        ),
        const SizedBox(height: AppSpacing.space3),
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.commonRetry),
        ),
      ],
    );
  }

  String _status(CashReceipt receipt, AppLocalizations l10n) =>
      receipt.voidedAt != null
      ? l10n.cashStatusReversed
      : receipt.appliedMinor == 0 && receipt.refundedMinor == 0
      ? l10n.cashStatusUnused
      : receipt.remainingMinor > 0
      ? l10n.cashStatusPartial
      : l10n.cashStatusUsed;

  PlutoColumn _column(String field, String title, {double width = 145}) =>
      PlutoColumn(
        title: title,
        field: field,
        type: PlutoColumnType.text(),
        width: width,
        readOnly: true,
        enableContextMenu: false,
        enableSorting: false,
      );

  Map<String, String> _receiptValues(CashReceipt receipt) {
    final l10n = AppLocalizations.of(context)!;
    return {
      'number': receipt.paymentNo,
      'date': Formatters.date(receipt.date),
      'method': _methodLabel(receipt.method, l10n),
      'original': Formatters.currency(receipt.originalMinor / 100),
      'applied': Formatters.currency(receipt.appliedMinor / 100),
      'refunded': Formatters.currency(receipt.refundedMinor / 100),
      'remaining': Formatters.currency(receipt.remainingMinor / 100),
      'status': _status(receipt, l10n),
    };
  }

  String _methodLabel(String value, AppLocalizations l10n) {
    final normalized = value.trim().toLowerCase().replaceAll(' ', '_');
    const known = {'cash', 'bank', 'card', 'mobile_wallet', 'credit', 'other'};
    return known.contains(normalized)
        ? unifiedMethodLabel(l10n, normalized)
        : value;
  }

  Widget _receipts(CashPage<CashReceipt> page, bool narrow) {
    final l10n = AppLocalizations.of(context)!;
    final canDelete =
        ref.watch(authProvider).user?.hasPermission('payments', 'delete') ??
        false;
    final byPayment = {
      for (final receipt in page.items) receipt.paymentId: receipt,
    };
    final labels = {
      'number': l10n.customersPaymentno,
      'date': l10n.commonDate,
      'method': l10n.customersMethod,
      'original': l10n.cashOriginal,
      'applied': l10n.cashApplied,
      'refunded': l10n.cashRefunded,
      'remaining': l10n.cashRemaining,
      'status': l10n.commonStatus,
    };
    final content = page.items.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(AppSpacing.space6),
            child: Center(child: Text(l10n.cashNoReceipts)),
          )
        : narrow
        ? Column(
            children: [
              for (final receipt in page.items)
                _card(
                  _receiptValues(receipt),
                  labels,
                  action: canDelete
                      ? _reverseAction(receipt, compact: false)
                      : null,
                ),
            ],
          )
        : DetailTabGrid<CashReceipt>(
            key: ValueKey((
              Localizations.localeOf(context),
              Theme.of(context).brightness,
              canDelete,
            )),
            data: page.items,
            widthKey: 'customer_unapplied_cash_receipts',
            buildColumns: (_) => [
              for (final entry in labels.entries)
                _column(entry.key, entry.value),
              if (canDelete)
                PlutoColumn(
                  title: '',
                  field: 'reverse',
                  type: PlutoColumnType.number(),
                  width: 64,
                  readOnly: true,
                  frozen: PlutoColumnFrozen.end,
                  enableContextMenu: false,
                  enableSorting: false,
                  renderer: (cell) => _reverseAction(
                    byPayment[cell.cell.value as int]!,
                    compact: true,
                  ),
                ),
            ],
            gridRowFor: (receipt) => PlutoRow(
              cells: {
                for (final entry in _receiptValues(receipt).entries)
                  entry.key: PlutoCell(value: entry.value),
                if (canDelete) 'reverse': PlutoCell(value: receipt.paymentId),
              },
            ),
          );
    return _panel(
      content,
      page.page,
      page.totalPages,
      narrow,
      (next) => setState(() => _receiptPage = next),
    );
  }

  Widget _activityPanel(bool narrow) {
    final range = customerDetailRangeIso(ref, widget.sessionId);
    final args = (
      customerId: widget.customer.id,
      fromDate: range.from,
      toDate: range.to,
      page: _activityPage,
      limit: _limit,
    );
    final activity = ref.watch(customerCashActivityProvider(args));
    final l10n = AppLocalizations.of(context)!;
    final labels = {
      'date': l10n.commonDate,
      'operation': l10n.cashActivity,
      'amount': l10n.cashAmount,
      'invoices': l10n.customersInvoices,
    };
    Map<String, String> values(CashActivity activity) => {
      'date': Formatters.date(activity.date),
      'operation': activity.operation == CashOperation.apply
          ? l10n.cashApplyLabel
          : l10n.cashRefundLabel,
      'amount': Formatters.currency(activity.amountMinor / 100),
      'invoices': activity.lines
          .where((line) => line.invoiceId != null)
          .map((line) => line.invoiceNo ?? '${line.invoiceId}')
          .toSet()
          .join(', '),
    };
    return switch (activity) {
      AsyncData(:final value) => _panel(
        value.items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.space6),
                child: Center(child: Text(l10n.cashNoActivity)),
              )
            : narrow
            ? Column(
                children: [
                  for (final row in value.items)
                    _card(values(row), labels, action: _invoiceLinks(row)),
                ],
              )
            : DetailTabGrid<CashActivity>(
                key: ValueKey((
                  Localizations.localeOf(context),
                  Theme.of(context).brightness,
                )),
                data: value.items,
                widthKey: 'customer_unapplied_cash_activity',
                hiddenFields: const ['data'],
                buildColumns: (_) => [
                  _column('data', ''),
                  for (final entry in labels.entries)
                    if (entry.key == 'invoices')
                      PlutoColumn(
                        title: entry.value,
                        field: entry.key,
                        type: PlutoColumnType.text(),
                        width: 220,
                        readOnly: true,
                        enableContextMenu: false,
                        renderer: (cell) => _invoiceLinks(
                          cell.row.cells['data']!.value as CashActivity,
                        ),
                      )
                    else
                      _column(
                        entry.key,
                        entry.value,
                        width: entry.key == 'operation' ? 220 : 170,
                      ),
                ],
                gridRowFor: (row) => PlutoRow(
                  cells: {
                    'data': PlutoCell(value: row),
                    for (final entry in values(row).entries)
                      entry.key: PlutoCell(value: entry.value),
                  },
                ),
              ),
        value.page,
        value.totalPages,
        narrow,
        (next) => setState(() => _activityPage = next),
      ),
      AsyncError(:final error) => _error(
        error,
        () => ref.invalidate(customerCashActivityProvider(args)),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(AppSpacing.space6),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }

  Widget _invoiceLinks(CashActivity activity) {
    if (!(ref.watch(authProvider).user?.hasPermission('invoices', 'read') ??
        false)) {
      return const SizedBox.shrink();
    }
    final invoices = {
      for (final line in activity.lines)
        if (line.invoiceId != null) line.invoiceId!: line.invoiceNo,
    };
    return Wrap(
      children: [
        for (final invoice in invoices.entries)
          TextButton(
            onPressed: _openingInvoice != null
                ? null
                : () => _openInvoice(invoice.key),
            child: Text(
              invoice.value ??
                  AppLocalizations.of(
                    context,
                  )!.cashDependencyInvoice('${invoice.key}'),
            ),
          ),
      ],
    );
  }

  Future<void> _openInvoice(int invoiceId) async {
    if (_openingInvoice != null ||
        !(ref.read(authProvider).user?.hasPermission('invoices', 'read') ??
            false)) {
      return;
    }
    setState(() => _openingInvoice = invoiceId);
    final result = await ref.read(invoiceRepositoryProvider).invoice(invoiceId);
    if (!mounted) return;
    setState(() => _openingInvoice = null);
    switch (result) {
      case ApiSuccess(:final data):
        GoRouter.of(context).push('/sales/print-preview', extra: data);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Widget _reverseAction(CashReceipt receipt, {required bool compact}) {
    final l10n = AppLocalizations.of(context)!;
    final eligible =
        receipt.canReverse &&
        receipt.appliedMinor == 0 &&
        receipt.refundedMinor == 0 &&
        receipt.remainingMinor == receipt.originalMinor;
    final action = eligible
        ? () => showUnappliedCashReverseDialog(
            context,
            customer: widget.customer,
            receipt: receipt,
          )
        : null;
    final tooltip = eligible ? l10n.cashReverse : l10n.cashReverseUnavailable;
    return compact
        ? IconButton(
            key: Key('cash_reverse_${receipt.paymentId}'),
            tooltip: tooltip,
            onPressed: action,
            icon: const Icon(Icons.undo_outlined),
          )
        : Tooltip(
            message: tooltip,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton.icon(
                  key: Key('cash_reverse_${receipt.paymentId}'),
                  onPressed: action,
                  icon: const Icon(Icons.undo_outlined),
                  label: Text(l10n.cashReverse),
                ),
                if (!eligible)
                  Text(
                    l10n.cashReverseUnavailable,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          );
  }

  Widget _card(
    Map<String, String> values,
    Map<String, String> labels, {
    Widget? action,
  }) => Card(
    margin: const EdgeInsets.only(bottom: AppSpacing.space3),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in values.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
              child: Text('${labels[entry.key]}: ${entry.value}'),
            ),
          ?action,
        ],
      ),
    ),
  );

  Widget _panel(
    Widget content,
    int page,
    int totalPages,
    bool narrow,
    ValueChanged<int> onPage,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: narrow ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow) content else Expanded(child: content),
        if (totalPages > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space2),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.space2,
              children: [
                Text(l10n.cashPageLabel(page, totalPages)),
                IconButton(
                  tooltip: l10n.commonPrevious,
                  onPressed: page > 1 ? () => onPage(page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: l10n.commonNext,
                  onPressed: page < totalPages ? () => onPage(page + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
