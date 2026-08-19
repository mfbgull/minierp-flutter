// Shared purchase-return status helpers — used by the list grid, the
// detail dialog, and the CSV export builder. The header's `status` is one
// of 'POSTED' (active, fully reversed against stock/GL) or 'VOIDED' (the
// full reversal has been reversed back); unknown values render as-is.
// Lives in core/utils (mirroring `po_status.dart`) so the core CSV export
// can reuse it without importing from features.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Return-status badge colors — Posted green, Voided red (the light color
/// plus the darker variant used as text on dark themes).
(Color, Color?) purchaseReturnStatusColors(String status) => switch (status) {
  'POSTED' => (Colors.green, Colors.lightGreen),
  'VOIDED' => (Colors.red, Colors.redAccent),
  _ => (Colors.blueGrey, Colors.blueGrey),
};

/// Localized return-status label (falls back to the raw server value).
String purchaseReturnStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'POSTED' => l10n.statusPosted,
      'VOIDED' => l10n.statusVoided,
      _ => status,
    };
