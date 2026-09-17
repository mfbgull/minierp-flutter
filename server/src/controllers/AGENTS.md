# Server Controllers Layer

**Parent:** `/AGENTS.md` | **Complexity:** High (22 controller files)

## OVERVIEW
Request/response handling, business logic orchestration.

## WHERE TO LOOK
| Task | File |
|------|------|
| Sales orders | `controllers/salesController.ts` |
| Invoices | `controllers/invoiceController.ts` |
| Inventory | `controllers/inventoryController.ts` |
| Reports | `controllers/reportsController.ts` (55KB - largest) |
| All controllers | `server/src/controllers/*.ts` |

## CONVENTIONS
- All controllers wrapped in try/catch
- Return structured JSON: `{ success: true, data: ..., error: null }`
- No stack trace leaks to client
- Validate inputs with express-validator

## ERROR HANDLING
```typescript
try {
  // logic
} catch (error) {
  return { success: false, data: null, error: error.message };
}
```

## ANTI-PATTERNS
- NO `console.error` in production
- NO raw SQL (use models)
- NO direct database access (use models)

## KEY CONTROLLERS
- `salesController.ts` - SalesOrder lifecycle
- `invoiceController.ts` - Invoice generation
- `reportsController.ts` - Financial reports
- `customersController.ts` - Customer ledger

## CREDIT OFFSET GOTCHAS (fix-customer-credit-reflection)

Two bugs were found and fixed in `invoiceController.ts`:

1. **RETURN ledger date**: Use `invoice.invoice_date`, NOT `todayDate`.
   `rebuildLedgerBalances()` reorders by `(transaction_date, id)`.
   A backdated return with today's date corrupts the running balance chain.

2. **CREDIT_OFFSET in customer_ledger**: Do NOT create a `customer_ledger`
   entry for credit offsets. The invoice DEBIT entry already covers the
   total. The GL entry via `postCreditOffsetEntry()` is sufficient.