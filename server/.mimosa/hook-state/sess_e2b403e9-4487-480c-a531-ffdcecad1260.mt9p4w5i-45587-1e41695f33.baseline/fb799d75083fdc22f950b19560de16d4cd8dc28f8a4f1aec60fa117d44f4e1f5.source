/**
 * Permission-based Access Control Middleware
 * -------------------------------------------
 * Drop-in replacement/companion for the existing requireAdmin middleware.
 *
 * Usage:
 *   router.get('/items', requirePermission('inventory', 'read'), handler);
 *   router.post('/items', requirePermission('inventory', 'create'), handler);
 *
 * NOTE: The Admin role (role_name = 'Admin') bypasses all permission checks,
 * so there is no need to attach full CRUD permissions to the Admin role in
 * the seed data — the bypass handles that automatically.
 */

import { Response, NextFunction } from 'express';
import { AuthRequest } from '../types';
import db from '../config/database';
import logger from '../utils/logger';

export function requirePermission(module: string, action: string) {
  return (req: AuthRequest, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    // Admin role bypasses all permission checks
    if (req.user.role === 'admin') {
      next();
      return;
    }

    try {
      // Look up user's role_id from the database
      const user = db.prepare(
        'SELECT role_id FROM users WHERE id = ?'
      ).get(req.user.id) as { role_id: number } | undefined;

      if (!user || !user.role_id) {
        res.status(403).json({ error: 'No role assigned to user' });
        return;
      }

      // Check if the role has the required permission
      const permission = db.prepare(`
        SELECT 1
        FROM role_permissions rp
        JOIN permissions p ON p.id = rp.permission_id
        WHERE rp.role_id = ?
          AND p.module = ?
          AND p.action = ?
      `).get(user.role_id, module, action);

      if (!permission) {
        logger.warn(
          `[Perm] Access denied for user ${req.user.username} ` +
          `(id=${req.user.id}, role_id=${user.role_id}) to ${module}:${action}`
        );
        res.status(403).json({
          error: `Access denied: you do not have "${action}" permission for "${module}"`,
        });
        return;
      }

      next();
    } catch (error) {
      logger.error('Permission check error:', error);
      res.status(500).json({ error: 'Permission check failed' });
    }
  };
}
