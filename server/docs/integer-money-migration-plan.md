# Integer Money Migration Plan — MiniERP

**Status:** DESIGN / PLANNING DOCUMENT — NOT IMPLEMENTED
**Scope:** `server/` (Node/TypeScript, better-sqlite3) + `lib/` (Flutter) in this monorepo
**Date:** 2026-09-27

This document designs the migration of every monetary value from SQLite
`DECIMAL`/`REAL`/`NUMERIC` columns (stored as IEEE-754 `double`, read into JS
`number`) into exact integer minor units. It contains **no production code
changes**. Every current-state claim cites `file:line`. Forward-looking design
decisions are marked **PROPOSAL**. Anything not verifiable from the repository
is marked **UNVERIFIED**.

---

## 1. Scope and non-goals

### 1.1 In scope

- All SQL columns holding money (see §2 inventory), across ~35 tables.
- All server-side money arithmetic: the `utils/currency.ts` helper set, the
  duplicated rounders in `Reports.ts` / `cashService.ts` / `OwnerWithdrawal.ts`
  / `OwnerCapital.ts`, and every raw `parseCurrency(x) - parseCurrency(y)`
  subtraction (see §3 inventory).
- Ledger running-balance chaining (`customer_ledger.balance`,
  `supplier_ledger.balance`) — a derived, drift-prone column (§3.2).
- The read surface: JSON API responses, SQL report aggregates (§4.1), and the
  Flutter presentation + calculation layer (§4.2), including client-side PDF
  generation.
- Historical data conversion, including detection of rows that are **already
  inconsistent** before any migration runs (§8).
- Schema migration mechanics (expand / backfill / contract) with rollback (§6).

### 1.2 Non-goals

- **Quantities are out of scope.** Stock quantities already have a
  precision-safe layer: `utils/quantity.ts` (`roundQty`, 3-dp, documented as
  matching `DECIMAL(15,3)`), with an explicit anti-pattern list at
  `utils/quantity.ts:1-30` that forbids "string conversion tricks
  (`Number(v + 'e+2')`)" and "inconsistent `Math.round(v * 100) / 100`
  patterns" — exactly the patterns `utils/currency.ts:8-11` still uses for
  money. Money should converge to the same discipline, but quantity columns
  (`DECIMAL(15,3)`) are not migrated here.
- **Tax *rates* are out of scope.** `invoice_items.tax_rate DECIMAL(5,2)`
  (`add-invoice-discount-tax-fields.sql:10`), `quotation_items.tax_rate`
  (`add-full-sales-cycle.sql:41`), `tax_rates.rate DECIMAL(5,2)`
  (`add-mobile-invoice-tables.sql:39`), `items.rounding_step REAL`
  (`add-loose-item-support.sql:5`) are percentages / steps, not money. They stay
  fractional; their *products* (tax amounts) are money and are in scope.
- **Multi-currency is out of scope.** The only currency-denoting column in the
  schema is `owner_personal_loans.currency VARCHAR(3) DEFAULT 'PKR'`
  (`add-owner-personal-loans.sql:43`). Exchange-rate support exists only as
  inert `settings` rows (`add-integration-settings.sql:30-33`: `currency_enabled`
  default `'false'`, `currency_api_key`, `currency_base`, update interval) with
  **no live exchange-rate table and no per-row currency on any money column**.
  The system is effectively single-currency PKR. **UNVERIFIED**: whether any
  front-end surface exposes the Fixer integration.
- **No behavioural change.** Rounding stays half-up at the cent; tolerances are
  preserved semantically (§7). The deliverable is representational exactness,
  not new business rules.
- **No test-suite runs, no migrations executed, no DB writes** were performed
  while producing this plan.

---

## 2. Monetary column inventory

SQLite applies **NUMERIC affinity** to `DECIMAL`/`NUMERIC` declarations and
stores them as `REAL` (float64); `REAL` declarations are float64 directly.
**None of the declared precisions are enforced** — a `DECIMAL(15,2)` column
will happily store `0.005`. Min/max below are the *declared* bounds; they are
the contract the integer migration must preserve, not a guarantee about stored
data.

Type groups found in the schema:

| Group | Declared type | Declared max (abs) | ×100 minor-unit max | JS-safe (< 2⁵³)? |
|---|---|---|---|---|
| A — money, 2 dp | `DECIMAL(15,2)` | 999,999,999,999.99 | 99,999,999,999,999 ≈ 1.0×10¹⁴ | ✅ yes |
| B — money, 4 dp | `DECIMAL(15,4)` | 999,999,999,999.9999 | at scale 10⁴: 9,999,999,999,999,999 ≈ 1.0×10¹⁶ | ❌ **NO** (exceeds 2⁵³ ≈ 9.007×10¹⁵) |
| C — money, 3 dp | `NUMERIC(15,3)` | 999,999,999,999.999 | at scale 10³: 999,999,999,999,999 ≈ 1.0×10¹⁵ | ✅ yes |
| D — money, bare `REAL` | `REAL` | unbounded (float64) | n/a | n/a |

**§2-critical finding (see §10 R1):** group B cannot be represented as exact
JS-safe integers at its *own* scale. Group D has no declared bound at all.

### 2.1 Sales — invoices and lines

| table.column | type | semantic | min/max (declared) | proposed (PROPOSAL) |
|---|---|---|---|---|
| `invoices.total_amount` | `DECIMAL(15,2)` `init.sql:238` | invoice grand total = Σ line amounts | 0 … 999999999999.99 | INTEGER (scale 100) |
| `invoices.paid_amount` | `DECIMAL(15,2)` `init.sql:239` | gross collected base (spec: refunds do not shrink it) | 0 … max | INTEGER (100) |
| `invoices.balance_amount` | `DECIMAL(15,2)` `init.sql:240` | total − paid (derived, clamped ≥ 0) | 0 … max | INTEGER (100) |
| `invoices.returned_amount` | `DECIMAL(15,2)` `add-returned-amount.sql:3` | gross returned value | 0 … max | INTEGER (100) |
| `invoices.credit_offset` | `DECIMAL(15,2)` `add-invoice-credit-offset.sql:5` | store credit applied at creation | 0 … max | INTEGER (100) |
| `invoices.discount_value` | `DECIMAL(15,2)` `add-invoice-discount-tax-fields.sql:6` | header discount (amount or % depending on `discount_type`) | 0 … max | INTEGER (100) |
| `invoices.return_fee` | added only programmatically at `config/database.ts:2175` (no `.sql`) | restocking fee | 0 … max | INTEGER (100) |
| `invoice_items.unit_price` | `DECIMAL(15,2)` `init.sql:256` | unit sale price | 0 … max | INTEGER (100) |
| `invoice_items.amount` | `DECIMAL(15,2)` `init.sql:257` | line total incl. tax, net of discount | 0 … max | INTEGER (100) |
| `invoice_items.net_amount` | `DECIMAL(15,2)` `add-invoice-item-tax-columns.sql:5` | line net (excl. tax) | 0 … max | INTEGER (100) |
| `invoice_items.tax_amount` | `DECIMAL(15,2)` `add-invoice-item-tax-columns.sql:6` | line tax (authoritative for GL, see `models/Invoice.ts:812-818`) | 0 … max | INTEGER (100) |
| `invoice_items.discount_value` | `DECIMAL(15,2)` `add-invoice-discount-tax-fields.sql:12` | line discount | 0 … max | INTEGER (100) |

### 2.2 Quotations and sales orders

| table.column | type | semantic | proposed (PROPOSAL) |
|---|---|---|---|
| `quotations.total_amount` | `DECIMAL(15,2)` `add-full-sales-cycle.sql:19` | quote total | INTEGER (100) |
| `quotation_items.unit_price` | `DECIMAL(15,2)` `add-full-sales-cycle.sql:38` | unit price | INTEGER (100) |
| `quotation_items.discount_value` | `DECIMAL(15,2)` `add-full-sales-cycle.sql:40` | line discount | INTEGER (100) |
| `quotation_items.amount` | `DECIMAL(15,2)` `add-full-sales-cycle.sql:42` | line total | INTEGER (100) |
| `sales_orders.total_amount` | `DECIMAL(15,2)` `init.sql:205` | order total | INTEGER (100) |
| `sales_order_items.unit_price` | `DECIMAL(15,2)` `init.sql:223` | unit price | INTEGER (100) |
| `sales_order_items.amount` | `DECIMAL(15,2)` `init.sql:224` | line total | INTEGER (100) |
| `sales.unit_price` | `DECIMAL(15,2)` `add-sales-table.sql:8` | sales-history unit price | INTEGER (100) |
| `sales.total_amount` | `DECIMAL(15,2)` `add-sales-table.sql:9` | sales-history total | INTEGER (100) |

