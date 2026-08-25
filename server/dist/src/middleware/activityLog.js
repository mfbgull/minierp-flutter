"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.newCorrelationId = newCorrelationId;
exports.activityLogBackstop = activityLogBackstop;
const activityLogger_1 = __importStar(require("../services/activityLogger"));
/** route pattern → entity/action mapping for mutating endpoints */
const ROUTE_MAP = [
    { method: 'POST', re: /\/api\/invoices\/?$/, meta: { action: activityLogger_1.ActionType.INVOICE_CREATE, entityType: 'Invoice' } },
    { method: 'PUT', re: /\/api\/invoices\/(\d+)$/, meta: { action: activityLogger_1.ActionType.INVOICE_UPDATE, entityType: 'Invoice' } },
    { method: 'DELETE', re: /\/api\/invoices\/(\d+)$/, meta: { action: activityLogger_1.ActionType.INVOICE_DELETE, entityType: 'Invoice' } },
    { method: 'POST', re: /\/api\/payments\/?$/, meta: { action: activityLogger_1.ActionType.PAYMENT_CREATE, entityType: 'Payment' } },
    { method: 'DELETE', re: /\/api\/payments\/(\d+)$/, meta: { action: activityLogger_1.ActionType.PAYMENT_DELETE, entityType: 'Payment' } },
    { method: 'POST', re: /\/api\/customers\/?$/, meta: { action: activityLogger_1.ActionType.CUSTOMER_CREATE, entityType: 'Customer' } },
    { method: 'PUT', re: /\/api\/customers\/(\d+)$/, meta: { action: activityLogger_1.ActionType.CUSTOMER_UPDATE, entityType: 'Customer' } },
    { method: 'DELETE', re: /\/api\/customers\/(\d+)$/, meta: { action: activityLogger_1.ActionType.CUSTOMER_DELETE, entityType: 'Customer' } },
    { method: 'POST', re: /\/api\/suppliers\/?$/, meta: { action: activityLogger_1.ActionType.SUPPLIER_CREATE, entityType: 'Supplier' } },
    { method: 'PUT', re: /\/api\/suppliers\/(\d+)$/, meta: { action: activityLogger_1.ActionType.SUPPLIER_UPDATE, entityType: 'Supplier' } },
    { method: 'DELETE', re: /\/api\/suppliers\/(\d+)$/, meta: { action: activityLogger_1.ActionType.SUPPLIER_DELETE, entityType: 'Supplier' } },
    { method: 'POST', re: /\/api\/inventory\/items\/?$/, meta: { action: activityLogger_1.ActionType.ITEM_CREATE, entityType: 'Item' } },
    { method: 'PUT', re: /\/api\/inventory\/items\/(\d+)$/, meta: { action: activityLogger_1.ActionType.ITEM_UPDATE, entityType: 'Item' } },
    { method: 'DELETE', re: /\/api\/inventory\/items\/(\d+)$/, meta: { action: activityLogger_1.ActionType.ITEM_DELETE, entityType: 'Item' } },
    { method: 'POST', re: /\/api\/inventory\/warehouses\/?$/, meta: { action: activityLogger_1.ActionType.WAREHOUSE_CREATE, entityType: 'Warehouse' } },
    { method: 'PUT', re: /\/api\/inventory\/warehouses\/(\d+)$/, meta: { action: activityLogger_1.ActionType.WAREHOUSE_UPDATE, entityType: 'Warehouse' } },
    { method: 'POST', re: /\/api\/inventory\/stock-movements\/?$/, meta: { action: activityLogger_1.ActionType.STOCK_MOVEMENT, entityType: 'StockMovement' } },
    { method: 'POST', re: /\/api\/inventory\/stock-transfers\/?$/, meta: { action: activityLogger_1.ActionType.STOCK_MOVEMENT, entityType: 'StockTransfer' } },
    { method: 'POST', re: /\/api\/expenses\/?$/, meta: { action: activityLogger_1.ActionType.EXPENSE_CREATE, entityType: 'Expense' } },
    { method: 'PUT', re: /\/api\/expenses\/(\d+)$/, meta: { action: activityLogger_1.ActionType.EXPENSE_UPDATE, entityType: 'Expense' } },
    { method: 'DELETE', re: /\/api\/expenses\/(\d+)$/, meta: { action: activityLogger_1.ActionType.EXPENSE_DELETE, entityType: 'Expense' } },
];
function newCorrelationId() {
    return `corr-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}
/**
 * Stamp correlationId on the request; run the handler; on 2xx of a mapped
 * mutating route write exactly one backstop row when none was logged already.
 */
function activityLogBackstop(req, res, next) {
    const authReq = req;
    authReq.correlationId = newCorrelationId();
    res.locals.activityLogged = false;
    const match = ROUTE_MAP.find((r) => r.method === req.method && r.re.test(req.path));
    res.on('finish', () => {
        if (!match)
            return;
        if (res.statusCode < 200 || res.statusCode >= 300)
            return;
        // Controllers signal "already logged" via either flag (task 4.3)
        if (res.locals.activityLogged || req.activityLogged)
            return;
        const m = req.path.match(match.re);
        const idRaw = m && m[1] ? parseInt(m[1], 10) : NaN;
        const user = req.user;
        activityLogger_1.default.log({
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
