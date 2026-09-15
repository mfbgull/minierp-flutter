// Write-off dialog — multi-select expired batches, enter reason, pick GL
// loss account, confirm. Calls POST /inventory/expired/write-off.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/report.dart' show ExpiryReportRow;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';

/// Shows the write-off dialog. Returns `true` when at least one batch was
/// written off successfully (caller should refresh data).
Future<bool?> showWriteOffDialog(
  BuildContext context, {
  required List<ExpiryReportRow> batches,
}) {
  return showDialog<bool?>(
    context: context,
    builder: (_) => _WriteOffDialog(batches: batches),
  );
}

class _WriteOffDialog extends ConsumerStatefulWidget {
  const _WriteOffDialog({required this.batches});
  final List<ExpiryReportRow> batches;

  @override
  ConsumerState<_WriteOffDialog> createState() => _WriteOffDialogState();
}

class _WriteOffDialogState extends ConsumerState<_WriteOffDialog> {
  final Set<int> _selectedIndices = {};
  final _reasonController = TextEditingController();
  String _glAccount = '7201';
  bool _loading = false;

  static const _glAccounts = {
    '7201': 'Expired Goods Loss',
    '7202': 'Damaged Goods Loss',
    '7203': 'Stock Shortage Loss',
    '7204': 'Obsolete Stock Loss',
  };

  double get _totalValue => _selectedIndices.fold(0, (sum, i) {
        final b = widget.batches[i];
        return sum + (b.quantityRemaining * b.unitCost);
      });

  Future<void> _submit() async {
    if (_selectedIndices.isEmpty || _reasonController.text.trim().isEmpty) {
      return;
    }
    setState(() => _loading = true);
    try {
      final batchIds = <int>[];
      for (final i in _selectedIndices) {
        final id = widget.batches[i].id;
        if (id > 0) batchIds.add(id);
      }

      if (batchIds.isEmpty) {
        if (mounted) {
          showAppToast(
            context,
            AppLocalizations.of(context)!.writeOffNoSelection,
            isError: true,
          );
        }
        return;
      }

      final repo = ref.read(inventoryRepositoryProvider);
      final result = await repo.writeOffExpiredBatches({
        'batchIds': batchIds,
        'reason': _reasonController.text.trim(),
        'glAccount': _glAccount,
      });

      if (!mounted) return;
      result.fold(
        onSuccess: (_) {
          showAppToast(
            context,
            AppLocalizations.of(context)!.writeOffSuccess(batchIds.length),
          );
          Navigator.of(context).pop(true);
        },
        onFailure: (error) {
          showAppToast(context, error.message, isError: true);
        },
      );
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          '${AppLocalizations.of(context)!.writeOffFailed}: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(l10n.writeOffBatches),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Batch list with checkboxes
            Expanded(
              child: ListView.builder(
                itemCount: widget.batches.length,
                itemBuilder: (ctx, i) {
                  final b = widget.batches[i];
                  final value = b.quantityRemaining * b.unitCost;
                  return CheckboxListTile(
                    value: _selectedIndices.contains(i),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedIndices.add(i);
                      } else {
                        _selectedIndices.remove(i);
                      }
                    }),
                    title: Text(
                      '${b.itemCode} — ${b.batchNo}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      '${b.quantityRemaining} × '
                      '${Formatters.currency(b.unitCost)} = '
                      '${Formatters.currency(value)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
            const Divider(),
            // Total
            Text(
              l10n.writeOffTotalValue(Formatters.currency(_totalValue)),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            // Reason
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: l10n.writeOffReason,
                hintText: l10n.writeOffReasonHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            // GL Account
            DropdownButtonFormField<String>(
              value: _glAccount,
              decoration: InputDecoration(
                labelText: l10n.writeOffGlAccount,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: _glAccounts.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text('${e.key} — ${e.value}'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _glAccount = v ?? '7201'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _loading ||
                  _selectedIndices.isEmpty ||
                  _reasonController.text.trim().isEmpty
              ? null
              : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.writeOff),
        ),
      ],
    );
  }
}
