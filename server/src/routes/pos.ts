import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import posController from '../controllers/posController';

router.use(authenticateToken);

router.post('/sale', requirePermission('pos', 'create'), posController.createPOSSale);
router.get('/transactions', requirePermission('pos', 'read'), posController.getPOSTransactions);

export default router;
