// Round-trip tests for GridColumnWidths (`lib/widgets/
// grid_column_widths.dart`): a simulated column drag must land in the
// SharedPreferences blob, and a freshly-mounted grid under the same key
// must re-apply it.
//
// Regression coverage: _mergeSave once wrote an empty per-screen map
// (the user's edits were never merged in), so persistence silently
// no-op'd while the storage key looked healthy on disk.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/widgets/grid_column_widths.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'grid_column_widths';
const _screenKey = 'sales_test';

/// Mounts a two-column grid and returns its state manager —
/// resizeColumn touches the scroll state, which only exists once the
/// grid's widget tree is live.
Future<PlutoGridStateManager> _mountGrid(WidgetTester tester) async {
  PlutoGridStateManager? manager;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: PlutoGrid(
            key: UniqueKey(),
            columns: [
              PlutoColumn(
                title: 'Batch',
                field: 'batchNo',
                type: PlutoColumnType.text(),
                width: 120,
              ),
              PlutoColumn(
                title: 'Warehouse',
                field: 'warehouse',
                type: PlutoColumnType.text(),
                width: 130,
                // Custom-rendered column (link/badge style, as on the
                // customer detail tabs) — its width must be remembered
                // just like a plain column's.
                renderer: (ctx) => Text('${ctx.cell.value}'),
              ),
            ],
            rows: const [],
            onLoaded: (event) => manager = event.stateManager,
          ),
        ),
      ),
    ),
  );
  return manager!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<Map<String, dynamic>> storedBlob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    return raw == null ? const {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  testWidgets('user resize is persisted and restored on next mount',
      (tester) async {
    final manager = await _mountGrid(tester);
    final tracker = GridColumnWidths.attach(
      stateManager: manager,
      screenKey: _screenKey,
    );
    // Let attach's post-frame restore/baseline pass settle.
    await tester.pump();
    await tester.pumpAndSettle();

    // Simulate the drag: the column-edge handler calls this exact method.
    // Both a plain column AND a custom-rendered one (regression: rendered
    // columns were once excluded from capture entirely).
    manager.resizeColumn(manager.columns.first, 50);
    manager.resizeColumn(manager.columns.last, -30);
    // Advance past the save debounce so the debounced capture runs.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final screen = await storedBlob();
    expect(screen[_screenKey], isA<Map>());
    expect(
      (screen[_screenKey] as Map)['batchNo'],
      closeTo(170, 0.6),
      reason: 'dragged width must be merged into storage, not dropped',
    );
    expect(
      (screen[_screenKey] as Map)['warehouse'],
      closeTo(100, 0.6),
      reason: 'rendered columns must be captured too',
    );

    tracker.dispose();

    // A freshly mounted grid (default widths) under the same key restores.
    final restored = await _mountGrid(tester);
    GridColumnWidths.attach(stateManager: restored, screenKey: _screenKey);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(restored.columns.first.width, closeTo(170, 0.6));
    expect(restored.columns.last.width, closeTo(100, 0.6));
  });

  testWidgets('programmatic resizes are not persisted', (tester) async {
    final manager = await _mountGrid(tester);
    final tracker = GridColumnWidths.attach(
      stateManager: manager,
      screenKey: _screenKey,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    tracker.programmaticPass(() {
      manager.resizeColumn(manager.columns.first, 40);
      manager.resizeColumn(manager.columns.last, -20);
    });
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final screen = await storedBlob();
    expect(screen[_screenKey], isNull, reason:
        'auto-fit sized widths must not freeze the layout');
  });
}
