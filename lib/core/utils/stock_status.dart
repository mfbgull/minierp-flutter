// Shared stock-status helpers for the inventory reports (stock level,
// low stock): the server emits raw English statuses ('In Stock', 'Low
// Stock', 'Out of Stock'), which the grids and detail dialogs render
// localized + colored (AGENTS.md self-audit: duplicated_logic == false).

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 'In Stock' / 'Low Stock' / 'Out of Stock' → localized label.
String stockStatusLabel(AppLocalizations l10n, String status) =>
    switch (status.toLowerCase()) {
      'in stock' => l10n.inventoryInstock,
      'low stock' => l10n.inventoryLowstock,
      'out of stock' => l10n.inventoryOutofstock,
      _ => status,
    };

/// Semantic color for a stock status (green / amber / red).
Color stockStatusColor(String status) => switch (status.toLowerCase()) {
  'in stock' => Colors.green.shade700,
  'low stock' => Colors.amber.shade800,
  'out of stock' => Colors.red.shade700,
  _ => Colors.grey.shade600,
};
