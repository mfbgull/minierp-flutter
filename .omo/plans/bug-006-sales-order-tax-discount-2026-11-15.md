# BUG-006 — `sales_order_items` has no tax or discount columns

Plan (2026-11-15). **Implemented 2026-11-15** on `feat/bug-006-so-tax-discount`.

Delivered: migration `126_sales_order_item_tax_discount.sql`; server recompute in
`SalesOrderModel`; shared `validateSalesLineTaxDiscount`; conversion carries the
real per-line rate and discount (and never the stored gross); Dart model fields;
shared rounding in `sales_order_calculations.dart`; tax/discount inputs in the
sales-order form; 16 server tests, 7 Dart parity tests, 3 form widget tests.

Source: `docs/bugs.md:334`.
Buyer: Gull asked for the plan before any code.

## 1. The problem, in plain terms

A sales order line can hold a tax rate and a discount. The Flutter form already
collects both. **The server throws them away.**

Verified current state:

- `sales_order_items` columns: `id, so_id, item_id, quantity,
  delivered_quantity, unit_price, amount`. **No `tax_rate`, no `discount_type`,
  no `discount_value`.**
- `invoice_items` **has** all three, added by
  `add-invoice-discount-tax-fields.sql` (plus `net_amount` and `tax_amount`
  from `add-invoice-item-tax-columns.sql`). So the invoice side is complete and
  the order side is behind.
- `SalesOrderModel.create` / `.update` insert only
  `(so_id, item_id, quantity, unit_price, amount)`. `amount` is
  `quantity * unit_price` — no discount, no tax.
- The Flutter client **already computes** both.
  `lib/features/sales/calculations/sales_order_calculations.dart` has
  `calculateItemDiscount`, an after-discount subtotal, a per-line tax amount
  and a tax sum. `SOFormItem` carries `taxRate` and `discount`.
- The Flutter request body carries only `{item_id, quantity, unit_price}`.
  Tax and discount never leave the client.
- `SalesOrderModel.convertToInvoice` (line 637) maps SO lines to invoice lines
  with `discount_type: 'none' as const` and **no `tax_rate`**.

**Impact.** A user who sets 17% tax on an order sees it vanish. The order total
is the pre-tax, undiscounted sum. The invoice made from the order is also
pre-tax. The error is silent. This is a wrong-number bug, not a crash.

## 2. The trap that makes this non-trivial

`InvoiceCreationService` **recomputes** the invoice total from its lines and
rejects a mismatch. `InvoiceCreationService.ts:138-144`:

```ts
const totalAmount = computeInvoiceGrandTotal([...input.items], {...});
if (input.totalAmount !== undefined && Math.abs(input.totalAmount - totalAmount) > 0.01) {
  throw new InvoiceCreationTotalMismatchError(input.totalAmount, totalAmount);
}
```

`convertToInvoice` passes `totalAmount: salesOrder.total_amount` and builds
lines with no tax and no discount. Today this passes **only because both sides
are zero**.

So the order of work matters. If the SO starts storing tax and the conversion
does not change, **every conversion of a taxed order throws a 400 total
mismatch**. The header total and the line sum must move together. This is the
main risk and the main test target.

## 3. Schema migration

New file `server/src/migrations/add-sales-order-item-tax-discount.sql`,
registered in `server/src/config/database.ts` through `runLedgered` (checksummed
— this is a plain additive migration, **not** an FK-off rebuild, so it does not
need `noTxn`).

Mirror `invoice_items` exactly so the two sides cannot drift again:

```sql
ALTER TABLE sales_order_items ADD COLUMN tax_rate DECIMAL(5,2) DEFAULT 0;
ALTER TABLE sales_order_items ADD COLUMN discount_type VARCHAR(20) DEFAULT 'none';
ALTER TABLE sales_order_items ADD COLUMN discount_value DECIMAL(15,2) DEFAULT 0;
```

Default `discount_type = 'none'` (not `'percentage'`): `'none'` is the value
`convertToInvoice` already hardcodes, so existing rows read back exactly as they
behave today.

Do **not** add `net_amount` / `tax_amount` cache columns to
`sales_order_items` in this change. An order is not a posted document; it has no
journals and no ledger. Store the inputs (`tax_rate`, discount) and compute the
rest. Add caches only if a query needs them — it does not. (`shortcut:` if a
future report needs SO tax totals per line, add the columns then.)

## 4. Backfill for existing orders

**No data backfill.** The migration defaults are `0` / `'none'` / `0`, which is
exactly the value every existing row already behaves as. Backfilling nothing is
correct and is also the safest choice: the live database is
dummy/historical data (AGENTS.md) and we do not rewrite it.

