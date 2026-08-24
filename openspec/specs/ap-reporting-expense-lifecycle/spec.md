# ap-reporting-expense-lifecycle Specification

## Purpose

See the archived change `financial-audit-p0-remediation` (proposal.md) for the
motivating forensic audit findings (PAY-07, CASH-01..04, EXP-03..05, PUR-03,
PRET-01..06, PAY-04/09/10/11).

## Requirements

### Requirement: AP reports derive from supplier_ledger
Accounts-payable aging and summary reports SHALL be computed from non-voided `supplier_ledger` rows (net debits minus credits per supplier, aged by debit document dates), covering both purchase orders and direct purchases. Reports SHALL declare their basis and SHALL execute without SQL errors against the live schema.

#### Scenario: Fully paid supplier shows zero outstanding
- **WHEN** a supplier's PO debits are fully offset by payment credits
- **THEN** that supplier's aging row totals 0

#### Scenario: Unpaid direct purchase appears
- **WHEN** a 500 direct purchase is recorded with no allocation
- **THEN** the supplier appears with 500 in the current aging bucket and summary totalPayables includes it

#### Scenario: Regression guard against schema drift
- **WHEN** the report integration suite runs against a fresh seeded schema
- **THEN** both report functions execute and match fixture totals (previously both 500'd on nonexistent columns)

### Requirement: Expense lifecycle is a validated state machine
Expense status SHALL be one of {Draft, Submitted, Approved, Paid, Cancelled}, defaulted to Draft on create; client-supplied status on create SHALL be ignored. Transitions follow Draft→Submitted|Cancelled, Submitted→Approved|Cancelled, Approved→Paid|Cancelled, Paid/Cancelled terminal. Transitions into Approved or Paid require `expenses:approve`. Approved/Paid expenses reject field edits except via cancellation. `expense_category` SHALL be validated against `expense_categories` on write. Expense numbers SHALL come from the shared sequence utility inside the creating transaction, with counters seeded from existing maxima; expense deletion routes are removed (cancellation replaces delete).

#### Scenario: New expense starts as Draft
- **WHEN** an expense is created with no status handling by the client
- **THEN** it stores Draft, is excluded from cash flows until submitted/approved, and cannot jump straight to Approved

#### Scenario: Illegal transition refused
- **WHEN** a Paid expense is edited back toward Draft
- **THEN** the request fails 400 naming the transition matrix

#### Scenario: Approval needs permission
- **WHEN** a user without `expenses:approve` moves an expense to Approved
- **THEN** the request fails 403

#### Scenario: Unknown category rejected
- **WHEN** an expense is created with category 'Utilites' (not in expense_categories)
- **THEN** creation fails 400 listing valid categories

#### Scenario: Numbering survives concurrent creates
- **WHEN** two expenses for the same month are created back-to-back
- **THEN** they receive distinct sequential numbers from the settings counter, and after deleting nothing (deletion impossible) numbers never repeat
