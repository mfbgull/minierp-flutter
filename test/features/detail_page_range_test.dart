// Phase 3 tests — the detail-page unified range state (customer + supplier
// mirror) from unified-detail-date-picker-spec §3.
//
// Covers the spec's Phase-3 verify list:
//   - a page session seeds once from the current global range (§3.2),
//   - a ranged commit updates the global range (dashboard + report pairs) (§3.3),
//   - "All dates" updates only the page pair (§3.3 / D5),
//   - a newly opened page seeds from the current global value, while an
//     already-open page keeps its own snapshot (§3.2 / §13 matrix).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/features/customers/customer_providers.dart'
    show
        commitCustomerDetailRange,
        customerDetailFromDateProvider,
        customerDetailToDateProvider,
        nextCustomerDetailSession;
import 'package:minierp_app/features/reports/report_providers.dart'
    show
        globalReportFromDateProvider,
        globalReportToDateProvider,
        reportDsoFromDateProvider,
        reportDsoToDateProvider;
import 'package:minierp_app/features/suppliers/supplier_providers.dart'
    show
        commitSupplierDetailRange,
        nextSupplierDetailSession,
        supplierDetailFromDateProvider,
        supplierDetailToDateProvider;

/// Minimal Consumer widget that runs a commit helper — the helpers take a
/// `WidgetRef`, which only exists inside a widget tree (Riverpod 2: `Ref`
/// and `WidgetRef` are unrelated types).
class _CommitHarness extends ConsumerWidget {
  const _CommitHarness({required this.action});

  final void Function(WidgetRef ref) action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => action(ref),
      child: const Text('commit'),
    );
  }
}

