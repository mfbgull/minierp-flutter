# ACCOUNTING LAYER FORENSIC AUDIT — MiniERP

Read-only audit. No file was modified. All line numbers verified against source at `/media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/`.

---

## PART 0 — ARCHITECTURAL VERDICT (Task 9)

**This is not double-entry. It is a subledger-authoritative system with a partially-wired, decorative General Ledger bolted on.**

Evidence chain:

1. The **Balance Sheet does not read the GL** for AR, AP, Inventory, or Equity. `ReportsModel.getBalanceSheet` (`server/src/models/Reports.ts:561-714`) derives Inventory from `stock_batches`, AR from `invoices.balance_amount`, AP from the `supplier_ledger` running balance, and Equity from a `settings` key plus a recomputed net income. Only Cash touches the GL.
2. The **Trial Balance is the only GL consumer** (`Reports.ts:733-773` → `AccountingService.getAllAccountBalances`).
3. Therefore the GL is a write-only side-effect that nothing in production depends on — which is *why* it has been allowed to drift into a -3,276.2 Inventory balance without anyone noticing.

**Multi-line entries ARE supported.** `AccountingService.postEntry` (`accountingService.ts:184-279`) accepts an arbitrary `lines[]` array, requires `>= 2`, and validates the sum. `postInvoiceReturnEntry` (`accountingService.ts:555-682`) emits up to **4** lines. The "only 2-line pairs exist in the data" observation is a *data* artifact caused by `tax_rate` always being 0 and restocking deductions being 0 — **not a code limitation**. Do not "add multi-line support"; it exists.

---

## PART 1 — COMPLETE POSTING MATRIX (Task 1)

`server/src/services/accountingService.ts` is the **only** writer to `journal_lines`. Every function below funnels through `postEntry`.

| Function | Line | Debit | Credit | reference_type | Table |
|---|---|---|---|---|---|
| `postInvoiceEntry` | 296-350 | 1100 AR (total) | 4000 Revenue (net) + 2100 Tax Payable (if tax>0) | `INVOICE` | journal_lines |
| `postCOGSEntry` | 465-497 | 5000 COGS | 1200 Inventory Asset | `INVOICE` | journal_lines |
| `postPaymentEntry` | 356-388 | 1000/1010/1020/1030/1040 (per method) | 1100 AR | `PAYMENT` | journal_lines |
| `postPurchaseOrderEntry` | 398-427 | 1200 Inventory Asset | 2000 AP | `PURCHASE_ORDER` | journal_lines |
| `postInvoiceReturnEntry` | 555-682 | 4100 Sales Returns (gross) + 2100 Tax (if tax) | 1100 AR (net) + 4150 Restocking Fee (if deduction) | `INVOICE_RETURN` | journal_lines |
| `postCOGSReversalEntry` | 511-543 | 1200 Inventory Asset | 5000 COGS | `INVOICE_RETURN` | journal_lines |
| `postPurchaseReturnEntry` | 692-723 | 2000 AP | 1200 Inventory Asset | `PURCHASE_RETURN` | journal_lines |
| `postRefundEntry` | 739-771 | 1100 AR | cash/bank per method | `REFUND` | journal_lines |
| `postSalaryEntry` | 844-878 | 6100 Wages & Salaries | cash/bank per method | `SALARY` | journal_lines |
| `voidJournalLinesByReference` | 787-800 | — soft void — | — | (by ref) | journal_lines |

Cash/bank account resolution, `accountingService.ts:441-451`: `cash`→1000, `easypaisa`→1020, `jazzcash`→1030, `upaisa`→1040, **everything else**→1010 Bank.

**Second, parallel posting path — legacy `journal_entries` (TEXT accounts, no `account_id`):**

| Writer | Line | Debit | Credit | reference_type |
|---|---|---|---|---|
| `StockMovement.postFinancialEntryForAdjustment` | `models/StockMovement.ts:349-393` | `inventory_shrinkage` (removal) / `inventory_asset` (addition) | `inventory_asset` / `inventory_correction` | `stock_adjustment` |
| `StockMovement.postFinancialEntryForProduction` | `models/StockMovement.ts:425-463` | `inventory_asset` | `production_clearing` | `production` |
| `PhysicalCount` (count variance) | `models/PhysicalCount.ts:345-357` | `inventory_shrinkage` / `inventory_asset` | `inventory_asset` / `inventory_correction` | `stock_adjustment` |

**NO posting function exists for:** direct purchases, supplier payments, expenses, POS sales, mobile invoices, sales-order-converted invoices, owner capital, drawings, retained-earnings closing, depreciation, or bank transfers.

---

## PART 2 — FINDINGS

### P0 — CONFIRMED BUGS

---

**ACC-01 — Two structurally incompatible GL tables with independent, colliding ID spaces**
Severity: **P0** (architectural + confirmed)
`server/src/services/accountingService.ts:12-22`, `:251-254`

```
 *   - This service does NOT replace the old journal_entries table
 *     (single debit_account + single credit_account, TEXT). That table
 *     is still used by postFinancialEntryForAdjustment / production
 *     ... New postings can go through either path.
```
```ts
const lastEntry = db.prepare(
  `SELECT COALESCE(MAX(journal_entry_id), 0) as last_id FROM journal_lines`
).get() as { last_id: number };
const entryId = lastEntry.last_id + 1;
```

Why it matters: `journal_lines.journal_entry_id` is generated from `MAX(journal_lines.journal_entry_id)+1`; `journal_entries.id` is `AUTOINCREMENT`. They overlap. Meanwhile `stock_movements.journal_entry_id` is an FK to `journal_entries(id)` (`config/database.ts:1377`) but `salary_payments.journal_entry_id` is populated from `postEntry`'s `journal_lines` grouping id (`controllers/employeeController.ts:245-248`). **The same column name refers to two different tables' key spaces.** Any future join, drill-down, or reconciliation report is silently wrong.
Failure scenario: Auditor drills into salary payment #3 (`journal_entry_id=57`) and the UI joins `journal_entries` — it returns an unrelated stock adjustment.
Fix: Migrate all three `journal_entries` writers onto `postEntry` with real `account_id`s (7100/7200/7000 already exist in the chart), then drop `journal_entries` or rename its FK column. Interim: rename `journal_lines.journal_entry_id` → `entry_group_id` and add a `source_table` discriminator.
Migration needed: **Yes** (data backfill of 44 rows + FK column rename).
Historical data affected: **Yes** — 44 rows, 72,800 currency units currently invisible to any `journal_lines`-only query.

---

**ACC-02 — Direct purchases post NOTHING to the GL (root cause of FACT 4)**
Severity: **P0**
`server/src/models/Purchase.ts:239-250`

```ts
if (resolvedSupplierId) {
  SupplierLedgerModel.createEntry({ supplier_id: resolvedSupplierId, transaction_date: purchase_date,
    transaction_type: 'PURCHASE', reference_no: purchaseNo, debit: totalCost, credit: 0,
    description: `Purchase ${purchaseNo}` }, db);
  SupplierLedgerModel.rebuildBalances(resolvedSupplierId, db);
}
```

