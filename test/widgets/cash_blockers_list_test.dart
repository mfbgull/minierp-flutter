// PRET-002 — the cash-blocker row list. When a void or edit would overdraw
// cash, the server's 409 carries the journal lines on the first deficit date
// under `details`. This widget turns them into readable rows and truncates a
// long list into "and N more", so a wall of blockers cannot fill the dialog.
//
// UX-6 (audit/GLM-UX-REVIEW.md) changed the row contract: the journal
// reference_type and the ISO date are no longer rendered raw — the type goes
// through cashBlockerTypeLabel (localized label, humanized fallback) and the
// date through Formatters.date. These tests assert the NEW contract; the raw
// tokens 'SALE'/'EXPENSE'/ISO must NOT appear (see
// cash_blockers_localization_test.dart for the leak pin).

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
    // UX-6 contract: the type renders as a localized/humanized label, the
    // date locale-formatted — never the raw enum or ISO string.
    expect(find.textContaining('Sale'), findsOneWidget);
    expect(find.textContaining('Expense'), findsOneWidget);
    expect(find.textContaining('Nov 5, 2026'), findsOneWidget);
    expect(find.textContaining('Nov 6, 2026'), findsOneWidget);
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
    expect(find.textContaining('Sale'), findsNWidgets(3));
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
    expect(find.textContaining('Sale'), findsNWidgets(3));
  });
}
