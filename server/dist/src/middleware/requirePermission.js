"use strict";
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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.requirePermission = requirePermission;
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
function requirePermission(module, action) {
    return (req, res, next) => {
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
            const user = database_1.default.prepare('SELECT role_id FROM users WHERE id = ?').get(req.user.id);
            if (!user || !user.role_id) {
                res.status(403).json({ error: 'No role assigned to user' });
                return;
            }
            // Check if the role has the required permission
            const permission = database_1.default.prepare(`
        SELECT 1
        FROM role_permissions rp
        JOIN permissions p ON p.id = rp.permission_id
        WHERE rp.role_id = ?
          AND p.module = ?
          AND p.action = ?
      `).get(user.role_id, module, action);
            if (!permission) {
                logger_1.default.warn(`[Perm] Access denied for user ${req.user.username} ` +
                    `(id=${req.user.id}, role_id=${user.role_id}) to ${module}:${action}`);
                res.status(403).json({
                    error: `Access denied: you do not have "${action}" permission for "${module}"`,
                });
                return;
            }
            next();
        }
        catch (error) {
            logger_1.default.error('Permission check error:', error);
            res.status(500).json({ error: 'Permission check failed' });
        }
    };
}
//# sourceMappingURL=requirePermission.js.map