Why it matters: `Purchase.ts` contains **zero** references to `AccountingService` (verified by grep across the whole 525-line file). Inventory is never debited and AP is never credited. But `postCOGSEntry` *does* credit 1200 Inventory on every sale. **Inventory Asset therefore accumulates credits with no offsetting debits — that is exactly the -3,276.2 in FACT 2.** Also `stock_movements.financial_posted` is never set for `movement_type='PURCHASE'` (the INSERT at `Purchase.ts:180-199` omits the column), so it stays 0 forever and no backfill job can distinguish "not posted" from "not applicable".
Failure scenario: Buy 100 units at 10 (1,000), sell 50 (COGS 500). GL Inventory = -500. Balance Sheet says +500 (it reads `stock_batches`). Trial balance is out by 1,000 and does not balance.
Fix: In the `recordPurchase` transaction, call a new `postPurchaseEntry` — Dr 1200 Inventory / Cr 2000 AP (or Cr 1000 Cash if paid immediately). Set `financial_posted=1`.
Migration needed: **Yes** — backfill historical purchases.
Historical data affected: **Yes** — every purchase ever recorded.

---

**ACC-03 — Supplier payments post NOTHING to the GL; 27,500 of cash left the business invisibly (root cause of FACT 3)**
Severity: **P0**
`server/src/models/Payment.ts:262-395`, specifically `:386-392`

```ts
db.prepare(`
  INSERT INTO supplier_ledger (supplier_id, transaction_date, transaction_type, reference_no, debit, credit, balance, description)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?)
`).run(data.supplier_id, data.payment_date, 'PAYMENT', paymentNo, 0, data.amount, newBalance, `Payment against ${references.join(', ')}`);
db.prepare('UPDATE suppliers SET current_balance = ? WHERE id = ?').run(newBalance, data.supplier_id);
return paymentId;
```

Why it matters: `createSupplierPayment` ends here. There is **no `AccountingService` call anywhere in the method**. Cash physically left the business (PAY001/002/009 = 27,500) and GL account 1000 Cash has no credit for it. GL Cash is therefore *overstated by the entire history of supplier payments* — it only ever receives debits from customer payments (FACT 2: "Cash = +4,367 debit only").
Failure scenario: Owner reads the Trial Balance, believes there is 4,367 cash on hand, writes a cheque. Actual position is negative.
Fix: Add `postSupplierPaymentEntry` — Dr 2000 AP / Cr cash-or-bank per `payment_method`, reusing `_cashOrBankAccountCode`.
Migration needed: **Yes** — backfill.
Historical data affected: **Yes** — all supplier payments.

---

**ACC-04 — Expenses post NOTHING to the GL**
Severity: **P0**
`server/src/models/Expense.ts:63-74`

The `create` method is a bare `INSERT INTO expenses`. No `AccountingService` import exists in the file. This is why account **6000 Operating Expenses has zero activity** (FACT 2) despite the expenses table being in active use, and why any GL-derived P&L would report inflated profit.
Fix: Dr 6000 (or an expense-category-mapped account) / Cr cash-or-bank. Requires an expense-category → account mapping table.
Migration needed: **Yes** (mapping table + backfill).
Historical data affected: **Yes**.

---

**ACC-05 — POS sales post NOTHING to the GL**
Severity: **P0**
`server/src/controllers/posController.ts:37-239`

`createPOSSale` inserts an invoice with `status='Paid'`, invoice_items, FIFO stock movements, a payment row, a payment allocation, and two `customer_ledger` rows — and makes **zero** GL postings. There is no `AccountingService` import in the 300-line file.
Why it matters: Revenue, AR, Cash, and COGS are all skipped. But `postPaymentEntry` from the *non-POS* path credits 1100 AR without POS ever debiting it — this is a direct contributor to the **-780 negative AR** in FACT 2.
Fix: Route POS through the same posting sequence as `invoiceController.createInvoice` (postInvoiceEntry + postCOGSEntry + postPaymentEntry), or better, have POS call the shared invoice-creation service rather than duplicating 200 lines.
Migration needed: **Yes** — backfill.
Historical data affected: **Yes**.

---

**ACC-06 — Mobile invoice submission posts NOTHING to the GL**
Severity: **P0**
`server/src/models/MobileInvoice.ts:194-305`

`submitInvoice` computes subtotal/tax/total, inserts invoice + items + stock movements + payment + allocations + `ledgerUtils.createLedgerEntry`, and makes no GL posting. Note it *does* compute a tax amount (`:205-210`) which is then discarded from an accounting standpoint.
Fix: Same as ACC-05.
Migration needed: **Yes**. Historical data affected: **Yes**.

---

**ACC-07 — `SalesOrder.convertToInvoice` posts neither the GL nor the customer subledger**
Severity: **P0**
`server/src/models/SalesOrder.ts:~610-720`

Verified by grep: `grep -n "ledger\|Ledger\|Accounting" models/SalesOrder.ts` returns **no matches** in the entire file. `convertToInvoice` inserts `invoices` + `invoice_items` + FIFO `stock_movements` and stops.
Why it matters: This is worse than ACC-05/06. The invoice does not appear in `customer_ledger` **at all**, so it is missing from the customer statement, the aged-receivables report, and `Reports.getGeneralLedger`. It *does* appear in `invoices`, so `updateCustomerBalance` (which sums `invoices.balance_amount`) sees it — producing a permanent, structural divergence between `customers.current_balance` and the ledger.
Failure scenario: Customer converts a 50,000 SO to an invoice. Statement shows nothing owed. Collections never chases it.
Fix: Add `createLedgerEntry` + the three GL postings inside the existing transaction.
Migration needed: **Yes**. Historical data affected: **Yes**.

---

**ACC-08 — `updateInvoice` never touches the GL: amounts silently diverge**
Severity: **P0**
`server/src/controllers/invoiceController.ts:375-596`, ledger handling at `:572-573`

```ts
InvoiceModel.deleteLedgerEntryByReference(db, resolvedInvoiceNo);
InvoiceModel.createLedgerEntry(db, parsedCustomerId, 'INVOICE', resolvedInvoiceNo, totalAmountNum, 0,
  `Invoice ${resolvedInvoiceNo} (updated)`);
```

Why it matters: `updateInvoice` contains **no** `voidJournalLinesByReference` and **no** re-post. Change an invoice from 1,000 to 100,000 and the GL still says 1,000, while the subledger says 100,000. This code is also the exact origin of the `"Invoice INV-2026-958984 (updated)"` description in **FACT 8** — the update hard-deletes the old ledger row (losing the original amount and its date) and appends a replacement, so there is no audit trail of what changed.
Failure scenario: Fraudulent or accidental invoice edit is invisible in the GL and leaves no before/after record.
Fix: In the update transaction: `voidJournalLinesByReference(db,'INVOICE',id)` then re-run `postInvoiceEntry` + `postCOGSEntry`. Replace the ledger delete-and-reinsert with a reversing ledger row.
Migration needed: No (code only). Historical data affected: **Yes** — existing GL amounts for edited invoices are stale and unrecoverable.

---

**ACC-09 — `Payment.delete` and `Payment.update` leave ACTIVE orphaned GL lines**
Severity: **P0**
`server/src/models/Payment.ts:453-488` (delete), `:400-448` (update)

```ts
db.prepare('DELETE FROM payments WHERE id = ?').run(id);
db.prepare('DELETE FROM customer_ledger WHERE reference_no = ?').run(existing.payment_no);
db.prepare('DELETE FROM supplier_ledger WHERE reference_no = ?').run(existing.payment_no);
```

