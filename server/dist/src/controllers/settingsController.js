"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const encryption_1 = require("../utils/encryption");
const logger_1 = __importDefault(require("../utils/logger"));
const Settings_1 = __importDefault(require("../models/Settings"));
function getSettings(req, res) {
    try {
        const settings = Settings_1.default.getAll(database_1.default);
        const settingsObj = settings.reduce((acc, setting) => {
            acc[setting.key] = { value: setting.value, description: setting.description, updated_at: setting.updated_at };
            return acc;
        }, {});
        res.json(settingsObj);
    }
    catch (error) {
        logger_1.default.error('Get settings error:', error);
        res.status(500).json({ error: 'Failed to fetch settings' });
    }
}
function getSetting(req, res) {
    try {
        const key = Array.isArray(req.params.key) ? req.params.key[0] : req.params.key;
        const setting = Settings_1.default.getByKey(database_1.default, key);
        if (!setting) {
            res.status(404).json({ error: 'Setting not found' });
            return;
        }
        res.json(setting);
    }
    catch (error) {
        logger_1.default.error('Get setting error:', error);
        res.status(500).json({ error: 'Failed to fetch setting' });
    }
}
function updateSetting(req, res) {
    try {
        const key = Array.isArray(req.params.key) ? req.params.key[0] : req.params.key;
        const { value, description } = req.body;
        if (!value) {
            res.status(400).json({ error: 'Value is required' });
            return;
        }
        const updated = Settings_1.default.upsert(database_1.default, key, value, description || null);
        res.json(updated);
    }
    catch (error) {
        logger_1.default.error('Update setting error:', error);
        res.status(500).json({ error: 'Failed to update setting' });
    }
}
function updateSettings(req, res) {
    try {
        const settings = req.body;
        if (!settings || typeof settings !== 'object') {
            res.status(400).json({ error: 'Invalid settings data' });
            return;
        }
        Settings_1.default.updateBulk(database_1.default, settings);
        const allSettings = Settings_1.default.getAll(database_1.default);
        const settingsObj = allSettings.reduce((acc, setting) => {
            acc[setting.key] = { value: setting.value, description: setting.description, updated_at: setting.updated_at };
            return acc;
        }, {});
        res.json(settingsObj);
    }
    catch (error) {
        logger_1.default.error('Update settings error:', error);
        res.status(500).json({ error: 'Failed to update settings' });
    }
}
function getIntegrationSettings() {
    const settings = Settings_1.default.getIntegrationKeys(database_1.default);
    return Settings_1.default.buildIntegrationStatus(settings);
}
function updateIntegrationSettings(service, body) {
    const params = body;
    Settings_1.default.updateIntegrationSetting(database_1.default, service, params, encryption_1.encrypt);
}
function initializeDefaults() {
    Settings_1.default.initializeDefaults(database_1.default);
}
exports.default = { getSettings, getSetting, updateSetting, updateSettings, getIntegrationSettings, updateIntegrationSettings, initializeDefaults };
