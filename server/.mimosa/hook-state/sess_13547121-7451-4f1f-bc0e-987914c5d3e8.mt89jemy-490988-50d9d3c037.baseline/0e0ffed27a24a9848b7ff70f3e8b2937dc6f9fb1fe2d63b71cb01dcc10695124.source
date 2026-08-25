import Database from 'better-sqlite3';

interface Setting {
  key: string;
  value: string;
  description: string | null;
  updated_at: string;
}

interface IntegrationSetting {
  key: string;
  value: string;
}

interface IntegrationStatus {
  email: { enabled: boolean; configured: boolean };
  notifications: { enabled: boolean; configured: boolean };
  weather: { enabled: boolean; configured: boolean };
  validation: { enabled: boolean; configured: boolean };
  currency: { enabled: boolean; configured: boolean };
  tax: { enabled: boolean; configured: boolean };
}

interface UpdateIntegrationParams {
  enabled: boolean;
  apiKey?: string;
  [key: string]: unknown;
}

const keyMap: Record<string, { service: keyof IntegrationStatus; field: 'enabled' | 'configured' }> = {
  sendgrid_enabled: { service: 'email', field: 'enabled' },
  sendgrid_api_key: { service: 'email', field: 'configured' },
  twilio_enabled: { service: 'notifications', field: 'enabled' },
  twilio_auth_token: { service: 'notifications', field: 'configured' },
  weather_enabled: { service: 'weather', field: 'enabled' },
  weather_api_key: { service: 'weather', field: 'configured' },
  validation_enabled: { service: 'validation', field: 'enabled' },
  validation_api_key: { service: 'validation', field: 'configured' },
  currency_enabled: { service: 'currency', field: 'enabled' },
  currency_api_key: { service: 'currency', field: 'configured' },
  tax_enabled: { service: 'tax', field: 'enabled' },
  tax_api_key: { service: 'tax', field: 'configured' },
};

const serviceKeys: Record<string, { enabled: string; api_key: string; others: Record<string, string> }> = {
  email: { enabled: 'sendgrid_enabled', api_key: 'sendgrid_api_key', others: { from_email: 'sendgrid_from_email', from_name: 'sendgrid_from_name' } },
  notifications: { enabled: 'twilio_enabled', api_key: 'twilio_auth_token', others: { account_sid: 'twilio_account_sid', phone_number: 'twilio_phone_number' } },
  weather: { enabled: 'weather_enabled', api_key: 'weather_api_key', others: { default_location: 'weather_default_location' } },
  validation: { enabled: 'validation_enabled', api_key: 'validation_api_key', others: {} },
  currency: { enabled: 'currency_enabled', api_key: 'currency_api_key', others: { base: 'currency_base', update_interval: 'currency_rates_update_interval' } },
  tax: { enabled: 'tax_enabled', api_key: 'tax_api_key', others: { default_country: 'tax_default_country', zip_code: 'tax_zip_code' } },
};

function getAll(db: Database.Database): Setting[] {
  return db.prepare('SELECT * FROM settings').all() as Setting[];
}

function getByKey(db: Database.Database, key: string): Setting | undefined {
  return db.prepare('SELECT * FROM settings WHERE key = ?').get(key) as Setting | undefined;
}

function upsert(db: Database.Database, key: string, value: string, description: string | null): Setting {
  const existing = getByKey(db, key);
  if (existing) {
    db.prepare('UPDATE settings SET value = ?, description = ?, updated_at = CURRENT_TIMESTAMP WHERE key = ?').run(value, description || existing.description, key);
  } else {
    db.prepare('INSERT INTO settings (key, value, description) VALUES (?, ?, ?)').run(key, value, description || null);
  }
  return getByKey(db, key)!;
}

function updateBulk(db: Database.Database, settings: Record<string, { value: string; description?: string | null }>): void {
  const transaction = db.transaction(() => {
    for (const [key, data] of Object.entries(settings)) {
      const value = typeof data === 'object' ? data.value : data;
      const description = typeof data === 'object' ? data.description : null;
      upsert(db, key, value, description);
    }
  });
  transaction();
}

function initializeDefaults(db: Database.Database): void {
  const defaults = [
    { key: 'currency_symbol', value: 'Rs.', description: 'Currency symbol displayed throughout the application' },
    { key: 'currency_code', value: 'PKR', description: 'Currency code (e.g., USD, EUR, PKR)' },
    { key: 'company_name', value: 'Mini ERP', description: 'Company name' },
    { key: 'date_format', value: 'MM/DD/YYYY', description: 'Date format preference' },
    { key: 'decimal_places', value: '2', description: 'Number of decimal places for currency' },
    { key: 'tooltip_timeout', value: '1', description: 'Tooltip auto-hide timeout in seconds' }
  ];
  defaults.forEach(({ key, value, description }) => {
    if (!getByKey(db, key)) {
      db.prepare('INSERT INTO settings (key, value, description) VALUES (?, ?, ?)').run(key, value, description);
    }
  });
}

function getIntegrationKeys(db: Database.Database): IntegrationSetting[] {
  return db.prepare(
    `SELECT key, value FROM settings WHERE key LIKE '%_enabled' OR key LIKE '%_api_key'`
  ).all() as IntegrationSetting[];
}

function buildIntegrationStatus(settings: IntegrationSetting[]): IntegrationStatus {
  const integrationSettings: IntegrationStatus = {
    email: { enabled: false, configured: false },
    notifications: { enabled: false, configured: false },
    weather: { enabled: false, configured: false },
    validation: { enabled: false, configured: false },
    currency: { enabled: false, configured: false },
    tax: { enabled: false, configured: false },
  };

  for (const setting of settings) {
    const mapping = keyMap[setting.key];
    if (mapping) {
      if (mapping.field === 'enabled') {
        integrationSettings[mapping.service].enabled = setting.value === 'true';
      } else {
        integrationSettings[mapping.service].configured = !!setting.value;
      }
    }
  }
  return integrationSettings;
}

function updateIntegrationSetting(
  db: Database.Database,
  service: string,
  params: UpdateIntegrationParams,
  encryptFn: (value: string) => string
): void {
  const keys = serviceKeys[service];
  if (!keys) throw new Error('Invalid service name');

  const { enabled, apiKey, ...otherSettings } = params;

  const updateEnabled = db.prepare('UPDATE settings SET value = ? WHERE key = ?');
  const updateValue = db.prepare('UPDATE settings SET value = ? WHERE key = ?');

  updateEnabled.run(enabled ? 'true' : 'false', keys.enabled);
  updateValue.run(apiKey ? encryptFn(apiKey as string) : '', keys.api_key);

  Object.entries(keys.others).forEach(([dbKey, settingKey]) => {
    const value = otherSettings[dbKey];
    if (value !== undefined) {
      updateValue.run(value, settingKey);
    }
  });
}

export default {
  getAll,
  getByKey,
  upsert,
  updateBulk,
  initializeDefaults,
  getIntegrationKeys,
  buildIntegrationStatus,
  updateIntegrationSetting,
};
