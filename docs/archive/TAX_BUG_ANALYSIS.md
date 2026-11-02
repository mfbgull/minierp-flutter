
---

## H2 — Persist the invoice header discount and give it back on returns

`createInvoice` read `notes` and the invoice-scope discount fields
(`discount_scope` / `discount_type` / `discount_value`) from the request
and used them to compute the grand total, but never forwarded them to
`InvoiceModel.createInvoice`. The stored row therefore kept
`discount_value = 0` (and `notes = NULL`) while its `total_amount` was
already discounted — so the return path had no discount to give back and
a discounted line could be credited for more than the customer was
charged. The update path already persisted all four fields.

### Changes

- `controllers/invoiceController.ts` — the create handler now passes
  `notes`, `discount_scope`, `discount_type` and `discount_value` into
  the `InvoiceModel.createInvoice` call.
- `services/returnMath.ts` — new pure `allocateHeaderDiscount(lines,
  {discount_scope, discount_type, discount_value, invoiceSubtotal})`:
  a no-op unless the discount is invoice-scoped and positive; otherwise
  the flat amount is spread over the WHOLE invoice pro-rata by line
  gross, scaled by each line's returned ratio, floored at 0 per line,
  and split to the cent with a largest-remainder pass so a full return
  closes exactly on the grand total. `ReturnedLine` now carries its
  pre-discount `lineGross`. Tax is never reduced — the deduction lands
  on the returned NET only, so H3's exact tax reversal still holds.
- `services/invoiceReturnService.ts` — computes `invoiceSubtotal` from
  the stored `invoice_items` rows (qty × unit_price, the same pre-tax
  base the grand total discounted — the stored `amount` is tax-INCLUSIVE
  and would inflate the base) and allocates the header discount before
  any downstream consumer sees the lines, so return items, stock
  reversal unit prices, GL lines, `returned_amount` and the over-return
  cap are all consistent. Mobile and desktop returns both funnel through
  this one point.

### Historical repair

`server/src/migrations/backfillInvoiceHeaderDiscount.ts` (boot key
`fn.backfillInvoiceHeaderDiscount`): the flat discount is exactly the gap
between the tax-inclusive line sum and the stored total, so legacy rows
with `discount_value = 0` are rewritten to `discount_type='flat'` with
that gap. Idempotent (repaired rows leave the zero-value predicate);
leaves undiscounted and cancelled invoices untouched.

### Tests added

- `server/src/__tests__/headerDiscountPersistence.test.ts` (11 tests) —
  percentage/flat header discount and notes persistence on create, null
  defaults, survival of an invoice update, full return crediting the
  discounted total, partial return crediting only its own share, a flat
  discount shared across lines, multi-line closing on the grand total,
  tax untouched with a header discount, credits capped by the invoice
  total, and every GL group still balanced.
- `server/src/__tests__/headerDiscountAllocation.unit.test.ts` (7 tests) —
  pure allocation math, including the cent-exact close and the negative
  guard.
- `server/src/__tests__/headerDiscountRepairMigration.test.ts` (5 tests) —
  gap recovery, post-repair full return, idempotency, and the
  undiscounted / cancelled exclusions.
