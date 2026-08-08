// Shared invoice status helpers — used by the sales list grid, the
// invoice form's status banner, and the invoices CSV export (PORTING.md
// §6: status text plus colors come from the web's
// `references/utils/statusColors.ts` conventions).

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Localized label for an invoice status value, falling back to the raw
/// server value when there's no key (defensive — the server owns the
/// status vocabulary).
String invoiceStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'Draft' => l10n.statusDraft,
      'Sent' => l10n.statusSent,
      'Paid' => l10n.statusPaid,
      'Unpaid' => l10n.statusUnpaid,
      'Overdue' => l10n.statusOverdue,
      'Cancelled' => l10n.statusCancelled,
      'Partially Paid' => l10n.statusPartiallypaid,
      'Returned' => l10n.statusReturned,
      'Partially Returned' => l10n.statusPartiallyreturned,
      _ => status,
    };

/// Status chip color (light) — port of the statusColors conventions in
/// PORTING.md §6.
Color invoiceStatusColor(String status) => switch (status) {
  'Draft' => Colors.blueGrey,
  'Sent' => Colors.lightBlue,
  'Unpaid' => Colors.orange,
  'Partially Paid' => Colors.amber,
  'Paid' => Colors.green,
  'Overdue' => Colors.red,
  'Cancelled' => Colors.grey,
  'Returned' => Colors.purple,
  'Partially Returned' => Colors.deepPurple,
  _ => Colors.blueGrey,
};
