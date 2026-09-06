import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';

// ============================================================================
// ZOD VALIDATION SCHEMAS AND MIDDLEWARE
// ============================================================================

/**
 * Common Zod validation schemas for reuse across controllers
 */
export const zodSchemas = {
  pagination: z.object({
    page: z.string().regex(/^\d+$/).default('1').transform(Number),
    limit: z.string().regex(/^\d+$/).default('10').transform(Number),
  }),

  sorting: (allowedColumns: string[]) => z.object({
    sortBy: z.enum(allowedColumns as [string, ...string[]]).optional().default(allowedColumns[0]),
    sortOrder: z.enum(['ASC', 'DESC']).optional().default('ASC'),
  }),

  dateRange: z.object({
    fromDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    toDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  }),

  search: z.object({
    search: z.string().max(100).optional(),
  }),

  id: z.object({
    id: z.string().regex(/^\d+$/).transform(Number),
  }),

  status: z.object({
    status: z.enum(['active', 'inactive', 'all']).optional().default('all'),
  }),

  period: z.object({
    period: z.string().regex(/^\d+$/).default('30').transform(Number)
      .refine(val => val >= 1 && val <= 3650, {
        message: 'Period must be between 1 and 3650 days'
      }),
  }),

  /**
   * Permissive query validation for GET list routes (spec 2.3):
   * pagination + sorting + date-range params are type-checked, everything
   * else the controllers read (ids, statuses, flags) passes through.
   */
  listQuery: z.object({
    page: z.string().regex(/^\d+$/).optional().transform(v => (v === undefined ? undefined : Number(v))),
    limit: z.string().regex(/^\d+$/).optional().transform(v => (v === undefined ? undefined : Number(v))),
    search: z.string().max(100).optional(),
    sortBy: z.string().max(50).optional(),
    sortOrder: z.string().max(10).optional(),
    start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    from_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    to_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    fromDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    toDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  }).passthrough(),
};

/**
 * Body schemas for POST/PUT routes (spec 2.3). Every schema is
 * `.passthrough()` so payloads keep their extra fields — controllers
 * still own the deep business rules (XOR counterparties, allocation
 * presence, status transitions) and their error messages.
 */
