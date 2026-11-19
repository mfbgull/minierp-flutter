// GLM (PR #41 follow-up): InvoiceItem.reservation_id round trip.
//
// Focused model test for the field the edit form depends on: the server's
// invoice-detail item shape carries `reservation_id`, and the client model
// must parse it and re-emit it unchanged. This is the unit-level companion to
// the wire test (invoice_edit_reservation_id_wire_test.dart), which proves the
// parsed value actually reaches the PUT body.

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/invoice.dart';

Map<String, dynamic> _itemJson({Object? reservationId = 101}) =>
    <String, dynamic>{
      'id': 7,
      'invoice_id': 42,
      'item_id': 1,
      'item_name': 'Widget',
      'item_code': 'ITM-1',
      'quantity': 2,
      'unit_price': 100,
      'amount': 200,
      'tax_rate': 0,
      'discount_type': 'none',
      'discount_value': 0,
      'returned_qty': 0,
      ...reservationId == null ? const {} : {'reservation_id': reservationId},
    };

void main() {
  test('fromJson parses reservation_id when the server sends it', () {
    final item = InvoiceItem.fromJson(_itemJson());
    expect(item.reservationId, 101);
  });

  test('fromJson leaves reservation_id null when the field is absent', () {
    final item = InvoiceItem.fromJson(_itemJson(reservationId: null));
    expect(item.reservationId, isNull);
  });

  test('toJson re-emits reservation_id when present', () {
    final json = InvoiceItem.fromJson(_itemJson()).toJson();
    expect(json['reservation_id'], 101);
  });

  test('toJson omits reservation_id when absent (no null key on the wire)', () {
    final json = InvoiceItem.fromJson(_itemJson(reservationId: null)).toJson();
    expect(json.containsKey('reservation_id'), isFalse);
  });
}
