# Design: financial-audit-p0-remediation

## Context

The payments/purchases/returns/expenses/cash audit (2026-08-23) overlaps heavily with two in-flight remediation changes. Verified current state:

- **Already fixed elsewhere**: GL posting for purchases/supplier-payments/expenses (`gl-posting-completeness`, archived); PO commitment posting removed; `Payment.delete` voids journal lines and reverses subledger rows append-only, scoped by counterparty+type; `deleted_payments` ownership guard + activity logging in `invoiceController`; `stock_batches` CHECK-widened with restamp migration for `GOODS_RECEIPT`/`RECON` rows; payments rebuild now copies all columns and `invoice_id` is recovered from `payment_allocations`.
- **Still broken, verified today**: `cashService.ts:125-131` and `:294-305` subtract every purchase's `total_cost` from the cash till unconditionally while `purchase_allocations` is empty — live till understated by 500 and will double-drain on payment. `normalizeCashMethod` returns `'bank'` as catch-all. `POST /cash-reconciliation` gated by `reports:read`. `Payment.update` rescales allocations proportionally with no invoice-balance validation and no supplier-side handling. `Purchase.delete` hard-deletes with only an allocation guard. Batch lookup at `Purchase.ts:172-176` re-queries by ambiguous `(source_type='PURCHASE', source_id)`. `PurchaseReturn.create` validates duplicate source lines against pre-request counters, consumes FIFO-oldest batches regardless of origin, silently under-consumes when coverage is short, resolves suppliers by name with a warn-and-skip on miss, never calls `rebuildBalances`, and voids restore stock to whatever batch the void logic picks. AP aging/summary query nonexistent columns (`balance_amount`, `due_date`, `total_cost`) → 500 on every call. Expenses: status free-text defaulting to `Approved`, category free text despite a seeded table, non-atomic `MAX(expense_no)` numbering outside any transaction. `paymentsController.createPayment` uses `||` instead of XOR for counterparty presence; `POST /payments/:id/allocate` returns 501; receipt "previous balance" = current balance + payment amount.
- **Live data**: 3 supplier payments fully allocated via `po_allocations` but `purchase_order_id` NULL (backfill needed); 1 expense (`Approved`, Cash); `purchases` table has **0 rows** (36 historical purchases already hard-deleted); `purchase_returns` empty; every non-voided journal line resolves to a live document.

Constraints from repo rules: layered architecture unchanged; prepared statements only; transactional writes; migration required per schema change; no `any`.

## Goals / Non-Goals

**Goals:**
1. Expected cash stops lying: remove double-count, surface unclassifiable methods, protect reconciliation records.
2. Money documents are immutable once they have downstream effects: no amount edits past allocations, no purchase hard-delete, exact void restoration for returns.
3. Purchase returns cannot lose money on first real use: aggregate validation, exact batch consumption, fail-closed supplier resolution, balance consistency.
4. AP reports return correct numbers over reachable statuses.
5. Expense lifecycle is a state machine, not a free string.
6. Regression tests pin each fix to observable money behavior.

**Non-Goals:**
- Full GL backfill/rebuild of deleted history (nothing recoverable remains).
- Unifying `purchases` vs `purchase_orders+goods_receipts` into one authoritative model (audit PUR-05 — large architectural change, separately planned).
- Owner drawings / capital injection / inter-account transfer tables (CASH-05).
- Credit-note refund workflow and negative supplier payments in cashService (PRET-06).
- Integer-cents money migration; customer `credit_balance` spend path (PAY-10 remainder).
- Reconciliation immutability/append-only re-count rows (needs UI; permission fix ships now).

## Decisions

