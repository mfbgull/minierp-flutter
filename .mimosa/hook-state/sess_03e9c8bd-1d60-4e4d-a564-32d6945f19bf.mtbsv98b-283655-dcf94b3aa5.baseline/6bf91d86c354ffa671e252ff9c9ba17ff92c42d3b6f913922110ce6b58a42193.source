import express from 'express';
const router = express.Router();
import userController from '../controllers/userController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';

// All user routes require authentication
router.use(authenticateToken);

router.get('/', requirePermission('users', 'read'), userController.getUsers);
router.get('/:id', requirePermission('users', 'read'), userController.getUser);
router.post('/', requirePermission('users', 'create'), userController.createUser);
router.put('/:id', requirePermission('users', 'update'), userController.updateUser);
router.delete('/:id', requirePermission('users', 'delete'), userController.deleteUser);
router.put('/:id/reset-password', requirePermission('users', 'update'), userController.resetPassword);
router.put('/:id/toggle-status', requirePermission('users', 'update'), userController.toggleUserStatus);

export default router;
