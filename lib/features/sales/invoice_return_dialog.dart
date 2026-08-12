// Invoice return-processing dialog — the sales-return flow for an
// invoice (`POST /invoices/:id/return`). Opened from the invoice edit
// form's Process Return action. Fetches the fresh invoice detail (so
// `returned_qty` is current), collects a per-line return quantity (capped
// at each line's remaining returnable quantity), an optional reason and
// the disposition (refund/credit/adjust — defaulted to the server's
// rule: refund when paid off, otherwise credit). On success it
// invalidates the invoices list and the returns-history grid — the
// invoice's returned_amount/status refetch, and the new return appears
// in the Returns tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart' show InvoiceItem;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/searchable_select.dart';
import 'invoice_providers.dart';
import 'invoice_return_providers.dart' show invoiceReturnsProvider;

/// Opens the return-processing dialog for [invoiceId].
Future<void> showInvoiceReturnDialog(
  BuildContext context, {
  required int invoiceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => InvoiceReturnDialog(invoiceId: invoiceId),
  );
}

class InvoiceReturnDialog extends ConsumerStatefulWidget {
  const InvoiceReturnDialog({super.key, required this.invoiceId});

  final int invoiceId;

  @override
  ConsumerState<InvoiceReturnDialog> createState() =>
      _InvoiceReturnDialogState();
}

class _InvoiceReturnDialogState extends ConsumerState<InvoiceReturnDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  /// Lines that still have something to return, with one qty controller
  /// per line (parallel lists — both rebuilt on load).
  List<InvoiceItem> _returnableItems = const [];
  final List<TextEditingController> _qtyControllers = [];

  String _disposition = 'credit';
  bool _submitting = false;
  bool _loading = true;
  String? _loadError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ref
        .read(invoiceRepositoryProvider)
        .invoice(widget.invoiceId);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _loading = false;
          final items = data.items ?? const <InvoiceItem>[];
          _returnableItems = [
            for (final item in items)
              if (item.quantity - item.returnedQty > 0) item,
          ];
          for (final c in _qtyControllers) {
            c.dispose();
          }
          _qtyControllers
            ..clear()
            ..addAll([
              for (final _ in _returnableItems) TextEditingController(),
            ]);
          // The server's default when no disposition is sent: refund
          // only when the invoice is paid off, credit otherwise.
          _disposition = data.balanceAmount <= 0 ? 'refund' : 'credit';
        });
      case ApiFailure(:final error):
        setState(() {
          _loading = false;
          _loadError = error.message;
        });
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _returnableItems.length; i++) {
      final qty = double.tryParse(_qtyControllers[i].text.trim()) ?? 0;
      if (qty > 0) {
        items.add({
          'invoice_item_id': _returnableItems[i].id,
          'return_quantity': qty,
        });
      }
    }
    if (items.isEmpty) {
      setState(() => _error = l10n.salesreturnsReturnqtyinvalid);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref
        .read(invoiceRepositoryProvider)
        .processReturn(
          widget.invoiceId,
          items: items,
          reason: _reasonController.text,
          disposition: _disposition,
        );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        ref.invalidate(invoicesProvider);
        ref.invalidate(invoiceReturnsProvider);
        showAppToast(
          context,
          '${l10n.salesreturnsReturnprocessed} — '
          '${Formatters.currency(data.netReturn)}',
        );
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _submitting = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.salesreturnsReturntitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.salesreturnsReturnsubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Flexible(child: _buildBody(l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          ErrorBanner(message: _loadError!),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonClose),
            ),
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_returnableItems.isEmpty) ...[
              Text(
                l10n.salesreturnsReturnnoitems,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              for (var i = 0; i < _returnableItems.length; i++) ...[
                if (i > 0) const Divider(height: 12),
                _ReturnLineRow(
                  item: _returnableItems[i],
                  controller: _qtyControllers[i],
                  autofocus: i == 0,
                  enabled: !_submitting,
                  onSubmit: _submit,
                ),
              ],
            ],
            const SizedBox(height: 12),
            FormFieldShell(
              label: l10n.salesreturnsReturnreason,
              child: TextFormField(
                controller: _reasonController,
                enabled: !_submitting,
                onFieldSubmitted: submitOnEnter(_submit),
                decoration: formInputDecoration(
                  hintText: l10n.salesreturnsReturnreasonplaceholder,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FormFieldShell(
              label: l10n.salesreturnsDisposition,
              child: SearchableSelect<String>(
                items: const ['refund', 'credit', 'adjust'],
                selected: _disposition,
                labelBuilder: (value) => switch (value) {
                  'refund' => l10n.salesreturnsDispositionrefund,
                  'credit' => l10n.salesreturnsDispositioncredit,
                  _ => l10n.salesreturnsDispositionadjust,
                },
                enabled: !_submitting,
                decoration: formInputDecoration(),
                onChanged: (value) {
                  if (value != null) setState(() => _disposition = value);
                },
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton.icon(
                  onPressed: _submitting || _returnableItems.isEmpty
                      ? null
                      : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.assignment_return_outlined, size: 18),
                  label: Text(l10n.salesreturnsReturn),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One returnable invoice line: item name/code + available qty on the
/// left, return-quantity input on the right.
class _ReturnLineRow extends StatelessWidget {
  const _ReturnLineRow({
    required this.item,
    required this.controller,
    required this.autofocus,
    required this.enabled,
    required this.onSubmit,
  });

  final InvoiceItem item;
  final TextEditingController controller;

  /// Focuses the first return-qty field on open — the quantities are the
  /// dialog's primary input.
  final bool autofocus;
  final bool enabled;

  /// Enter-to-submit: pressing Enter on a filled line processes the
  /// return (same [submitOnEnter] contract as the other dialogs).
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final available = item.quantity - item.returnedQty;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.itemName ?? '',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if ((item.itemCode ?? '').isNotEmpty)
                Text(item.itemCode!, style: muted),
              const SizedBox(height: 2),
              Text(
                '${l10n.salesreturnsAvailableqty}: '
                '${Formatters.number(available)}',
                style: muted,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 130,
          child: FormFieldShell(
            label: l10n.salesreturnsReturnquantity,
            child: TextFormField(
              controller: controller,
              autofocus: autofocus,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onFieldSubmitted: submitOnEnter(onSubmit),
              decoration: formInputDecoration(
                hintText: Formatters.number(available),
              ),
              // Empty lines are optional; a filled line must be a valid,
              // non-negative quantity within the available amount.
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return null;
                final qty = double.tryParse(text);
                if (qty == null || qty <= 0) {
                  return l10n.salesreturnsReturnqtyinvalid;
                }
                if (qty > available) {
                  return l10n.salesreturnsReturnqtyexceeds;
                }
                return null;
              },
            ),
          ),
        ),
      ],
    );
  }
}