### D1 — Delete the direct-purchase cash blocks entirely (CASH-01)
Remove both blocks (`collectFlows` aggregate + drill-down loop). Rationale: cash out for purchases is already captured by supplier payments allocated through `purchase_allocations`/`po_allocations`; keeping a "quick cash purchase" shortcut would require adding `purchases.payment_method` plus auto-created supplier payments — new write-path complexity to preserve a wrong number. Alternative rejected: conditional inclusion via a paid-flag (no such column exists; inventing one duplicates the allocation truth source). Drill-down loses its `type:'purchase'` row — acceptable; supplier payments remain visible there. With 0 live purchases the fix changes expected cash by ₨0 today; it prevents the wrong numbers from returning.

### D2 — Explicit method whitelist + `unclassified` bucket (CASH-02/03)
`normalizeCashMethod`: `{cash, easypaisa, jazzcash, upaisa}` map to themselves; bank-like set `{bank, check, cheque, card, online, transfer}` → `'bank'`; `'credit'` → null; anything else → `'unclassified'` sentinel that flows through `add()`/`push()` like a real bucket. The reconciliation report renders it as its own row flagged for attention instead of silently folding into bank. Write-path validation: payment create/update reject methods outside whitelist ∪ {credit} with 400 listing valid values. Migration: blank/null → `'Cash'`, then NOT NULL DEFAULT 'Cash' on `payments.payment_method` and `expenses.payment_method`. All live rows are 'Cash', so nothing shifts buckets at deploy.

### D3 — Reconciliation saves behind `reports:create` (CASH-04)
Change the POST route permission to `reports:create`; seed it for admin and manager roles if absent. Permission-first is the P1; append-only re-count rows need Flutter work and are explicitly deferred.

### D4 — Void-and-reissue replaces payment amount editing (PAY-04)
`Payment.update`: `data.amount !== undefined && data.amount !== existing.amount` → throw; controller maps to 400 "Amount edits are not allowed — void this payment and record a new one". Applies to both counterparties: proportional rescaling cannot validate against invoice balances mid-loop, and supplier `po_allocations`/`purchase_allocations`/ledger credit were never maintained by the old code. Date/method/reference/notes edits stay allowed; method changes keep the existing GL void+repost, which stays correct because amount is fixed. Alternatives rejected: full re-validation of rescaled allocations (keeps three-way supplier desync alive); silent clamp (hides intent). Flutter: payment edit dialog disables the amount field with explanatory text.

### D5 — XOR counterparty guard + DB CHECK (PAY-09)
Controller: `if (!!parsedCustomerId === !!parsedSupplierId)` → 400 "Exactly one of customer_id or supplier_id is required". Schema: payments table rebuild adding `CHECK ((customer_id IS NULL) <> (supplier_id IS NULL))`, executed strictly with the fixed copy-all-columns pattern from audit-remediation task 3.1 (column list derived from `pragma_table_info(payments)` at runtime inside the migration, foreign_keys pragma restored in `finally`). Live data is clean (verified), so the constraint is safe immediately.

### D6 — Backfill `purchase_order_id` from `po_allocations` (PAY-06 residue)
Ledgered data migration mirroring `recoverPaymentsInvoiceId()` (`database.ts:2400`): payments with exactly one distinct `po_allocations.po_id` and zero `purchase_allocations` get `purchase_order_id` set; predicate `WHERE purchase_order_id IS NULL` keeps it idempotent; activity_log row records count. Recovers PAY001/PAY002/PAY009. Satisfies the existing `supplier-payment-po-link` spec's backfill expectation without touching balance math.

### D7 — Receipt previous balance from own ledger row (PAY-11)
Replace `currentBalance + amount`: select the payment's ledger row (`customer_ledger`/`supplier_ledger` WHERE reference_no = payment_no AND transaction_type='PAYMENT' AND voided=0), previous balance = stored `balance` net of that row's own movement (customer: `balance + credit − debit`; supplier: `balance + debit − credit`). Fallback to old arithmetic only when no ledger row exists (legacy rows). Receipt output shape unchanged — Flutter needs nothing.

