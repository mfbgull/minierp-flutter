import type { Request, Response, NextFunction } from 'express';

export function jsonBodyErrorHandler(error: unknown, _req: Request, res: Response, next: NextFunction): void {
  if (error instanceof SyntaxError && 'type' in error && error.type === 'entity.parse.failed') {
    res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: 'Malformed JSON body' } });
    return;
  }
  next(error);
}
