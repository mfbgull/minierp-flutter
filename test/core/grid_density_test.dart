// P1 UI audit — grid density is a user preference with DESIGN.md's
// 32/40/48 row heights.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/core/theme/grid_density.dart';
import 'package:minierp_app/widgets/pluto_grid_screen.dart';
import 'package:pluto_grid/pluto_grid.dart';

void main() {
  test('density presets match the design scale', () {
    expect(GridDensity.compact.rowHeight, 32);
    expect(GridDensity.standard.rowHeight, 40);
    expect(GridDensity.comfortable.rowHeight, 48);
  });

  testWidgets('grid configuration follows the density scope', (tester) async {
    late PlutoGridConfiguration compact;
    late PlutoGridConfiguration standard;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: GridDensityScope(
          density: GridDensity.compact,
          child: Builder(
            builder: (context) {
              compact = plutoGridConfigurationFor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: GridDensityScope(
          density: GridDensity.standard,
          child: Builder(
            builder: (context) {
              standard = plutoGridConfigurationFor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(compact.style.rowHeight, GridDensity.compact.rowHeight);
    expect(standard.style.rowHeight, GridDensity.standard.rowHeight);
  });
}
