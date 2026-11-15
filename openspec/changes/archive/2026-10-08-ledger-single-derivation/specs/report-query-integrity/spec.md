# report-query-integrity (Delta)

## ADDED Requirements

### Requirement: An as-of report filters on the as-of date on both sides
A report parameterised by an as-of date SHALL apply that date to both the debit
side and the credit side of every net it computes. Filtering one side only lets a
future-dated credit silently reduce an earlier figure.

#### Scenario: A future purchase is excluded from a past report
- **WHEN** a purchase of 500 dated 2031-01-01 is on the books
- **THEN** `getAPAgingReport('2026-01-01')` excludes it
- **AND** a report as of 2031 includes it

#### Scenario: A future credit does not shrink an earlier figure
- **WHEN** a purchase of 500 dated 2026-01-05 has a 200 credit dated 2027-06-01
- **THEN** AP as of 2026-12-31 reports 500

### Requirement: Soft-deleted rows are excluded by the shared predicate, not by each caller
`AR_OUTSTANDING` SHALL include `deleted_at IS NULL`. `deleteInvoice` is a soft
delete: the row survives with `status = 'Deleted'` and its `balance_amount`
intact, so a status-only filter counted a deleted invoice as live AR.

Membership in the shared predicate is the defence. Adding the condition to
individual call sites would leave the next new AR surface unprotected.

#### Scenario: A deleted invoice is not outstanding AR
- **WHEN** a 400 invoice is soft-deleted and a 100 invoice remains
- **THEN** AR aging, top debtors and the receivables summary all report 100

#### Scenario: The predicate itself is asserted
- **WHEN** a test inspects `AR_OUTSTANDING`
- **THEN** it contains `deleted_at IS NULL`, `balance_amount > 0`, and the
      Cancelled/Draft exclusion

### Requirement: An aging report's buckets foot to its total
Every balance included in an aging report's total SHALL be assigned to exactly one
bucket, so the buckets sum to the total.

A NULL `due_date` yields NULL from `julianday()`, so every comparison is NULL and
the row falls to `ELSE 0`: it appeared in the total and in no bucket. Such a row
is not yet due and belongs in `current`.

#### Scenario: An invoice with no due date still ages
- **WHEN** an invoice of 175 has `due_date IS NULL`
- **THEN** current + 1–30 + 31–60 + 61–90 + over-90 equals the total outstanding

#### Scenario: Mixed dated and undated invoices foot
- **WHEN** a report mixes overdue, not-yet-due and undated invoices
- **THEN** the buckets still sum to the total