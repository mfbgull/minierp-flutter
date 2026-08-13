// Opening-balance editor — lets a new business record the starting
// (seed) cash/bank balance it was founded with. Saves via
// `PUT /dashboard/cash-opening-balances` and refreshes the cash
// position strip so the dashboard reflects the real till.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_summary.dart' show CashOpeningBalances;
import '../../data/repositories/api_result.dart'
    show ApiFailure, ApiSuccess;
import '../../data/repositories/dashboard_repository.dart'
    show dashboardRepositoryProvider;
import '../../l10n/app_localizations.dart';
import 'dashboard_providers.dart'
    show
        dashboardCashOpeningBalancesProvider,
        dashboardCashPositionProvider;

/// Opens the opening-balance editor. [ref] is used to load the current
/// values, save, and refresh the cash-position strip afterwards.
Future<void> showCashOpeningBalanceDialog(
  BuildContext context,
  WidgetRef ref,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CashOpeningBalanceDialog(),
  );
}

class _CashOpeningBalanceDialog extends ConsumerStatefulWidget {
  const _CashOpeningBalanceDialog();

  @override
  ConsumerState<_CashOpeningBalanceDialog> createState() =>
      _CashOpeningBalanceDialogState();
}

class _CashOpeningBalanceDialogState
    extends ConsumerState<_CashOpeningBalanceDialog> {
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initControllers(CashOpeningBalances balances) {
    for (final account in balances.accounts) {
      _controllers.putIfAbsent(
        account.key,
        () => TextEditingController(
          text: account.amount == 0 ? '' : account.amount.toString(),
        ),
      );
    }
  }

  Future<void> _save() async {
    final balances = ref.read(dashboardCashOpeningBalancesProvider).valueOrNull;
    if (balances == null) return;
    setState(() => _saving = true);
    final repo = ref.read(dashboardRepositoryProvider);
    final accounts = [
      for (final account in balances.accounts)
        (
          key: account.key,
          amount: num.tryParse(_controllers[account.key]?.text ?? '') ?? 0,
        ),
    ];
    final result = await repo.saveCashOpeningBalances(accounts);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ApiSuccess():
        ref.invalidate(dashboardCashOpeningBalancesProvider);
        ref.invalidate(dashboardCashPositionProvider);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.dashboardOpeningbalanceSaved)),
        );
      case ApiFailure(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final balances = ref.watch(dashboardCashOpeningBalancesProvider);

    return AlertDialog(
      title: Text(l10n.dashboardOpeningbalance),
      content: SizedBox(
        width: 400,
        child: balances.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, _) => Text(error.toString()),
          data: (data) {
            _initControllers(data);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.dashboardOpeningbalanceHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                for (final account in data.accounts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _controllers[account.key],
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: account.name,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
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
    );
  }
}
