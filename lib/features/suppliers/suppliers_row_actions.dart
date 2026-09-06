// Per-row actions for the Suppliers grid (extracted from
// suppliers_screen.dart, spec 1.3). Contains the ⋮ popup menu
// ([openSupplierRowMenu]) and the destructive [deleteSupplier] action.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/supplier_repository.dart'
    show supplierRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import 'supplier_form_dialog.dart';
import 'supplier_providers.dart';

/// The per-row actions menu items (web ⋮ dropdown: View / Edit / Delete).
enum SupplierRowAction { view, edit, delete }

/// Opens the row-actions menu anchored at [context] (the ⋮ cell).
/// Uses [showMenu] directly — the PopupMenuButton trigger can't receive
/// the tap inside a PlutoGrid cell, but this path only needs a position.
///
/// After the user picks an action it is dispatched immediately:
/// View → push detail page, Edit → form dialog, Delete → confirm + API.
Future<void> openSupplierRowMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Supplier? supplier,
}) async {
  if (supplier == null) return;
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  final l10n = AppLocalizations.of(context)!;

  final action = await showMenu<SupplierRowAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      ),
      Offset.zero & overlay.context.size!,
    ),
    items: [
      PopupMenuItem(
        value: SupplierRowAction.view,
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 18),
            const SizedBox(width: 8),
            Text(l10n.commonView),
          ],
        ),
      ),
      PopupMenuItem(
        value: SupplierRowAction.edit,
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, size: 18),
            const SizedBox(width: 8),
            Text(l10n.commonEdit),
          ],
        ),
      ),
      PopupMenuItem(
        value: SupplierRowAction.delete,
        child: Row(
          children: [
            Icon(
              Icons.delete_outline,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.suppliersDelete,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case SupplierRowAction.view:
      context.push('/suppliers/${supplier.id}');
    case SupplierRowAction.edit:
      showSupplierFormDialog(context, supplier: supplier);
    case SupplierRowAction.delete:
      await deleteSupplier(context: context, ref: ref, supplier: supplier);
  }
}

/// Shows a confirmation dialog and, on confirm, deletes [supplier] via
/// the repository. Refreshes the suppliers list on success; shows a
/// toast on failure (including the server's 400 for "cannot delete
/// supplier with existing purchase orders").
Future<void> deleteSupplier({
  required BuildContext context,
  required WidgetRef ref,
  required Supplier supplier,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.suppliersDelete,
    message: '${l10n.suppliersConfirmdelete} "${supplier.supplierName}"?',
    confirmLabel: l10n.suppliersDelete,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  final result = await ref
      .read(supplierRepositoryProvider)
      .delete(supplier.id);
  if (!context.mounted) return;
  switch (result) {
    case ApiSuccess():
      showAppToast(context, l10n.suppliersSupplierdeleted);
      ref.invalidate(suppliersProvider);
    case ApiFailure(:final error):
      // Surfaces the server 400 ("Cannot delete supplier with existing
      // purchase orders") verbatim.
      showAppToast(context, error.message, isError: true);
  }
}