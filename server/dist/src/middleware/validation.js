"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validateZodParams = exports.validateZodQuery = exports.validateZodBody = exports.zodSchemas = void 0;
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
                res.status(400).json({
                    success: false,
                    error: 'Validation failed',
                    details: error.issues.map((err) => ({
                        field: err.path.join('.'),
                        message: err.message,
                    })),
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