State this in the migration header comment so a later reader does not "fix" it.

## 5. How conversion changes

In `SalesOrderModel.convertToInvoice`, map the real line values instead of
zeroes:

```ts
items: (salesOrder.items || []).map((item) => ({
  item_id: item.item_id,
  quantity: item.quantity,
  unit_price: item.unit_price,
  tax_rate: item.tax_rate,
  discount_type: item.discount_type,
  discount_value: item.discount_value,
  amount: item.amount,
})),
```

Two coupled obligations:

1. **`totalAmount` must be the grand total, not the line sum.**
   `salesOrder.total_amount` must itself be written as the tax-and-discount
   grand total at create/update time, using the same arithmetic as
   `computeInvoiceGrandTotal`. The simplest correct rule: **stop trusting the
   header field and let `InvoiceCreationService` derive it** — pass
   `totalAmount: undefined` for the conversion path. The service then computes
   from the same lines and cannot disagree with itself. Prefer this; keep the
   explicit `totalAmount` only where a genuine caller-supplied total exists.

2. **The client must send tax and discount.** Serialize `tax_rate`,
   `discount_type`, `discount_value` in the SO create/update body, next to
   `unit_price`. Without this the server has zeros to store and nothing changes
   for the user.

Validation: reuse the invoice-side rules. `tax_rate` 0–100,
`discount_type` in `('none','percentage','flat')`, `discount_value >= 0`, and a
percentage discount `< 100`. Put these in the shared zod schema so SO and
invoice agree, rather than writing a second validator.

## 6. Tests (red first)

Add `server/src/__tests__/salesOrderTaxDiscount.test.ts`.

**A. Migration/schema.**
1. A fresh DB has `tax_rate`, `discount_type`, `discount_value` on
   `sales_order_items`.
2. An order created before the columns existed (insert with explicit old
   columns) reads back `0 / 'none' / 0` after migration.

**B. Round-trip through the API.**
3. Create an SO with a taxed line (for example quantity 2, unit price 100, tax
   17%). `GET /api/sales-orders/:id` returns the tax and discount on the line.
4. The SO `total_amount` equals the tax-inclusive grand total, not
   `2 * 100`. **This is the red test today.**

**C. Conversion totals match — the core requirement.**
5. Convert the taxed order. The invoice is created (no 400). The invoice
   `total_amount` equals the SO `total_amount`.
6. The invoice **line** keeps the same `tax_rate` and discount as the SO line.
7. Sum of invoice line values (net + tax, discount applied) equals the invoice
   header total, within 0.01. This is the invariant the mismatch guard protects;
   assert it directly.
8. A conversion of a **zero-tax, zero-discount** order still works and gives
   the same numbers as before this change (regression guard for existing
   orders).

**D. Invariant G and the ledger.**
9. After conversion, GL AP/receivable equals the invoice total; the journal
   balances; `assertCashTimeline` is unaffected (an invoice is not cash).
10. Run the accounting invariants A–J for the converted order, as AGENTS.md
    requires for any accounting change.

**E. Flutter.**
11. The SO form sends `tax_rate` / `discount_type` / `discount_value` in the
    body, and the displayed SO total matches what the server stores. The
    calculation module already has tests; add the request-shape assertion at
    the repository/dialog boundary (Dio mock adapter, the house pattern).

## 7. Order of work

1. Migration + schema test (A). No behaviour change yet.
2. Server: store and return tax/discount; add zod validation (B). Red first.
3. Client: send tax/discount (E) — required for B to be reachable by a user.
4. Conversion: real line values, and let the service derive the total (C, D).
   Red first — write test 5 and watch the 400.
5. Full server suite and Flutter suite at the end of the phase.

## 8. What could go wrong

- **Header/line drift.** A stored SO total that disagrees with its lines. Test
  4 and test 7 exist for this. Removing the header total from the conversion
  path removes the whole class.
- **Old orders with stored totals.** Existing rows have `total_amount` equal to
  the undiscounted, untaxed sum and lines with zero tax, so they stay
  consistent. Test 8 pins that.
- **Reports that read `sales_order_items.amount`.** Checked on 2026-11-15:
  nothing but `SalesOrder.ts`, `Quotation.ts` (an INSERT) and
  `entityRegistry.ts` (table metadata) touches the table. No report reads it.
  So `amount` is free to keep its current meaning — pre-tax, pre-discount line
  value. If a report is ever added, it must not assume `amount` is the final
  line total.

## 9. Out of scope

- Quotation lines (quotations have the same shape and may have the same gap —
  check separately, do not fold into this change).
- Any historical-data repair (AGENTS.md).
</content>
