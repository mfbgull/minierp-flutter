import express from 'express';
const router = express.Router();
import settingsController from '../controllers/settingsController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';

router.use(authenticateToken);

router.get('/', requirePermission('settings', 'read'), settingsController.getSettings);
router.get('/:key', requirePermission('settings', 'read'), settingsController.getSetting);
router.put('/:key', requirePermission('settings', 'update'), settingsController.updateSetting);
router.post('/bulk', requirePermission('settings', 'update'), settingsController.updateSettings);

export default router;
