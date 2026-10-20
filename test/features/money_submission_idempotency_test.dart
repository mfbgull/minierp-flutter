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
            ],
          },
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
        final amount = entry.key == 'supplier advance application'
          ? find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == 'Amount')
          : find.byType(TextField).first;
        final submit = find
            .byWidgetPredicate((widget) => widget is FilledButton)
            .last;
        await tester.enterText(amount, entry.key == 'receipt' ? '5' : '100');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        await tester.enterText(amount, entry.key == 'receipt' ? '6' : '150');
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
