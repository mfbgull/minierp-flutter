import { Response } from 'express';

interface ApiErrorResponse {
  success: false;
  error: {
    code: string;
    message: string;
    details?: Record<string, unknown>;
  };
}

interface ApiSuccessResponse<T = unknown> {
  success: true;
  data: T;
  meta?: {
    page?: number;
    limit?: number;
    total?: number;
    totalPages?: number;
  };
}

export function sendSuccess<T>(
  res: Response,
  data: T,
  statusCode: number = 200,
  meta?: ApiSuccessResponse<T>['meta']
): void {
  const response: ApiSuccessResponse<T> = { success: true, data };
  if (meta) response.meta = meta;
  res.status(statusCode).json(response);
}

export function sendCreated<T>(res: Response, data: T): void {
  sendSuccess(res, data, 201);
}

function sendError(
  res: Response,
  statusCode: number,
  code: string,
  message: string,
  details?: Record<string, unknown>
): void {
  const response: ApiErrorResponse = {
    success: false,
    error: { code, message },
  };
  if (details) response.error.details = details;
  res.status(statusCode).json(response);
}

export function sendBadRequest(res: Response, message: string = 'Bad request'): void {
  sendError(res, 400, 'INVALID_INPUT', message);
}

export function sendUnauthorized(res: Response, message: string = 'Unauthorized'): void {
  sendError(res, 401, 'UNAUTHORIZED', message);
}

export function sendForbidden(res: Response, message: string = 'Forbidden'): void {
  sendError(res, 403, 'FORBIDDEN', message);
}

export function sendNotFound(res: Response, resource: string = 'Resource'): void {
  sendError(res, 404, 'RESOURCE_NOT_FOUND', `${resource} not found`);
}

export function sendConflict(res: Response, message: string = 'Resource already exists'): void {
  sendError(res, 409, 'RESOURCE_ALREADY_EXISTS', message);
}

export function sendInternalError(res: Response, message: string = 'Internal server error'): void {
  sendError(res, 500, 'INTERNAL_SERVER_ERROR', message);
}
