import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/cache/cached_repository.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/party.dart';
import '../../data/repositories/party_repository.dart';
import '../../data/repositories/api_result.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../customers/customer_providers.dart';
import '../suppliers/supplier_providers.dart';
import '../sales/invoice_providers.dart';
import '../purchases/purchase_providers.dart';
import '../purchase_orders/purchase_order_providers.dart';
import '../reports/report_providers.dart';
import 'party_adjustment_dialog.dart';
import 'party_adjustment_history.dart';
import 'party_role_dialog.dart';

class PartyAccountButton extends ConsumerWidget {
  const PartyAccountButton({super.key, required this.partyId});
  final int? partyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = partyId;
    if (id == null || !(ref.watch(authProvider).user?.hasPermission('parties', 'read') ?? false)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return OutlinedButton.icon(
      key: const Key('party_account_open'), icon: const Icon(Icons.compare_arrows), label: Text(l.partyAccount),
      onPressed: () => showDialog<void>(context: context, barrierDismissible: false, builder: (_) => PartyAccountDialog(partyId: id)),
    );
  }
}

Future<void> invalidatePartyAccounts(WidgetRef ref, PartyPosition position) async {
  await ref.read(cachedRepositoryClientProvider).invalidatePaths([
    '/customers', '/suppliers', '/invoices', '/purchases', '/purchase-orders', '/reports', '/dashboard',
  ]);
  await ref.read(partyRepositoryProvider).invalidateAccounts();
  if (position.customer case final customer?) invalidateCustomerQueries(ref, customer.id);
  if (position.supplier case final supplier?) invalidateSupplierQueries(ref, supplier.id);
  ref.invalidate(customersProvider);
  ref.invalidate(suppliersProvider);
  ref.invalidate(invoicesProvider);
  ref.invalidate(filteredInvoicesProvider);
  ref.invalidate(purchasesProvider);
  ref.invalidate(purchaseDetailProvider);
  ref.invalidate(purchaseOrdersProvider);
  ref.invalidate(purchaseOrderDetailProvider);
  ref.invalidate(arAgingProvider);
  ref.invalidate(apAgingProvider);
  ref.invalidate(arSummaryProvider);
  ref.invalidate(topDebtorsReportProvider);
  ref.invalidate(customerStatementsReportProvider);
  ref.invalidate(balanceSheetProvider);
  ref.invalidate(trialBalanceProvider);
  ref.invalidate(generalLedgerProvider);
  ref.invalidate(partyPositionProvider(position.id));
}

class PartyAccountDialog extends ConsumerStatefulWidget {
  const PartyAccountDialog({super.key, required this.partyId});
  final int partyId;
  @override
  ConsumerState<PartyAccountDialog> createState() => _PartyAccountDialogState();
}

class _PartyAccountDialogState extends ConsumerState<PartyAccountDialog> {
  late int _partyId = widget.partyId;
  int _historyVersion = 0;
  Future<void> _changed(PartyPosition position) async {
    await invalidatePartyAccounts(ref, position);
    if (!mounted) return;
    setState(() { _partyId = position.id; _historyVersion++; });
  }
  Future<void> _role(PartyPosition position, bool link) async {
    final result = await showDialog<PartyPosition>(context: context, barrierDismissible: false,
      builder: (_) => PartyRoleDialog(position: position, linkExisting: link));
    if (result != null && mounted) {
      showAppToast(context, link ? AppLocalizations.of(context)!.partyLinked : AppLocalizations.of(context)!.partyRoleCreated);
      await _changed(result);
    }
  }
  Future<void> _unlink(PartyPosition position) async {
    final l = AppLocalizations.of(context)!;
    if (!await showConfirmDialog(context, title: l.partyUnlink, message: l.partyUnlinkConfirm) || !mounted) return;
    final result = await ref.read(partyRepositoryProvider).unlink(position.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data):
        await invalidatePartyAccounts(ref, position);
        if (mounted) await _changed(data);
      case ApiFailure(:final error): showAppToast(context, error.message, isError: true);
    }
  }
  Future<void> _adjust(PartyPosition position) async {
    final changed = await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (_) => PartyAdjustmentDialog(position: position));
    if (changed == true && mounted) await _changed(position);
  }
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider).user;
    final canLink = (user?.hasPermission('parties', 'link') ?? false) &&
      (user?.hasPermission('customers', 'update') ?? false) &&
      (user?.hasPermission('suppliers', 'update') ?? false);
    final position = ref.watch(partyPositionProvider(_partyId));
    return AlertDialog(
      title: Text(l.partyAccount),
      content: SizedBox(width: 1000, child: SingleChildScrollView(child: position.when(
        loading: () => const SizedBox(height: 140, child: Center(child: CircularProgressIndicator())),
        error: (error, _) => Column(mainAxisSize: MainAxisSize.min, children: [Text('$error'), TextButton(onPressed: () => ref.invalidate(partyPositionProvider(_partyId)), child: Text(l.commonRefresh))]),
        data: (p) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(p.displayName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (p.customer case final c?) ActionChip(label: Text('${l.partyCustomer} · ${c.code}'), onPressed: () { final router = GoRouter.of(context); Navigator.pop(context); router.push('/customers/${c.id}'); }),
            if (p.supplier case final s?) ActionChip(label: Text('${l.partySupplier} · ${s.code}'), onPressed: () { final router = GoRouter.of(context); Navigator.pop(context); router.push('/suppliers/${s.id}'); }),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 16, children: [
            _balance(l.partyTheyOwe, p.customerBalance), _balance(l.partyYouOwe, p.supplierBalance),
            _balance(p.netBalance >= 0 ? l.partyNetReceivable : l.partyNetPayable, p.netBalance.abs()),
            _balance(l.partyCredit, p.customerCredit), _balance(l.partyAdvance, p.supplierAdvance),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!p.hasBothRoles && canLink)
              OutlinedButton.icon(onPressed: () => _role(p, true), icon: const Icon(Icons.link), label: Text(l.partyLink)),
            if (!p.hasBothRoles && (user?.hasPermission('parties', 'link') ?? false) &&
              (user?.hasPermission(p.customer == null ? 'customers' : 'suppliers', 'create') ?? false))
              OutlinedButton.icon(onPressed: () => _role(p, false), icon: const Icon(Icons.person_add_alt), label: Text(p.customer == null ? l.partyAddCustomer : l.partyAddSupplier)),
            if (p.hasBothRoles && canLink)
              OutlinedButton(onPressed: () => _unlink(p), child: Text(l.partyUnlink)),
            if (p.hasBothRoles && (user?.hasPermission('party_adjustments', 'create') ?? false))
              FilledButton.icon(onPressed: p.maximumAdjustment > 0 && p.customer!.isActive && p.supplier!.isActive ? () => _adjust(p) : null,
                icon: const Icon(Icons.compare_arrows), label: Text(l.partyAdjust)),
            TextButton.icon(onPressed: () => ref.invalidate(partyPositionProvider(_partyId)), icon: const Icon(Icons.refresh), label: Text(l.commonRefresh)),
          ]),
          const SizedBox(height: 12), Text(l.partyNoCash),
          if (user?.hasPermission('party_adjustments', 'read') ?? false)
            PartyAdjustmentHistory(key: ValueKey((_partyId, _historyVersion)), partyId: _partyId, onChanged: () => _changed(p)),
        ]),
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonClose))],
    );
  }
  Widget _balance(String label, num amount) => SizedBox(width: 180, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: Theme.of(context).textTheme.bodySmall), Text(Formatters.currency(amount), style: Theme.of(context).textTheme.titleMedium),
  ]));
}
