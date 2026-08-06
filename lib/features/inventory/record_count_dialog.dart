// Record-count dialog — opened from the physical-count detail for a
// non-terminal count (Draft or In Progress; the server's `recordCount`
// rejects only Completed/Cancelled sessions). Shows the count's item
// lines with editable counted quantities (prefilled from the current
// values) and POSTs each changed row via
// `POST /inventory/physical-counts/:id/items` (recordPhysicalCountItem).
// An empty field leaves that line unchanged; recording works one item at
// a time server-side, so rows are submitted sequentially.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/physical_count.dart' show PhysicalCountItem;
import '../../data/repositories/api_result.dart' show ApiFailure;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/detail_labels.dart' show detailSectionLabel;
import '../../widgets/form_helpers.dart' show ErrorBanner, formInputDecoration;
import 'inventory_providers.dart';

/// Opens the record-count dialog for [countId] with the count's item
/// lines ([items]) prefilled from their current counted quantities.
Future<void> showRecordCountDialog(
  BuildContext context, {
  required int countId,
  required List<PhysicalCountItem> items,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _RecordCountDialog(countId: countId, items: items),
  );
}

class _RecordCountDialog extends ConsumerStatefulWidget {
  const _RecordCountDialog({required this.countId, required this.items});

  final int countId;
  final List<PhysicalCountItem> items;

  @override
  ConsumerState<_RecordCountDialog> createState() => _RecordCountDialogState();
}

class _RecordCountDialogState extends ConsumerState<_RecordCountDialog> {
  late final List<TextEditingController> _controllers;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final item in widget.items)
        TextEditingController(
          text: item.countedQuantity == null
              ? ''
              : _formatQty(item.countedQuantity!),
        ),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// '95.0' → '95', '88.5' → '88.5' — avoids trailing `.0` noise.
  static String _formatQty(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  static String _itemLabel(PhysicalCountItem item) => [
    item.itemCode,
    item.itemName,
  ].where((s) => s != null && s.isNotEmpty).join(' — ');

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;

    // Validate every entered value up front — no POSTs until the whole
    // form is clean.
    final values = <int, num>{};
    for (final (index, item) in widget.items.indexed) {
      final raw = _controllers[index].text.trim();
      if (raw.isEmpty) continue;
      final qty = num.tryParse(raw);
      if (qty == null || qty < 0) {
        setState(() => _error = l10n.physicalcountsRecordinvalid);
        return;
      }
      values[item.itemId] = qty;
    }
    if (values.isEmpty) {
      setState(() => _error = l10n.physicalcountsRecordnone);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    for (final entry in values.entries) {
      final result = await ref
          .read(inventoryRepositoryProvider)
          .recordPhysicalCountItem(widget.countId, {
            'item_id': entry.key,
            'counted_quantity': entry.value,
          });
      if (result case ApiFailure(:final error)) {
        if (!mounted) return;
        // Rows already submitted in this run are on the server — refetch
        // so the table reflects them, and let the user retry the rest.
        ref.invalidate(physicalCountsProvider);
        ref.invalidate(physicalCountDetailProvider(widget.countId));
        setState(() {
          _busy = false;
          _error = error.message;
        });
        return;
      }
    }

    if (!mounted) return;
    ref.invalidate(physicalCountsProvider);
    ref.invalidate(physicalCountDetailProvider(widget.countId));
    showAppToast(context, l10n.physicalcountsRecordedmsg);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  detailSectionLabel(context, l10n.physicalcountsRecorditems),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.items.length} '
                    '${widget.items.length == 1 ? 'item' : 'items'}',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: ErrorBanner(message: _error!),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, item) in widget.items.indexed) ...[
                      if (index > 0)
                        Divider(height: 16, color: scheme.outlineVariant),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _itemLabel(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'System: ${_formatQty(item.systemQuantity)}'
                                  '${item.unitOfMeasure == null || item.unitOfMeasure!.isEmpty ? '' : ' ${item.unitOfMeasure}'}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 140,
                            child: TextFormField(
                              controller: _controllers[index],
                              enabled: !_busy,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: formInputDecoration(
                                hintText: l10n.physicalcountsRecordhint,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.commonClose),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(l10n.physicalcountsRecordsave),
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
