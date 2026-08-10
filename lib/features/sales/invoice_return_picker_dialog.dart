// Process Return picker — the Invoice Returns tab's "New"-equivalent.
// Returns are created against an invoice (there is no standalone return
// form; the process-return dialog lives on the invoice edit form, and
// the web app pairs it with `/sales/returns`). This dialog lets the
// user pick any invoice, then opens the standard
// [showInvoiceReturnDialog] for it. Pops with the chosen invoice id —
// the caller opens the return dialog with it (a dialog cannot push
// another dialog from its own context once it is being popped).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/invoice.dart' show Invoice;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/searchable_select.dart';
import 'invoice_return_dialog.dart' show showInvoiceReturnDialog;
import 'invoice_return_providers.dart' show invoiceReturnPickerProvider;

/// Opens the Process Return picker; after an invoice is chosen, opens
/// the return dialog for it.
Future<void> showInvoiceReturnPicker(BuildContext context) async {
  final invoiceId = await showDialog<int>(
    context: context,
    builder: (dialogContext) => const InvoiceReturnPickerDialog(),
  );
  if (invoiceId == null || !context.mounted) return;
  showInvoiceReturnDialog(context, invoiceId: invoiceId);
}

class InvoiceReturnPickerDialog extends ConsumerWidget {
  const InvoiceReturnPickerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final invoices = ref.watch(invoiceReturnPickerProvider);
    final invoicesData = invoices.valueOrNull ?? const <Invoice>[];
    final errorMessage = switch (invoices) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.salesreturnsProcessreturn,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.salesreturnsReturnsubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (errorMessage != null)
                Text(
                  errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (invoices.isLoading && invoicesData.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SearchableSelect<int>(
                  items: [for (final invoice in invoicesData) invoice.id],
                  hint: l10n.salesreturnsSelectinvoice,
                  searchHint: l10n.salesreturnsSearchinvoices,
                  emptyText: l10n.salesNoinvoices,
                  labelBuilder: (id) {
                    final invoice = invoicesData.firstWhere(
                      (i) => i.id == id,
                      orElse: () => Invoice(
                        id: id,
                        invoiceNo: '',
                        customerId: 0,
                        invoiceDate: '',
                        totalAmount: 0,
                        paidAmount: 0,
                        balanceAmount: 0,
                        status: '',
                      ),
                    );
                    return '${invoice.invoiceNo} — ${invoice.customerName ?? ''}';
                  },
                  onChanged: (id) {
                    if (id == null) return;
                    Navigator.of(context).pop(id);
                  },
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (errorMessage != null) ...[
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(invoiceReturnPickerProvider),
                      child: Text(l10n.commonRefresh),
                    ),
                    const SizedBox(width: 8),
                  ],
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
