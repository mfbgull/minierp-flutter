// Integrations module models — shaped after
// `server/src/models/Settings.ts` (PORTING.md §13):
//
//   GET /api/integrations/settings → BARE body (no envelope):
//     { email: {enabled, configured}, notifications: {…}, weather: {…},
//       validation: {…}, currency: {…}, tax: {…} }
//   PUT /api/integrations/settings/:service → body {enabled, apiKey?, …}
//     → {success: true, message}
//
// The GET only reports each service's `enabled`/`configured` flags — the
// actual keys are encrypted server-side and never returned, so the forms
// start with empty key fields (the reference UI behaves the same way).

import 'package:flutter/material.dart' show IconData, Icons;

/// One service's `{enabled, configured}` flags from the status GET.
class IntegrationServiceStatus {
  const IntegrationServiceStatus({
    required this.enabled,
    required this.configured,
  });

  factory IntegrationServiceStatus.fromJson(Map<String, dynamic> json) =>
      IntegrationServiceStatus(
        enabled: json['enabled'] == true,
        configured: json['configured'] == true,
      );

  final bool enabled;
  final bool configured;
}

/// One editable field on a service's settings form. `bodyKey` is the JSON
/// key the PUT expects (mirrors `serviceKeys[service]` on the server).
class IntegrationField {
  const IntegrationField(this.bodyKey, {this.secret = false});

  final String bodyKey;

  /// Secret fields (API keys / auth tokens) render obscured and get the
  /// "stored encrypted, never returned" helper note.
  final bool secret;
}

/// A configurable third-party service card. `id` is the PUT `:service`
/// path parameter (email / notifications / weather / validation /
/// currency / tax).
class IntegrationService {
  const IntegrationService({
    required this.id,
    required this.icon,
    required this.fields,
  });

  final String id;
  final IconData icon;

  /// Ordered PUT-body fields. The API key / auth token is first for every
  /// service (sendgrid_api_key, twilio_auth_token, …).
  final List<IntegrationField> fields;
}

/// The six services the server knows about, in display order.
const integrationServices = <IntegrationService>[
  IntegrationService(
    id: 'email',
    icon: Icons.mail_outline,
    fields: [
      IntegrationField('apiKey', secret: true),
      IntegrationField('from_email'),
      IntegrationField('from_name'),
    ],
  ),
  IntegrationService(
    id: 'notifications',
    icon: Icons.sms_outlined,
    fields: [
      IntegrationField('apiKey', secret: true),
      IntegrationField('account_sid', secret: true),
      IntegrationField('phone_number'),
    ],
  ),
  IntegrationService(
    id: 'weather',
    icon: Icons.cloud_outlined,
    fields: [
      IntegrationField('apiKey', secret: true),
      IntegrationField('default_location'),
    ],
  ),
  IntegrationService(
    id: 'validation',
    icon: Icons.verified_user_outlined,
    fields: [IntegrationField('apiKey', secret: true)],
  ),
  IntegrationService(
    id: 'currency',
    icon: Icons.currency_exchange_outlined,
    fields: [
      IntegrationField('apiKey', secret: true),
      IntegrationField('base'),
      IntegrationField('update_interval'),
    ],
  ),
  IntegrationService(
    id: 'tax',
    icon: Icons.receipt_long_outlined,
    fields: [
      IntegrationField('apiKey', secret: true),
      IntegrationField('default_country'),
      IntegrationField('zip_code'),
    ],
  ),
];