export const zodBodySchemas = {
  // Shape-only: the body must be a JSON object when present. Used for
  // complex/partial update bodies whose business validation lives in the
  // controller. Bodies are OPTIONAL here — express.json() leaves
  // `req.body` undefined on empty POST/PUTs (e.g. POST /admin/backup),
  // and Zod would otherwise 400 every bodyless action.
  object: z.object({}).passthrough().optional(),

  login: z.object({
    username: z.string().min(1),
    password: z.string().min(1),
  }).passthrough(),

  refresh: z.object({
    refreshToken: z.string().min(1),
  }).passthrough(),

  changePassword: z.object({
    currentPassword: z.string().min(1),
    newPassword: z.string().min(1),
  }).passthrough(),

  customerCreate: z.object({
    customer_name: z.string().min(1),
    phone: z.string().min(1),
  }).passthrough(),

  itemCreate: z.object({
    item_code: z.string().min(1),
    item_name: z.string().min(1),
  }).passthrough(),

  invoiceCreate: z.object({
    customer_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    invoice_date: z.string().min(1),
    items: z.array(z.any()).min(1),
  }).passthrough(),

  paymentCreate: z.object({
    payment_date: z.string().min(1),
    amount: z.union([z.number(), z.string()]),
  }).passthrough(),

  expenseCreate: z.object({
    expense_category: z.string().min(1),
    amount: z.union([z.number(), z.string()]),
    expense_date: z.string().min(1),
  }).passthrough(),

  expenseCategoryCreate: z.object({
    category_name: z.string().min(1),
  }).passthrough(),

  employeeCreate: z.object({
    first_name: z.string().min(1),
  }).passthrough(),

  roleCreate: z.object({
    role_name: z.string().min(1),
  }).passthrough(),

  userCreate: z.object({
    username: z.string().min(1),
    email: z.string().min(1),
    password: z.string().min(1),
    full_name: z.string().min(1),
    role_id: z.union([z.number(), z.string()]),
  }).passthrough(),

  // ------------------------------------------------------------------
  // Secondary routers (spec 2.3 — phase-2 completion). Same policy as
  // above: shape-only guards on identity fields; controllers keep the
  // deep business rules (allocation math, transition tables, ledger
  // side effects).
  // ------------------------------------------------------------------

  // Purchase orders
  poCreate: z.object({
    supplier_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    po_date: z.string().min(1),
    items: z.array(z.any()).min(1),
  }).passthrough(),

  poStatus: z.object({
    status: z.enum(['Draft', 'Submitted', 'Partially Received', 'Completed', 'Cancelled']),
  }).passthrough(),

  goodsReceipt: z.object({
    receipt_date: z.string().min(1),
    warehouse_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    items: z.array(z.any()).min(1),
  }).passthrough(),

  // BOM
  bomCreate: z.object({
    finished_item_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    quantity: z.union([z.number(), z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
    bom_name: z.string().min(1),
    items: z.array(z.any()).min(1),
  }).passthrough(),

  // POS
  posSale: z.object({
    warehouse_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    items: z.array(z.any()).min(1),
  }).passthrough(),

  // Production
  productionCreate: z.object({
    output_item_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    output_quantity: z.union([z.number(), z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
    warehouse_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    production_date: z.string().min(1),
    input_items: z.array(z.any()).min(1),
  }).passthrough(),

  // Quotations / sales orders
  quotationCreate: z.object({
    customer_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    quotation_date: z.string().min(1),
    items: z.array(z.any()).min(1),
  }).passthrough(),

  // Purchase returns
  purchaseReturnCreate: z.object({
    return_date: z.string().min(1),
    source_type: z.enum(['PURCHASE', 'PURCHASE_ORDER']),
    source_id: z.union([z.number(), z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
    warehouse_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
  }).passthrough(),

  // Mobile invoices (drafts are flexible; submit mirrors invoiceCreate).
  // Drafts POST/PUT may ship an empty body — optional like [object].
  mobileDraft: z.object({}).passthrough().optional(),

  mobileSubmit: z.object({
    customer_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    invoice_date: z.string().min(1),
    items: z.array(z.any()).min(1),
  }).passthrough(),

  // Owner equity
  ownerCapital: z.object({
    capital_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    amount: z.union([z.number(), z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
  }).passthrough(),

  ownerWithdrawal: z.object({
    withdrawal_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    kind: z.enum(['cash', 'goods']),
  }).passthrough(),

  // Quote may be called with an empty/absent items array — the
  // controller's validateItemLines only errors for goods withdrawals.
  ownerWithdrawalQuote: z.object({
    items: z.array(z.any()).optional(),
  }).passthrough(),

  personalLoanCreate: z.object({
    borrower_name: z.string().min(1),
    amount: z.union([z.number(), z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
    loan_date: z.string().min(1),
  }).passthrough(),

  repaymentCreate: z.object({
    amount: z.union([z.number(), z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
    payment_date: z.string().min(1),
  }).passthrough(),

  // Dashboard
  cashOpeningBalances: z.object({
    accounts: z.array(z.object({
      key: z.string().min(1),
      amount: z.number(),
    })).min(1),
  }).passthrough(),

  dashboardLayoutCreate: z.object({}).passthrough().optional(),

  dashboardLayoutRename: z.object({
    layout_name: z.string().min(1),
  }).passthrough(),

  // Custom reports
  reportCreate: z.object({
    name: z.string().min(1),
  }).passthrough(),

  // Settings / preferences / integrations
  settingUpdate: z.object({
    value: z.unknown().refine(v => v !== undefined && v !== null && v !== '', { message: 'Value is required' }),
  }).passthrough(),

  settingsBulk: z.record(z.string(), z.unknown()),

  preferencesUpdate: z.object({}).passthrough().optional(),

  integrationSettings: z.object({}).passthrough().optional(),

  // Forecasts
  forecastOverride: z.object({}).passthrough().optional(),

  seasonalEvent: z.object({}).passthrough().optional(),

  modelConfig: z.object({}).passthrough().optional(),

  // Activity log cleanup
  cleanupLogs: z.object({
    days: z.union([z.string().regex(/^\d+$/), z.number()]).optional(),
  }).passthrough(),

  // Stock batches (partial PATCH bodies)
  batchExpiry: z.object({
    expiry_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  }).passthrough(),

  batchHalt: z.object({
    reason: z.string().max(500).optional(),
  }).passthrough(),

  // Accounting periods
  periodOpen: z.object({
    period_name: z.string().min(1),
    start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  }).passthrough(),
};

/**
 * Zod validation middleware factory
 * @param schema - Zod schema to validate against
 * @param source - Where to get data from: 'body', 'query', or 'params'
 */
export function validateZod(schema: z.ZodSchema, source: 'body' | 'query' | 'params' = 'body') {
  return (req: Request, res: Response, next: NextFunction): void => {
    try {
      const data = source === 'body' ? req.body : source === 'query' ? req.query : req.params;
      const validated = schema.parse(data);

      if (source === 'body') {
        req.body = validated;
      } else if (source === 'query') {
        Object.assign(req.query, validated);
      } else {
        Object.assign(req.params, validated);
      }

      next();
    } catch (error) {
      if (error instanceof z.ZodError) {
        // Consistent validation envelope (spec 2.3 step 4): the `error`
        // field is an object with code/message/details.
        res.status(400).json({
          success: false,
          error: {
            code: 'VALIDATION_ERROR',
            message: 'Validation failed',
            details: error.issues.map((err: z.ZodIssue) => ({
              field: err.path.join('.'),
              message: err.message,
            })),
          },
        });
        return;
      }
      next(error);
    }
  };
}

export const validateZodBody = (schema: z.ZodSchema) => validateZod(schema, 'body');
export const validateZodQuery = (schema: z.ZodSchema) => validateZod(schema, 'query');
export const validateZodParams = (schema: z.ZodSchema) => validateZod(schema, 'params');


