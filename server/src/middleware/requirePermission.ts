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

/**
 * Programmatic permission check (same rules as requirePermission): admins pass,
 * everyone else needs the role permission. Used where the module being
 * authorised depends on request content (e.g. the custom-report entity).
 */
export function userHasPermission(
  user: { id: number; role?: string } | undefined,
  module: string,
  action: string
): boolean {
  if (!user) return false;
  if (user.role === 'admin') return true;
  const row = db.prepare('SELECT role_id FROM users WHERE id = ?').get(user.id) as { role_id: number | null } | undefined;
  if (!row || !row.role_id) return false;
  const granted = db.prepare(`
    SELECT 1
    FROM role_permissions rp
    JOIN permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = ? AND p.module = ? AND p.action = ?
  `).get(row.role_id, module, action);
  return !!granted;
}

/** 'module:action' keys granted to a role. */
export function rolePermissionKeys(roleId: number): Set<string> {
  const rows = db.prepare(`
    SELECT p.module AS module, p.action AS action
    FROM role_permissions rp JOIN permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = ?
  `).all(roleId) as Array<{ module: string; action: string }>;
  return new Set(rows.map(r => `${r.module}:${r.action}`));
}

/** 'module:action' keys for a list of permission ids. */
export function permissionKeysForIds(ids: number[]): Set<string> {
  const keys = new Set<string>();
  const stmt = db.prepare('SELECT module, action FROM permissions WHERE id = ?');
  for (const id of ids) {
    const row = stmt.get(Number(id)) as { module: string; action: string } | undefined;
    if (row) keys.add(`${row.module}:${row.action}`);
  }
  return keys;
}

/**
 * Permissions in `wanted` that the acting user does not hold themselves.
 * Administrators are unrestricted (empty result). Used to stop a delegated
 * user/role manager from minting access beyond their own (AUTHZ-003/004).
 */
export function permissionsBeyondActor(
  user: { id: number; role?: string } | undefined,
  wanted: Set<string>
): string[] {
  if (user?.role === 'admin') return [];
  const actorRow = user
    ? db.prepare('SELECT role_id FROM users WHERE id = ?').get(user.id) as { role_id: number | null } | undefined
    : undefined;
  const held = actorRow?.role_id ? rolePermissionKeys(actorRow.role_id) : new Set<string>();
  return [...wanted].filter(k => !held.has(k));
}

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
