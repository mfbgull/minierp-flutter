"use strict";
/**
 * Accounting Routes
 * -----------------
 * REST surface for the chart of accounts and accounting periods.
 *
 * Mount point: /api/accounting
 *
 * Auth:
 *   - All routes are gated by authenticateToken.
 *   - State-changing routes (POST /periods, POST /periods/:id/close) are
 *     gated by requireAdmin on top of the token check.
 *
 *   Note: we apply the admin guard inside the controller rather than as
 *   router-level middleware so that we can return our own JSON error
 *   shape via sendForbidden() instead of a bare 403 from the middleware.
 *
 * Rate limiting: the global apiLimiter (in app.ts) covers all /api routes.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const rateLimiter_1 = require("../middleware/rateLimiter");
const accountingController_1 = __importDefault(require("../controllers/accountingController"));
const router = (0, express_1.Router)();
// All endpoints require authentication.
router.use(auth_1.authenticateToken);
// ---- Chart of accounts -----------------------------------------------------
// GET /api/accounting/accounts
router.get('/accounts', (0, requirePermission_1.requirePermission)('accounting', 'read'), accountingController_1.default.listAccounts);
// GET /api/accounting/accounts/balances  (must come before /:code so it
// doesn't get captured as a "code" param)
router.get('/accounts/balances', (0, requirePermission_1.requirePermission)('accounting', 'read'), accountingController_1.default.listAccountBalances);
// GET /api/accounting/accounts/:code
router.get('/accounts/:code', (0, requirePermission_1.requirePermission)('accounting', 'read'), accountingController_1.default.getAccount);
// GET /api/accounting/accounts/:code/balance
router.get('/accounts/:code/balance', (0, requirePermission_1.requirePermission)('accounting', 'read'), accountingController_1.default.getAccountBalance);
// ---- Accounting periods ----------------------------------------------------
// GET /api/accounting/periods
router.get('/periods', (0, requirePermission_1.requirePermission)('accounting', 'read'), accountingController_1.default.listPeriods);
// GET /api/accounting/periods/current  (must come before /:id)
router.get('/periods/current', (0, requirePermission_1.requirePermission)('accounting', 'read'), accountingController_1.default.getCurrentPeriod);
// GET /api/accounting/periods/:id
router.get('/periods/:id', (0, requirePermission_1.requirePermission)('accounting', 'read'), accountingController_1.default.getPeriod);
// POST /api/accounting/periods  (sensitive operation; admin gated inside controller)
router.post('/periods', (0, requirePermission_1.requirePermission)('accounting', 'update'), rateLimiter_1.sensitiveOperationLimiter, accountingController_1.default.openPeriod);
// POST /api/accounting/periods/:id/close  (sensitive operation)
router.post('/periods/:id/close', (0, requirePermission_1.requirePermission)('accounting', 'update'), rateLimiter_1.sensitiveOperationLimiter, accountingController_1.default.closePeriod);
exports.default = router;
//# sourceMappingURL=accounting.js.map