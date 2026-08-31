// Borrower list management dialog — full-screen dialog for managing borrowers.
// Purely record-keeping — no GL impact on business data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import 'personal_loan_borrower_form_dialog.dart';
import 'personal_loan_models.dart';
import 'personal_loan_providers.dart';
import 'personal_loan_repository.dart' show personalLoanRepositoryProvider;

/// Opens the borrower list management dialog. Returns true if data changed.
Future<bool?> showBorrowerListDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => const _BorrowerListDialog(),
  );
}

class _BorrowerListDialog extends ConsumerStatefulWidget {
  const _BorrowerListDialog();

  @override
  ConsumerState<_BorrowerListDialog> createState() =>
      _BorrowerListDialogState();
}

class _BorrowerListDialogState extends ConsumerState<_BorrowerListDialog> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final borrowersAsync = ref.watch(borrowersProvider);
    final borrowers = borrowersAsync.valueOrNull ?? [];
    final scheme = Theme.of(context).colorScheme;

    // Apply filter
    final filtered = borrowers.where((b) {
      switch (_filter) {
        case 'with_loans':
          return b.loanCount > 0;
        case 'customers':
          return b.linkedType == 'customer';
        case 'suppliers':
          return b.linkedType == 'supplier';
        case 'personal':
          return b.linkedType == null;
        default:
          return true;
      }
    }).toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.equityPersonalLoanManageBorrowers,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: l10n.equityPersonalLoanFilterAll,
                      selected: _filter == 'all',
                      onTap: () => setState(() => _filter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: l10n.equityPersonalLoanFilterWithLoans,
                      selected: _filter == 'with_loans',
                      onTap: () => setState(() => _filter = 'with_loans'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: l10n.equityPersonalLoanFilterCustomers,
                      selected: _filter == 'customers',
                      onTap: () => setState(() => _filter = 'customers'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: l10n.equityPersonalLoanFilterSuppliers,
                      selected: _filter == 'suppliers',
                      onTap: () => setState(() => _filter = 'suppliers'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: l10n.equityPersonalLoanFilterPersonal,
                      selected: _filter == 'personal',
                      onTap: () => setState(() => _filter = 'personal'),
                    ),
                  ],
                ),
              ),
            ),
            // List
            Expanded(
              child: borrowersAsync.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            l10n.equityPersonalLoanNoBorrowers,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) =>
                              _BorrowerRow(
                            borrower: filtered[index],
                            onChanged: () {
                              ref.invalidate(borrowersProvider);
                            },
                          ),
                        ),
            ),
            // Add button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton.tonalIcon(
                onPressed: () => _addBorrower(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.equityPersonalLoanAddBorrower),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addBorrower(BuildContext context) async {
    final result = await showBorrowerFormDialog(context);
    if (result == true && mounted) {
      ref.invalidate(borrowersProvider);
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class _BorrowerRow extends ConsumerWidget {
  const _BorrowerRow({required this.borrower, required this.onChanged});

  final PersonalLoanBorrower borrower;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: borrower.linkedType != null
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        child: Text(
          borrower.name.isNotEmpty ? borrower.name[0].toUpperCase() : '?',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              borrower.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (borrower.badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                borrower.badge!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        borrower.phone != null && borrower.phone!.isNotEmpty
            ? '${borrower.phone} · ${borrower.loanCount} loans · ${Formatters.currency(borrower.totalLent)}'
            : '${borrower.loanCount} loans · ${Formatters.currency(borrower.totalLent)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) => _handleAction(context, ref, action),
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'edit',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.edit_outlined, size: 18),
              title: Text(l10n.equityPersonalLoanEditBorrower),
            ),
          ),
          if (borrower.linkedType != null)
            PopupMenuItem(
              value: 'unlink',
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.link_off, size: 18),
                title: Text(l10n.equityPersonalLoanUnlinkBorrower),
              ),
            ),
          PopupMenuItem(
            value: 'merge',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.merge, size: 18),
              title: Text(l10n.equityPersonalLoanMergeBorrower),
            ),
          ),
          if (borrower.isActive && borrower.loanCount == 0)
            PopupMenuItem(
              value: 'deactivate',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.visibility_off, size: 18, color: scheme.error),
                title: Text(
                  l10n.equityPersonalLoanDeactivateBorrower,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          if (!borrower.isActive)
            PopupMenuItem(
              value: 'reactivate',
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.visibility, size: 18),
                title: Text(l10n.equityPersonalLoanReactivateBorrower),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, String action) async {
    final l10n = AppLocalizations.of(context)!;
    final repo = ref.read(personalLoanRepositoryProvider);

    switch (action) {
      case 'edit':
        final result = await showBorrowerFormDialog(
          context,
          borrower: borrower,
        );
        if (result == true) onChanged();
        break;
      case 'unlink':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.equityPersonalLoanUnlinkBorrower),
            content: Text(l10n.equityPersonalLoanUnlinkBorrowerBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.equityPersonalLoanUnlinkBorrower),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          final result = await repo.unlinkBorrower(borrower.id);
          if (context.mounted) {
            switch (result) {
              case ApiSuccess():
                showAppToast(context, l10n.equityPersonalLoanBorrowerUnlinked);
                onChanged();
              case ApiFailure(:final error):
                showAppToast(context, error.message, isError: true);
            }
          }
        }
        break;
      case 'merge':
        // TODO: Implement merge dialog
        break;
      case 'deactivate':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.equityPersonalLoanDeactivateBorrower),
            content: Text(
                '${l10n.equityPersonalLoanDeactivateBorrowerConfirm} ${borrower.name}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.equityPersonalLoanDeactivateBorrower),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          final result = await repo.deactivateBorrower(borrower.id);
          if (context.mounted) {
            switch (result) {
              case ApiSuccess():
                showAppToast(context, l10n.equityPersonalLoanBorrowerDeactivated);
                onChanged();
              case ApiFailure(:final error):
                showAppToast(context, error.message, isError: true);
            }
          }
        }
        break;
      case 'reactivate':
        final result = await repo.reactivateBorrower(borrower.id);
        if (context.mounted) {
          switch (result) {
            case ApiSuccess():
              showAppToast(context, l10n.equityPersonalLoanBorrowerReactivated);
              onChanged();
            case ApiFailure(:final error):
              showAppToast(context, error.message, isError: true);
          }
        }
        break;
    }
  }
}
