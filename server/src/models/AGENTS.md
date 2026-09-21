# Server Models Layer

**Parent:** `/AGENTS.md` | **Complexity:** Medium (14 model files)

## OVERVIEW
Database access layer. SQLite queries via better-sqlite3.

## WHERE TO LOOK
| Task | File |
|------|------|
| Sales orders | `models/SalesOrder.ts` |
| Invoices | `models/Invoice.ts` |
| BOM | `models/BOM.ts` |
| All models | `server/src/models/*.ts` |

## CONVENTIONS
- Use prepared statements only
- No string-interpolated SQL
- Transactions for multi-step writes
- Models export functions, not classes

## DATABASE RULES
- `db.prepare()` for all statements
- `.all()` for selects, `.run()` for inserts/updates
- Transactions via `db.transaction()`

## ANTI-PATTERNS
- NO raw SQL strings outside models
- NO schema changes without migration
- NO silent failures

## KEY MODELS
- `SalesOrder.ts` - 22KB, complex relations
- `PurchaseOrder.ts` - 24KB, largest
- `Quotation.ts` - 19KB
- `Invoice.ts` - 11KB

## CREDIT OFFSET BEHAVIOR

Customer credit has TWO non-overlapping representations (H9):

1. **Store-credit pool** — `customers.credit_balance`, created by return
   settlements of type `credit` (`InvoiceReturnService.applyCredit`). The
   settlement posts a consuming CREDIT *debit* on `customer_ledger`, so the
   pool is deliberately ABSENT from the ledger/AR while unused. When
   `credit_offset` consumes pool credit, the controller writes a matching
   CREDIT *credit* ledger row (`CREDIT-{invoice_no}`) and decrements
   `credit_balance`. Available credit = `credit_balance` + legacy negative
   `current_balance` (they never coexist for the same money).

2. **Legacy ledger credit** — a RETURN credit row that sits on
   `customer_ledger` (negative `current_balance`). Consumed directly by the
   invoice's full-value DEBIT row.

When a customer applies credit to a new invoice via `credit_offset`:

- `invoices.paid_amount` = cash payments + credit_offset (already handled)
- `invoices.balance_amount` = total_amount - paid_amount
- GL entry: Dr Customer Credit (1110) / Cr AR (1100) via `postCreditOffsetEntry()`
- `InvoiceModel.getPayments()` adds a synthetic `CREDIT-{invoice_no}` entry

**DO NOT** create an extra `CREDIT_OFFSET` entry for the LEGACY half — the
invoice DEBIT entry plus the existing RETURN credit already account for the
total; a second credit double-counts and breaks
`recalcCustomerBalanceFromLedger()`. The pool-half credit row is required
(see 1 above) because no ledger row carries that credit anymore.

**RETURN ledger entries** must use `invoice.invoice_date` (not today's date)
as the `transaction_date`. Otherwise `rebuildLedgerBalances()` reorders by
date and corrupts the running balance chain for backdated returns.