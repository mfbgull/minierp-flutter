# gl-integrity (Delta)

## ADDED Requirements

### Requirement: Every journal entry is asserted to balance at boot
Before the HTTP server listens, the application SHALL assert that each
`journal_entry_id` group of live journal lines satisfies
`SUM(debit) = SUM(credit)`, and SHALL abort the boot if any group does not.

Comparison SHALL be made in integer minor units, matching the application-level
invariant in `accountingService`, so a float-summation artefact cannot fail a
boot. Fully voided groups SHALL be ignored; a partially voided group SHALL be
checked on its live lines and therefore reported as unbalanced.

The assertion is deliberately scoped to `journal_entry_id` — the accounting
entry — rather than the document reference. The existing requirement in this
spec checks `(reference_type, reference_id)` on a schedule; an entry can foot
per document yet be split across two entry ids, or the reverse. The entry id is
the unit that must balance.

This is DETECTION, not prevention. SQLite has no cross-row `CHECK` and no
`DEFERRABLE` constraint, and a row-level trigger cannot be used because four
legitimate operations leave a group momentarily unbalanced mid-statement
(per-line insert loop, bulk void, bulk un-void, per-row orphan void). Raw SQL
that writes an unbalanced entry is therefore caught on the NEXT boot, not at
write time. Closing write-time prevention is tracked in `docs/bugs.md` BUG-005.

#### Scenario: A balanced ledger boots normally
- **WHEN** every journal entry's live lines foot to zero
- **THEN** the assertion passes and the server starts

#### Scenario: An unbalanced entry aborts the boot and names it
- **WHEN** an entry's live lines have unequal debits and credits
- **THEN** the boot fails before HTTP listen
- **AND** the message names the offending `journal_entry_id` and the size of the difference

#### Scenario: A half-voided entry is reported
- **WHEN** an entry's lines were balanced and only some were voided
- **THEN** the remaining live lines no longer foot
- **AND** the assertion reports that entry as unbalanced

#### Scenario: A fully voided entry is ignored
- **WHEN** every line of an entry is voided
- **THEN** the group has no live lines and is not reported

#### Scenario: A float-summation artefact does not fail the boot
- **WHEN** an entry's debits and credits are equal to the cent but differ as
      binary floats
- **THEN** the minor-unit comparison still treats it as balanced
