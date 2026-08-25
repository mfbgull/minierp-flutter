"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const authController_1 = __importDefault(require("../controllers/authController"));
const auth_1 = require("../middleware/auth");
const rateLimiter_1 = require("../middleware/rateLimiter");
router.post('/login', rateLimiter_1.authLimiter, authController_1.default.login);
router.post('/logout', auth_1.authenticateToken, authController_1.default.logout);
router.get('/me', auth_1.authenticateToken, authController_1.default.getCurrentUser);
router.post('/change-password', auth_1.authenticateToken, rateLimiter_1.passwordChangeLimiter, authController_1.default.changePassword);
exports.default = router;
