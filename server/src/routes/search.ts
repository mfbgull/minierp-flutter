import express from 'express';
const router = express.Router();
import searchController from '../controllers/searchController';
import { authenticateToken } from '../middleware/auth';
import { validateZodQuery } from '../middleware/validation';
import { z } from 'zod';

const searchQuerySchema = z.object({
  q: z.string().min(2).max(100),
  limit: z.coerce.number().int().min(1).max(50).optional().default(10),
});

router.use(authenticateToken);
router.get('/', validateZodQuery(searchQuerySchema), searchController.getSearch);

export default router;
