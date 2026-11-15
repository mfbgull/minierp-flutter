// PRET-002 — the cash-blocker row list. When a void or edit would overdraw
// cash, the server's 409 carries the journal lines on the first deficit date
// under `details`. This widget turns them into readable rows and truncates a
// long list into "and N more", so a wall of blockers cannot fill the dialog.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/cash_blockers_list.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

CashBlocker _blocker(int id, {String type = 'SALE', String date = '2026-11-05'}) =>
    CashBlocker(id: id, date: date, amount: 100 * id, type: type);

void main() {
  testWidgets('an empty list renders nothing', (tester) async {
    await tester.pumpWidget(_host(const CashBlockersList(blockers: [])));
    expect(find.textContaining('Cash'), findsNothing);
  });

  testWidgets('renders one row per blocker with its type, date and amount',
      (tester) async {
    await tester.pumpWidget(
      _host(
        CashBlockersList(
          blockers: [
            _blocker(1, type: 'SALE', date: '2026-11-05'),
            _blocker(2, type: 'EXPENSE', date: '2026-11-06'),
          ],
        ),
      ),
    );
    expect(find.textContaining('SALE'), findsOneWidget);
    expect(find.textContaining('EXPENSE'), findsOneWidget);
    expect(find.textContaining('2026-11-05'), findsOneWidget);
    expect(find.textContaining('2026-11-06'), findsOneWidget);
  });

  testWidgets('shows the guard title and the retry hint', (tester) async {
    await tester.pumpWidget(_host(CashBlockersList(blockers: [_blocker(1)])));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.refundBlockedTitle), findsOneWidget);
    expect(find.text(l10n.refundBlockedHint), findsOneWidget);
  });

  testWidgets('truncates a long list into "and N more"', (tester) async {
    await tester.pumpWidget(
      _host(
        CashBlockersList(
          blockers: [for (var i = 1; i <= 8; i++) _blocker(i)],
          previewCount: 3,
        ),
      ),
    );
    // Three rows shown, five collapsed into the counter.
    expect(find.textContaining('SALE'), findsNWidgets(3));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.refundBlockedMore(5)), findsOneWidget);
  });

  testWidgets('a list at the preview cap shows no counter', (tester) async {
    await tester.pumpWidget(
      _host(
        CashBlockersList(
          blockers: [for (var i = 1; i <= 3; i++) _blocker(i)],
          previewCount: 3,
        ),
      ),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.refundBlockedMore(0)), findsNothing);
    expect(find.textContaining('SALE'), findsNWidgets(3));
  });
}