Why it matters: No `voidJournalLinesByReference(db,'PAYMENT',id)`. Delete a customer payment via `DELETE /api/payments/:id` and the **Dr Cash / Cr AR lines stay active** in `journal_lines` while the payment row is gone. `Payment.update` recalculates allocations proportionally but likewise never voids/reposts, so the GL keeps the pre-edit amount. This is the **only confirmed, currently-reachable orphaning path in the codebase** — and it is the most plausible mechanism behind FACT 5 (see UNVERIFIED-1).
Failure scenario: Mistyped payment deleted and re-entered → Cash double-counted permanently.
Fix: Void by reference in both methods; repost on update.
Migration needed: No. Historical data affected: **Yes** — orphans already exist.

---

**ACC-10 — Balance Sheet bypasses the GL entirely: two irreconcilable books**
Severity: **P0** (architectural)
`server/src/models/Reports.ts:561-714`

Inventory from `stock_batches` + legacy `items` (`:595-610`); AR from `invoices.balance_amount` (`:612-617`); AP from the latest `supplier_ledger` running balance per supplier (`:632-644`); Equity = `settings['opening_retained_earnings']` + net income recomputed from `invoices`/`stock_movements`/`expenses` (`:646-677`).
Why it matters: The Balance Sheet and the Trial Balance are computed from **completely disjoint data sources**. The BS will always look plausible (it is derived from the operational tables) while the TB is catastrophically wrong. There is no report in the system that would reveal the discrepancy, which is why a -3,276.2 Inventory balance survived to production. This is also why closing the books is impossible: there is no path from the GL to the Balance Sheet.
Fix: Long-term, make the GL authoritative and have the BS read `getAccountBalance`. Short-term, add a **reconciliation report** that diffs GL balances against the operational derivations per account — this is the highest-value single addition to the codebase.
Migration needed: No. Historical data affected: N/A (reporting).

---

**ACC-11 — Period auto-open covers only the current month: a guaranteed hard outage on the 1st of next month**
Severity: **P0** (time bomb; will fire 2026-09-01)
`server/src/migrations/add-gl-foundation.sql` (section 4) + `accountingService.ts:226-237`

```sql
INSERT INTO accounting_periods (period_name, start_date, end_date, status)
SELECT strftime('%Y-%m','now'), date('now','start of month'),
       date('now','start of month','+1 month','-1 day'), 'open'
WHERE NOT EXISTS (SELECT 1 FROM accounting_periods WHERE status = 'open');
```
```ts
if (!openPeriod) {
  throw new Error(`No open accounting period covers ${input.entry_date}. ...`);
}
```

Why it matters: The migration seeds **one** period, for the current month, and the `WHERE NOT EXISTS` guard means it will **never seed another** as long as any open period exists. Once the open period's `end_date` passes, `postEntry` throws. Verified by grep: **no `AccountingService.post*` call anywhere is wrapped in a try/catch that swallows the error** (the only try/catch, at `controllers/employeeController.ts:228`, rethrows). Because `postInvoiceEntry` is called *inside* the `createInvoice` transaction (`invoiceController.ts:303-311`), the throw **rolls back the entire invoice** — stock movements, payment, ledger and all.
Failure scenario: On 2026-09-01 every invoice creation, every customer payment, every PO submit, and every salary payment fails with HTTP 500 "Failed to create invoice". The business cannot trade. Backdating an invoice into a closed month fails identically today.
Fix: Auto-create-and-open the period covering `entry_date` on demand (or a nightly rollover job). Additionally: catch the period error at the controller and return a specific, actionable 409 rather than a generic 500.
Migration needed: **Yes** (period rows for future months).
Historical data affected: No — but note the inverse risk: because only one period was ever opened, **any legitimately backdated posting has been silently rejected**, which may itself explain missing GL rows.

---

**ACC-12 — Customer ledger running balance is chained by `id`, and the transaction date is forced to today (root cause of FACT 6)**
Severity: **P0**
`server/src/utils/ledgerUtils.ts:11-27`

```ts
const lastBalanceResult = db.prepare(`
  SELECT balance FROM customer_ledger WHERE customer_id = ? ORDER BY id DESC LIMIT 1
`).get(customerId) as { balance: number } | undefined;
...
) VALUES (?, date('now'), ?, ?, ?, ?, ?, ?)
```

Two independent defects in 17 lines:
(a) `ORDER BY id DESC` — the chain follows *insertion* order, not *transaction_date* order. Insert a back-dated RETURN after a later-dated PAYMENT and the stored `balance` column becomes nonsense. This is precisely FACT 6's `600 → -600 → 0`.
(b) `date('now')` — the caller-supplied document date is **discarded**. Every ledger row is stamped with the server's current date. So the ledger cannot be sorted chronologically even in principle, and any date-ranged statement is wrong.
`rebuildLedgerBalances` (`ledgerUtils.ts:128-144`) does not fix this — it also recomputes `ORDER BY id ASC`. Meanwhile `Customer.getStatement` (`models/Customer.ts:274-330`) computes its opening balance with `ORDER BY transaction_date DESC LIMIT 1` and `SupplierLedger.getTransactions` (`models/SupplierLedger.ts:102-108`) reads `ORDER BY transaction_date DESC, created_at DESC` — **the display order and the stored-chain order are different**, so the printed running balance never reconciles with the printed rows.
Failure scenario: Customer statement is emailed showing a negative running balance mid-column. Customer disputes. There is no way to reproduce the correct figure without a full rebuild.
Fix: (1) Pass and store the real document date. (2) Stop storing `balance` — compute it as a window function at read time: `SUM(debit-credit) OVER (PARTITION BY customer_id ORDER BY transaction_date, id)`. If the column must stay for compatibility, rebuild it in `(transaction_date, id)` order and rebuild after **every** insert, not just deletes.
Migration needed: **Yes** — `transaction_date` values are lost and cannot be recovered for existing rows except by joining back to `invoices.invoice_date` / `payments.payment_date` via `reference_no`.
Historical data affected: **Yes** — every `customer_ledger` row written through this function.

---

**ACC-13 — Four mutually inconsistent sources of truth for a customer's balance**
Severity: **P0**
Four distinct writers, four different bases:

1. `server/src/utils/ledgerUtils.ts:46-54` — `customers.current_balance` from open-invoice status:
```ts
SELECT COALESCE(SUM(balance_amount), 0) as total_balance FROM invoices
WHERE customer_id = ? AND status IN ('Unpaid', 'Partially Paid', 'Overdue')
```
2. `server/src/controllers/invoiceController.ts:1077-1079` and `:1173-1175` — `customers.credit_balance`, written independently during returns.
3. `server/src/models/Payment.ts:228-240` — writes a `customer_ledger` row whose `balance` is derived from `customers.current_balance - amount`, **not** from the ledger chain. A third basis.
4. `server/src/models/Customer.ts:337-344` — `recalculateBalance`, a duplicate of (1).

Plus the stored `customer_ledger.balance` column itself (ACC-12) and the derived `SUM(debit)-SUM(credit)`.
Why it matters: This is FACT 6's "Customer 1 has THREE different balances" — `current_balance=0`, `credit_balance=600`, ledger sum `-180`, last stored ledger balance `0`. Note that `status IN ('Unpaid',...)` **excludes `'Cancelled'` and `'Paid'`** but also excludes any status string not in the list, so a typo or new status silently zeroes a customer's balance. `credit_balance` is never netted against `current_balance` anywhere.
Failure scenario: Credit limit check reads `current_balance` (0), approves a large order, while the customer actually holds a 600 credit and owes -180 net. Aged receivables, statement, and customer list all show different numbers.
Fix: Pick one derivation. Recommend: drop `customers.current_balance` and `credit_balance` as stored columns entirely and expose a single SQL view over `customer_ledger`. If they must remain as a cache, write them from exactly one function that reads the ledger.
Migration needed: **Yes** if columns are dropped. Historical data affected: **Yes**.