### 2.3 Payments and allocations

| table.column | type | semantic | proposed (PROPOSAL) |
|---|---|---|---|
| `payments.amount` | `DECIMAL(15,2)` `init.sql:269` | payment header amount (signed in some refund paths — `services/PaymentRecordingService.ts:43` negates) | INTEGER (100) |
| `payment_allocations.amount` | `DECIMAL(15,2)` `create-payment-allocations.sql:8` | customer payment → invoice allocation | INTEGER (100) |
| `po_allocations.amount` | `DECIMAL(15,2)` `add-supplier-payment-support.sql:13` | supplier payment → PO allocation | INTEGER (100) |
| `purchase_allocations.amount` | `DECIMAL(15,2)` `add-purchase-supplier-payment.sql:14` | supplier payment → direct-purchase allocation | INTEGER (100) |

Note: `payments` also carries a migration-scoped rebuild copy `payments_nn.amount`
(`normalize-payment-methods.sql:19`) — temporary, dropped after rebuild; not
migrated.

### 2.4 Customer / supplier sub-ledgers and AR fields

| table.column | type | semantic | proposed (PROPOSAL) |
|---|---|---|---|
| `customer_ledger.debit` | `DECIMAL(15,2)` `create-customer-ledger.sql:10`, `customer-ar-migration.sql:17` | ledger debit | INTEGER (100) |
| `customer_ledger.credit` | `DECIMAL(15,2)` `create-customer-ledger.sql:11` | ledger credit | INTEGER (100) |
| `customer_ledger.balance` | `DECIMAL(15,2)` `create-customer-ledger.sql:12` | **derived** running balance (drift-prone — §3.2) | INTEGER (100), or drop and compute |
| `supplier_ledger.debit/credit/balance` | `DECIMAL(15,2)` `create-supplier-ledger.sql:10-12` | supplier ledger (same shape) | INTEGER (100) |
| `customers.credit_limit` | `DECIMAL(15,2)` `add-customer-ar-fields.sql:5`, `customer-ar-migration.sql:5` | AR credit limit | INTEGER (100) |
| `customers.current_balance` | `DECIMAL(15,2)` `add-customer-ar-fields.sql:6`, `customer-ar-migration.sql:6` | legacy AR balance (mirrors ledger net) | INTEGER (100) |
| `customers.opening_balance` | `DECIMAL(15,2)` `add-customer-ar-fields.sql:7`, `customer-ar-migration.sql:7` | AR opening seed | INTEGER (100) |
| `customers.credit_balance` | `DECIMAL(15,2)` `add-credit-balance.sql:5` | store credit (different representation — `models/Customer.ts:35-36`) | INTEGER (100) |

### 2.5 General ledger (group B — 4 dp, the hard case)

| table.column | type | semantic | proposed (PROPOSAL) |
|---|---|---|---|
| `journal_lines.debit` | `DECIMAL(15,4)` `add-gl-foundation.sql:61` | GL debit leg | **see §5.2** — scale decision required |
| `journal_lines.credit` | `DECIMAL(15,4)` `add-gl-foundation.sql:62` | GL credit leg | same |
| `journal_entries.amount` | `DECIMAL(15,4)` `add-stock-adjustment-financial.sql:15` | journal entry header amount | same |

All GL postings derive from 2-dp document values (see §3.4), so the 4th decimal
absorbs float noise rather than carrying business meaning — but that is an
inference, **UNVERIFIED** against a live DB.

### 2.6 Purchases, POs, receipts

| table.column | type | semantic | proposed (PROPOSAL) |
|---|---|---|---|
| `purchase_orders.total_amount` | `DECIMAL(15,2)` `init.sql:127` | PO total | INTEGER (100) |
| `purchase_order_items.unit_price` | `DECIMAL(15,2)` `init.sql:145` | PO unit price | INTEGER (100) |
| `purchase_order_items.amount` | `DECIMAL(15,2)` `init.sql:146` | PO line total | INTEGER (100) |
| `purchases.unit_cost` | `DECIMAL(15,2)` `add-purchases-table.sql:8` | direct-purchase unit cost | INTEGER (100) |
| `purchases.total_cost` | `DECIMAL(15,2)` `add-purchases-table.sql:9` | direct-purchase total | INTEGER (100) |

`goods_receipt_items.received_quantity` is a quantity (`DECIMAL(15,3)`,
`init.sql:171`), not money; its `unit_price` equivalent is read from
`purchase_order_items` at `models/PurchaseOrder.ts:997`.

### 2.7 Purchase returns / credit notes / supplier refunds (group C — 3 dp)

| table.column | type | semantic | proposed (PROPOSAL) |
|---|---|---|---|
| `purchase_returns.total_amount` | `NUMERIC(15,3)` `add-purchase-returns-tables.sql:32` | return total | **see §5.3** — 3-dp money |
| `purchase_return_items.unit_cost` | `NUMERIC(15,3)` `add-purchase-returns-tables.sql:56` | return unit cost | same |
| `purchase_return_items.amount` | `NUMERIC(15,3)` `add-purchase-returns-tables.sql:58` | return line amount | same |
| `credit_notes.amount` | `NUMERIC(15,3)` `add-purchase-returns-tables.sql:77` | supplier credit note value | same |
| `supplier_refunds.amount` | `NUMERIC(15,3)` `add-disposition-and-supplier-refunds.sql:26` | refund paid out | same |

(`purchase_returns.total_qty` `NUMERIC(15,3)` at `:31` is a quantity.)

### 2.8 Invoice returns / settlements (group D — bare REAL, no bound)

| table.column | type | semantic | proposed (PROPOSAL) |
|---|---|---|---|
| `invoice_returns.fee_value` | `REAL` `add-invoice-returns.sql:26` | fee input (10 = %, 150 = fixed) | INTEGER (100); note dual semantic |
| `invoice_returns.fee_amount` | `REAL` `add-invoice-returns.sql:27` | resolved fee | INTEGER (100) |
| `invoice_returns.returned_amount` | `REAL` `add-invoice-returns.sql:28` | gross returned | INTEGER (100) |
| `invoice_returns.net_amount` | `REAL` `add-invoice-returns.sql:29` | returned − fee | INTEGER (100) |
| `invoice_returns.settled_amount` | `REAL` `add-invoice-returns.sql:30` | Σ allocations (≤ net) | INTEGER (100) |
| `invoice_return_items.unit_price` | `REAL` `add-invoice-returns.sql:52` | original sale price (proportional mirror) | INTEGER (100) |
| `invoice_return_items.tax_amount` | `REAL` `add-invoice-returns.sql:53` | mirrored tax | INTEGER (100) |
| `invoice_return_items.line_amount` | `REAL` `CHECK (line_amount >= 0)` `add-invoice-returns.sql:54` | net of item discount, incl. tax | INTEGER (100) |
| `return_settlements.amount` | `REAL` `CHECK (amount > 0)` `add-invoice-returns.sql:69` | settlement (refund/credit/adjust) | INTEGER (100) |

### 2.9 Expenses, payroll, owner equity, loans

| table.column | type | semantic | proposed (PROPOSAL) |
|---|---|---|---|
| `expenses.amount` | `DECIMAL(15,2)` `add-expenses-table.sql:9` | expense amount | INTEGER (100) |
| `employees.salary` | `DECIMAL(15,2)` `add-employees-table.sql:23` | salary | INTEGER (100) |
| `salary_payments.amount` | `DECIMAL(15,2)` `add-salary-payments.sql:9` | salary payment | INTEGER (100) |
| `employee_loans.amount` | `REAL` `add-employee-loans.sql:21` | loan principal | INTEGER (100) |
| `employee_loans.balance` | `REAL` `add-employee-loans.sql:22` | remaining balance (derived) | INTEGER (100) |
| `employee_loans.monthly_installment` | `REAL` `add-employee-loans.sql:27` | suggested installment | INTEGER (100) |
| `employee_loans.written_off_amount` | `REAL` `add-employee-loans.sql:30` | forgiven amount | INTEGER (100) |
| `employee_loan_repayments.amount` | `REAL` `add-employee-loans.sql:47` | repayment | INTEGER (100) |
| `owner_capital.amount` | `DECIMAL(15,2)` `CHECK (amount > 0)` `add-owner-equity.sql:33` | capital injection | INTEGER (100) |
| `owner_withdrawals.amount` | `DECIMAL(15,2)` `CHECK (amount >= 0)` `add-owner-equity.sql:58` | withdrawal | INTEGER (100) |
| `owner_personal_loans.amount` | `DECIMAL(15,2)` `CHECK (amount > 0)` `add-owner-personal-loans.sql:41` | loan given | INTEGER (100) |
| `owner_personal_loan_repayments.amount` | `DECIMAL(15,2)` `CHECK (amount > 0)` `add-owner-personal-loans.sql:68` | repayment received | INTEGER (100) |

