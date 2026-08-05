// Shared PO status helpers — used by both the list grid and the detail
// dialog (PORTING.md §6: status text plus colors come from the web's
// `references/utils/statusColors.ts`).

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// PO status badge colors — Draft gray, Submitted blue, Partially Received
/// yellow, Completed green, Cancelled gray: the light color plus the
/// darker variant used as text on dark themes.
(Color, Color?) poStatusColors(String status) => switch (status) {
  'Submitted' => (Colors.blue, Colors.lightBlueAccent),
  'Partially Received' => (Colors.amber, Colors.orangeAccent),
  'Completed' => (Colors.green, Colors.lightGreen),
  'Cancelled' => (Colors.grey, Colors.blueGrey),
  _ => (Colors.blueGrey, Colors.blueGrey),
};

/// Localized PO status label (falls back to the raw server value).
String poStatusLabel(AppLocalizations l10n, String status) => switch (status) {
  'Draft' => l10n.statusDraft,
  'Submitted' => l10n.statusSubmitted,
  'Partially Received' => l10n.statusPartiallyreceived,
  'Completed' => l10n.statusCompleted,
  'Cancelled' => l10n.statusCancelled,
  _ => status,
};
