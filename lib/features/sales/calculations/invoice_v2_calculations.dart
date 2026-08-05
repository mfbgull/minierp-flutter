// V2 Invoice Calculations (PORTING.md §7).
// 1:1 port of `calculations/invoiceV2Calculations.ts`.
//
// The TS file re-exports the shared invoice math with casts between the
// V2 and form item shapes. Dart achieves the same type-safely: both item
// types implement `CalculableLine`, so the shared functions accept
// `List<InvoiceV2FormItem>` directly — no casts, no duplicate math.

import '../../../data/models/invoice.dart' show PaymentMethod;
import '../../../data/models/item.dart' show SaleType;
import '../models/sales_forms.dart'
    show
        DiscountScope,
        InvoiceV2FormItem,
        InvoiceV2Payment,
        InvoiceV2State,
        defaultCompany,
        flatZeroDiscount,
        isoDate;

// `export` re-exports for consumers only — the file itself needs a plain
// import to call `generateInvoiceNo` in the factories below.
import 'invoice_calculations.dart' show generateInvoiceNo;

export 'invoice_calculations.dart'
    show
        calculateDiscount,
        calculateItemTotal,
        calculateSubtotal,
        calculateTax,
        calculateTotal,
        generateInvoiceNo;

InvoiceV2FormItem createEmptyInvoiceV2Item([int? id]) {
  return InvoiceV2FormItem(
    id: id ?? DateTime.now().millisecondsSinceEpoch,
    itemId: '',
    description: '',
    quantity: 1,
    rate: 0,
    tax: 0,
    discount: flatZeroDiscount,
    saleType: SaleType.packed,
    amount: 0,
    lastEditedField: null,
    qtyDecimalPrecision: 0,
    roundingStep: null,
  );
}

InvoiceV2State createDefaultInvoiceV2State() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return InvoiceV2State(
    invoiceNo: generateInvoiceNo(),
    customer: null,
    invoiceDate: isoDate(),
    dueDate: isoDate(const Duration(days: 14)),
    discountScope: DiscountScope.invoice,
    discount: flatZeroDiscount,
    items: [createEmptyInvoiceV2Item()],
    notes: 'Thank you for your business. Payment is due within 14 days.',
    terms: 'Net 14 days. Late payments subject to 1.5% monthly interest.',
    source: null,
    payment: InvoiceV2Payment(
      recordPayment: true,
      paymentDate: isoDate(),
      // Amount defaults to 1 instead of 0 so the invoice total auto-fills
      // correctly; the actual total is synced when items change in the page.
      paymentMethods: [
        PaymentMethod(id: now, method: 'Cash', amount: 1, referenceNo: ''),
      ],
      paymentNotes: '',
    ),
    company: defaultCompany,
  );
}
