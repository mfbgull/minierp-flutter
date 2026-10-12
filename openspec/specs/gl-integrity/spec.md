# Spec: gl-integrity

## Purpose

Keeps the general ledger internally consistent: soft deletion of invoices,
reconciliation of pre-existing damage, and continuous reference-integrity
checking.
## Requirements
### Requirement: Invoice deletion is soft
Deleting an invoice SHALL mark it deleted (deleted_at/deleted_by) and void — not remove — its dependent rows: journal lines, customer_ledger entry, stock movements reversal entries, payment allocations and payments; no DELETE statement against invoices, journal_lines or customer_ledger SHALL exist on any API path.

#### Scenario: Deleted invoice leaves queryable GL history
- **WHEN** an invoice with GL postings is deleted
- **THEN** all its journal_lines remain present with voided=1 referencing an intact invoice row, and the trial balance is unchanged by the deletion

### Requirement: Existing GL damage is reconciled
A one-time data-fix migration SHALL void the 12 measured unvoided orphaned `journal_lines` rows (₨685 trial-balance misstatement: AR +420, revenue +420, COGS +265, inventory −265), attach or document the 26 dangling `journal_entry_id` references, and record the reconciliation in the audit trail.

#### Scenario: Trial balance returns to balance after reconciliation
- **WHEN** the data-fix migration runs
- **THEN** zero non-voided journal_lines reference a nonexistent invoice, and SUM(debit) equals SUM(credit) over non-voided rows

### Requirement: Reference integrity is continuously checked
A scheduled integrity check SHALL detect journal_lines whose (reference_type, reference_id) points at a missing document, ledger entries whose document vanished, and per-reference debit/credit imbalance; findings SHALL be logged loudly and surfaced to admins.

#### Scenario: Orphan detection fires
- **WHEN** a journal_line references a deleted/missing document
- **THEN** the scheduled check reports the exact rows within one check cycle

#### Scenario: Per-document double-entry holds
- **WHEN** any mutating workflow completes
- **THEN** grouped by (reference_type, reference_id), SUM(debit) = SUM(credit) across non-voided lines

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

