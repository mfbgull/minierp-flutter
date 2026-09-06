import express from 'express';
const router = express.Router();
import authController from '../controllers/authController';
import { authenticateToken } from '../middleware/auth';
import { authLimiter, passwordChangeLimiter } from '../middleware/rateLimiter';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';

router.post('/login', authLimiter, validateZodBody(zodBodySchemas.login), authController.login);
router.post('/refresh', authLimiter, validateZodBody(zodBodySchemas.refresh), authController.refresh);
router.post('/logout', authenticateToken, authController.logout);
router.get('/me', authenticateToken, authController.getCurrentUser);
router.post('/change-password', authenticateToken, passwordChangeLimiter, validateZodBody(zodBodySchemas.changePassword), authController.changePassword);

export default router;
