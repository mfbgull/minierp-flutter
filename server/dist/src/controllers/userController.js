"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const bcrypt_1 = __importDefault(require("bcrypt"));
const activityLogger_1 = require("../services/activityLogger");
const logger_1 = __importDefault(require("../utils/logger"));
const User_1 = __importDefault(require("../models/User"));
const Role_1 = __importDefault(require("../models/Role"));
function getUsers(req, res) {
    try {
        const { role, is_active, search } = req.query;
        const users = User_1.default.getAll({ role, is_active, search }, database_1.default);
        res.json({ success: true, data: users });
    }
    catch (error) {
        logger_1.default.error('Get users error:', error);
        res.status(500).json({ error: 'Failed to fetch users' });
    }
}
function getUser(req, res) {
    try {
        const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const user = User_1.default.getPublicById(id, database_1.default);
        if (!user) {
            res.status(404).json({ error: 'User not found' });
            return;
        }
        res.json({ success: true, data: user });
    }
    catch (error) {
        logger_1.default.error('Get user error:', error);
        res.status(500).json({ error: 'Failed to fetch user' });
    }
}
function createUser(req, res) {
    try {
        const { username, email, password, full_name, role_id, is_active = true } = req.body;
        if (!username || !email || !password || !full_name || !role_id) {
            res.status(400).json({ error: 'Username, email, password, full name, and role are required' });
            return;
        }
        if (!User_1.default.roleExists(database_1.default, role_id)) {
            res.status(400).json({ error: 'Invalid role' });
            return;
        }
        if (User_1.default.usernameExists(database_1.default, username)) {
            res.status(409).json({ error: 'Username already exists' });
            return;
        }
        if (User_1.default.emailExists(database_1.default, email)) {
            res.status(409).json({ error: 'Email already exists' });
            return;
        }
        if (password.length < 6) {
            res.status(400).json({ error: 'Password must be at least 6 characters long' });
            return;
        }
        const passwordHash = bcrypt_1.default.hashSync(password, 12);
        const userId = User_1.default.create(database_1.default, { username, email, password_hash: passwordHash, full_name, role_id, is_active });
        (0, activityLogger_1.log)({ userId: req.user.id, action: 'USER_CREATE', entityType: 'User', description: `User ${username} created by ${req.user.username}`, metadata: { username, email, role_id }, ipAddress: String(req.ip || '') });
        req.activityLogged = true;
        const newUser = User_1.default.getPublicById(userId, database_1.default);
        res.status(201).json({ success: true, data: newUser });
    }
    catch (error) {
        logger_1.default.error('Create user error:', error);
        res.status(500).json({ error: 'Failed to create user' });
    }
}
function updateUser(req, res) {
    try {
        const userId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const { username, email, full_name, role_id, is_active } = req.body;
        const existingUser = User_1.default.getPublicById(userId, database_1.default);
        if (!existingUser) {
            res.status(404).json({ error: 'User not found' });
            return;
        }
        if (req.user.id === userId && role_id) {
            const newRoleName = Role_1.default.getById(database_1.default, role_id)?.role_name;
            if (newRoleName !== 'Admin') {
                res.status(400).json({ error: 'Cannot change your own role' });
                return;
            }
        }
        if (role_id && !User_1.default.roleExists(database_1.default, role_id)) {
            res.status(400).json({ error: 'Invalid role' });
            return;
        }
        if (username && username !== existingUser.username && User_1.default.usernameExists(database_1.default, username, userId)) {
            res.status(409).json({ error: 'Username already exists' });
            return;
        }
        if (email && email !== existingUser.email && User_1.default.emailExists(database_1.default, email, userId)) {
            res.status(409).json({ error: 'Email already exists' });
            return;
        }
        User_1.default.update(database_1.default, userId, { username, email, full_name, role_id, is_active });
        (0, activityLogger_1.log)({ userId: req.user.id, action: 'USER_UPDATE', entityType: 'User', description: `User ${existingUser.username} updated by ${req.user.username}`, metadata: { userId, updates: { username, email, full_name, role_id, is_active } }, ipAddress: String(req.ip || '') });
        req.activityLogged = true;
        const updatedUser = User_1.default.getPublicById(userId, database_1.default);
        res.json({ success: true, data: updatedUser });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to update user';
        if (message === 'User not found') {
            res.status(404).json({ error: message });
        }
        else if (message === 'No fields to update') {
            res.status(400).json({ error: message });
        }
        else {
            logger_1.default.error('Update user error:', error);
            res.status(500).json({ error: 'Failed to update user' });
        }
    }
}
function deleteUser(req, res) {
    try {
        const userId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const existingUser = User_1.default.getPublicById(userId, database_1.default);
        if (!existingUser) {
            res.status(404).json({ error: 'User not found' });
            return;
        }
        if (req.user.id === userId) {
            res.status(400).json({ error: 'Cannot delete your own account' });
            return;
        }
        if (existingUser.role === 'admin' && User_1.default.getAdminCount(database_1.default) <= 1) {
            res.status(400).json({ error: 'Cannot delete the last active admin user' });
            return;
        }
        User_1.default.softDelete(database_1.default, userId);
        (0, activityLogger_1.log)({ userId: req.user.id, action: 'USER_DELETE', entityType: 'User', description: `User ${existingUser.username} deleted by ${req.user.username}`, metadata: { userId, username: existingUser.username }, ipAddress: String(req.ip || '') });
        req.activityLogged = true;
        res.json({ success: true, message: 'User deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete user error:', error);
        res.status(500).json({ error: 'Failed to delete user' });
    }
}
function resetPassword(req, res) {
    try {
        const userId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const { newPassword } = req.body;
        if (!newPassword) {
            res.status(400).json({ error: 'New password is required' });
            return;
        }
        if (newPassword.length < 6) {
            res.status(400).json({ error: 'Password must be at least 6 characters long' });
            return;
        }
        const existingUser = User_1.default.getPublicById(userId, database_1.default);
        if (!existingUser) {
            res.status(404).json({ error: 'User not found' });
            return;
        }
        const passwordHash = bcrypt_1.default.hashSync(newPassword, 12);
        User_1.default.updatePassword(userId, passwordHash, database_1.default);
        (0, activityLogger_1.logAuth)(activityLogger_1.ActionType.PASSWORD_CHANGE, req.user.id, `Password reset for user ${existingUser.username} by ${req.user.username}`, { userId, username: existingUser.username }, String(req.ip || ''));
        req.activityLogged = true;
        res.json({ success: true, message: 'Password reset successfully' });
    }
    catch (error) {
        logger_1.default.error('Reset password error:', error);
        res.status(500).json({ error: 'Failed to reset password' });
    }
}
function toggleUserStatus(req, res) {
    try {
        const userId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const { is_active } = req.body;
        if (typeof is_active !== 'boolean') {
            res.status(400).json({ error: 'is_active must be a boolean' });
            return;
        }
        const existingUser = User_1.default.getPublicById(userId, database_1.default);
        if (!existingUser) {
            res.status(404).json({ error: 'User not found' });
            return;
        }
        if (req.user.id === userId) {
            res.status(400).json({ error: 'Cannot deactivate your own account' });
            return;
        }
        if (existingUser.role === 'admin' && !is_active && User_1.default.getAdminCount(database_1.default) <= 1) {
            res.status(400).json({ error: 'Cannot deactivate the last active admin user' });
            return;
        }
        User_1.default.update(database_1.default, userId, { is_active });
        (0, activityLogger_1.log)({ userId: req.user.id, action: 'USER_UPDATE', entityType: 'User', description: `User ${existingUser.username} ${is_active ? 'activated' : 'deactivated'} by ${req.user.username}`, metadata: { userId, username: existingUser.username, is_active }, ipAddress: String(req.ip || '') });
        req.activityLogged = true;
        res.json({ success: true, message: `User ${is_active ? 'activated' : 'deactivated'} successfully` });
    }
    catch (error) {
        logger_1.default.error('Toggle user status error:', error);
        res.status(500).json({ error: 'Failed to update user status' });
    }
}
exports.default = {
    getUsers,
    getUser,
    createUser,
    updateUser,
    deleteUser,
    resetPassword,
    toggleUserStatus,
};
//# sourceMappingURL=userController.js.map