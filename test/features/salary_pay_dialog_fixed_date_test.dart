// Audit-artifact policy (audit/DECISIONS.md D26 item 4, Option B).
//
// The accounting-report audit tests write tracked artifacts under
// audit/accounting-audit/remediation/. Those files must be byte-stable from
// one run to the next, so the tests must supply a fixed date. Before this
// change the salary dialog always opened on `DateTime.now()`, and the test
// rewrote the one label that carried today's date back to a frozen string.
// That kept the file stable by lookup, not by rule: it silently depended on
// the machine's date never equalling the frozen one, and it could not see a
// real regression in that label.
//
// The rule this pins: the dialog takes its opening date from its caller. The
// app keeps the today default; a test that needs a fixed date passes one in.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/utils/date_utils.dart' show isoDate;
import 'package:minierp_app/core/utils/formatters.dart';
import 'package:minierp_app/features/employees/employee_models.dart'
    show Employee;
import 'package:minierp_app/features/employees/employee_providers.dart';
import 'package:minierp_app/features/employees/loan_providers.dart';
import 'package:minierp_app/features/employees/salary_pay_dialog.dart';

import '../test_helpers.dart';

const Employee _employee = Employee(
  id: 1,
  employeeCode: 'AUDIT',
  firstName: 'Audit',
  lastName: 'Fixture',
  salary: 1000,
  isActive: true,
);

Widget _host(Widget child) => buildTestable(
  Scaffold(body: child),
  overrides: [
    employeeSalaryHistoryProvider(1).overrideWith((ref) async => []),
    employeeActiveLoansProvider(1).overrideWith((ref) => []),
  ],
);

void main() {
  testWidgets(
    'the dialog opens on the date its caller supplies, not on the machine date',
    (tester) async {
      // Deliberately not today: a fixed audit date from the past.
      final fixed = DateTime(2026, 11, 15);

      await tester.pumpWidget(
        _host(SalaryPayDialog(employee: _employee, initialPaymentDate: fixed)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(Formatters.date(isoDate(fixed))),
        findsOneWidget,
        reason: 'the caller-supplied date must drive the payment-date label',
      );
      expect(
        find.text(Formatters.date(isoDate(DateTime.now()))),
        findsNothing,
        reason:
            'the machine date must not leak into an audit capture; if this '
            'fires on the fixed date itself the pin is not date-independent',
      );
    },
  );
}
