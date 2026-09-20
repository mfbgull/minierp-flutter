# Tax Posting Bug Analysis (H3 Fix)

## BUG SUMMARY

The controller calculates tax on pre-discount amount while stored invoice tax uses discounted net.

**Example:**
- Line: $1,000
- Discount: 20%
- Tax Rate: 10%

**Stored tax** = round(800 * 0.10) = **$80** (correct)
**GL tax** = round(1000 * 0.10) = **$100** (WRONG)

---

## ROOT CAUSE

### File: `server/src/controllers/invoiceController.ts` (lines 393-396)

```typescript
// BUG: Computes tax on GROSS (pre-discount)
const computedTaxAmount = items.reduce<number>((sum, item) => {
  const lineAmount = item.quantity * item.unit_price;  // <-- GROSS
  return sum + lineAmount * ((item.tax_rate || 0) / 100);
}, 0);
```

### File: `server/src/utils/currency.ts` (canonical calculation)

```typescript
// CORRECT: Computes tax on NET (post-discount)
export function decomposeLineAmount(args: {...}): {...} {
  // ... discount applied ...
  const net = subtractCurrency(gross, Math.min(discountAmount, gross));
  const taxAmount = taxRate !== 0 ? roundCurrency(net * (taxRate / 100)) : 0;
  return { amount: addCurrency(net, taxAmount), netAmount: net, taxAmount, gross };
}
```

---

## THE FIX

Replace the manual tax computation with `decomposeLineAmount` from `currency.ts`:

```typescript
import { decomposeLineAmount } from '../utils/currency';

// In createInvoice (replace lines 393-396):
const computedTaxAmount = items.reduce<number>((sum, item) => {
  const { taxAmount } = decomposeLineAmount({
    quantity: item.quantity,
    unit_price: item.unit_price,
    tax_rate: item.tax_rate,
    discount_type: item.discount_type,
    discount_value: item.discount_value,
  });
  return sum + taxAmount;
}, 0);
```

---

## SAME BUG IN updateInvoice

The `updateInvoice` function has the same pattern. Find and fix it too.

---

## ALSO CHECK

1. `server/src/controllers/mobileInvoiceController.ts` - may have same bug
2. `server/src/controllers/posController.ts` - may have same bug  
3. Return reversal tax calculation in `invoiceReturnService.ts`

---

## WHY decomposeLineAmount IS THE CANONICAL CALCULATION

1. **Used by `computeInvoiceGrandTotal`** - the server-authoritative total function (ACC-18)
2. **Used by `computeLineAmount`** - the stored invoice line amount
3. **Matches Flutter `invoice_calculations.dart`** - `_lineNet` + `_round2(net * item.tax / 100)`
4. **Matches `backfillInvoiceItemTax.ts`** - the migration uses same formula
5. **Single source of truth** - no second tax formula needed

---

## TESTS REQUIRED

Create `server/src/__tests__/taxPostingConsistency.test.ts`:

```typescript
describe('H3: Tax posting matches stored invoice tax', () => {
  it('no discount + tax', () => {
    // 1000 line, 10% tax = 100 tax
  });

  it('line discount + tax', () => {
    // 1000 line, 20% discount, 10% tax = 80 tax
  });

  it('multiple discounted lines + tax', () => {
    // Line 1: 500, 10% disc, 10% tax = 45
    // Line 2: 500, 20% disc, 10% tax = 40
    // Total tax = 85
  });

  it('full return - tax payable returns to zero', () => {
    // Create invoice with tax, full return, verify GL balance
  });

  it('partial return - tax reduces proportionally', () => {
    // Create invoice, return 50%, verify tax split
  });

  it('stored invoice tax == GL Tax Payable', () => {
    // Assert: sum(invoice_items.tax_amount) == GL tax credit
  });
});
```

---

## EXPECTED RESULT

After fix:
- `stored invoice tax` == `GL Tax Payable` in all cases
- After full return, tax payable returns to zero
- Revenue (net) also returns correctly via contra-revenue account


---

## IMPLEMENTATION STATUS — DONE (verified 2026-09-20)

All checks below pass: `tsc --noEmit` 0 errors, eslint 0 errors, full suite
**76 test files / 650 tests green**.

### What was actually wrong (real paths, not the illustrative `lib/…` ones)

The GL tax was recomputed from GROSS `qty × unit_price` at every
`AccountingService.postInvoiceEntry` call site, while the stored
`invoice_items.tax_amount` is `decomposeLineAmount(item).taxAmount`
(discounted net). Every discounted invoice was mis-split between Sales
Revenue (4000) and Tax Payable (2100). The AR debit was always correct.

Affected call sites fixed:

| File | Site |
| --- | --- |
| `server/src/controllers/invoiceController.ts` | create (~393) + update (~787) |
| `server/src/models/MobileInvoice.ts` | `submitInvoice` GL post |
| `server/src/controllers/posController.ts` | POS sale post (was hard-coded 0) |
| `server/src/models/SalesOrder.ts` | SO → invoice conversion post |

### The fix (stronger than the sketch above)

Rather than recomputing tax from the DTO again, the posting path now READS
the stored columns — the same rows the tax report and the return math read:

- `server/src/utils/currency.ts` → new `sumInvoiceLineTax(items)`:
  Σ `decomposeLineAmount(item).taxAmount` (the pure single-source-of-truth
  formula the doc above asks for).
- `server/src/models/Invoice.ts` → new `getInvoiceTaxTotal(db, invoiceId)`:
  `SELECT COALESCE(SUM(tax_amount), 0) FROM invoice_items WHERE invoice_id = ?`.
- Every `postInvoiceEntry` call site passes `InvoiceModel.getInvoiceTaxTotal(db, invoiceId)`.

This guarantees `GL Tax Payable == stored invoice tax` structurally — it
cannot diverge even if a DTO ever disagrees with the stored row.

### Return / reversal path — already correct, left as-is

`server/src/services/returnMath.ts::computeReturnedLine` decomposes the
stored line (discount + tax_rate from `invoice_items`) and takes the
proportional share: full return → ratio snaps to 1 → reverses the stored
tax exactly; partial → `round(storedTax × ratio)`. Verified by the new tests.

### Historical drift repair

`server/src/migrations/backfillInvoiceTaxGl.ts` (registered in the boot
ledger as `fn.backfillInvoiceTaxGl` in `server/src/config/database.ts`):

- For each invoice with a live INVOICE revenue posting:
  `delta = storedTax − postedTax`.
- `delta > 0` → Dr 4000 / Cr 2100; `delta < 0` → Dr 2100 / Cr 4000.
- Moves ONLY the Revenue ↔ Tax Payable split — AR, COGS, payments, returns
  and the subledgers are never touched.
- Dated on the original invoice date; idempotent (the correction is folded
  into `postedTax` on re-run); auto-excludes cancelled invoices (their
  INVOICE group is voided) and invoices never posted to the GL.

### Tests added

- `server/src/__tests__/taxPostingConsistency.test.ts` (9 tests) — the doc's
  exact matrix: no discount, percentage/flat item discount, header
  discount, multi-line rounding, zero-rated, full return, partial return,
  and the `stored invoice tax == GL Tax Payable` invariant.
- `server/src/__tests__/taxGlRepairMigration.test.ts` (6 tests) — repair of
  over-posted and under-posted drift, idempotency, and the cancelled /
  never-posted exclusions.
