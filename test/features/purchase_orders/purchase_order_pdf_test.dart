// Unit tests for the A4 purchase order PDF builder (PORTING.md §12).
// These only verify the bytes are a well-formed PDF and that the builder
// survives edge-case orders (no items, empty supplier, etc.) — layout
// mirrors the reference `PurchaseOrderTemplateA4.tsx` target.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/data/models/purchase_order.dart';
import 'package:minierp_app/features/purchase_orders/purchase_order_pdf.dart';

void main() {
  setUpAll(() async {
    // Formatters.date needs the intl date symbols for the en locale.
    await initializeDateFormatting('en');
  });

  /// Reads the PDF magic header without decoding the whole document.
  String pdfHeader(List<int> bytes) => String.fromCharCodes(bytes.take(5));

  test('buildA4PurchaseOrderPdf produces a well-formed PDF for a full order',
      () async {
    final purchaseOrder = PurchaseOrderDetail(
      id: 1,
      poNo: 'PO-2026-001',
      poDate: '2026-01-18',
      supplierId: 3,
      supplierName: 'Alpha Traders',
      warehouseId: 1,
      warehouseName: 'Main Warehouse',
      totalAmount: 1500,
      paidAmount: 500,
      balanceAmount: 1000,
      status: 'Partially Received',
      expectedDeliveryDate: '2026-02-01',
      notes: 'Deliver to the loading bay.',
      items: const [
        PurchaseOrderItem(
          id: 1,
          itemId: 10,
          itemCode: 'RM001',
          itemName: 'Raw Material A',
          unitOfMeasure: 'Kg',
          quantity: 100,
          unitPrice: 10,
          amount: 1000,
          receivedQuantity: 40,
          pendingQuantity: 60,
        ),
        PurchaseOrderItem(
          id: 2,
          itemId: 11,
          itemCode: 'RM002',
          itemName: 'Raw Material B',
          unitOfMeasure: 'Ltr',
          quantity: 50,
          unitPrice: 10,
          amount: 500,
          receivedQuantity: 0,
          pendingQuantity: 50,
        ),
      ],
    );

    final bytes = await buildA4PurchaseOrderPdf(purchaseOrder: purchaseOrder);

    expect(pdfHeader(bytes), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('buildA4PurchaseOrderPdf handles an order without items or dates',
      () async {
    final purchaseOrder = PurchaseOrderDetail(
      id: 2,
      poNo: 'PO-2026-002',
      poDate: '2026-01-25',
      supplierId: 1,
      supplierName: '',
      status: 'Draft',
      totalAmount: 0,
      items: const [],
    );

    final bytes = await buildA4PurchaseOrderPdf(purchaseOrder: purchaseOrder);

    expect(pdfHeader(bytes), '%PDF-');
    // No company + no items + empty supplier: builder must still not throw.
    expect(bytes.length, greaterThan(500));
  });

  test('buildA4PurchaseOrderPdf uses the default company block when none set',
      () async {
    final purchaseOrder = PurchaseOrderDetail(
      id: 3,
      poNo: 'PO-2026-003',
      poDate: '2026-01-30',
      supplierId: 2,
      supplierName: 'A Supplier',
      status: 'Completed',
      totalAmount: 12.5,
      items: const [
        PurchaseOrderItem(
          id: 3,
          itemId: 5,
          itemCode: 'B-05',
          itemName: 'Bolt',
          unitOfMeasure: '',
          quantity: 5,
          unitPrice: 2.5,
          amount: 12.5,
        ),
      ],
    );

    final bytes = await buildA4PurchaseOrderPdf(purchaseOrder: purchaseOrder);

    expect(pdfHeader(bytes), '%PDF-');
    expect(bytes.length, greaterThan(500));
  });
}
