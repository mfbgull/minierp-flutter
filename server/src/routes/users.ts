import express from 'express';
const router = express.Router();
import userController from '../controllers/userController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';

// All user routes require authentication
router.use(authenticateToken);

router.get('/', requirePermission('users', 'read'), userController.getUsers);
router.get('/:id', requirePermission('users', 'read'), userController.getUser);
router.post('/', requirePermission('users', 'create'), validateZodBody(zodBodySchemas.userCreate), userController.createUser);
router.put('/:id', requirePermission('users', 'update'), validateZodBody(zodBodySchemas.object), userController.updateUser);
router.delete('/:id', requirePermission('users', 'delete'), userController.deleteUser);
router.put('/:id/reset-password', requirePermission('users', 'update'), validateZodBody(zodBodySchemas.object), userController.resetPassword);
router.put('/:id/toggle-status', requirePermission('users', 'update'), validateZodBody(zodBodySchemas.object), userController.toggleUserStatus);

export default router;
