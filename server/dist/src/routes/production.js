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
const productionController_1 = __importDefault(require("../controllers/productionController"));
router.use(auth_1.authenticateToken);
router.post('/productions', (0, requirePermission_1.requirePermission)('production', 'create'), rateLimiter_1.sensitiveOperationLimiter, productionController_1.default.recordProduction);
router.get('/productions', (0, requirePermission_1.requirePermission)('production', 'read'), productionController_1.default.getProductions);
router.get('/productions/:id', (0, requirePermission_1.requirePermission)('production', 'read'), productionController_1.default.getProduction);
router.delete('/productions/:id', (0, requirePermission_1.requirePermission)('production', 'delete'), rateLimiter_1.sensitiveOperationLimiter, productionController_1.default.deleteProduction);
router.get('/productions/summary/item/:item_id', (0, requirePermission_1.requirePermission)('production', 'read'), productionController_1.default.getProductionSummaryByItem);
exports.default = router;
//# sourceMappingURL=production.js.map