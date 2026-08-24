# gl-posting-matrix Specification

## Purpose

Every financial document type posts a complete, balanced journal entry at the
economically correct moment, and every mutation path voids or re-posts what it
invalidates.

## Requirements


### Requirement: Every financial document posts a balanced GL entry
Each of the following SHALL produce a complete, balanced `journal_lines` entry through `AccountingService.postEntry` inside the document's own transaction: direct purchases, supplier payments, expenses, POS sales, mobile invoices, and sales-order-to-invoice conversion. Each entry SHALL use the seeded chart accounts (1200 Inventory Asset, 2000 Accounts Payable, 6000 Operating Expenses, 4000 Sales Revenue, 5000 COGS, 1100 AR, cash-per-method 1000/1010/1020/1030/1040).

#### Scenario: Direct purchase on credit
- **WHEN** a purchase is recorded with no immediate payment
- **THEN** journal lines exist debiting 1200 Inventory Asset and crediting 2000 Accounts Payable for the total cost
- **AND** the entry balances to zero within rounding tolerance

#### Scenario: Supplier payment credits the correct cash account
- **WHEN** a supplier payment is created with payment_method 'jazzcash'
- **THEN** journal lines debit 2000 AP and credit 1030 for the payment amount

#### Scenario: Expense posting
- **WHEN** an expense is created
- **THEN** journal lines debit 6000 Operating Expenses and credit the resolved cash account

#### Scenario: POS sale posts revenue, COGS, and payment entries
- **WHEN** a POS sale completes
- **THEN** the same three postings made by the standard invoice path exist (invoice entry, COGS entry at actual FIFO cost, payment entry)
- **AND** all are voided together when the sale is reversed

#### Scenario: Mobile invoice submission posts like a standard invoice
- **WHEN** a mobile invoice is submitted
- **THEN** invoice, COGS, and payment GL entries exist referencing that invoice id

#### Scenario: SO conversion produces subledger row as well as GL entry
- **WHEN** a sales order is converted to an invoice
- **THEN** a customer_ledger INVOICE row exists for the converted amount
- **AND** the GL postings exist inside the conversion transaction

### Requirement: Mutations keep the GL consistent with documents
Invoice update SHALL void and re-post its INVOICE and COGS journal lines. Payment deletion SHALL void the payment's PAYMENT lines. Payment amount changes are PROHIBITED: `Payment.update` SHALL reject any request changing `amount` with 400, instructing void-and-reissue; date, method, reference, and notes edits remain permitted, with method changes keeping void+repost at the unchanged amount. Invoice deletion SHALL run its orphaned-payment cleanup branch (payments whose only allocation was the deleted invoice are removed and their GL lines voided).

#### Scenario: Invoice edit re-posts the GL
- **WHEN** an invoice's total is changed from 1,000 to 2,000 via update
- **THEN** the old INVOICE journal lines have voided = 1 and new active lines total 2,000

#### Scenario: Payment delete leaves no orphaned lines
- **WHEN** a customer payment is deleted via DELETE /api/payments/:id
- **THEN** no non-voided journal_lines rows reference that payment

#### Scenario: Orphan cleanup branch executes
- **WHEN** an invoice is deleted whose payment had no other allocations
- **THEN** that payment row is deleted and its PAYMENT GL lines are voided in the same transaction

#### Scenario: Amount edit refused on allocated payment
- **WHEN** a payment update supplies a different amount for a fully allocated payment
- **THEN** the response is 400 explaining void-and-reissue; allocations, invoice paid_amount, supplier_ledger credit, and suppliers.current_balance all remain untouched and consistent

