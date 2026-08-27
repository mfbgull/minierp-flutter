"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const rateLimiter_1 = require("../middleware/rateLimiter");
const ownerEquityController_1 = __importDefault(require("../controllers/ownerEquityController"));
router.use(auth_1.authenticateToken);
// Shared
router.get('/summary', (0, requirePermission_1.requirePermission)('owner_equity', 'read'), ownerEquityController_1.default.getSummary);
router.get('/payment-method-options', (0, requirePermission_1.requirePermission)('owner_equity', 'read'), ownerEquityController_1.default.getPaymentMethodOptions);
// Owner capital
router.post('/capital', (0, requirePermission_1.requirePermission)('owner_equity', 'create'), rateLimiter_1.sensitiveOperationLimiter, ownerEquityController_1.default.createCapital);
router.get('/capital', (0, requirePermission_1.requirePermission)('owner_equity', 'read'), ownerEquityController_1.default.getCapitalList);
router.put('/capital/:id', (0, requirePermission_1.requirePermission)('owner_equity', 'edit'), rateLimiter_1.sensitiveOperationLimiter, ownerEquityController_1.default.updateCapital);
router.delete('/capital/:id', (0, requirePermission_1.requirePermission)('owner_equity', 'delete'), rateLimiter_1.sensitiveOperationLimiter, ownerEquityController_1.default.voidCapital);
// Owner withdrawals (quote must precede /:id routes)
router.post('/withdrawals/quote', (0, requirePermission_1.requirePermission)('owner_equity', 'read'), ownerEquityController_1.default.quoteWithdrawal);
router.post('/withdrawals', (0, requirePermission_1.requirePermission)('owner_equity', 'create'), rateLimiter_1.sensitiveOperationLimiter, ownerEquityController_1.default.createWithdrawal);
router.get('/withdrawals', (0, requirePermission_1.requirePermission)('owner_equity', 'read'), ownerEquityController_1.default.getWithdrawalList);
router.get('/withdrawals/:id', (0, requirePermission_1.requirePermission)('owner_equity', 'read'), ownerEquityController_1.default.getWithdrawalById);
router.put('/withdrawals/:id', (0, requirePermission_1.requirePermission)('owner_equity', 'edit'), rateLimiter_1.sensitiveOperationLimiter, ownerEquityController_1.default.updateWithdrawal);
router.delete('/withdrawals/:id', (0, requirePermission_1.requirePermission)('owner_equity', 'delete'), rateLimiter_1.sensitiveOperationLimiter, ownerEquityController_1.default.voidWithdrawal);
exports.default = router;
