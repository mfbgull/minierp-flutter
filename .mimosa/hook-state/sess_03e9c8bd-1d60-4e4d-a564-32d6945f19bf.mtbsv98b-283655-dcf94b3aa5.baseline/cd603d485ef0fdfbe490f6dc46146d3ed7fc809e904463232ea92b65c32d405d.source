import express from 'express';
const router = express.Router();
import preferencesController from '../controllers/preferencesController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';

router.use(authenticateToken);

router.get('/', requirePermission('settings', 'read'), preferencesController.getPreferences);
router.put('/', requirePermission('settings', 'update'), preferencesController.updatePreferences);

export default router;
