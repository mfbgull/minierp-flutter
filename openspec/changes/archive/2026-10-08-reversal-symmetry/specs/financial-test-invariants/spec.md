# financial-test-invariants (Delta)

## ADDED Requirements

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