### 2.10 Inventory valuation / costing

| table.column | type | semantic | proposed (PROPOSAL) |
|---|---|---|---|
| `items.standard_cost` | `DECIMAL(15,2)` `init.sql:45` | standard cost | INTEGER (100) |
| `items.standard_selling_price` | `DECIMAL(15,2)` `init.sql:46` | list price | INTEGER (100) |
| `bom_items.unit_cost` | `DECIMAL(15,2)` `init.sql:305` | BOM line cost | INTEGER (100) |
| `stock_batches.unit_cost` | `DECIMAL(15,4)` `add-batch-costing.sql:15` | **group B** — batch unit cost (total/qty, fractional) | **see §5.2** |
| `stock_movements.unit_cost` | `DECIMAL(15,2)` `init.sql:76` | movement unit cost | INTEGER (100) |
| `stock_movements.financial_value` | `DECIMAL(15,4)` `add-stock-adjustment-financial.sql:34` | **group B** — movement value | **see §5.2** |
| `physical_count_items.unit_cost` | `DECIMAL(15,2)` `add-physical-counts.sql:30` | variance valuation cost | INTEGER (100) |
| `physical_count_items.variance_value` | `DECIMAL(15,2)` `add-physical-counts.sql:31` | variance × unit_cost | INTEGER (100) |
| `productions.overhead_cost` | `DECIMAL(15,2)` `add-production-tables.sql:11` | production overhead | INTEGER (100) |
| `productions.total_batch_cost` | `DECIMAL(15,4)` added programmatically at `config/database.ts:2237` (no `.sql`) | **group B** — batch cost | **see §5.2** |

`cash_reconciliations.expected_balance / counted_balance / variance`
(`DECIMAL(15,2)`, `add-cash-accounts.sql:29-31`) and
`opening_balances.amount` (`DECIMAL(15,2)`, `add-opening-balances.sql:9`) are
money; proposed INTEGER (100).

### 2.11 Naming inconsistencies (migration hazard)

- **`unit_price` vs `unit_cost`** carry the same semantic (per-unit money) across
  tables: `unit_price` in `invoice_items`/`sales_order_items`/`quotation_items`/
  `sales`/`invoice_return_items`; `unit_cost` in `purchases`/`purchase_return_items`/
  `stock_batches`/`physical_count_items`/`bom_items`/`stock_movements`.
  A shared integer-money column type must be applied to both spellings.
- **`productions.overhead_cost` is added twice** in `config/database.ts`
  (line 1835 and again in the 2235 region) — both guarded; harmless today but a
  trap for a migration that greps for single definitions.
- **`invoices.returned_amount` is defined twice**: by
  `add-returned-amount.sql:3` and again inside the programmatic GL-foundation
  block (`config/database.ts:2162`); `return_fee` exists **only** programmatically
  (`config/database.ts:2175`). A SQL-only migration under-counts columns unless
  it also scans `config/database.ts` programmatic `ALTER`s (lines 273, 276,
  280-283, 1238, 1465-1469, 1489, 1626-1635, 1835, 2119-2121, 2132, 2162, 2175,
  2188, 2223-2248, 2237).

---

## 3. Calculation and rounding inventory

### 3.1 The canonical helper (and its rounding mode)

`server/src/utils/currency.ts`:

| site | behaviour | risk |
|---|---|---|
| `:8-11` `roundCurrency` | `Number(Math.round(Number(value + 'e+2')) + 'e-2')` — **half-up** (JS `Math.round`), string round-trip | String conversion; diverges from `utils/quantity.ts:30` `Math.round(v*factor)/factor`; docstring at `:5` claims `Math.round(value*100)/100` but code does not |
| `:13-23` `addCurrency`/`subtractCurrency`/`multiplyCurrency` | round after each op | correct-but-dense call sites; easy to bypass (see §3.3) |
| `:54-77` `decomposeLineAmount` | gross = `amount` override **or** `qty × unit_price`; flat vs `%` discount clamped by `Math.min(discountAmount, gross)`; `tax = round(net × rate/100)` | per-line rounding accumulates Σ-tax ≠ tax-of-Σ; this is the ACC-18 decomposition the storage path uses (`models/Invoice.ts:789`) |
| `:90-103` `sumInvoiceLineTax` | Σ `decomposeLineAmount(...).taxAmount` | mirrors stored tax; must stay identical post-migration |
| `:108-120` `computeInvoiceTotal` | Σ `computeLineAmount` | header total = sum of rounded lines (no final re-round beyond `addCurrency`) |
| `:130-152` `computeInvoiceGrandTotal` | total with header discount | header discount allocation order matters |
| `:158-162` `parseCurrency` | coerces DB/JSON input to number | **this is the float-ingress point** — every `parseCurrency(column)` re-imports float noise |

### 3.2 Ledger running-balance chaining (drift source)

- `models/Invoice.ts:864-885` `createLedgerEntry`: reads last
  `customer_ledger.balance` (`:866-871`, `ORDER BY transaction_date DESC, id DESC`),
  then `newBalance = subtractCurrency(addCurrency(lastBalance, debit), credit)`
  (`:876`) and **stores it** (`:884`). The stored `balance` is derived; any
  out-of-order insert (backdated document) makes it disagree with
  `Σ(debit − credit)`.
- `utils/ledgerUtils.ts:35-38` (customer) and `:108-109` (reversal) repeat the
  same chaining.
- `utils/ledgerUtils.ts:275, 311-314` rebuild the supplier running balance;
  `:298-332` recompute from `Σ(debit) − Σ(credit)`. The `Σ` derivation is the
  robust one; the stored column is derived.
- Position math at `utils/ledgerUtils.ts:156-198`:
  `collections = addCurrency(totalPaid, creditOffset)` (`:166`);
  `owed = subtractCurrency(addCurrency(subtractCurrency(total, returned), fee), …)`
  (`:173-174`) — nested add/subtract, each rounding; order-dependent.
- **Risk:** integer migration must decide whether `balance` stays a stored column
  (and gets rebuilt in id order — the documented requirement for
  `SupplierLedgerModel.rebuildBalances`) or becomes computed-on-read (PROPOSAL §5.5).

### 3.3 Raw float arithmetic that bypasses the helpers (bugs today, breakage post-migration)

| site | current behaviour | risk |
|---|---|---|
| `services/paymentValidation.ts:39` | `parseCurrency(invoice.total_amount) - parseCurrency(invoice.returned_amount)` — **raw subtraction** | float residue in a *ceiling* used by `:74-81`; should be `subtractCurrency` |
| `controllers/posController.ts:78` | `change: cashReceived - total` — raw subtraction, **unrounded** | POS change amount can carry float dust into the response and into `Math.min(cashReceived, total)` at `:152` |
| `controllers/posController.ts:65,123` | `parseFloat(String(body.cash_received ?? '')) \|\| total` | `parseFloat` ingress; accepts `'10.005'` |
| `controllers/posController.ts:56` | SQL `ii.quantity * ii.unit_price AS line_total` — computed in SQL, never rounded | report-side line total can differ from stored `invoice_items.amount`; under integers this product mis-scales by 100× (§4.1) |
| `services/cashService.ts:368,380,456` | `Math.round(amount * 100) / 100` — a **third** independent rounder; `:368` is on the DB write path | diverges from `roundCurrency`; same pattern `utils/quantity.ts:25-30` explicitly lists as an anti-pattern |
| `models/Reports.ts:74` | `const r2 = (v) => Math.round(v * 100) / 100` | report rounder ≠ `roundCurrency`; applied to `opening_balance`, `total_debits`, `total_credits` (`:76-87`) |
| `models/Reports.ts:449,456-511` | a **second** `round2` in the balance-sheet section, same formula | duplicated rounder; two places to update |
| `models/OwnerWithdrawal.ts:73` | `round2 = (n) => parseFloat(n.toFixed(2))` | fourth rounder; `toFixed` rounds half-away-from-zero on negatives |
| `models/OwnerCapital.ts:254` | `parseFloat((...).toFixed(2))` | fifth rounder |
| `models/Customer.ts:100,150` | SQL `ROUND((current_balance / credit_limit) * 100, 2)` | a *percentage* (not money) — must stay fractional; do not integer-ize |
| `models/Customer.ts:172` | inserts `data.opening_balance || 0` into both `opening_balance` **and** `current_balance` | seed duplication; integer conversion must copy both consistently |
| `controllers/invoiceController.ts:689` | `freshInvoice.total_amount > 0` raw comparison | benign for floats; exact under integers — no change needed, but note |
| `models/Invoice.ts:1052,1058` | `paid.toFixed(2)` / `returned.toFixed(2)` in guard error text | formatting only |
| `services/accountingService.ts:454-1564` | ~28 `toFixed(2)` sites | **message/description strings only** — no arithmetic; safe to leave or convert for consistency |

