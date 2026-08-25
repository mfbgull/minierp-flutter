"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const keyMap = {
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
const serviceKeys = {
    email: { enabled: 'sendgrid_enabled', api_key: 'sendgrid_api_key', others: { from_email: 'sendgrid_from_email', from_name: 'sendgrid_from_name' } },
    notifications: { enabled: 'twilio_enabled', api_key: 'twilio_auth_token', others: { account_sid: 'twilio_account_sid', phone_number: 'twilio_phone_number' } },
    weather: { enabled: 'weather_enabled', api_key: 'weather_api_key', others: { default_location: 'weather_default_location' } },
    validation: { enabled: 'validation_enabled', api_key: 'validation_api_key', others: {} },
    currency: { enabled: 'currency_enabled', api_key: 'currency_api_key', others: { base: 'currency_base', update_interval: 'currency_rates_update_interval' } },
    tax: { enabled: 'tax_enabled', api_key: 'tax_api_key', others: { default_country: 'tax_default_country', zip_code: 'tax_zip_code' } },
};
function getAll(db) {
    return db.prepare('SELECT * FROM settings').all();
}
function getByKey(db, key) {
    return db.prepare('SELECT * FROM settings WHERE key = ?').get(key);
}
function upsert(db, key, value, description) {
    const existing = getByKey(db, key);
    if (existing) {
        db.prepare('UPDATE settings SET value = ?, description = ?, updated_at = CURRENT_TIMESTAMP WHERE key = ?').run(value, description || existing.description, key);
    }
    else {
        db.prepare('INSERT INTO settings (key, value, description) VALUES (?, ?, ?)').run(key, value, description || null);
    }
    return getByKey(db, key);
}
function updateBulk(db, settings) {
    const transaction = db.transaction(() => {
        for (const [key, data] of Object.entries(settings)) {
            const value = typeof data === 'object' ? data.value : data;
            const description = typeof data === 'object' ? data.description : null;
            upsert(db, key, value, description);
        }
    });
    transaction();
}
function initializeDefaults(db) {
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
function getIntegrationKeys(db) {
    return db.prepare(`SELECT key, value FROM settings WHERE key LIKE '%_enabled' OR key LIKE '%_api_key'`).all();
}
function buildIntegrationStatus(settings) {
    const integrationSettings = {
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
            }
            else {
                integrationSettings[mapping.service].configured = !!setting.value;
            }
        }
    }
    return integrationSettings;
}
function updateIntegrationSetting(db, service, params, encryptFn) {
    const keys = serviceKeys[service];
    if (!keys)
        throw new Error('Invalid service name');
    const { enabled, apiKey, ...otherSettings } = params;
    const updateEnabled = db.prepare('UPDATE settings SET value = ? WHERE key = ?');
    const updateValue = db.prepare('UPDATE settings SET value = ? WHERE key = ?');
    updateEnabled.run(enabled ? 'true' : 'false', keys.enabled);
    updateValue.run(apiKey ? encryptFn(apiKey) : '', keys.api_key);
    Object.entries(keys.others).forEach(([dbKey, settingKey]) => {
        const value = otherSettings[dbKey];
        if (value !== undefined) {
            updateValue.run(value, settingKey);
        }
    });
}
exports.default = {
    getAll,
    getByKey,
    upsert,
    updateBulk,
    initializeDefaults,
    getIntegrationKeys,
    buildIntegrationStatus,
    updateIntegrationSetting,
};
