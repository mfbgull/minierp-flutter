import { Response } from 'express';
import { AuthRequest } from '../types';
import db from '../config/database';
import logger from '../utils/logger';
import {
  getForUser,
  updateForUser,
  UserPreferences,
} from '../models/UserPreferences';
import type { WeekStart } from '../utils/weekMath';

const WEEK_STARTS: ReadonlyArray<WeekStart> = ['monday', 'saturday', 'sunday'];
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function isIsoDate(value: unknown): value is string {
  return typeof value === 'string' && ISO_DATE.test(value);
}

function validateDefaultRange(range: unknown): string | null {
  if (range === null) return null;
  if (typeof range !== 'object' || !range || !('from' in range) || !('to' in range)
      || !isIsoDate(range.from) || !isIsoDate(range.to)) {
    return 'defaultRange must be { from, to } with YYYY-MM-DD dates, or null';
  }
  return range.from > range.to ? 'defaultRange.from must not be after defaultRange.to' : null;
}

function validatePresets(presets: unknown): string | null {
  if (!Array.isArray(presets)) return 'presets must be an array';
  const presetIds = new Set<string>();
  for (const preset of presets) {
    const p = preset as Record<string, unknown> | null;
    if (!p || typeof p !== 'object' || typeof p.id !== 'string' || p.id === ''
        || typeof p.name !== 'string' || !isIsoDate(p.from) || !isIsoDate(p.to)) {
      return 'Each preset must be { id, name, from, to } with YYYY-MM-DD dates';
    }
    if (p.from > p.to) return `Preset "${p.id}" has from after to`;
    if (presetIds.has(p.id)) return `Duplicate preset id: ${p.id}`;
    presetIds.add(p.id);
  }
  return null;
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
      const error = validateDefaultRange(body.defaultRange);
      if (error) {
        res.status(400).json({ error });
        return;
      }
      const range = body.defaultRange as { from: string; to: string } | null;
      partial.defaultRange = range === null ? null : { from: range.from, to: range.to };
    }

    if (body.presets !== undefined) {
      const error = validatePresets(body.presets);
      if (error) {
        res.status(400).json({ error });
        return;
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
