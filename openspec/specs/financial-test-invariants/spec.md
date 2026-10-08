# Spec: financial-test-invariants

## Purpose

Locks in the financial-correctness guarantees of the audit-remediation work with
regression tests covering double-entry balance, transaction atomicity, boot
idempotency, migration replay, and money-path coverage gaps.
## Requirements
### Requirement: Double-entry invariant is regression-tested
The test suite SHALL assert after every mutating scenario that SUM(debit) = SUM(credit) over non-voided journal_lines globally and grouped per (reference_type, reference_id).

#### Scenario: Invoice workflow keeps the ledger balanced
- **WHEN** create → partial pay → edit → delete flows execute in tests
- **THEN** the global and per-document balance assertions pass at each step

### Requirement: Transaction atomicity is regression-tested
Tests SHALL force a mid-transaction failure (e.g. insufficient stock on a later invoice line) and assert complete rollback: no invoice, items, stock movements, ledger entry or journal lines persist.

#### Scenario: Failed multi-line invoice writes nothing
- **WHEN** line 2 of a 3-line invoice fails validation
- **THEN** zero rows from that operation exist in any affected table

### Requirement: Boot idempotency is regression-tested
The suite SHALL snapshot row hashes of all business tables, re-run the boot sequence against the same database, and assert zero row changes.

#### Scenario: Restart is a no-op
- **WHEN** the boot sequence runs twice against one database
- **THEN** no business-table row differs between snapshots

### Requirement: Migration replay is regression-tested
The suite SHALL apply the full migration set to a fresh in-memory database twice and assert identical schemas and zero errors, catching dead guards and broken SQL.

#### Scenario: Replay is deterministic
- **WHEN** migrations apply twice to :memory:
- **THEN** sqlite_master content is identical after each run and no migration errors

### Requirement: Money-path coverage gaps are closed
The suite SHALL cover: invoice edit after payment (totals/status/stock/GL), invoice delete leaving no orphaned journal_lines or ledger rows plus an audit row, customer-side partial payment asserting payment_allocations rows, and concurrent invoice creation producing unique invoice numbers with correct stock.

#### Scenario: Edit-after-payment stays consistent
- **WHEN** a paid invoice is edited in tests
- **THEN** paid_amount, balance_amount, status, stock levels and GL postings are all correct

#### Scenario: Concurrent creation serializes numbers
- **WHEN** two invoice creations race
- **THEN** invoice numbers are unique and final stock equals expected

### Requirement: A GL assertion checks both sides of the account
A test helper that returns debit and credit totals for an account SHALL have
every caller assert on **both**. An assertion on one side alone SHALL NOT be
accepted as evidence that the account is clear.

A net figure (`SUM(debit) - SUM(credit)`) SHALL NOT be used to prove an account
is zero, because a debit-normal asset that has flipped to a credit balance nets
to a plausible-looking number. `glTotals` in `supplierlessPurchase.test.ts`
returns both columns separately for this reason.

#### Scenario: The single-sided guard passes on defective books
- **WHEN** a purchase void leaves GL 1200 at `debit 0, credit 500`
- **THEN** an assertion of `glTotals('1200').debit ≈ 0` passes
- **AND** an assertion of `credit ≈ 0` fails

#### Scenario: Both sides are asserted after a void
- **WHEN** any test voids a document that posted to an inventory or payable
  account
- **THEN** it asserts that account's debit **and** credit are zero

### Requirement: A void path is covered by the invariant gate
Every code path that voids a financial document SHALL have at least one test that
calls `expectAllInvariantsHold` after the void. The gate is the only check that
compares GL inventory against operational batch value, so a void asserted solely
on its own reference type can miss an unrelated second posting.

Measured: after the purchase-void defect, invariant H reported
`glBalance 500, batchVal 0, legacyVal 0, diff 500`. The gate would have caught
it. It was not called on that path — `purchaseVoid.test.ts` contains no
`expectAllInvariantsHold` and never exercised a successful void.

#### Scenario: The gate is reached on the purchase-void path
- **WHEN** a purchase is created and voided in a test
- **THEN** `expectAllInvariantsHold` is called afterwards and passes

#### Scenario: A global account check accompanies a reference-type check
- **WHEN** a test asserts that a voided document's own GL group is cleared
- **THEN** it also asserts the affected accounts globally, because a second
  posting under a different `reference_type` is otherwise invisible

### Requirement: Void-path unit tests state what they cannot reach
A test that stubs or skips part of a void path SHALL name the suite that really
covers that behaviour, so the gap is recorded rather than assumed closed.

`Purchase.void`'s supplier-ledger reversal is bound to the global database via
`ledgerUtils` and cannot run against an in-memory fixture. `models.test.ts`
covers it, asserting the supplier balance returns to zero after a successful
void. The GL behaviour is covered separately with the ledger call stubbed.

#### Scenario: The named suite exists and passes
- **WHEN** a reader follows the pointer from the stubbed unit test
- **THEN** `models.test.ts` contains a successful-void assertion and the suite
  passes

