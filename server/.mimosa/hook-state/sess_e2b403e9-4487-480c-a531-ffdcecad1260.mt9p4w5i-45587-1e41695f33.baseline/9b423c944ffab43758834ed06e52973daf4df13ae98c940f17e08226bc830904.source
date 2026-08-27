import { Router, Request, Response } from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import settingsController from '../controllers/settingsController';
import logger from '../utils/logger';

const router = Router();

router.use(authenticateToken);
router.use(requirePermission('integrations', 'read'));

router.get('/settings', requirePermission('integrations', 'read'), (_req: Request, res: Response): void => {
  try {
    const integrationSettings = settingsController.getIntegrationSettings();
    res.json(integrationSettings);
  } catch (error) {
    logger.error('Get integration settings error:', error);
    res.status(500).json({ error: 'Failed to fetch integration settings' });
  }
});

router.put('/settings/:service', requirePermission('integrations', 'update'), (req: Request, res: Response): void => {
  try {
    const { service } = req.params;
    const serviceKey = typeof service === 'string' ? service : service[0];
    settingsController.updateIntegrationSettings(serviceKey, req.body);
    res.json({ success: true, message: 'Settings updated successfully' });
  } catch (error) {
    logger.error('Update integration settings error:', error);
    if (error instanceof Error && error.message === 'Invalid service name') {
      res.status(400).json({ error: 'Invalid service name' });
    } else {
      res.status(500).json({ error: 'Failed to update integration settings' });
    }
  }
});

export default router;
