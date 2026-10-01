import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import posController from '../controllers/posController';

router.use(authenticateToken);

router.post('/sale', requirePermission('pos', 'create'), validateZodBody(zodBodySchemas.posSale), posController.createPOSSale);
router.get('/transactions', requirePermission('pos', 'read'), posController.getPOSTransactions);
// Own endpoint under pos:read — the mobile equivalent stays behind
// invoices:read, and a POS operator should not need invoice permission.
router.get('/tax-rates', requirePermission('pos', 'read'), posController.getPOSTaxRates);

export default router;
