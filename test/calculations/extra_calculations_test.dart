// Smoke tests for the calculation modules that had no `.test.ts` in the
// kit (quotation, sales order, invoice rules, V2, customer) plus the
// invoice helpers the kit test file doesn't touch (status, numbering,
// row padding). Expectations are derived directly from the TS sources.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/data/models/customer.dart' show Customer;
import 'package:minierp_app/data/models/invoice.dart'
    show Discount, DiscountType, Invoice, PaymentMethod;
import 'package:minierp_app/data/models/item.dart' show Item, SaleType;
import 'package:minierp_app/data/models/ledger_entry.dart' show LedgerEntry;
import 'package:minierp_app/data/models/payment.dart' show Payment;
import 'package:minierp_app/features/customers/calculations/customer_calculations.dart';
import 'package:minierp_app/features/sales/calculations/invoice_calculations.dart';
import 'package:minierp_app/features/sales/calculations/invoice_rules.dart';
import 'package:minierp_app/features/sales/calculations/invoice_v2_calculations.dart';
import 'package:minierp_app/features/sales/calculations/quotation_calculations.dart'
    as quotation;
import 'package:minierp_app/features/sales/calculations/sales_order_calculations.dart'
    as sales_order;
import 'package:minierp_app/features/sales/models/sales_forms.dart'
    show DiscountScope, InvoiceFormItem, QuotationFormItem, SOFormItem, filterFilledItems;

const flatZero = Discount(type: DiscountType.flat, value: 0);

/* ── Invoice helpers (not covered by the kit test file) ─────────── */

