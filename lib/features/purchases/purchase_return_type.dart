// Shared purchase-return type helpers — used by both the list grid and
// the detail dialog. The server's `reference_doctype` is one of
// 'PURCHASE_RETURN' (return against a direct purchase) or 'PO_RETURN'
// (return against a purchase order); unknown values render as-is.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Return-type badge colors — Purchase Return red (stock leaves),
/// PO Return orange: the light color plus the darker variant used as text
/// on dark themes.
(Color, Color?) returnTypeColors(String type) => switch (type) {
  'PURCHASE_RETURN' => (Colors.red, Colors.redAccent),
  'PO_RETURN' => (Colors.orange, Colors.orangeAccent),
  _ => (Colors.blueGrey, Colors.blueGrey),
};

/// Localized return-type label (falls back to the raw server value).
String returnTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'PURCHASE_RETURN' => l10n.purchasesPurchasereturn,
  'PO_RETURN' => l10n.purchasesPoreturn,
  _ => type,
};
