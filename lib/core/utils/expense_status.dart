// Shared expense status helpers — used by the expenses list grid and the
// expenses CSV export (PORTING.md §6: status text plus colors come from
// the web's `references/utils/statusColors.ts` conventions).

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Localized label for an expense status value, falling back to the raw
/// server value when there's no key (defensive — the server owns the
/// status vocabulary).
String expenseStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'Draft' => l10n.statusDraft,
      'Submitted' => l10n.statusSubmitted,
      'Approved' => l10n.statusApproved,
      'Paid' => l10n.statusPaid,
      'Cancelled' => l10n.statusCancelled,
      _ => status,
    };

/// Status chip color (light) — port of the statusColors conventions in
/// PORTING.md §6.
Color expenseStatusColor(String status) => switch (status) {
  'Draft' => Colors.blueGrey,
  'Submitted' => Colors.blue,
  'Approved' => Colors.green,
  'Paid' => Colors.teal,
  'Cancelled' => Colors.red,
  _ => Colors.blueGrey,
};
