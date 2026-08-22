FORENSIC AUDIT — PAYMENTS / PURCHASES / PURCHASE RETURNS / EXPENSES / CASH
Read-only. No file was modified. All paths absolute; all line numbers verified against current source.

---

## 0. CORRECTIONS TO THE SUPPLIED FACTS

Before the findings — three of the stated FACTS are wrong or incomplete, and they change the priority ordering.

**FACT 3 is WRONG.** PAY001/PAY002/PAY009 **do** have allocations — in `po_allocations`, which the fact-gathering evidently did not query:

```
po_allocations (id, payment_id, po_id, amount, created_at):
  (1, 1, 1,  5000, 2026-08-13 19:09:50)
  (2, 2, 2,  2500, 2026-08-13 19:51:22)
  (3, 9, 3, 20000, 2026-08-20 11:29:04)
```

The 27,500 is fully allocated to PO-2026-0001/0002/0003 and each PO's `total_amount` (5000/2500/20000) is exactly matched. Nothing is "effectively unallocated". The supplier ledger reaches balance 0 on the PO/payment pairs, and the only genuine residual payable is **500** (`PURCH-2026-0029`, supplier_ledger id 22, `suppliers.current_balance = 500`) — which is correct.

**FACT 2's premise is right but the cause is different.** `payments.invoice_id` is NULL for every row not because the write path skips it (it does skip it) but *also* because a startup migration **destroyed** the column's data — see PAY-06. And the real dual-mechanism double-count risk is on the **supplier** side, not the customer side.

**FACT 9 is WRONG about wiring.** `cash_reconciliations` is empty but fully implemented and wired end-to-end: `GET/POST /reports/cash-reconciliation` → `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/lib/features/reports/cash_reconciliation_screen.dart`, registered in `lib/app.dart`. It is unused, not unbuilt.

Live GL confirms FACT 5 exactly — there is **no account 2000 (Accounts Payable) journal activity at all**, and Cash 1000 has 4,367 debit / **0.00 credit**:

```
1000 Cash                  Dr 4367.00   Cr    0.00
1100 Accounts Receivable   Dr 4187.00   Cr 4967.00
1200 Inventory Asset       Dr  500.00   Cr 3776.20
4000 Sales Revenue         Dr    0.00   Cr 4187.00
4100 Sales Returns         Dr  600.00   Cr    0.00
5000 Cost of Goods Sold    Dr 3776.20   Cr  500.00
journal_lines by reference_type: INVOICE 36, INVOICE_RETURN 4, PAYMENT 14 — nothing else.
```

---

## 1. PAYMENTS