### Requirement: Receipt previous balance reflects payment-time state
A receipt's "previous balance" SHALL be derived from the payment's own ledger row (stored running balance net of that row's movement), not from today's counterparty balance. Fallback to current-balance arithmetic only when no ledger row exists.

#### Scenario: Reprinting an old receipt shows its era
- **WHEN** a receipt printed weeks ago is reprinted after many later transactions
- **THEN** its previous balance equals the counterparty balance just before that payment posted

### Requirement: Manual allocation endpoint exists
`POST /api/payments/:id/allocate` SHALL accept additional invoice allocations for a partially allocated payment, validating total equality within tolerance, invoice ownership by the payment's customer, per-invoice cap at balance_amount, gated by `payments:update`, applied transactionally with invoice balance recalculation.

#### Scenario: Legacy partially-allocated payment can be finished
- **WHEN** a valid allocation set covering the unallocated remainder is posted
- **THEN** payment_allocations rows appear, affected invoices' balances update, and over-cap requests fail 400


#### Scenario: Invoice edit re-posts the GL
- **WHEN** an invoice's total is changed from 1,000 to 2,000 via update
- **THEN** the old INVOICE journal lines have voided = 1 and new active lines total 2,000

#### Scenario: Payment delete leaves no orphaned lines
- **WHEN** a customer payment is deleted via DELETE /api/payments/:id
- **THEN** no non-voided journal_lines rows reference that payment

#### Scenario: Orphan cleanup branch executes
- **WHEN** an invoice is deleted whose payment had no other allocations
- **THEN** that payment row is deleted and its PAYMENT GL lines are voided in the same transaction

### Requirement: POs post at goods receipt, not commitment
Purchase-order submission SHALL NOT create GL entries or supplier-ledger debits. The purchase-recording flow SHALL be the sole poster of the inventory/AP (or cash) entry. Existing double-postings (a PURCHASE_ORDER ledger debit later followed by a PURCHASE debit for the same supplier and order) SHALL be deduplicated by an idempotent backfill that reverses the redundant commitment debit.

#### Scenario: PO submission posts nothing
- **WHEN** a purchase order reaches status Submitted
- **THEN** no journal_lines row and no supplier_ledger row is written for it

#### Scenario: Goods received once, posted once
- **WHEN** goods for a submitted PO are recorded via recordPurchase
- **THEN** exactly one Dr Inventory / Cr AP entry exists for that economic event
- **AND** any pre-existing PURCHASE_ORDER supplier-ledger debit for the same PO has been reversed by the backfill

### Requirement: Void operations carry attribution
`journal_lines` SHALL record `voided_at`, `voided_by`, and `void_reason` when lines are voided by mutation paths. Pre-existing voids MAY retain NULL attribution.

#### Scenario: Update voids are attributed
- **WHEN** an invoice update voids old GL lines
- **THEN** those lines carry the acting user id and timestamp

### Requirement: Pre-posting documents are backfilled into the GL
A one-time, idempotent, ledgered migration SHALL post balanced journal entries for financial documents created before live posting was enabled: direct purchases (debit 1200 / credit 2000), supplier payments (debit 2000 / credit method cash account), customer payments lacking GL lines (debit method cash account / credit 1100), expenses (debit 6000 / credit method cash account), and an opening-equity entry reconciling the residual to the operational opening balances. Backfill entries SHALL be marked (e.g. `reference_type = 'BACKFILL'`) so they are identifiable and never re-applied.

#### Scenario: Migration is idempotent
- **WHEN** the backfill migration runs twice
- **THEN** the second run inserts no journal lines and leaves balances unchanged

#### Scenario: Historical trial balance becomes sane
- **WHEN** the backfill completes on the audited live data
- **THEN** Inventory Asset (1200) and Accounts Payable (2000) carry positive, plausible balances instead of −69,015 / zero activity, and debits still equal credits

#### Scenario: Opening equity closes the residual
- **WHEN** all document backfills are posted and a residual difference remains against operational cash/opening balances
- **THEN** a single Owner's Equity (3000) entry absorbs it exactly once, and the balance sheet balances within 0.01

### Requirement: Cash service reads expected balances from the GL
`cashService` SHALL derive each method family's expected balance from its GL cash account (1000–1040) instead of independently re-aggregating payments/expenses/salary payments; its transaction classification remains for flow breakdowns only. Dashboard cash, cash-flow report, cash reconciliation and the balance sheet SHALL therefore agree by construction.

#### Scenario: One cash number everywhere
- **WHEN** any user compares the dashboard cash card, cash-flow report, cash reconciliation and balance sheet in one session
- **THEN** all show the same per-method and total cash figures
