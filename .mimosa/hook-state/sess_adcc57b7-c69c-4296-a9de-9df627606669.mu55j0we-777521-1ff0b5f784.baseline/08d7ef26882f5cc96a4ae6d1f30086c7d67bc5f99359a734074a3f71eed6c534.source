import { Request, Response } from 'express';
import { search } from '../services/searchService';
import { AuthRequest } from '../types';

function getSearch(req: AuthRequest, res: Response): void {
  try {
    const q = (req.query.q as string | undefined)?.trim() ?? '';
    const limit = Math.min(Number(req.query.limit ?? 10), 10); // spec: max 10 per entity

    if (!q || q.length < 2) {
      res.status(400).json({
        success: false,
        error: 'Query must be at least 2 characters',
      } as const);
      return;
    }

    const userId = req.user?.id ?? 0;
    const results = search(q, limit, userId);

    res.status(200).json({
      success: true,
      data: {
        query: q,
        results: results.results,
        total: results.total,
      },
    });
  } catch {
    res.status(500).json({
      success: false,
      error: 'Search failed',
    } as const);
  }
}

export default {
  getSearch,
};
