// Shared SO status helpers — used by the list grid, the detail dialog,
// and the CSV export builder (PORTING.md §6: status text plus colors
// come from the web's `references/utils/statusColors.ts` conventions).
// Lives in core/utils (mirroring `movement_type_label.dart`) so the core
// CSV export can reuse it without importing from features.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// SO status badge colors — Draft gray, Confirmed blue, Delivered green,
/// Invoiced teal, Completed green, Cancelled grey: the light color plus
/// the darker variant used as text on dark themes.
(Color, Color?) soStatusColors(String status) => switch (status) {
  'Confirmed' => (Colors.blue, Colors.lightBlueAccent),
  'Delivered' => (Colors.green, Colors.lightGreen),
  'Invoiced' => (Colors.teal, Colors.tealAccent),
  'Completed' => (Colors.green, Colors.lightGreen),
  'Cancelled' => (Colors.grey, Colors.blueGrey),
  _ => (Colors.blueGrey, Colors.blueGrey),
};

/// Localized SO status label (falls back to the raw server value).
String soStatusLabel(AppLocalizations l10n, String status) => switch (status) {
  'Draft' => l10n.salesordersDraft,
  'Confirmed' => l10n.salesordersConfirmed,
  'Delivered' => l10n.salesordersDelivered,
  'Invoiced' => l10n.salesordersInvoiced,
  'Completed' => l10n.salesordersCompleted,
  'Cancelled' => l10n.salesordersCancelled,
  _ => status,
};
