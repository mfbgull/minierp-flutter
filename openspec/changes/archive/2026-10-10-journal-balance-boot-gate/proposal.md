# Journal Balance Boot Gate — DB-002 detection

## What Changes

Adds one requirement to `gl-integrity`, documenting behaviour that already
ships: `assertJournalEntriesBalance` asserts at boot that every
`journal_entry_id` group of live journal lines sums to zero, and aborts before
HTTP listen if any group does not.

- `openspec/specs/gl-integrity/spec.md` — one added requirement.
- No source change: the behaviour landed in
  `openspec/changes/archive/2026-10-10-db-integrity-constraints`, which was
  archived before this requirement was drafted, so the rule existed only in that
  change's notes and in `docs/bugs.md`.

## Why

The specification is the record of what the system guarantees. A rule that lives
only in a changelog is easy to miss, and the next person to see
`assertJournalEntriesBalance` at boot with no mention of it in the specbook may
reasonably treat it as removable scaffolding.

## Scope — detection only, and why that is not the whole answer

This records the DETECTION half of DB-002. It does not close the finding.

The invariant cannot be enforced at write time in SQLite. There is no cross-row
`CHECK` and no `DEFERRABLE` constraint, and a row-level trigger is unusable
because four legitimate operations leave a group momentarily unbalanced
mid-statement:

- `postEntry` inserts one statement per line;
- `voidJournalLinesByReference` and its un-void sibling flip every line of a
  reference in a single bulk `UPDATE`;
- the orphan reconciler voids rows one at a time;
- the GL-unification backfill repoints `journal_entry_id` one line at a time.

Three prevention designs were built and measured against the suite; all were
reverted, and the measurements are recorded in `docs/bugs.md` BUG-005. A seal
design (seal the entry in one statement the database checks atomically) is sound
in principle but is blocked by a separate defect: 24 test files maintain their
own hand-written migration lists, so no migration that application code depends
on can currently be added. The derivation for fixing that is in
`docs/test-migration-order.ts`.

The ledger row for DB-002 therefore remains `planned`. This spec records what IS
guaranteed, not what is not.

## Grouping note

`gl-integrity` already requires per-`(reference_type, reference_id)` balance
checking on a schedule. This requirement is deliberately different and does not
replace it:

| | existing requirement | this one |
|---|---|---|
| grouping | `(reference_type, reference_id)` — the document | `journal_entry_id` — the accounting entry |
| trigger | scheduled integrity check | boot, before HTTP listen |
| failure | findings logged and surfaced to admins | boot aborts |

An entry can balance per document and still be split across two entry ids, or
vice versa. The entry id is the unit that must foot, so it is checked at the one
moment where nothing else is running.