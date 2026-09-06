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
    // Shape-only: the body must be a JSON object. Used for complex/partial
    // update bodies whose business validation lives in the controller.
    object: zod_1.z.object({}).passthrough(),
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