---

**ACC-14 — Reversal is implemented as hard DELETE in three places; no reversing entries (root cause of FACT 8)**
Severity: **P0**
Three hard-delete sites, all verified:

- `server/src/models/Invoice.ts:891-893`
```ts
static deleteLedgerEntryByReference(db: Database.Database, referenceNo: string): void {
  db.prepare(`DELETE FROM customer_ledger WHERE reference_no = ?`).run(referenceNo);
}
```
- `server/src/models/Payment.ts:462-463` — `DELETE FROM customer_ledger` / `DELETE FROM supplier_ledger WHERE reference_no = ?`
- `server/src/models/Purchase.ts:467-470` — `DELETE FROM supplier_ledger WHERE supplier_id = ? AND reference_no = ? AND transaction_type = 'PURCHASE'`

Why it matters: This is why `customer_ledger` ids jump 15 → 32 (FACT 8). A ledger is an append-only record; deleting rows destroys the audit trail, breaks the running-balance chain (leaving a mid-chain gap until a rebuild runs), and makes it impossible to answer "what did this account look like on date X". Note that `Invoice.ts:891-893` has **no `customer_id` predicate** (see ACC-20).
Failure scenario: Tax authority requests the ledger for a prior period. Rows for deleted/edited documents are simply gone; totals no longer tie to filed returns.
Fix: Never delete. Insert a reversing row (`transaction_type='REVERSAL'`, swapped debit/credit, referencing the original row id) and add a `reversed_by` / `voided` column. Add a DB trigger or app-level guard forbidding `DELETE` on the ledger tables.
Migration needed: **Yes** (add `voided`/`reversed_by` columns).
Historical data affected: **Yes** — deleted rows are unrecoverable.

---

**ACC-15 — Money is floating point end-to-end; no integer cents anywhere**
Severity: **P0**
`server/src/utils/currency.ts:1-33`

```ts
export function roundCurrency(value: number): number {
  return Number(Math.round(Number(value + 'e+2')) + 'e-2');
}
```

Why it matters: This is the entire money layer — 33 lines of float helpers. There is no minor-unit/integer-cents representation anywhere in the codebase (verified by grep). Columns are declared `DECIMAL(15,2)` but SQLite has no DECIMAL type — this is **NUMERIC affinity**, which stores whatever JS hands it, producing the mixed INTEGER/REAL you observed. Critically, several posting paths **bypass** `roundCurrency` entirely: `postInvoiceReturnEntry` receives an unrounded `returnAmount` computed by raw float arithmetic (`invoiceController.ts:898-912`), `PurchaseOrder.ts:133` uses `items.reduce((sum,i) => sum + (i.quantity * i.unit_price), 0)`, `posController.ts:73` uses `total += item.quantity * item.unit_price`, and `SupplierLedger.createEntry` (`models/SupplierLedger.ts:34`) uses bare `currentBalance + debit - credit`. `postEntry`'s own balance check has a 0.01 tolerance (`accountingService.ts:220`), so unbalanced-by-a-cent entries pass validation and are committed.
Failure scenario: `journal_lines.debit = 1366.7999999999998`. Trial balance shows a 0.0000000002 imbalance that no human can reconcile. Repeated over thousands of rows, the tolerance-accumulated drift becomes material.
Fix: Store money as INTEGER minor units. That is a large migration; the pragmatic interim is to force `roundCurrency` at every write boundary — especially `postEntry` (round each line before insert) and the four bypass sites above — and change the 0.01 tolerance to an exact zero check on rounded integers.
Migration needed: **Yes** for true integer cents; No for the interim hardening.
Historical data affected: **Yes** — float artifacts already stored.

---

### P1 — CONFIRMED BUGS / SERIOUS RISKS

---

**ACC-16 — Purchase Orders are posted to the GL and to AP at commitment, not at goods receipt (root cause of FACT 7)**
Severity: **P1**
`server/src/models/PurchaseOrder.ts:170-191`; the author documents the choice at `accountingService.ts:390-397` ("Posted at PO creation in this implementation; in stricter systems you'd post at goods receipt instead").

On `status === 'Submitted'`, `create` writes a `supplier_ledger` DEBIT with `transaction_type='PURCHASE_ORDER'` (`:171-179`) **and** calls `postPurchaseOrderEntry` (`:184-190`) → Dr 1200 Inventory / Cr 2000 AP.
Why it matters: A PO is a commitment, not a liability, and no goods have arrived so there is no inventory asset. AP and Inventory are both overstated from the moment of submission. It also creates a **double-count vector with ACC-02**: if a PO is submitted *and* the goods are then recorded via `Purchase.recordPurchase`, the supplier ledger receives **two debits** (`PURCHASE_ORDER` then `PURCHASE`) for the same economic event. FACT 7 confirms both types are present in the live data.
Failure scenario: 100,000 PO submitted, then received as a purchase → supplier appears to be owed 200,000. Overpayment.
Fix: Post at goods receipt. If commitment tracking is wanted, use a memo/encumbrance table outside the GL. At minimum, make `recordPurchase` detect and reverse a prior `PURCHASE_ORDER` ledger debit for the same PO.
Migration needed: **Yes** — dedupe existing double debits.
Historical data affected: **Yes**.

---

**ACC-17 — `cancelInvoice` deliberately leaves PAYMENT lines active, driving AR negative**
Severity: **P1**
`server/src/controllers/invoiceController.ts:713-728`

```ts
// Do NOT void PAYMENT or INVOICE_RETURN lines — those are still valid
// adjustments. The CANCELLATION ledger entry below handles the AR offset.
AccountingService.voidJournalLinesByReference(db, 'INVOICE', invoiceId);
```

Why it matters: The comment is a subledger-level rationalisation applied to a GL problem. Voiding `INVOICE` removes the **Dr 1100 AR** while leaving the payment's **Cr 1100 AR** active. Net effect on the GL: AR is credited with nothing debiting it. **This is a direct, code-confirmed cause of FACT 2's -780 negative Accounts Receivable.** The compensating `CANCELLATION` row is written to `customer_ledger`, which the GL does not read.
Failure scenario: Cancel a paid invoice → GL AR goes negative, GL Cash still holds the receipt, and the Trial Balance no longer balances. Repeat and AR drifts arbitrarily negative.
Fix: Either post a proper GL cancellation entry (Dr 4000 Revenue / Cr 1100 AR, plus a COGS reversal), or refuse to cancel invoices with payments and require a credit note / refund instead.
Migration needed: No. Historical data affected: **Yes**.

---

**ACC-18 — `invoice_items.amount` ignores discount and tax; header total comes from the client (root cause of the invoice-24 0.2 discrepancy)**
Severity: **P1**
`server/src/models/Invoice.ts:731` and `server/src/controllers/invoiceController.ts:179`

```ts
const amount = multiplyCurrency(item.quantity, item.unit_price);
```
```ts
const totalAmountNum = parseCurrency(total_amount);   // ← from req.body
```

