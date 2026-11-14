// PRET-002 — the supplier refund claim list. One list of claims with status
// chips; a toggle that defaults to open items only (EXPECTED + PARTIAL),
// because a closed claim needs no action. "Record receipt" opens the refund
// dialog against the claim; "Write off" opens the short-pay dialog.
//
// The refunds-due total is shown as a separate figure. It is a receivable
// memo — cash moves only when a receipt posts (REFUND_RECEIPT) — so it must
// not be read as, or added to, a cash balance.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/purchase_repository.dart'
    show
        RefundClaim,
        purchaseRepositoryProvider,
        refundClaimsProvider,
        refundsDueProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/detail_tab_grid.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/status_badge.dart';
import 'refund_claim_write_off_dialog.dart';
import 'refund_claim_receipts_dialog.dart';
import 'supplier_refund_dialog.dart';

class RefundClaimsScreen extends ConsumerStatefulWidget {
  const RefundClaimsScreen({super.key});

  @override
  ConsumerState<RefundClaimsScreen> createState() => _RefundClaimsScreenState();
}

class _RefundClaimsScreenState extends ConsumerState<RefundClaimsScreen> {
  int _page = 1;
  int _limit = 25;

  /// Open-only by default: a RECEIVED or CANCELLED claim needs no action.
  bool _openOnly = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider).user;
    // The server filters on a single status, so "open" is two page-fetches
    // merged here rather than a server-side OR.
    final provider = refundClaimsProvider((
      status: _openOnly ? null : null,
      page: _page,
      limit: _limit,
    ));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.refundClaimsTitle)),
      body: Column(
        children: [
          _RefundsDueBanner(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: Text(l10n.refundClaimsOpenOnly),
                  selected: _openOnly,
                  onSelected: (value) => setState(() {
                    _openOnly = value;
                    _page = 1;
                  }),
                ),
                IconButton(
                  tooltip: l10n.commonRefresh,
                  onPressed: () => ref.invalidate(provider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: ref
                .watch(provider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          error is ApiError
                              ? error.message
                              : l10n.errorsFailed,
                        ),
                        TextButton(
                          onPressed: () => ref.invalidate(provider),
                          child: Text(l10n.commonRetry),
                        ),
                      ],
                    ),
                  ),
                  data: (value) {
                    final claims = _openOnly
                        ? value.items.where((c) => c.isOpen).toList()
                        : value.items;
                    if (claims.isEmpty) {
                      return Center(
                        child: Text(
                          _openOnly
                              ? l10n.refundClaimsEmptyOpen
                              : l10n.refundClaimsEmpty,
                        ),
                      );
                    }
                    return Column(
                      children: [
                        Expanded(
                          child: DetailTabGrid<RefundClaim>(
                            data: claims,
                            buildColumns: (l10n) => _columns(l10n, user),
                            hiddenFields: const ['data'],
                            widthKey: 'refund_claims',
                            gridRowFor: (claim) => PlutoRow(
                              cells: {
                                'data': PlutoCell(value: claim),
                                'claim_no': PlutoCell(value: claim.claimNo),
                                'supplier': PlutoCell(
                                  value: claim.supplierName,
                                ),
                                'date': PlutoCell(
                                  value: Formatters.date(claim.claimDate),
                                ),
                                'amount': PlutoCell(value: claim.amount),
                                'received': PlutoCell(
                                  value: claim.receivedAmount,
                                ),
                                'remaining': PlutoCell(
                                  value: claim.remaining,
                                ),
                                'status': PlutoCell(value: claim.status),
                                'actions': PlutoCell(value: ''),
                              },
                            ),
                          ),
                        ),
                        LayoutBuilder(
                          builder: (_, constraints) => SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: constraints.maxWidth < 700
                                  ? 700
                                  : constraints.maxWidth,
                              child: ServerPaginationBar(
                                page: value.currentPage,
                                totalPages: value.totalPages,
                                totalItems: value.totalItems,
                                hasNext: value.hasNext,
                                hasPrev: value.hasPrev,
                                limit: _limit,
                                itemLabel: l10n.refundClaimsTitle,
                                onPageChanged: (page) =>
                                    setState(() => _page = page),
                                onLimitChanged: (limit) => setState(() {
                                  _limit = limit;
                                  _page = 1;
                                }),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  List<PlutoColumn> _columns(AppLocalizations l10n, user) => [
    PlutoColumn(
      title: l10n.fieldsReference,
      field: 'claim_no',
      type: PlutoColumnType.text(),
      width: 150,
    ),
    PlutoColumn(
      title: l10n.refundClaimStandaloneSupplier,
      field: 'supplier',
      type: PlutoColumnType.text(),
      width: 180,
    ),
    PlutoColumn(
      title: l10n.fieldsDate,
      field: 'date',
      type: PlutoColumnType.text(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.fieldsAmount,
      field: 'amount',
      type: PlutoColumnType.number(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.refundClaimStatusRECEIVED,
      field: 'received',
      type: PlutoColumnType.number(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.fieldsBalance,
      field: 'remaining',
      type: PlutoColumnType.number(),
      width: 120,
    ),
    PlutoColumn(
      title: l10n.commonStatus,
      field: 'status',
      type: PlutoColumnType.text(),
      width: 150,
      renderer: (cell) {
        final claim = cell.row.cells['data']!.value as RefundClaim;
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: StatusBadge(
            status: _statusLabel(l10n, claim.status),
            color: _statusColor(Theme.of(context), claim.status),
          ),
        );
      },
    ),
    PlutoColumn(
      title: l10n.commonActions,
      field: 'actions',
      type: PlutoColumnType.text(),
      width: 90,
      renderer: (cell) {
        final claim = cell.row.cells['data']!.value as RefundClaim;
        final canRead = user?.hasPermission('supplier_refunds', 'read') ?? false;
        final canCreate =
            user?.hasPermission('supplier_refunds', 'create') ?? false;
        final canWriteOff =
            user?.hasPermission('supplier_refunds', 'write_off') ?? false;
        // Receipts stay viewable on a closed claim; the actions that change
        // it need an open claim.
        return PopupMenuButton<_ClaimAction>(
          tooltip: l10n.commonActions,
          enabled: canRead || canCreate || canWriteOff,
          onSelected: (action) => _action(action, claim),
          itemBuilder: (_) => [
            if (canRead)
              PopupMenuItem(
                value: _ClaimAction.receipts,
                child: Text(l10n.refundClaimViewReceipts),
              ),
            if (canCreate && claim.isOpen)
              PopupMenuItem(
                value: _ClaimAction.receipt,
                child: Text(l10n.refundClaimRecordReceipt),
              ),
            if (canWriteOff && claim.isOpen)
              PopupMenuItem(
                value: _ClaimAction.writeOff,
                child: Text(l10n.refundClaimWriteOff),
              ),
            if (canCreate && claim.isOpen)
              PopupMenuItem(
                value: _ClaimAction.cancel,
                child: Text(l10n.refundClaimCancel),
              ),
          ],
        );
      },
    ),
    PlutoColumn(
      title: '',
      field: 'data',
      type: PlutoColumnType.text(),
      hide: true,
    ),
  ];

  String _statusLabel(AppLocalizations l10n, String status) => switch (status) {
    'EXPECTED' => l10n.refundClaimStatusEXPECTED,
    'PARTIAL' => l10n.refundClaimStatusPARTIAL,
    'RECEIVED' => l10n.refundClaimStatusRECEIVED,
    'CANCELLED' => l10n.refundClaimStatusCANCELLED,
    _ => status,
  };

  Color _statusColor(ThemeData theme, String status) => switch (status) {
    'RECEIVED' => Colors.green.shade600,
    'CANCELLED' => theme.colorScheme.outline,
    'PARTIAL' => Colors.orange.shade700,
    _ => theme.colorScheme.primary,
  };

  Future<void> _action(_ClaimAction action, RefundClaim claim) async {
    final l10n = AppLocalizations.of(context)!;
    switch (action) {
      case _ClaimAction.receipts:
        final changed = await showRefundClaimReceiptsDialog(
          context,
          claim: claim,
        );
        if (!mounted || !changed) return;
        ref.invalidate(refundsDueProvider);
      case _ClaimAction.receipt:
        // A standalone claim settles against itself; a return-backed claim
        // carries its credit note.
        await showSupplierClaimReceiptDialog(context, claim: claim);
        if (!mounted) return;
        ref.invalidate(refundsDueProvider);
      case _ClaimAction.writeOff:
        final isAdmin = ref.read(authProvider).user?.role == 'admin';
        final done = await showRefundClaimWriteOffDialog(
          context,
          claim: claim,
          isAdmin: isAdmin,
        );
        if (!mounted || !done) return;
        ref.invalidate(refundsDueProvider);
      case _ClaimAction.cancel:
        final reason = await showDialog<String>(
          context: context,
          builder: (_) => _CancelClaimDialog(claim: claim),
        );
        if (!mounted || reason == null) return;
        final result = await ref
            .read(purchaseRepositoryProvider)
            .cancelClaim(claim.id, reason: reason);
        if (!mounted) return;
        switch (result) {
          case ApiSuccess():
            showAppToast(context, l10n.refundClaimCancel);
            ref.invalidate(refundsDueProvider);
          case ApiFailure(:final error):
            showAppToast(context, error.message, isError: true);
        }
    }
    if (mounted) {
      ref.invalidate(
        refundClaimsProvider((status: null, page: _page, limit: _limit)),
      );
    }
  }
}

enum _ClaimAction { receipts, receipt, writeOff, cancel }

/// The refunds-due total, deliberately rendered apart from any cash figure.
class _RefundsDueBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final due = ref.watch(refundsDueProvider);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: due.when(
        loading: () => Text(l10n.commonLoading),
        error: (_, _) => Text(l10n.refundsDueTitle),
        data: (value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.refundsDueBadge(Formatters.currency(value.totalDue)),
              style: theme.textTheme.titleSmall,
            ),
            Text(
              l10n.refundsDueHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelClaimDialog extends StatefulWidget {
  const _CancelClaimDialog({required this.claim});

  final RefundClaim claim;

  @override
  State<_CancelClaimDialog> createState() => _CancelClaimDialogState();
}

class _CancelClaimDialogState extends State<_CancelClaimDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.refundClaimCancel),
      content: TextField(
        controller: _reasonController,
        maxLines: 2,
        decoration: InputDecoration(labelText: l10n.refundClaimCancelReason),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_reasonController.text.trim()),
          child: Text(l10n.refundClaimCancel),
        ),
      ],
    );
  }
}
