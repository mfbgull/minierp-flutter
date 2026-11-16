import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/owner_equity/owner_capital_form_dialog.dart';
import 'package:minierp_app/features/owner_equity/owner_withdrawal_form_dialog.dart';
import 'package:minierp_app/features/employees/employee_models.dart';
import 'package:minierp_app/features/employees/salary_pay_dialog.dart';
import 'package:minierp_app/features/purchases/supplier_refund_dialog.dart';
import 'package:minierp_app/data/models/purchase_return.dart';
import 'package:minierp_app/data/models/purchase_order.dart';
import 'package:minierp_app/features/purchase_orders/receive_goods_dialog.dart';
import 'package:minierp_app/features/sales/invoice_return_dialog.dart';
import 'package:minierp_app/features/expenses/expense_payments_dialog.dart';
import 'package:minierp_app/features/suppliers/supplier_bill_dialog.dart';
import 'package:minierp_app/data/models/supplier_bill.dart';
import 'package:minierp_app/features/suppliers/supplier_advance_dialog.dart';
import 'package:minierp_app/data/models/supplier_prepayment.dart';
import 'package:minierp_app/features/inventory/stock_adjustment_dialog.dart';
import 'package:minierp_app/features/inventory/stock_transfer_dialog.dart';
import 'package:minierp_app/features/purchases/purchase_return_form_dialog.dart';
import 'package:minierp_app/widgets/searchable_select.dart';

import '../test_helpers.dart';

