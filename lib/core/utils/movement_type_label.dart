// Localized labels for stock-movement types. The screen's filter, the
// stock ledger table and its CSV export all render movement types — keep
// the mapping in one place so the labels can't drift between surfaces.

import '../../l10n/app_localizations.dart';

/// Localized label for a stock-movement type (falls back to the raw
/// value for unknown types).
String movementTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'PURCHASE' => l10n.stockmovementsFilterpurchase,
  'SALE' => l10n.stockmovementsFiltersale,
  'TRANSFER' => l10n.stockmovementsFiltertransfer,
  'PRODUCTION' => l10n.stockmovementsFilterproduction,
  'ADJUSTMENT' => l10n.stockmovementsFilteradjustment,
  _ => type,
};
