// Return source picker — the first step of the return entry flow (§8.2).
// Choose the source type (Direct Purchase | Purchase Order) then a
// searchable document list (one large server-filtered page each,
// `returnSourcePurchasesProvider` / `returnSourceOrdersProvider`), then
// tap a document. Pops with a [ReturnSource] the caller hands to the
// return entry form (pre-seeded with the selected document's number and
// warehouse). The returns-tab "New Return" action opens this empty; the
// purchases / PO row menus skip it and open the form directly (their
// source document is already known — the "pre-seeded" case of §8.1/8.2).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart' show formInputDecoration;
import 'purchase_return_form_dialog.dart'
    show ReturnSource, ReturnSourceType, showPurchaseReturnFormDialog;
import 'purchase_return_providers.dart'
    show returnSourceOrdersProvider, returnSourcePurchasesProvider;

/// Opens the source picker; on a confirmed selection, opens the return
/// entry form for it. A no-op when the user cancels.
Future<void> showReturnSourcePicker(
  BuildContext context, {
  ReturnSourceType initialType = ReturnSourceType.purchase,
}) {
  return showDialog<ReturnSource>(
    context: context,
    builder: (dialogContext) => ReturnSourcePickerDialog(initialType: initialType),
  ).then((source) {
    if (source == null || !context.mounted) return;
    showPurchaseReturnFormDialog(context, source: source);
  });
}

class ReturnSourcePickerDialog extends ConsumerStatefulWidget {
  const ReturnSourcePickerDialog({
    super.key,
    this.initialType = ReturnSourceType.purchase,
  });

  final ReturnSourceType initialType;

  @override
  ConsumerState<ReturnSourcePickerDialog> createState() =>
      _ReturnSourcePickerDialogState();
}

class _ReturnSourcePickerDialogState
    extends ConsumerState<ReturnSourcePickerDialog> {
  late ReturnSourceType _type = widget.initialType;
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _search = value.trim());
    });
  }

  void _pick(ReturnSource source) => Navigator.of(context).pop(source);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return MovableDialog(
      dialogId: 'return_source_picker',
      maxWidth: 620,
      maxHeight: 560,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.purchasesReturnsourcepicker,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  FormFieldShell(
                    label: l10n.purchasesReturnsourcetype,
                    required: true,
                    child: SegmentedButton<ReturnSourceType>(
                      segments: [
                        ButtonSegment(
                          value: ReturnSourceType.purchase,
                          icon: const Icon(Icons.receipt_long_outlined, size: 16),
                          label: Text(l10n.purchasesReturnsourcedirect),
                        ),
                        ButtonSegment(
                          value: ReturnSourceType.purchaseOrder,
                          icon: const Icon(Icons.assignment_outlined, size: 16),
                          label: Text(l10n.purchasesReturnsourcepo),
                        ),
                      ],
                      selected: {_type},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        if (!mounted) return;
                        setState(() => _type = selection.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: formInputDecoration(
                      hintText: l10n.commonSearch,
                    ).copyWith(prefixIcon: const Icon(Icons.search, size: 18)),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _sourceList(l10n)),
          ],
      ),
    );
  }

  Widget _sourceList(AppLocalizations l10n) {
    switch (_type) {
      case ReturnSourceType.purchase:
        final purchases = ref.watch(returnSourcePurchasesProvider(_search));
        return purchases.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('$error', textAlign: TextAlign.center),
            ),
          ),
          data: (rows) => rows.isEmpty
              ? Center(child: Text(l10n.purchasesReturnsourcenone))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final p = rows[index];
                    return ListTile(
                      dense: true,
                      title: Text(p.purchaseNo),
                      subtitle: Text(
                        '${p.itemName} · ${p.supplierName ?? '—'}'
                        ' · ${p.purchaseDate}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        size: 18,
                      ),
                      onTap: () => _pick(
                        ReturnSource.purchase(
                          id: p.id,
                          no: p.purchaseNo,
                          warehouseId: p.warehouseId,
                        ),
                      ),
                    );
                  },
                ),
        );
      case ReturnSourceType.purchaseOrder:
        final orders = ref.watch(returnSourceOrdersProvider(_search));
        return orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('$error', textAlign: TextAlign.center),
            ),
          ),
          data: (rows) => rows.isEmpty
              ? Center(child: Text(l10n.purchasesReturnsourcenone))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final po = rows[index];
                    return ListTile(
                      dense: true,
                      title: Text(po.poNo),
                      subtitle: Text(
                        '${po.supplierName} · ${po.status} · ${po.poDate}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        size: 18,
                      ),
                      onTap: () => _pick(
                        ReturnSource.purchaseOrder(
                          id: po.id,
                          no: po.poNo,
                          warehouseId: po.warehouseId,
                        ),
                      ),
                    );
                  },
                ),
        );
    }
  }
}
