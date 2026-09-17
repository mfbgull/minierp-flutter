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

Customer credits are generated from invoice returns (`disposition: 'credit'`).
When a customer applies credit to a new invoice via `credit_offset`:

- `invoices.paid_amount` = cash payments + credit_offset (already handled)
- `invoices.balance_amount` = total_amount - paid_amount
- GL entry: Dr Customer Credit (1110) / Cr AR (1100) via `postCreditOffsetEntry()`
- `InvoiceModel.getPayments()` adds a synthetic `CREDIT-{invoice_no}` entry

**DO NOT** create a `CREDIT_OFFSET` entry in `customer_ledger`. The invoice
DEBIT entry already accounts for the full total. Adding a CREDIT_OFFSET
CREDIT entry double-counts and prevents `recalcCustomerBalanceFromLedger()`
from reducing the customer's balance after credit application.

**RETURN ledger entries** must use `invoice.invoice_date` (not today's date)
as the `transaction_date`. Otherwise `rebuildLedgerBalances()` reorders by
date and corrupts the running balance chain for backdated returns.