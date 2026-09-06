// Per-row actions for the Customers grid (extracted from
// customers_screen.dart, spec 1.3). Contains the ⋮ popup menu
// ([openCustomerRowMenu]) and the destructive [deleteCustomer] action
// with its Undo toast (SHORTCOMINGS-FIX 4.2).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/customer.dart' show Customer;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import 'customer_form_dialog.dart';
import 'customer_providers.dart';

/// The per-row actions menu items (web ⋮ dropdown: View / Edit / Delete).
enum CustomerRowAction { view, edit, delete }

/// Opens the row-actions menu anchored at [context] (the ⋮ cell).
/// Uses [showMenu] directly — the PopupMenuButton trigger can't receive
/// the tap inside a PlutoGrid cell, but this path only needs a position.
///
/// After the user picks an action it is dispatched immediately:
/// View → push detail page, Edit → form dialog, Delete → confirm + API.
Future<void> openCustomerRowMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Customer? customer,
}) async {
  if (customer == null) return;
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  final l10n = AppLocalizations.of(context)!;

  final action = await showMenu<CustomerRowAction>(
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
        value: CustomerRowAction.view,
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 18),
            const SizedBox(width: 8),
            Text(l10n.commonView),
          ],
        ),
      ),
      PopupMenuItem(
        value: CustomerRowAction.edit,
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, size: 18),
            const SizedBox(width: 8),
            Text(l10n.commonEdit),
          ],
        ),
      ),
      PopupMenuItem(
        value: CustomerRowAction.delete,
        child: Row(
          children: [
            Icon(
              Icons.delete_outline,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.customersDelete,
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
    case CustomerRowAction.view:
      context.push('/customers/${customer.id}');
    case CustomerRowAction.edit:
      showCustomerFormDialog(context, customer: customer);
    case CustomerRowAction.delete:
      await deleteCustomer(context: context, ref: ref, customer: customer);
  }
}

/// Shows a confirmation dialog and, on confirm, deletes [customer] via
/// the repository. Refreshes the customers list on success; shows a
/// toast on failure (including the server's 400 for "cannot delete
/// customer with existing transactions").
Future<void> deleteCustomer({
  required BuildContext context,
  required WidgetRef ref,
  required Customer customer,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.customersDelete,
    message: '${l10n.customersConfirmdelete} "${customer.customerName}"?',
    confirmLabel: l10n.customersDelete,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  final result = await ref.read(customerRepositoryProvider).delete(
    customer.id,
  );
  if (!context.mounted) return;
  switch (result) {
    case ApiSuccess():
      // 10s window + Undo (SHORTCOMINGS-FIX 4.2) — the delete is a soft
      // delete server-side, so restore() reverts it in place.
      showAppToast(
        context,
        l10n.customersCustomerdeleted,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () async {
            final undo = await ref
                .read(customerRepositoryProvider)
                .restore(customer.id);
            if (!context.mounted) return;
            switch (undo) {
              case ApiSuccess():
                ref.invalidate(customersProvider);
              case ApiFailure(:final error):
                showAppToast(context, error.message, isError: true);
            }
          },
        ),
      );
      ref.invalidate(customersProvider);
    case ApiFailure(:final error):
      // Surfaces the server 400 ("Cannot delete customer with existing
      // transactions") verbatim.
      showAppToast(context, error.message, isError: true);
  }
}