import express from 'express';
const router = express.Router();
import rolesController from '../controllers/rolesController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';

// All role routes require authentication
router.use(authenticateToken);

router.get('/', requirePermission('roles', 'read'), rolesController.getRoles);
router.get('/permissions', requirePermission('roles', 'read'), rolesController.getPermissions);
router.get('/:id/permissions', requirePermission('roles', 'read'), rolesController.getRolePermissions);
router.post('/', requirePermission('roles', 'create'), rolesController.createRole);
router.put('/:id', requirePermission('roles', 'update'), rolesController.updateRole);
router.put('/:id/permissions', requirePermission('roles', 'update'), rolesController.updateRolePermissions);
router.delete('/:id', requirePermission('roles', 'delete'), rolesController.deleteRole);

export default router;
