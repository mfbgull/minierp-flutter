import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/unified_payment.dart';

void main() {
  for (final source in ['expense_payment', 'supplier_advance', 'unknown_future_source']) {
    test('$source cannot use generic bulk deletion', () {
      final row = UnifiedPayment.fromJson({
        'source': source, 'source_id': 1, 'ref_no': 'REF-1',
        'date': '2026-09-01', 'amount': 50, 'method': 'cash',
        'type': 'expense', 'direction': 'out', 'status': 'posted',
      });
      expect(row.canDeleteGenerically, isFalse);
    });
  }
}