### D8 — Manual allocation endpoint implemented (PAY-10)
`POST /payments/:id/allocate` accepts `{allocations:[{invoice_id, amount}]}`; validates sum == payment amount − currently allocated (±0.01), each invoice open and owned by the payment's customer, per-invoice cap at `balance_amount`; inserts `payment_allocations` rows in a transaction, then recalculates affected invoice balances. The create-time fully-allocated guard stays; this endpoint lets an operator finish allocating partially-allocated legacy payments. Permission: `payments:update`.

### D9 — Purchase void instead of hard delete (PUR-03)
Migration adds `voided_at TEXT`, `voided_by INTEGER REFERENCES users(id)`, `void_reason TEXT` to `purchases`. New `Purchase.void(id, userId, reason)` replaces delete semantics:
- Guards (each throws): non-voided `purchase_returns` row against the purchase; `returned_quantity > 0`; `quantity_remaining < quantity_original − 0.01` (stock already sold); existing allocation guard kept.
- Actions inside one transaction: append-only reversal of the subledger PURCHASE row (existing pattern); `AccountingService.voidJournalLinesByReference(db,'PURCHASE',id)`; ADJUSTMENT movement for remaining quantity only; batch `quantity_remaining=0`; stamp void columns; activity_log with reason.
Route cutover: DELETE `/api/purchases/:id` removed, POST `/api/purchases/:id/void` added with required reason body; Flutter purchase row menu calls void with a reason prompt. Hard DELETE statement disappears from the model. The already-deleted 36 purchases stay gone; no backfill attempted.

### D10 — Batch identity from `lastInsertRowid` (PUR-02 residue)
`recordPurchase` takes the batch id from the INSERT's `lastInsertRowid` instead of re-querying `(source_type='PURCHASE', source_id=purchaseId)`; same replacement wherever the ambiguous re-query survives in write paths. Read-path lookups keyed by `source_type='PURCHASE'` are safe post-restamp because GR batches now carry `'GOODS_RECEIPT'`.

### D11 — Purchase return correctness bundle (PRET-01..05)
1. **Aggregate validation**: group request lines by `(source_type, source_item_id)`, sum quantities, validate the aggregate against `returned_quantity` headroom read inside the transaction; conflicting unit_cost across duplicate lines → 400.
2. **Source-batch consumption**: direct purchase consumes `source_type='PURCHASE' AND source_id=<purchase id>`; PO line consumes `source_type='GOODS_RECEIPT' AND source_id=<goods_receipt_item id>`. Coverage < requested quantity → throw naming the shortfall; never silently under-consume.
3. **Supplier resolution fail-closed**: use `purchases.supplier_id` / `purchase_orders.supplier_id` exclusively; unresolved → throw before any write. Name lookup deleted; credit note always gets its ledger entry plus `rebuildBalances(supplierId)`.
4. **Balance consistency**: every `createEntry` site pairs with `rebuildBalances` (create and voidReturn paths).
5. **Exact void restoration**: new table `purchase_return_batches(return_line_id, batch_id, quantity)` populated during create; `voidReturn` restores exactly those batches (MAX(0,…) clamp retained as belt-and-braces). Additive migration; empty live table means zero backfill.

### D12 — AP reports rebuilt on supplier_ledger (PAY-07)
Both reports re-derived from `supplier_ledger` positions — the audited single source that already reconciles — instead of PO header columns that do not exist. Outstanding = sum of non-voided debits minus credits per supplier (FIFO-style netting within supplier for aging buckets, bucketed by the debit document dates); includes direct-purchase `'PURCHASE'` debits automatically; no status filter needed (the ledger has none). Summary = per-supplier net outstanding > 0. Replaces the dead SQL wholesale and removes the broken `payments.purchase_order_id` join. Response payload declares `basis: 'supplier_ledger'`. Integration test executes both against a schema-fresh seeded DB asserting known totals.

