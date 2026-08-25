"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const userController_1 = __importDefault(require("../controllers/userController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
// All user routes require authentication
router.use(auth_1.authenticateToken);
router.get('/', (0, requirePermission_1.requirePermission)('users', 'read'), userController_1.default.getUsers);
router.get('/:id', (0, requirePermission_1.requirePermission)('users', 'read'), userController_1.default.getUser);
router.post('/', (0, requirePermission_1.requirePermission)('users', 'create'), userController_1.default.createUser);
router.put('/:id', (0, requirePermission_1.requirePermission)('users', 'update'), userController_1.default.updateUser);
router.delete('/:id', (0, requirePermission_1.requirePermission)('users', 'delete'), userController_1.default.deleteUser);
router.put('/:id/reset-password', (0, requirePermission_1.requirePermission)('users', 'update'), userController_1.default.resetPassword);
router.put('/:id/toggle-status', (0, requirePermission_1.requirePermission)('users', 'update'), userController_1.default.toggleUserStatus);
exports.default = router;
