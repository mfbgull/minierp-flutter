// Shared invoice-return badge helpers — used by the returns grid (no
// dedicated Type column — every row is a `RETURN` movement — so they
// drive the detail dialog's badge) and the detail dialog. The server's
// `reference_doctype` is 'RETURN' for all invoice-return movements;
// unknown values render as-is (defensive — the server owns the
// vocabulary).

import 'package:flutter/material.dart';
import '../../core/theme/status_colors.dart';

import '../../l10n/app_localizations.dart';

/// Return badge colors — teal (returns restock the warehouse, unlike
/// purchase returns which leave it): the light color plus the darker
/// variant used as text on dark themes.
Color invoiceReturnTypeColors(ColorScheme scheme, String type) =>
    StatusColors(scheme).invoiceReturnType(type);

/// Localized return label (falls back to the raw server value).
String invoiceReturnTypeLabel(AppLocalizations l10n, String type) =>
    switch (type) {
      'RETURN' => l10n.salesreturnsReturn,
      _ => type,
    };
