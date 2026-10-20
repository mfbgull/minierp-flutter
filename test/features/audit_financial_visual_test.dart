import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/data/models/supplier_bill.dart';
import 'package:minierp_app/data/models/supplier_prepayment.dart';
import 'package:minierp_app/features/expenses/expense_payments_dialog.dart';
import 'package:minierp_app/features/reports/tax_summary_report_screen.dart';
import 'package:minierp_app/features/suppliers/supplier_advance_dialog.dart';
import 'package:minierp_app/features/suppliers/supplier_bill_dialog.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(() async {
    final fontDirectory = Platform.environment['AUDIT_FONT_DIRECTORY'];
    if (Platform.environment['AUDIT_CAPTURE_DIR'] != null &&
        fontDirectory == null) {
      throw StateError(
        'AUDIT_FONT_DIRECTORY must point to Flutter material_fonts for readable captures',
      );
    }
    if (fontDirectory != null) {
      final loader = FontLoader('Roboto');
      for (final font in [
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-Bold.ttf',
      ]) {
        loader.addFont(
          File('$fontDirectory/$font').readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
    }
  });
  final surfaces = <String, Widget Function()>{
    'supplier-bill': () => const SupplierBillDialog.create(supplierId: 1),
    'bill-payment': () => SupplierBillDialog.payment(
      bill: const SupplierBill(
        id: 1,
        supplierId: 1,
        billNo: 'VENDOR-1',
        billDate: '2026-09-01',
        netAmount: 200,
        inputTaxAmount: 30,
        totalAmount: 230,
        balanceAmount: 230,
        description: 'Services',
      ),
    ),
    'supplier-advance': () => const SupplierAdvanceDialog.create(supplierId: 1),
    'advance-application': () => SupplierAdvanceDialog.apply(
      advance: const SupplierPrepayment(
        id: 1,
        supplierId: 1,
        amount: 200,
        appliedAmount: 0,
        availableAmount: 200,
        prepayDate: '2026-09-01',
        paymentMethod: 'Cash',
      ),
    ),
    'expense-payment': () => const ExpensePaymentsDialog(expenseId: 1),
    'tax-summary': () => const TaxSummaryReportScreen(),
  };
  for (final surface in surfaces.entries) {
    for (final size in [const Size(390, 844), const Size(1440, 900)]) {
      for (final dark in [false, true]) {
        final name =
            '${surface.key}-${size.width.toInt()}-${dark ? 'dark' : 'light'}';
        testWidgets(
          '$name fits, exposes fields and supports keyboard traversal',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final boundaryKey = GlobalKey();
            final semantics = tester.ensureSemantics();
            try {
              final dio = createFakeDio({
                '/supplier-prepayments/1/targets': successEnvelope([
                  {
                    'kind': 'supplier_bill',
                    'id': 7,
                    'reference': 'Vendor invoice 7',
                    'balance_amount': 200,
                  },
                ]),
                '/expenses/1': successEnvelope({
                  'id': 1,
                  'expense_date': '2026-09-01',
                  'amount': 200,
                  'payment_method': 'Credit',
                  'status': 'Recorded',
                  'expense_category': 'Utilities',
                  'payments': [],
                  'paid_amount': 0,
                }),
                '/expenses/payment-method-options': successEnvelope([
                  'Cash',
                  'Bank',
                  'Easypaisa',
                  'JazzCash',
                  'Upaisa',
                  'Credit',
                ]),
                '/reports/tax-summary': successEnvelope({
                  'total_tax': 20,
                  'input_tax': 15,
                  'net_tax': 5,
                }),
              });
              await tester.pumpWidget(
                buildTestable(
                  Theme(
                    data: dark ? AppTheme.dark : AppTheme.light,
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: Scaffold(body: surface.value()),
                    ),
                  ),
                  dio: dio,
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final fields = find.byType(TextField);
              if (fields.evaluate().isNotEmpty) {
                await tester.ensureVisible(fields.first);
                await tester.tap(fields.first);
                await tester.pumpAndSettle();
                final firstFocus = FocusManager.instance.primaryFocus;
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pumpAndSettle();
                expect(
                  FocusManager.instance.primaryFocus,
                  isNot(same(firstFocus)),
                );
              }
              expect(tester.takeException(), isNull);
              final captureDir = Platform.environment['AUDIT_CAPTURE_DIR'];
              if (captureDir != null) {
                await tester.runAsync(() async {
                  final boundary =
                      boundaryKey.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  final image = await boundary.toImage();
                  final bytes = (await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!;
                  await Directory(captureDir).create(recursive: true);
                  await File(
                    '$captureDir/$name.png',
                  ).writeAsBytes(bytes.buffer.asUint8List());
                  image.dispose();
                });
              }
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}
