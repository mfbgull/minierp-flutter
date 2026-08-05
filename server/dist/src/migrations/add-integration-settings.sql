-- Add Integration Settings

-- Email Integration Settings (SendGrid)
INSERT OR IGNORE INTO settings (key, value, description) VALUES
('sendgrid_enabled', 'false', 'Enable SendGrid email service'),
('sendgrid_api_key', '', 'SendGrid API key for sending emails'),
('sendgrid_from_email', '', 'Default from email address for SendGrid'),
('sendgrid_from_name', '', 'Default from name for SendGrid emails');

-- Notification Integration Settings (Twilio)
INSERT OR IGNORE INTO settings (key, value, description) VALUES
('twilio_enabled', 'false', 'Enable Twilio SMS notifications'),
('twilio_account_sid', '', 'Twilio Account SID'),
('twilio_auth_token', '', 'Twilio Auth Token'),
('twilio_phone_number', '', 'Twilio phone number for sending SMS');

-- Weather Integration Settings (Weatherstack)
INSERT OR IGNORE INTO settings (key, value, description) VALUES
('weather_enabled', 'false', 'Enable Weatherstack API for weather data'),
('weather_api_key', '', 'Weatherstack API key'),
('weather_default_location', '', 'Default location for weather checks');

-- Data Validation Settings (Numverify)
INSERT OR IGNORE INTO settings (key, value, description) VALUES
('validation_enabled', 'false', 'Enable Numverify API for phone validation'),
('validation_api_key', '', 'Numverify API key');

-- Currency Exchange Settings (Fixer)
INSERT OR IGNORE INTO settings (key, value, description) VALUES
('currency_enabled', 'false', 'Enable Fixer API for currency exchange'),
('currency_api_key', '', 'Fixer API key for exchange rates'),
('currency_base', 'USD', 'Base currency for exchange rates'),
('currency_rates_update_interval', '3600', 'Update interval for exchange rates (seconds)');

-- Tax Integration Settings (TaxJar)
INSERT OR IGNORE INTO settings (key, value, description) VALUES
('tax_enabled', 'false', 'Enable TaxJar API for tax calculation'),
('tax_api_key', '', 'TaxJar API key'),
('tax_default_country', 'US', 'Default country for tax calculation'),
('tax_zip_code', '', 'Default ZIP code for tax calculation');
