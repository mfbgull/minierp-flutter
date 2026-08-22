# Spec: gl-posting-matrix (Delta)

## ADDED Requirements

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
Invoice update SHALL void and re-post its INVOICE and COGS journal lines. Payment deletion SHALL void the payment's PAYMENT lines. Payment update with an amount change SHALL void and re-post. Invoice deletion SHALL run its orphaned-payment cleanup branch (payments whose only allocation was the deleted invoice are removed and their GL lines voided).

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
