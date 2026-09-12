// Count-correction dialog — opened from the physical-count detail for a
// COMPLETED, not-yet-corrected count. POSTED counts are immutable on the
// server; correction is a single-shot workflow that reverses the original
// completion's stock adjustments + accounting entries and re-applies the
// recounted quantities (`POST /inventory/physical-counts/:id/correct`).
// Rows without input are left untouched; the confirmation explains the
// reversal before anything is sent.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/physical_count.dart' show PhysicalCountItem;
import '../../data/repositories/api_result.dart'
    show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/detail_labels.dart' show detailSectionLabel;
import '../../widgets/form_helpers.dart' show ErrorBanner, formInputDecoration;
import 'inventory_providers.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

/// Opens the correction dialog for [countId] with the count's item lines
/// ([items]) prefilled from their originally counted quantities.
Future<void> showCorrectCountDialog(
  BuildContext context, {
  required int countId,
  required List<PhysicalCountItem> items,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _CorrectCountDialog(countId: countId, items: items),
  );
}

class _CorrectCountDialog extends ConsumerStatefulWidget {
  const _CorrectCountDialog({required this.countId, required this.items});

  final int countId;
  final List<PhysicalCountItem> items;

  @override
  ConsumerState<_CorrectCountDialog> createState() =>
      _CorrectCountDialogState();
}

class _CorrectCountDialogState extends ConsumerState<_CorrectCountDialog> {
  late final List<TextEditingController> _controllers;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final item in widget.items)
        TextEditingController(
          // Prefill with the ORIGINALLY counted quantity — the recount
          // starts from what the posted adjustment says, not blank.
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

    // Validate every entered value up front — nothing is sent until the
    // whole form is clean.
    final corrections = <Map<String, dynamic>>[];
    for (final (index, item) in widget.items.indexed) {
      final raw = _controllers[index].text.trim();
      if (raw.isEmpty) continue;
      final qty = num.tryParse(raw);
      if (qty == null || qty < 0) {
        setState(() => _error = l10n.physicalcountsRecordinvalid);
        return;
      }
      // Skip rows unchanged from the originally counted quantity — the
      // server re-applies everything supplied, so only real recounts go
      // over the wire.
      if (item.countedQuantity != null && qty == item.countedQuantity) {
        continue;
      }
      corrections.add({'item_id': item.itemId, 'counted_quantity': qty});
    }
    if (corrections.isEmpty) {
      setState(() => _error = l10n.physicalcountsCorrectnone);
      return;
    }

    // Explain the reversal before committing — this is a destructive,
    // single-shot workflow.
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.physicalcountsCorrecttitle,
      message: l10n.physicalcountsCorrectconfirm,
      confirmLabel: l10n.physicalcountsCorrectapply,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(inventoryRepositoryProvider)
        .correctPhysicalCount(widget.countId, corrections);

    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        ref.invalidate(physicalCountsProvider);
        ref.invalidate(physicalCountDetailProvider(widget.countId));
        showAppToast(context, l10n.physicalcountsCorrectedmsg);
        Navigator.of(context).pop();
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MovableDialog(
      dialogId: 'correct_count',
      maxWidth: 560,
      maxHeight: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                detailSectionLabel(context, l10n.physicalcountsCorrecttitle),
                const SizedBox(height: 2),
                Text(
                  l10n.physicalcountsCorrectconfirm,
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
                                '${l10n.physicalcountsCorrectorig}: '
                                '${item.countedQuantity == null ? '—' : _formatQty(item.countedQuantity!)}'
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
                              hintText: l10n.physicalcountsCorrectnewqty,
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
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.tertiary,
                    foregroundColor: scheme.onTertiary,
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.published_with_changes_outlined,
                          size: 18),
                  label: Text(l10n.physicalcountsCorrectapply),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
