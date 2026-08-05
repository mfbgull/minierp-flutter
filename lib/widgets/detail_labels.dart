// Shared detail-dialog label helpers — the item, customer, supplier and
// ledger dialogs otherwise each define a private `_label`/`_dash` copy
// (AGENTS.md self-audit: duplicated_logic == false).

import 'package:flutter/material.dart';

/// The muted section-label style used throughout the detail dialogs
/// (e.g. "Customer Details", "Stock by Warehouse").
Widget detailSectionLabel(BuildContext context, String text) => Text(
  text,
  style: Theme.of(context).textTheme.labelMedium?.copyWith(
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    letterSpacing: 0.4,
  ),
);

/// Renders a nullable/empty detail value as an em dash (the accounting
/// convention the detail dialogs use for absent fields).
String detailDash(String? value) =>
    (value == null || value.isEmpty) ? '—' : value;
