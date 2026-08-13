"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const preferencesController_1 = __importDefault(require("../controllers/preferencesController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
router.use(auth_1.authenticateToken);
router.get('/', (0, requirePermission_1.requirePermission)('settings', 'read'), preferencesController_1.default.getPreferences);
router.put('/', (0, requirePermission_1.requirePermission)('settings', 'update'), preferencesController_1.default.updatePreferences);
exports.default = router;
//# sourceMappingURL=preferences.js.map