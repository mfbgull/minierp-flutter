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