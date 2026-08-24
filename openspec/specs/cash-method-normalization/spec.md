# cash-method-normalization Specification

## Purpose

See the archived change `financial-audit-p0-remediation` (proposal.md) for the
motivating forensic audit findings (PAY-07, CASH-01..04, EXP-03..05, PUR-03,
PRET-01..06, PAY-04/09/10/11).

## Requirements

### Requirement: Purchases drain cash only through payments
The cash-position calculation SHALL NOT include direct-purchase totals as a till outflow. Cash outflow for purchased goods SHALL be derived solely from supplier payments (and other recorded payment rows), so an unpaid purchase never moves expected cash and a paid purchase moves it exactly once.

#### Scenario: Unpaid purchase does not move the till
- **WHEN** a purchase of 500 is recorded and no supplier payment is allocated to it
- **THEN** expected cash before and after the purchase differs by 0

#### Scenario: Paid purchase drains the till exactly once
- **WHEN** the 500 purchase is settled by a 500 cash supplier payment
- **THEN** expected cash decreases by exactly 500, not 1000

#### Scenario: Drill-down matches aggregate
- **WHEN** the transaction drill-down lists cash outflows for a period containing a paid purchase
- **THEN** the purchase appears only via its supplier payment row and no separate 'purchase' entry exists

### Requirement: Unknown payment methods are surfaced, not absorbed
Payment-method normalization SHALL use an explicit whitelist (cash, easypaisa, jazzcash, upaisa; bank-like values map to bank; credit maps to no money movement). Any unrecognized value SHALL land in a distinct `unclassified` bucket that the reconciliation report displays as its own flagged row, instead of being counted as bank.

#### Scenario: Typo method becomes visible
- **WHEN** a payment is stored with method 'Cash on delivery'
- **THEN** reconciliation shows it under `unclassified` with a warning flag and bank total excludes it

#### Scenario: Invalid method rejected at write time
- **WHEN** a payment create/update supplies a method outside whitelist ∪ {'credit'}
- **THEN** the request fails 400 listing valid methods and no payment row is written

### Requirement: Reconciliation saves require write permission
Saving a cash reconciliation SHALL require `reports:create` permission. Reading reconciliation reports remains `reports:read`.

#### Scenario: Read-only user cannot overwrite a signed count
- **WHEN** a user holding only `reports:read` posts to the save endpoint
- **THEN** the request fails 403 and the stored reconciliation for that date/account is unchanged

### Requirement: Payment methods default to Cash
`payments.payment_method` and `expenses.payment_method` SHALL be NOT NULL DEFAULT 'Cash'; blank or NULL legacy values are migrated to 'Cash'.

#### Scenario: Omitted method still reaches the till
- **WHEN** a payment is created without payment_method
- **THEN** the row stores 'Cash' and appears in expected cash