Why it matters: `invoice_items` has `tax_rate`, `discount_type`, and `discount_value` columns (added by `migrations/add-invoice-discount-tax-fields.sql`) and `createInvoiceItem` **stores** them — but `amount` is computed as bare `quantity * unit_price`, ignoring all three. Simultaneously the header `total_amount` is taken **verbatim from the request body** and never validated against the lines. The two are computed by different code in different places (one server, one client), so they diverge by construction. Your invoice 24 (header 1367 vs. line sum 1366.8) is the client having applied rounding or a discount the server did not. Note `postInvoiceEntry` debits AR with the **header** figure while `postCOGSEntry` uses the server-computed FIFO cost — so revenue is client-controlled and COGS is not.
Failure scenario: A malicious or buggy client posts `total_amount: 1` with 100,000 of line items. The server accepts it, AR is debited 1, revenue is understated by 99,999, and stock is still consumed. This is also a **money-integrity security hole**, not just a rounding bug.
Fix: Compute `amount` per line as `round(qty * unit_price - discount) * (1 + tax_rate/100)` (or split net/tax), compute the header as the sum of lines server-side, and **reject** any client-supplied `total_amount` that differs by more than 0.005. Do the same in POS (`posController.ts:73`) and mobile (`MobileInvoice.ts:205-210`).
Migration needed: **Yes** — recompute existing `invoice_items.amount` and reconcile headers.
Historical data affected: **Yes** — invoice 24 is confirmed; likely many more.

---

**ACC-19 — Tax is plumbed but never populated (root cause of FACT 9)**
Severity: **P1**
`server/src/controllers/invoiceController.ts:299-302`

```ts
const computedTaxAmount = items.reduce<number>((sum, item) => {
  const lineAmount = item.quantity * item.unit_price;
  return sum + lineAmount * ((item.tax_rate || 0) / 100);
}, 0);
```

Why it matters: The machinery is correct and complete — `postInvoiceEntry` splits Cr 2100 Tax Payable when `taxAmount > 0` (`accountingService.ts:318-335`). But (a) nothing populates `invoice_items.tax_rate` (0 rows have a non-zero value), (b) the 5 rows in `tax_rates` are never joined to invoice creation anywhere, and (c) POS, mobile, and SO-conversion do not even reach this code. Result: **account 2100 has zero activity and the business is under-reporting tax liability**. `Reports.getTaxSummary` (`Reports.ts:812-816`) computes tax ad hoc from `invoice_items`, so it too reports zero — the failure is self-concealing.
Failure scenario: Tax return filed at zero. Regulatory exposure.
Fix: Wire `tax_rates` into item pricing so `tax_rate` is populated at invoice-line creation; apply it in `createInvoiceItem`'s `amount` (see ACC-18); extend to POS/mobile/SO.
Migration needed: Likely (historical tax reconstruction). Historical data affected: **Yes**.

---

**ACC-20 — `deleteLedgerEntryByReference` has no `customer_id` predicate — cross-customer data loss**
Severity: **P1**
`server/src/models/Invoice.ts:891-893` (quoted in ACC-14)

Why it matters: Deletes by `reference_no` alone. `invoice_no` has a UNIQUE constraint so invoice references are safe *today*, but the same function is called with **payment numbers** (`invoiceController.ts:643`) and `customer_ledger.reference_no` also carries `CANCELLATION` and `RETURN` references. Any reference_no collision — including a manually entered or imported reference — silently deletes another customer's ledger rows. Same class of defect at `Payment.ts:462-463`.
Failure scenario: Two customers' ledgers both hold `reference_no='REF-001'`. Deleting one invoice wipes the other customer's row. No error, no log.
Fix: Add `AND customer_id = ?` (and stop deleting at all — see ACC-14).
Migration needed: No. Historical data affected: Possible but **UNVERIFIED**.

---

**ACC-21 — Dead code: the payment-cleanup branch in `deleteInvoice` can never execute**
Severity: **P1** (confirmed logic bug)
`server/src/controllers/invoiceController.ts:636-649` + `server/src/models/Payment.ts:493-495`

```ts
for (const alloc of allocations) {
  const otherAllocations = PaymentModel.getAllocationsByPaymentId(db, alloc.payment_id);
  if (otherAllocations.length === 0) {
    ... voidJournalLinesByReference(db, 'PAYMENT', alloc.payment_id);
    PaymentModel.delete(db, alloc.payment_id);
  }
}
```
```ts
static getAllocationsByPaymentId(db, paymentId) {
  return db.prepare('SELECT invoice_id FROM payment_allocations WHERE payment_id = ?').all(paymentId);
}
```

Why it matters: `getAllocationsByPaymentId` returns **all** allocations for that payment — **including `alloc` itself**, which still exists at this point. So `otherAllocations.length` is always `>= 1` and the `=== 0` branch is unreachable. The variable name reveals the intent: the author meant "allocations *other than this invoice's*". The block that voids PAYMENT GL lines and deletes the orphaned payment therefore **never runs**.
Failure scenario: Only reachable if `invoices.paid_amount` is stale (0) while `payment_allocations` rows exist — which the derived-vs-stored divergence in ACC-13 makes possible. Then the invoice is deleted while its payment, its payment ledger row, and its active `PAYMENT` GL lines survive as orphans.
Fix: `getAllocationsByPaymentId(...).filter(a => a.invoice_id !== invoiceId)`, or add an `excludeInvoiceId` parameter.
Migration needed: No. Historical data affected: Possibly — this is a strong candidate for FACT 5.

---

**ACC-22 — There is no reversing-entry mechanism; voiding is an in-place mutation with no audit metadata**
Severity: **P1**
`server/src/services/accountingService.ts:787-800`

```ts
const result = db.prepare(`
  UPDATE journal_lines SET voided = 1
  WHERE reference_type = ? AND reference_id = ? AND voided = 0
`).run(referenceType, referenceId);
```

Why it matters: The soft-void approach itself is **correct** and I recommend keeping it (see PART 3). The gap is that it records **no `voided_at`, no `voided_by`, and no reason**, and there is **no function anywhere that generates a reversing journal entry**. In a period-closed system you cannot mutate a posted entry — you must post an equal-and-opposite entry in the current open period. Because this system voids in place, voiding a transaction dated inside a *closed* period silently rewrites closed-period figures. A previously-filed Trial Balance will not reproduce.
Failure scenario: August is closed and reported. In September someone cancels an August invoice. Re-running the August TB now returns different numbers than were filed.
Fix: Add `voided_at`, `voided_by`, `void_reason` to `journal_lines` immediately (cheap, high value). Then add `postReversalEntry(originalEntryId, reversalDate)` that posts opposite lines dated in the current open period, and use it instead of in-place voiding once periods are actually being closed.
Migration needed: **Yes** (three columns).
Historical data affected: **Yes** — existing voids have no attribution.

---

**ACC-23 — Period close is enforced in exactly one place and gates almost nothing (Task 7 answer)**
Severity: **P1**
`server/src/services/accountingService.ts:226-237`; documented at `server/src/models/Period.ts:5-14`