### 3.4 GL posting construction (group B ingress)

`services/accountingService.ts` posting functions are the sole writers of
`journal_lines`. Each takes already-2-dp document amounts (invoice total, payment
amount, receipt amount, expense, capital, withdrawal, COGS, return legs) and
splits them into Dr/Cr legs:

- `:218` **balance guard**: `if (Math.abs(totalDebit - totalCredit) > 0.01)` —
  tolerance **0.01**.
- `:454,469` sales invoice posting (AR / Sales / Tax split).
- `:507` payment posting (Dr cash / Cr AR).
- `:548` credit-offset posting.
- `:592` goods-receipt posting (Dr 1200 / Cr 2000) — keyed to
  `(GOODS_RECEIPT, receiptId)`.
- `:633` purchase posting.
- `:673` supplier payment.
- `:713` expense.
- `:817,854` owner capital / withdrawal.
- `:893-902` goods-withdrawal posting with its own tolerance
  `Math.abs(creditTotal - args.totalCost) > 0.01`.
- `:942-964` **funds guard**: `bal.balance < args.amount - 0.01` (`:954`) and
  `bal.balance < 0.01` (`:959`) — the empty-cash CTA heuristic.
- `:1020,1072` COGS / COGS reversal.
- `:1130,1155,1198` return legs (AR reduction, sales return, restocking fee).
- `:1239,1287` purchase return / supplier refund.

**Risk:** GL legs are `DECIMAL(15,4)`. Because they are *splits* of 2-dp values,
most legs are exact at 2 dp; but a split like "tax-inclusive gross → net + tax"
or a percentage fee can yield a 3rd/4th decimal that is currently *absorbed* by
the 4-dp column and *excused* by the `> 0.01` tolerance. Under exact integer
cents that residue becomes a hard imbalance and the `:218` guard will start
rejecting postings that used to pass. See §7.3 and §10 R2.

### 3.5 Remaining arithmetic sites (currency-helper call sites)

Counts of `roundCurrency|addCurrency|subtractCurrency|multiplyCurrency|parseCurrency`
per file (grep over `models/ services/ utils/ controllers/`):

```
services/returnMath.ts:29            utils/currency.ts:27          utils/ledgerUtils.ts:25
services/invoiceReturnService.ts:17  controllers/paymentsController.ts:16
controllers/invoiceController.ts:13  models/PurchaseOrder.ts:11     models/Invoice.ts:9
services/paymentValidation.ts:8      services/PaymentRecordingService.ts:8
services/InvoiceCreationService.ts:7 services/SupplierPaymentService.ts:5
models/Payment.ts:5                  models/Production.ts:2
```

Notable specifics:

- `services/InvoiceCreationService.ts:83-104` — server-authoritative total;
  grace comparisons at `:88` (`> 0.01`), `:98` (`> totalAmount + 0.01`), `:122`
  (`> available + 0.005`).
- `services/invoiceReturnService.ts:309-325` —
  `returnedGross = roundCurrency(Σ lines.returnedGross)`,
  `netAmount = roundCurrency(returnedGross − feeAmount)`,
  over-return guard `currentReturned + returnedGross > invoiceTotal + 0.01`.
- `services/invoiceReturnService.ts:351,370` —
  `unit_price: roundCurrency(line.returnedGross / line.returnedQuantity)` —
  **division** producing a sub-cent value that is then rounded to 2 dp and stored
  in `invoice_return_items.unit_price`. Re-deriving `line_amount` from that
  rounded `unit_price` will not foot to `returnedGross`. This is a real
  rounding-loss site that integer representation makes visible (§7.4).
- `services/invoiceReturnService.ts:438,562,618` — `remainder = roundCurrency(net − settled)`.
- `models/PurchaseOrder.ts:139,173,377,430,450,499,542,997,1034` — PO totals and
  receipt movement values
  (`roundCurrency(receiptItem.received_quantity * poItem.unit_price)` at `:997`).
- `services/SupplierPaymentService.ts:29,45,49,73` — supplier payment +
  opening-balance decrement (`subtractCurrency(openingBalance, amount)`).
- `models/SupplierRefund.ts:138` — `amount > refundable + 0.005` (tolerance 0.005).
- `models/Production.ts:391` — `costPerUnit.toFixed(4)` (group-B scale, 4 dp) and
  `:573` `parseCurrency(production.total_batch_cost)`.
- `models/StockMovement.ts:515` — `value.toFixed(2)` in a description string.

---

## 4. Read-surface impact

### 4.1 Server API / reports

**No server-side monetary PDF or CSV export exists.** The only CSV exporter is
`controllers/activityLogController.ts:226-230` (`Content-Type: text/csv` over
`activityLogModel.exportToCSV`), which is audit-log text, not money. All PDFs are
generated **client-side in Flutter** (§4.2). This materially shrinks the server
read surface: the server's money read surface is (a) JSON response bodies and
(b) SQL report aggregates.

SQL aggregates that become exact under integers (currently float `SUM`):

- `models/Reports.ts:8-25` AR aging — `SUM(i.balance_amount)` and per-bucket
  `CASE` sums; `:20-25` totals; `:50-52` customer-statement opening/debits/credits;
  `:102-104,118` outstanding/invoiced; `:156-200` invoice-status buckets;
  `:315-334` AP aging over `supplier_ledger.debit`.
- `models/Invoice.ts:819-823` `getInvoiceTaxTotal` —
  `COALESCE(SUM(tax_amount), 0)`; the authoritative tax for GL.
- `models/Invoice.ts:890-896` `getTotalPaid` — `SUM(amount)` over `payment_allocations`.
- `utils/ledgerUtils.ts:156` — `SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END)`.
- `utils/ledgerUtils.ts:298,327` — `SUM(debit) - SUM(credit)` net derivations.
- `services/cashService.ts:380,456` — opening + flow arithmetic and
  `flow_variance`.

**Impact:** every such `SUM` is float-inexact today and exact after migration.
Report *fixtures* and Flutter golden values that hard-code float outputs will
change in the last digit — the `r2`/`round2` rounders (`models/Reports.ts:74,449`)
become no-ops and may be removed (PROPOSAL).

The single most dangerous read-surface site: `controllers/posController.ts:56`
computes `ii.quantity * ii.unit_price AS line_total` in SQL. Under integers this
is an **integer × integer minor-unit product** and must be divided by the scale
or precomputed in JS; leaving it raw silently changes the magnitude by 100×.

JSON contract: all money currently serialises as a JSON `number` (JS double).
Examples: `controllers/invoiceController.ts:100-102,121-122,254,314,479-481,502-506`;
`controllers/posController.ts:75-78`. Changing the wire type to JSON integer is a
**breaking API contract change** — see §6 Phase 3 gate and §10 R3.

### 4.2 Flutter

Presentation (must divide by scale before formatting):

- `lib/core/utils/formatters.dart:27-40` `CurrencyFormatter.format` →
  `NumberFormat.currency(...).format(value)` — `NumberFormat.currency` expects
  **major units**; an integer minor-unit input would render "Rs 12345" for
  123.45.
- `lib/core/utils/formatters.dart:59-71` static `Formatters.currency` facade
  (used across the app, e.g. `features/sales/sales_invoice_form_page.dart:1162`);
  `:126-128` `Formatters.number`.
- `lib/features/settings/settings_providers.dart:35-38`
  `currencyFormatterProvider` — the single injection point.
- Per-feature `_fmtCurrency` wrappers that call `formatter.format`:
  `features/customers/thermal_payment_receipt_pdf.dart:346-348`,
  `features/owner_equity/thermal_repayment_receipt_pdf.dart:358-360`,
  `features/sales/pos_thermal_receipt_pdf.dart:228-229`,
  `features/sales/thermal_invoice_pdf.dart:400-402`,
  `widgets/payment_receipt_pdf.dart:243-247`.

Client-side arithmetic that mirrors server rounding (must be re-based on
integers or on divided-down values):

- `lib/features/sales/calculations/invoice_calculations.dart:28-30`
  `_round2 = (value * 100).round() / 100` — documented as "mirrors the server's
  `roundCurrency`"; under integer money this whole layer becomes integer
  addition.