void main() {
  // `formatDateString` delegates to Formatters.date (intl DateFormat);
  // plain unit tests need the locale symbols initialized explicitly.
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  group('invoice helpers', () {
    test('generateInvoiceNo has the INV-YYYY-NNNNNN shape', () {
      expect(generateInvoiceNo(), matches(RegExp(r'^INV-\d{4}-\d{6}$')));
    });

    test('field order follows the discount scope', () {
      expect(
        getFieldOrder(DiscountScope.item),
        ['description', 'quantity', 'rate', 'discountValue', 'tax', 'amount'],
      );
      expect(
        getFieldOrder(DiscountScope.invoice),
        ['description', 'quantity', 'rate', 'tax', 'amount'],
      );
      expect(getNextField('quantity', DiscountScope.item), 'rate');
      expect(getNextField('amount', DiscountScope.item), null);
      expect(getNextField('unknown', DiscountScope.item), null);
    });

    test('empty rows and padding', () {
      final row = createEmptyItemRow(0);
      expect(row.quantity, 1);
      expect(row.rate, 0);
      expect(row.saleType, SaleType.packed);
      expect(row.itemId, '');

      final padded = padItemsToMinimum(const [], min: 2);
      expect(padded.length, 2);
      // pad rows are quantity 0 (TS behaviour); createEmptyItemRow is 1
      expect(padded.every((r) => r.quantity == 0), true);
      // already at minimum → same list
      expect(padItemsToMinimum(const <InvoiceFormItem>[], min: 0), isEmpty);
    });

    test('createDefaultInvoice has sane defaults', () {
      final state = createDefaultInvoice();
      expect(state.status, 'Unpaid');
      expect(state.discountScope, DiscountScope.invoice);
      expect(state.items.length, 1);
      expect(state.invoiceNo, matches(RegExp(r'^INV-\d{4}-\d{6}$')));
      expect(state.customerId, '');
    });

    test('expected status: paid / partially paid / unpaid / existing', () {
      const items = <InvoiceFormItem>[
        InvoiceFormItem(
          id: 1,
          itemId: '1',
          description: 'Soap',
          quantity: 2,
          rate: 50,
          tax: 10,
          discount: flatZero,
          saleType: SaleType.packed,
        ),
      ];
      const overpay = [
        PaymentMethod(id: 1, method: 'Cash', amount: 300, referenceNo: ''),
      ];
      const underpay = [
        PaymentMethod(id: 1, method: 'Cash', amount: 50, referenceNo: ''),
      ];
      expect(
        getExpectedStatus(null, true, overpay, items,
            DiscountScope.invoice, flatZero),
        'Paid',
      );
      expect(
        getExpectedStatus(null, true, underpay, items,
            DiscountScope.invoice, flatZero),
        'Partially Paid',
      );
      expect(
        getExpectedStatus(null, false, const [], items,
            DiscountScope.invoice, flatZero),
        'Unpaid',
      );
      expect(
        getExpectedStatus('7', true, const [], items,
            DiscountScope.invoice, flatZero,
            currentStatus: 'Paid'),
        'Paid',
      );
    });
  });

  /* ── Quotation ─────────────────────────────────────────────────── */

  group('quotation calculations', () {
    const flat = QuotationFormItem(
      id: 1,
      itemId: '1',
      description: 'Soap',
      quantity: 2,
      rate: 50,
      tax: 10,
      discount: flatZero,
    );
    const pct = QuotationFormItem(
      id: 2,
      itemId: '2',
      description: 'Rice',
      quantity: 1,
      rate: 100,
      tax: 10,
      discount: Discount(type: DiscountType.percentage, value: 10),
    );

    test('totals', () {
      expect(quotation.calculateItemTotal(flat), 110);
      expect(quotation.calculateItemTotal(pct), 99); // 100 − 10% + tax on the remainder
      expect(quotation.calculateTotal([pct]), 99);
      expect(quotation.calculateSubtotal([flat]), 100);
      expect(quotation.calculateDiscount([pct]), 10);
    });

    test('row helpers and field navigation', () {
      final row = quotation.createEmptyItemRow(0);
      expect(row.quantity, 1);
      expect(row.itemId, '');
      expect(quotation.padItemsToMinimum(const <QuotationFormItem>[], min: 2).length, 2);
      expect(quotation.getFieldOrder(),
          ['description', 'quantity', 'rate', 'discountValue', 'tax']);
      expect(quotation.getNextField('rate'), 'discountValue');
      expect(quotation.getNextField('tax'), null);
    });

    test('getSellableItems filters raw materials', () {
      const raw = Item(
        id: 1,
        itemCode: 'RM1',
        itemName: 'Flour',
        unitOfMeasure: 'kg',
        currentStock: 10,
        isRawMaterial: true,
      );
      const finished = Item(
        id: 2,
        itemCode: 'FG1',
        itemName: 'Bread',
        unitOfMeasure: 'pcs',
        currentStock: 5,
        isFinishedGood: true,
      );
      final sellable = quotation.getSellableItems([raw, finished]);
      expect(sellable.map((i) => i.id), [2]);
    });

    test('filterFilledItems keeps rows with item id or description', () {
      const empty = QuotationFormItem(id: 1, itemId: '', description: '', quantity: 1, rate: 0, tax: 0, discount: flatZero);
      const filled = QuotationFormItem(id: 2, itemId: '5', description: 'X', quantity: 1, rate: 0, tax: 0, discount: flatZero);
      expect(filterFilledItems([empty, filled]), [filled]);
    });
  });

  /* ── Sales order ───────────────────────────────────────────────── */

  group('sales order calculations', () {
    const flat = SOFormItem(
      id: 1,
      itemId: '1',
      name: 'Soap',
      quantity: 2,
      unitPrice: 50,
      taxRate: 10,
      discount: flatZero,
    );
    const pct = SOFormItem(
      id: 2,
      itemId: '2',
      name: 'Rice',
      quantity: 1,
      unitPrice: 100,
      taxRate: 10,
      discount: Discount(type: DiscountType.percentage, value: 10),
    );

    test('totals', () {
      expect(sales_order.calculateItemTotal(flat), 110);
      expect(sales_order.calculateItemTotal(pct), 99);
      expect(sales_order.calculateTotal([pct]), 99);
      expect(sales_order.calculateSubtotal([flat]), 100);
    });

    test('field order and rows', () {
      expect(sales_order.getFieldOrder(),
          ['name', 'quantity', 'unitPrice', 'discountValue', 'taxRate']);
      expect(sales_order.getNextField('unitPrice'), 'discountValue');
      final row = sales_order.createEmptyItemRow(0);
      expect(row.quantity, 1);
      expect(row.name, '');
      expect(sales_order.padItemsToMinimum(const <SOFormItem>[], min: 2).length, 2);
    });
  });

  /* ── Invoice rules ─────────────────────────────────────────────── */

  group('invoice rules', () {
    test('payment validation', () {
      expect(isValidPaymentAmount(0), false);
      expect(isValidPaymentAmount(100), true);
      expect(doesPaymentExceedBalance(110, 100), true);
      expect(doesPaymentExceedBalance(90, 100), false);
    });

    test('submission validation messages', () {
      expect(validateInvoiceSubmission(null, 1), 'Please select a customer');
      expect(validateInvoiceSubmission('', 1), 'Please select a customer');
      expect(validateInvoiceSubmission('5', 0), 'Please add at least one item');
      expect(validateInvoiceSubmission('5', 2), null);
    });

    test('preparePaymentData builds allocation bodies', () {
      const methods = [
        PaymentMethod(id: 1, method: 'Cash', amount: 100, referenceNo: ''),
        PaymentMethod(id: 2, method: 'Check', amount: 0, referenceNo: ''),
      ];
      final result = preparePaymentData(
        methods,
        customerId: '5',
        paymentDate: '2026-08-03',
        invoiceNo: 'INV-2026-000001',
        invoiceId: '42',
        paymentNotes: 'note',
      );
      expect(result.length, 1);
      expect(result.first['customer_id'], '5');
      expect(result.first['amount'], 100);
      expect(result.first['payment_method'], 'Cash');
      expect(result.first['reference_no'], null);
      expect(result.first['description'], 'Payment for INV-2026-000001');
      expect(result.first['notes'], 'note');
      expect(result.first['invoice_allocations'],
          [{'invoice_id': 42, 'amount': 100}]);
    });

    test('delete/cancel guards', () {
      const unpaid = Invoice(
        id: 1,
        invoiceNo: 'INV-1',
        customerId: 1,
        invoiceDate: '2026-08-01',
        totalAmount: 100,
        paidAmount: 0,
        balanceAmount: 100,
        status: 'Unpaid',
      );
      const paid = Invoice(
        id: 2,
        invoiceNo: 'INV-2',
        customerId: 1,
        invoiceDate: '2026-08-01',
        totalAmount: 100,
        paidAmount: 100,
        balanceAmount: 0,
        status: 'Paid',
      );
      const cancelled = Invoice(
        id: 3,
        invoiceNo: 'INV-3',
        customerId: 1,
        invoiceDate: '2026-08-01',
        totalAmount: 100,
        paidAmount: 0,
        balanceAmount: 100,
        status: 'Cancelled',
      );
      expect(canDeleteInvoice(unpaid), true);
      expect(canDeleteInvoice(paid), false);
      expect(canShowDeleteAction(unpaid), true);
      expect(canShowDeleteAction(paid), false);
      expect(canCancelInvoice(unpaid), true);
      expect(canCancelInvoice(cancelled), false);
    });
  });

  /* ── Invoice V2 ────────────────────────────────────────────────── */

  group('invoice V2', () {
    test('empty item defaults', () {
      final item = createEmptyInvoiceV2Item();
      expect(item.quantity, 1);
      expect(item.itemId, '');
      expect(item.saleType, SaleType.packed);
      expect(item.discount.type, DiscountType.flat);
    });

    test('default state', () {
      final state = createDefaultInvoiceV2State();
      expect(state.invoiceNo, matches(RegExp(r'^INV-\d{4}-\d{6}$')));
      expect(state.customer, null);
      expect(state.discountScope, DiscountScope.invoice);
      expect(state.items.length, 1);
      expect(state.source, null);
      // documented quirk: default payment amount is 1 so totals auto-fill
      expect(state.payment.paymentMethods.single.amount, 1);
    });
  });

  /* ── Customer ──────────────────────────────────────────────────── */

  group('customer calculations', () {
    const ledgerEntries = [
      LedgerEntry(
        id: 1,
        transactionDate: '2026-07-01',
        transactionType: 'INVOICE',
        referenceNo: 'INV-1',
        description: '',
        debit: 100,
        credit: 0,
        balance: 100,
      ),
      LedgerEntry(
        id: 2,
        transactionDate: '2026-07-02',
        transactionType: 'RETURN',
        referenceNo: 'RET-1',
        description: '',
        debit: 100,
        credit: 0,
        balance: 200,
      ),
      LedgerEntry(
        id: 3,
        transactionDate: '2026-07-03',
        transactionType: 'PAYMENT',
        referenceNo: 'PAY-1',
        description: '',
        debit: 0,
        credit: 100,
        balance: 100,
        linkedInvoiceNo: 'INV-1',
      ),
    ];

    test('ledger totals exclude returns and returned-invoice entries', () {
      final totals =
          calculateLedgerTotals(ledgerEntries, returnedInvoiceNos: {'INV-1'});
      expect(totals.debit, 0);
      expect(totals.credit, 0);
      // balance still counts ALL entries for true AR
      expect(totals.balance, 100);

      final withoutReturns = calculateLedgerTotals([ledgerEntries[0], ledgerEntries[1]]);
      expect(withoutReturns.debit, 100);
      expect(withoutReturns.credit, 0);
      expect(withoutReturns.balance, 200);

      expect(calculateLedgerTotals(const []), (debit: 0, credit: 0, balance: 0));
    });

    test('invoice aggregates and credit utilization', () {
      const invoices = [
        Invoice(
          id: 1,
          invoiceNo: 'INV-1',
          customerId: 1,
          invoiceDate: '2026-07-01',
          totalAmount: 100,
          paidAmount: 100,
          balanceAmount: 0,
          status: 'Paid',
          updatedAt: '2026-07-05',
        ),
        Invoice(
          id: 2,
          invoiceNo: 'INV-2',
          customerId: 1,
          invoiceDate: '2026-07-10',
          totalAmount: 50,
          paidAmount: 0,
          balanceAmount: 50,
          status: 'Overdue',
        ),
        Invoice(
          id: 3,
          invoiceNo: 'INV-3',
          customerId: 1,
          invoiceDate: '2026-07-12',
          totalAmount: 30,
          paidAmount: 0,
          balanceAmount: 30,
          status: 'Unpaid',
        ),
      ];
      expect(calculateTotalInvoiced(invoices), 180);
      expect(calculateTotalPaid(invoices), 100);
      expect(calculateTotalOutstanding(invoices), 80);
      expect(calculateCreditUtilization(500, 1000), 50);
      expect(calculateCreditUtilization(500, null), 0);
      expect(calculateOverdueInvoices(invoices).map((i) => i.id), [2]);
      expect(countPaidInvoices(invoices), 1);
      expect(countUnpaidInvoices(invoices), 1);
      expect(calculateAverageDaysToPay(invoices), 4);
      expect(getRecentInvoices(invoices, count: 2).map((i) => i.invoiceNo),
          ['INV-3', 'INV-2']);
    });

    test('computeCustomerMetrics aggregates everything', () {
      const invoices = [
        Invoice(
          id: 1,
          invoiceNo: 'INV-1',
          customerId: 1,
          invoiceDate: '2026-07-01',
          totalAmount: 100,
          paidAmount: 100,
          balanceAmount: 0,
          status: 'Paid',
          updatedAt: '2026-07-05',
        ),
        Invoice(
          id: 2,
          invoiceNo: 'INV-2',
          customerId: 1,
          invoiceDate: '2026-07-10',
          totalAmount: 50,
          paidAmount: 0,
          balanceAmount: 50,
          status: 'Overdue',
        ),
        Invoice(
          id: 3,
          invoiceNo: 'INV-3',
          customerId: 1,
          invoiceDate: '2026-07-12',
          totalAmount: 30,
          paidAmount: 0,
          balanceAmount: 30,
          status: 'Unpaid',
        ),
      ];
      const ledger = [
        LedgerEntry(id: 1, transactionDate: '2026-07-01', transactionType: 'INVOICE', referenceNo: 'INV-1', description: '', debit: 100, credit: 0, balance: 100),
        LedgerEntry(id: 2, transactionDate: '2026-07-05', transactionType: 'PAYMENT', referenceNo: 'PAY-1', description: '', debit: 0, credit: 100, balance: 0),
        LedgerEntry(id: 3, transactionDate: '2026-07-10', transactionType: 'INVOICE', referenceNo: 'INV-2', description: '', debit: 50, credit: 0, balance: 50),
        LedgerEntry(id: 4, transactionDate: '2026-07-12', transactionType: 'INVOICE', referenceNo: 'INV-3', description: '', debit: 30, credit: 0, balance: 80),
      ];
      const customer = Customer(
        id: 1,
        customerCode: 'C001',
        customerName: 'Acme',
        currentBalance: 80,
        creditLimit: 1000,
      );

      final metrics = computeCustomerMetrics(invoices, ledger, customer);
      expect(metrics.currentBalance, 80);
      expect(metrics.totalDebit, 180);
      expect(metrics.totalCredit, 100);
      expect(metrics.totalInvoiced, 180);
      expect(metrics.totalPaid, 100);
      expect(metrics.totalOutstanding, 80);
      expect(metrics.creditUtilization, 8);
      expect(metrics.overdueInvoicesCount, 1);
      expect(metrics.paidInvoicesCount, 1);
      expect(metrics.unpaidInvoicesCount, 1);
      expect(metrics.overdueInvoicesItemsCount, 1);
      expect(metrics.avgDaysToPay, 4);
    });

    test('recent payments sort by date desc', () {
      const payments = [
        Payment(id: 1, paymentNo: 'PAY001', customerId: 1, paymentDate: '2026-07-01', amount: 100, paymentMethod: 'Cash'),
        Payment(id: 2, paymentNo: 'PAY002', customerId: 1, paymentDate: '2026-07-15', amount: 50, paymentMethod: 'Cash'),
      ];
      expect(getRecentPayments(payments).map((p) => p.paymentNo),
          ['PAY002', 'PAY001']);
    });

    test('legacy formatters', () {
      expect(formatAsCurrency(1234.5), r'$1,234.50');
      expect(formatAsCurrency('100'), r'$100.00');
      expect(formatAsCurrency(null), r'$0.00');
      expect(formatAsFixed(12.5), '12.50');
      expect(formatDateString('2026-08-03'), 'Aug 3, 2026');
      expect(formatDateString(null), '');
      expect(formatDateString(''), '');
    });
  });
}
