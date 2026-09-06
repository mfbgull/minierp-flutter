"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const rolesController_1 = __importDefault(require("../controllers/rolesController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const validation_1 = require("../middleware/validation");
// All role routes require authentication
router.use(auth_1.authenticateToken);
router.get('/', (0, requirePermission_1.requirePermission)('roles', 'read'), rolesController_1.default.getRoles);
router.get('/permissions', (0, requirePermission_1.requirePermission)('roles', 'read'), rolesController_1.default.getPermissions);
router.get('/:id/permissions', (0, requirePermission_1.requirePermission)('roles', 'read'), rolesController_1.default.getRolePermissions);
router.post('/', (0, requirePermission_1.requirePermission)('roles', 'create'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.roleCreate), rolesController_1.default.createRole);
router.put('/:id', (0, requirePermission_1.requirePermission)('roles', 'update'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.object), rolesController_1.default.updateRole);
router.put('/:id/permissions', (0, requirePermission_1.requirePermission)('roles', 'update'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.object), rolesController_1.default.updateRolePermissions);
router.delete('/:id', (0, requirePermission_1.requirePermission)('roles', 'delete'), rolesController_1.default.deleteRole);
exports.default = router;
