// Widget tests for the shared list-screen toolbar
// (`lib/widgets/screen_toolbar.dart`): the search field's suffix
// switching (text-clear `Icons.clear` vs clear-all
// `Icons.filter_alt_off`), the `onClearSearch` hook screens use to
// reset server pagination, the disabled search state
// (`searchEnabled: false`), the shortcut-discoverability hints, and the
// keyboard shortcuts (Ctrl+F/N/R/E) dispatched by the shell's
// ScreenShortcutScope. The widget is pumped inside the app's l10n
// MaterialApp so it can resolve `AppLocalizations`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/screen_shortcuts.dart';
import 'package:minierp_app/widgets/screen_toolbar.dart';

/// Pumps [child] inside the app's l10n MaterialApp so `ScreenToolbar`
/// can resolve `AppLocalizations` (search hint, tooltips).
Widget _harness(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

/// Presses Ctrl+[key] (down, key, up, up) — the sequence Shortcuts
/// matches for `SingleActivator(…, control: true)`.
Future<void> _pressCtrlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  group('search suffix switching (text-clear vs clear-all)', () {
    testWidgets('no suffix while the field is empty without clear-all', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            searchController: controller,
            onSearchChanged: (_) {},
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget); // prefix
      expect(find.byIcon(Icons.clear), findsNothing);
      expect(find.byIcon(Icons.filter_alt_off), findsNothing);
    });

    testWidgets('text-clear icon appears once text is entered', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            searchController: controller,
            onSearchChanged: (_) {},
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'bolt');
      await tester.pump();

      expect(find.byIcon(Icons.clear), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_off), findsNothing);
      // The text-clear suffix carries the shared clear tooltip too.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ScreenToolbar)),
      )!;
      expect(find.byTooltip(l10n.commonClear), findsOneWidget);
    });

    testWidgets('clear-all icon shows when onClearAll + hasActiveFilters', (
      tester,
    ) async {
      var clearAllCalls = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            searchController: controller,
            onSearchChanged: (_) {},
            onClearAll: () => clearAllCalls++,
            hasActiveFilters: true,
          ),
        ),
      );

      // Shown even with an empty field...
      expect(find.byIcon(Icons.filter_alt_off), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsNothing);
      // ...with the shared clear-all tooltip.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ScreenToolbar)),
      )!;
      expect(find.byTooltip(l10n.commonClear), findsOneWidget);

      // ...and it takes priority over the text-clear while typing too.
      await tester.enterText(find.byType(TextField), 'bolt');
      await tester.pump();
      expect(find.byIcon(Icons.filter_alt_off), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsNothing);

      await tester.tap(find.byIcon(Icons.filter_alt_off));
      expect(clearAllCalls, 1);
    });

    testWidgets(
      'suffix switches from text-clear to clear-all when filters activate',
      (tester) async {
        var filtersActive = false;
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _harness(
            StatefulBuilder(
              builder: (context, setState) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScreenToolbar(
                    searchController: controller,
                    onSearchChanged: (_) {},
                    onClearAll: () {},
                    hasActiveFilters: filtersActive,
                  ),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () => setState(() => filtersActive = true),
                        child: const Text('activate filter'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => filtersActive = false),
                        child: const Text('deactivate filter'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        // Filters inactive → typing shows the text-clear suffix.
        await tester.enterText(find.byType(TextField), 'bolt');
        await tester.pump();
        expect(find.byIcon(Icons.clear), findsOneWidget);
        expect(find.byIcon(Icons.filter_alt_off), findsNothing);

        // A filter becomes active → the suffix switches to clear-all.
        await tester.tap(find.text('activate filter'));
        await tester.pump();
        expect(find.byIcon(Icons.filter_alt_off), findsOneWidget);
        expect(find.byIcon(Icons.clear), findsNothing);

        // Clearing the filters switches the suffix back to text-clear.
        await tester.tap(find.text('deactivate filter'));
        await tester.pump();
        expect(find.byIcon(Icons.clear), findsOneWidget);
        expect(find.byIcon(Icons.filter_alt_off), findsNothing);
      },
    );
  });

  group('text-clear tap behavior', () {
    testWidgets('default clear empties the field and re-runs the search', (
      tester,
    ) async {
      final controller = TextEditingController();
      final searchCalls = <String>[];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            searchController: controller,
            onSearchChanged: searchCalls.add,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'bolt');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(searchCalls, ['bolt', '']);
      // The suffix reverts to hidden once the field is empty.
      expect(find.byIcon(Icons.clear), findsNothing);
    });

    testWidgets('onClearSearch hook fires instead of the default (page reset)', (
      tester,
    ) async {
      final controller = TextEditingController();
      final searchCalls = <String>[];
      var clearCalls = 0;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            searchController: controller,
            onSearchChanged: searchCalls.add,
            onClearSearch: () => clearCalls++,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'bolt');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      // The screen's hook owns the clear — the widget neither clears
      // the field nor re-runs onSearchChanged itself.
      expect(clearCalls, 1);
      expect(controller.text, 'bolt');
      expect(searchCalls, ['bolt']);
    });
  });

  group('disabled search state', () {
    testWidgets('searchEnabled: false disables the TextField', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            searchController: controller,
            searchEnabled: false,
            onSearchChanged: (_) {},
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
      // Still rendered with the search affordance.
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('search is enabled by default', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(searchController: controller, onSearchChanged: (_) {}),
        ),
      );

      expect(
        tester.widget<TextField>(find.byType(TextField)).enabled,
        isTrue,
      );
    });
  });

  group('structural', () {
    testWidgets('omitting searchController renders no search field', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(const ScreenToolbar()));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('refresh button appears and fires when onRefresh is given', (
      tester,
    ) async {
      var refreshCalls = 0;
      await tester.pumpWidget(
        _harness(ScreenToolbar(onRefresh: () => refreshCalls++)),
      );
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh));
      expect(refreshCalls, 1);
    });
  });

  group('shortcut discoverability hints', () {
    testWidgets('search hint advertises the Ctrl+F chord', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            searchController: controller,
            onSearchChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Search ($kShortcutFindChord)'), findsOneWidget);
    });

    testWidgets('custom search hints keep the Ctrl+F chord', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            searchController: controller,
            searchHint: 'Find items',
            onSearchChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Find items ($kShortcutFindChord)'), findsOneWidget);
    });

    testWidgets('disabled search omits the Ctrl+F chord', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            searchController: controller,
            searchEnabled: false,
            onSearchChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Search'), findsOneWidget);
      expect(find.textContaining(kShortcutFindChord), findsNothing);
    });

    testWidgets('first primary action carries the Ctrl+N tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            primaryActions: [
              FilledButton(
                onPressed: () {},
                child: const Text('New Item'),
              ),
              FilledButton.tonal(
                onPressed: () {},
                child: const Text('Bulk Import'),
              ),
            ],
          ),
        ),
      );

      // Only the first (the Ctrl+N target) is hint-wrapped.
      expect(find.byTooltip(kShortcutNewChord), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Tooltip),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('refresh tooltip advertises the Ctrl+R chord', (tester) async {
      await tester.pumpWidget(
        _harness(ScreenToolbar(onRefresh: () {})),
      );
      expect(
        find.byTooltip('Refresh ($kShortcutRefreshChord)'),
        findsOneWidget,
      );
    });

    testWidgets('no Ctrl+R hint without a refresh button', (tester) async {
      await tester.pumpWidget(_harness(const ScreenToolbar()));
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byTooltip(kShortcutRefreshChord), findsNothing);
    });

    testWidgets('first enabled export action carries the Ctrl+E tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            actions: [
              // Disabled (loading/empty) — not the Ctrl+E target.
              TextButton.icon(
                onPressed: null,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export disabled'),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ),
      );

      // Only the first *enabled* action (the Ctrl+E target) is
      // hint-wrapped.
      expect(find.byTooltip(kShortcutExportChord), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Tooltip),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no Ctrl+E hint when every export action is disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ScreenToolbar(
            actions: [
              TextButton.icon(
                onPressed: null,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ),
      );
      expect(find.byTooltip(kShortcutExportChord), findsNothing);
    });
  });

  group('keyboard shortcuts (Ctrl+F / Ctrl+N)', () {
    testWidgets('Ctrl+F focuses the search field from elsewhere on the screen',
        (tester) async {
      final controller = TextEditingController();
      final gridFocus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(gridFocus.dispose);

      await tester.pumpWidget(
        _harness(
          ScreenShortcutScope(
            child: Column(
              children: [
                ScreenToolbar(
                  searchController: controller,
                  onSearchChanged: (_) {},
                ),
                // Simulates the grid below the toolbar holding focus.
                TextField(focusNode: gridFocus, autofocus: true),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, gridFocus);

      await _pressCtrlKey(tester, LogicalKeyboardKey.keyF);
      await tester.pump();

      final searchField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(FocusManager.instance.primaryFocus, searchField.focusNode);
    });

    testWidgets('Ctrl+N fires the first primary action', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var newCalls = 0;

      await tester.pumpWidget(
        _harness(
          ScreenShortcutScope(
            child: ScreenToolbar(
              searchController: controller,
              onSearchChanged: (_) {},
              primaryActions: [
                FilledButton(
                  onPressed: () => newCalls++,
                  child: const Text('New Item'),
                ),
              ],
            ),
          ),
        ),
      );

      // Focus inside the scope (the search field), then Ctrl+N.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await _pressCtrlKey(tester, LogicalKeyboardKey.keyN);
      await tester.pump();

      expect(newCalls, 1);
    });

    testWidgets('Ctrl+N without a primary action is a no-op', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          ScreenShortcutScope(
            child: ScreenToolbar(
              searchController: controller,
              onSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await _pressCtrlKey(tester, LogicalKeyboardKey.keyN);
      await tester.pump();

      // Nothing crashed and the search field kept focus.
      final searchField = tester.widget<TextField>(find.byType(TextField));
      expect(FocusManager.instance.primaryFocus, searchField.focusNode);
    });

    testWidgets('only the visible branch toolbar responds (TickerMode prune)',
        (tester) async {
      // Regression guard for the shell's StatefulShellRoute.indexedStack:
      // every branch's screen stays mounted, and go_router wraps the
      // hidden ones in TickerMode(enabled: false) — a shortcut must always
      // resolve to the visible branch's toolbar, never a hidden one.
      var visibleNew = 0;
      var hiddenNew = 0;
      Widget toolbar(void Function() onPressed, TextEditingController c) =>
          ScreenToolbar(
            searchController: c,
            onSearchChanged: (_) {},
            primaryActions: [
              FilledButton(onPressed: onPressed, child: const Text('New')),
            ],
          );
      final visibleController = TextEditingController();
      final hiddenController = TextEditingController();
      addTearDown(visibleController.dispose);
      addTearDown(hiddenController.dispose);

      await tester.pumpWidget(
        _harness(
          ScreenShortcutScope(
            child: Column(
              children: [
                // Hidden branch FIRST in tree order — exactly what
                // go_router's shell wraps inactive branches in. The walk
                // must prune it and continue to the visible toolbar;
                // without the TickerMode guard it would return this one.
                TickerMode(
                  enabled: false,
                  child: toolbar(() => hiddenNew++, hiddenController),
                ),
                // Visible branch — TickerMode(enabled: true).
                TickerMode(
                  enabled: true,
                  child: toolbar(() => visibleNew++, visibleController),
                ),
              ],
            ),
          ),
        ),
      );

      // Focus even lands inside the hidden branch's own field — the walk
      // is focus-independent and must still resolve the visible toolbar.
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await _pressCtrlKey(tester, LogicalKeyboardKey.keyN);
      await tester.pump();

      expect(visibleNew, 1);
      expect(hiddenNew, 0);
    });

    testWidgets('Ctrl+R fires onRefresh from elsewhere on the screen', (
      tester,
    ) async {
      var refreshCalls = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          ScreenShortcutScope(
            child: ScreenToolbar(
              searchController: controller,
              onSearchChanged: (_) {},
              onRefresh: () => refreshCalls++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await _pressCtrlKey(tester, LogicalKeyboardKey.keyR);
      await tester.pump();

      expect(refreshCalls, 1);
    });

    testWidgets('Ctrl+R without a refresh button is a no-op', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          ScreenShortcutScope(
            child: ScreenToolbar(
              searchController: controller,
              onSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await _pressCtrlKey(tester, LogicalKeyboardKey.keyR);
      await tester.pump();

      // Nothing crashed and the search field kept focus.
      final searchField = tester.widget<TextField>(find.byType(TextField));
      expect(FocusManager.instance.primaryFocus, searchField.focusNode);
    });

    testWidgets('Ctrl+E fires the first enabled export action', (tester) async {
      var exportCalls = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          ScreenShortcutScope(
            child: ScreenToolbar(
              searchController: controller,
              onSearchChanged: (_) {},
              actions: [
                TextButton.icon(
                  onPressed: () => exportCalls++,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Export CSV'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await _pressCtrlKey(tester, LogicalKeyboardKey.keyE);
      await tester.pump();

      expect(exportCalls, 1);
    });

    testWidgets('Ctrl+E with only a disabled export action is a no-op', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          ScreenShortcutScope(
            child: ScreenToolbar(
              searchController: controller,
              onSearchChanged: (_) {},
              actions: [
                TextButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Export CSV'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await _pressCtrlKey(tester, LogicalKeyboardKey.keyE);
      await tester.pump();

      // Nothing crashed and the search field kept focus.
      final searchField = tester.widget<TextField>(find.byType(TextField));
      expect(FocusManager.instance.primaryFocus, searchField.focusNode);
    });

    testWidgets('shortcuts do not fire while a dialog is open', (tester) async {
      var newCalls = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          ScreenShortcutScope(
            child: Builder(
              builder: (dialogContext) => Column(
                children: [
                  ScreenToolbar(
                    searchController: controller,
                    onSearchChanged: (_) {},
                    primaryActions: [
                      FilledButton(
                        onPressed: () => newCalls++,
                        child: const Text('New Item'),
                      ),
                    ],
                  ),
                  OutlinedButton(
                    onPressed: () => showDialog<void>(
                      context: dialogContext,
                      builder: (_) => const AlertDialog(
                        content: TextField(
                          autofocus: true,
                          decoration:
                              InputDecoration(labelText: 'dialog field'),
                        ),
                      ),
                    ),
                    child: const Text('open dialog'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Open the dialog and let its field take focus.
      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Ctrl+N from inside the dialog must not reach the screen below.
      await _pressCtrlKey(tester, LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(newCalls, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
