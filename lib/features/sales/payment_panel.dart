// Payment panel for the invoice form — port of the web client's
// `InvoicePaymentPanel.tsx`. Sits beside the items grid (desktop split).
// Owns the record-payment toggle, payment date/notes, per-method rows
// (method / amount / reference), the existing-payment list with
// edit + delete, and the payment/balance summary.
//
// Authorization (amount > 0, amount <= remaining balance) and all posting
// live in the page — this widget is presentational + local text state.

import 'package:flutter/material.dart';

import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart'
    show InvoicePaymentRecord, PaymentMethod;
import '../../l10n/app_localizations.dart';
import '../../widgets/searchable_select.dart';

/// Payment methods offered by the reference dropdown.
const List<String> kPaymentMethods = [
  'Cash',
  'Check',
  'Bank Transfer',
  'Credit Card',
  'Online Payment',
];

class PaymentPanel extends StatefulWidget {
  const PaymentPanel({
    super.key,
    required this.isEdit,
    required this.recordPayment,
    required this.paymentDate,
    required this.methods,
    required this.existingPayments,
    required this.deletedPayments,
    required this.total,
    required this.paidAmount,
    required this.balance,
    required this.saving,
    required this.onRecordChanged,
    required this.onPickPaymentDate,
    required this.onPaymentNotesChanged,
    required this.onAddMethod,
    required this.onRemoveMethod,
    required this.onUpdateMethod,
    required this.onRecord,
    required this.onDeletePayment,
    required this.onEditPayment,
  });

  final bool isEdit;
  final bool recordPayment;
  final DateTime paymentDate;
  final List<PaymentMethod> methods;
  final List<InvoicePaymentRecord> existingPayments;
  final Set<int> deletedPayments;

  /// Invoice total (create mode) / stored total (edit mode).
  final num total;
  final num paidAmount;

  /// Remaining balance the payment is authorized against.
  final num balance;
  final bool saving;

  final ValueChanged<bool> onRecordChanged;
  final VoidCallback onPickPaymentDate;
  final ValueChanged<String> onPaymentNotesChanged;
  final VoidCallback onAddMethod;
  final void Function(int id) onRemoveMethod;

  /// field: `method` | `amount` | `reference_no`
  final void Function(int id, String field, Object? value) onUpdateMethod;
  final VoidCallback onRecord;
  final void Function(InvoicePaymentRecord payment) onDeletePayment;
  final void Function(InvoicePaymentRecord payment) onEditPayment;

  @override
  State<PaymentPanel> createState() => PaymentPanelState();
}

