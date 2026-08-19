// Unit tests for `ledger_grouping.dart` — the port of the web
// `utils/ledgerGrouping.ts`: group-by-invoice behavior (linked_invoice_no,
// INVOICE/CANCELLATION self-reference, description match), RETURN
// exclusion, and original-order output.

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/ledger_entry.dart';
import 'package:minierp_app/features/customers/calculations/ledger_grouping.dart';

LedgerEntry _entry({
  required int id,
  required String type,
  String ref = '',
  String? linked,
  String description = '',
  num debit = 0,
  num credit = 0,
  num balance = 0,
}) => LedgerEntry(
  id: id,
  transactionDate: '2026-01-01',
  transactionType: type,
  referenceNo: ref,
  description: description,
  debit: debit,
  credit: credit,
  balance: balance,
  linkedInvoiceNo: linked,
);

void main() {
  group('extractInvoiceNo', () {
    test('RETURN entries never resolve to an invoice', () {
      expect(
        extractInvoiceNo(
          _entry(id: 1, type: 'RETURN', ref: 'RTN-1', linked: 'INV-001'),
        ),
        isNull,
      );
    });

    test('linked_invoice_no wins when present', () {
      expect(
        extractInvoiceNo(
          _entry(
            id: 2,
            type: 'PAYMENT',
            ref: 'PAY-1',
            linked: 'INV-002',
            description: 'Payment for INV-999',
          ),
        ),
        'INV-002',
      );
    });

    test('INVOICE and CANCELLATION group by their own reference', () {
      expect(
        extractInvoiceNo(_entry(id: 3, type: 'INVOICE', ref: 'INV-003')),
        'INV-003',
      );
      expect(
        extractInvoiceNo(_entry(id: 4, type: 'CANCELLATION', ref: 'INV-003')),
        'INV-003',
      );
    });

    test('comma-joined linked invoices never match a single group', () {
      // The server joins a multi-invoice payment's allocations into a
      // comma-separated `linked_invoice_no`; the raw string matches no
      // single group key, so the entry is rendered ungrouped.
      expect(
        extractInvoiceNo(
          _entry(
            id: 7,
            type: 'PAYMENT',
            ref: 'PAY-6',
            linked: 'INV-A, INV-B',
          ),
        ),
        'INV-A, INV-B',
      );

      final nodes = groupLedgerByInvoice([
        _entry(id: 1, type: 'INVOICE', ref: 'INV-A', debit: 100),
        _entry(id: 2, type: 'INVOICE', ref: 'INV-B', debit: 100),
        _entry(
          id: 3,
          type: 'PAYMENT',
          ref: 'PAY-6',
          linked: 'INV-A, INV-B',
          credit: 40,
        ),
      ]);

      expect(nodes, hasLength(3));
      expect(nodes[0], isA<InvoiceGroupNode>());
      expect(nodes[1], isA<InvoiceGroupNode>());
      expect(nodes[2], isA<UngroupedNode>());
      expect((nodes[2] as UngroupedNode).entry.entry.referenceNo, 'PAY-6');
    });

    test('falls back to a for/against/on description match', () {
      expect(
        extractInvoiceNo(
          _entry(
            id: 5,
            type: 'PAYMENT',
            ref: 'PAY-2',
            description: 'Payment for INV-004',
          ),
        ),
        'INV-004',
      );
      expect(
        extractInvoiceNo(
          _entry(id: 6, type: 'PAYMENT', ref: 'PAY-3', description: 'against INV-005'),
        ),
        'INV-005',
      );
    });
  });

  group('groupLedgerByInvoice', () {
    test('groups payments under their invoice and tracks totalPaid/balance', () {
      final ledger = [
        _entry(id: 1, type: 'INVOICE', ref: 'INV-100', debit: 100),
        _entry(id: 2, type: 'PAYMENT', ref: 'PAY-1', linked: 'INV-100', credit: 40),
        _entry(id: 3, type: 'PAYMENT', ref: 'PAY-2', linked: 'INV-100', credit: 60),
      ];

      final nodes = groupLedgerByInvoice(ledger);

      expect(nodes, hasLength(1));
      final group = (nodes.single as InvoiceGroupNode).group;
      expect(group.invoice.referenceNo, 'INV-100');
      expect(group.children, hasLength(2));
      expect(group.totalPaid, 100);
      expect(group.balance, 0);
    });

    test('keeps RETURN entries ungrouped and preserves input order', () {
      final ledger = [
        _entry(id: 1, type: 'RETURN', ref: 'RTN-1', credit: 10),
        _entry(id: 2, type: 'INVOICE', ref: 'INV-200', debit: 50),
        _entry(id: 3, type: 'PAYMENT', ref: 'PAY-3', linked: 'INV-200', credit: 50),
      ];

      final nodes = groupLedgerByInvoice(ledger);

      expect(nodes, hasLength(2));
      expect(nodes[0], isA<UngroupedNode>());
      expect(nodes[1], isA<InvoiceGroupNode>());
      expect((nodes[0] as UngroupedNode).entry.entry.referenceNo, 'RTN-1');
      expect((nodes[1] as InvoiceGroupNode).group.invoice.referenceNo, 'INV-200');
    });

    test('resolves an invoice from a description match', () {
      final ledger = [
        _entry(id: 1, type: 'INVOICE', ref: 'INV-300', debit: 90),
        _entry(
          id: 2,
          type: 'PAYMENT',
          ref: 'PAY-4',
          description: 'Payment for INV-300',
          credit: 90,
        ),
      ];

      final nodes = groupLedgerByInvoice(ledger);

      expect(nodes, hasLength(1));
      expect(
        (nodes.single as InvoiceGroupNode).group.children,
        hasLength(1),
      );
    });

    test('unmatched non-invoice entries become ungrouped rows', () {
      final ledger = [
        _entry(id: 1, type: 'INVOICE', ref: 'INV-400', debit: 20),
        _entry(id: 2, type: 'PAYMENT', ref: 'PAY-5', credit: 5),
      ];

      final nodes = groupLedgerByInvoice(ledger);

      expect(nodes, hasLength(2));
      expect(nodes[0], isA<InvoiceGroupNode>());
      expect(nodes[1], isA<UngroupedNode>());
      expect((nodes[1] as UngroupedNode).entry.entry.referenceNo, 'PAY-5');
    });
  });
}
