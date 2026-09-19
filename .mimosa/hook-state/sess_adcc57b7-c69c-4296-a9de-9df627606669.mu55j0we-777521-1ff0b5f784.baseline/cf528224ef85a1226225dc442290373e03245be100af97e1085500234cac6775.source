import { Request, Response } from 'express';
import db from '../config/database';
import { encrypt } from '../utils/encryption';
import logger from '../utils/logger';
import SettingsModel from '../models/Settings';

function getSettings(req: Request, res: Response): void {
  try {
    const settings = SettingsModel.getAll(db);
    const settingsObj: Record<string, any> = settings.reduce((acc, setting) => {
      acc[setting.key] = { value: setting.value, description: setting.description, updated_at: setting.updated_at };
      return acc;
    }, {} as Record<string, unknown>);
    res.json(settingsObj);
  } catch (error) {
    logger.error('Get settings error:', error);
    res.status(500).json({ error: 'Failed to fetch settings' });
  }
}

function getSetting(req: Request, res: Response): void {
  try {
    const key = Array.isArray(req.params.key) ? req.params.key[0] : req.params.key;
    const setting = SettingsModel.getByKey(db, key);
    if (!setting) { res.status(404).json({ error: 'Setting not found' }); return; }
    res.json(setting);
  } catch (error) {
    logger.error('Get setting error:', error);
    res.status(500).json({ error: 'Failed to fetch setting' });
  }
}

function updateSetting(req: Request, res: Response): void {
  try {
    const key = Array.isArray(req.params.key) ? req.params.key[0] : req.params.key;
    const { value, description } = req.body;
    if (!value) { res.status(400).json({ error: 'Value is required' }); return; }

    const updated = SettingsModel.upsert(db, key, value, description || null);
    res.json(updated);
  } catch (error) {
    logger.error('Update setting error:', error);
    res.status(500).json({ error: 'Failed to update setting' });
  }
}

function updateSettings(req: Request, res: Response): void {
  try {
    const settings = req.body as Record<string, any>;
    if (!settings || typeof settings !== 'object') { res.status(400).json({ error: 'Invalid settings data' }); return; }

    SettingsModel.updateBulk(db, settings);

    const allSettings = SettingsModel.getAll(db);
    const settingsObj: Record<string, any> = allSettings.reduce((acc, setting) => {
      acc[setting.key] = { value: setting.value, description: setting.description, updated_at: setting.updated_at };
      return acc;
    }, {} as Record<string, unknown>);
    res.json(settingsObj);
  } catch (error) {
    logger.error('Update settings error:', error);
    res.status(500).json({ error: 'Failed to update settings' });
  }
}

function getIntegrationSettings() {
  const settings = SettingsModel.getIntegrationKeys(db);
  return SettingsModel.buildIntegrationStatus(settings);
}

function updateIntegrationSettings(service: string, body: Record<string, unknown>): void {
  const params = body as Parameters<typeof SettingsModel.updateIntegrationSetting>[2];
  SettingsModel.updateIntegrationSetting(db, service, params, encrypt);
}

function initializeDefaults(): void {
  SettingsModel.initializeDefaults(db);
}

export default { getSettings, getSetting, updateSetting, updateSettings, getIntegrationSettings, updateIntegrationSettings, initializeDefaults };
