import { Response } from 'express';
import db from '../config/database';
import { AuthRequest } from '../types';
import logger from '../utils/logger';
import RoleModel from '../models/Role';

function getRoles(req: AuthRequest, res: Response): void {
  try {
    const roles = RoleModel.getAll(db);
    res.json({ success: true, data: roles });
  } catch (error: unknown) {
    logger.error('Get roles error:', error);
    res.status(500).json({ error: 'Failed to fetch roles' });
  }
}

function getRolePermissions(req: AuthRequest, res: Response): void {
  try {
    const { id } = req.params;
    const roleId = parseInt(String(id), 10);
    const permissions = RoleModel.getPermissionsForRole(db, roleId);
    res.json({ success: true, data: permissions });
  } catch (error: unknown) {
    logger.error('Get role permissions error:', error);
    res.status(500).json({ error: 'Failed to fetch role permissions' });
  }
}

function createRole(req: AuthRequest, res: Response): void {
  try {
    const { role_name, description, permissions } = req.body as {
      role_name: string;
      description?: string;
      permissions?: number[];
    };

    if (!role_name) {
      res.status(400).json({ error: 'Role name is required' });
      return;
    }

    const existing = RoleModel.getByName(db, role_name);
    if (existing) {
      res.status(409).json({ error: 'Role name already exists' });
      return;
    }

    const userId = req.user?.id ?? 0;
    const newRole = RoleModel.create(db, { role_name, description, permissions }, userId);

    res.status(201).json({ success: true, data: newRole });
  } catch (error: unknown) {
    logger.error('Create role error:', error);
    res.status(500).json({ error: 'Failed to create role' });
  }
}

function updateRole(req: AuthRequest, res: Response): void {
  try {
    const { id } = req.params;
    const roleId = parseInt(String(id), 10);
    const { role_name, description, is_active } = req.body as {
      role_name?: string;
      description?: string;
      is_active?: boolean;
    };

    const updatedRole = RoleModel.update(db, roleId, { role_name, description, is_active });
    res.json({ success: true, data: updatedRole });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update role';
    if (message === 'Role not found') {
      res.status(404).json({ error: message });
    } else if (message.includes('system role') || message.includes('already exists')) {
      res.status(400).json({ error: message });
    } else {
      logger.error('Update role error:', error);
      res.status(500).json({ error: 'Failed to update role' });
    }
  }
}

function updateRolePermissions(req: AuthRequest, res: Response): void {
  try {
    const { id } = req.params;
    const roleId = parseInt(String(id), 10);
    const { permissions }: { permissions: number[] } = req.body;

    RoleModel.updatePermissions(db, roleId, permissions);
    res.json({ success: true, message: 'Permissions updated successfully' });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update role permissions';
    if (message === 'Role not found') {
      res.status(404).json({ error: message });
    } else {
      logger.error('Update role permissions error:', error);
      res.status(500).json({ error: 'Failed to update role permissions' });
    }
  }
}

function deleteRole(req: AuthRequest, res: Response): void {
  try {
    const { id } = req.params;
    const roleId = parseInt(String(id), 10);

    RoleModel.delete(db, roleId);
    res.json({ success: true, message: 'Role deleted successfully' });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete role';
    if (message === 'Role not found') {
      res.status(404).json({ error: message });
    } else if (message.includes('system role') || message.includes('user(s)')) {
      res.status(400).json({ error: message });
    } else {
      logger.error('Delete role error:', error);
      res.status(500).json({ error: 'Failed to delete role' });
    }
  }
}

function getPermissions(req: AuthRequest, res: Response): void {
  try {
    const permissions = RoleModel.getAllPermissions(db);
    const grouped: Record<string, typeof permissions> = {};
    for (const perm of permissions) {
      if (!grouped[perm.module]) grouped[perm.module] = [];
      grouped[perm.module].push(perm);
    }
    res.json({ success: true, data: grouped });
  } catch (error: unknown) {
    logger.error('Get permissions error:', error);
    res.status(500).json({ error: 'Failed to fetch permissions' });
  }
}

export default {
  getRoles,
  getRolePermissions,
  createRole,
  updateRole,
  updateRolePermissions,
  deleteRole,
  getPermissions,
};
