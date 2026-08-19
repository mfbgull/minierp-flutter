// Shared quotation status helpers — used by the list grid, the detail
// dialog, and the quotations CSV export (PORTING.md §6: status text
// plus colors come from the web's `references/utils/statusColors.ts`
// conventions).

import 'package:flutter/material.dart';
import '../../core/theme/status_colors.dart';

import '../../l10n/app_localizations.dart';

/// Quotation status badge colors — Draft gray, Sent blue, Accepted green,
/// Expired orange, Converted teal, Rejected grey: the light color plus
/// the darker variant used as text on dark themes.
Color quotationStatusColors(ColorScheme scheme, String status) =>
    StatusColors(scheme).quotation(status);

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
