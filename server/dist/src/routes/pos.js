"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const posController_1 = __importDefault(require("../controllers/posController"));
router.use(auth_1.authenticateToken);
router.post('/sale', (0, requirePermission_1.requirePermission)('pos', 'create'), posController_1.default.createPOSSale);
router.get('/transactions', (0, requirePermission_1.requirePermission)('pos', 'read'), posController_1.default.getPOSTransactions);
exports.default = router;
//# sourceMappingURL=pos.js.map