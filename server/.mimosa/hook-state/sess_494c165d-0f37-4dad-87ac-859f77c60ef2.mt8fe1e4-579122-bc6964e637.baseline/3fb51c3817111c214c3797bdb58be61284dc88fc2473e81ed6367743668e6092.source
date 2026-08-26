/**
 * Activity-log backstop middleware (audit-remediation task 4.3).
 *
 * After a 2xx response on a mutating verb, writes ONE trail row for the
 * request — unless the controller/service already logged one
 * (`res.locals.activityLogged`). Correlation id is stamped per request and
 * exposed via `req.correlationId` so services can join their rows to it.
 */
import { Request, Response, NextFunction } from 'express';
import activityLogger, { ActionType } from '../services/activityLogger';
import { AuthRequest } from '../types';

interface RouteMeta {
  action: ActionType | string;
  entityType: string;
}

/** route pattern → entity/action mapping for mutating endpoints */
const ROUTE_MAP: Array<{ method: string; re: RegExp; meta: RouteMeta }> = [
  { method: 'POST', re: /\/api\/invoices\/?$/, meta: { action: ActionType.INVOICE_CREATE, entityType: 'Invoice' } },
  { method: 'PUT', re: /\/api\/invoices\/(\d+)$/, meta: { action: ActionType.INVOICE_UPDATE, entityType: 'Invoice' } },
  { method: 'DELETE', re: /\/api\/invoices\/(\d+)$/, meta: { action: ActionType.INVOICE_DELETE, entityType: 'Invoice' } },
  { method: 'POST', re: /\/api\/payments\/?$/, meta: { action: ActionType.PAYMENT_CREATE, entityType: 'Payment' } },
  { method: 'DELETE', re: /\/api\/payments\/(\d+)$/, meta: { action: ActionType.PAYMENT_DELETE, entityType: 'Payment' } },
  { method: 'POST', re: /\/api\/customers\/?$/, meta: { action: ActionType.CUSTOMER_CREATE, entityType: 'Customer' } },
  { method: 'PUT', re: /\/api\/customers\/(\d+)$/, meta: { action: ActionType.CUSTOMER_UPDATE, entityType: 'Customer' } },
  { method: 'DELETE', re: /\/api\/customers\/(\d+)$/, meta: { action: ActionType.CUSTOMER_DELETE, entityType: 'Customer' } },
  { method: 'POST', re: /\/api\/suppliers\/?$/, meta: { action: ActionType.SUPPLIER_CREATE, entityType: 'Supplier' } },
  { method: 'PUT', re: /\/api\/suppliers\/(\d+)$/, meta: { action: ActionType.SUPPLIER_UPDATE, entityType: 'Supplier' } },
  { method: 'DELETE', re: /\/api\/suppliers\/(\d+)$/, meta: { action: ActionType.SUPPLIER_DELETE, entityType: 'Supplier' } },
  { method: 'POST', re: /\/api\/inventory\/items\/?$/, meta: { action: ActionType.ITEM_CREATE, entityType: 'Item' } },
  { method: 'PUT', re: /\/api\/inventory\/items\/(\d+)$/, meta: { action: ActionType.ITEM_UPDATE, entityType: 'Item' } },
  { method: 'DELETE', re: /\/api\/inventory\/items\/(\d+)$/, meta: { action: ActionType.ITEM_DELETE, entityType: 'Item' } },
  { method: 'POST', re: /\/api\/inventory\/warehouses\/?$/, meta: { action: ActionType.WAREHOUSE_CREATE, entityType: 'Warehouse' } },
  { method: 'PUT', re: /\/api\/inventory\/warehouses\/(\d+)$/, meta: { action: ActionType.WAREHOUSE_UPDATE, entityType: 'Warehouse' } },
  { method: 'POST', re: /\/api\/inventory\/stock-movements\/?$/, meta: { action: ActionType.STOCK_MOVEMENT, entityType: 'StockMovement' } },
  { method: 'POST', re: /\/api\/inventory\/stock-transfers\/?$/, meta: { action: ActionType.STOCK_MOVEMENT, entityType: 'StockTransfer' } },
  { method: 'POST', re: /\/api\/expenses\/?$/, meta: { action: ActionType.EXPENSE_CREATE, entityType: 'Expense' } },
  { method: 'PUT', re: /\/api\/expenses\/(\d+)$/, meta: { action: ActionType.EXPENSE_UPDATE, entityType: 'Expense' } },
  { method: 'DELETE', re: /\/api\/expenses\/(\d+)$/, meta: { action: ActionType.EXPENSE_DELETE, entityType: 'Expense' } },
];

export function newCorrelationId(): string {
  return `corr-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

/**
 * Stamp correlationId on the request; run the handler; on 2xx of a mapped
 * mutating route write exactly one backstop row when none was logged already.
 */
export function activityLogBackstop(req: Request, res: Response, next: NextFunction): void {
  const authReq = req as AuthRequest & { correlationId?: string; activityLogged?: boolean };
  authReq.correlationId = newCorrelationId();
  res.locals.activityLogged = false;

  const match = ROUTE_MAP.find((r) => r.method === req.method && r.re.test(req.path));

  res.on('finish', () => {
    if (!match) return;
    if (res.statusCode < 200 || res.statusCode >= 300) return;
    // Controllers signal "already logged" via either flag (task 4.3)
    if (res.locals.activityLogged || (req as AuthRequest & { activityLogged?: boolean }).activityLogged) return;

    const m = req.path.match(match.re);
    const idRaw = m && m[1] ? parseInt(m[1], 10) : NaN;
    const user = (req as AuthRequest).user;
    activityLogger.log({
      userId: user?.id,
      action: match.meta.action,
      entityType: match.meta.entityType,
      entityId: Number.isFinite(idRaw) ? idRaw : undefined,
      description: `${match.meta.action} ${match.meta.entityType}${Number.isFinite(idRaw) ? ` #${idRaw}` : ''} (${req.method} ${req.path})`,
      ipAddress: req.ip,
      userAgent: req.get?.('user-agent'),
      correlationId: authReq.correlationId
    });
  });

  next();
}
