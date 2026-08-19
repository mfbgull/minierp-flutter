import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/date_picker.dart' show pickDate;
import '../../widgets/detail_labels.dart' show detailSectionLabel;
import '../../widgets/form_field.dart' show FormFieldShell;
import '../../widgets/form_helpers.dart'
    show ErrorBanner, formInputDecoration, submitOnEnter;
import '../../widgets/searchable_select.dart';
import './inventory_providers.dart'
    show physicalCountsProvider, warehousesProvider;
import 'package:minierp_app/core/theme/app_border_radius.dart';

Future<void> showNewPhysicalCountDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _NewPhysicalCountDialog(),
  );
}

class _NewPhysicalCountDialog extends ConsumerStatefulWidget {
  const _NewPhysicalCountDialog();

  @override
  ConsumerState<_NewPhysicalCountDialog> createState() =>
      _NewPhysicalCountDialogState();
}

class _NewPhysicalCountDialogState extends ConsumerState<_NewPhysicalCountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  int? _warehouseId;
  DateTime? _countDate;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(
      context,
      initialDate: _countDate ?? DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _countDate = picked;
    });
  }

  String? _validateWarehouse(int? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null) return l10n.commonRequired;
    return null;
  }

  String? _validateDate(DateTime? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null) return l10n.commonRequired;
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final notes = _notesController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(inventoryRepositoryProvider)
        .createPhysicalCount({
          'warehouse_id': _warehouseId!,
          'count_date': DateFormat('yyyy-MM-dd').format(_countDate!),
          if (notes.isNotEmpty) 'notes': notes,
        });

    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        ref.invalidate(physicalCountsProvider);
        showAppToast(context, l10n.physicalcountsRecordedmsg);
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
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];
    final scheme = Theme.of(context).colorScheme;

    String warehouseLabel(int id) {
      final match = warehouses.where((w) => w.id == id);
      final name = match.isEmpty ? null : match.first.warehouseName;
      return name ?? '$id';
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                detailSectionLabel(context, 'New Count'),
                const SizedBox(height: 4),
                Text(
                  'Start a new stock count for a warehouse.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                FormFieldShell(
                  label: l10n.fieldsWarehouse,
                  required: true,
                  child: SearchableSelect<int>(
                    items: [for (final w in warehouses) w.id],
                    selected: _warehouseId,
                    labelBuilder: warehouseLabel,
                    onChanged: (value) =>
                        setState(() => _warehouseId = value),
                    validator: _validateWarehouse,
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.fieldsDate,
                  required: true,
                  child: TextFormField(
                    controller: TextEditingController(
                      text: _countDate == null
                          ? ''
                          : DateFormat.yMMMd().format(_countDate!),
                    ),
                    enabled: !_busy,
                    readOnly: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(borderRadius: AppBorderRadius.smRadius),
                      suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    onTap: _pickDate,
                    validator: (_) => _validateDate(_countDate),
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldShell(
                  label: l10n.fieldsNotes,
                  child: TextFormField(
                    controller: _notesController,
                    enabled: !_busy,
                    maxLines: 3,
                    decoration: formInputDecoration(),
                    onFieldSubmitted: submitOnEnter(_submit),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_outlined, size: 18),
                      label: Text(l10n.commonCreate),
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
