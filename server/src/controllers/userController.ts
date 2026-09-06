import { Response } from 'express';
import db from '../config/database';
import { AuthRequest } from '../types';
import bcrypt from 'bcrypt';
import { log, logAuth, ActionType } from '../services/activityLogger';
import logger from '../utils/logger';
import UserModel from '../models/User';

function getUsers(req: AuthRequest, res: Response): void {
  try {
    const { role, is_active, search } = req.query as { role?: string; is_active?: string; search?: string };
    const users = UserModel.getAll({ role, is_active, search }, db);
    res.json({ success: true, data: users });
  } catch (error: unknown) {
    logger.error('Get users error:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
}

function getUser(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const user = UserModel.getPublicById(id, db);
    if (!user) { res.status(404).json({ error: 'User not found' }); return; }
    res.json({ success: true, data: user });
  } catch (error: unknown) {
    logger.error('Get user error:', error);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
}

async function createUser(req: AuthRequest, res: Response): Promise<void> {
  try {
    const { username, email, password, full_name, role_id, is_active = true } = req.body;

    if (!username || !email || !password || !full_name || !role_id) {
      res.status(400).json({ error: 'Username, email, password, full name, and role are required' });
      return;
    }

    if (!UserModel.roleExists(db, role_id)) {
      res.status(400).json({ error: 'Invalid role' });
      return;
    }

    if (UserModel.usernameExists(db, username)) {
      res.status(409).json({ error: 'Username already exists' });
      return;
    }

    if (UserModel.emailExists(db, email)) {
      res.status(409).json({ error: 'Email already exists' });
      return;
    }

    if (password.length < 6) {
      res.status(400).json({ error: 'Password must be at least 6 characters long' });
      return;
    }

    // Async bcrypt (spec 2.1) — hashSync blocked the event loop ~300ms.
    const passwordHash = await bcrypt.hash(password, 12);
    const userId = UserModel.create(db, { username, email, password_hash: passwordHash, full_name, role_id, is_active });

    log({ userId: req.user!.id, action: 'USER_CREATE', entityType: 'User', description: `User ${username} created by ${req.user!.username}`, metadata: { username, email, role_id }, ipAddress: String(req.ip || '') });
    req.activityLogged = true;

    const newUser = UserModel.getPublicById(userId, db);
    res.status(201).json({ success: true, data: newUser });
  } catch (error: unknown) {
    logger.error('Create user error:', error);
    res.status(500).json({ error: 'Failed to create user' });
  }
}

function updateUser(req: AuthRequest, res: Response): void {
  try {
    const userId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const { username, email, full_name, role_id, is_active } = req.body;

    const existingUser = UserModel.getPublicById(userId, db);
    if (!existingUser) { res.status(404).json({ error: 'User not found' }); return; }

    // SEC-04: own role is immutable through self-edit, full stop.
    // Reject any self-edit containing role_id regardless of target role —
    // the previous name comparison let a user promote themselves to Admin.
    if (req.user!.id === userId && role_id !== undefined) {
      res.status(400).json({ error: 'Cannot change your own role' });
      return;
    }

    if (role_id && !UserModel.roleExists(db, role_id)) {
      res.status(400).json({ error: 'Invalid role' });
      return;
    }

    if (username && username !== existingUser.username && UserModel.usernameExists(db, username, userId)) {
      res.status(409).json({ error: 'Username already exists' });
      return;
    }

    if (email && email !== existingUser.email && UserModel.emailExists(db, email, userId)) {
      res.status(409).json({ error: 'Email already exists' });
      return;
    }

    UserModel.update(db, userId, { username, email, full_name, role_id, is_active });

    log({ userId: req.user!.id, action: 'USER_UPDATE', entityType: 'User', description: `User ${existingUser.username} updated by ${req.user!.username}`, metadata: { userId, updates: { username, email, full_name, role_id, is_active } }, ipAddress: String(req.ip || '') });
    req.activityLogged = true;

    const updatedUser = UserModel.getPublicById(userId, db);
    res.json({ success: true, data: updatedUser });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update user';
    if (message === 'User not found') {
      res.status(404).json({ error: message });
    } else if (message === 'No fields to update') {
      res.status(400).json({ error: message });
    } else {
      logger.error('Update user error:', error);
      res.status(500).json({ error: 'Failed to update user' });
    }
  }
}

function deleteUser(req: AuthRequest, res: Response): void {
  try {
    const userId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const existingUser = UserModel.getPublicById(userId, db);
    if (!existingUser) { res.status(404).json({ error: 'User not found' }); return; }
    if (req.user!.id === userId) { res.status(400).json({ error: 'Cannot delete your own account' }); return; }
    if (existingUser.role === 'admin' && UserModel.getAdminCount(db) <= 1) {
      res.status(400).json({ error: 'Cannot delete the last active admin user' });
      return;
    }

    UserModel.softDelete(db, userId);

    log({ userId: req.user!.id, action: 'USER_DELETE', entityType: 'User', description: `User ${existingUser.username} deleted by ${req.user!.username}`, metadata: { userId, username: existingUser.username }, ipAddress: String(req.ip || '') });
    req.activityLogged = true;

    res.json({ success: true, message: 'User deleted successfully' });
  } catch (error: unknown) {
    logger.error('Delete user error:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
}

async function resetPassword(req: AuthRequest, res: Response): Promise<void> {
  try {
    const userId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const { newPassword } = req.body;

    if (!newPassword) { res.status(400).json({ error: 'New password is required' }); return; }
    if (newPassword.length < 6) { res.status(400).json({ error: 'Password must be at least 6 characters long' }); return; }

    const existingUser = UserModel.getPublicById(userId, db);
    if (!existingUser) { res.status(404).json({ error: 'User not found' }); return; }

    // Async bcrypt (spec 2.1) — hashSync blocked the event loop ~300ms.
    const passwordHash = await bcrypt.hash(newPassword, 12);
    UserModel.updatePassword(userId, passwordHash, db);

        logAuth(ActionType.PASSWORD_CHANGE, req.user!.id, `Password reset for user ${existingUser.username} by ${req.user!.username}`, { userId, username: existingUser.username }, String(req.ip || ''));
    req.activityLogged = true;

    res.json({ success: true, message: 'Password reset successfully' });
  } catch (error: unknown) {
    logger.error('Reset password error:', error);
    res.status(500).json({ error: 'Failed to reset password' });
  }
}

function toggleUserStatus(req: AuthRequest, res: Response): void {
  try {
    const userId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const { is_active } = req.body;

    if (typeof is_active !== 'boolean') { res.status(400).json({ error: 'is_active must be a boolean' }); return; }

    const existingUser = UserModel.getPublicById(userId, db);
    if (!existingUser) { res.status(404).json({ error: 'User not found' }); return; }
    if (req.user!.id === userId) { res.status(400).json({ error: 'Cannot deactivate your own account' }); return; }
    if (existingUser.role === 'admin' && !is_active && UserModel.getAdminCount(db) <= 1) {
      res.status(400).json({ error: 'Cannot deactivate the last active admin user' });
      return;
    }

    UserModel.update(db, userId, { is_active });

    log({ userId: req.user!.id, action: 'USER_UPDATE', entityType: 'User', description: `User ${existingUser.username} ${is_active ? 'activated' : 'deactivated'} by ${req.user!.username}`, metadata: { userId, username: existingUser.username, is_active }, ipAddress: String(req.ip || '') });
    req.activityLogged = true;

    res.json({ success: true, message: `User ${is_active ? 'activated' : 'deactivated'} successfully` });
  } catch (error: unknown) {
    logger.error('Toggle user status error:', error);
    res.status(500).json({ error: 'Failed to update user status' });
  }
}

export default {
  getUsers,
  getUser,
  createUser,
  updateUser,
  deleteUser,
  resetPassword,
  toggleUserStatus,
};
