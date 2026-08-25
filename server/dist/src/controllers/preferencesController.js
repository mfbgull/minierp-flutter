"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const UserPreferences_1 = require("../models/UserPreferences");
const WEEK_STARTS = ['monday', 'saturday', 'sunday'];
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
function isIsoDate(value) {
    return typeof value === 'string' && ISO_DATE.test(value);
}
function requireUser(req, res) {
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
function getPreferences(req, res) {
    try {
        const userId = requireUser(req, res);
        if (userId === null)
            return;
        const data = (0, UserPreferences_1.getForUser)(database_1.default, userId);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('Get preferences error:', error);
        res.status(500).json({ error: 'Failed to fetch preferences' });
    }
}
/**
 * PUT /api/preferences — partial update of the current user's preferences.
 * Body: any subset of `{ weekStart, defaultRange, presets }`. Returns the
 * saved (merged) object. Invalid values → 400.
 */
function updatePreferences(req, res) {
    try {
        const userId = requireUser(req, res);
        if (userId === null)
            return;
        const body = req.body;
        if (!body || typeof body !== 'object' || Array.isArray(body)) {
            res.status(400).json({ error: 'Invalid preferences data' });
            return;
        }
        const partial = {};
        if (body.weekStart !== undefined) {
            if (!WEEK_STARTS.includes(body.weekStart)) {
                res.status(400).json({ error: 'weekStart must be one of: monday, saturday, sunday' });
                return;
            }
            partial.weekStart = body.weekStart;
        }
        if (body.defaultRange !== undefined) {
            if (body.defaultRange === null) {
                partial.defaultRange = null;
            }
            else {
                const range = body.defaultRange;
                if (!range ||
                    typeof range !== 'object' ||
                    !isIsoDate(range.from) ||
                    !isIsoDate(range.to)) {
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
            const presetIds = new Set();
            for (const preset of body.presets) {
                const p = preset;
                if (!p ||
                    typeof p !== 'object' ||
                    typeof p.id !== 'string' ||
                    p.id === '' ||
                    typeof p.name !== 'string' ||
                    !isIsoDate(p.from) ||
                    !isIsoDate(p.to)) {
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
            partial.presets = body.presets;
        }
        const data = (0, UserPreferences_1.updateForUser)(database_1.default, userId, partial);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('Update preferences error:', error);
        res.status(500).json({ error: 'Failed to update preferences' });
    }
}
exports.default = { getPreferences, updatePreferences };
