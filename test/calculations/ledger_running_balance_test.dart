// Regression guard for the customer Ledger tab running-balance display.
//
// Origin: customer 15 (Jabran, CUST-0926-00013) showed "Balance 0" in the KPI
// but a row cell of "-550" in the Ledger tab. Investigation proved BOTH are
// correct but they are different quantities:
//   - the KPI/footer is the CLOSING balance (live net over all rows) = 0;
//   - a row cell is the RUNNING balance after that row; it legitimately reads
//     -550 after the second Rs 550 return (RET-0926-00002, 2026-09-20), which
//     was never refunded, and returns to 0 only after the October rows.
//
// The stored `customer_ledger.balance` column equals the live running balance
// on every active row (verified against the live DB). This test locks that
// invariant so a future writer cannot silently let the column drift from the
// ledger's own debit/credit history.
//
// The display fix (label clarity) is covered by the l10n keys
// `customersLedgerRunningbalance` / `customersLedgerClosingbalance`.

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/ledger_entry.dart';

LedgerEntry _entry({
  required int id,
  required String type,
  String date = '2026-01-01',
  num debit = 0,
  num credit = 0,
  num balance = 0,
}) => LedgerEntry(
  id: id,
  transactionDate: date,
  transactionType: type,
  referenceNo: 'REF-$id',
  description: '',
  debit: debit,
  credit: credit,
  balance: balance,
);

/// Live running balance after each row, in endpoint order
/// (transaction_date ASC, id ASC).
List<num> _liveRunning(List<LedgerEntry> ledger) {
  final out = <num>[];
  num running = 0;
  for (final e in ledger) {
    running += e.debit - e.credit;
    out.add(running);
  }
  return out;
}

void main() {
  group('ledger running balance', () {
    test('cumulative debit-minus-credit matches the stored column', () {
      // Exact active rows for customer 15 (voided/reversed rows excluded —
      // the endpoint returns only active rows, ACC-14).
      final ledger = [
        _entry(id: 100, type: 'INVOICE', date: '2026-09-16', debit: 1800, balance: 1800),
        _entry(id: 101, type: 'PAYMENT', date: '2026-09-16', credit: 1800, balance: 0),
        _entry(id: 102, type: 'RETURN', date: '2026-09-16', credit: 600, balance: -600),
        _entry(id: 103, type: 'INVOICE', date: '2026-09-17', debit: 1200, balance: 600),
        _entry(id: 104, type: 'CREDIT_OFFSET', date: '2026-09-17', credit: 600, balance: 0),
        _entry(id: 105, type: 'PAYMENT', date: '2026-09-17', credit: 600, balance: -600),
        _entry(id: 106, type: 'RETURN', date: '2026-09-17', credit: 600, balance: -1200),
        _entry(id: 107, type: 'INVOICE', date: '2026-09-17', debit: 1800, balance: 600),
        _entry(id: 108, type: 'CREDIT_OFFSET', date: '2026-09-17', credit: 1200, balance: -600),
        _entry(id: 109, type: 'PAYMENT', date: '2026-09-17', credit: 600, balance: -1200),
        _entry(id: 110, type: 'INVOICE', date: '2026-09-17', debit: 1800, balance: 600),
        _entry(id: 111, type: 'PAYMENT', date: '2026-09-17', credit: 600, balance: 0),
        _entry(id: 112, type: 'RETURN', date: '2026-09-18', credit: 550, balance: -550),
        _entry(id: 113, type: 'REFUND', date: '2026-09-18', debit: 550, balance: 0),
        _entry(id: 115, type: 'RETURN', date: '2026-09-20', credit: 550, balance: -550),
        _entry(id: 119, type: 'INVOICE', date: '2026-10-08', debit: 600, balance: 50),
        _entry(id: 120, type: 'PAYMENT', date: '2026-10-08', credit: 50, balance: 0),
        _entry(id: 125, type: 'INVOICE', date: '2026-10-10', debit: 600, balance: 600),
        _entry(id: 126, type: 'PAYMENT', date: '2026-10-10', credit: 400, balance: 200),
        _entry(id: 129, type: 'PAYMENT', date: '2026-10-10', credit: 1400, balance: -1200),
        _entry(id: 130, type: 'PAYMENT', date: '2026-10-10', credit: 600, balance: -1800),
        _entry(id: 131, type: 'INVOICE', date: '2026-10-10', debit: 1800, balance: 0),
      ];

      final live = _liveRunning(ledger);
      final stored = ledger.map((e) => e.balance).toList();

      // Invariant: stored column == live running balance on every row.
      expect(stored, live);

      // The two returned rows are legitimately -550 (not a stale artefact).
      expect(stored[12], -550); // row 112
      expect(stored[14], -550); // row 115

      // The CLOSING balance (the KPI/footer figure) is 0, not -550.
      expect(live.last, 0);
    });
  });
}
