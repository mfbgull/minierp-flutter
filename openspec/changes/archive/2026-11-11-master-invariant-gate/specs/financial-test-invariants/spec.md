## ADDED Requirements

### Requirement: Master invariant assertion covers inventory

The suite SHALL provide a single canonical master assertion that checks the
accounting invariants **A–E and H**, including invariant H (GL inventory 1200
against stock-batch value). A caller of the master SHALL NOT be able to receive
a pass while any of A–E or H is violated.

H is in scope specifically because it was previously unchecked by the master, and
an unchecked H is how a clean-data double-post of inventory reached a fully
green suite.

The master SHALL compose the existing specialized collectors. It SHALL NOT
re-implement their comparison logic, and it SHALL NOT weaken, skip, or
conditionally bypass any collector it does assert.

The mapping from letter to collector is fixed and SHALL be documented in the
helper's header comment so it is verifiable by reading one file:

| | invariant | collector | in master |
|---|---|---|---|
| A | GL balance, globally and per reference group | `glImbalances` | yes |
| B | customer subledger vs `customer_ledger` | `customerArImbalances` | yes |
| C | invoice `paid_amount` vs allocations | `customerArImbalances` | yes |
| D | supplier subledger vs `supplier_ledger` | `supplierApImbalances` | yes |
| E | `stock_balances` vs batch quantities | `stockImbalances` | yes |
| F | GL 1100 + 1110 vs customer balances | `arImbalances` | **no — deferred** |
| G | GL 2000 vs supplier balances | `apImbalances` | **no — deferred** |
| H | GL 1200 vs batch + legacy item values | `inventoryImbalances` | yes |
| I | GL cash vs operational cash flows | `cashImbalances` | **no — deferred** |

A returns a two-field object rather than `Violation[]`, so the master asserts
its `groups`/`totalDiff` pair separately.

#### Scenario: Planted inventory violation fails the master assertion

- **WHEN** a balanced but incorrect inventory posting is added to a clean database — a journal entry that debits an account other than 1200 and credits 1200, leaving every journal_lines reference group internally balanced and leaving the double-entry invariant intact
- **THEN** the master assertion fails, and the failure identifies invariant H with a non-zero signed gap between GL 1200 and batch value

#### Scenario: Balanced-but-wrong drift is still caught

- **WHEN** the planted drift is such that no individual journal entry is unbalanced and no per-reference group fails
- **THEN** the master assertion still fails, because invariant H compares the aggregate GL inventory account against operational batch value rather than checking entry-level balance

#### Scenario: Clean state passes the complete master assertion

- **WHEN** the master assertion is invoked on a freshly migrated database with no transactions, and again after a lifecycle of balanced transactions
- **THEN** it passes at every checkpoint

### Requirement: Deferred invariants are named, never silently omitted

The master SHALL NOT be documented as asserting an invariant it does not check.
Any invariant the master omits SHALL appear in the helper's header map marked as
deferred, with a pointer to the finding that blocks it.

A deferred invariant SHALL be recorded as sequenced follow-up work naming the
condition that unblocks it, so the omission reads as a decision rather than an
oversight.

The reason for deferring SHALL be that the invariant currently **fails**, not
that its assertion is inconvenient. An invariant excluded merely because its
assertion is inconvenient SHALL be treated as a defect in the exclusion.

#### Scenario: Header states what the master actually checks

- **WHEN** the helper's header comment is read
- **THEN** it names the collector behind each of the nine letters, marks which the master asserts, and marks which are deferred with a reference to the blocking finding

#### Scenario: Function docstring agrees with the header

- **WHEN** the docstring on `expectAllInvariantsHold` is read
- **THEN** it states the same set the header marks as asserted, and does not claim to assert all nine

#### Scenario: A deferred invariant is traceable to a finding

- **WHEN** a reader finds an invariant marked deferred in the header
- **THEN** a reference is present identifying what blocks it, so the omission is traceable to a finding rather than looking like an oversight

### Requirement: Asserting an invariant in the master requires proving the master reaches it

For each invariant the master asserts, the suite SHALL contain a test that fails
when that assertion is removed from the master. A master assertion with no such
test is unproven and SHALL NOT be treated as covered.

This applies to every invariant added to the master, including those added after
this change.

#### Scenario: Removing H from the master is detected

- **WHEN** the `inventoryImbalances()` call is removed from the master and the planted-drift test is run
- **THEN** it fails because the master no longer throws on the planted inventory violation

#### Scenario: Adding an invariant without a proof does not count as covered

- **WHEN** F, G or I are added to the master later
- **THEN** a planted-drift test exists for each before the addition is considered guarded, because the file's existing planted-drift test targets `cashImbalances` through the collector directly and does not prove the master reaches it

### Requirement: Specialized invariant collectors remain individually callable

Every collector SHALL remain individually exported and callable for focused
testing, with behaviour unchanged by the existence of the master. The master
SHALL delegate to these collectors rather than duplicating their logic, so that
a fix applied to a collector's comparison is picked up by every caller of both
the collector and the master.

Adding, removing, or re-scoping a collector in the master SHALL NOT remove or
alter the collector's own exported signature.

#### Scenario: Inventory collector is usable on its own

- **WHEN** a test calls `inventoryImbalances()` directly
- **THEN** it returns a `Violation[]` describing the GL-1200-versus-batch
  comparison, independently of the master assertion

#### Scenario: Specialized checks continue to work after the change

- **WHEN** the reconciliation composers that assert F, G and I in isolation
  continue to run alongside the master
- **THEN** both continue to pass on a consistent database and both continue to
  fail on an inconsistent one

#### Scenario: Collector logic is not duplicated

- **WHEN** the master's implementation is reviewed
- **THEN** it contains no inventory, cash, receivable or payable comparison of
  its own, and delegates each invariant to its named collector
