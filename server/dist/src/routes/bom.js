"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const bomController_1 = require("../controllers/bomController");
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const validation_1 = require("../middleware/validation");
// All BOM routes require authentication
router.use(auth_1.authenticateToken);
router.get('/', (0, requirePermission_1.requirePermission)('bom', 'read'), bomController_1.getAllBOMs);
router.get('/:id', (0, requirePermission_1.requirePermission)('bom', 'read'), bomController_1.getBOMById);
router.get('/by-item/:itemId', (0, requirePermission_1.requirePermission)('bom', 'read'), bomController_1.getBOMsByFinishedItem);
router.post('/', (0, requirePermission_1.requirePermission)('bom', 'create'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.bomCreate), bomController_1.createBOM);
router.put('/:id', (0, requirePermission_1.requirePermission)('bom', 'update'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.object), bomController_1.updateBOM);
router.patch('/:id/toggle-active', (0, requirePermission_1.requirePermission)('bom', 'update'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.object), bomController_1.toggleBOMActive);
router.delete('/:id', (0, requirePermission_1.requirePermission)('bom', 'delete'), bomController_1.deleteBOM);
exports.default = router;
