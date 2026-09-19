import { Response } from 'express';
import { AuthRequest } from '../types';
import db from '../config/database';
import logger from '../utils/logger';
import {
  getForUser,
  updateForUser,
  UserPreferences,
  WeekStart,
} from '../models/UserPreferences';

const WEEK_STARTS: ReadonlyArray<WeekStart> = ['monday', 'saturday', 'sunday'];
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function isIsoDate(value: unknown): value is string {
  return typeof value === 'string' && ISO_DATE.test(value);
}

function requireUser(req: AuthRequest, res: Response): number | null {
  if (!req.user) {
    res.status(401).json({ error: 'Authentication required' });
    return null;
  }
  return req.user.id;
}

/**
 * GET /api/preferences — the current user's date-range picker preferences
 * (week start, default range, custom presets). Server defaults when the
 * user has no row yet.
 */
function getPreferences(req: AuthRequest, res: Response): void {
  try {
    const userId = requireUser(req, res);
    if (userId === null) return;
    const data = getForUser(db, userId);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Get preferences error:', error);
    res.status(500).json({ error: 'Failed to fetch preferences' });
  }
}

/**
 * PUT /api/preferences — partial update of the current user's preferences.
 * Body: any subset of `{ weekStart, defaultRange, presets }`. Returns the
 * saved (merged) object. Invalid values → 400.
 */
function updatePreferences(req: AuthRequest, res: Response): void {
  try {
    const userId = requireUser(req, res);
    if (userId === null) return;

    const body = req.body as Record<string, unknown> | undefined;
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      res.status(400).json({ error: 'Invalid preferences data' });
      return;
    }

    const partial: Partial<UserPreferences> = {};

    if (body.weekStart !== undefined) {
      if (!WEEK_STARTS.includes(body.weekStart as WeekStart)) {
        res.status(400).json({ error: 'weekStart must be one of: monday, saturday, sunday' });
        return;
      }
      partial.weekStart = body.weekStart as WeekStart;
    }

    if (body.defaultRange !== undefined) {
      if (body.defaultRange === null) {
        partial.defaultRange = null;
      } else {
        const range = body.defaultRange as Record<string, unknown> | null;
        if (
          !range ||
          typeof range !== 'object' ||
          !isIsoDate(range.from) ||
          !isIsoDate(range.to)
        ) {
          res.status(400).json({
            error: 'defaultRange must be { from, to } with YYYY-MM-DD dates, or null',
          });
          return;
        }
        // ISO strings compare lexicographically — from > to would store a
        // reversed window that later produces an empty range.
        if (range.from > range.to) {
          res.status(400).json({ error: 'defaultRange.from must not be after defaultRange.to' });
          return;
        }
        partial.defaultRange = { from: range.from, to: range.to };
      }
    }

    if (body.presets !== undefined) {
      if (!Array.isArray(body.presets)) {
        res.status(400).json({ error: 'presets must be an array' });
        return;
      }
      const presetIds = new Set<string>();
      for (const preset of body.presets) {
        const p = preset as Record<string, unknown> | null;
        if (
          !p ||
          typeof p !== 'object' ||
          typeof p.id !== 'string' ||
          p.id === '' ||
          typeof p.name !== 'string' ||
          !isIsoDate(p.from) ||
          !isIsoDate(p.to)
        ) {
          res.status(400).json({
            error: 'Each preset must be { id, name, from, to } with YYYY-MM-DD dates',
          });
          return;
        }
        if (p.from > p.to) {
          res.status(400).json({ error: `Preset "${p.id}" has from after to` });
          return;
        }
        if (presetIds.has(p.id)) {
          res.status(400).json({ error: `Duplicate preset id: ${p.id}` });
          return;
        }
        presetIds.add(p.id);
      }
      partial.presets = body.presets as UserPreferences['presets'];
    }

    const data = updateForUser(db, userId, partial);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Update preferences error:', error);
    res.status(500).json({ error: 'Failed to update preferences' });
  }
}

export default { getPreferences, updatePreferences };