/// State of the payment panel — public so the invoice form can focus the
/// first payment-method amount field via a `GlobalKey` (Shift+Enter
/// shortcut, spec §7).
class PaymentPanelState extends State<PaymentPanel> {
  final Map<int, TextEditingController> _amountControllers = {};
  final Map<int, TextEditingController> _referenceControllers = {};
  final Map<int, FocusNode> _amountFocusNodes = {};
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    for (final c in _referenceControllers.values) {
      c.dispose();
    }
    for (final n in _amountFocusNodes.values) {
      n.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  /// The first method's Amount field focus node — created at build time
  /// (via [_amountNode]) so the TextField is *attached* to the same node
  /// [focusFirstAmount] later requests. Lazy creation in the focus call
  /// would leave the TextField on its own internal node and the request
  /// would silently no-op.
  FocusNode _amountNode(int id) => _amountFocusNodes.putIfAbsent(id, () {
    final n = FocusNode();
    n.addListener(() {
      if (!n.hasFocus) return;
      // Bring the focused amount field into view when the panel body is
      // scrolled (spec: invoice-form-layout §4.5 focus-into-view).
      final ctx = n.context;
      if (ctx != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Scrollable.ensureVisible(ctx, alignment: 0.5);
        });
      }
      final c = _amountControllers[id];
      if (c != null && c.text.isNotEmpty) {
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      }
    });
    return n;
  });

  /// Focus the first payment-method amount field, selecting its existing
  /// text (spec §8.20). Ensures at least one method row exists first.
  void focusFirstAmount() {
    if (widget.saving) return;
    if (widget.methods.isEmpty) {
      widget.onAddMethod();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.methods.isNotEmpty) {
          _focusAmount(widget.methods.first.id);
        }
      });
      return;
    }
    _focusAmount(widget.methods.first.id);
  }

  void _focusAmount(int id) => _amountNode(id).requestFocus();

  TextEditingController _amountController(PaymentMethod m) =>
      _amountControllers.putIfAbsent(
        m.id,
        () =>
            TextEditingController(text: m.amount == 0 ? '' : _plain(m.amount)),
      );

  TextEditingController _referenceController(PaymentMethod m) =>
      _referenceControllers.putIfAbsent(
        m.id,
        () => TextEditingController(text: m.referenceNo ?? ''),
      );

  num get _paymentSum => widget.methods.fold<num>(0, (s, m) => s + m.amount);

  bool get _showForm => widget.isEdit || widget.recordPayment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      // The body scrolls internally so the panel fits the right column's
      // height in the fixed-height layout (spec: invoice-form-layout
      // §4.5); the Record Payment button scrolls with it.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(l10n, theme),
            const Divider(height: 16),
            if (widget.isEdit) _existingPayments(l10n),
            if (_showForm) _paymentForm(l10n),
            // Create mode records payments as part of invoice save (no
            // invoice id to allocate yet); edit mode records immediately.
            if (widget.isEdit) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: widget.saving ? null : widget.onRecord,
                  icon: widget.saving
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payments_outlined, size: 16),
                  label: Text(l10n.paymentsRecordpayment),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────

  Widget _header(AppLocalizations l10n, ThemeData theme) {
    if (!widget.isEdit) {
      return Row(
        children: [
          const Icon(Icons.payments_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.salesPayment,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Checkbox(
            value: widget.recordPayment,
            visualDensity: VisualDensity.compact,
            onChanged: widget.saving
                ? null
                : (v) => widget.onRecordChanged(v ?? false),
          ),
          Flexible(
            child: Text(
              l10n.salesRecordpaymentnow,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.payments_outlined, size: 18),
            const SizedBox(width: 6),
            Text(
              l10n.salesPayment,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _summaryLine(l10n.salesGrandtotal, widget.total, null),
        _summaryLine(
          l10n.salesTotalpaid,
          widget.paidAmount,
          const Color(0xff16a34a),
        ),
        _summaryLine(
          l10n.salesBalance,
          widget.balance,
          widget.balance > 0
              ? theme.colorScheme.error
              : const Color(0xff16a34a),
        ),
      ],
    );
  }

  Widget _summaryLine(String label, num value, Color? color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        // Flexible + ellipsis: long labels truncate instead of pushing
        // the value out of the narrow panel column.
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        Text(
          Formatters.currency(value),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );

  // ── Existing payments (edit mode) ──────────────────────────────

  Widget _existingPayments(AppLocalizations l10n) {
    final visible = [
      for (final p in widget.existingPayments)
        if (!widget.deletedPayments.contains(p.id)) p,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.salesPaymenthistory,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 4),
        for (final p in visible)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${Formatters.date(p.paymentDate ?? '')} · ${p.method}',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                Formatters.currency(p.amount),
                style: const TextStyle(fontSize: 12),
              ),
              IconButton(
                tooltip: l10n.commonEdit,
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                icon: const Icon(Icons.edit_outlined),
                onPressed: widget.saving ? null : () => widget.onEditPayment(p),
              ),
              IconButton(
                tooltip: l10n.commonDelete,
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                icon: const Icon(Icons.delete_outline),
                onPressed: widget.saving
                    ? null
                    : () => widget.onDeletePayment(p),
              ),
            ],
          ),
        const Divider(height: 16),
      ],
    );
  }

  // ── New-payment form ───────────────────────────────────────────

  Widget _paymentForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 38,
          child: OutlinedButton.icon(
            onPressed: widget.saving ? null : widget.onPickPaymentDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 14),
            label: Text(
              Formatters.date(isoDate(widget.paymentDate)),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.salesPaymentmethods,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: widget.saving ? null : widget.onAddMethod,
              icon: const Icon(Icons.add, size: 14),
              label: Text(
                l10n.salesAddmethod,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        for (final m in widget.methods) _methodRow(l10n, m),
        const SizedBox(height: 6),
        _summaryLine(l10n.salesPaymenttotal, _paymentSum, null),
        _summaryLine(l10n.salesBalance, widget.balance, null),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          enabled: !widget.saving,
          onChanged: widget.onPaymentNotesChanged,
          style: const TextStyle(fontSize: 12),
          decoration: _fieldDecoration(l10n.fieldsNotes),
        ),
      ],
    );
  }

  Widget _methodRow(AppLocalizations l10n, PaymentMethod m) {
    final isFirst = m == widget.methods.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchableSelect<String>(
            items: kPaymentMethods,
            selected: kPaymentMethods.contains(m.method)
                ? m.method
                : kPaymentMethods.first,
            labelBuilder: (method) => method,
            textStyle: const TextStyle(fontSize: 12),
            enabled: !widget.saving,
            decoration: _fieldDecoration(l10n.salesMethod),
            onChanged: (v) {
              if (v != null) widget.onUpdateMethod(m.id, 'method', v);
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController(m),
                  focusNode: isFirst ? _amountNode(m.id) : null,
                  enabled: !widget.saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  decoration: _fieldDecoration(l10n.fieldsAmount),
                  onChanged: (v) => widget.onUpdateMethod(
                    m.id,
                    'amount',
                    num.tryParse(v.trim()) ?? 0,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _referenceController(m),
                  enabled: !widget.saving,
                  style: const TextStyle(fontSize: 12),
                  decoration: _fieldDecoration(l10n.salesReference),
                  onChanged: (v) =>
                      widget.onUpdateMethod(m.id, 'reference_no', v),
                ),
              ),
              if (widget.methods.length > 1)
                IconButton(
                  tooltip: l10n.commonRemove,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.close),
                  onPressed: widget.saving
                      ? null
                      : () {
                          _amountControllers.remove(m.id)?.dispose();
                          _referenceControllers.remove(m.id)?.dispose();
                          _amountFocusNodes.remove(m.id)?.dispose();
                          widget.onRemoveMethod(m.id);
                        },
                ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 11),
    isDense: true,
    border: const OutlineInputBorder(),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
  );

  static String _plain(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}
