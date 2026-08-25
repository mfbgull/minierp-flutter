import { Request, Response, NextFunction } from 'express';
import logger from '../utils/logger';
import { sendInternalError } from '../utils/apiResponse';

function errorHandler(
  err: { status?: number; message?: string; stack?: string },
  req: Request,
  res: Response,
  _next: NextFunction
): void {
  const status = err.status || 500;
  const message = err.message || 'Internal server error';

  logger.error('Unhandled error', {
    requestId: req.requestId,
    method: req.method,
    url: req.originalUrl || req.url,
    statusCode: status,
    error: message,
    stack: err.stack,
    userId: req.user?.id,
  });

  if (process.env.NODE_ENV === 'development') {
    res.status(status).json({
      success: false,
      error: {
        code: 'INTERNAL_ERROR',
        message,
        stack: err.stack,
      },
    });
  } else {
    sendInternalError(res);
  }
}

function notFoundHandler(req: Request, res: Response): void {
  res.status(404).json({
    success: false,
    error: {
      code: 'NOT_FOUND',
      message: `Route not found: ${req.path}`,
    },
  });
}

export default { errorHandler, notFoundHandler };