Grep result: the **only** enforcement of `accounting_periods` on any write is the `postEntry` gate. Specifically **not** gated:
- `StockMovement.postFinancialEntryForAdjustment` (`StockMovement.ts:379-384`) — writes `journal_entries` with no period check
- `StockMovement.postFinancialEntryForProduction` (`StockMovement.ts:443-454`) — same
- `PhysicalCount` variance posting (`PhysicalCount.ts:345-357`) — same
- **All** `customer_ledger` and `supplier_ledger` writes
- All `invoices`, `payments`, `purchases`, `expenses` inserts and updates

Also: `accountingController.openPeriod` validates overlap **only against periods with `status='open'`** — so you can create a new period that overlaps an already-**closed** one, at which point `postEntry`'s `WHERE status='open' AND start_date <= ? AND end_date >= ?` matches and postings flow into a closed month. And `Period.ts:11-13` documents that closed periods cannot be reopened via the API, which combined with ACC-11 means a mistake is unrecoverable without direct DB access.
Failure scenario: August is closed. A user records an August expense, a stock adjustment, and a supplier payment. All three succeed. August's reported figures change after filing.
Fix: Extract the period check into shared middleware/helper and call it from every financial write path (including the legacy `journal_entries` writers). Fix `openPeriod` overlap validation to consider **all** periods regardless of status.
Migration needed: No. Historical data affected: N/A.

---

**ACC-24 — No owner capital, drawings, or retained-earnings postings exist; `opening_balances` is disconnected from the GL (Task 8 answer)**
Severity: **P1**
`server/src/services/cashService.ts:153-174`