- `lib/features/sales/calculations/invoice_line_calc.dart:114-119` —
  `double.parse(rounded.toStringAsFixed(...))` step-decimal re-fix; `:118-120`
  `_round2`.
- `lib/features/customers/calculations/customer_calculations.dart:243-245`
  `formatAsFixed` — `toStringAsFixed(2)` on `num`.
- `lib/features/customers/customer_detail_screen.dart:228` and
  `features/customers/customers_grid_columns.dart:315` —
  `creditUtilization.toStringAsFixed(2)` is a **percentage**, not money (mirrors
  `models/Customer.ts:100`).

Input ingress (text → number) — these send fractional doubles today and would
send integers after the change:

- `lib/data/models/json_helpers.dart:11-15` `asNum` accepts `num` **or numeric
  string** — tolerant ingress; will read an integer fine, but consumers expect
  major units.
- Payment/loan/expense dialogs that parse user text and POST fractional values:
  `features/customers/customer_payment_modal.dart:115,120,174,251`;
  `features/suppliers/supplier_payment_modal.dart:148,150,229,250,265,283,307,319`;
  `features/expenses/expense_form_dialog.dart:122,154`;
  `features/owner_equity/owner_capital_form_dialog.dart:95,110`,
  `owner_withdrawal_form_dialog.dart:158,216,232`;
  `features/owner_equity/personal_loan_create_dialog.dart:90,222`;
  `features/employees/loan_create_dialog.dart:89,95,105`,
  `loan_repay_dialog.dart:103,114`, `salary_pay_dialog.dart:99,110,121`;
  `features/dashboard/cash_opening_balance_dialog.dart:71`;
  `features/inventory/item_form_dialog.dart:127-129`;
  `features/customers/customer_form_dialog.dart:139-141`.

Text controllers seeded with `toStringAsFixed(2)` (must switch to minor-unit
formatting or be fed divided values):
`customer_payment_modal.dart:157,178,193`;
`supplier_payment_modal.dart:148,150,229,250,265,283,307,319`.

Model typings: money fields are `num` (e.g. `lib/data/models/customer.dart:62,66,67`;
`lib/data/models/dashboard_summary.dart:23,37,51,143-148,191,204,236,271,300,340,379-382`;
`lib/data/models/bom.dart:48,51,107`). `num` accommodates `int`, but every
`+`/`-`/comparison against a `double` literal (e.g. `> 0.005` at
`features/sales/invoice_return_dialog.dart:279`) is a mixed-mode site to audit.
`lib/data/models/price_history.dart:38-39` parses a price via `num.tryParse`.

**Non-money `toStringAsFixed` (do NOT integer-ize):** byte sizes
(`formatters.dart:118,121`, `settings_screen.dart:921-923`), percentages
(`dashboard_screen.dart:1197`, `demand_forecast_screen.dart:211,257,699`,
`forecast_accuracy_screen.dart:329,349,481,489,564,824,844`,
`forecast_dashboard_screen.dart:316`, `customer_overview_tab.dart:140`), and
quantity display precision (`features/sales/line_cells.dart:407`, which uses
`qtyDecimalPrecision`).

---

## 5. Target data model and scale decision

### 5.1 Scale factor (PROPOSAL)

**PROPOSAL: canonical scale = 100** (2 minor units per major unit, cents/paisa)
for all group A columns. Rationale:

1. Every money column in group A is declared `DECIMAL(15,2)`; the business
   (PKR, 2-dp) never produces sub-cent document values — all 2-dp values are
   constructed by `roundCurrency` (`utils/currency.ts:8-11`).
2. `×100` keeps the declared max at 99,999,999,999,999 ≈ 1.0×10¹⁴, comfortably
   below 2⁵³ (≈9.007×10¹⁵) — **all group-A values stay exactly representable in
   a JS `number`**, so better-sqlite3 reads them as exact integers and JSON
   serialises them losslessly. (SQLite `INTEGER` is i64, max ≈9.22×10¹⁸ — no
   storage concern.)
3. The existing precedent — `utils/quantity.ts` — keeps a *quantity*-scale of
   10³ alongside a *money*-scale of 10² today; money converging on 10² preserves
   that boundary.

### 5.2 Group B — the 4-dp columns (decision required)

`journal_lines.debit/credit` (`add-gl-foundation.sql:61-62`),
`journal_entries.amount` (`add-stock-adjustment-financial.sql:15`),
`stock_batches.unit_cost` (`add-batch-costing.sql:15`),
`stock_movements.financial_value` (`add-stock-adjustment-financial.sql:34`),
`productions.total_batch_cost` (`config/database.ts:2237`).

Declared max at own scale = 9,999,999,999,999,999 ≈ 1.0×10¹⁶ **exceeds 2⁵³** —
not exactly representable in JS. Options:

- **PROPOSAL B1 (recommended): normalise to scale 100.** Round all group-B
  values to cents during backfill and store as INTEGER (scale 100). Cost: any
  genuine 3rd/4th-decimal content is lost. Justification: every group-B writer
  is a *split* of a 2-dp document amount (§3.4), and the GL already tolerates a
  ±0.01 imbalance (`accountingService.ts:218`), so sub-cent content has no
  business meaning. Risk: `models/Production.ts:391` prints
  `costPerUnit.toFixed(4)` and `stock_batches.unit_cost` is a total/qty average
  that can be genuinely fractional — **UNVERIFIED** whether live data has
  meaningful 3rd/4th decimals here; must be measured pre-migration (§8.3).
- **B2: keep scale 10⁴.** Exact in SQLite i64, but **not** JS-safe across the
  declared range; would require BigInt or a value-range guard on the read path.
  Rejected unless measurement shows material sub-cent content.

Decision gate: §8.3 measurement must report the count of group-B rows whose
value × 10⁴ mod 100 ≠ 0.

### 5.3 Group C — the 3-dp purchase-return family (decision required)

`purchase_returns`, `purchase_return_items`, `credit_notes`, `supplier_refunds`
are `NUMERIC(15,3)` (`add-purchase-returns-tables.sql:32,56,58,77`,
`add-disposition-and-supplier-refunds.sql:26`). 3-dp money is unusual; at scale
10³ the max (≈1.0×10¹⁵) is JS-safe. Options: keep scale 10³ (heterogeneous), or
round to cents (scale 100) for uniformity. **PROPOSAL: round to scale 100** for
schema uniformity, with the same §8.3 measurement gate applied at 10³. Risk: the
`NUMERIC(15,3)` choice may have been deliberate for per-unit costs in
`purchase_return_items.unit_cost` — **UNVERIFIED**.

### 5.4 Group D — bare REAL

`invoice_returns`, `invoice_return_items`, `return_settlements`, `employee_loans`,
`employee_loan_repayments` have no declared precision at all. Backfill must
`ROUND(value × 100)` and the expand phase must add a `CHECK` that the integer is
within the implied `DECIMAL(15,2)` range in minor units — these tables currently
*cannot* reject a sub-cent or absurd value, so the backfill doubles as a
data-quality scan (§8.2).

### 5.5 Column shape (PROPOSAL)

- New money columns declared `INTEGER` with a `CHECK` bound mirroring the old
  `DECIMAL(15,2)` range in minor units:
  `CHECK (x BETWEEN -99999999999999 AND 99999999999999)`, preserving existing
  sign constraints where present (`CHECK (amount > 0)` on `owner_capital`,
  `return_settlements`, `owner_personal_loans` (both tables);
  `CHECK (amount >= 0)` on `owner_withdrawals`, `invoice_return_items.line_amount`).
- A `_minor_scale` metadata row per table (or a small `money_columns` registry
  table created by the migration) so the read layer knows the divisor — avoids
  hard-coding 100 in N places. **PROPOSAL.**
- The derived `customer_ledger.balance` / `supplier_ledger.balance` /
  `employee_loans.balance` columns: **PROPOSAL** — keep as stored INTEGER but
  treat as derived; the canonical value is `Σ(debit) − Σ(credit)` over non-voided
  rows (the invariant already relied on by `utils/ledgerUtils.ts:298-332`). A
  post-backfill rebuild in **id order** (the documented
  `SupplierLedgerModel.rebuildBalances` requirement) re-derives them exactly.

---

## 6. Phased migration plan

Each phase is an idempotent migration registered in the existing ledgered
migration runner (`config/database.ts:87-138` `runLedgered`, sequenced in the
boot migration block at `:1528-1771`). Every phase has an explicit rollback.
Column names below are illustrative of the pattern, not an exhaustive list.

### Phase 0 — Measurement and dry-run (no schema change)

1. Run the §8.2 inconsistency scan and §8.3 sub-cent measurement against a
   **backup copy** of the live DB (never the running one).
