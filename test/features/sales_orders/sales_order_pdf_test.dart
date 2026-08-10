// Unit tests for the A4 sales order PDF builder (PORTING.md §12). These
// only verify the bytes are a well-formed PDF and that the builder
// survives edge-case orders (no items, empty customer, etc.) — layout
// follows the same A4 conventions as the invoice/quotation templates.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/data/models/sales_order.dart';
import 'package:minierp_app/features/sales_orders/sales_order_pdf.dart';

void main() {
  setUpAll(() async {
    // Formatters.date needs the intl date symbols for the en locale.
    await initializeDateFormatting('en');
  });

  /// Reads the PDF magic header without decoding the whole document.
  String pdfHeader(List<int> bytes) => String.fromCharCodes(bytes.take(5));

  test('buildA4SalesOrderPdf produces a well-formed PDF for a full order',
      () async {
    final salesOrder = SalesOrderDetail(
      id: 1,
      soNo: 'SO-2026-001',
      soDate: '2026-01-20',
      customerId: 7,
      customerName: 'Acme Corp',
      deliveryDate: '2026-02-01',
      status: 'Confirmed',
      totalAmount: 1500,
      notes: 'Deliver to the main gate.',
      warehouseId: 1,
      warehouseCode: 'WH-MAIN',
      warehouseName: 'Main Warehouse',
      items: const [
        SalesOrderItem(
          id: 1,
          itemId: 10,
          itemName: 'Widget A',
          itemCode: 'FG001',
          quantity: 10,
          deliveredQuantity: 4,
          unitPrice: 100,
          amount: 1000,
        ),
        SalesOrderItem(
          id: 2,
          itemId: 11,
          itemName: 'Finished Good B',
          itemCode: 'FG002',
          quantity: 5,
          deliveredQuantity: 5,
          unitPrice: 100,
          amount: 500,
        ),
      ],
    );

    final bytes = await buildA4SalesOrderPdf(salesOrder: salesOrder);

    expect(pdfHeader(bytes), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('buildA4SalesOrderPdf handles an order without items or dates',
      () async {
    final salesOrder = SalesOrderDetail(
      id: 2,
      soNo: 'SO-2026-002',
      soDate: '2026-01-25',
      customerId: 1,
      customerName: '',
      status: 'Draft',
      totalAmount: 0,
      items: const [],
    );

    final bytes = await buildA4SalesOrderPdf(salesOrder: salesOrder);

    expect(pdfHeader(bytes), '%PDF-');
    // No company + no items + empty customer: builder must still not throw.
    expect(bytes.length, greaterThan(500));
  });

  test('buildA4SalesOrderPdf uses the default company block when none is set',
      () async {
    final salesOrder = SalesOrderDetail(
      id: 3,
      soNo: 'SO-2026-003',
      soDate: '2026-01-30',
      customerId: 2,
      customerName: 'A Customer',
      status: 'Delivered',
      totalAmount: 12.5,
      items: const [
        SalesOrderItem(
          itemId: 5,
          itemName: 'Bolt',
          itemCode: 'B-05',
          quantity: 5,
          unitPrice: 2.5,
          amount: 12.5,
        ),
      ],
    );

    final bytes = await buildA4SalesOrderPdf(salesOrder: salesOrder);

    expect(pdfHeader(bytes), '%PDF-');
    expect(bytes.length, greaterThan(500));
  });
}
