import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/screen_error_panel.dart';

/// Opens the warehouse create/edit dialog. Resolves `true` when a save
/// succeeded (the dialog pops with `true` on success).
Future<bool?> showWarehouseFormDialog(
  BuildContext context, {
  Warehouse? warehouse,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => WarehouseFormDialog(warehouse: warehouse),
  );
}

class WarehouseFormDialog extends ConsumerStatefulWidget {
  const WarehouseFormDialog({super.key, this.warehouse});

  final Warehouse? warehouse;

  @override
  ConsumerState<WarehouseFormDialog> createState() =>
      _WarehouseFormDialogState();
}

class _WarehouseFormDialogState extends ConsumerState<WarehouseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final w = widget.warehouse;
    _codeController = TextEditingController(text: w?.warehouseCode ?? '');
    _nameController = TextEditingController(text: w?.warehouseName ?? '');
    _locationController = TextEditingController(text: w?.location ?? '');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(inventoryRepositoryProvider);
    final body = {
      'warehouse_code': _codeController.text.trim(),
      'warehouse_name': _nameController.text.trim(),
      if (_locationController.text.trim().isNotEmpty)
        'location': _locationController.text.trim(),
    };
    final result = widget.warehouse == null
        ? await repo.createWarehouse(body)
        : await repo.updateWarehouse(widget.warehouse!.id, body);
    if (!mounted) return;
    setState(() => _saving = false);
    result.fold(
      onSuccess: (_) => Navigator.of(context).pop(true),
      onFailure: (err) => setState(() => _error = err.message),
    );
  }

  /// Delete the warehouse (edit mode only) — confirms, DELETE /:id, then
  /// pops the form with `true` so the screen refetches the list (mirrors
  /// the PO form's delete flow).
  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.warehousesDeleteconfirm,
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(inventoryRepositoryProvider)
        .deleteWarehouse(widget.warehouse!.id);
    if (!mounted) return;
    result.fold(
      onSuccess: (_) {
        // The screen invalidates warehousesProvider when the form pops
        // with `true`; the refetch drops the deleted row.
        Navigator.of(context).pop(true);
        showAppToast(context, l10n.warehousesDeletedmsg);
      },
      onFailure: (err) => setState(() {
        _saving = false;
        _error = err.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEdit = widget.warehouse != null;
    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEdit ? 'Edit Warehouse' : 'New Warehouse',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (_error != null) ...[
                ScreenErrorPanel(message: _error!, onRetry: () {}),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(labelText: 'Warehouse Code'),
                enabled: !isEdit,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: 'Warehouse Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (isEdit)
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _delete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(l10n.commonDelete),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.commonSave),
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
