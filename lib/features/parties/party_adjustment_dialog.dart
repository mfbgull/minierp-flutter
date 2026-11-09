import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/idempotency_key.dart';
import '../../data/models/party.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/party_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker.dart';

class PartyAdjustmentDialog extends ConsumerStatefulWidget {
  const PartyAdjustmentDialog({super.key, required this.position});
  final PartyPosition position;
  @override
  ConsumerState<PartyAdjustmentDialog> createState() => _PartyAdjustmentDialogState();
}

class _PartyAdjustmentDialogState extends ConsumerState<PartyAdjustmentDialog> {
  final _amounts = <String, TextEditingController>{};
  final _notes = TextEditingController();
  final _keys = IdempotencyKeyCache(prefix: 'party-adjustment');
  DateTime _date = DateTime.now();
  PartyAdjustmentTargets? _targets;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _invalid = false;
  PartyAdjustment? _posted;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() {
    for (final c in _amounts.values) { c.dispose(); }
    _notes.dispose();
    super.dispose();
  }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final result = await ref.read(partyRepositoryProvider).targets(widget.position.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case ApiSuccess(:final data): _targets = data;
        case ApiFailure(:final error): _error = error.message;
      }
    });
  }
  int _minor(PartyAdjustmentTarget target) {
    final text = _amounts[target.key]?.text.trim() ?? '';
    if (text.isEmpty) return 0;
    final value = num.tryParse(text.replaceAll(',', ''));
    return value == null || !value.isFinite ? -1 : (value * 100).round();
  }
  int _total(List<PartyAdjustmentTarget> targets) => targets.fold(0, (sum, t) => sum + _minor(t));
  Future<void> _submit() async {
    final targets = _targets;
    if (_busy || targets == null) return;
    final all = [...targets.receivables, ...targets.payables];
    final total = _total(targets.receivables);
    final invalid = total <= 0 || total != _total(targets.payables) ||
      total > (widget.position.maximumAdjustment * 100).round() ||
      all.any((t) => _minor(t) < 0 || _minor(t) > (t.balance * 100).round() ||
        (_minor(t) > 0 && isoDate(_date).compareTo(t.date.substring(0, 10)) < 0));
    if (invalid) { setState(() => _invalid = true); return; }
    final body = <String, dynamic>{
      'adjustment_date': isoDate(_date), 'amount': total / 100,
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      'receivables': [for (final t in targets.receivables) if (_minor(t) > 0) {'invoice_id': t.id, 'amount': _minor(t) / 100}],
      'payables': [for (final t in targets.payables) if (_minor(t) > 0) {'kind': t.kind, 'id': t.id, 'amount': _minor(t) / 100}],
    };
    setState(() { _busy = true; _invalid = false; _error = null; });
    final result = await ref.read(partyRepositoryProvider).post(widget.position.id, body, _keys.keyFor(body));
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case ApiSuccess(:final data): _posted = data;
        case ApiFailure(:final error): _error = error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final targets = _targets;
    final amount = targets == null ? 0 : _total(targets.receivables) / 100;
    return PopScope(canPop: !_busy, child: AlertDialog(
      title: Text(_posted == null ? l.partyAdjust : l.partyPosted),
      content: SizedBox(width: 900, child: _loading
        ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
        : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.position.displayName, style: Theme.of(context).textTheme.titleMedium),
          Text('${widget.position.customer?.code ?? ''} · ${widget.position.supplier?.code ?? ''}'),
          const SizedBox(height: 12),
          Text(l.partyNoCash),
          if (_posted case final posted?) ...[
            const SizedBox(height: 16),
            Text('${posted.number} · ${Formatters.currency(posted.amount)}'),
          ] else ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _busy ? null : () async {
              final picked = await pickDate(context, initialDate: _date, lastDate: DateTime.now());
              if (picked != null && mounted) setState(() => _date = picked);
            }, icon: const Icon(Icons.calendar_today), label: Text('${l.fieldsDate}: ${isoDate(_date)}')),
            if (targets != null) ...[
              _section(l.partyInvoices, targets.receivables),
              _section(l.partyPayables, targets.payables),
              const SizedBox(height: 12),
              Text('${l.partyMaximum}: ${Formatters.currency(widget.position.maximumAdjustment)}'),
              Text('${l.partyAllocation}: ${Formatters.currency(amount)}', style: Theme.of(context).textTheme.titleMedium),
              Text('${l.partyAfter}: ${l.partyTheyOwe} ${Formatters.currency(widget.position.customerBalance - amount)} · ${l.partyYouOwe} ${Formatters.currency(widget.position.supplierBalance - amount)}'),
              const SizedBox(height: 12),
              TextField(controller: _notes, enabled: !_busy, decoration: InputDecoration(labelText: l.fieldsNotes), maxLines: 2),
            ],
            if (_invalid) Padding(padding: const EdgeInsets.only(top: 12), child: Text(l.partyInvalidAllocation, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (_error != null) ...[
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              TextButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), label: Text(l.commonRefresh)),
            ],
          ],
        ]))),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(_posted != null), child: Text(l.commonClose)),
        if (_posted == null) FilledButton(key: const Key('party_adjust_submit'), onPressed: _busy || _loading || targets == null ? null : _submit,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l.partyAdjust)),
      ],
    ));
  }
  Widget _section(String title, List<PartyAdjustmentTarget> targets) {
    final l = AppLocalizations.of(context)!;
    return Padding(padding: const EdgeInsets.only(top: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      if (targets.isEmpty) Text(l.commonNoresults),
      for (final t in targets) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
        Expanded(child: Text('${t.reference}\n${t.date} · ${Formatters.currency(t.balance)}')),
        const SizedBox(width: 12),
        SizedBox(width: 150, child: TextField(key: Key('party_amount_${t.key}'),
          controller: _amounts.putIfAbsent(t.key, TextEditingController.new), enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l.partyAllocation), onChanged: (_) => setState(() => _invalid = false))),
      ])),
    ]));
  }
}