Grep across `server/src` for `owners_equity`, `capital`, `drawing`, `retained`: the **only** hits are the seeded chart rows (3000 Owner's Equity, 3100 Retained Earnings in `migrations/add-gl-foundation.sql`) and the `settings['opening_retained_earnings']` key read by `Reports.getBalanceSheet:646-677`. **No code ever posts to 3000 or 3100.** That is why FACT 2 shows zero activity on both.

The `opening_balances` table has exactly two consumers — `getOpeningBalances` (`cashService.ts:153-158`) and `saveOpeningBalance` (`:161-174`) — and is used purely to seed a dashboard cash figure. It never becomes a journal entry, so the GL has no opening position at all.
Why it matters: Without equity postings the accounting equation cannot hold; the GL starts from an implicit zero net worth. Owner contributions and withdrawals are entirely untracked — a Pakistani SME context where the owner routinely moves cash in and out makes this a material control gap. There is also **no year-end closing procedure**: nothing rolls P&L accounts into 3100.
Failure scenario: Owner withdraws 100,000 cash. No record exists. Cash reconciliation fails and the shortfall is indistinguishable from theft.
Fix: (1) Post opening balances as a real opening journal entry (Dr assets / Cr liabilities / Cr 3000 for the plug). (2) Add Capital Contribution (Dr cash / Cr 3000) and Drawings (Dr 3200 Drawings / Cr cash) transaction types. (3) Add a year-end close that posts net P&L to 3100.
Migration needed: **Yes** (3200 Drawings account + opening entry).
Historical data affected: **Yes** — no opening position exists.

---

**ACC-25 — `Reports.getGeneralLedger` returns the customer subledger, not the general ledger**
Severity: **P1**
`server/src/models/Reports.ts:775-779`

```ts
return db.prepare(`SELECT * FROM customer_ledger WHERE transaction_date BETWEEN ? AND ?`)
  .all(startDate, endDate);
```

Why it matters: An endpoint named "General Ledger" returns AR subledger rows only — no cash, no inventory, no expenses, and none of `journal_lines`. Combined with ACC-12, `transaction_date` is always the insert date, so the date filter does not do what it appears to. Anyone using this to verify the books will conclude the GL is fine.
Fix: Rename to `getCustomerLedger` and implement a real GL report over `journal_lines` UNION `journal_entries` joined to `chart_of_accounts`.
Migration needed: No. Historical data affected: N/A.

---

**ACC-26 — Balance Sheet cash reads only account 1000, ignoring bank and all four mobile wallets**
Severity: **P1**
`server/src/models/Reports.ts:619-625`

Cash is fetched via `AccountingService.getAccountByTextCode(db, 'cash')` — account **1000 only**. But `_cashOrBankAccountCode` (`accountingService.ts:441-451`) routes payments to 1010 Bank, 1020 Easypaisa, 1030 JazzCash, and 1040 Upaisa depending on `payment_method`, and defaults **everything unrecognised to 1010**.
Why it matters: Any payment not literally by `'cash'` lands in an account the Balance Sheet cannot see. Bank and wallet balances are invisible; total assets are understated by their full amount.
Failure scenario: Business takes 500,000 through JazzCash. Balance Sheet shows zero cash movement.
Fix: Sum all accounts of type Asset with a cash/bank subtype (add an `is_cash_equivalent` flag to `chart_of_accounts`).
Migration needed: **Yes** (one column + seed). Historical data affected: N/A (reporting).

---

**ACC-27 — Legacy inventory postings use `standard_cost`, not actual batch cost**
Severity: **P1**
`server/src/models/StockMovement.ts:358-365`

`postFinancialEntryForAdjustment` values the adjustment at `item.standard_cost`, while sales value COGS at actual FIFO batch cost via `postCOGSEntry`. Same for `PhysicalCount.ts:345-357`.
Why it matters: Inventory is debited at one cost basis and credited at another, so account 1200 accumulates a permanent, un-diagnosable variance independent of ACC-02. This is a second contributor to the -3,276.2.
Fix: Value adjustments at batch cost (the batch is known — `stock_movements.batch_id`), or post the difference to 7100 Inventory Correction.
Migration needed: No. Historical data affected: **Yes** — 44 rows, 72,800.

---

**ACC-28 — The `'adjust'` return disposition creates payments and ledger rows with no GL posting**
Severity: **P1**
`server/src/controllers/invoiceController.ts:773-1227` (dispositions), GL calls only at `:929-938` and `:963-969`

The `refund` and `credit` dispositions reach `postInvoiceReturnEntry` / `postCOGSReversalEntry`. The `adjust` disposition creates `payments` rows and `PAYMENT` `customer_ledger` rows (a synthetic settlement) **without any GL posting**. Cash/AR effects are recorded in the subledger only.
Fix: Post the adjustment (Dr 1100 AR / Cr 1100 AR is a no-op — the correct treatment is to post the return entry and offset it against the receivable in the GL as well).
Migration needed: **Yes** — backfill. Historical data affected: **Yes**.

---

### P2 — RISKS AND MAINTAINABILITY

**ACC-29 — Duplicate, divergent `createLedgerEntry` implementations.** `server/src/utils/ledgerUtils.ts:9-42` and `server/src/models/Invoice.ts:777-806` are near-identical copies, both carrying the ACC-12 defects. `Invoice.ts:810-812` `updateCustomerBalance` is a **no-op stub** whose body comment claims "Balance is recalculated from ledger entries — no action needed here", which is false — callers who use this one instead of `ledgerUtils.updateCustomerBalance` silently skip the balance update. Fix: delete both duplicates, keep one. Migration: No. Historical: possible silent skips (**UNVERIFIED** which callers).

**ACC-30 — `Customer.addOpeningBalanceLedger` breaks the balance chain.** `server/src/models/Customer.ts:213-229` inserts with `balance = openingBalance` directly, ignoring any existing rows. If called on a customer with history, every subsequent stored balance is wrong until a rebuild. Fix: chain from the prior balance, or run `rebuildLedgerBalances` after.

**ACC-31 — `SupplierLedger` running balance uses raw float arithmetic.** `server/src/models/SupplierLedger.ts:34`: `const newBalance = currentBalance + debit - credit;` — the only balance computation in the codebase that does not use the `currency.ts` helpers. Compounds ACC-15.

**ACC-32 — `SupplierLedger.getBalance` defends `id`-as-chronology in a comment.** `server/src/models/SupplierLedger.ts:63-76` — `ORDER BY id DESC LIMIT 1`, with the comment "id order = insertion order = ledger chronology." FACT 7 disproves this: PAY009 (20,000) was written before its purchase order row. The assumption is stated, documented, and false. Same class as ACC-12.

**ACC-33 — `postEntry`'s group-id generation is not concurrency-safe across processes.** `accountingService.ts:251-254` reads `MAX(journal_entry_id)+1` **outside** the insert transaction. Within a single `better-sqlite3` process this is safe (synchronous, single-threaded) — but two server processes or a concurrent script would produce colliding group ids with no UNIQUE constraint to stop them. Fix: use a proper sequence, or move the read inside the transaction and add a unique index on `(journal_entry_id, account_id, debit, credit)`. Severity is P2 only because single-process deployment is the norm here — **UNVERIFIED** whether this deployment is single-process.

**ACC-34 — `journal_lines` has no FK to source documents.** Coupling is via `(reference_type, reference_id)` strings with no constraint, which is why orphaned lines pointing at invoices 6/7/8 are *structurally permitted*. `invoice_items` correctly uses `ON DELETE CASCADE` (`migrations/init.sql:257`) but `journal_lines` cannot, since `reference_id` is polymorphic. Fix: add a scheduled/on-demand orphan-detection report — cheap, and it would have caught FACT 5 on day one.

**ACC-35 — GL foundation migration re-runs on every boot inside a swallowing try/catch.** `server/src/config/database.ts:1398-1410` reads and `db.exec`s `add-gl-foundation.sql` at every start; failures are logged only. Combined with ACC-11, a partially-applied GL schema would be invisible except in the log.

**ACC-36 — The GL is not exposed to custom reports.** `server/src/services/reportQueryEngine.ts` (581 lines) builds SQL from `entityRegistry`, which has **no** entity for `journal_lines`, `journal_entries`, or `chart_of_accounts`. Users cannot build any report that would reveal the GL's state. Not a bug, but it removes the last chance of detection.

**ACC-37 — Reports recompute the same figures from source tables three separate ways.** `Reports.getBalanceSheet:646-677`, `getIncomeStatement:716-731` → `getProfitLossReport`, and `getGrossProfit:830-834` each independently re-derive revenue/COGS from `invoices`/`stock_movements`/`expenses`. Three implementations will drift. Fix: single source.

---

## PART 3 — WHAT IS CORRECT (DO NOT CHANGE)

These are the load-bearing, well-built parts. Preserve them; build the fixes on top of them.

1. **`postEntry` validation is genuinely sound.** `accountingService.ts:184-223` — requires >= 2 lines, rejects negative amounts, enforces debit-XOR-credit per line, rejects zero-amount lines, verifies each `account_id` exists in `chart_of_accounts`, and throws when `Math.abs(totalDebit - totalCredit) > 0.01`. Change only the tolerance (ACC-15); the structure is right.

2. **`journal_lines` DDL enforces the invariants at the database level.** `migrations/add-gl-foundation.sql` — `CHECK (debit = 0 OR credit = 0)` and `CHECK (debit >= 0 AND credit >= 0)`. Correct and worth keeping.

3. **Soft-voiding via `voided = 1` is the right primitive.** `accountingService.ts:787-800`. Do **not** replace it with deletes. It only needs attribution columns (ACC-22).

4. **`voided = 0` filtering is applied consistently on every `journal_lines` read.** Verified by exhaustive grep: outside `accountingService.ts` the only `journal_lines` references are void calls (`invoiceController.ts:645/656/659/717`, `PurchaseReturn.ts:527`), comments, and tests. `getAccountBalance` (`accountingService.ts:109-160`) filters `voided = 0` on **both** legs of the UNION. There is no read path that includes voided rows. This is correct.

5. **`getTrialBalance` DOES read BOTH GL tables — it does not silently omit half the data.** `Reports.ts:733-773` delegates to `AccountingService.getAllAccountBalances`, and `getAccountBalance` (`accountingService.ts:109-160`) UNIONs `journal_lines` (by `account_id`, `line_date <= ?`, `voided = 0`) with `journal_entries` (matched by `chart_of_accounts.text_code` against `debit_account`/`credit_account`). I verified every text code written to `journal_entries` — `inventory_asset`, `inventory_shrinkage`, `inventory_correction`, `production_clearing` — has a matching `text_code` in the seeded chart, so nothing is dropped by a failed match. **Direct answer to your question: the trial balance is complete with respect to both tables.** Its wrongness comes entirely from transactions that were never posted to *either* table (ACC-02 through ACC-07), not from a reporting gap. The self-documenting `note` field at `Reports.ts:768-772` accurately states this. This is the single most trustworthy report in the system.

6. **The salary payment path is fully and correctly wired — the reference implementation.** `controllers/employeeController.ts:229-248`: posts via `postSalaryEntry` inside the transaction, wraps it in try/catch that **rethrows** with a clear `GL posting failed: ...` message rather than swallowing, and persists the returned `journal_entry_id` back onto `salary_payments`. Every other money-mutating path should be refactored to look like this one.

7. **The purchase return path is correctly wired for both posting and reversal.** `models/PurchaseReturn.ts:~437-446` calls `postPurchaseReturnEntry` (Dr 2000 AP / Cr 1200 Inventory) keyed to the return header, and `voidReturn` at `:527` calls `voidJournalLinesByReference(db, 'PURCHASE_RETURN', id)`, plus reverses stock, batch coverage, the credit note, and the supplier ledger. It is the only document type in the system with a complete, symmetric create-and-void lifecycle. It also has real test coverage (`__tests__/purchaseReturn.test.ts:238`, `:389` assert on `journal_lines`). **Use this as the template for the other document types.**

8. **`Purchase.delete` correctly refuses to delete a purchase with recorded payments.** `models/Purchase.ts:455-462` — blocks and instructs the caller to reverse payments first, preventing orphaned allocations. Exactly the right guard; `deleteInvoice` has the equivalent (`invoiceController.ts:620-624`), though ACC-21 undermines it.

9. **`postEntry` opens a nested `db.transaction`, which `better-sqlite3` implements as a SAVEPOINT.** Calling it from inside a caller's transaction is safe and correct — all lines commit or none, and a GL failure rolls back the whole business transaction. That atomicity is desirable; the ACC-11 outage is caused by the period gate, not by the transaction nesting.

10. **The chart of accounts is well designed.** 17 accounts with sensible numbering, `normal_balance`, and a `text_code` column specifically to bridge legacy `journal_entries`. Accounts already exist for everything currently unposted (2000 AP, 6000 Operating Expenses, 2100 Tax Payable, 3000/3100 Equity). The fixes above require almost no new accounts.

11. **`accountingController.ts` is clean.** 348 lines of thin, correct REST delegation. `openPeriod`/`closePeriod` are admin-gated, validate ISO dates, and `closePeriod` is idempotent. `listAccountBalances:103-113` correctly computes and exposes a `balanced` flag. The only defect is the overlap-validation scope (ACC-23).

12. **`sanitizeSortParams` whitelisting is applied on ledger and list queries** (`Customer.getLedger:231-272`, `Purchase.getAll:332-339`). The SQL-injection tests at `__tests__/security.regression.test.ts:252` pass. Ordering is a correctness problem (ACC-12), not an injection problem.

---

## PART 4 — UNVERIFIED

I could not confirm these in code. Stated explicitly rather than speculated.

**UNVERIFIED-1 — The exact code path that orphaned FACT 5's 12 active `journal_lines` for invoices 6, 7, 8.**
What I verified conclusively:
- There is exactly **one** `DELETE FROM invoices` in the entire codebase: `models/Invoice.ts:913`, reachable only from `invoiceController.deleteInvoice`.
- That path **does** void: `voidJournalLinesByReference(db,'INVOICE',invoiceId)` at `invoiceController.ts:656` and `'INVOICE_RETURN'` at `:659`.
- `invoices` has **no** `ON DELETE CASCADE` from `customers` (`migrations/init.sql:230-248`), so a customer deletion cannot cascade-delete invoices.
- There is **no** `DELETE FROM journal_lines` anywhere.
- `git log` shows a single squashed `518dce7 "Initial commit"` dated 2026-08-05, so **the history needed to test the "older revision" hypothesis does not exist in this repo**.
- The 12 lines / 3 invoices = 4 lines each, consistent with `postInvoiceEntry` (2) + `postCOGSEntry` (2) — so these were created by the normal invoice path, and the 685 of debits is AR + COGS.

Ranked hypotheses, none provable from code alone:
(a) **ACC-21's dead code**, if `invoices.paid_amount` was stale — the only currently-reachable in-code mechanism.
(b) **ACC-09** (`Payment.delete`) followed by an invoice delete — `Payment.delete` definitively does not void, so it is a proven orphan-producer, though for `PAYMENT` lines rather than `INVOICE` lines.
(c) Deletion by a pre-squash code revision, before the void calls at `:656`/`:659` were added.
(d) Direct/manual DB manipulation or an ad-hoc script (the three files in `server/src/scripts/` — `backfill-batches.ts`, `fix-duplicate-purchase.ts`, `reconcile-stock-cash.ts` — were grepped and contain **no** references to `invoices` or `journal_lines`, so they are excluded).
To resolve: query `activity_log` for `action='DELETE' AND entity_type='Invoice' AND entity_id IN (6,7,8)`. If rows exist with a user and timestamp, hypothesis (c) or (a). If absent, hypothesis (d).

**UNVERIFIED-2 — Whether ACC-20's missing `customer_id` predicate has already destroyed data.** Requires a reference_no collision check across `customer_ledger`.

**UNVERIFIED-3 — Whether the ACC-29 no-op `Invoice.updateCustomerBalance` stub is actually called anywhere.** I confirmed it exists and is a no-op; I did not enumerate its callers.

**UNVERIFIED-4 — Deployment process count** (bears on ACC-33's severity).

**UNVERIFIED-5 — Flutter client behaviour.** This audit covered `server/src` only. ACC-18 makes the client the authority for `total_amount`, so the client's rounding logic is part of the money path. It was out of scope and is unexamined.

---

## PART 5 — FACT → ROOT CAUSE MAP

| Fact | Root cause | Finding |
|---|---|---|
| 1. Two parallel GL tables | Deliberate dual-writer design, documented at `accountingService.ts:12-22`; independent id spaces at `:251-254` | ACC-01 |
| 2. Inventory -3,276.2 | COGS credits 1200; purchases never debit it; adjustments use `standard_cost` | ACC-02, ACC-27 |
| 2. AR -780 | `cancelInvoice` voids the AR debit but keeps the payment's AR credit; POS/mobile/SO never debit AR | ACC-17, ACC-05, ACC-06, ACC-07 |
| 2. Cash debit-only | Supplier payments never credit cash | ACC-03 |
| 2. AP/Equity/Expenses/Tax all zero | No posting code exists for purchases, expenses, or equity; tax_rate always 0 | ACC-02, ACC-04, ACC-24, ACC-19 |
| 3. 27,500 cash paid, no GL credit | `Payment.createSupplierPayment` has no `AccountingService` call | ACC-03 |
| 4. Purchases post nothing; `financial_posted=0` | `Purchase.recordPurchase` has no `AccountingService` call; column never set | ACC-02 |
| 5. Orphaned active lines for invoices 6,7,8 | **UNVERIFIED** — `deleteInvoice` does void; candidates are ACC-21 dead code, ACC-09, or pre-squash code | UNVERIFIED-1 |
| 5. Invoices 9-23 correctly voided | `invoiceController.ts:656/659` working as intended | (correct) |
| 6. Ledger balance jumps 600 → -600 → 0 | `ORDER BY id DESC` chain + `date('now')` overriding the document date | ACC-12 |
| 6. Three different customer balances | Four independent writers on four different bases | ACC-13 |
| 7. `PURCHASE_ORDER` debits + `PURCHASE` debits | PO submit posts AP at commitment; `recordPurchase` posts again at receipt | ACC-16 |
| 7. PAY009 written before its PO row | `ORDER BY id DESC` chronology; no date ordering enforced on `supplier_ledger` | ACC-32 |
| 8. `customer_ledger` ids 16-31 missing | Three hard-DELETE sites | ACC-14 |
| 8. `"(updated)"` description | `updateInvoice` delete-and-reinsert at `invoiceController.ts:572-573` | ACC-08 |
| 9. Tax never posted | Nothing populates `invoice_items.tax_rate`; `tax_rates` table never joined | ACC-19 |
| 10. `accounting_periods` exists | Enforced only in `postEntry`; auto-opens only the current month | ACC-23, ACC-11 |
| Invoice 24: header 1367 vs. lines 1366.8 | `invoice_items.amount = qty * unit_price` ignoring discount/tax; header taken from client body | ACC-18 |
| Money stored as mixed INTEGER/REAL | Floats end-to-end; no integer cents; four sites bypass `roundCurrency` | ACC-15 |

---

## PART 6 — REMEDIATION ORDER

**Fix this week, before anything else:** ACC-11. It is a dated outage that will halt all trading on 2026-09-01 and it is a ~10-line change.

**Then, highest value per unit of effort:** ACC-10's reconciliation report. Build a page that diffs each GL account balance against its operational derivation. It changes nothing and it makes every other defect on this list visible and measurable — including whichever ones I have not found.

**Then, in order:** ACC-18 (client-controlled revenue is a money-integrity hole, not just rounding) → ACC-03 + ACC-02 (the two largest GL holes) → ACC-09 + ACC-08 (stop creating new orphans) → ACC-12 + ACC-13 (ledger truth) → ACC-05/06/07 (route the three bypass paths through the shared posting sequence) → ACC-14 + ACC-22 (append-only ledger, void attribution) → ACC-24 (equity) → ACC-01 (table unification, largest and least urgent).

Model the refactors on `models/PurchaseReturn.ts` and `controllers/employeeController.ts:229-248` — both are already correct.

agentId: a8bb74c0cde1f86c0 (use SendMessage with to: 'a8bb74c0cde1f86c0', summary: '<5-10 word recap>' to continue this agent)
<usage>subagent_tokens: 93274
tool_uses: 50
duration_ms: 1994948</usage>