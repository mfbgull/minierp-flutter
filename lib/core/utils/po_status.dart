// Shared PO status helpers — used by the list grid, the detail dialog,
// and the CSV export builder (PORTING.md §6: status text plus colors
// come from the web's `references/utils/statusColors.ts`). Lives in
// core/utils (mirroring `movement_type_label.dart` / `so_status.dart`)
// so the core CSV export can reuse it without importing from features.

import 'package:flutter/material.dart';
import '../../core/theme/status_colors.dart';

import '../../l10n/app_localizations.dart';

/// PO status badge colors — Draft gray, Submitted blue, Partially Received
/// yellow, Completed green, Cancelled gray: the light color plus the
/// darker variant used as text on dark themes.
Color poStatusColors(ColorScheme scheme, String status) =>
    StatusColors(scheme).po(status);

/// Localized PO status label (falls back to the raw server value).
String poStatusLabel(AppLocalizations l10n, String status) => switch (status) {
  'Draft' => l10n.statusDraft,
  'Submitted' => l10n.statusSubmitted,
  'Partially Received' => l10n.statusPartiallyreceived,
  'Completed' => l10n.statusCompleted,
  'Cancelled' => l10n.statusCancelled,
  _ => status,
};