void main() {
  final forms = <String, Widget>{
    'supplier advance': const SupplierAdvanceDialog.create(supplierId: 1),
    'supplier advance application': SupplierAdvanceDialog.apply(advance: const SupplierPrepayment(
      id: 1, supplierId: 1, amount: 200, appliedAmount: 0, availableAmount: 200, prepayDate: '2026-09-01', paymentMethod: 'Cash',
    )),
    'supplier bill payment': SupplierBillDialog.payment(bill: const SupplierBill(
      id: 1, supplierId: 1, billNo: 'BILL-1', billDate: '2026-09-01',
      netAmount: 200, inputTaxAmount: 0, totalAmount: 200, balanceAmount: 200, description: 'Services',
    )),
    'credit expense payment': const ExpensePaymentsDialog(expenseId: 1),
    'capital': const OwnerCapitalFormDialog(),
    'withdrawal': const OwnerWithdrawalFormDialog(),
    'sales return': const InvoiceReturnDialog(invoiceId: 1),
    'receipt': ReceiveGoodsDialog(
      detail: PurchaseOrderDetail.fromJson({
        'id': 1,
        'warehouse_id': 1,
        'items': [
          {
            'id': 1,
            'item_id': 1,
            'item_name': 'Test item',
            'quantity': 10,
            'unit_price': 10,
          },
        ],
      }),
    ),
    'salary': SalaryPayDialog(
      employee: Employee.fromJson({
        'id': 1,
        'employee_code': 'EMP-1',
        'first_name': 'Test',
        'salary': 100,
      }),
    ),
    'salary with deduction': SalaryPayDialog(
      employee: Employee.fromJson({
        'id': 1,
        'employee_code': 'EMP-1',
        'first_name': 'Test',
        'salary': 100,
      }),
    ),
    'supplier refund': Builder(
      builder: (context) => TextButton(
        onPressed: () => showSupplierRefundDialog(
          context,
          purchaseReturn: PurchaseReturn.fromJson({
            'id': 1,
            'credit_note_id': 1,
          }),
          refundable: 200,
        ),
        child: const Text('Open refund'),
      ),
    ),
    'stock adjustment': Builder(
      builder: (context) => TextButton(
        onPressed: () => showStockAdjustmentDialog(context),
        child: const Text('Open stock dialog'),
      ),
    ),
    'stock transfer': Builder(
      builder: (context) => TextButton(
        onPressed: () => showStockTransferDialog(context),
        child: const Text('Open stock dialog'),
      ),
    ),
    'purchase return': Builder(
      builder: (context) => TextButton(
        onPressed: () => showPurchaseReturnFormDialog(
          context,
          source: const ReturnSource.purchase(
            id: 1,
            no: 'PUR-1',
            warehouseId: 1,
          ),
        ),
        child: const Text('Open return'),
      ),
    ),
  };
  for (final entry in forms.entries) {
    testWidgets(
      '${entry.key} retries retain their key and an edited amount rotates it',
      (tester) async {
        final requests = <RequestOptions>[];
        final dio = createFakeDio({
          '/supplier-prepayments/1/targets': {
            'success': true,
            'data': [
              {'kind': 'supplier_bill', 'id': 7, 'reference': 'VENDOR-1', 'balance_amount': 200},
            ],
          },
          '/expenses/1': {
            'success': true,
            'data': {
              'id': 1,
              'expense_no': 'EXP-1',
              'expense_category': 'Services',
              'amount': 200,
              'expense_date': '2026-09-01',
              'payment_method': 'Credit',
              'status': 'Recorded',
              'paid_amount': 0,
              'payments': <Object?>[],
            },
          },
          if (entry.key == 'salary with deduction')
            '/employees/1/loans': {
              'success': true,
              'data': {
                'loans': [
                  {
                    'id': 7,
                    'employee_id': 1,
                    'amount': 200,
                    'balance': 200,
                    'monthly_installment': 20,
                    'status': 'active',
                  },
                ],
                'summary': <String, Object?>{},
              },
            },
          '/invoices/1': {
            'id': 1,
            'invoice_no': 'INV-1',
            'customer_id': 1,
            'invoice_date': '2026-09-01',
            'total_amount': 200,
            'balance_amount': 200,
            'items': [
              {
                'id': 1,
                'invoice_id': 1,
                'item_id': 1,
                'item_name': 'Return item',
                'quantity': 200,
                'unit_price': 1,
                'amount': 200,
              },
            ],
          },
          '/invoices': {'success': true, 'data': <Object?>[]},
          '/inventory/warehouses': {
            'success': true,
            'data': [
              {'id': 1, 'warehouse_code': 'WH-1', 'warehouse_name': 'Main'},
              {'id': 2, 'warehouse_code': 'WH-2', 'warehouse_name': 'Second'},
            ],
          },
          // Stock adjustment / transfer pickers.
          '/inventory/items': pagedEnvelope([
            {'id': 1, 'item_code': 'ITM-1', 'item_name': 'Test item'},
          ]),
          // Purchase-return source detail (bare object) and its line's
          // live stock so the returnable cap stays open.
          '/purchases/1': {
            'id': 1,
            'purchase_no': 'PUR-1',
            'purchase_date': '2026-09-01',
            'item_id': 1,
            'item_code': 'ITM-1',
            'item_name': 'Test item',
            'unit_of_measure': 'Nos',
            'quantity': 10,
            'unit_cost': 10,
            'total_cost': 100,
            'paid_amount': 100,
            'balance_amount': 0,
            'warehouse_id': 1,
            'warehouse_name': 'Main',
            'returned_quantity': 0,
          },
          '/inventory/items/1': {
            'id': 1,
            'item_code': 'ITM-1',
            'item_name': 'Test item',
            'stock_by_warehouse': [
              {
                'warehouse_id': 1,
                'warehouse_code': 'WH-1',
                'warehouse_name': 'Main',
                'quantity': 10,
              },
            ],
          },
          '/inventory/stock-batches': [],
          '/owner-equity/payment-method-options': {
            'success': true,
            'data': <Object?>[],
          },
        });
        dio.interceptors.insert(
          0,
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.method == 'POST') {
                requests.add(options);
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.receiveTimeout,
                  ),
                );
              } else {
                handler.next(options);
              }
            },
          ),
        );
        await tester.pumpWidget(
          buildTestable(Scaffold(body: entry.value), dio: dio),
        );
        await tester.pumpAndSettle();
        if (entry.key == 'supplier refund') {
          await tester.tap(find.text('Open refund'));
          await tester.pumpAndSettle();
        }
        if (entry.key == 'stock adjustment' || entry.key == 'stock transfer') {
          await tester.tap(find.text('Open stock dialog'));
          await tester.pumpAndSettle();
        }
        if (entry.key == 'purchase return') {
          await tester.tap(find.text('Open return'));
          await tester.pumpAndSettle();
        }
        if (entry.key == 'stock adjustment') {
          await tester.tap(find.byType(SearchableSelect<int>).at(0));
          await tester.pumpAndSettle();
          await tester.tap(find.text('ITM-1 — Test item').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(SearchableSelect<int>).at(1));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Main').last);
          await tester.pumpAndSettle();
        }
        if (entry.key == 'stock transfer') {
          await tester.tap(find.byType(SearchableSelect<int>).at(0));
          await tester.pumpAndSettle();
          await tester.tap(find.text('ITM-1 — Test item').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(SearchableSelect<int>).at(1));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Main').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(SearchableSelect<int>).at(2));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Second').last);
          await tester.pumpAndSettle();
        }
        if (entry.key == 'sales return') {
          await tester.tap(
            find.byWidgetPredicate((widget) => widget is SearchableSelect<int>),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Main').last);
          await tester.pumpAndSettle();
        }
        if (entry.key == 'supplier advance application') {
          await tester.tap(find.byType(DropdownButtonFormField<SupplierPaymentTarget>));
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('VENDOR-1').last);
          await tester.pumpAndSettle();
        }
        // The receipt and the purchase return cap their quantity, so they
        // enter smaller values; the cap must stay open for both submits.
        final firstQty = {'receipt': '5', 'purchase return': '5'}[entry.key] ?? '100';
        final editedQty = {'receipt': '6', 'purchase return': '6'}[entry.key] ?? '150';
        final amount = entry.key == 'supplier advance application'
          ? find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == 'Amount')
          : find.byType(TextField).first;
        final submit = find
            .byWidgetPredicate((widget) => widget is FilledButton)
            .last;
        await tester.enterText(amount, firstQty);
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        await tester.enterText(amount, editedQty);
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();

        expect(requests, hasLength(3));
        if (entry.key == 'supplier advance application') {
          for (final request in requests) {
            expect(request.path, '/supplier-prepayments/1/apply');
            expect(request.data['allocations'].first['kind'], 'supplier_bill');
            expect(request.data['allocations'].first['id'], 7);
          }
        }
        if (entry.key == 'salary with deduction') {
          for (final request in requests) {
            expect(request.path, '/employees/1/salary/pay');
            expect(request.data['loan_id'], 7);
            expect(request.data['loan_deduction'], 20);
          }
        }
        final keys = requests.map((r) => r.headers['Idempotency-Key']).toList();
        expect(
          keys[0],
          isA<String>().having(
            (value) => value.length,
            'length',
            greaterThanOrEqualTo(8),
          ),
        );
        expect(keys[1], keys[0]);
        expect(keys[2], isNot(keys[0]));
      },
    );
  }
}