2. Produce a report: per-column count of (a) rows not exactly representable at
   the chosen scale, (b) rows violating the target `CHECK` bound, (c) rows
   failing a foot/invariant check.
3. **Rollback:** none needed — read-only.

### Phase 1 — Expand (add integer shadow columns)

For every money column `T.c`: `ALTER TABLE T ADD COLUMN c_minor INTEGER;` plus a
`CHECK` bound. Mirrors the existing programmatic-ALTER pattern already used at
`config/database.ts` (e.g. `:2175` for `return_fee`). Both spellings from §2.11
and both the `.sql`-defined and `config/database.ts`-only columns are covered.

- **Idempotence:** `ALTER TABLE … ADD COLUMN` guarded by a
  `pragma_table_info` existence check — the same pattern `config/database.ts`
  already uses for double-added `productions.overhead_cost` (§2.11).
- **Write amplification:** during expand, writes go to *both* `c` (float) and
  `c_minor`. **PROPOSAL:** implement via a thin write-side shim so the two cannot
  diverge; alternatively accept expand as read-only-shadow and keep Phase 2 short.
- **Rollback:** `ALTER TABLE T DROP COLUMN c_minor;` (SQLite ≥3.35 supports
  `DROP COLUMN`; the repo already relies on programmatic ALTERs and detects
  SQLite features via `pragma_table_info`, so a capability check is in keeping).
  Drop the registry rows from Phase 0.

### Phase 2 — Backfill (convert, verify, reconcile)

Per table, inside a `db.transaction(() => …)` (the project's transactional-write
rule):

1. `UPDATE T SET c_minor = ROUND(c * 100)` (group A); group B/C per §5.2/§5.3
   decision, with residue counted and logged.
2. For derived columns (`*_ledger.balance`, `employee_loans.balance`), recompute
   in **id order**, not `transaction_date` order — the documented drift cause for
   `SupplierLedgerModel.rebuildBalances`.
3. Re-run the §8.2 scanner against the `_minor` columns and assert zero
   hard-failures; log soft-failures for human triage (do not abort boot — the
   `runLedgered` process-exit behaviour makes an abort fatal, per existing
   backfill convention).
4. **Idempotence:** backfill is a pure function of `c`, so re-running is safe;
   guard with a `WHERE c_minor IS NULL` to make progress observable.
- **Rollback:** `UPDATE T SET c_minor = NULL;` (leaves `c` untouched — the float
  column is still authoritative in Phase 2). Re-run Phase 2 after fixing data.

### Phase 3 — Read/write cutover (contract change)

1. Switch all writers to `c_minor` only; readers divide by the registered scale
   at the boundary (`parseCurrency` replacement — an integer-aware
   `parseMinorUnits`) or return integers to the API (§4.1).
2. Server arithmetic moves to plain integer `+`/`-` on minor units;
   `roundCurrency`/`addCurrency`/… become identity/passthrough shims during the
   transition and are then deleted. The duplicated rounders
   (`Reports.ts:74,449`, `cashService.ts:368,380,456`, `OwnerWithdrawal.ts:73`,
   `OwnerCapital.ts:254`) are deleted in the same change.
3. Fix the §3.3 raw-arithmetic sites **before** or **in** this phase — under
   integers, `paymentValidation.ts:39`'s raw subtraction and
   `posController.ts:78`'s unrounded `change` silently mis-scale.
4. SQL expression sites: `controllers/posController.ts:56`
   (`quantity * unit_price AS line_total`) must be re-expressed; SQL `SUM` of
   integers is exact and needs no change; `models/Customer.ts:100,150`
   percentage `ROUND` stays fractional.
5. **API contract gate (§10 R3):** decide and publish whether responses carry
   integer minor units (breaking) or major-unit decimals reconstructed
   server-side (non-breaking). **PROPOSAL:** ship integer minor units with a
   versioned `/api/v2` prefix or a `X-Money-Units: minor` response header, and
   migrate Flutter in lockstep.
- **Rollback:** flip readers/writers back to `c`; the `_minor` columns retain the
  converted data so the cutover is re-entrant.

### Phase 4 — Contract (drop float columns)

1. Backfill `c` from `c_minor / scale` for a temporary coexistence window
   (optional), then `ALTER TABLE T DROP COLUMN c;` and
   `ALTER TABLE T RENAME COLUMN c_minor TO c;`.
2. Remove the `_minor_scale` registry rows now that only one representation exists.
- **Rollback:** restore `c` as `DECIMAL(15,2)` and backfill from the integer
  column before dropping it — requires the integer column to still exist, so
  Phase 4's drop is the last, gated action.

### Phase 5 — Flutter

1. Boundary division: `CurrencyFormatter.format` (`formatters.dart:36`) receives
   minor units; add a single divide-by-scale at the formatting boundary (or at
   the repository layer) so the ~30 `_fmtCurrency`/`Formatters.currency`
   call-sites need no per-site change.
2. Client calculation layers (`invoice_calculations.dart:28-30`,
   `invoice_line_calc.dart:114-119`, `customer_calculations.dart:243-245`)
   re-based on integers.
3. Input dialogs: parse minor units or divide at the repository boundary; the
   text-controller seeds (`toStringAsFixed(2)`) switch to a minor-unit formatter.
4. `json_helpers.dart:11-15` `asNum` already tolerates numeric strings — no crash
   risk, but all consumers must expect major-vs-minor per the Phase 3 contract.
- **Rollback:** revert the Flutter bundle; the server still serves both if
  Phase 3's header gate is used.

---

## 7. Rounding and tolerance policy

### 7.1 Rounding mode

Current: **half-up**, via `Math.round` in the `e+2` string trick
(`utils/currency.ts:8-11`). Flutter mirrors it: `(value * 100).round() / 100`
(`invoice_calculations.dart:28-30`), and the calculations README at
`lib/features/sales/calculations/README.md:44-47` explicitly warns that Dart
`num.round()` rounds half **away from zero** while JS `Math.round` rounds `-2.5`
to `-2` — irrelevant for positive prices/quantities, relevant if negative lines
appear.

**PROPOSAL:** preserve half-up exactly. Under integer minor units, rounding
happens only at the *ingress* boundary (a fractional input or a division) —
`ROUND(value * 100)` in SQL and a single JS `Math.round(value * 100)` (or
`BigInt`-safe equivalent) at the boundary. Post-ingress, all arithmetic is exact
integer arithmetic and **no rounding function is needed mid-computation** — this
is the core correctness win.

### 7.2 Tolerance values to preserve (and their integer semantics)

| current site | tolerance | semantic | integer equivalent (PROPOSAL) |
|---|---|---|---|
| `accountingService.ts:218` | `> 0.01` | GL Dr≠Cr imbalance | `> 1` minor unit |
| `accountingService.ts:893` | `> 0.01` | goods-withdrawal Dr≠Cr | `> 1` |
| `accountingService.ts:954` | `bal.balance < amount - 0.01` | funds guard | `< amount - 1` |
| `accountingService.ts:959` | `bal.balance < 0.01` | empty-cash CTA | `< 1` (i.e. `=== 0`) |
| `InvoiceCreationService.ts:88` | `\|client − computed\| > 0.01` | total mismatch | `> 1` |
| `InvoiceCreationService.ts:98` | `payment + credit > total + 0.01` | over-offset | `> 1` |
| `InvoiceCreationService.ts:122` | `credit > available + 0.005` | credit guard | **decision required** — see §7.3 |
| `paymentValidation.ts:79` | `amount > ceiling + 0.01` | allocation ceiling | `> 1` |
| `paymentValidation.ts:131` | `\|allocated − payment\| > 0.01` | allocation completeness | `> 1` |
| `paymentValidation.ts:166-169` | remaining-balance clamp | `Math.max(0, total − paid)` | exact integer; tolerance unnecessary |
| `PaymentRecordingService.ts:86` | `\|allocated − unallocated\| > 0.01` | allocation remainder | `> 1` |
| `PaymentRecordingService.ts:126` | `amount > balance + 0.01` | allocation ceiling | `> 1` |
| `invoiceReturnService.ts:322` | `returned + gross > total + 0.01` | over-return | `> 1` |
| `invoiceReturnService.ts:461` | `position.refundCreditDue > 0.005` | legacy refund due | **decision required** |
| `SupplierRefund.ts:138` | `amount > refundable + 0.005` | refund ceiling | **decision required** |
| `check-gl-integrity.ts:44` | `ABS(SUM(dr) − SUM(cr)) > 0.005` | offline GL check | **decision required** |
| `lib/features/sales/invoice_return_dialog.dart:279` | `remainder > 0.005` | Flutter remainder | **decision required** |

