"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validateZodParams = exports.validateZodQuery = exports.validateZodBody = exports.zodBodySchemas = exports.zodSchemas = void 0;
exports.validateZod = validateZod;
const zod_1 = require("zod");
// ============================================================================
// ZOD VALIDATION SCHEMAS AND MIDDLEWARE
// ============================================================================
/**
 * Common Zod validation schemas for reuse across controllers
 */
exports.zodSchemas = {
    pagination: zod_1.z.object({
        page: zod_1.z.string().regex(/^\d+$/).default('1').transform(Number),
        limit: zod_1.z.string().regex(/^\d+$/).default('10').transform(Number),
    }),
    sorting: (allowedColumns) => zod_1.z.object({
        sortBy: zod_1.z.enum(allowedColumns).optional().default(allowedColumns[0]),
        sortOrder: zod_1.z.enum(['ASC', 'DESC']).optional().default('ASC'),
    }),
    dateRange: zod_1.z.object({
        fromDate: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
        toDate: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    }),
    search: zod_1.z.object({
        search: zod_1.z.string().max(100).optional(),
    }),
    id: zod_1.z.object({
        id: zod_1.z.string().regex(/^\d+$/).transform(Number),
    }),
    status: zod_1.z.object({
        status: zod_1.z.enum(['active', 'inactive', 'all']).optional().default('all'),
    }),
    period: zod_1.z.object({
        period: zod_1.z.string().regex(/^\d+$/).default('30').transform(Number)
            .refine(val => val >= 1 && val <= 3650, {
            message: 'Period must be between 1 and 3650 days'
        }),
    }),
    /**
     * Permissive query validation for GET list routes (spec 2.3):
     * pagination + sorting + date-range params are type-checked, everything
     * else the controllers read (ids, statuses, flags) passes through.
     */
    listQuery: zod_1.z.object({
        page: zod_1.z.string().regex(/^\d+$/).optional().transform(v => (v === undefined ? undefined : Number(v))),
        limit: zod_1.z.string().regex(/^\d+$/).optional().transform(v => (v === undefined ? undefined : Number(v))),
        search: zod_1.z.string().max(100).optional(),
        sortBy: zod_1.z.string().max(50).optional(),
        sortOrder: zod_1.z.string().max(10).optional(),
        start_date: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
        end_date: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
        from_date: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
        to_date: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
        fromDate: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
        toDate: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    }).passthrough(),
};
/**
 * Body schemas for POST/PUT routes (spec 2.3). Every schema is
 * `.passthrough()` so payloads keep their extra fields — controllers
 * still own the deep business rules (XOR counterparties, allocation
 * presence, status transitions) and their error messages.
 */
