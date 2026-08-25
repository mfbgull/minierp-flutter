"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const bcrypt_1 = __importDefault(require("bcrypt"));
const auth_1 = require("../middleware/auth");
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const User_1 = __importDefault(require("../models/User"));
const logger_1 = __importDefault(require("../utils/logger"));
const apiResponse_1 = require("../utils/apiResponse");
function login(req, res) {
    try {
        const { username, password } = req.body;
        const ipAddress = req.ip || req.get('x-forwarded-for') || req.get('x-real-ip');
        if (!username || !password) {
            (0, apiResponse_1.sendBadRequest)(res, 'Username and password required');
            return;
        }
        const user = User_1.default.findByUsername(username, database_1.default);
        if (!user) {
            (0, activityLogger_1.logAuth)(activityLogger_1.ActionType.LOGIN_FAILED, undefined, `Failed login attempt for user: ${username}`, { username }, ipAddress);
            req.activityLogged = true;
            (0, apiResponse_1.sendUnauthorized)(res, 'Invalid username or password');
            return;
        }
        const passwordMatch = bcrypt_1.default.compareSync(password, user.password_hash);
        if (!passwordMatch) {
            (0, activityLogger_1.logAuth)(activityLogger_1.ActionType.LOGIN_FAILED, user.id, `Failed login attempt for user: ${username}`, { username }, ipAddress);
            req.activityLogged = true;
            (0, apiResponse_1.sendUnauthorized)(res, 'Invalid username or password');
            return;
        }
        const token = (0, auth_1.generateToken)({ id: user.id, username: user.username, email: user.email, role: user.role });
        (0, activityLogger_1.logAuth)(activityLogger_1.ActionType.LOGIN, user.id, `User ${username} logged in successfully`, { username, email: user.email }, ipAddress);
        req.activityLogged = true;
        const { password_hash: _password_hash, ...userWithoutPassword } = user;
        res.cookie('token', token, { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'strict', maxAge: 24 * 60 * 60 * 1000 });
        // PORTING.md §0: desktop Flutter has no cookie jar — also return the
        // JWT in the body so the native client can store it as a Bearer token.
        (0, apiResponse_1.sendSuccess)(res, { token, user: userWithoutPassword });
    }
    catch (error) {
        logger_1.default.error('Login error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Login failed');
    }
}
function logout(req, res) {
    try {
        (0, activityLogger_1.logAuth)(activityLogger_1.ActionType.LOGOUT, req.user?.id, `User ${req.user?.username} logged out`);
        req.activityLogged = true;
        res.clearCookie('token');
        (0, apiResponse_1.sendSuccess)(res, { message: 'Logged out successfully' });
    }
    catch (error) {
        logger_1.default.error('Logout error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Logout failed');
    }
}
function getCurrentUser(req, res) {
    try {
        const user = User_1.default.getById(req.user.id, database_1.default);
        if (!user) {
            (0, apiResponse_1.sendNotFound)(res, 'User');
            return;
        }
        (0, apiResponse_1.sendSuccess)(res, user);
    }
    catch (error) {
        logger_1.default.error('Get current user error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to get user info');
    }
}
function changePassword(req, res) {
    try {
        const { currentPassword, newPassword } = req.body;
        if (!currentPassword || !newPassword) {
            (0, apiResponse_1.sendBadRequest)(res, 'Current and new password required');
            return;
        }
        if (newPassword.length < 6) {
            (0, apiResponse_1.sendBadRequest)(res, 'New password must be at least 6 characters');
            return;
        }
        const user = User_1.default.getPasswordHash(req.user.id, database_1.default);
        if (!user) {
            (0, apiResponse_1.sendNotFound)(res, 'User');
            return;
        }
        const passwordMatch = bcrypt_1.default.compareSync(currentPassword, user.password_hash);
        if (!passwordMatch) {
            (0, apiResponse_1.sendUnauthorized)(res, 'Current password is incorrect');
            return;
        }
        User_1.default.updatePassword(req.user.id, bcrypt_1.default.hashSync(newPassword, 12), database_1.default);
        (0, activityLogger_1.logAuth)(activityLogger_1.ActionType.PASSWORD_CHANGE, req.user.id, 'Password changed successfully');
        req.activityLogged = true;
        (0, apiResponse_1.sendSuccess)(res, { message: 'Password changed successfully' });
    }
    catch (error) {
        logger_1.default.error('Change password error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to change password');
    }
}
exports.default = { login, logout, getCurrentUser, changePassword };
