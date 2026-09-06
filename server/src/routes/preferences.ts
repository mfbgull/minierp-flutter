import express from 'express';
const router = express.Router();
import preferencesController from '../controllers/preferencesController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';

router.use(authenticateToken);

router.get('/', requirePermission('settings', 'read'), preferencesController.getPreferences);
router.put('/', requirePermission('settings', 'update'), validateZodBody(zodBodySchemas.preferencesUpdate), preferencesController.updatePreferences);

export default router;
