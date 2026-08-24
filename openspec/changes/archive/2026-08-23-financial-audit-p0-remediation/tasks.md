# Tasks: financial-audit-p0-remediation

## 1. Cash truth (CASH-01/02/03/04)

- [x] 1.1 Delete the direct-purchase outflow block from `collectFlows` (`server/src/services/cashService.ts:125-131`) and the drill-down purchase loop (`:294-305`)
- [x] 1.2 Rewrite `normalizeCashMethod` as explicit whitelist (cash/easypaisa/jazzcash/upaisa; bank-like set → 'bank'; credit → null; else `'unclassified'`); make `add()`/`push()` treat `unclassified` as a real bucket
- [x] 1.3 Render `unclassified` as a flagged row in the reconciliation report (`Reports.ts` getCashReconciliation + Flutter `cash_reconciliation_screen.dart` warning chip)
- [x] 1.4 Validate payment method on create/update in `PaymentModel.create`/`update` + controller (400 listing valid methods); migration `normalize-payment-methods.sql`: blank→'Cash', NOT NULL DEFAULT 'Cash' on `payments.payment_method` and `expenses.payment_method`
- [x] 1.5 Change `POST /reports/cash-reconciliation` to `requirePermission('reports','create')`; seed `reports:create` for admin+manager when absent
- [x] 1.6 Tests: unpaid purchase moves cash 0; paid purchase moves exactly once; unknown method → unclassified row; reconciliation POST 403 without write permission

## 2. Payments immutability + guards (PAY-04/09/10/11, PAY-06 residue)

- [x] 2.1 `Payment.update`: throw on amount change ("void this payment and record a new one"); remove proportional rescaling block; keep method-change GL void+repost; controller maps to 400
- [x] 2.2 XOR counterparty guard in `paymentsController.createPayment` (`!!customer_id === !!supplier_id` → 400)
- [x] 2.3 Migration `add-payments-counterparty-check.sql`: rebuild payments with CHECK `(customer_id IS NULL) <> (supplier_id IS NULL)` using runtime `pragma_table_info` column copy (pattern from audit-remediation task 3.1) + regression test asserting copy-list matches table_info
- [x] 2.4 Migration `backfill-payments-po-id.sql`: single-distinct-po_id payments with zero purchase_allocations get purchase_order_id; idempotent NULL predicate; activity_log count
- [x] 2.5 Implement `POST /payments/:id/allocate`: validate remainder-equality ±0.01, customer ownership, per-invoice balance_amount cap; transactional insert + invoice balance recalculation; permission `payments:update`; replace 501 stub
- [x] 2.6 Receipt previous-balance from payment's own ledger row (customer: `balance + credit − debit`; supplier: `balance + debit − credit`), fallback only when no ledger row
- [x] 2.7 Flutter: disable amount field in payment edit dialog with void-and-reissue hint; smoke-test receipt reprint shows era-correct previous balance
- [x] 2.8 Tests: amount-edit 400 both counterparties; XOR guard; allocate happy/sad; receipt previous balance equals pre-payment ledger balance

## 3. Purchase void lifecycle (PUR-03, PUR-02 residue)

- [x] 3.1 Migration `add-purchase-void-columns.sql`: `voided_at TEXT`, `voided_by INTEGER REFERENCES users(id)`, `void_reason TEXT` on purchases
- [x] 3.2 Implement `Purchase.void(id, userId, reason)`: guards (open return rows, returned_quantity>0, remaining<original−0.01, allocation guard), subledger append-only reversal, `voidJournalLinesByReference('PURCHASE',id)`, ADJUSTMENT for remaining units only, batch zeroed, void columns stamped, activity_log with reason — all in one transaction
- [x] 3.3 Route cutover: remove DELETE `/api/purchases/:id`, add POST `/api/purchases/:id/void` (reason required); delete hard-delete code path
- [x] 3.4 Replace ambiguous batch re-query at `Purchase.ts:172-176` with insert-result `lastInsertRowid`; sweep other write-path re-queries of `(source_type='PURCHASE', source_id)`
- [x] 3.5 Flutter: purchase row menu void action with reason prompt; verify list refresh and void badge display
- [x] 3.6 Tests: sold-stock void refused; returned-stock void refused; clean void reverses ledger+GL in balance; lastInsertRowid identity under simulated GR-id collision

## 4. Purchase returns correctness (PRET-01..05, PRET-06 disposition part)

- [x] 4.1 Aggregate request lines by `(source_type, source_item_id)` before headroom validation; reject conflicting unit_cost duplicates; atomic headroom re-check inside the UPDATE
- [x] 4.2 Source-batch consumption: direct purchase → its PURCHASE batch; PO line → GOODS_RECEIPT batch of that goods_receipt_item; shortfall → throw naming deficit (no silent under-consume)
- [x] 4.3 Supplier resolution via FK only (`purchases.supplier_id` / `purchase_orders.supplier_id`); unresolved → throw pre-write; delete name lookup; pair every `createEntry` with `rebuildBalances` in create + voidReturn
- [x] 4.4 Migration `add-purchase-return-batches.sql`: `purchase_return_batches(return_line_id, batch_id, quantity)` + index; persist consumption during create; voidReturn restores exactly those rows
- [x] 4.5 Disposition guard: return value exceeding unpaid balance requires `credit_on_account`|`refund_expected`, recorded on credit note; refuse otherwise
- [x] 4.6 Tests: duplicate-line over-return rejected; short coverage throws; renamed supplier credited via FK; create→void stock value-identity; overpaid return without disposition fails

## 5. AP reports + expense lifecycle (PAY-07, EXP-03/04/05)

- [x] 5.1 Rewrite `getAPAgingReport`/`getAPSummary` over non-voided supplier_ledger (net debits−credits per supplier, aged by debit document dates, POs + direct purchases); payload declares `basis:'supplier_ledger'`; wire unchanged routes
- [x] 5.2 Expense status state machine: whitelist five statuses (400 otherwise), default Draft, ignore client status on create, transition matrix incl. terminal states, Approved/Paid immutable except Cancelled, `expenses:approve` gate into Approved/Paid; seed that permission
- [x] 5.3 Validate `expense_category` against `expense_categories` on write (400 on miss)
- [x] 5.4 Atomic numbering: `getNextSequenceNumber(db,'EXP_last_no_YYYYMM')` inside create transaction; migration seeds counters from existing max suffixes; remove hard `deleteExpense` route (Cancelled replaces deletion)
- [x] 5.5 Flutter expense form: no status field on create; detail dialog gets transition actions respecting matrix + permission; verify ≤768px layout
- [x] 5.6 Tests: AP reports execute on fresh schema matching fixture totals; invalid status/category 400; Draft default; illegal transition 400; approve without permission 403; concurrent numbering monotonic

## 6. Verification + cleanup

- [x] 6.1 Run `npm run typecheck` and `npm run lint` — zero errors; run full jest suite green
- [x] 6.2 Boot server against a copy of live DB: migrations apply once, second boot is no-op; expected-cash card reflects corrected math; AP screens load with data
- [x] 6.3 Flutter analyze + targeted widget checks for changed dialogs; desktop and mobile layouts verified
- [x] 6.4 Remove dead code: old rescaler, name-based supplier lookup, DELETE purchase route handler, MAX-scan numbering; confirm no unused imports/aliases remain
