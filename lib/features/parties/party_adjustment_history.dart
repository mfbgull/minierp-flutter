import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/party.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/paged_request.dart';
import '../../data/repositories/party_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart';
import '../../widgets/detail_tab_grid.dart';

class PartyAdjustmentHistory extends ConsumerStatefulWidget {
  const PartyAdjustmentHistory({super.key, required this.partyId, required this.onChanged});
  final int partyId;
  final Future<void> Function() onChanged;
  @override
  ConsumerState<PartyAdjustmentHistory> createState() => _PartyAdjustmentHistoryState();
}

class _PartyAdjustmentHistoryState extends ConsumerState<PartyAdjustmentHistory> {
  int _page = 1;
  PagedResponse<PartyAdjustment>? _data;
  String? _error;
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final result = await ref.read(partyRepositoryProvider).history(widget.partyId, page: _page);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case ApiSuccess(:final data): _data = data;
        case ApiFailure(:final error): _error = error.message;
      }
    });
  }
  Future<void> _open(PartyAdjustment row) async {
    final changed = await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (_) => PartyAdjustmentDetailDialog(partyId: widget.partyId, adjustmentId: row.id));
    if (changed == true && mounted) { await widget.onChanged(); if (mounted) await _load(); }
  }
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: Text(l.partyHistory, style: Theme.of(context).textTheme.titleMedium)), IconButton(tooltip: l.commonRefresh, onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      SizedBox(height: 260, child: _loading ? const Center(child: CircularProgressIndicator()) : DetailTabGrid<PartyAdjustment>(
        data: _data?.items ?? [], buildColumns: (l) => [
          PlutoColumn(title: l.partyCode, field: 'number', type: PlutoColumnType.text(), width: 180),
          PlutoColumn(title: l.fieldsDate, field: 'date', type: PlutoColumnType.text(), width: 130),
          PlutoColumn(title: l.partyAllocation, field: 'amount', type: PlutoColumnType.text(), width: 150),
          PlutoColumn(title: l.commonStatus, field: 'status', type: PlutoColumnType.text(), width: 160),
          PlutoColumn(title: l.commonActions, field: 'action', type: PlutoColumnType.text(), width: 90,
            renderer: (cell) => TextButton(onPressed: () => _open(cell.cell.value as PartyAdjustment), child: Text(l.commonView))),
        ], gridRowFor: (a) => PlutoRow(cells: {
          'number': PlutoCell(value: a.number), 'date': PlutoCell(value: a.date),
          'amount': PlutoCell(value: Formatters.currency(a.amount)),
          'status': PlutoCell(value: a.status == 'posted' ? l.partyPosted : l.partyReversed),
          'action': PlutoCell(value: a),
        }))),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        IconButton(tooltip: l.commonPrevious, onPressed: !_loading && (_data?.hasPrev ?? false) ? () { _page--; _load(); } : null, icon: const Icon(Icons.chevron_left)),
        Text('${l.commonPage} $_page ${l.commonOf} ${_data?.totalPages ?? 1}'),
        IconButton(tooltip: l.commonNext, onPressed: !_loading && (_data?.hasNext ?? false) ? () { _page++; _load(); } : null, icon: const Icon(Icons.chevron_right)),
      ]),
    ]);
  }
}

class PartyAdjustmentDetailDialog extends ConsumerStatefulWidget {
  const PartyAdjustmentDetailDialog({super.key, required this.partyId, required this.adjustmentId});
  final int partyId;
  final int adjustmentId;
  @override
  ConsumerState<PartyAdjustmentDetailDialog> createState() => _PartyAdjustmentDetailDialogState();
}

class _PartyAdjustmentDetailDialogState extends ConsumerState<PartyAdjustmentDetailDialog> {
  PartyAdjustment? _data;
  String? _error;
  bool _busy = false;
  bool _changed = false;
  bool _reversing = false;
  final _reason = TextEditingController();
  DateTime _date = DateTime.now();
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _reason.dispose(); super.dispose(); }
  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    final result = await ref.read(partyRepositoryProvider).detail(widget.partyId, widget.adjustmentId);
    if (!mounted) return;
    setState(() { _busy = false; switch (result) {
      case ApiSuccess(:final data): _data = data;
      case ApiFailure(:final error): _error = error.message;
    }});
  }
  Future<void> _reverse() async {
    if (_busy || _reason.text.trim().isEmpty) return;
    setState(() { _busy = true; _error = null; });
    final result = await ref.read(partyRepositoryProvider).reverse(widget.partyId, widget.adjustmentId, reason: _reason.text.trim(), date: isoDate(_date));
    if (!mounted) return;
    setState(() { _busy = false; switch (result) {
      case ApiSuccess(:final data): _data = data; _changed = true; _reversing = false;
      case ApiFailure(:final error): _error = error.message;
    }});
  }
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final data = _data;
    final canReverse = ref.watch(authProvider).user?.hasPermission('party_adjustments', 'reverse') ?? false;
    return PopScope(canPop: !_busy, child: AlertDialog(
      title: Text(data?.number ?? l.partyHistory),
      content: SizedBox(width: 620, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_busy) const LinearProgressIndicator(),
        if (data != null) ...[
          Text('${data.date} · ${Formatters.currency(data.amount)}'),
          Text(data.status == 'posted' ? l.partyPosted : l.partyReversed),
          if (data.notes?.isNotEmpty ?? false) Text(data.notes!),
          const SizedBox(height: 12), Text('${l.partySource} · ${l.partyInvoices}', style: Theme.of(context).textTheme.titleSmall),
          for (final row in data.receivables) Text('${row['reference'] ?? row['invoice_no'] ?? row['invoice_id']} · ${Formatters.currency(row['amount'] as num)}'),
          const SizedBox(height: 12), Text(l.partyPayables, style: Theme.of(context).textTheme.titleSmall),
          for (final row in data.payables) Text('${row['reference'] ?? row['purchase_id'] ?? row['purchase_order_id'] ?? row['bill_id'] ?? row['id']} · ${Formatters.currency(row['amount'] as num)}'),
          if (data.reversalReason != null) Text('${data.reversalDate ?? ''} · ${data.reversalReason}'),
          if (_reversing) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: _busy ? null : () async {
              final picked = await pickDate(context, initialDate: _date, lastDate: DateTime.now());
              if (picked != null && mounted) setState(() => _date = picked);
            }, icon: const Icon(Icons.calendar_today), label: Text('${l.fieldsDate}: ${isoDate(_date)}')),
            TextField(key: const Key('party_reverse_reason'), controller: _reason, enabled: !_busy, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: l.partyReverseReason)),
          ],
        ],
        if (_error != null) ...[Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), TextButton(onPressed: _busy ? null : _load, child: Text(l.commonRefresh))],
      ]))),
      actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context, _changed), child: Text(l.commonClose)),
        if (data?.status == 'posted' && canReverse) FilledButton(key: const Key('party_reverse_submit'), onPressed: _busy || (_reversing && _reason.text.trim().isEmpty) ? null : () {
          if (!_reversing) { setState(() => _reversing = true); } else { _reverse(); }
        }, child: Text(l.partyReverse))],
    ));
  }
}
