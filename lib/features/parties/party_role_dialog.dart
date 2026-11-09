import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/party.dart';
import '../../data/repositories/api_result.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../data/repositories/paged_request.dart';
import '../../data/repositories/party_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/detail_tab_grid.dart';

class PartyRoleDialog extends ConsumerStatefulWidget {
  const PartyRoleDialog({super.key, required this.position, required this.linkExisting});
  final PartyPosition position;
  final bool linkExisting;
  @override
  ConsumerState<PartyRoleDialog> createState() => _PartyRoleDialogState();
}

class _Candidate {
  const _Candidate(this.id, this.code, this.name, this.contact, this.balance);
  final int id;
  final String code;
  final String name;
  final String contact;
  final num balance;
}

class _PartyRoleDialogState extends ConsumerState<PartyRoleDialog> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  List<_Candidate> _candidates = [];
  _Candidate? _selected;
  String? _error;
  bool _busy = false;
  bool _loading = false;
  bool _confirmed = false;
  int _page = 1;
  bool _hasNext = false;
  bool get _customer => widget.position.customer == null;

  @override
  void initState() {
    super.initState();
    _name.text = widget.position.displayName;
    if (widget.linkExisting) _load();
  }
  @override
  void dispose() {
    for (final c in [_search, _name, _code, _phone, _email]) { c.dispose(); }
    super.dispose();
  }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _selected = null; _confirmed = false; });
    final request = PagedRequest(page: _page, limit: 25, search: _search.text.trim());
    if (_customer) {
      final result = await ref.read(customerRepositoryProvider).list(request);
      if (!mounted) return;
      switch (result) {
        case ApiSuccess(:final data):
          _candidates = [for (final c in data.items) if (c.isActive) _Candidate(c.id, c.customerCode, c.customerName, [c.contactPerson, c.phone, c.email].whereType<String>().join(' · '), c.currentBalance)];
          _hasNext = data.hasNext;
        case ApiFailure(:final error): _error = error.message;
      }
    } else {
      final result = await ref.read(supplierRepositoryProvider).list(request);
      if (!mounted) return;
      switch (result) {
        case ApiSuccess(:final data):
          _candidates = [for (final s in data.items) if (s.isActive) _Candidate(s.id, s.supplierCode, s.supplierName, [s.contactPerson, s.phone, s.email].whereType<String>().join(' · '), s.currentBalance ?? 0)];
          _hasNext = data.hasNext;
        case ApiFailure(:final error): _error = error.message;
      }
    }
    setState(() => _loading = false);
  }
  Future<void> _submit() async {
    if (_busy) return;
    if (widget.linkExisting && (_selected == null || !_confirmed)) return;
    if (!widget.linkExisting && (_name.text.trim().isEmpty || (!_customer && _code.text.trim().isEmpty))) return;
    setState(() { _busy = true; _error = null; });
    final repo = ref.read(partyRepositoryProvider);
    final result = widget.linkExisting
      ? await repo.link(customerId: _customer ? _selected!.id : widget.position.customer!.id,
          supplierId: _customer ? widget.position.supplier!.id : _selected!.id)
      : await repo.addRole(widget.position.id, customer: _customer, body: {
          _customer ? 'customer_name' : 'supplier_name': _name.text.trim(),
          if (!_customer) 'supplier_code': _code.text.trim(),
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        });
    if (!mounted) return;
    switch (result) {
      case ApiSuccess(:final data): Navigator.of(context).pop(data);
      case ApiFailure(:final error): setState(() { _error = error.message; _busy = false; });
    }
  }
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final current = widget.position.customer ?? widget.position.supplier!;
    return PopScope(canPop: !_busy, child: AlertDialog(
      title: Text(widget.linkExisting ? l.partyLink : _customer ? l.partyAddCustomer : l.partyAddSupplier),
      content: SizedBox(width: 800, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${current.name} · ${current.code}'),
        Text('${_customer ? l.partyYouOwe : l.partyTheyOwe}: ${Formatters.currency(_customer ? widget.position.supplierBalance : widget.position.customerBalance)}'),
        const SizedBox(height: 16),
        if (widget.linkExisting) ...[
          TextField(controller: _search, enabled: !_busy && !_loading,
            decoration: InputDecoration(labelText: l.partySearch, suffixIcon: IconButton(tooltip: l.commonSearch,
              onPressed: _busy || _loading ? null : () { _page = 1; _load(); }, icon: const Icon(Icons.search))),
            onSubmitted: (_) { _page = 1; _load(); }),
          const SizedBox(height: 12),
          SizedBox(height: 250, child: _loading ? const Center(child: CircularProgressIndicator()) : DetailTabGrid<_Candidate>(
            data: _candidates, buildColumns: (l) => [
              PlutoColumn(title: l.partyName, field: 'name', type: PlutoColumnType.text(), width: 230),
              PlutoColumn(title: l.partyCode, field: 'code', type: PlutoColumnType.text(), width: 130),
              PlutoColumn(title: l.commonActions, field: 'action', type: PlutoColumnType.text(), width: 100,
                renderer: (cell) => TextButton(onPressed: _busy ? null : () => setState(() { _selected = cell.cell.value as _Candidate; _confirmed = false; }), child: Text(l.commonView))),
            ], gridRowFor: (c) => PlutoRow(cells: {'name': PlutoCell(value: c.name), 'code': PlutoCell(value: c.code), 'action': PlutoCell(value: c)}))),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(tooltip: l.commonPrevious, onPressed: _loading || _busy || _page <= 1 ? null : () { _page--; _load(); }, icon: const Icon(Icons.chevron_left)),
            Text('${l.commonPage} $_page'),
            IconButton(tooltip: l.commonNext, onPressed: _loading || _busy || !_hasNext ? null : () { _page++; _load(); }, icon: const Icon(Icons.chevron_right)),
          ]),
          if (_selected case final selected?) ...[
            Text('${selected.name} · ${selected.code}', style: Theme.of(context).textTheme.titleMedium),
            Text(selected.contact), Text(Formatters.currency(selected.balance)),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: _confirmed, onChanged: _busy ? null : (v) => setState(() => _confirmed = v ?? false), title: Text(l.partyLinkConfirm)),
          ],
        ] else ...[
          TextField(controller: _name, enabled: !_busy, decoration: InputDecoration(labelText: l.partyName)),
          if (!_customer) TextField(controller: _code, enabled: !_busy, decoration: InputDecoration(labelText: l.partyCode)),
          TextField(controller: _phone, enabled: !_busy, decoration: InputDecoration(labelText: l.fieldsPhone)),
          TextField(controller: _email, enabled: !_busy, decoration: InputDecoration(labelText: l.fieldsEmail)),
        ],
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]))),
      actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(onPressed: _busy || (widget.linkExisting && !_confirmed) ? null : _submit, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.linkExisting ? l.partyLink : l.commonSave))],
    ));
  }
}
