# Server Routes Layer

**Parent:** `/AGENTS.md` | **Complexity:** High (22 route files)

## OVERVIEW
API endpoint definitions. Delegates to controllers.

## WHERE TO LOOK
| Task | File |
|------|------|
| Auth | `routes/auth.ts` |
| Inventory | `routes/inventory.ts` |
| Sales | `routes/sales.ts` |
| Reports | `routes/reports.ts` |
| All routes | `server/src/routes/*.ts` |

## CONVENTIONS
- Route files = endpoint definitions only
- No business logic in routes
- Use controller imports: `import { login } from '../controllers/authController.js'`

## ANTI-PATTERNS
- NO try/catch in routes (controllers handle errors)
- NO raw queries (use models)
- NO business logic

## KEY ROUTES
- `auth.ts` - login, logout, me, change-password
- `sales.ts` - orders CRUD, quotations
- `inventory.ts` - items, stock, movements
- `reports.ts` - profit-loss, balance-sheet, trial-balance