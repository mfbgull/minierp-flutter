// Unit tests for the stock-ledger CSV export — the pure
// `buildStockLedgerCsv` / `stockLedgerBalances` helpers (the save helper
// is platform-interactive and covered by the widget tests via a mocked
// FilePicker channel).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/core/utils/ledger_csv_export.dart';
import 'package:minierp_app/data/models/stock_movement.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

StockMovement _movement({
  required int id,
  required String type,
  required num quantity,
  required String date,
  String? ref,
  String? warehouseCode,
}) => StockMovement(
  id: id,
  movementNo: 'SM-2026-$id',
  itemId: 1,
  warehouseId: 1,
  movementType: type,
  quantity: quantity,
  unitCost: null,
  referenceDocType: null,
  referenceDocNo: ref,
  remarks: null,
  movementDate: date,
  createdBy: 1,
  createdAt: '$date 09:00:00',
  itemCode: null,
  itemName: null,
  unitOfMeasure: null,
  warehouseCode: warehouseCode,
  warehouseName: null,
  createdByName: null,
);

void main() {
  // The builder uses intl DateFormat for the Date column — initialize the
  // en locale so dates render deterministically (same as the app does on
  // startup).
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  final movements = [
    // Newest-first, as the API returns.
    _movement(
      id: 3,
      type: 'TRANSFER',
      quantity: 2,
      date: '2026-02-03',
      warehouseCode: 'WH-RAW',
    ),
    _movement(
      id: 2,
      type: 'SALE',
      quantity: -3,
      date: '2026-02-02',
      ref: 'INV-2026-001',
      warehouseCode: 'WH-MAIN',
    ),
    _movement(
      id: 1,
      type: 'PURCHASE',
      quantity: 10,
      date: '2026-02-01',
      ref: 'PUR-2026-001',
      warehouseCode: 'WH-MAIN',
    ),
  ];

  test(
    'stockLedgerBalances walks oldest-first to the balance after each movement',
    () {
      final balances = stockLedgerBalances(movements);
      // PURCHASE +10 → 10; SALE -3 → 7; TRANSFER +2 → 9.
      expect(balances[1], 10);
      expect(balances[2], 7);
      expect(balances[3], 9);
    },
  );

  test(
    'buildStockLedgerCsv emits the header and the rows with in/out/balance',
    () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final csv = buildStockLedgerCsv(l10n, movements);
      final lines = csv.trim().split('\r\n');

      expect(lines.length, 4);
      expect(lines.first, contains('Date'));
      expect(lines.first, contains('Type'));
      expect(lines.first, contains('Reference'));
      expect(lines.first, contains('Warehouse'));
      expect(lines.first, contains('In'));
      expect(lines.first, contains('Out'));
      expect(lines.first, contains('Balance'));

      // Transfer row: In=2, Balance=9.
      expect(lines[1], contains('Transfer'));
      expect(lines[1], contains('WH-RAW'));
      expect(lines[1], contains('2'));
      expect(lines[1], contains('9'));
      // Sale row: Out=3, Balance=7.
      expect(lines[2], contains('Sale'));
      expect(lines[2], contains('INV-2026-001'));
      expect(lines[2], contains('3'));
      expect(lines[2], contains('7'));
      // Purchase row: In=10, Balance=10.
      expect(lines[3], contains('Purchase'));
      expect(lines[3], contains('PUR-2026-001'));
      expect(lines[3], contains('10'));
    },
  );

  test('buildStockLedgerCsv on an empty list emits just the header', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildStockLedgerCsv(l10n, const []);
    expect(csv.trim().split('\r\n'), hasLength(1));
    expect(csv, contains('Balance'));
  });
}
