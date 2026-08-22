## 1. Implement

- [x] 1.1 In `PaymentModel.createSupplierPayment` (`src/models/Payment.ts`), compute `singlePoId`: `poAllocs.length === 1 && purchaseAllocs.length === 0` → `parseInt(poAllocs[0].po_id, 10)`, otherwise `null`.
- [x] 1.2 Add `purchase_order_id` to the `INSERT INTO payments (payment_no, supplier_id, payment_date, amount, payment_method, reference_no, notes)` column list and bind `singlePoId` (or `null`) as the value.
- [x] 1.3 Add migration `src/migrations/add-payments-purchase-order-id.sql` (`ALTER TABLE payments ADD COLUMN purchase_order_id ...`) and wire `runPaymentsPurchaseOrderIdMigration()` into `src/config/database.ts` (column-existence guard, runs on startup).

## 2. Verify

- [x] 2.1 Run the server typecheck (`npx tsc --noEmit`) and lint (`npm run lint`); my changes add 0 new errors (pre-existing `no-empty` errors at database.ts:713-718 are unrelated).
- [x] 2.2 Add a model test in `src/__tests__/models.test.ts` asserting `purchase_order_id` is set for a single-PO supplier payment and stays `NULL` for multi-PO and PO+purchase mixed payments.
- [x] 2.3 Run the model tests (`npx jest src/__tests__/models.test.ts`); all 63 pass.
