// Manage Companies dialog — company lifecycle over
// `/inventory/item-companies`, plus one company's product and supplier
// detail (`/products`, `/suppliers`).
//
// The server owns identity and delete eligibility: duplicate names, an
// archived name reuse, a company that still has products, and permission
// failures all come back as 4xx messages shown verbatim.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_notifier.dart' show authProvider;
import '../../data/models/company_supplier.dart' show CompanySupplier;
import '../../data/models/item.dart' show Item, ItemCompany;
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart'
    show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_helpers.dart';
import '../../widgets/movable_dialog.dart';
import '../../widgets/pagination_bar.dart';
import 'inventory_providers.dart';
import 'item_detail_dialog.dart';

/// Opens the Manage Companies dialog. Returns true when data changed.
Future<bool?> showManageCompaniesDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => const ManageCompaniesDialog(),
  );
}

class ManageCompaniesDialog extends ConsumerStatefulWidget {
  const ManageCompaniesDialog({super.key});

  @override
  ConsumerState<ManageCompaniesDialog> createState() =>
      _ManageCompaniesDialogState();
}

class _ManageCompaniesDialogState extends ConsumerState<ManageCompaniesDialog> {
  final _searchController = TextEditingController();
  final Set<int> _busy = <int>{};
  Timer? _debounce;
  String _status = 'active';
  int _page = 1;
  int _limit = 10;
  bool _changed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  ManagedCompaniesArgs get _args => ManagedCompaniesArgs(
    page: _page,
    limit: _limit,
    search: _searchController.text.trim(),
    status: _status,
  );

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _page = 1);
    });
  }

  void _setStatus(String status) {
    if (_status == status) return;
    setState(() {
      _status = status;
      _page = 1;
    });
  }

  Future<void> _add() async {
    final saved = await _showCompanyNameDialog(context);
    if (!mounted) return;
    if (saved == true) {
      _changed = true;
      _page = 1;
      invalidateCompanyQueries(ref);
    }
  }

  Future<void> _edit(ItemCompany company) async {
    final saved = await _showCompanyNameDialog(context, company: company);
    if (!mounted) return;
    if (saved == true) {
      _changed = true;
      invalidateCompanyQueries(ref);
    }
  }

  Future<void> _setActive(ItemCompany company, bool active) async {
    if (_busy.contains(company.id)) return;
    setState(() => _busy.add(company.id));
    final repo = ref.read(inventoryRepositoryProvider);
    final result = active
        ? await repo.restoreCompany(company.id)
        : await repo.archiveCompany(company.id);
    if (!mounted) return;
    setState(() => _busy.remove(company.id));
    final l10n = AppLocalizations.of(context)!;
    switch (result) {
      case ApiSuccess():
        _changed = true;
        invalidateCompanyQueries(ref);
        showAppToast(
          context,
          active
              ? l10n.inventoryCompanyRestored
              : l10n.inventoryCompanyArchivedToast,
        );
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<void> _delete(ItemCompany company) async {
    if (_busy.contains(company.id)) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.inventoryCompanyDelete,
      message: l10n.inventoryCompanyDeleteConfirm(company.name),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(company.id));
    final result = await ref
        .read(inventoryRepositoryProvider)
        .deleteCompany(company.id);
    if (!mounted) return;
    setState(() => _busy.remove(company.id));
    switch (result) {
      case ApiSuccess():
        _changed = true;
        _page = 1;
        invalidateCompanyQueries(ref);
        showAppToast(context, l10n.inventoryCompanyDeleted);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<void> _openDetail(ItemCompany company) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _CompanyDetailDialog(companyId: company.id),
    );
    if (changed == true) _changed = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final companies = ref.watch(managedCompaniesProvider(_args));
    final user = ref.watch(authProvider).user;
    final canCreate = user?.hasPermission('inventory', 'create') ?? false;
    final canUpdate = user?.hasPermission('inventory', 'update') ?? false;
    final canDelete = user?.hasPermission('inventory', 'delete') ?? false;
    final scheme = Theme.of(context).colorScheme;

    return MovableDialog(
      dialogId: 'manage_companies',
      maxWidth: 760,
      maxHeight: 760,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.inventoryManageCompanies,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canCreate)
                  IconButton(
                    key: const ValueKey('manage-companies-add'),
                    tooltip: l10n.inventoryCompanyAdd,
                    onPressed: _add,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                IconButton(
                  tooltip: l10n.commonClose,
                  onPressed: () => Navigator.of(context).pop(_changed),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              key: const ValueKey('manage-companies-search'),
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: formInputDecoration(
                hintText: l10n.inventoryCompanySearchHint,
              ).copyWith(
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _page = 1);
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                _statusChip(l10n.inventoryCompanyActive, 'active'),
                _statusChip(l10n.inventoryCompanyArchived, 'archived'),
                _statusChip(l10n.inventoryCompanyAll, 'all'),
              ],
            ),
          ),
          Expanded(
            child: switch (companies) {
              AsyncData(:final value) => value.items.isEmpty
                  ? Center(
                      child: Text(
                        l10n.inventoryCompanyNoCompanies,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: value.items.length,
                      itemBuilder: (context, index) {
                        final company = value.items[index];
                        return _CompanyRow(
                          company: company,
                          busy: _busy.contains(company.id),
                          canUpdate: canUpdate,
                          canDelete: canDelete,
                          onOpen: () => _openDetail(company),
                          onEdit: () => _edit(company),
                          onToggleActive: () =>
                              _setActive(company, !company.isActive),
                          onDelete: () => _delete(company),
                        );
                      },
                    ),
              AsyncError(:final error) => _ErrorState(
                message: error is ApiError
                    ? error.message
                    : l10n.messagesFetcherror,
                onRetry: () => ref.invalidate(managedCompaniesProvider),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
          if (companies.valueOrNull case final page?)
            ServerPaginationBar(
              page: page.currentPage,
              totalPages: page.totalPages,
              totalItems: page.totalItems,
              hasNext: page.hasNext,
              hasPrev: page.hasPrev,
              limit: _limit,
              itemLabel: l10n.inventoryCompanies,
              onPageChanged: (value) => setState(() => _page = value),
              onLimitChanged: (value) => setState(() {
                _limit = value;
                _page = 1;
              }),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, String value) {
    return FilterChip(
      key: ValueKey('company-filter-$value'),
      label: Text(label),
      selected: _status == value,
      onSelected: (_) => _setStatus(value),
    );
  }
}

class _CompanyRow extends StatelessWidget {
  const _CompanyRow({
    required this.company,
    required this.busy,
    required this.canUpdate,
    required this.canDelete,
    required this.onOpen,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final ItemCompany company;
  final bool busy;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey('company-row-${company.id}'),
      enabled: !busy,
      onTap: busy ? null : onOpen,
      leading: CircleAvatar(
        backgroundColor: company.isActive
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        child: Text(
          company.name.isNotEmpty ? company.name[0].toUpperCase() : '?',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      title: Text(company.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${l10n.inventoryCompanyProductCount(company.productCount)} · '
        '${company.isActive ? l10n.inventoryCompanyActive : l10n.inventoryCompanyArchived}',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (canUpdate || canDelete)
          ? PopupMenuButton<String>(
              key: ValueKey('company-menu-${company.id}'),
              onSelected: (action) {
                switch (action) {
                  case 'edit':
                    onEdit();
                  case 'toggle':
                    onToggleActive();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                if (canUpdate)
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.edit_outlined, size: 18),
                      title: Text(l10n.commonEdit),
                    ),
                  ),
                if (canUpdate)
                  PopupMenuItem(
                    value: 'toggle',
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        company.isActive
                            ? Icons.archive_outlined
                            : Icons.unarchive_outlined,
                        size: 18,
                      ),
                      title: Text(
                        company.isActive
                            ? l10n.inventoryCompanyArchive
                            : l10n.inventoryCompanyRestore,
                      ),
                    ),
                  ),
                if (canDelete)
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: scheme.error,
                      ),
                      title: Text(
                        l10n.commonDelete,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ),
              ],
            )
          : null,
    );
  }
}

class _CompanyDetailDialog extends ConsumerStatefulWidget {
  const _CompanyDetailDialog({required this.companyId});

  final int companyId;

  @override
  ConsumerState<_CompanyDetailDialog> createState() =>
      _CompanyDetailDialogState();
}

class _CompanyDetailDialogState extends ConsumerState<_CompanyDetailDialog> {
  bool _changed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final company = ref.watch(itemCompanyProvider(widget.companyId));
    return MovableDialog(
      dialogId: 'company_detail',
      maxWidth: 840,
      maxHeight: 740,
      child: switch (company) {
        AsyncData(:final value) => DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!value.isActive)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Chip(
                          label: Text(l10n.inventoryCompanyArchived),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    IconButton(
                      tooltip: l10n.commonClose,
                      onPressed: () =>
                          Navigator.of(context).pop(_changed),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              TabBar(
                tabs: [
                  Tab(text: l10n.inventoryCompanyProducts),
                  Tab(text: l10n.inventoryCompanySuppliers),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    _CompanyProductsTab(companyId: widget.companyId),
                    _CompanySuppliersTab(
                      companyId: widget.companyId,
                      companyActive: value.isActive,
                      onChanged: () => _changed = true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AsyncError(:final error) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ErrorBanner(
                message: error is ApiError
                    ? error.message
                    : l10n.messagesFetcherror,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(itemCompanyProvider(widget.companyId)),
                    child: Text(l10n.commonRetry),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_changed),
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ],
          ),
        ),
        _ => const SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}

class _CompanyProductsTab extends ConsumerStatefulWidget {
  const _CompanyProductsTab({required this.companyId});

  final int companyId;

  @override
  ConsumerState<_CompanyProductsTab> createState() =>
      _CompanyProductsTabState();
}

class _CompanyProductsTabState extends ConsumerState<_CompanyProductsTab> {
  int _page = 1;
  int _limit = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final products = ref.watch(
      companyProductsProvider(
        CompanyProductsArgs(
          companyId: widget.companyId,
          page: _page,
          limit: _limit,
        ),
      ),
    );
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: switch (products) {
            AsyncData(:final value) => value.items.isEmpty
                ? Center(
                    child: Text(
                      l10n.inventoryCompanyNoProducts,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: value.items.length,
                    itemBuilder: (context, index) {
                      final item = value.items[index];
                      return _ProductRow(
                        item: item,
                        onTap: () =>
                            showItemDetailDialog(context, itemId: item.id),
                      );
                    },
                  ),
            AsyncError(:final error) => _ErrorState(
              message: error is ApiError
                  ? error.message
                  : l10n.messagesFetcherror,
              onRetry: () => ref.invalidate(companyProductsProvider),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
        if (products.valueOrNull case final page?)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: _limit,
            itemLabel: l10n.inventoryCompanyProducts,
            onPageChanged: (value) => setState(() => _page = value),
            onLimitChanged: (value) => setState(() {
              _limit = value;
              _page = 1;
            }),
          ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.item, required this.onTap});

  final Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (item.category != null && item.category!.isNotEmpty) item.category!,
      item.unitOfMeasure,
    ].join(' · ');
    return ListTile(
      key: ValueKey('company-product-${item.id}'),
      onTap: onTap,
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(
        '${item.itemCode} · ${item.itemName}',
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        details,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: item.isActive
          ? null
          : Text(
              AppLocalizations.of(context)!.inventoryCompanyArchived,
              style: TextStyle(color: scheme.error),
            ),
    );
  }
}

class _CompanySuppliersTab extends ConsumerStatefulWidget {
  const _CompanySuppliersTab({
    required this.companyId,
    required this.companyActive,
    required this.onChanged,
  });

  final int companyId;
  final bool companyActive;
  final VoidCallback onChanged;

  @override
  ConsumerState<_CompanySuppliersTab> createState() =>
      _CompanySuppliersTabState();
}

class _CompanySuppliersTabState extends ConsumerState<_CompanySuppliersTab> {
  int _page = 1;
  int _limit = 10;
  final Set<int> _busy = <int>{};

  Future<void> _setLinked(CompanySupplier supplier, bool linked) async {
    if (_busy.contains(supplier.supplierId)) return;
    final l10n = AppLocalizations.of(context)!;
    if (!linked) {
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.inventoryCompanyUnlink,
        message: l10n.inventoryCompanyUnlinkConfirm(supplier.supplierName),
        confirmLabel: l10n.inventoryCompanyUnlink,
        cancelLabel: l10n.commonCancel,
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy.add(supplier.supplierId));
    final result = await ref
        .read(inventoryRepositoryProvider)
        .setCompanySupplierLink(widget.companyId, supplier.supplierId, linked);
    if (!mounted) return;
    setState(() => _busy.remove(supplier.supplierId));
    switch (result) {
      case ApiSuccess():
        widget.onChanged();
        ref.invalidate(companySuppliersProvider);
        showAppToast(
          context,
          linked
              ? l10n.inventoryCompanySupplierLinkedToast
              : l10n.inventoryCompanySupplierUnlinkedToast,
        );
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<void> _addSupplier() async {
    final supplier = await showDialog<Supplier>(
      context: context,
      builder: (dialogContext) => const _SupplierPickerDialog(),
    );
    if (supplier == null || !mounted) return;
    await _setLinked(
      CompanySupplier(
        supplierId: supplier.id,
        supplierName: supplier.supplierName,
      ),
      true,
    );
  }

  void _openSupplier(int supplierId) {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context, rootNavigator: true).popUntil(
      (route) => route.isFirst,
    );
    router?.go('/suppliers/$supplierId');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider).user;
    final canUpdate = user?.hasPermission('inventory', 'update') ?? false;
    final suppliers = ref.watch(
      companySuppliersProvider(
        CompanySupplierListArgs(
          companyId: widget.companyId,
          page: _page,
          limit: _limit,
        ),
      ),
    );
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.inventoryCompanySuppliers,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (canUpdate)
                FilledButton.tonalIcon(
                  key: const ValueKey('company-add-supplier'),
                  onPressed: widget.companyActive ? _addSupplier : null,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: Text(l10n.inventoryCompanyAddSupplier),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (suppliers) {
            AsyncData(:final value) => value.items.isEmpty
                ? Center(
                    child: Text(
                      l10n.inventoryCompanyNoSuppliers,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: value.items.length,
                    itemBuilder: (context, index) {
                      final supplier = value.items[index];
                      return _SupplierRow(
                        supplier: supplier,
                        busy: _busy.contains(supplier.supplierId),
                        canLink: canUpdate && widget.companyActive,
                        onOpen: () => _openSupplier(supplier.supplierId),
                        onToggleLink: () =>
                            _setLinked(supplier, !supplier.linked),
                      );
                    },
                  ),
            AsyncError(:final error) => _ErrorState(
              message: error is ApiError
                  ? error.message
                  : l10n.messagesFetcherror,
              onRetry: () => ref.invalidate(companySuppliersProvider),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
        if (suppliers.valueOrNull case final page?)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: _limit,
            itemLabel: l10n.inventoryCompanySuppliers,
            onPageChanged: (value) => setState(() => _page = value),
            onLimitChanged: (value) => setState(() {
              _limit = value;
              _page = 1;
            }),
          ),
      ],
    );
  }
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({
    required this.supplier,
    required this.busy,
    required this.canLink,
    required this.onOpen,
    required this.onToggleLink,
  });

  final CompanySupplier supplier;
  final bool busy;
  final bool canLink;
  final VoidCallback onOpen;
  final VoidCallback onToggleLink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final contact = [
      if (supplier.contactPerson != null && supplier.contactPerson!.isNotEmpty)
        supplier.contactPerson!,
      if (supplier.phone != null && supplier.phone!.isNotEmpty) supplier.phone!,
    ].join(' · ');
    final history = [
      l10n.inventoryCompanyProductCount(supplier.productCount),
      if (supplier.lastPurchaseDate != null)
        l10n.inventoryCompanyLastPurchase(supplier.lastPurchaseDate!),
    ].join(' · ');

    return ListTile(
      key: ValueKey('company-supplier-${supplier.supplierId}'),
      enabled: !busy,
      onTap: busy ? null : onOpen,
      leading: const Icon(Icons.local_shipping_outlined),
      title: Row(
        children: [
          Flexible(
            child: Text(
              supplier.supplierName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (supplier.linked) ...[
            const SizedBox(width: 6),
            _Badge(label: l10n.inventoryCompanyLinked),
          ],
          if (supplier.purchased) ...[
            const SizedBox(width: 4),
            _Badge(label: l10n.inventoryCompanyPurchased),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (contact.isNotEmpty)
            Text(
              contact,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          Text(
            history,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<String>(
              key: ValueKey('company-supplier-menu-${supplier.supplierId}'),
              onSelected: (action) {
                switch (action) {
                  case 'open':
                    onOpen();
                  case 'link':
                    onToggleLink();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'open',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.open_in_new, size: 18),
                    title: Text(l10n.inventoryCompanyOpenSupplier),
                  ),
                ),
                if (canLink)
                  PopupMenuItem(
                    value: 'link',
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        supplier.linked ? Icons.link_off : Icons.link,
                        size: 18,
                      ),
                      title: Text(
                        supplier.linked
                            ? l10n.inventoryCompanyUnlink
                            : l10n.inventoryCompanyLink,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 9,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _SupplierPickerDialog extends ConsumerStatefulWidget {
  const _SupplierPickerDialog();

  @override
  ConsumerState<_SupplierPickerDialog> createState() =>
      _SupplierPickerDialogState();
}

class _SupplierPickerDialogState
    extends ConsumerState<_SupplierPickerDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final suppliers = ref.watch(linkableSuppliersProvider);
    final scheme = Theme.of(context).colorScheme;
    final term = _searchController.text.trim().toLowerCase();

    return MovableDialog(
      dialogId: 'company_supplier_picker',
      maxWidth: 520,
      maxHeight: 620,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.inventoryCompanySelectSupplier,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l10n.commonClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const ValueKey('company-supplier-search'),
              controller: _searchController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: formInputDecoration(
                hintText: l10n.inventoryCompanySearchSuppliers,
              ).copyWith(prefixIcon: const Icon(Icons.search, size: 18)),
            ),
          ),
          Expanded(
            child: switch (suppliers) {
              AsyncData(:final value) => Builder(
                builder: (context) {
                  final filtered = value.where((supplier) {
                    if (term.isEmpty) return true;
                    return supplier.supplierName.toLowerCase().contains(term) ||
                        supplier.supplierCode.toLowerCase().contains(term) ||
                        (supplier.contactPerson ?? '')
                            .toLowerCase()
                            .contains(term) ||
                        (supplier.phone ?? '').toLowerCase().contains(term);
                  }).toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.inventoryCompanyNoSuppliers,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final supplier = filtered[index];
                      return ListTile(
                        key: ValueKey(
                          'supplier-picker-option-${supplier.id}',
                        ),
                        onTap: () => Navigator.of(context).pop(supplier),
                        title: Text(
                          supplier.supplierName,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            supplier.supplierCode,
                            if (supplier.contactPerson != null &&
                                supplier.contactPerson!.isNotEmpty)
                              supplier.contactPerson!,
                          ].join(' · '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  );
                },
              ),
              AsyncError(:final error) => _ErrorState(
                message: error is ApiError
                    ? error.message
                    : l10n.messagesFetcherror,
                onRetry: () => ref.invalidate(linkableSuppliersProvider),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

Future<bool?> _showCompanyNameDialog(
  BuildContext context, {
  ItemCompany? company,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _CompanyNameDialog(company: company),
  );
}

class _CompanyNameDialog extends ConsumerStatefulWidget {
  const _CompanyNameDialog({this.company});

  final ItemCompany? company;

  @override
  ConsumerState<_CompanyNameDialog> createState() => _CompanyNameDialogState();
}

class _CompanyNameDialogState extends ConsumerState<_CompanyNameDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.company?.name ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(inventoryRepositoryProvider);
    final name = _controller.text.trim();
    final result = widget.company == null
        ? await repo.addCompany(name)
        : await repo.updateCompany(widget.company!.id, name);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        Navigator.of(context).pop(true);
      case ApiFailure(:final error):
        setState(() {
          _saving = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MovableDialog(
      dialogId: 'company_name',
      maxWidth: 460,
      maxHeight: 360,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.company == null
                          ? l10n.inventoryCompanyAdd
                          : l10n.inventoryCompanyEdit,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.commonClose,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextFormField(
                key: const ValueKey('company-name-field'),
                controller: _controller,
                autofocus: true,
                enabled: !_saving,
                maxLength: 200,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                decoration: formInputDecoration().copyWith(
                  labelText: l10n.inventoryCompanyName,
                ),
                validator: (value) => requiredValidator(
                  value,
                  l10n.commonRequired,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ErrorBanner(message: _error!),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('company-name-cancel'),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('company-name-save'),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.commonSave),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
          ],
        ),
      ),
    );
  }
}
