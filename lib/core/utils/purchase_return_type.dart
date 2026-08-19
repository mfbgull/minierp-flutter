// Shared purchase-return type helpers — used by the list grid, the detail
// dialog, and the CSV export builder. The server's `reference_doctype` is
// one of 'PURCHASE_RETURN' (return against a direct purchase) or
// 'PO_RETURN' (return against a purchase order); unknown values render
// as-is. Lives in core/utils (mirroring `movement_type_label.dart`) so
// the core CSV export can reuse it without importing from features.

import 'package:flutter/material.dart';
import '../../core/theme/status_colors.dart';

import '../../l10n/app_localizations.dart';

/// Return-type badge colors — Purchase Return red (stock leaves),
/// PO Return orange: the light color plus the darker variant used as text
/// on dark themes.
Color returnTypeColors(ColorScheme scheme, String type) =>
    StatusColors(scheme).returnType(type);

/// Localized return-type label (falls back to the raw server value).
String returnTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'PURCHASE_RETURN' => l10n.purchasesPurchasereturn,
  'PO_RETURN' => l10n.purchasesPoreturn,
  _ => type,
};
