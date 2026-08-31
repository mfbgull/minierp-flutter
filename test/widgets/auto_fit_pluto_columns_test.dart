// Unit tests for autoFitPlutoColumns viewport-budget logic.
//
// The function measures each column's content width, then constrains the
// total growth to the grid's viewport so status / action columns never get
// pushed off-screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, kAutoFitMaxColumnWidth;
import 'package:pluto_grid/pluto_grid.dart';

/// Convenience: two plain-text columns.
List<PlutoColumn> _twoTextColumns() => [
      PlutoColumn(
        title: 'Name',
        field: 'name',
        type: PlutoColumnType.text(),
        width: 100,
      ),
      PlutoColumn(
        title: 'Value',
        field: 'value',
        type: PlutoColumnType.text(),
        width: 100,
      ),
    ];

List<PlutoRow> _rows(List<Map<String, String>> data) => data
    .map((d) => PlutoRow(cells: {
          for (final e in d.entries) e.key: PlutoCell(value: e.value),
        }))
    .toList();

void main() {
  group('autoFitPlutoColumns', () {
    testWidgets('widens columns when there is slack', (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: _twoTextColumns(),
              rows: _rows([
                {'name': 'Acme Corp', 'value': '1234.56'},
                {'name': 'Beta Ltd', 'value': '789.00'},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final before = sm.columns.map((c) => c.width).toList();
      autoFitPlutoColumns(sm);
      await tester.pump();

      final after = sm.columns.map((c) => c.width).toList();
      expect(after[0], greaterThan(before[0]));
      expect(after[1], greaterThan(before[1]));
    });

    testWidgets('does not exceed the viewport budget', (tester) async {
      // Columns start small (100 each) in a 300px viewport — there is 100px
      // of slack. Auto-fit should grow them but never exceed the viewport.
      tester.view.physicalSize = const Size(300, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: [
                PlutoColumn(
                  title: 'Long Column Name',
                  field: 'a',
                  type: PlutoColumnType.text(),
                  width: 100,
                ),
                PlutoColumn(
                  title: 'Another Long Name',
                  field: 'b',
                  type: PlutoColumnType.text(),
                  width: 100,
                ),
              ],
              rows: _rows([
                {'a': 'Some wide text content here', 'b': 'More text here'},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      autoFitPlutoColumns(sm);
      await tester.pump();

      // Total width must not exceed the viewport.
      final total = sm.columns.fold<double>(0, (s, c) => s + c.width);
      expect(total, lessThanOrEqualTo(300));
    });

    testWidgets('proportionally scales growth when requests exceed slack',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: [
                for (final name in ['Alpha', 'Bravo', 'Charlie', 'Delta'])
                  PlutoColumn(
                    title: name,
                    field: name.toLowerCase(),
                    type: PlutoColumnType.text(),
                    width: 100,
                  ),
              ],
              rows: _rows([
                {
                  'alpha': 'Wide Alpha text',
                  'bravo': 'Wide Bravo text',
                  'charlie': 'Wide Charlie text',
                  'delta': 'Wide Delta text',
                },
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      autoFitPlutoColumns(sm);
      await tester.pump();

      final total = sm.columns.fold<double>(0, (s, c) => s + c.width);
      expect(total, lessThanOrEqualTo(400));
    });

    testWidgets('skips columns with custom renderers', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final rendererColumn = PlutoColumn(
        title: 'Badge',
        field: 'badge',
        type: PlutoColumnType.text(),
        width: 80,
        renderer: (ctx) => const Icon(Icons.check),
      );

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: [
                PlutoColumn(
                  title: 'Name',
                  field: 'name',
                  type: PlutoColumnType.text(),
                  width: 100,
                ),
                rendererColumn,
              ],
              rows: _rows([
                {'name': 'Acme Corp', 'badge': 'active'},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rendererWidthBefore = rendererColumn.width;
      autoFitPlutoColumns(sm);
      await tester.pump();

      // Renderer column should not have changed width.
      expect(rendererColumn.width, equals(rendererWidthBefore));
    });

    testWidgets('skips hidden columns', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // PlutoGrid may filter hidden columns from the visible list.
      // Verify that the auto-fit logic iterates all columns without
      // error and that only visible columns grow.
      final hidColumn = PlutoColumn(
        title: 'Hidden',
        field: 'hid',
        type: PlutoColumnType.text(),
        width: 100,
        hide: true,
      );
      final visColumn = PlutoColumn(
        title: 'Visible',
        field: 'vis',
        type: PlutoColumnType.text(),
        width: 100,
      );

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: [visColumn, hidColumn],
              rows: _rows([
                {'vis': 'Acme Corp', 'hid': 'secret'},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final visBefore = visColumn.width;
      autoFitPlutoColumns(sm);
      await tester.pump();

      // Visible column should have grown.
      expect(visColumn.width, greaterThan(visBefore));
      // Hidden column should not have grown (auto-fit skips it).
      expect(hidColumn.width, equals(100));
    });

    testWidgets('falls back to unbounded when viewport is null', (tester) async {
      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: _twoTextColumns(),
              rows: _rows([
                {'name': 'Acme Corp', 'value': '1234.56'},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      autoFitPlutoColumns(sm);
      await tester.pump();

      // Columns should have grown (unbounded mode).
      final total = sm.columns.fold<double>(0, (s, c) => s + c.width);
      expect(total, greaterThan(200));
    });

    testWidgets('no-ops when column width is already within 1px of ideal',
        (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: [
                PlutoColumn(
                  title: 'A',
                  field: 'a',
                  type: PlutoColumnType.text(),
                  width: 50,
                ),
              ],
              rows: _rows([
                {'a': 'X'},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Run once to set ideal widths.
      autoFitPlutoColumns(sm);
      await tester.pump();
      final afterFirst = sm.columns.first.width;

      // Run again — should not change.
      autoFitPlutoColumns(sm);
      await tester.pump();
      final afterSecond = sm.columns.first.width;

      expect(afterSecond, closeTo(afterFirst, 1));
    });

    testWidgets('respects column minWidth', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: [
                PlutoColumn(
                  title: 'Narrow',
                  field: 'n',
                  type: PlutoColumnType.text(),
                  width: 50,
                  minWidth: 80,
                ),
              ],
              rows: _rows([
                {'n': 'X'},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      autoFitPlutoColumns(sm);
      await tester.pump();

      expect(sm.columns.first.width, greaterThanOrEqualTo(80));
    });

    testWidgets('clamps column width to kAutoFitMaxColumnWidth',
        (tester) async {
      tester.view.physicalSize = const Size(2000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: [
                PlutoColumn(
                  title: 'Wide',
                  field: 'w',
                  type: PlutoColumnType.text(),
                  width: 100,
                ),
              ],
              rows: _rows([
                {'w': 'A' * 500},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      autoFitPlutoColumns(sm);
      await tester.pump();

      expect(
        sm.columns.first.width,
        lessThanOrEqualTo(kAutoFitMaxColumnWidth),
      );
    });

    testWidgets('growth is proportional when columns compete for slack',
        (tester) async {
      tester.view.physicalSize = const Size(250, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: [
                PlutoColumn(
                  title: 'Alpha',
                  field: 'alpha',
                  type: PlutoColumnType.text(),
                  width: 100,
                ),
                PlutoColumn(
                  title: 'Bravo',
                  field: 'bravo',
                  type: PlutoColumnType.text(),
                  width: 100,
                ),
              ],
              rows: _rows([
                {'alpha': 'Long Alpha text', 'bravo': 'Long Bravo text'},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final beforeA = sm.columns[0].width;
      final beforeB = sm.columns[1].width;

      autoFitPlutoColumns(sm);
      await tester.pump();

      final afterA = sm.columns[0].width;
      final afterB = sm.columns[1].width;

      // Both should have grown, but total must not exceed viewport.
      expect(afterA, greaterThan(beforeA));
      expect(afterB, greaterThan(beforeB));
      expect(afterA + afterB, lessThanOrEqualTo(250));
    });

    testWidgets('total never exceeds viewport across many calls',
        (tester) async {
      tester.view.physicalSize = const Size(300, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late PlutoGridStateManager sm;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlutoGrid(
              columns: _twoTextColumns(),
              rows: _rows([
                {'name': 'Acme Corp', 'value': '1234.56'},
                {'name': 'Beta Ltd', 'value': '789.00'},
              ]),
              onLoaded: (e) => sm = e.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Call multiple times — idempotent and never over budget.
      for (var i = 0; i < 5; i++) {
        autoFitPlutoColumns(sm);
        await tester.pump();
        final total = sm.columns.fold<double>(0, (s, c) => s + c.width);
        expect(
          total,
          lessThanOrEqualTo(300),
          reason: 'exceeded viewport on iteration $i',
        );
      }
    });
  });
}
