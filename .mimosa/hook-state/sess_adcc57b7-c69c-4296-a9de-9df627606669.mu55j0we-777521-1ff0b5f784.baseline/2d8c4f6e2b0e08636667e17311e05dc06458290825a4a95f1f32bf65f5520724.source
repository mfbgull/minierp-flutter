import express from 'express';
const router = express.Router();
import {
  getAllBOMs,
  getBOMById,
  getBOMsByFinishedItem,
  createBOM,
  updateBOM,
  toggleBOMActive,
  deleteBOM
} from '../controllers/bomController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';

// All BOM routes require authentication
router.use(authenticateToken);

router.get('/', requirePermission('bom', 'read'), getAllBOMs);
router.get('/:id', requirePermission('bom', 'read'), getBOMById);
router.get('/by-item/:itemId', requirePermission('bom', 'read'), getBOMsByFinishedItem);
router.post('/', requirePermission('bom', 'create'), validateZodBody(zodBodySchemas.bomCreate), createBOM);
router.put('/:id', requirePermission('bom', 'update'), validateZodBody(zodBodySchemas.object), updateBOM);
router.patch('/:id/toggle-active', requirePermission('bom', 'update'), validateZodBody(zodBodySchemas.object), toggleBOMActive);
router.delete('/:id', requirePermission('bom', 'delete'), deleteBOM);

export default router;
