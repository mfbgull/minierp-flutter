import express from 'express';
const router = express.Router();
import authController from '../controllers/authController';
import { authenticateToken } from '../middleware/auth';
import { authLimiter, passwordChangeLimiter } from '../middleware/rateLimiter';

router.post('/login', authLimiter, authController.login);
router.post('/logout', authenticateToken, authController.logout);
router.get('/me', authenticateToken, authController.getCurrentUser);
router.post('/change-password', authenticateToken, passwordChangeLimiter, authController.changePassword);

export default router;
