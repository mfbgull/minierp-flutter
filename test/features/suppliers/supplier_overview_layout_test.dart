// The supplier Overview tab puts PO Status, Contact Information and Account
// Settings side by side below the Financial Summary, and stacks them when the
// window is too narrow for three columns (customer_tab parity).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/supplier.dart' show Supplier;
import 'package:minierp_app/data/repositories/purchase_order_repository.dart'
    show POSummary;
import 'package:minierp_app/data/repositories/supplier_repository.dart'
    show SupplierBalance;
import 'package:minierp_app/features/suppliers/supplier_overview_tab.dart';
import 'package:minierp_app/features/suppliers/supplier_providers.dart'
    show
        SupplierPOSummaryArgs,
        supplierBalanceProvider,
        supplierDetailFromDateProvider,
        supplierDetailProvider,
        supplierDetailToDateProvider,
        supplierPOSummaryProvider;

import '../../test_helpers.dart';

void main() {
  final supplier = Supplier.fromJson({
    'id': 1,
    'supplier_code': 'SUP001',
    'supplier_name': 'Alpha Traders',
    'contact_person': 'Ali',
  });

  // Each section card's header icon — stable, unlike the localized titles.
  const statusIcon = Icons.bar_chart_outlined;
  const contactIcon = Icons.phone_outlined;
  const accountIcon = Icons.tune_outlined;

  Future<void> pumpTab(WidgetTester tester, {required Size size}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const session = 1;
    await tester.pumpWidget(
      buildTestable(
        const Scaffold(
          body: SupplierOverviewTab(supplierId: 1, sessionId: session),
        ),
        overrides: [
          supplierDetailProvider(1).overrideWith((ref) async => supplier),
          supplierBalanceProvider(1).overrideWith(
            (ref) async => const SupplierBalance(
              supplierId: 1,
              supplierName: 'Alpha Traders',
              currentBalance: 100,
            ),
          ),
          supplierPOSummaryProvider(
            const SupplierPOSummaryArgs(supplierId: 1),
          ).overrideWith(
            (ref) async => const POSummary(
              totalPos: 4,
              totalValue: 1000,
              draftPos: 1,
              submittedPos: 1,
              partiallyReceivedPos: 1,
              completedPos: 1,
            ),
          ),
          // All dates — keeps the range pair local to the page.
          supplierDetailFromDateProvider(session).overrideWith((ref) => null),
          supplierDetailToDateProvider(session).overrideWith((ref) => null),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('three equal columns when the window is wide', (tester) async {
    await pumpTab(tester, size: const Size(1400, 1000));

    final status = tester.getTopLeft(find.byIcon(statusIcon));
    final contact = tester.getTopLeft(find.byIcon(contactIcon));
    final account = tester.getTopLeft(find.byIcon(accountIcon));

    // Same row, left to right.
    expect(status.dy, contact.dy);
    expect(contact.dy, account.dy);
    expect(status.dx, lessThan(contact.dx));
    expect(contact.dx, lessThan(account.dx));
  });

  testWidgets('stacks when the window is narrow', (tester) async {
    await pumpTab(tester, size: const Size(600, 1000));

    final status = tester.getTopLeft(find.byIcon(statusIcon));
    final contact = tester.getTopLeft(find.byIcon(contactIcon));
    final account = tester.getTopLeft(find.byIcon(accountIcon));

    // Same column, top to bottom.
    expect(status.dx, contact.dx);
    expect(contact.dx, account.dx);
    expect(status.dy, lessThan(contact.dy));
    expect(contact.dy, lessThan(account.dy));
  });
}
