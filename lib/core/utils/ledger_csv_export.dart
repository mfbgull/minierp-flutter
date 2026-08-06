// Stock ledger CSV export.
//
// The builder is a pure function (no context, no plugins) so the row and
// running-balance logic is unit-testable in isolation; the save helper
// owns the platform interaction (FilePicker save dialog + toast
// feedback). Mirrors the table the ledger dialog renders: signed
// quantity → In/Out columns, Balance = running total after each
// movement (oldest-first walk of the newest-first API list).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/models/stock_movement.dart' show StockMovement;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import 'formatters.dart';
import 'movement_type_label.dart';

/// The running balance after each movement — keyed by movement id. The
/// API returns newest-first, so walk the reversed (oldest-first) list.
Map<int, num> stockLedgerBalances(List<StockMovement> movements) {
  final balances = <int, num>{};
  var running = 0.0;
  for (final m in movements.reversed) {
    running += m.quantity;
    balances[m.id] = running;
  }
  return balances;
}

/// Builds the CSV text for [movements] (newest-first display, matching
/// the ledger dialog table): Date | Type | Reference | Warehouse | In |
/// Out | Balance.
String buildStockLedgerCsv(
  AppLocalizations l10n,
  List<StockMovement> movements,
) {
  final balances = stockLedgerBalances(movements);
  final rows = <List<dynamic>>[
    [
      l10n.commonDate,
      l10n.inventoryStockledgerType,
      l10n.fieldsReference,
      l10n.fieldsWarehouse,
      l10n.inventoryStockledgerIn,
      l10n.inventoryStockledgerOut,
      l10n.inventoryStockledgerBalance,
    ],
  ];

  for (final m in movements) {
    final qty = m.quantity;
    final inQty = qty > 0 ? qty : null;
    final outQty = qty < 0 ? -qty : null;
    rows.add([
      m.movementDate.isEmpty ? '—' : Formatters.date(m.movementDate),
      movementTypeLabel(l10n, m.movementType),
      m.referenceDocNo ?? '—',
      m.warehouseCode ?? '—',
      inQty == null ? '—' : Formatters.number(inQty),
      outQty == null ? '—' : Formatters.number(outQty),
      Formatters.number(balances[m.id] ?? 0),
    ]);
  }

  return Csv().encode(rows);
}

/// Prompts for a save location via the platform file picker and writes
/// [csv] to the chosen path. Shows a success toast on completion and an
/// error toast on failure (PORTING.md §9). Returns the save path, or
/// null when the user cancels or an error occurs.
Future<String?> saveLedgerCsv(
  BuildContext context, {
  required String suggestedName,
  required String csv,
  required String successMessage,
  required String errorMessage,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(csv));
  try {
    final path = await FilePicker.saveFile(
      dialogTitle: suggestedName,
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: bytes,
    );
    if (path == null) return null; // cancelled
    await File(path).writeAsBytes(bytes, flush: true);
    if (!context.mounted) return path;
    showAppToast(context, successMessage);
    return path;
  } catch (_) {
    if (!context.mounted) return null;
    showAppToast(context, errorMessage, isError: true);
    return null;
  }
}
