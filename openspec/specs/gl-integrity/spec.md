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