### 7.3 The 0.005 sites (policy decision required)

The `0.005` tolerances are *sub-cent*: they accept an imbalance of up to half a
minor unit. Under exact integers there is no such thing as half a minor unit.
**PROPOSAL:** replace every `> X + 0.005` with `> X` (strict) *after* the §8
inconsistency scan confirms no live row depends on the slack — i.e. a refund
equal to `refundable + 0.004` today passes and would then fail. Note the existing
**inconsistency**: `accountingService.ts:218` uses `0.01` while the offline
checker `check-gl-integrity.ts:44` uses `0.005` for the same GL-balance check —
they disagree today and should converge on one integer policy (`> 1`) as part of
this migration.

### 7.4 Rounding-loss sites that become visible (must be designed, not just converted)

- `invoiceReturnService.ts:351,370`: `unit_price = roundCurrency(gross / qty)`
  rounds a per-unit price to cents, then `invoice_return_items.line_amount` is
  derived from it. Under integers the division `gross_minor / qty` truncates or
  rounds; a 3-unit / 7-unit split cannot foot. **PROPOSAL:** keep the
  *line amount* authoritative (integer, exact) and derive `unit_price` for
  display only — or store a per-unit remainder. Design decision required; do not
  convert blindly.
- `decomposeLineAmount` (`currency.ts:54-77`): per-line tax rounding means
  `Σ tax ≠ tax(Σ)`. This is intentional (the stored `invoice_items.tax_amount`
  is the single source of truth per `models/Invoice.ts:812-818`); integer
  representation preserves it exactly and removes the float residue that made
  the divergence look random.
- `Reports.ts:100,150` percentage utilisation is a ratio — stays fractional.

---

## 8. Historical data migration procedure

### 8.1 Order of operations

Backfill in **dependency order** so derived columns are rebuilt from
already-converted sources (PROPOSAL):

1. Document-level source columns: `invoices`, `invoice_items`, `purchase_orders`,
   `purchase_order_items`, `purchases`, `quotations`(+items), `sales_orders`(+items),
   `sales`, `expenses`, `salary_payments`, `employees.salary`, `items`,
   `bom_items`, `opening_balances`.
2. Payment/allocation layer: `payments`, `payment_allocations`, `po_allocations`,
   `purchase_allocations`.
3. Sub-ledgers: `customer_ledger`, `supplier_ledger` (rebuild `balance` in id
   order — §6 Phase 2), then `customers.current_balance`/`credit_balance`/`credit_limit`/`opening_balance`.
4. Costing layer: `stock_batches.unit_cost`, `stock_movements.financial_value`,
   `productions.total_batch_cost`, `physical_count_items`, `cash_reconciliations`.
5. GL: `journal_lines`, `journal_entries` (group B decision §5.2) — converted
   last so the §8.2 GL-balance check can compare converted document totals
   against converted journal legs.
6. Returns and loans (group D / group C): `invoice_returns`, `invoice_return_items`,
   `return_settlements`, `purchase_returns`, `purchase_return_items`,
   `credit_notes`, `supplier_refunds`, owner/employee loan tables.

Each step runs inside `db.transaction(() => …)` and is idempotent.

### 8.2 Detecting already-inconsistent rows (pre-migration scan)

The repo already ships two scanners to extend (do not duplicate):

- `server/scripts/historical-data-integrity.ts` — exports
  `scanHistoricalDataIntegrity(db)` returning a `HistoricalIntegrityReport` with
  typed finding codes including `'return_restock_quantity_mismatch'`
  (`:8`). Its checks join `journal_lines` to documents (`:168-181`, `:240-244`)
  and goods receipts to POs (`:309-331`), and it already tolerates
  optional columns via `hasColumn`/`pragma_table_info` (`:309`) — the exact
  pattern a money scanner needs for the heterogeneous `DECIMAL/REAL/NUMERIC`
  column set.
- `server/scripts/check-gl-integrity.ts` — offline GL checker; `:40-44` selects
  `SUM(jl.debit) AS dr, SUM(jl.credit) AS cr … HAVING ABS(dr − cr) > 0.005`.

**PROPOSAL — money-consistency scan (new checks, same harness):**

| check | rule | current-state evidence |
|---|---|---|
| `invoice_foots` | `invoices.total_amount` = Σ `invoice_items.amount` | total is computed as Σ lines (`currency.ts:108-120`) but stored independently — drift possible |
| `invoice_paid_balance` | `balance_amount` = `total_amount` − (`paid_amount` − `returned_amount` + `return_fee`) subject to the §7.2 clamps | `ledgerUtils.ts:156-198` computes position differently from the stored column; `paid_amount` is a gross base that refunds do not shrink |
| `tax_gl_matches_stored` | GL Tax legs for (INVOICE, id) = `getInvoiceTaxTotal` | `models/Invoice.ts:812-818` documents this as H3; the existence of `__tests__/taxGlRepairMigration.test.ts` implies a repair already shipped |
| `gl_balanced` | `SUM(debit) = SUM(credit)` per `journal_entries` | `check-gl-integrity.ts:40-44` (tolerance 0.005) vs `accountingService.ts:218` (0.01) |
| `ledger_balance_matches_sum` | stored `balance` = running `Σ(debit) − Σ(credit)` in id order | `Invoice.ts:864-885` chaining is drift-prone; `ledgerUtils.ts:298-332` already derives from Σ |
| `allocation_foots` | Σ `payment_allocations` for a payment = `payments.amount` | `paymentValidation.ts:129-134` enforces this at write time; historical rows may predate it |
| `return_net_foots` | `invoice_returns.net_amount` = `returned_amount` − `fee_amount`, and `settled_amount` ≤ `net_amount` | `invoiceReturnService.ts:309-313`; `invoice_returns` columns are bare `REAL` with no CHECK |
| `ap_reconciles` | GL 2000 = `Σ(supplier_ledger debit − credit, voided=0)` − outstanding PO value | invariant documented for `SupplierLedgerModel.rebuildBalances`; the AP report derives from the ledger (`Reports.ts:315-334`) |
| `ar_reconciles` | GL 1100 = `Σ(customer_ledger debit − credit)` | mirror of the above; `customer_ledger` is the AR sub-ledger (`create-customer-ledger.sql`) |
| `cash_position` | cash account balance = `opening_balances` + inflows − outflows | `cashService.ts:380,456` computes this with a third rounder |

Scan output must separate **hard failures** (mismatch > 0.01 ⇒ will break after
migration) from **soft failures** (0 < mismatch ≤ 0.01 ⇒ absorbed by tolerance,
safe but should be repaired). This is the §7.3 decision input.

### 8.3 Sub-cent measurement (group B/C gate)

Before §5.2/§5.3 can be settled, measure per column:

```sql
SELECT COUNT(*) AS rows_total,
       SUM(CASE WHEN ABS(value * 10000 - ROUND(value * 10000)) > 0.0001 THEN 1 ELSE 0 END) AS residue_rows
FROM <table>;
```

and equivalently at scale 1000 for group C, and scale 100 for group D (where any
non-zero residue is by definition sub-cent). If `residue_rows` is 0, normalising
to scale 100 is lossless and B1 (§5.2) is safe. If non-zero, quantify the
magnitude and decide B2 vs lossy-normalise-with-audit-log. **This measurement has
not been run** (no DB access permitted for this plan) — the group-B/C scale
decision is therefore **UNVERIFIED** pending it.

### 8.4 Backfill safety properties

- Every conversion is a pure function of the source column ⇒ idempotent.
- Write a per-table row count + checksum (Σ of the integer column, and a hash of
  the sorted value list) before/after, asserted equal modulo rounding residue.
- The backfill logs soft failures via `logger.warn` and continues — never aborts
  boot, because `runLedgered` calls `process.exit(1)` on throw (the existing
  convention used by the mobile-invoice stock backfill).
- Run against a **backup** first; the repo already has backup tooling
  (`server/scripts/backup-db.js`, `verify-backup.js`, `restore-smoke.js`).

---

## 9. Regression matrix

Coverage claims below are made **only** for test files actually read during this
planning session (`server/src/__tests__/`, 101 entries including `helpers/`,
`setup.ts`, `teardown.ts`). Files listed as *UNVERIFIED* were confirmed to exist
by directory listing and, where noted, `it()`-counted by grep — but their
contents were not read, so no coverage is claimed beyond the name.

