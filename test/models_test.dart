import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/bom.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/dashboard_summary.dart';
import 'package:minierp_app/data/models/expense.dart';
import 'package:minierp_app/data/models/invoice.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/models/production.dart';
import 'package:minierp_app/data/models/supplier.dart';

void main() {
  group('Customer', () {
    test('parses a server list-row payload (0/1 ints)', () {
      final json = {
        'id': 1,
        'customer_code': 'CUST-001',
        'customer_name': 'Alpha Traders',
        'contact_person': 'Ali',
        'email': 'ali@example.com',
        'phone': '0300-1234567',
        'payment_terms': 'Net 30',
        'payment_terms_days': 30,
        'credit_limit': 100000,
        'credit_utilization_percent': 12.5,
        'current_balance': 12500,
        'is_active': 1,
        'created_at': '2026-01-01 10:00:00',
      };
      final c = Customer.fromJson(json);

      expect(c.id, 1);
      expect(c.customerCode, 'CUST-001');
      expect(c.customerName, 'Alpha Traders');
      expect(c.currentBalance, 12500);
      expect(c.creditUtilizationPercent, 12.5);
      expect(c.isActive, isTrue);
      expect(c.shippingAddress, isNull);
    });

    test('tolerates boolean is_active and missing optionals', () {
      final c = Customer.fromJson({
        'id': 2,
        'customer_code': 'CUST-002',
        'customer_name': 'Beta',
        'current_balance': 0,
        'is_active': false,
      });
      expect(c.isActive, isFalse);
      expect(c.email, isNull);
      expect(c.currentBalance, 0);
    });

    test('round-trips through toJson', () {
      final original = Customer.fromJson({
        'id': 3,
        'customer_code': 'CUST-003',
        'customer_name': 'Gamma',
        'current_balance': 50.25,
        'is_active': 1,
      });
      final parsed = Customer.fromJson(original.toJson());
      expect(parsed.id, original.id);
      expect(parsed.customerName, original.customerName);
      expect(parsed.currentBalance, original.currentBalance);
      expect(parsed.isActive, original.isActive);
    });
  });

  group('Item', () {
    test('parses a server payload with 0/1 flags and sale_type', () {
      final json = {
        'id': 10,
        'item_code': 'ITM-001',
        'item_name': 'Cement Bag',
        'category': 'Building',
        'unit_of_measure': 'Bag',
        'current_stock': 45,
        'reorder_level': 20,
        'standard_cost': 800,
        'standard_selling_price': 950,
        'is_raw_material': 0,
        'is_finished_good': 1,
        'is_purchased': 1,
        'is_manufactured': 0,
        'sale_type': 'packed',
        'qty_decimal_precision': 0,
        'rounding_step': null,
        'is_active': 1,
      };
      final item = Item.fromJson(json);

      expect(item.id, 10);
      expect(item.itemCode, 'ITM-001');
      expect(item.currentStock, 45);
      expect(item.isFinishedGood, isTrue);
      expect(item.isRawMaterial, isFalse);
      expect(item.saleType, SaleType.packed);
      expect(item.roundingStep, isNull);
    });

    test('tolerates string ids and loose sale_type', () {
      final item = Item.fromJson({
        'id': '11',
        'item_code': 'ITM-002',
        'item_name': 'Loose Sugar',
        'unit_of_measure': 'kg',
        'current_stock': 12.5,
        'is_raw_material': true,
        'is_finished_good': false,
        'is_purchased': '1',
        'is_manufactured': '0',
        'sale_type': 'loose',
      });
      expect(item.id, 11);
      expect(item.currentStock, 12.5);
      expect(item.saleType, SaleType.loose);
      expect(item.isPurchased, isTrue);
      expect(item.isManufactured, isFalse);
    });

    test('round-trips through toJson', () {
      final original = Item.fromJson({
        'id': 12,
        'item_code': 'ITM-003',
        'item_name': 'Nails',
        'unit_of_measure': 'Box',
        'current_stock': 3,
        'is_raw_material': 1,
        'is_finished_good': 0,
        'is_purchased': 1,
        'is_manufactured': 0,
        'sale_type': 'packed',
      });
      final parsed = Item.fromJson(original.toJson());
      expect(parsed.id, original.id);
      expect(parsed.itemName, original.itemName);
      expect(parsed.isRawMaterial, original.isRawMaterial);
      expect(parsed.saleType, original.saleType);
      expect(parsed.toJson()['is_raw_material'], 1);
    });
  });

  group('Supplier', () {
    test('parses a server payload', () {
      final s = Supplier.fromJson({
        'id': 5,
        'supplier_code': 'SUP-001',
        'supplier_name': 'Steel Mills Ltd',
        'contact_person': 'Raza',
        'email': 'raza@steel.pk',
        'phone': '042-1112223',
        'address': 'Lahore',
        'payment_terms': 'Net 15',
        'is_active': 1,
      });
      expect(s.id, 5);
      expect(s.supplierName, 'Steel Mills Ltd');
      expect(s.isActive, isTrue);
      expect(s.currentBalance, isNull);
    });

    test('round-trips through toJson', () {
      final original = Supplier.fromJson({
        'id': 6,
        'supplier_code': 'SUP-002',
        'supplier_name': 'ChemCo',
        'is_active': 0,
      });
      final parsed = Supplier.fromJson(original.toJson());
      expect(parsed.id, original.id);
      expect(parsed.supplierName, original.supplierName);
      expect(parsed.isActive, isFalse);
    });
  });

  group('Invoice', () {
    final detailJson = {
      'id': 100,
      'invoice_no': 'INV-2026-0001',
      'customer_id': 1,
      'customer_name': 'Alpha Traders',
      'customer_email': 'ali@example.com',
      'customer_phone': '0300-1234567',
      'customer_address': 'Karachi',
      'customer_current_balance': 12500,
      'customer_credit_limit': 100000,
      'customer_credit_utilization': 12.5,
      'invoice_date': '2026-08-01',
      'due_date': '2026-08-31',
      'total_amount': 28500,
      'paid_amount': 10000,
      'balance_amount': 18500,
      'returned_amount': 0,
      'status': 'Partially Paid',
      'discount_scope': 'invoice',
      'discount_type': 'percentage',
      'discount_value': 5,
      'notes': 'Thanks',
      'terms': 'Net 30',
      'created_by': 1,
      'created_by_username': 'admin',
      'created_at': '2026-08-01 12:00:00',
      'updated_at': '2026-08-01 12:00:00',
      'source_type': 'DIRECT',
      'warehouse_id': 1,
      'warehouse_code': 'WH-001',
      'warehouse_name': 'Main',
      'items': [
        {
          'id': 501,
          'invoice_id': 100,
          'item_id': 10,
          'item_code': 'ITM-001',
          'item_name': 'Cement Bag',
          'quantity': 30,
          'unit_price': 950,
          'amount': 28500,
          'tax_rate': 0,
          'discount_type': 'none',
          'discount_value': 0,
          'returned_qty': 0,
        },
      ],
    };

    test('parses a detail payload (items + source links)', () {
      final inv = Invoice.fromJson(detailJson);

      expect(inv.id, 100);
      expect(inv.invoiceNo, 'INV-2026-0001');
      expect(inv.customerId, 1);
      expect(inv.status, 'Partially Paid');
      expect(InvoiceStatus.tryParse(inv.status), InvoiceStatus.partiallyPaid);
      expect(inv.balanceAmount, 18500);
      expect(inv.discountScope, 'invoice');
      expect(inv.sourceType, 'DIRECT');
      expect(inv.warehouseCode, 'WH-001');
      expect(inv.items, hasLength(1));
      expect(inv.items!.first.itemName, 'Cement Bag');
      expect(inv.items!.first.unitPrice, 950);
      expect(inv.items!.first.discountType, 'none');
    });

    test('parses client-style camelCase discountScope', () {
      final inv = Invoice.fromJson({
        'id': 101,
        'invoice_no': 'INV-2',
        'customer_id': 2,
        'invoice_date': '2026-08-02',
        'total_amount': 100,
        'paid_amount': 0,
        'balance_amount': 100,
        'status': 'Unpaid',
        'discountScope': 'item',
      });
      expect(inv.discountScope, 'item');
    });

    test('parses nested discount/payment/company blocks when present', () {
      final inv = Invoice.fromJson({
        'id': 102,
        'invoice_no': 'INV-3',
        'customer_id': 3,
        'invoice_date': '2026-08-03',
        'total_amount': 200,
        'paid_amount': 50,
        'balance_amount': 150,
        'status': 'Paid',
        'discount': {'type': 'flat', 'value': 10},
        'company': {
          'name': 'My Co',
          'email': 'a@b.c',
          'phone': '1',
          'address': 'x',
          'taxId': 'T1',
        },
        'payment': {
          'record_payment': true,
          'payment_date': '2026-08-03',
          'payment_amount': 50,
          'payment_method': 'Cash',
        },
        'paymentMethods': [
          {'id': 1, 'method': 'Cash', 'amount': 50},
        ],
      });

      expect(inv.discount!.type, DiscountType.flat);
      expect(inv.discount!.value, 10);
      expect(inv.company!.name, 'My Co');
      expect(inv.company!.taxId, 'T1');
      expect(inv.payment!.recordPayment, isTrue);
      expect(inv.paymentMethods, hasLength(1));
    });

    test('round-trips through toJson', () {
      final original = Invoice.fromJson(detailJson);
      final parsed = Invoice.fromJson(original.toJson());

      expect(parsed.id, original.id);
      expect(parsed.invoiceNo, original.invoiceNo);
      expect(parsed.status, original.status);
      expect(parsed.items, hasLength(original.items!.length));
      expect(parsed.items!.first.amount, original.items!.first.amount);
      expect(parsed.warehouseName, original.warehouseName);
    });

    test('handles empty/missing optional lists', () {
      final inv = Invoice.fromJson({
        'id': 103,
        'invoice_no': 'INV-4',
        'customer_id': 4,
        'invoice_date': '2026-08-04',
        'total_amount': 0,
        'paid_amount': 0,
        'balance_amount': 0,
        'status': 'Draft',
        'items': [],
      });
      expect(inv.items, isEmpty);
    });

    test('parses a bare list row (no items/discount keys) as nulls', () {
      final inv = Invoice.fromJson({
        'id': 104,
        'invoice_no': 'INV-5',
        'customer_id': 5,
        'invoice_date': '2026-08-05',
        'total_amount': 500,
        'paid_amount': 0,
        'balance_amount': 500,
        'status': 'Overdue',
        'source_type': null,
      });
      expect(inv.items, isNull);
      expect(inv.discount, isNull);
      expect(inv.discountScope, isNull);
      expect(inv.sourceType, isNull);
      expect(InvoiceStatus.tryParse(inv.status), InvoiceStatus.overdue);
    });
  });

  group('Expense', () {
    test('parses a server list-row payload', () {
      final json = {
        'id': 1,
        'expense_no': 'EXP-2605-0001',
        'expense_category': 'Fuel',
        'description': 'Generator diesel',
        'amount': 1000,
        'expense_date': '2026-05-22',
        'payment_method': 'Cash',
        'reference_no': '34f3f33',
        'vendor_name': 'abc',
        'project': null,
        'status': 'Approved',
        'created_at': '2026-05-22 15:55:17',
        'created_by_name': 'Fawad',
      };
      final e = Expense.fromJson(json);

      expect(e.id, 1);
      expect(e.expenseNo, 'EXP-2605-0001');
      expect(e.expenseCategory, 'Fuel');
      expect(e.amount, 1000);
      expect(e.expenseDate, '2026-05-22');
      expect(e.paymentMethod, 'Cash');
      expect(e.vendorName, 'abc');
      expect(e.project, isNull);
      expect(e.status, 'Approved');
      expect(e.createdByName, 'Fawad');
      expect(e.updatedAt, isNull);
    });

    test('tolerates missing optional fields and a null payment method', () {
      final e = Expense.fromJson({
        'id': 2,
        'expense_no': 'EXP-2605-0002',
        'expense_category': 'Rent',
        'amount': 500.5,
        'expense_date': '2026-05-23',
        'status': 'Draft',
      });
      expect(e.description, isNull);
      expect(e.paymentMethod, isNull);
      expect(e.referenceNo, isNull);
      expect(e.amount, 500.5);
      expect(e.status, 'Draft');
    });

    test('round-trips through toJson', () {
      final original = Expense.fromJson({
        'id': 3,
        'expense_no': 'EXP-2605-0003',
        'expense_category': 'Travel',
        'description': 'Hotel',
        'amount': 250,
        'expense_date': '2026-05-24',
        'payment_method': 'Credit Card',
        'status': 'Paid',
        'created_by_name': 'Ali',
      });
      final parsed = Expense.fromJson(original.toJson());
      expect(parsed.id, original.id);
      expect(parsed.expenseNo, original.expenseNo);
      expect(parsed.expenseCategory, original.expenseCategory);
      expect(parsed.amount, original.amount);
      expect(parsed.paymentMethod, original.paymentMethod);
      expect(parsed.createdByName, original.createdByName);
    });
  });

  group('ExpenseCategory', () {
    test('parses a category row with 0/1 is_active', () {
      final c = ExpenseCategory.fromJson({
        'id': 12,
        'category_name': 'Equipment',
        'description': 'Purchase of equipment and tools',
        'is_active': 1,
      });
      expect(c.id, 12);
      expect(c.categoryName, 'Equipment');
      expect(c.isActive, isTrue);
    });

    test('tolerates boolean is_active and missing description', () {
      final c = ExpenseCategory.fromJson({
        'id': 13,
        'category_name': 'Fuel',
        'is_active': false,
      });
      expect(c.isActive, isFalse);
      expect(c.description, isNull);
    });
  });

  group('ExpenseOption', () {
    test('parses value/label rows', () {
      final o = ExpenseOption.fromJson({'value': 'Cash', 'label': 'Cash'});
      expect(o.value, 'Cash');
      expect(o.label, 'Cash');
    });
  });

  group('Production', () {
    test('parses a server list row with joined warehouse names', () {
      final p = Production.fromJson({
        'id': 7,
        'production_no': 'PROD-2026-009',
        'output_item_id': 3,
        'output_quantity': 25,
        'warehouse_id': 1,
        'raw_materials_warehouse_id': 2,
        'production_date': '2026-08-14',
        'batch_no': 'BATCH-26-PRD-0009',
        'unit_cost': 112.5,
        'total_material_cost': 2500,
        'total_batch_cost': 2812.5,
        'output_item_name': 'Mango Juice',
        'output_uom': 'Carton',
        'finished_goods_warehouse_name': 'FG Warehouse',
        'raw_materials_warehouse_name': 'RM Warehouse',
        'created_by_username': 'admin',
      });
      expect(p.id, 7);
      expect(p.productionNo, 'PROD-2026-009');
      expect(p.outputQuantity, 25);
      expect(p.unitCost, 112.5);
      expect(p.totalBatchCost, 2812.5);
      expect(p.outputItemName, 'Mango Juice');
    });

    test('tolerates missing optionals and defaults overhead to 0', () {
      final p = Production.fromJson({
        'id': 8,
        'production_no': 'PROD-2026-010',
        'output_item_id': 4,
        'output_quantity': 10,
        'warehouse_id': 1,
        'production_date': '2026-08-12',
      });
      expect(p.batchNo, isNull);
      expect(p.remarks, isNull);
      expect(p.overheadCost, 0);
      expect(p.inputs, isEmpty);
      expect(p.outputItemName, isNull);
    });

    test('parses detail inputs', () {
      final p = Production.fromJson({
        'id': 7,
        'production_no': 'PROD-2026-009',
        'output_item_id': 3,
        'output_quantity': 25,
        'warehouse_id': 1,
        'production_date': '2026-08-11',
        'inputs': [
          {
            'id': 31,
            'production_id': 7,
            'item_id': 12,
            'quantity': 8.5,
            'warehouse_id': 2,
            'item_code': 'RM-012',
            'item_name': 'Sugar',
            'unit_of_measure': 'kg',
            'warehouse_code': 'RM-01',
            'warehouse_name': 'RM Warehouse',
          },
        ],
      });
      final input = p.inputs.single;
      expect(input.itemCode, 'RM-012');
      expect(input.itemName, 'Sugar');
      expect(input.quantity, 8.5);
      expect(input.warehouseName, 'RM Warehouse');
    });
  });

  group('Bom', () {
    test('parses a list row with aggregates and 0/1 is_active', () {
      final b = Bom.fromJson({
        'id': 1,
        'bom_no': 'BOM-2026-001',
        'bom_name': 'Juice Kit',
        'finished_item_id': 3,
        'finished_item_code': 'FG-003',
        'finished_item_name': 'Colour Juice',
        'finished_uom': 'Carton',
        'quantity': 10,
        'description': 'Standard batch',
        'is_active': 1,
        'item_count': 3,
        'total_material_cost': 850.5,
      });
      expect(b.bomNo, 'BOM-2026-001');
      expect(b.finishedItemName, 'Colour Juice');
      expect(b.quantity, 10);
      expect(b.isActive, isTrue);
      expect(b.itemCount, 3);
      expect(b.totalMaterialCost, 850.5);
    });

    test('tolerates boolean is_active and missing aggregates', () {
      final b = Bom.fromJson({
        'id': 2,
        'bom_no': 'BOM-2026-002',
        'bom_name': 'Gadget Kit',
        'finished_item_id': 9,
        'quantity': 5,
        'is_active': false,
      });
      expect(b.isActive, isFalse);
      expect(b.itemCount, isNull);
      expect(b.totalMaterialCost, isNull);
    });
  });

  group('Dashboard blocks', () {
    test('TopCustomer parses the top-customers row', () {
      final row = TopCustomer.fromJson({
        'customer_name': 'Alpha Traders',
        'total_revenue': 452300.50,
        'invoice_count': 18,
      });
      expect(row.customerName, 'Alpha Traders');
      expect(row.totalRevenue, 452300.50);
      expect(row.invoiceCount, 18);
    });

    test('SalesSummaryResult parses period totals', () {
      final row = SalesSummaryResult.fromJson({
        'period_total': 123456.75,
        'count': 9,
      });
      expect(row.periodTotal, 123456.75);
      expect(row.count, 9);
    });

    test('ExpenseSummaryResult parses period totals', () {
      final row = ExpenseSummaryResult.fromJson({
        'period_total': 6543.25,
        'count': 4,
      });
      expect(row.periodTotal, 6543.25);
      expect(row.count, 4);
    });

    test('ProductionStatusResult parses the status counts', () {
      final row = ProductionStatusResult.fromJson({
        'total': 20,
        'active': 5,
        'completed': 12,
        'cancelled': 3,
      });
      expect(row.total, 20);
      expect(row.active, 5);
      expect(row.completed, 12);
      expect(row.cancelled, 3);
    });

    test('StockMovementSummaryResult parses inbound/outbound/net', () {
      final row = StockMovementSummaryResult.fromJson({
        'inbound_qty': 850,
        'outbound_qty': 320,
        'net': 530,
      });
      expect(row.inboundQty, 850);
      expect(row.outboundQty, 320);
      expect(row.net, 530);
    });

    test('KpiResult parses metric/value/unit/label', () {
      final row = KpiResult.fromJson({
        'metric': 'stock_health',
        'value': 87.5,
        'unit': '%',
        'label': 'Stock Health',
      });
      expect(row.metric, 'stock_health');
      expect(row.value, 87.5);
      expect(row.unit, '%');
      expect(row.label, 'Stock Health');
    });

    test('ArSummaryResult parses total + aging buckets', () {
      final row = ArSummaryResult.fromJson({
        'total_ar': 250000,
        'current_amount': 80000,
        'amount_1_30': 60000,
        'amount_31_60': 50000,
        'amount_61_90': 40000,
        'amount_over_90': 20000,
        'customer_count': 7,
      });
      expect(row.totalAr, 250000);
      expect(row.currentAmount, 80000);
      expect(row.amount130, 60000);
      expect(row.amount3160, 50000);
      expect(row.amount6190, 40000);
      expect(row.amountOver90, 20000);
      expect(row.customerCount, 7);
    });

    test('block models tolerate missing/string keys', () {
      final top = TopCustomer.fromJson({'customer_name': 'X'});
      expect(top.totalRevenue, 0);
      expect(top.invoiceCount, 0);

      final kpi = KpiResult.fromJson({
        'metric': 'stock_health',
        'value': '88', // numeric string
      });
      expect(kpi.value, 88);
      expect(kpi.unit, '');
    });
  });

  group('BomDetail', () {
    test('parses items and keeps the header aggregates', () {
      final d = BomDetail.fromJson({
        'id': 1,
        'bom_no': 'BOM-2026-001',
        'bom_name': 'Juice Kit',
        'finished_item_id': 3,
        'quantity': 10,
        'is_active': 1,
        'total_material_cost': 850.5,
        'items': [
          {
            'id': 11,
            'item_id': 12,
            'item_code': 'RM-012',
            'item_name': 'Sugar',
            'unit_of_measure': 'kg',
            'current_stock': 40,
            'quantity': 2,
            'standard_cost': 208.5,
            'line_cost': 417,
          },
        ],
      });
      expect(d.totalMaterialCost, 850.5);
      final item = d.items.single;
      expect(item.itemCode, 'RM-012');
      expect(item.quantity, 2);
      expect(item.standardCost, 208.5);
      expect(item.lineCost, 417);
      expect(item.currentStock, 40);
    });
  });
}
