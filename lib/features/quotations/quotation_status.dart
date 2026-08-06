// Shared quotation status helpers — used by the list grid and (later)
// the detail dialog (PORTING.md §6: status text plus colors come from
// the web's `references/utils/statusColors.ts` conventions).

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Quotation status badge colors — Draft gray, Sent blue, Accepted green,
/// Expired orange, Converted teal, Rejected grey: the light color plus
/// the darker variant used as text on dark themes.
(Color, Color?) quotationStatusColors(String status) => switch (status) {
  'Sent' => (Colors.lightBlue, Colors.lightBlueAccent),
  'Accepted' => (Colors.green, Colors.lightGreen),
  'Expired' => (Colors.orange, Colors.orangeAccent),
  'Converted' => (Colors.teal, Colors.tealAccent),
  'Rejected' => (Colors.grey, Colors.blueGrey),
  _ => (Colors.blueGrey, Colors.blueGrey),
};

/// Localized quotation status label (falls back to the raw server value).
String quotationStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'Draft' => l10n.quotationsDraft,
      'Sent' => l10n.quotationsSent,
      'Accepted' => l10n.quotationsAccepted,
      'Expired' => l10n.quotationsExpired,
      'Converted' => l10n.quotationsConverted,
      'Rejected' => l10n.quotationsRejected,
      _ => status,
    };