/// Pumps a harness bound to [container] whose button runs [action], so the
/// commit helpers (typed WidgetRef) can be exercised from a widget test.
Future<ProviderContainer> _pumpHarness(
  WidgetTester tester, {
  required void Function(WidgetRef ref) action,
  required DateTime globalFrom,
  required DateTime globalTo,
}) async {
  final container = ProviderContainer(
    overrides: [
      // Deterministic app-wide range — bypasses the preferences-seeded
      // initializer so the tests don't depend on the current month.
      globalReportFromDateProvider.overrideWith((ref) => globalFrom),
      globalReportToDateProvider.overrideWith((ref) => globalTo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: _CommitHarness(action: action)),
      ),
    ),
  );
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'customer page seeds once from the global range and keeps its snapshot',
      (tester) async {
    final container = await _pumpHarness(
      tester,
      globalFrom: DateTime(2026, 3, 1),
      globalTo: DateTime(2026, 3, 31),
      action: (_) {},
    );

    // First read of a session seeds from the current global range.
    final sessionA = nextCustomerDetailSession();
    expect(
      container.read(customerDetailFromDateProvider(sessionA)),
      DateTime(2026, 3, 1),
    );
    expect(
      container.read(customerDetailToDateProvider(sessionA)),
      DateTime(2026, 3, 31),
    );

    // The dashboard range changes while the page is open — the open page
    // must NOT follow it (snapshot-on-open, v1 accepted behavior).
    container.read(globalReportFromDateProvider.notifier).state =
        DateTime(2026, 4, 1);
    container.read(globalReportToDateProvider.notifier).state =
        DateTime(2026, 4, 30);
    expect(
      container.read(customerDetailFromDateProvider(sessionA)),
      DateTime(2026, 3, 1),
    );

    // A newly opened page seeds from the *current* global value.
    final sessionB = nextCustomerDetailSession();
    expect(
      container.read(customerDetailFromDateProvider(sessionB)),
      DateTime(2026, 4, 1),
    );
    expect(
      container.read(customerDetailToDateProvider(sessionB)),
      DateTime(2026, 4, 30),
    );
  });

  testWidgets('customer ranged commit updates the global range and report pairs',
      (tester) async {
    final session = nextCustomerDetailSession();
    final container = await _pumpHarness(
      tester,
      globalFrom: DateTime(2026, 3, 1),
      globalTo: DateTime(2026, 3, 31),
      action: (ref) => commitCustomerDetailRange(ref, session),
    );

    // The pill writes the session pair, then onChanged runs the commit.
    container.read(customerDetailFromDateProvider(session).notifier).state =
        DateTime(2026, 2, 1);
    container.read(customerDetailToDateProvider(session).notifier).state =
        DateTime(2026, 2, 28);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    // Global range + a report-page pair follow the ranged commit.
    expect(
      container.read(globalReportFromDateProvider),
      DateTime(2026, 2, 1),
    );
    expect(
      container.read(globalReportToDateProvider),
      DateTime(2026, 2, 28),
    );
    expect(
      container.read(reportDsoFromDateProvider),
      DateTime(2026, 2, 1),
    );
    expect(
      container.read(reportDsoToDateProvider),
      DateTime(2026, 2, 28),
    );
  });

  testWidgets('customer All dates clears only the page pair, never the global range',
      (tester) async {
    final session = nextCustomerDetailSession();
    final container = await _pumpHarness(
      tester,
      globalFrom: DateTime(2026, 3, 1),
      globalTo: DateTime(2026, 3, 31),
      action: (ref) => commitCustomerDetailRange(ref, session),
    );

    // Select "All dates" — the pill writes null/null, then commits.
    container.read(customerDetailFromDateProvider(session).notifier).state =
        null;
    container.read(customerDetailToDateProvider(session).notifier).state =
        null;
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(
      container.read(customerDetailFromDateProvider(session)),
      isNull,
    );
    expect(container.read(customerDetailToDateProvider(session)), isNull);
    // The global range keeps its ranged value (the report-pair propagation
    // itself is asserted in the ranged-commit test above).
    expect(
      container.read(globalReportFromDateProvider),
      DateTime(2026, 3, 1),
    );
    expect(
      container.read(globalReportToDateProvider),
      DateTime(2026, 3, 31),
    );
  });

  testWidgets('two open customer pages stay independent', (tester) async {
    final sessionA = nextCustomerDetailSession();
    final sessionB = nextCustomerDetailSession();
    final container = await _pumpHarness(
      tester,
      globalFrom: DateTime(2026, 3, 1),
      globalTo: DateTime(2026, 3, 31),
      action: (ref) {
        // Page A commits a ranged change (also becomes the global value).
        commitCustomerDetailRange(ref, sessionA);
        // Page B selects All dates — local only.
        ref.read(customerDetailFromDateProvider(sessionB).notifier).state =
            null;
        ref.read(customerDetailToDateProvider(sessionB).notifier).state = null;
        commitCustomerDetailRange(ref, sessionB);
      },
    );
    container.read(customerDetailFromDateProvider(sessionA).notifier).state =
        DateTime(2026, 2, 1);
    container.read(customerDetailToDateProvider(sessionA).notifier).state =
        DateTime(2026, 2, 28);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    // Page A's ranged commit reached the global range…
    expect(
      container.read(globalReportFromDateProvider),
      DateTime(2026, 2, 1),
    );
    // …while page B's All dates is page-local and did not leak into A or
    // the global range.
    expect(container.read(customerDetailToDateProvider(sessionA)), isNotNull);
    expect(
      container.read(customerDetailFromDateProvider(sessionB)),
      isNull,
    );
    expect(
      container.read(customerDetailToDateProvider(sessionB)),
      isNull,
    );
    expect(
      container.read(globalReportToDateProvider),
      DateTime(2026, 2, 28),
    );
  });

  testWidgets('supplier mirror: seed, ranged commit, and All dates semantics',
      (tester) async {
    final container = await _pumpHarness(
      tester,
      globalFrom: DateTime(2026, 3, 1),
      globalTo: DateTime(2026, 3, 31),
      action: (_) {},
    );
    final session = nextSupplierDetailSession();

    // Seeds from the global range.
    expect(
      container.read(supplierDetailFromDateProvider(session)),
      DateTime(2026, 3, 1),
    );
    expect(
      container.read(supplierDetailToDateProvider(session)),
      DateTime(2026, 3, 31),
    );

    // Ranged commit → global follows.
    final ranged = nextSupplierDetailSession();
    final container2 = await _pumpHarness(
      tester,
      globalFrom: DateTime(2026, 3, 1),
      globalTo: DateTime(2026, 3, 31),
      action: (ref) => commitSupplierDetailRange(ref, ranged),
    );
    container2
        .read(supplierDetailFromDateProvider(ranged).notifier)
        .state = DateTime(2026, 6, 1);
    container2.read(supplierDetailToDateProvider(ranged).notifier).state =
        DateTime(2026, 6, 30);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(
      container2.read(globalReportFromDateProvider),
      DateTime(2026, 6, 1),
    );

    // All dates → local only.
    container2.read(supplierDetailFromDateProvider(ranged).notifier).state =
        null;
    container2.read(supplierDetailToDateProvider(ranged).notifier).state =
        null;
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(
      container2.read(supplierDetailFromDateProvider(ranged)),
      isNull,
    );
    expect(
      container2.read(globalReportFromDateProvider),
      DateTime(2026, 6, 1),
    );
  });
}
