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
        res.status(400).json({
          success: false,
          error: 'Validation failed',
          details: error.issues.map((err: z.ZodIssue) => ({
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

export const validateZodBody = (schema: z.ZodSchema) => validateZod(schema, 'body');
export const validateZodQuery = (schema: z.ZodSchema) => validateZod(schema, 'query');
export const validateZodParams = (schema: z.ZodSchema) => validateZod(schema, 'params');