### PAY-01 — `deleted_payments[]` on the invoice-update endpoint destroys ARBITRARY payments with no ownership check — P0

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/controllers/invoiceController.ts:436-455`

```ts
if (deleted_payments && Array.isArray(deleted_payments) && deleted_payments.length > 0) {
    for (const deletedPaymentId of deleted_payments) {
        const paymentInfo = PaymentModel.getById(db, deletedPaymentId);
        if (paymentInfo) {
            InvoiceModel.deleteLedgerEntryByReference(db, paymentInfo.payment_no);
        }
        const allocations = PaymentModel.getAllocationsByPaymentId(db, deletedPaymentId);
        PaymentModel.deleteAllocationsByPaymentId(db, deletedPaymentId);
        PaymentModel.delete(db, deletedPaymentId);
```

There is **no check that `deletedPaymentId` is allocated to `invoiceId`, or belongs to `parsedCustomerId`, or is even a customer payment**. Any authenticated user with `invoices:update` can delete any payment in the system — including supplier payments — through a sales endpoint that requires no payment permission.

Failure scenario: `PUT /api/invoices/5` with body `{..., deleted_payments:[9]}`. Payment 9 = PAY009, a 20,000 supplier payment. Result: `payments` row gone, `po_allocations` row 3 cascade-deleted (FK `ON DELETE CASCADE`, `add-supplier-payment-support.sql:15`), `supplier_ledger` id 8 deleted, supplier balance rebuilt to 20,000 owing, PO-2026-0003 flips to unpaid — all logged as an invoice edit, with no payment-permission check and no trace linking the two.

Fix: require each id in `deleted_payments` to appear in `payment_allocations WHERE invoice_id = :invoiceId`, and require `customer_id = :parsedCustomerId`; reject anything with a non-null `supplier_id`. Enforce `requirePermission('payments','delete')` on the route when the array is non-empty.
Migration: no. Historical data affected: unknown — the 26 Purchase deletes are logged but payment deletions leave no activity_log entry at all (see PAY-05), so past abuse is undetectable. **UNVERIFIED** whether it has been exploited.

### PAY-02 — `Payment.delete` never voids the GL journal lines — P0

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Payment.ts:457-463`

```ts
db.transaction(() => {
  const allocations = db.prepare('SELECT * FROM payment_allocations WHERE payment_id = ?').all(id) as Array<{ invoice_id: number }>;
  db.prepare('DELETE FROM payment_allocations WHERE payment_id = ?').run(id);
  db.prepare('DELETE FROM purchase_allocations WHERE payment_id = ?').run(id);
  db.prepare('DELETE FROM payments WHERE id = ?').run(id);
  db.prepare('DELETE FROM customer_ledger WHERE reference_no = ?').run(existing.payment_no);
  db.prepare('DELETE FROM supplier_ledger WHERE reference_no = ?').run(existing.payment_no);
```

`Payment.create` posts to the GL at `Payment.ts:246` (`AccountingService.postPaymentEntry`, `reference_type='PAYMENT'`, `reference_id=paymentId`). `delete` never calls `AccountingService.voidJournalLinesByReference(db,'PAYMENT',id)`, which exists and is used elsewhere. The journal lines survive with a `reference_id` pointing at a deleted row.

Failure scenario with live numbers: delete PAY010 (1,367, customer 1). `payments` loses 1,367; `customer_ledger` loses the credit; `invoices.paid_amount` recomputes down; AR sub-ledger says the customer owes 1,367 more. The GL still carries Dr Cash 1,367 / Cr AR 1,367. Trial balance still balances (both sides survive) so nothing screams — but Cash 1000 now overstates the till by 1,367 and AR 1100 understates the sub-ledger by 1,367 **permanently and silently**. Repeat over a year of corrections and the GL and the AR aging report diverge without bound.

Fix: inside the same transaction, `AccountingService.voidJournalLinesByReference(db, 'PAYMENT', id)` (and `'REFUND'` for negative payments). Better: replace destructive delete with a reversing payment.
Migration: yes — a one-off script to void `journal_lines` whose `reference_type='PAYMENT'` and `reference_id NOT IN (SELECT id FROM payments)`. Historical data: currently 14 PAYMENT lines totalling 4,367 Dr/4,367 Cr, all matched to live payments, so **no orphans exist today** — the exposure is prospective.

### PAY-03 — Ledger deletion by bare `reference_no`, unscoped by counterparty or transaction type — P1

`Payment.ts:462-463` (excerpt above). Deletes from **both** `customer_ledger` and `supplier_ledger` for *every* row whose `reference_no` equals the payment number, regardless of `customer_id`/`supplier_id` and regardless of `transaction_type`. Same pattern at `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Invoice.ts:891-893` (`deleteLedgerEntryByReference`).

Live payment numbers are `PAY001…PAY010` — a namespace that will never collide with `INV-…`/`PURCH-…`/`PO-…`, so today this is latent. It becomes live damage the moment a user types a `reference_no` on a manual ledger adjustment, or an import assigns a document number starting with `PAY`. Contrast with the *correct* version at `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Purchase.ts:467-470`, which scopes by all three columns.

Fix: `DELETE FROM customer_ledger WHERE customer_id = ? AND reference_no = ? AND transaction_type = 'PAYMENT'`, and the symmetric supplier version. Migration: no. Historical: none detected.

### PAY-04 — `Payment.update` silently desynchronises supplier payments three ways — P0

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Payment.ts:400-448`

```ts
if (amountChanged) {
  const newAmount = data.amount!;
  const allocations = db.prepare('SELECT id, invoice_id, amount FROM payment_allocations WHERE payment_id = ?').all(id) ...
  const ratio = newAmount / totalAllocated;
  ...
}
const allocations = db.prepare('SELECT invoice_id FROM payment_allocations WHERE payment_id = ?').all(id) ...
ledgerUtils.updateCustomerBalance(existing.customer_id);
```

`update` touches **only** `payment_allocations`. For a supplier payment there are none, so:
- `payments.amount` changes; `po_allocations.amount` / `purchase_allocations.amount` do **not**.
- `supplier_ledger` PAYMENT credit row keeps the **old** amount; `suppliers.current_balance` is never recomputed.
- No GL void/repost (there was no GL entry for supplier payments in the first place — PAY-08).
- `updateCustomerBalance(existing.customer_id)` is called with `customer_id = NULL`.

On the **customer** side it is also unsafe: allocations are rescaled with **no re-validation against `invoices.balance_amount`**, the `customer_ledger` PAYMENT credit row is never updated, and the GL PAYMENT entry is never voided/reposted.

Failure scenario: `PATCH /api/payments/9 {"amount": 5000}` on PAY009. Result: `payments.amount = 5000`, `po_allocations` still 20,000 → PO-2026-0003 reports paid 20,000 on a 5,000 payment; `supplier_ledger` credit still 20,000 and `suppliers.current_balance` still reflects it; `cashService` (which reads `payments.amount`) now shows the till 15,000 higher. Three books, three different numbers, no error raised.
Customer-side scenario: PAY010 = 1,367 allocated 1,367 to one invoice with balance 0 after payment. `PATCH {"amount": 10000}` → allocation rescaled to 10,000 on an invoice whose total was 1,367 → `paid_amount = 10000`, `balance_amount` clamped to 0 (`ledgerUtils.calculateInvoiceBalance`), 8,633 of cash vanishes into an over-paid invoice with **no** credit balance created.

Fix: reject `amount` changes on payments that have `po_allocations`/`purchase_allocations` unless new allocations are supplied; re-run the full `createSupplierPayment` validation; update the ledger credit row and rebuild balances; void + repost the GL entry. Simplest correct design: forbid amount edits — require void-and-reissue.
Migration: no. Historical: **UNVERIFIED** — no `activity_log` rows exist for payment updates, so past edits cannot be detected.

### PAY-05 — Payment create/update/delete write no `activity_log` row — P1

`Payment.ts:175-260`, `262-395`, `400-448`, `453-488` contain no `INSERT INTO activity_log`, unlike `Purchase.recordPurchase` (`Purchase.ts:252-261`) and `Purchase.delete` (`Purchase.ts:506-515`). `activity_log` shows `Purchase CREATE 37 / DELETE 26` precisely because purchases *are* logged; payments are invisible. Combined with PAY-01/PAY-02/PAY-04, money can be created, altered and destroyed with zero audit trail.
Fix: log all four operations with before/after amounts. Migration: no. Historical: irrecoverable.

### PAY-06 — A startup migration silently DROPPED `payments.invoice_id` and `payments.purchase_order_id` data — P1

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/config/database.ts:764-797`

```ts
if (notNullCheck.count > 0) {
  db.exec(`
    ... CREATE TABLE payments_new ( ... invoice_id INTEGER, ... );
    INSERT INTO payments_new (id, payment_no, customer_id, supplier_id, payment_date, amount, payment_method, reference_no, notes, created_by, created_at)
      SELECT id, payment_no, customer_id, supplier_id, payment_date, amount, payment_method, reference_no, notes, created_by, created_at FROM payments;
    DROP TABLE payments;
    ALTER TABLE payments_new RENAME TO payments;
```

The new table declares `invoice_id` but the copy list **omits it** — every pre-existing `invoice_id` became NULL. The rebuilt table also has no `purchase_order_id` column at all; it is re-added afterwards by `runPaymentsPurchaseOrderIdMigration()` (`database.ts:803-822`, called at line 1056, *after* line 1055) as an all-NULL column. Identical omission in `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/migrations/add-supplier-payment-support.sql:40`.

This is why live data shows `purchase_order_id = NULL` on PAY001/PAY002/PAY009 even though `createSupplierPayment` sets it for single-PO payments (`Payment.ts:340-343,356`) and all three *are* single-PO. It is a verified, executed data-loss event.

Fix: never omit columns in a table-rebuild copy; add a regression test that the copy list matches `pragma_table_info` of the new table. Migration: yes — backfill `payments.purchase_order_id` from `po_allocations` where a payment has exactly one PO allocation, and `payments.invoice_id` from `payment_allocations` where exactly one invoice allocation exists. Historical data affected: **yes, already lost** (3 supplier payments, all recoverable from `po_allocations`).

### PAY-07 — `getAPSummary` and `getAPAgingReport` reference columns that do not exist — both AP reports are dead — P1

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Reports.ts:479-497` and `505-520`

```sql
-- getAPAgingReport (line 479)
SUM(po.balance_amount) as total_outstanding, ... julianday(po.due_date) ...
FROM purchase_orders po ... WHERE po.status IN ('Approved','Received','Partial') AND po.balance_amount > 0

-- getAPSummary (line 507)
SELECT s.supplier_name, SUM(po.total_cost - COALESCE(p.paid_amount, 0)) as outstanding
FROM purchase_orders po JOIN suppliers s ON po.supplier_id = s.id
LEFT JOIN (SELECT purchase_order_id, SUM(amount) as paid_amount FROM payments GROUP BY purchase_order_id) p
  ON po.id = p.purchase_order_id
WHERE po.status IN ('Approved','Received') GROUP BY s.supplier_name
```

`purchase_orders` actually has: `id, po_no, supplier_id, po_date, expected_delivery_date, status, total_amount, notes, warehouse_id, created_by, created_at, updated_at`. There is **no `balance_amount`, no `due_date`, no `total_cost`**, and no `ALTER TABLE purchase_orders` anywhere in `server/src`. Verified against the live DB:

```
AP-AGING SQL FAILS: no such column: balance_amount
AP-SUMMARY SQL FAILS: no such column: total_cost
```

`GET /reports/ap-aging` (`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/routes/reports.ts:13`) is wired to a live Flutter screen (`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/lib/features/reports/ap_aging_report_screen.dart`) and **500s on every call**. There is therefore no working accounts-payable aging in the product.

Three further defects in the same code, all of which would still be wrong after the column names are fixed:
1. `status IN ('Approved','Received','Partial')` — `PurchaseOrderModel.validTransitions` only ever produces `Draft / Submitted / Partially Received / Completed / Cancelled`. **None of the three filtered statuses is reachable**, so the report would return empty even with valid columns. Live POs are all `Completed`.
2. It aggregates payments from `payments.purchase_order_id` while every other read uses `po_allocations` — the FACT-2 dual-mechanism problem, on the supplier side. Because PAY-06 nulled that column, all three POs would report `paid_amount = 0` and appear 27,500 outstanding when they are fully paid.
3. AP is computed from purchase **orders** only — the `purchases` table (the model that actually holds the live 500 payable) is not included at all.

Fix: rewrite both against `supplier_ledger` (the only source that already reconciles), or against `total_amount − (SELECT SUM(amount) FROM po_allocations WHERE po_id = po.id)` with a reachable status filter and a UNION over `purchases`. Add an integration test that executes every report SQL against a fresh schema.
Migration: no. Historical: no data corrupted; the feature has simply never worked.

### PAY-08 — Supplier payments post nothing to the GL; AP account 2000 has zero lifetime activity — P0

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Payment.ts:262-395` — the whole method, ending at line 391 with `UPDATE suppliers SET current_balance`. There is no `AccountingService` import call anywhere in it, in contrast to `Payment.create:246`.

Combined with PUR-01 (purchases post nothing) and PUR-04 (goods receipts post nothing), the general ledger has **never recorded a single credit to Cash and never touched Accounts Payable**. Live GL: `1000 Cash Dr 4367 / Cr 0`; account `2000` absent from the aggregate entirely.

Failure scenario: books show cash of 5,000 opening + 4,367 receipts = 9,367 in the GL, while 27,600 has actually left the till (27,500 supplier payments + 100 expense). A balance sheet or trial balance drawn from `journal_lines` overstates cash by 27,600 and omits the inventory/COGS effect of purchases. `cashService` gets the right answer only because it bypasses the GL (`cashService.ts:10-15` documents this deliberately) — which means the GL and the dashboard permanently disagree and the GL is the wrong one.

Fix: post `Dr 2000 Accounts Payable / Cr 1000-1040 <cash account>` in `createSupplierPayment`, with `reference_type='SUPPLIER_PAYMENT'`, inside the existing transaction; void on delete.
Migration: yes — backfill journal entries for the 3 historical supplier payments (27,500) and for `PURCH-2026-0029` (500), in an open accounting period. Historical data affected: yes, the entire GL is incomplete.

### PAY-09 — The create-payment guard admits both counterparties and then silently discards the supplier — P2

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/controllers/paymentsController.ts:67-68`

```ts
if ((!customer_id && !supplier_id) || !payment_date || !amount || amount <= 0) {
  res.status(400).json({ success:false, error:'Customer ID or Supplier ID, payment date, and amount are required' });
```

`||` not XOR. With both ids supplied the customer branch (lines 74-135) runs and returns, so `supplier_id` is dropped without warning — no error, no log. This is the application-level counterpart of FACT 1 (no CHECK constraint in `add-supplier-payment-support.sql:22-38`).
Fix: `if (!!customer_id === !!supplier_id) return 400`. Add the DB constraint `CHECK ((customer_id IS NULL) <> (supplier_id IS NULL))`.
Migration: yes for the CHECK (table rebuild — and see PAY-06 for how to not lose columns doing it). Historical: live data is clean, every row has exactly one counterparty.

### PAY-10 — `POST /payments/:id/allocate` returns 501; unallocated remainders are impossible by construction but also unrepresentable — P2

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/controllers/paymentsController.ts:344-346` returns `501 Not Implemented`. Consequently a payment can only ever be created fully allocated, enforced at lines 118-120:

```ts
const totalAllocated = invoice_allocations.reduce((sum, alloc) => sum + parseCurrency(alloc.amount), 0);
if (Math.abs(totalAllocated - parsedAmount) > 0.01) {
  res.status(400).json({ success:false, error:`Payment amount (...) does not match total allocated amount (...)` });
```

This is a *good* guard, but it means **a customer who pays more than they owe cannot be recorded at all** through `/api/payments` — the payment is rejected. The only route to an on-account balance is the invoice-return path (`invoiceController.ts:1071-1079`, disposition `'credit'`), which writes `customers.credit_balance`.

`customers.credit_balance` is **write-only**: it is set by the return path and by the `'adjust'` disposition (`invoiceController.ts:1167-1175`), but `ledgerUtils.updateCustomerBalance` (`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/utils/ledgerUtils.ts:44-58`) sums only `invoices.balance_amount` for `Unpaid/Partially Paid/Overdue` and never subtracts it, and no payment-creation code reads it. Live: customer 1 (`Walkin Customer`) holds `credit_balance = 600` that nothing in the system can spend.

Fix: implement the allocate endpoint; carry the unallocated remainder to `credit_balance` with a matching `customer_ledger` row and GL `Dr Cash / Cr Customer Advances (liability)`; make `updateCustomerBalance` net it off; offer it as a tender on new invoices.
Migration: no. Historical: 600 of customer credit is stranded — real money owed to a customer that the software cannot return.

### PAY-11 — Receipt "previous balance" is computed by arithmetic that is wrong for anything but the newest payment — P3

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/controllers/paymentsController.ts:251` and `:277`

```ts
previousBalance = parseCurrency(currentBalance + parseCurrency(payment.amount));
```

`currentBalance` is the counterparty's balance *now*, so reprinting an old receipt shows a "previous balance" polluted by every invoice and payment since. For suppliers the sign convention is also inverted relative to the customer case. Fix: read the `balance` column of the payment's own ledger row and add back its credit. Migration: no.

### What is CORRECT in payments — do not change

- The **customer** allocation guards are sound: per-invoice over-payment is blocked at `paymentsController.ts:109-115` (`alloc.amount > invoice.balance_amount`), and total-vs-amount equality at `118-120`.
- The **supplier** per-document over-allocation guards are sound and use the *authoritative* allocation tables: `Payment.ts:284-307` (PO: `total_amount − SUM(po_allocations.amount)`) and `309-332` (purchase: `total_cost − SUM(purchase_allocations.amount)`), plus a counterparty-ownership check at `295-297` and `320-322`.
- **FACT 2's feared double-count does not exist on the customer side.** Every read of invoice payment derives from `payment_allocations` alone: `ledgerUtils.calculateInvoiceBalance` (`ledgerUtils.ts:60-86`), `Invoice.getTotalPaid` (`Invoice.ts:819-826`), `Payment.getTotalPaidByInvoiceId` (`Payment.ts:523-530`). `payments.invoice_id` is read only for display joins in `Payment.getById`/`getAll`. No query sums both. **Do not "fix" this by re-populating `invoice_id` into the balance calculations.**
- `Payment.delete` **does** correctly rebuild the supplier running-balance chain (`Payment.ts:465-469`) and the customer chain (`480-486`), and correctly recomputes affected invoice balances from the pre-delete allocation snapshot taken at line 458.
- `po_allocations` and `purchase_allocations` cascade correctly on payment delete (`ON DELETE CASCADE`, `add-supplier-payment-support.sql:15`), with `foreign_keys = ON` set at `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/config/database.ts:24`.
- Every payment write is inside `db.transaction(...)` (`Payment.ts:176, 263, 406, 457`).

---

## 2. PURCHASES

### PUR-01 — Purchases post nothing to the general ledger — P0

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Purchase.ts:101-267`. `recordPurchase` writes `purchases`, `stock_batches`, `stock_movements`, `stock_balances`, `items.current_stock`, `supplier_ledger` (lines 239-250) and `activity_log` — and never calls `AccountingService`. No `Dr 1200 Inventory / Cr 2000 Accounts Payable`.

Live proof: `1200 Inventory Asset Dr 500.00` total. That single 500 debit is not from a purchase — `PURCH-2026-0029` is also 500, but the only `reference_type` values in `journal_lines` are `INVOICE`, `INVOICE_RETURN`, `PAYMENT`. Inventory has been credited 3,776.20 by sales COGS against a 500 debit that came from a return, so **account 1200 carries a negative balance of −3,276.20 while the warehouse holds real stock**. A balance sheet from this GL is unusable.

Fix: post `Dr 1200 Inventory (total_cost) / Cr 2000 Accounts Payable` with `reference_type='PURCHASE'`, `reference_id=purchaseId`, inside the existing transaction at `Purchase.ts:239`; void it in `delete`.
Migration: yes — backfill for surviving purchases and reverse for the 26 deleted ones (their data is gone; only `activity_log` descriptions remain). Historical: yes, GL inventory and AP are both wrong from inception.

### PUR-02 — `stock_batches.source_type='PURCHASE'` is a shared namespace between direct purchases and goods receipts; the lookup is ambiguous — P0

Two writers use the same `(source_type, source_id)` namespace with **different id spaces**:

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Purchase.ts:154-176`
```ts
INSERT INTO stock_batches (... source_type, source_id ...) VALUES (?, ?, ?, 'PURCHASE', ?, ...)   -- source_id = purchases.id
...
const batchRecord = db.prepare(`
  SELECT id FROM stock_batches
  WHERE source_type = 'PURCHASE' AND source_id = ?
`).get(purchaseId);          //  <-- no LIMIT, no ORDER BY, no batch_no filter
```

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/PurchaseOrder.ts:771-788` inserts with `source_type='PURCHASE'` and `source_id = goods_receipt_items.id`.

Live database — the collision is **already materialised**:
```
stock_batches WHERE source_type='PURCHASE':
 id 1  BATCH-26-PUR-0001    source_id=1   (from purchases.id=1,  now hard-deleted)
 id 2  BATCH-26-PUR-0002    source_id=2   (from purchases.id=2,  now hard-deleted)
 id 5  BATCH-26-RECON-0001  source_id=0   (reconciliation batch, source_id 0)
 id 18 BATCH-26-PUR-0017    source_id=3   <-- created by GOODS RECEIPT GR-2026-0003
 id 32 BATCH-26-PUR-0030    source_id=29  (purchases.id=29, the only live purchase)
```
Batch 18 is provably a goods-receipt batch: `stock_movements` id 35 = `STK-2026-0035`, `reference_doctype='GOODS_RECEIPT'`, `reference_docno='GR-2026-0003'`, `batch_id=18`. It nevertheless claims `source_type='PURCHASE', source_id=3`. It currently holds `quantity_remaining = 38.722`.

`sqlite_sequence`: `purchases = 37`, `goods_receipt_items = 3`. AUTOINCREMENT means the next purchase gets id 38 and the next GR item gets id 4. The id spaces are on a collision course: as soon as `goods_receipt_items` reaches 38+, or a purchase is created while a GR item shares its id, `.get(purchaseId)` at line 175 returns whichever row has the lower rowid — **the wrong batch**.

Failure scenario: a new goods receipt creates `goods_receipt_items.id = 38` → batch B with `source_id=38`. A new direct purchase then gets `purchases.id = 38` and inserts batch C, also `source_id=38`. Line 172-176 returns **B** (lower rowid). Then: `purchases.batch_id` points at B (`Purchase.ts:202-204`), the purchase's `stock_movements.batch_id` points at B, and FIFO costing will consume B at the GR's unit cost, not the purchase's. Worse, `Purchase.delete(38)` (`Purchase.ts:475-501`) looks up the same ambiguous row, issues an `ADJUSTMENT` for **B's** `quantity_remaining` and sets **B's** `quantity_remaining = 0` — writing off the goods receipt's stock while leaving the purchase's own batch C intact and orphaned. With the live batch 18 that is 38.722 units of real inventory destroyed by deleting an unrelated purchase.

Fix: give goods receipts their own `source_type` (`'GOODS_RECEIPT'`), or use `result.lastInsertRowid` from the insert at line 154-170 instead of re-querying (the re-query is pointless — the id is already available). Add `UNIQUE(source_type, source_id)` once the namespaces are separated.
Migration: yes — relabel batch 18 (and any other batch whose `stock_movements.reference_doctype='GOODS_RECEIPT'`) to `source_type='GOODS_RECEIPT'` with `source_id` = its `goods_receipt_items.id`; clean up the orphaned batches 1, 2 and the `source_id=0` reconciliation batch. Historical data affected: yes, 3 mislabelled/orphaned batch rows exist today.

### PUR-03 — Purchases are hard-deleted with no guard for consumed stock, returns, or closed periods — P0

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Purchase.ts:444-521`. The only guard is:

```ts
const paymentAlloc = db.prepare('SELECT id FROM purchase_allocations WHERE purchase_id = ? LIMIT 1').get(id);
if (paymentAlloc) throw new Error('Cannot delete purchase with recorded payments — delete the payments first');
```

Missing guards: (a) `purchase_returns` against this purchase, (b) `purchases.returned_quantity > 0`, (c) stock already sold — the code explicitly handles the sold case *incorrectly* by only reversing `quantity_remaining`:

```ts
if (batch && batch.quantity_remaining > 0) {
  StockMovementModel.recordMovement({ ..., quantity: -batch.quantity_remaining, reference_doctype: 'PURCHASE_DELETE', ... });
  db.prepare('UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?').run(batch.id);
}
```

(d) no accounting-period check, (e) no GL void (there is nothing to void — PUR-01), (f) the "delete the payments first" instruction routes users straight into PAY-02.

Failure scenario with live shapes: purchase of 50 units @ 10 = 500, 45 sold at 20 (COGS 450 recognised from that batch). Delete the purchase. `quantity_remaining` is 5, so an ADJUSTMENT of −5 is posted and the batch is zeroed. The `purchases` row vanishes. Net effect: 450 of COGS in the GL now references a batch whose source purchase does not exist; `supplier_ledger` is correctly reversed (−500) so the supplier is no longer owed; and the business has recognised 450 of cost against goods it no longer has any record of buying. Gross margin on those sales is unauditable. `activity_log` records only `Deleted purchase PURCH-…`, not the quantities.

Live: `sqlite_sequence.purchases = 37` with **1 surviving row** — 36 purchases have been hard-deleted (FACT 11 says 26 DELETE entries in `activity_log`, so ~10 were deleted before logging existed or through another path). Batches 1 and 2 are the visible orphan residue.
Fix: soft delete (`voided_at`, `voided_by`, `void_reason`); block when `returned_quantity > 0`, when any `purchase_returns.source_id = id`, or when `quantity_remaining < quantity_original`; require an open period; void the GL entry.
Migration: yes for the soft-delete columns. Historical: 36 purchases irrecoverable; the GL, inventory valuation and supplier history for that period cannot be reconstructed.

### PUR-04 — Goods receipts move stock but touch neither the supplier ledger nor the GL; PO status and PO GL posting are asymmetric — P1

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/PurchaseOrder.ts:684-888` (`addReceipt`) writes `goods_receipts`, `goods_receipt_items`, `stock_batches`, `stock_movements`, `stock_balances`, `items.current_stock` and recalculates PO status — **no `supplier_ledger`, no `AccountingService`**. Goods arrive and inventory rises with no payable and no journal entry.

The payable is instead created at PO **submit** time (`PurchaseOrder.ts:170-191`), which is FACT 4's defect: a purchase order is a commitment, not a payable, and `transaction_type='PURCHASE_ORDER'` debits the supplier before any goods exist. Live `supplier_ledger` shows exactly this, including the ordering anomaly:

```
id 8  2026-08-20  PAYMENT         PAY001... PAY009   credit 20000  balance -20000   'Payment against PO-2026-0003'
id 9  2026-08-20  PURCHASE_ORDER  PO-2026-0003       debit  20000  balance      0   'Purchase Order PO-2026-0003'
```
The supplier was in a −20,000 (prepaid) position mid-chain because the payment row was written before the PO's debit. `rebuildBalances` orders by `id ASC` (`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/SupplierLedger.ts:84-100`), not by `transaction_date` then `id`, so this stays visible forever in the statement.

Additionally the GL/ledger posting is asymmetric between the two ways a PO reaches `Submitted`: `create` posts **both** the `supplier_ledger` debit and `AccountingService.postPurchaseOrderEntry` (`PurchaseOrder.ts:170-191`), whereas `updateStatus` on `Draft → Submitted` (`PurchaseOrder.ts:585-595`) posts **only** the `supplier_ledger` entry. A PO saved as Draft then submitted therefore has a sub-ledger payable with no journal entry — permanently out of balance with a PO created directly as Submitted.

Fix: move the payable recognition from PO-submit to goods-receipt (`Dr 1200 Inventory / Cr 2000 AP` per receipt line, `reference_type='GOODS_RECEIPT'`), and drop `PURCHASE_ORDER` from `supplier_ledger` entirely (or move it to a memo/commitment table). Until then, at minimum make `updateStatus` post the same GL entry as `create`.
Migration: yes — reclassify the 3 historical `PURCHASE_ORDER` ledger rows. Historical: the live ledger nets to the right total by luck (each PO is fully received and fully paid), but the timeline is wrong.

### PUR-05 — Two purchasing models, neither authoritative, no cross-check — P1

`purchases` (one row per item, `supplier_name TEXT` denormalised beside `supplier_id`) versus `purchase_orders → purchase_order_items → goods_receipts → goods_receipt_items`. Both increase stock, both create `stock_batches` under the same `source_type` (PUR-02), and both feed the supplier balance — but through different `transaction_type` values (`'PURCHASE'` vs `'PURCHASE_ORDER'`), different allocation tables (`purchase_allocations` vs `po_allocations`) and different code paths with different completeness.

Nothing prevents recording the same delivery twice — once as a goods receipt against the PO and once as a direct purchase. There is no link column from `purchases` to `purchase_order_items`, no supplier-invoice-number uniqueness (`purchases.invoice_no` has no UNIQUE constraint), and no reconciliation report. The payable is then double-counted: the PO submit debit (PUR-04) plus the direct-purchase debit (`Purchase.ts:239-250`) for the same goods.

Failure scenario: PO-2026-0004 for 100 units @ 50 is submitted → supplier debited 5,000. Goods arrive; the storekeeper records a direct purchase of 100 @ 50 → supplier debited another 5,000 and stock rises 100. Someone also posts the goods receipt → stock rises another 100. Result: supplier owed 10,000 instead of 5,000, and 200 units in stock instead of 100, with 5,000 of phantom inventory value. Nothing in the code detects it.

Fix: pick one. Recommended — make `purchase_orders`/`goods_receipts` authoritative and reduce `purchases` to a view over goods receipts (or a "quick purchase" that auto-creates a one-line PO + receipt). Add `UNIQUE(supplier_id, invoice_no)` and a `purchases.goods_receipt_item_id` link. Add a duplicate-delivery warning on matching supplier + invoice_no + amount.
Migration: yes, substantial. Historical: only 1 purchase and 3 POs live, so the cleanup is cheap **now** and gets exponentially harder later.

### PUR-06 — `purchases.supplier_name` denormalised beside `supplier_id`, and `getTopSuppliers` groups by the text — P2

`Purchase.ts:110-121` resolves the name from `suppliers` when `supplier_id` is present (good), but the column is still stored and `Purchase.getTopSuppliers` (`Purchase.ts:429-441`) groups by `supplier_name`, and `getAll` filters on `p.supplier_name LIKE ?` (`Purchase.ts:317-319`). Renaming a supplier splits their history across two names in the report; purchases entered with only free text never merge with the linked ones.
Fix: `GROUP BY supplier_id` with a `LEFT JOIN suppliers`; keep `supplier_name` only as a fallback for legacy rows. Migration: backfill `supplier_id` by name match, then make it NOT NULL. Historical: 1 row, already linked.

### What is CORRECT in purchases — do not change

- `Purchase.getAll` / `getById` derive `paid_amount` and `balance_amount` from `purchase_allocations` alone (`Purchase.ts:282-291`, `367-376`) — single source of truth, no double-count. This is the pattern PAY-07 should copy.
- `Purchase.delete`'s supplier-ledger reversal is correctly scoped by all three of `supplier_id`, `reference_no` and `transaction_type` (`Purchase.ts:467-470`) and rebuilds the balance chain (line 471). This is the correct pattern; `Payment.delete` should adopt it.
- `recordPurchase` validates all inputs before opening the transaction (`Purchase.ts:102-106`) and resolves `supplier_id` → canonical name with a hard failure on a bad id (line 119).
- The whole of `recordPurchase` and `delete` is inside `db.transaction` (lines 123, 451).
- Sort parameters are whitelisted through `sanitizeSortParams` + `PURCHASE_SORT_COLUMN_MAP` (`Purchase.ts:57-70`, `332-339`) — no SQL injection via `sortBy`.
- The delete guard on `purchase_allocations` (lines 455-462) is correct as far as it goes.

---

## 3. PURCHASE RETURNS (0 rows — never executed against real data)

### PRET-01 — Duplicate lines for the same source item bypass the returnable-quantity check — P0

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/PurchaseReturn.ts` — validation reads `returned_quantity` in a first loop (lines 255-331):

```ts
const returned = purchase.returned_quantity || 0;      // line 275   (direct purchase)
const returned = poItem.returned_quantity || 0;        // line 310   (PO line)
```

and the counter is only incremented in a **second, later** loop (lines 378-385):

```ts
db.prepare(`UPDATE purchases SET returned_quantity = COALESCE(returned_quantity,0) + ? WHERE id = ?`)   // 380
db.prepare(`UPDATE purchase_order_items SET returned_quantity = COALESCE(returned_quantity,0) + ? WHERE id = ?`) // 383
```

Every line in one request therefore validates against the **same pre-request** `returned_quantity`. Two lines referencing the same `source_item_id` each pass independently.

Failure scenario: purchase of 50 units @ 10, nothing returned. POST a return with two lines, each `source_item_id = <that purchase>`, quantity 50, unit_cost 10. Both validate (50 ≤ 50 − 0). Result: `returned_quantity = 100` on a 50-unit purchase, 100 units decremented from `stock_batches` (driving `quantity_remaining` negative — see PRET-02), a 1,000 credit note against a 500 purchase, and a 1,000 credit to the supplier who was only owed 500. The supplier now shows a 500 prepayment that does not exist.
Fix: aggregate the request lines by `source_item_id` before validating, and validate the aggregate; add `CHECK (returned_quantity <= quantity)` on `purchases` and on `purchase_order_items`; re-read `returned_quantity` with the update (`UPDATE ... WHERE id = ? AND returned_quantity + ? <= quantity` and assert `changes === 1`).
Migration: yes for the CHECK constraints. Historical: none — 0 rows.

### PRET-02 — Return consumes FIFO-oldest batches instead of the batch the goods came from, and can drive stock negative — P0

`PurchaseReturn.ts:408-420`

```ts
SELECT id, quantity_remaining
FROM stock_batches
WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
ORDER BY ...
...
const consume = Math.min(toReturn, batch.quantity_remaining);
db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?`)
```

Two defects. First, the goods being returned belong to a **specific** batch — the one created by the source purchase/receipt, whose `unit_cost` is the cost being credited. Consuming oldest-first means the return can be valued at cost A while depleting batch B bought at cost B, silently mis-stating inventory value by the cost difference. Second, `Math.min` caps each batch but there is no check that the batches in total can satisfy `toReturn`: if the goods have already been sold, the loop exhausts all available batches and **silently returns fewer units than the return document claims**, leaving `returned_quantity`, the credit note and the supplier ledger all recorded at the full quantity while the stock reduction is short.

Failure scenario: purchase 50 @ 10 (batch X, cost 10). 45 are sold. An earlier batch Y of the same item holds 40 @ 6. Return 50 to the supplier. The loop consumes Y (40 @ 6) then X (5 @ 10 wait — X has 5) = 45 units total; 5 units are never found. Recorded: `returned_quantity = 50`, credit note 500, supplier credited 500, stock reduced by 45 units of which 40 were the *wrong*, cheaper batch. Inventory value falls by 40×6 + 5×10 = 290 while the GL entry (`postPurchaseReturnEntry`, `Dr AP / Cr Inventory`, line 438) credits Inventory 500. Inventory sub-ledger and GL diverge by 210, and 40 units of cheap stock have been destroyed to satisfy a return of expensive stock.
Fix: return against the source document's own batch (`stock_batches WHERE source_type/source_id` matching the source purchase or receipt item); throw if `quantity_remaining < toReturn`; never silently under-consume.
Migration: no. Historical: none — 0 rows.

### PRET-03 — Credit note resolves the supplier by NAME and skips the ledger entry on a miss — P0

`PurchaseReturn.ts:604-658`

```ts
SELECT id FROM suppliers WHERE supplier_name = ? COLLATE NOCASE LIMIT 1     // line 624
...
SupplierLedgerModel.createEntry({ ... });                                    // line 640
...
logger.warn(`[PurchaseReturn] Credit note ${creditNo} posted without supplier ledger entry (unresolved supplier: ${name ?? 'none'})`);  // line 654
```

For a return against a **direct purchase** the supplier is looked up from `purchases.supplier_name` — the denormalised text — even though `purchases.supplier_id` exists and is populated (live row 29 has `supplier_id = 1`). Three consequences: `LIMIT 1` silently picks an arbitrary supplier when names duplicate; a renamed supplier resolves to nothing; and on a miss the code **creates the credit note anyway** and only logs a warning. The credit note exists, the supplier is never credited, and the operator sees a success response.

Failure scenario: return 500 against `PURCH-2026-0029` (supplier "Demo supplier"). An admin has meanwhile renamed the supplier to "Demo Supplier Pvt Ltd". Lookup misses. `credit_notes` gets a 500 row; `supplier_ledger` gets nothing; `suppliers.current_balance` stays at 500. The business pays the full 500 for goods it returned, and the only record of the discrepancy is a log line.
Fix: use `purchases.supplier_id` (and `purchase_orders.supplier_id`); if it cannot be resolved, **throw and roll back** — never post a half credit note.
Migration: no. Historical: none — 0 rows.

### PRET-04 — Supplier balance left stale: `createEntry` without `rebuildBalances` — P1

`PurchaseReturn.ts:640` and `:541` call `SupplierLedgerModel.createEntry` but never `rebuildBalances`. `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/SupplierLedger.ts:27-55` (`createEntry`) does **not** touch `suppliers.current_balance`; only `rebuildBalances` does, at line 98:

```ts
db.prepare('UPDATE suppliers SET current_balance = ? WHERE id = ?').run(running, supplierId);
```

Every other caller pairs them (`Purchase.ts:240-249`, `Purchase.ts:471`). Purchase returns and voids do not, so `suppliers.current_balance` — the number shown on the supplier list and used by `Payment.createSupplierPayment` via `SupplierLedgerModel.getBalance` for the new ledger `balance` (`Payment.ts:371-372`) — silently drifts.

Failure scenario: return 500 against purchase 29. `supplier_ledger` gets a 500 credit (running balance 0), `suppliers.current_balance` stays 500. The supplier list shows 500 owing forever. If a 500 payment is then made, `getBalance` reads the ledger correctly, so the ledger reaches −500 while the header says 0 — and the business pays for returned goods.
Fix: call `SupplierLedgerModel.rebuildBalances(supplierId, db)` after every `createEntry`, or move the `UPDATE suppliers` into `createEntry`. Migration: no. Historical: none — 0 rows.

### PRET-05 — Void restores stock to the newest batch, not the batch it was taken from — P2

`PurchaseReturn.ts:513-521` adds `quantity_remaining` back to a batch chosen by the void logic rather than the one(s) the return consumed (there is no per-line record of which batches were depleted). Combined with PRET-02's FIFO consumption, create-then-void is **not** an identity operation: units can migrate between batches at different unit costs, permanently changing inventory valuation.
Fix: persist the batch consumption per return line (a `purchase_return_batches` table) and reverse it exactly. Migration: yes (new table). Historical: none.

### PRET-06 — No guard for returning goods already paid for; refund vs credit is not modelled — P1

Nothing in `PurchaseReturn.create` (lines 234-470) consults `purchase_allocations` / `po_allocations`. Returning goods already paid for produces a credit that drives the supplier balance **negative** (a receivable from the supplier) with no refund mechanism, no `refund_due` flag, and no way to record cash coming back. `cashService` cannot represent it either: negative supplier payments are filtered out at `cashService.ts:96` (`AND amount > 0`) and at `:267` (`if (amount > 0)`), so a supplier refund would be invisible to the till.

Failure scenario: PO-2026-0003, 20,000, paid in full by PAY009. Return the whole delivery. `supplier_ledger` reaches −20,000. There is no `credit_notes.status`, no refund workflow, and no cash inflow path. 20,000 of the company's money is owed by the supplier with no tracking.
Fix: block returns exceeding `total − paid` unless a disposition (`credit_on_account` | `refund_expected`) is supplied; model the refund as a negative supplier payment and remove the `amount > 0` filters in `cashService`.
Migration: yes (`credit_notes.status`, `refund_expected`). Historical: none.

### What is CORRECT in purchase returns — do not change

- `create` and `voidReturn` are each fully wrapped in `db.transaction` (`PurchaseReturn.ts:240`, `481`) — atomicity is right.
- Returns are **voided, not deleted** (`voidReturn`, lines 476-560), with a required reason. This is the correct immutable pattern and is exactly what payments and purchases should adopt.
- `voidReturn` correctly clamps the counter restoration with `MAX(0, ...)` (lines 487, 490).
- The GL posting exists and has the right shape: `AccountingService.postPurchaseReturnEntry` → `Dr 2000 AP / Cr 1200 Inventory` (line 438). Purchase returns are, ironically, the only purchase-side flow that touches the GL at all.
- Returnable quantity is derived from the source document, not stored on the return (`purchases.quantity - returned_quantity`, `purchase_order_items.received_quantity - returned_quantity`) — the right basis; only the read/write ordering (PRET-01) is wrong.

---

## 4. EXPENSES

### EXP-01 — Expenses post nothing to the GL; Operating Expenses has zero activity — P0

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Expense.ts:62-74`

```ts
function create(db: Database.Database, data: CreateExpenseDTO): number {
  const result = db.prepare(`
    INSERT INTO expenses ( expense_no, expense_category, description, amount, expense_date,
      payment_method, reference_no, vendor_name, project, status, created_by ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run( ... );
  return result.lastInsertRowid as number;
}
```

A bare INSERT: **no GL posting, no transaction wrapper, no cash entry, no supplier linkage.** Live GL has no expense account activity whatsoever (only 1000, 1100, 1200, 4000, 4100, 5000 appear). `getProfitLossReport` computes `net_profit = gross_profit − expenses` by summing the `expenses` table directly, so the P&L and the GL tell different stories about the same 100.

Fix: `Dr 6xxx <category account> / Cr 1000-1040 <cash>` for cash-settled expenses; `Dr 6xxx / Cr 2000 AP` for `payment_method='Credit'`. Wrap in a transaction. Post on the transition to `Approved`/`Paid`, void on cancel.
Migration: yes — map `expense_categories` to `chart_of_accounts` rows (the COA currently has no operating-expense accounts beyond `6100 Wages`; new accounts are needed) and backfill the 1 live expense (100, Meals, Cash, Approved). Historical: 1 row.

### EXP-02 — `payment_method='Credit'` creates no liability — P1

The schema advertises it (`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/migrations/add-expenses-table.sql:12`, `-- Cash, Check, Bank Transfer, Card, Credit`), and `cashService.normalizeCashMethod` correctly returns `null` for it (`cashService.ts:49`) so it does not drain the till. But nothing creates the corresponding payable: no `supplier_ledger` row, no `Cr 2000 AP`, no `vendor_name → suppliers.id` link (`vendor_name` is free text, `add-expenses-table.sql:14`).

Failure scenario: 50,000 of rent booked on Credit. Till unaffected (correct), P&L shows the 50,000 (via `getProfitLossReport`), and the company's payables show **nothing**. The landlord is owed 50,000 that appears in no aging report, no supplier balance, and no GL. It will be discovered when the landlord calls.
Fix: add `expenses.supplier_id` (nullable FK); when `payment_method='Credit'`, require it and post a `supplier_ledger` debit + `Cr 2000 AP`; settle it through the existing supplier-payment flow.
Migration: yes (`ALTER TABLE expenses ADD COLUMN supplier_id INTEGER REFERENCES suppliers(id)`). Historical: the 1 live expense is Cash, so nothing is currently hidden.

### EXP-03 — Status is a free string defaulting to 'Approved'; no transition rules, no immutability — P1

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/controllers/expenseController.ts:29`

```ts
expense_date, payment_method, reference_no, vendor_name, project, status: status || 'Approved', created_by: userId,
```

The client supplies `status` and it is written verbatim — no enum check against `Draft/Submitted/Approved/Paid/Cancelled`, and the default **skips the entire approval workflow**. `Expense.update` (`Expense.ts:134-155`) then allows any status to change to any other, including `Paid → Draft`, at any time, with the amount editable:

```ts
data.status || existing.status,
```

Since `cashService` includes expenses `WHERE status NOT IN ('Cancelled','Draft')` (`cashService.ts:107`), flipping an approved expense to `Draft` makes cash silently reappear in the till, and flipping it back makes it vanish — both without an audit record (`logCRUD` records the event but not the before/after status).

Failure scenario: a 50,000 expense is Approved and paid. A user edits it to `Draft`. Expected cash jumps by 50,000; the end-of-day count is 50,000 short; the reconciliation report shows an unexplained 50,000 variance. Edit it back and the variance moves to a different day.
Fix: whitelist the five statuses; default new expenses to `Draft` (or `Submitted`); enforce a transition matrix; make `Approved`/`Paid` expenses immutable except through a documented reversal; require `expenses:approve` permission for the transition into `Approved`.
Migration: no (add a CHECK constraint if desired). Historical: the 1 live row is `Approved` — created with no approval.

### EXP-04 — `expense_category` is unvalidated free text despite an `expense_categories` table — P2

`expenseController.ts:15` checks only that it is truthy. `expense_categories` exists with 15 seeded rows (`add-expenses-table.sql:23-48`) and full CRUD (`expenseController.ts:189-238`), but `expenses.expense_category` is a `VARCHAR(100)` with no FK. `Expense.getAll` filters with `AND e.expense_category = ?` (`Expense.ts:89`) — exact match — so a typo ("Utilites") creates a category that is invisible to every filter and to any category-based report.
Fix: `expenses.expense_category_id INTEGER REFERENCES expense_categories(id)`, or validate against the table on write. Migration: yes if normalising. Historical: 1 row, category 'Meals', which is valid.

### EXP-05 — `expense_no` generation is non-atomic and reuses numbers after deletion — P2

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Expense.ts:46-60`

```ts
const lastExpense = db.prepare(`
  SELECT expense_no FROM expenses WHERE expense_no LIKE ? ORDER BY expense_no DESC LIMIT 1
`).get(`EXP-${year}${month}-%`);
if (lastExpense) {
  const lastNum = parseInt(lastExpense.expense_no.split('-')[2]);
  return `EXP-${year}${month}-${String(lastNum + 1).padStart(4, '0')}`;
}
```

A read-modify-write over `MAX(expense_no)`, called from `expenseController.createExpense` **outside any transaction** and not using `utils/sequence.ts`. Two consequences: (a) concurrent creates both read the same max and the second fails on `expense_no UNIQUE` with a 500; (b) `deleteExpense` (`Expense.ts:157-161`) hard-deletes, so deleting the highest-numbered expense of a month causes the **next** expense to reuse that number — two different documents, one number, one of them only in a paper file.
Fix: use `getNextSequenceNumber(db, 'EXP_last_no_YYYYMM')` inside a transaction spanning the INSERT; soft-delete instead of hard-delete.
Migration: yes — seed the `settings` counters from existing max per month. Historical: 1 row.

### What is CORRECT in expenses — do not change

- `cashService.normalizeCashMethod` correctly excludes `'Credit'` from cash movement (`cashService.ts:49`) — that is the right call and must survive the EXP-02 fix.
- Excluding `Draft` and `Cancelled` from cash flows (`cashService.ts:107`, `:277`) is the right filter set.
- `Expense.update` correctly distinguishes "not supplied" from "zero" for the amount: `data.amount !== undefined ? data.amount : existing.amount` (`Expense.ts:146`), unlike the `||` fallbacks on the neighbouring fields.
- `logCRUD(ActionType.EXPENSE_CREATE, ...)` (`expenseController.ts:32`) — expenses are at least audit-logged, which payments are not.
- Expense list/count filters are parameterised throughout (`Expense.ts:89-98`, `110-119`) — no injection.

---

## 5. CASH / TILL RECONCILIATION

The cash model as actually implemented, `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/services/cashService.ts:60-133` (`collectFlows`), mirrored for the drill-down at `:218-309`:

| Component | Included? | Where |
|---|---|---|
| Opening balance (per account) | YES | `:64-68` (seeded into `inflow`) |
| Customer payments in | YES | `:80-90` |
| Customer refunds out (negative payments) | YES | `:82-83` |
| Supplier payments out | YES | `:93-101` — but only `amount > 0` |
| Expenses out (not Draft/Cancelled) | YES | `:104-112` |
| Salary payments out | YES | `:115-123` |
| Direct purchases out | YES — **unconditionally** | `:126-131` |
| Goods receipts / PO settlements | via supplier payments only | — |
| Cash sales not recorded as a payment | NO | — |
| Other income | NO | — |
| Owner drawings | **NO — concept absent** | — |
| Capital injection | **NO — concept absent** | — |
| Inter-account transfers (cash↔bank) | **NO — concept absent** | — |
| Supplier refunds in | **NO — filtered out** | `:96`, `:267` |
| Payments with NULL `payment_method` | **NO — silently dropped** | `:43` |

### CASH-01 — Every purchase drains the cash till regardless of method or payment status; paying for it drains it again — P0

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/services/cashService.ts:125-131`

```ts
// Direct purchases: paid on the spot, so they drain the cash till.
const purchases = db.prepare(`
  SELECT COALESCE(SUM(total_cost), 0) as outflow
  FROM purchases
  WHERE purchase_date <= ?
`).get(uptoDate) as { outflow: number };
totals.get('cash')!.outflow += Number(purchases.outflow) || 0;
```

Duplicated at `:294-305` for the transaction drill-down, which hard-codes `method: 'cash'`.

The comment is an assumption, not a fact. `purchases` has **no payment-method column and no paid flag**; payment is tracked in `purchase_allocations`. So:
1. An unpaid (credit) purchase reduces expected cash even though no money moved.
2. When it *is* paid, the supplier payment (`:93-101`) reduces cash **again** — the same money out twice.
3. A purchase paid by bank transfer still reduces `cash`, never `bank`.

Live numbers: `PURCH-2026-0029` = 500, `purchase_allocations` is **empty** (verified) → the purchase is unpaid, yet `cashService` subtracts 500 from the till *today*, while `supplier_ledger` id 22 correctly shows 500 still payable. Expected cash is understated by 500 right now. Pay it with a 500 cash supplier payment tomorrow and the till drops another 500 — a 1,000 cash outflow for a 500 purchase, and the reconciliation report will show a +500 "cash over" variance that no one can explain.

Fix: delete both purchase blocks. Cash out for purchases is *already* captured by supplier payments allocated to them — that is what `purchase_allocations` is for. If quick cash purchases must remain, add `purchases.payment_method` plus an auto-created supplier payment, and derive cash from payments only.
Migration: no (report-only). Historical data affected: every historical cash position and dashboard figure is wrong by the sum of purchases in the period; with 36 purchases hard-deleted the historical series is not even reproducible.

### CASH-02 — Payments with a NULL/empty `payment_method` are invisible to cash — P1

`cashService.ts:42-51`

```ts
export function normalizeCashMethod(method?: string | null): string | null {
  if (!method) return null;
  ...
  if (m === 'credit') return null;
  return 'bank';
}
```

`add(...)` returns immediately on a null key (`:70-76`), and `push(...)` filters the same way (`:233`). `payments.payment_method` is `VARCHAR(50)` with no NOT NULL and no default; `Payment.create` (`Payment.ts:215`) passes it straight through from the request, and `MobileInvoice.ts:264` / `Invoice.ts:756` are separate insert paths. Only `createSupplierPayment` defaults it (`Payment.ts:353`, `data.payment_method || 'Cash'`).

Failure scenario: a POS or mobile payment of 5,000 is created without `payment_method`. It appears in the payments list, credits the invoice, debits GL Cash — and is **completely absent** from the till, the dashboard cash card and the reconciliation report. The drawer is 5,000 over and the system says the count is wrong.
Fix: `NOT NULL DEFAULT 'Cash'` on `payments.payment_method` and `expenses.payment_method`; validate against `CASH_ACCOUNTS` keys + `'credit'` + the bank-like set on write; log and surface any row that normalises to null instead of dropping it silently.
Migration: yes. Historical: all 10 live payments have `payment_method='Cash'`, so nothing is currently hidden.

### CASH-03 — `return 'bank'` catch-all silently absorbs typos and unknown methods — P2

`cashService.ts:50`. Any unrecognised string — `'Cheque'`, `'cash '` with a trailing space is handled by `.trim()` but `'Cash on delivery'`, `'CASH-2'`, a mojibake import — becomes **bank**. Cash goes missing from the till and appears in the bank balance, with no warning. Fix: whitelist explicitly; route unknown methods to an `unclassified` bucket that the reconciliation report displays. Migration: no.

### CASH-04 — `cash_reconciliations` write endpoint is gated by a READ permission — P1

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/routes/reports.ts:19-21`

```ts
router.post('/cash-reconciliation', requirePermission('reports', 'read'), ...)
```

`saveCashReconciliation` (`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/models/Reports.ts:1132-1173`) persists the counted cash, the expected snapshot and the variance — the record a manager signs off on. Anyone with read access to reports can create or overwrite it (`ON CONFLICT(reconciliation_date, account_key) DO UPDATE`, per `add-cash-accounts.sql`). There is no immutability once signed and no `activity_log` entry.

Failure scenario: a cashier who is 10,000 short re-posts the reconciliation for that date with `counted = expected`, overwriting the variance. The shortfall disappears from the only record that would have caught it.
Fix: `requirePermission('reports','create')` or a dedicated `cash_reconciliation:approve`; make a saved reconciliation immutable (append-only, with an explicit re-count row); log it.
Migration: no. Historical: 0 rows.

### CASH-05 — No owner drawings, capital injection, other income, or inter-account transfer — P1

Grep of `cashService.ts` and the schema finds no drawings/capital/transfer concept, and `CASH_ACCOUNTS` (`:28-34`) has no mechanism for moving money between the five accounts. Consequences: the owner taking 20,000 from the till has no representation, so the reconciliation shows a permanent unexplained 20,000 shortage; depositing 50,000 of till cash into the bank cannot be recorded at all, so cash stays overstated by 50,000 and bank understated by the same. In a business where the owner routinely moves cash — which the presence of five wallet accounts strongly implies — the till will never reconcile.
Fix: a `cash_transactions` table (or reuse `journal_entries`) for `DRAWING`, `CAPITAL`, `TRANSFER`, `OTHER_INCOME`, `OTHER_EXPENSE`, with `from_account_key`/`to_account_key`, included in `collectFlows` and posted to the GL (`Dr 3xxx Drawings / Cr 1000` etc.).
Migration: yes (new table + COA accounts). Historical: past variances are unexplainable.

### CASH-06 — `getCashAccountTotals` recomputes the entire history twice per call — P3

`cashService.ts:136-210` calls `collectFlows(asOfDate)` and `collectFlows(asOfDate − 1 day)` to derive the day's opening balance, and each call runs five full-table aggregate scans with `<= date` (no index usable for the `purchases` scan). Two full history scans per dashboard load, growing linearly forever. Fix: one pass returning `(before, on)` buckets via `CASE WHEN date < ? ...`; index `payments(payment_date)`, `expenses(expense_date)`, `purchases(purchase_date)`. Migration: indexes only.

### What is CORRECT in cash — do not change

- **Deriving cash from the transactional tables rather than the GL is the right decision** given PAY-08/PUR-01/EXP-01, and `cashService.ts:8-21` documents exactly why. Do not "fix" this by switching to GL balances until the GL is complete.
- Seeding each account with its `opening_balances` row into `inflow` (`:64-68`) so that `balance = inflow − outflow` includes it on every date is correct and neatly avoids a special case. Live: cash 5,000, all others 0.
- Signed handling of customer payments — positive as inflow, negative (refunds) as outflow, in one pass (`:80-90`) — is correct and matches how `invoiceController` records refunds as negative payments.
- `normalizeCashMethod` returning `null` for `'credit'` (`:49`) is right: a credit adjustment is not money.
- `cash_reconciliations` snapshots `expected_balance` at save time (`Reports.ts:1132-1173`) rather than recomputing it later — the correct design for an auditable reconciliation, since the expected figure must not drift when back-dated transactions arrive.
- `getCashReconciliation` (`Reports.ts:1069-1124`) and the Flutter screen (`lib/features/reports/cash_reconciliation_screen.dart`) are complete and wired. The feature works; it is simply unused.

---

## 6. DOCUMENT NUMBERING

### NUM-01 — Sequence numbers are consumed inside transactions, so every rollback burns a number — P2 (explains FACT 10)

`/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/server/src/utils/sequence.ts:8-24`

```ts
export function getNextSequenceNumber(db: Database.Database, settingKey: string): number {
  db.prepare(`
    INSERT INTO settings (key, value, updated_at) VALUES (?, '1', CURRENT_TIMESTAMP)
    ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT), updated_at = CURRENT_TIMESTAMP
  `).run(settingKey);
  const setting = db.prepare('SELECT value FROM settings WHERE key = ?').get(settingKey) as { value: string };
  return parseInt(setting.value, 10);
}
```

The increment is a single atomic statement against `settings(key)` PRIMARY KEY (`init.sql:24-29`), and `better-sqlite3` is synchronous with one connection, so **two concurrent requests in this process cannot receive the same number**. FACT 11's premise is therefore false: there is no duplicate-number race and no resulting 500 from the UNIQUE constraint — with one caveat below.

The real issue is that the counter lives in the same transaction as the document. `Purchase.recordPurchase` calls `generatePurchaseNo` at `Purchase.ts:124`, *inside* `db.transaction` opened at line 123. If the transaction rolls back, the `settings` increment rolls back too — which is actually correct behaviour and does **not** burn the number. `PURCH_last_no_2026 = 37` with 1 surviving row is explained not by rollbacks but by **hard deletes**: `sqlite_sequence.purchases = 37` confirms 37 rows were successfully created and 36 subsequently deleted. So the counter is honest; the data is missing.

Residual defect: because `getNextSequenceNumber` and `generateDocNo` are called inside long transactions that also do stock and ledger work, the `settings` row is write-locked for the duration, serialising all document creation. On a multi-user till this is a throughput ceiling, and with `busy_timeout = 5000` (`config/database.ts:32`) a slow transaction can push a concurrent one into `SQLITE_BUSY`.

Caveat / **UNVERIFIED**: `Payment.generatePaymentNo` (`Payment.ts:56-73`) and `Invoice.generatePaymentNoAtomic` (`Invoice.ts:475-501`) both resync the counter from `MAX(payment_no)` before incrementing. Live payment numbers are `PAY001…PAY010` (no year segment) while `generateDocNo` (`sequence.ts:27-32`) produces `PREFIX-YEAR-NNNN`. I did not trace which format `generatePaymentNo` emits today, so whether the MAX-resync parses the legacy format correctly is unverified — if it does not, the resync could reset the counter and collide on `payment_no UNIQUE`.

Fix: take document numbers from a short dedicated transaction, or accept gaps and document that numbers are not gapless. Do not hard-delete numbered documents.
Migration: no. Historical: numbering gaps exist and are legitimate.

### NUM-02 — `expense_no` bypasses the sequence utility entirely — P2

See EXP-05. `Expense.generateExpenseNo` uses `MAX(expense_no)` with no transaction and no `settings` counter — the one document type that genuinely can collide, because it is the one that does not use `getNextSequenceNumber`.

### What is CORRECT in numbering — do not change

- `getNextSequenceNumber`'s single-statement atomic UPSERT (`sequence.ts:9-15`) is the right primitive. It is safe under `better-sqlite3`'s synchronous single-connection model.
- `settings(key)` is a PRIMARY KEY (`init.sql:25`), so the `ON CONFLICT` target is valid.
- All of `PAY`, `PO`, `PURCH`, `GR`, `STK`, `BATCH`, `CUST` route through it (`sequence.ts:27-32` + callers), giving one consistent mechanism — except expenses.
- Year-scoped keys (`${prefix}_last_no_${year}`) give clean annual restarts.

---

## 7. UNVERIFIED / NOT COVERED

- `Payment.generatePaymentNo`'s emitted format vs the live `PAY001` style, and whether its `MAX(payment_no)` resync parses legacy numbers safely (NUM-01 caveat).
- Whether a `purchase_returns:void` permission exists in the roles/permissions seed — if it does not, `voidReturn` may be unreachable or open to everyone.
- `posController.ts:195-197` and `MobileInvoice.ts:264-282` as additional payment-creation paths: both insert into `payments` + `payment_allocations` directly. Not read in full; they are the most likely source of NULL `payment_method` rows (CASH-02).
- Whether the Flutter client ever sends `deleted_payments` with ids not belonging to the invoice (PAY-01 is a server-side hole regardless).
- `add-purchase-returns-tables.sql` DDL: whether `purchase_returns.source_id` has an enforced FK (it cannot have one, since `source_type` selects between `purchases` and `purchase_order_items` — a polymorphic FK, unenforceable in SQLite), and the exact `credit_notes` column set.
- Concurrency behaviour under Electron with multiple renderer processes sharing `erp.db` in WAL mode — if a second process ever opens the database, the two-statement read in `getNextSequenceNumber` becomes genuinely racy.

---

## 8. PRIORITY ORDER FOR REMEDIATION

**P0, in this order:**
1. PAY-01 — arbitrary payment deletion via the invoice endpoint (security + integrity, trivial fix).
2. CASH-01 — delete the two `purchases` cash blocks; the till is wrong today by 500 and doubles on payment.
3. PUR-02 — separate the `stock_batches` source namespace before `goods_receipt_items.id` reaches 38.
4. PAY-02 / PAY-04 — void the GL on payment delete; block amount edits on allocated payments.
5. PAY-08 / PUR-01 / EXP-01 — post supplier payments, purchases and expenses to the GL. The general ledger is currently not a ledger.
6. PUR-03 — stop hard-deleting purchases.
7. PRET-01 / PRET-02 / PRET-03 — purchase returns must not ship as they stand; the three P0s here each lose money on the first real return.

**Cheapest high-value wins:** delete `cashService.ts:125-131` and `:294-305` (CASH-01); add the ownership check at `invoiceController.ts:436-455` (PAY-01); add `voidJournalLinesByReference` to `Payment.delete` (PAY-02); change `requirePermission('reports','read')` to a write permission on the reconciliation POST (CASH-04); use `lastInsertRowid` instead of the ambiguous re-query at `Purchase.ts:172-176` (half of PUR-02).

agentId: a5967478ee97e7ad3 (use SendMessage with to: 'a5967478ee97e7ad3', summary: '<5-10 word recap>' to continue this agent)
<usage>subagent_tokens: 118298
tool_uses: 64
duration_ms: 3042309</usage>