### D13 — Expense lifecycle state machine (EXP-03/04)
Statuses fixed to `{Draft, Submitted, Approved, Paid, Cancelled}` validated server-side (400 on anything else; behavioral validation chosen over CHECK table-rebuild). Default on create: `Draft`; controller stops accepting client-supplied status entirely. Transition matrix: Draft→Submitted|Cancelled; Submitted→Approved|Cancelled; Approved→Paid|Cancelled; Paid and Cancelled terminal. Transitions into Approved/Paid require `expenses:approve` permission; Approved/Paid documents reject field edits except via Cancelled-then-reissue. Category: validate `expense_category` against `expense_categories.name` on write (400 on miss); FK normalization deferred (single live row). Flutter expense form: status picker removed on create; transition actions on detail dialog.

### D14 — Atomic expense numbering (EXP-05)
Replace MAX-scan with `getNextSequenceNumber(db, 'EXP_last_no_YYYYMM')` called in the same transaction as the INSERT (controller wraps numbering+create in `db.transaction`). One-off migration seeds counters from max `EXP-*` suffix per month prefix so numbering continues rather than colliding; UNIQUE on `expense_no` makes residual mistakes loud. Hard `deleteExpense` route removed — Cancelled terminal state replaces deletion (clean cutover).

### D15 — Test strategy
Jest suites under `server/src/__tests__/`, mirroring existing conventions (fresh `:memory:` DB helper, minimal seeded fixtures):
- cash: unpaid purchase does not move expected cash; paid purchase moves it exactly once; unknown method → `unclassified`; reconciliation POST rejects without `reports:create`.
- payments: amount-edit 400; XOR guard; allocate endpoint happy/sad; receipt previous-balance equals pre-payment ledger balance.
- purchases: void blocks when sold or returned; batch id from lastInsertRowid under simulated GR-id collision.
- returns: duplicate-line over-return rejected; short coverage throws; renamed supplier still credited via FK; create→void is value-identity on stock.
- expenses: invalid status/category 400; Draft default; transition matrix incl. permission gate; numbering monotonic.
- reports: AP aging/summary execute and match fixture totals (regression for the permanent 500s).

## Risks / Trade-offs

- [Void-and-reissue breaks workflows relying on amount edits] → Error states the exact remedy; Flutter edit dialog explains before submit; two clicks vs silent three-book desync.
- [Removing purchase cash block changes dashboard numbers] → Numbers become correct; reconciliation report shows supplier payments as sole purchase-side drain; zero live purchases means no visible shift at deploy.
- [Payments table rebuild repeats PAY-06 class bug] → Column list generated from `pragma_table_info` at runtime, not hand-maintained; test asserts copy-list matches table_info and roundtrips all columns.
- [AP report semantics change (PO-based → ledger-based)] → Old reports never worked (500); basis declared in payload; figures reconcile with supplier list by construction.
- [Expense status default change surprises users] → Create dialog omits status (was invisible anyway); approval becomes explicit, matching audit control intent.
- [`unclassified` bucket appears in reconciliation] → Visible warning is the feature; runbook note says clear it by correcting the payment method.

## Migration Plan

All migrations run through the ledgered runner (audit-remediation §2), forward-only:
1. `add-payments-counterparty-check.sql` — rebuild `payments`, runtime-derived column copy + CHECK.
2. `add-purchase-void-columns.sql` — `voided_at/by/reason` on `purchases`.
3. `add-purchase-return-batches.sql` — consumption ledger table + index on `return_line_id`.
4. `backfill-payments-po-id.sql` (data) — single-PO payments from `po_allocations`.
5. `normalize-payment-methods.sql` (data + DDL) — blank→'Cash'; NOT NULL DEFAULT on both method columns.
6. `seed-expense-sequence.sql` (data) — settings counters from existing max suffixes.

Order matters only for 4–6 after 1; runner preserves listed order. Rollback: forward-only like all ledgered migrations; documented recovery is restore-from-backup (`db-backup-recovery` spec covers backup cadence).

## Open Questions

None blocking. Two consciously deferred items are recorded as Non-Goals rather than open questions: reconciliation immutability rows and the purchases-vs-PO model unification.
