"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const Role_1 = __importDefault(require("../models/Role"));
function getRoles(req, res) {
    try {
        const roles = Role_1.default.getAll(database_1.default);
        res.json({ success: true, data: roles });
    }
    catch (error) {
        logger_1.default.error('Get roles error:', error);
        res.status(500).json({ error: 'Failed to fetch roles' });
    }
}
function getRolePermissions(req, res) {
    try {
        const { id } = req.params;
        const roleId = parseInt(String(id), 10);
        const permissions = Role_1.default.getPermissionsForRole(database_1.default, roleId);
        res.json({ success: true, data: permissions });
    }
    catch (error) {
        logger_1.default.error('Get role permissions error:', error);
        res.status(500).json({ error: 'Failed to fetch role permissions' });
    }
}
function createRole(req, res) {
    try {
        const { role_name, description, permissions } = req.body;
        if (!role_name) {
            res.status(400).json({ error: 'Role name is required' });
            return;
        }
        const existing = Role_1.default.getByName(database_1.default, role_name);
        if (existing) {
            res.status(409).json({ error: 'Role name already exists' });
            return;
        }
        const userId = req.user?.id ?? 0;
        const newRole = Role_1.default.create(database_1.default, { role_name, description, permissions }, userId);
        res.status(201).json({ success: true, data: newRole });
    }
    catch (error) {
        logger_1.default.error('Create role error:', error);
        res.status(500).json({ error: 'Failed to create role' });
    }
}
function updateRole(req, res) {
    try {
        const { id } = req.params;
        const roleId = parseInt(String(id), 10);
        const { role_name, description, is_active } = req.body;
        const updatedRole = Role_1.default.update(database_1.default, roleId, { role_name, description, is_active });
        res.json({ success: true, data: updatedRole });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to update role';
        if (message === 'Role not found') {
            res.status(404).json({ error: message });
        }
        else if (message.includes('system role') || message.includes('already exists')) {
            res.status(400).json({ error: message });
        }
        else {
            logger_1.default.error('Update role error:', error);
            res.status(500).json({ error: 'Failed to update role' });
        }
    }
}
function updateRolePermissions(req, res) {
    try {
        const { id } = req.params;
        const roleId = parseInt(String(id), 10);
        const { permissions } = req.body;
        Role_1.default.updatePermissions(database_1.default, roleId, permissions);
        res.json({ success: true, message: 'Permissions updated successfully' });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to update role permissions';
        if (message === 'Role not found') {
            res.status(404).json({ error: message });
        }
        else {
            logger_1.default.error('Update role permissions error:', error);
            res.status(500).json({ error: 'Failed to update role permissions' });
        }
    }
}
function deleteRole(req, res) {
    try {
        const { id } = req.params;
        const roleId = parseInt(String(id), 10);
        Role_1.default.delete(database_1.default, roleId);
        res.json({ success: true, message: 'Role deleted successfully' });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to delete role';
        if (message === 'Role not found') {
            res.status(404).json({ error: message });
        }
        else if (message.includes('system role') || message.includes('user(s)')) {
            res.status(400).json({ error: message });
        }
        else {
            logger_1.default.error('Delete role error:', error);
            res.status(500).json({ error: 'Failed to delete role' });
        }
    }
}
function getPermissions(req, res) {
    try {
        const permissions = Role_1.default.getAllPermissions(database_1.default);
        const grouped = {};
        for (const perm of permissions) {
            if (!grouped[perm.module])
                grouped[perm.module] = [];
            grouped[perm.module].push(perm);
        }
        res.json({ success: true, data: grouped });
    }
    catch (error) {
        logger_1.default.error('Get permissions error:', error);
        res.status(500).json({ error: 'Failed to fetch permissions' });
    }
}
exports.default = {
    getRoles,
    getRolePermissions,
    createRole,
    updateRole,
    updateRolePermissions,
    deleteRole,
    getPermissions,
};
