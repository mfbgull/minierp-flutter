# Proposal: financial-audit-p0-remediation

## Why

The 2026-08-23 payments/purchases/returns/expenses/cash forensic audit (`opus5-audit-report/payments.md`) found 27 defects, 11 of them P0. Several of its headline findings were already remediated by two in-flight changes — `audit-remediation` (payments table rebuild data loss, GL void-on-delete) and `gl-posting-completeness` (purchases/expenses/supplier-payments now post to the GL; PO commitment posting removed). What remains is verified against current source and live data: the cash till is wrong **today** by ₨500 and doubles on payment (CASH-01), `Payment.update` still rescales allocations past invoice balances with no supplier-side guard (PAY-04), purchase hard-delete still silently writes off sold stock (PUR-03), purchase returns validate duplicate lines pre-write and FIFO-consume the wrong batches (PRET-01/02), supplier resolution falls back to a name lookup that skips the ledger on miss (PRET-03), both AP reports 500 on every call because they query nonexistent columns (PAY-07), reconciliation saves are gated by a read permission (CASH-04), expenses default to `Approved` with a client-supplied free-text status and a non-atomic document number (EXP-03/05), and the create-payment guard admits both counterparty types then silently discards the supplier (PAY-09).

## What Changes

- **Cash**: delete both direct-purchase blocks from `cashService` (`collectFlows` + drill-down); cash out for purchases is already captured by supplier payments via `purchase_allocations`. Whitelist payment methods; unknown methods land in an `unclassified` bucket shown by the reconciliation report instead of silently becoming bank. Require a write permission to save cash reconciliations.
- **Payments**: forbid amount edits on any allocated payment (void-and-reissue policy); add XOR counterparty guard plus DB CHECK constraint; backfill `payments.purchase_order_id` from `po_allocations`; derive receipt "previous balance" from the payment's own ledger row; implement the manual allocation endpoint.
- **Purchases**: convert hard delete to void (`voided_at/by/reason`) guarded against returns and consumed stock; fix batch lookup ambiguity by using `lastInsertRowid` at insert; group top-suppliers by id.
- **Purchase returns**: aggregate request lines per source item before validating; consume only the source document's own batch and refuse short coverage; resolve suppliers by FK or roll back; rebuild balances after every ledger entry; persist per-line batch consumption so void restores exactly.
- **Expenses**: whitelist statuses with a transition matrix, default `Draft`, lock Approved/Paid documents behind a reversal path; validate category against `expense_categories`; generate numbers via `getNextSequenceNumber` inside the create transaction.
- **Reports**: rewrite AP aging/summary over reachable statuses and `total_amount − po_allocations`, UNIONed with live purchases; add an integration test executing every report SQL against a fresh schema.

## Capabilities

### New Capabilities
- `cash-method-normalization`: payment methods normalize through an explicit whitelist; unknown values surface as an `unclassified` bucket rather than silently counting as bank.
- `document-void-lifecycle`: purchases (and expense reversals) are voided with attribution, never hard-deleted while downstream value remains.

### Modified Capabilities
- `purchase-returns`: adds same-source-item aggregation validation, source-batch-exact stock consumption with short-coverage refusal, FK-based supplier resolution that fails closed, balance rebuild after every ledger write, persisted per-line batch consumption for exact void restoration.
- `supplier-payment-po-link`: adds backfill of `purchase_order_id` for existing single-PO payments and a CHECK constraint enforcing exactly-one-counterparty on new rows.
- `authz-hardening`: cash-reconciliation saves move from `reports:read` to a write permission.
- `gl-posting-matrix`: payment amount edits are forbidden on allocated payments (void-and-reissue replaces re-post-on-edit).

## Impact

- **Server code**: `services/cashService.ts`, `models/Payment.ts`, `models/Purchase.ts`, `models/PurchaseReturn.ts`, `models/PurchaseOrder.ts` (batch restamp follow-ups), `models/Expense.ts`, `controllers/{paymentsController,expenseController,paymentsController}.ts`, `models/Reports.ts`.
- **Database**: additive migrations only — CHECK constraint on payments (table rebuild executed with full column copy per audit-remediation's fixed pattern), `voided_at/by/reason` on `purchases`, settings counters seeded from max expense number. No destructive schema change; no historical GL backfill required (verified: every non-voided journal line resolves to a live document).
- **Flutter client**: expense form dialog status default changes to Draft; payment edit UI must route amount changes through void-and-reissue. No API contract breaks; allocate endpoint is additive.
- **Risk notes**: deleting the cashService purchase blocks changes dashboard expected-cash figures immediately (by design — they are wrong today); void-and-reissue removes a capability users may rely on (accepted: silent three-way desync is worse).
