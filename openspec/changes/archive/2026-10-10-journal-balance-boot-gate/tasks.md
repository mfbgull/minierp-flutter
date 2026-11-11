# Journal Balance Boot Gate — Tasks

Documentation-only change. The behaviour already ships; this records it in the
specification so it is discoverable as a guarantee rather than looking like
removable scaffolding.

## Phase 1 — Confirm the behaviour is what will be documented

- [x] 1.1 Confirm `assertJournalEntriesBalance` exists and is wired into boot.
      **done-when:** it is defined and invoked in `src/config/database.ts`, after
      the migration sequence and before `export default db`.
- [x] 1.2 Confirm its placement is after table creation.
      **done-when:** placed after the 4150 boot guard. Placed earlier it queried
      `journal_lines` before `fn.initializeDatabase` created it and every first
      boot exited 1 — caught by running the suite, not by reading the diff.
- [x] 1.3 Confirm it compares in integer minor units and ignores fully voided groups.
      **done-when:** `CAST(ROUND(x * 100) AS INTEGER)` with `WHERE voided = 0`.
- [x] 1.4 Confirm the shipped behaviour is covered by behavioural tests.
      **done-when:** 5 tests in `dbIntegrityConstraints.test.ts`; mutation M12
      (neutralising the `HAVING` clause) fails 3 of them.

## Phase 2 — Check the new requirement does not duplicate an existing one

- [x] 2.1 Read `gl-integrity` and list its requirements.
      **done-when:** three exist — soft invoice deletion, one-time damage
      reconciliation, scheduled reference-integrity checking.
- [x] 2.2 Confirm the scheduled check does not already cover this.
      **done-when:** it groups by `(reference_type, reference_id)` on a schedule
      and logs findings; this groups by `journal_entry_id` at boot and aborts.
      An entry can foot per document yet be split across two entry ids, so both
      are required. The difference is stated in the requirement, not left implicit.
- [x] 2.3 Confirm the requirement is scoped as DETECTION, so the spec cannot be
      read as claiming DB-002 is closed.
      **done-when:** the requirement states raw SQL is caught on the NEXT boot,
      not at write time, and points at BUG-005. The ledger row stays `planned`.

## Phase 3 — Record it

- [x] 3.1 Add the requirement and five scenarios to `gl-integrity`.
      **done-when:** covers a balanced boot, an unbalanced entry naming itself
      and its drift, a half-voided entry, a fully voided entry, and the
      float-artefact case.
- [x] 3.2 `openspec validate journal-balance-boot-gate` passes.
      **done-when:** "Change 'journal-balance-boot-gate' is valid".
- [x] 3.3 Archive through the gate.
      **done-when:** every box above is ticked and the guard permits archiving.

## Phase 4 — Verification

- [x] 4.1 `openspec validate --all` — 0 failed.
- [x] 4.2 Archive-guard test suite still green.
- [x] 4.3 No source change: the tree's server code is untouched by this change.

## Out of scope

Write-time prevention for DB-002. Three designs were built and reverted; the
fourth (the seal) is blocked on the duplicated migration lists across 24 test
files. See `docs/bugs.md` BUG-005 and `docs/test-migration-order.ts`.