| behaviour | covering test (read?) | status | integer-migration concern |
|---|---|---|---|
| Quantity float safety (`roundQty`, `qtyEquals`, …) | `floatingPointPrecision.test.ts` (**read** — header + first suites; 39 `it()` total) | not run here | **out of scope** (quantities), but it is the design template for the money layer (`utils/quantity.ts`) |
| Partial payment allocation, invoice edit after payment, parallel invoice numbering, GL side-effects | `moneyPaths.test.ts` (**read** — header + first case; 6 `it()`) | asserts via `toBeCloseTo(…, 2)` and direct DB row reads | `toBeCloseTo` tolerance must become exact integer equality; `glBalance()` sums GL legs — confirm integer legs sum exactly |
| Historical-inconsistency scan machinery (fixture-based) | `historicalDataIntegrityScanner.test.ts` (**read** — header + fixture; 2 `it()`) | in-memory fixture | extend this harness for the §8.2 money checks; the fixture already models `invoice_returns`/`journal_lines`/`stock_movements` money columns |
| Ledger integrity | `ledgerIntegrity.test.ts` (**UNVERIFIED** — 10 `it()` counted by grep) | unknown | must cover the `balance` = `Σ(debit) − Σ(credit)` id-order invariant after rebuild |
| Accounting invariants | `accountingInvariants.test.ts` (**UNVERIFIED** — 20 `it()` counted by grep) | unknown | name suggests AR/AP/GL footing checks — the primary guard for §8.2 |
| GL posting matrix | `glPostingMatrix.test.ts` (**UNVERIFIED**) | unknown | every `accountingService.ts` posting from §3.4 must post integer legs that foot exactly |
| Tax posting consistency | `taxPostingConsistency.test.ts` (**UNVERIFIED**) | unknown | the `tax_gl_matches_stored` check in §8.2 |
| Tax GL repair | `taxGlRepairMigration.test.ts` (**UNVERIFIED**) | unknown | implies a shipped repair for the H3 invariant; re-run post-migration |
| PO receipt GL | `poReceiptGl.test.ts` (**UNVERIFIED**) | unknown | covers `(GOODS_RECEIPT, receiptId)` posting (12 tests per prior session memory) |
| Invoice idempotency (desktop/mobile/POS) | `invoiceIdempotency.test.ts` (**UNVERIFIED**) | unknown | replay paths must reconstruct integer totals; POS replay reads `invoices`/`invoice_items` rows (11 tests per prior session memory) |
| Mobile return parity | `mobileReturn.test.ts` (**UNVERIFIED**) | unknown | mirrors desktop return math incl. `roundCurrency(gross / qty)` at `invoiceReturnService.ts:351` |
| Return math (pure functions) | `returnMath.test.ts` (**UNVERIFIED**) | unknown | `computeReturnedLine`/`allocateHeaderDiscount`/`resolveFee`/`computePosition` — rounding-order sensitivity |
| Payment recording matrix | `paymentRecordingMatrix.test.ts` (**UNVERIFIED**) | unknown | signed refund amounts (`PaymentRecordingService.ts:43`) |
| Supplier refund | `supplierRefund.test.ts` (**UNVERIFIED**) | unknown | the `+ 0.005` tolerance at `SupplierRefund.ts:138` (§7.3) |
| Cash truth | `cashTruth.test.ts` (**UNVERIFIED**) | unknown | cash position — the third rounder sites in §3.3 |
| GL return tax balance | `glReturnTaxBalance.test.ts` (**UNVERIFIED**) | unknown | the 2× group-total trap for `INVOICE_RETURN` (group totals include both the return entry and the COGS reversal) |

**Gaps (no covering test found in this session):**

- No test asserts `invoices.total_amount` = Σ `invoice_items.amount` on a
  stored-vs-computed basis (the `invoice_foots` check).
- No test covers the duplicated rounder agreement — i.e. that
  `cashService.ts:368`'s `Math.round(x*100)/100` equals `roundCurrency` for the
  same input.
- No test covers `posController.ts:56`'s SQL-computed `line_total` against the
  stored `invoice_items.amount` — the highest-risk read-surface site.

**PROPOSAL:** add these as regression tests that fail pre-migration and pass
post-migration (they are the natural homes for the §8.2 checks), and convert the
`moneyPaths.test.ts` `toBeCloseTo(…, 2)` assertions to exact integer equality as
the migration's canary.

---

## 10. Open questions and risks

**R1 — Group B exceeds 2⁵³ (blocking, must measure).**
`journal_lines.debit/credit`, `journal_entries.amount`, `stock_batches.unit_cost`,
`stock_movements.financial_value`, `productions.total_batch_cost` are
`DECIMAL(15,4)`; at their own scale the declared max ≈1.0×10¹⁶ exceeds 2⁵³.
Cannot be stored as JS-exact integers at scale 10⁴. Resolution runs through
§5.2 B1 (normalise to cents) vs B2 (keep 10⁴ with BigInt), gated on the §8.3
measurement which has **not been run**. **UNVERIFIED** until measured.

**R2 — GL 4-dp residue becomes hard imbalance (high).**
The `> 0.01` balance guard (`accountingService.ts:218`) and the `> 0.005` offline
checker (`check-gl-integrity.ts:44`) currently *excuse* sub-cent residue that the
4-dp columns *absorb*. Under exact integer cents, any historical leg with a
3rd/4th decimal becomes `SUM(debit) ≠ SUM(credit)` and postings start failing.
The §8.2 `gl_balanced` scan over live data is a prerequisite to Phase 2; expect
repairs to be needed. Also note the two tolerances disagree today (0.01 vs
0.005) — converge on `> 1` minor unit.

**R3 — API contract is a breaking change (high).**
Money serialises as JSON `number` today
(`invoiceController.ts:100-102,254,314,479-481`; `posController.ts:75-78`).
Switching to JSON integers breaks every un-versioned client. Decision required:
integer minor units behind a versioned route/response header (PROPOSAL) vs
server-side reconstruction of major-unit decimals (non-breaking, keeps a
conversion boundary forever). Flutter's `json_helpers.dart:11-15` `asNum`
tolerates numeric strings, so a string-encoded integer is also viable.

**R4 — Rounding-loss return lines (medium).**
`invoiceReturnService.ts:351,370` divides gross by quantity to get a unit price,
rounds to 2 dp, and stores it; `line_amount` is derived from it. Integer
representation makes the non-footing explicit. Needs a design decision
(line-amount-authoritative vs per-unit remainder) — see §7.4. Do not convert
this site blindly.

**R5 — Derived ledger `balance` columns are drift-prone (medium).**
`customer_ledger.balance` (`Invoice.ts:864-885` chaining) and
`supplier_ledger.balance` are derived; backdated inserts desync them from
`Σ(debit − credit)`. The rebuild must run in **id order** (the documented
`SupplierLedgerModel.rebuildBalances` requirement), and the migration must
decide keep-stored vs compute-on-read (§5.5).

**R6 — Magnitude hazard in SQL products (high).**
`controllers/posController.ts:56` computes `ii.quantity * ii.unit_price` in SQL.
Under integers both operands are minor-unit/quantity integers, so the product
silently changes scale (100× for the money operand). Every SQL money expression
must be audited — this one is known; others may exist and were not exhaustively
grep'd for `*` over money columns.

**R7 — Five independent rounding implementations (medium).**
`currency.ts:8-11`, `Reports.ts:74`, `Reports.ts:449`, `cashService.ts:368/380/456`,
`OwnerWithdrawal.ts:73`, `OwnerCapital.ts:254` each reimplement round-to-2dp with
different mechanisms (`e+2` string trick, `Math.round(x*100)/100`, `toFixed(2)`).
They agree for positive values today but diverge on negatives and on
half-way values. All must be removed in Phase 3 — leaving even one creates a
second representation.

**R8 — Scope surface is wide (operational).**
~35 tables, ~90 money columns, 5 duplicated rounders, 3 raw-float bypass sites,
~14 tolerance sites, and a Flutter layer with ~30 formatting sites and ~30
input-ingress sites. The plan deliberately phases this; Phase 0 measurement is
the only cheap step and should gate everything else.

**Open questions:**

1. Does any live deployment have material sub-cent content in group B/C columns?
  (§8.3 — **UNVERIFIED**, measurement not run.)
2. Should the API break (integer minor units) or preserve the decimal contract
  (server-side reconstruction)? (R3.)
3. Are the `NUMERIC(15,3)` purchase-return columns deliberately 3-dp for per-unit
  costs, or an inconsistency to normalise to 2 dp? (§5.3 — **UNVERIFIED**.)
4. Does any consumer depend on `posController.ts:56`'s SQL `line_total` matching
  the stored `amount` exactly? (R6.)
5. Is the Fixer currency integration surfaced anywhere in the Flutter UI?
  (§1.2 — **UNVERIFIED**; the integration is inert settings rows today.)
