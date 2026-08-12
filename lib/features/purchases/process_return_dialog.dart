// Process-return dialog — the return-processing flow for a direct
// purchase (`POST /purchases/:id/return`). Opened from the purchase
// detail dialog's Process Return action. Collects the return quantity
// (capped at the purchase's remaining returnable quantity) and an
// optional reason, then invalidates the purchases list, the purchase
// detail and the returns-history grid on success — the detail dialog
// beneath refetches with the updated returned quantity.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/purchase.dart' show Purchase;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/purchase_repository.dart'
    show purchaseRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/detail_rows.dart';
import '../../widgets/form_field.dart';
import '../../widgets/form_helpers.dart';
import 'purchase_providers.dart';
import 'purchase_return_providers.dart' show purchaseReturnsProvider;

/// Opens the return-processing dialog for [purchase].
Future<void> showProcessReturnDialog(
  BuildContext context, {
  required Purchase purchase,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => ProcessReturnDialog(purchase: purchase),
  );
}

class ProcessReturnDialog extends ConsumerStatefulWidget {
  const ProcessReturnDialog({super.key, required this.purchase});

  final Purchase purchase;

  @override
  ConsumerState<ProcessReturnDialog> createState() =>
      _ProcessReturnDialogState();
}

class _ProcessReturnDialogState extends ConsumerState<ProcessReturnDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final repo = ref.read(purchaseRepositoryProvider);
    final result = await repo.processReturn(
      widget.purchase.id,
      quantity: double.parse(_qtyController.text.trim()),
      reason: _reasonController.text,
    );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        ref.invalidate(purchasesProvider);
        ref.invalidate(purchaseDetailProvider(widget.purchase.id));
        ref.invalidate(purchaseReturnsProvider);
        showAppToast(
          context,
          '${l10n.purchasesReturnprocessed} — '
          '${Formatters.currency(data.totalCost)}',
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
    final purchase = widget.purchase;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.purchasesReturntitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.purchasesReturnsubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${purchase.purchaseNo} · ${purchase.itemName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                DetailTiles(
                  tiles: [
                    DetailTile(
                      l10n.purchasesOriginalqty,
                      Formatters.number(purchase.quantity),
                    ),
                    DetailTile(
                      l10n.purchasesReturnqty,
                      Formatters.number(purchase.returnedQuantity),
                    ),
                    DetailTile(
                      l10n.purchasesAvailableqty,
                      Formatters.number(purchase.returnableQty),
                      emphasize: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.purchasesReturnquantity,
                  required: true,
                  child: TextFormField(
                    controller: _qtyController,
                    onFieldSubmitted: submitOnEnter(_submit),
                    enabled: !_submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: formInputDecoration(
                      hintText: Formatters.number(purchase.returnableQty),
                    ),
                    validator: (v) {
                      final qty = double.tryParse((v ?? '').trim());
                      if (qty == null || qty <= 0) {
                        return l10n.purchasesReturnqtyinvalid;
                      }
                      if (qty > purchase.returnableQty) {
                        return l10n.purchasesReturnqtyexceeds;
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 10),
                FormFieldShell(
                  label: l10n.purchasesReturnreason,
                  child: TextFormField(
                    controller: _reasonController,
                    onFieldSubmitted: submitOnEnter(_submit),
                    enabled: !_submitting,
                    decoration: formInputDecoration(
                      hintText: l10n.purchasesReturnreasonplaceholder,
                    ),
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
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.assignment_return_outlined,
                              size: 18,
                            ),
                      label: Text(l10n.purchasesReturn),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