exports.zodBodySchemas = {
    // Shape-only: the body must be a JSON object when present. Used for
    // complex/partial update bodies whose business validation lives in the
    // controller. Bodies are OPTIONAL here — express.json() leaves
    // `req.body` undefined on empty POST/PUTs (e.g. POST /admin/backup),
    // and Zod would otherwise 400 every bodyless action.
    object: zod_1.z.object({}).passthrough().optional(),
    login: zod_1.z.object({
        username: zod_1.z.string().min(1),
        password: zod_1.z.string().min(1),
    }).passthrough(),
    refresh: zod_1.z.object({
        refreshToken: zod_1.z.string().min(1),
    }).passthrough(),
    changePassword: zod_1.z.object({
        currentPassword: zod_1.z.string().min(1),
        newPassword: zod_1.z.string().min(1),
    }).passthrough(),
    customerCreate: zod_1.z.object({
        customer_name: zod_1.z.string().min(1),
        phone: zod_1.z.string().min(1),
    }).passthrough(),
    itemCreate: zod_1.z.object({
        item_code: zod_1.z.string().min(1),
        item_name: zod_1.z.string().min(1),
    }).passthrough(),
    invoiceCreate: zod_1.z.object({
        customer_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
        invoice_date: zod_1.z.string().min(1),
        items: zod_1.z.array(zod_1.z.any()).min(1),
    }).passthrough(),
    paymentCreate: zod_1.z.object({
        payment_date: zod_1.z.string().min(1),
        amount: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]),
    }).passthrough(),
    expenseCreate: zod_1.z.object({
        expense_category: zod_1.z.string().min(1),
        amount: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]),
        expense_date: zod_1.z.string().min(1),
    }).passthrough(),
    expenseCategoryCreate: zod_1.z.object({
        category_name: zod_1.z.string().min(1),
    }).passthrough(),
    employeeCreate: zod_1.z.object({
        first_name: zod_1.z.string().min(1),
    }).passthrough(),
    roleCreate: zod_1.z.object({
        role_name: zod_1.z.string().min(1),
    }).passthrough(),
    userCreate: zod_1.z.object({
        username: zod_1.z.string().min(1),
        email: zod_1.z.string().min(1),
        password: zod_1.z.string().min(1),
        full_name: zod_1.z.string().min(1),
        role_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]),
    }).passthrough(),
    // ------------------------------------------------------------------
    // Secondary routers (spec 2.3 — phase-2 completion). Same policy as
    // above: shape-only guards on identity fields; controllers keep the
    // deep business rules (allocation math, transition tables, ledger
    // side effects).
    // ------------------------------------------------------------------
    // Purchase orders
    poCreate: zod_1.z.object({
        supplier_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
        po_date: zod_1.z.string().min(1),
        items: zod_1.z.array(zod_1.z.any()).min(1),
    }).passthrough(),
    poStatus: zod_1.z.object({
        status: zod_1.z.enum(['Draft', 'Submitted', 'Partially Received', 'Completed', 'Cancelled']),
    }).passthrough(),
    goodsReceipt: zod_1.z.object({
        receipt_date: zod_1.z.string().min(1),
        warehouse_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
        items: zod_1.z.array(zod_1.z.any()).min(1),
    }).passthrough(),
    // BOM
    bomCreate: zod_1.z.object({
        finished_item_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
        quantity: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
        bom_name: zod_1.z.string().min(1),
        items: zod_1.z.array(zod_1.z.any()).min(1),
    }).passthrough(),
    // POS
    posSale: zod_1.z.object({
        warehouse_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
        items: zod_1.z.array(zod_1.z.any()).min(1),
    }).passthrough(),
    // Production
    productionCreate: zod_1.z.object({
        output_item_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
        output_quantity: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
        warehouse_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
        production_date: zod_1.z.string().min(1),
        input_items: zod_1.z.array(zod_1.z.any()).min(1),
    }).passthrough(),
    // Quotations / sales orders
    quotationCreate: zod_1.z.object({
        customer_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
        quotation_date: zod_1.z.string().min(1),
        items: zod_1.z.array(zod_1.z.any()).min(1),
    }).passthrough(),
    // Purchase returns
    purchaseReturnCreate: zod_1.z.object({
        return_date: zod_1.z.string().min(1),
        source_type: zod_1.z.enum(['PURCHASE', 'PURCHASE_ORDER']),
        source_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
        warehouse_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
    }).passthrough(),
    // Supplier refunds (cash payout against a credit note)
    supplierRefundCreate: zod_1.z.object({
        refund_date: zod_1.z.string().min(1),
        credit_note_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
        amount: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
    }).passthrough(),
    // Mobile invoices (drafts are flexible; submit mirrors invoiceCreate).
    // Drafts POST/PUT may ship an empty body — optional like [object].
    mobileDraft: zod_1.z.object({}).passthrough().optional(),
    mobileSubmit: zod_1.z.object({
        customer_id: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
        invoice_date: zod_1.z.string().min(1),
        items: zod_1.z.array(zod_1.z.any()).min(1),
    }).passthrough(),
    // Owner equity
    ownerCapital: zod_1.z.object({
        capital_date: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        amount: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
    }).passthrough(),
    ownerWithdrawal: zod_1.z.object({
        withdrawal_date: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        kind: zod_1.z.enum(['cash', 'goods']),
    }).passthrough(),
    // Quote may be called with an empty/absent items array — the
    // controller's validateItemLines only errors for goods withdrawals.
    ownerWithdrawalQuote: zod_1.z.object({
        items: zod_1.z.array(zod_1.z.any()).optional(),
    }).passthrough(),
    personalLoanCreate: zod_1.z.object({
        borrower_name: zod_1.z.string().min(1),
        amount: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
        loan_date: zod_1.z.string().min(1),
    }).passthrough(),
    repaymentCreate: zod_1.z.object({
        amount: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).refine(v => Number(v) > 0, { message: 'Must be positive' }),
        payment_date: zod_1.z.string().min(1),
    }).passthrough(),
    // Dashboard
    cashOpeningBalances: zod_1.z.object({
        accounts: zod_1.z.array(zod_1.z.object({
            key: zod_1.z.string().min(1),
            amount: zod_1.z.number(),
        })).min(1),
    }).passthrough(),
    dashboardLayoutCreate: zod_1.z.object({}).passthrough().optional(),
    dashboardLayoutRename: zod_1.z.object({
        layout_name: zod_1.z.string().min(1),
    }).passthrough(),
    // Custom reports
    reportCreate: zod_1.z.object({
        name: zod_1.z.string().min(1),
    }).passthrough(),
    // Settings / preferences / integrations
    settingUpdate: zod_1.z.object({
        value: zod_1.z.unknown().refine(v => v !== undefined && v !== null && v !== '', { message: 'Value is required' }),
    }).passthrough(),
    settingsBulk: zod_1.z.record(zod_1.z.string(), zod_1.z.unknown()),
    preferencesUpdate: zod_1.z.object({}).passthrough().optional(),
    integrationSettings: zod_1.z.object({}).passthrough().optional(),
    // Forecasts
    forecastOverride: zod_1.z.object({}).passthrough().optional(),
    seasonalEvent: zod_1.z.object({}).passthrough().optional(),
    modelConfig: zod_1.z.object({}).passthrough().optional(),
    // Activity log cleanup
    cleanupLogs: zod_1.z.object({
        days: zod_1.z.union([zod_1.z.string().regex(/^\d+$/), zod_1.z.number()]).optional(),
    }).passthrough(),
    // Stock batches (partial PATCH bodies)
    batchExpiry: zod_1.z.object({
        expiry_date: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    }).passthrough(),
    batchHalt: zod_1.z.object({
        reason: zod_1.z.string().max(500).optional(),
    }).passthrough(),
    // Accounting periods
    periodOpen: zod_1.z.object({
        period_name: zod_1.z.string().min(1),
        start_date: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        end_date: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    }).passthrough(),
};
/**
 * Zod validation middleware factory
 * @param schema - Zod schema to validate against
 * @param source - Where to get data from: 'body', 'query', or 'params'
 */
function validateZod(schema, source = 'body') {
    return (req, res, next) => {
        try {
            const data = source === 'body' ? req.body : source === 'query' ? req.query : req.params;
            const validated = schema.parse(data);
            if (source === 'body') {
                req.body = validated;
            }
            else if (source === 'query') {
                Object.assign(req.query, validated);
            }
            else {
                Object.assign(req.params, validated);
            }
            next();
        }
        catch (error) {
            if (error instanceof zod_1.z.ZodError) {
                // Consistent validation envelope (spec 2.3 step 4): the `error`
                // field is an object with code/message/details.
                res.status(400).json({
                    success: false,
                    error: {
                        code: 'VALIDATION_ERROR',
                        message: 'Validation failed',
                        details: error.issues.map((err) => ({
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
const validateZodBody = (schema) => validateZod(schema, 'body');
exports.validateZodBody = validateZodBody;
const validateZodQuery = (schema) => validateZod(schema, 'query');
exports.validateZodQuery = validateZodQuery;
const validateZodParams = (schema) => validateZod(schema, 'params');
exports.validateZodParams = validateZodParams;
