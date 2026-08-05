"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const settingsController_1 = __importDefault(require("../controllers/settingsController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
router.use(auth_1.authenticateToken);
router.get('/', (0, requirePermission_1.requirePermission)('settings', 'read'), settingsController_1.default.getSettings);
router.get('/:key', (0, requirePermission_1.requirePermission)('settings', 'read'), settingsController_1.default.getSetting);
router.put('/:key', (0, requirePermission_1.requirePermission)('settings', 'update'), settingsController_1.default.updateSetting);
router.post('/bulk', (0, requirePermission_1.requirePermission)('settings', 'update'), settingsController_1.default.updateSettings);
exports.default = router;
//# sourceMappingURL=settings.js.map