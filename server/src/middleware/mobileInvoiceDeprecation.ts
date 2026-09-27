import { NextFunction, Request, Response } from 'express';

const SUCCESSOR_ENDPOINT = '/api/invoices';

/**
 * Mark the legacy mobile invoice surface without changing its response body.
 * The middleware runs before authentication so clients receive the migration
 * signal even when a request is rejected for missing or invalid credentials.
 */
export function markMobileInvoiceApiDeprecated(
  _req: Request,
  res: Response,
  next: NextFunction,
): void {
  res.setHeader('Deprecation', 'true');
  res.setHeader(
    'Warning',
    `299 mini-erp "The /api/mobile-invoices API is deprecated; use ${SUCCESSOR_ENDPOINT}."`,
  );
  res.setHeader('Link', `<${SUCCESSOR_ENDPOINT}>; rel="successor-version"`);
  res.setHeader('X-Deprecated-Endpoint', '/api/mobile-invoices');
  next();
}
