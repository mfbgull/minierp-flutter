# Unapplied cash plan verification — 2026-10-16

The corrected implementation plan is ready for user review. No feature code,
registered migration, API route, or production data was changed. Stages 0–E
still require the approvals described in the plan.

## Artifacts

- Plan: `docs/superpowers/plans/2026-10-16-unapplied-customer-payments.md`.
- Reproducible document exercises:
  `docs/superpowers/verification/unapplied-customer-payments.cjs`.
- Design baseline: `docs/superpowers/specs/2026-10-16-unapplied-customer-payments-design.md`, rev 28.

Run from the repository root:

```bash
node docs/superpowers/verification/unapplied-customer-payments.cjs
node --check docs/superpowers/verification/unapplied-customer-payments.cjs
git diff --check
```

Requires the existing server dependencies. The verifier reads production schema
metadata and chart-of-accounts reference rows through an explicitly read-only
connection, then exercises SQLite in memory or in disposable temporary files.
It does not copy production business records or apply any SQL to the live file.

## Red evidence

Before correction, a temporary verifier executed the original plan's historical
seed against the actual production schema reconstructed in memory. It failed
with `NOT NULL constraint failed: customer_ledger.balance`. The subsequent
ID, refund, backfill, and reconciliation assertions also failed because the
fixture could not populate. Independently measured path resolution confirmed
that four parent levels select the repository-root database; three select the
canonical server database.

Inspection also established these execution defects in the previous plan:

- Refund amounts were inserted into credit while debit was zero.
- Historical customer IDs were generated rather than explicitly preserved.
- Backfill tests seeded history after schema cloning but never ran a backfill.
- A customer-level total was asserted against one of four source rows.
- Migration registration was represented by a standalone `path.join` expression;
  subsequent stages appended SQL to the same already-recorded migration.
- The proposed invariant collector aggregated L instead of checking each source,
  ignored refund consumptions, and treated negative refund payments as receipts
  for N.
- The negative-customer receipt test returned early without an assertion when
  the fixture omitted the negative customer.
- API capacity failures were mapped to 422 despite the spec requiring 409.

The handoff's receipt-date example had already gained a `today` declaration by
commit `362398f1`. The corrected plan removes the duplicated implementation and
requires a single resolved receipt date for payment, journal, and period checks.

## Green evidence

The final document verifier completed with **17 passed, 0 failed**:

1. All proposed TypeScript snippets pass strict semantic type checking with the
   installed TypeScript compiler and server database types; no emitted files.
2. Guard path resolves exactly to `server/database/erp.db`.
3. The wrapped native SQLite constructor rejects canonical and relative writes.
4. File and parent-directory symlink aliases are refused.
5. A hardlink alias is refused using a disposable canonical file, without adding
   links to the real database.
6. Real inserts and reads succeed for memory and disposable file databases.
7. Read-only opens are allowed; a disposable read-only database rejects writes.
   No write statement was attempted on the real canonical connection.
8. Historical seed SQL executes against the actual schema, including the required
   ledger balance column.
9. Explicit customer IDs and 13 RETURN/two CREDIT_OFFSET row counts match.
10. Refund debits total 4450 and refund credits total zero.
11. FIFO yields 13 sources: 8550.20 credited, 1800 consumed, 6750.20 remaining,
    zero refundable cash; no per-source overdraw and no foreign-key violations.
    Customer 15 totals 2300/1800/500 across its four sources.
12. Capacity preflight rejects consumption without any supporting return.
13. Query-only reconciliation yields 250.20, 100, 800, 1200, -50 for customers
    1, 12, 13, 14, 15 respectively, with all stored-balance disagreements visible.
14. Voided/reversed distractors change neither reconciliation nor backfill count.
15. Feature seeds, generated remaining, apply-then-refund drain, and the four
    source CHECK bounds behave as specified against the spec's DDL.
16. The coverage matrix includes every spec test ID from 1 through 35.
17. Main database and existing WAL/SHM fingerprints match before and after the
    entire verifier run.

`node --check` and `git diff --check` also passed. A post-edit LSP diagnostic
hook timed out once; the edit was applied, and the executable document checks
subsequently passed. No LSP-clean claim is made.

Main-file SHA-256:

```text
63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f
```

## Limits and approval gate

These exercises validate the plan's included snippets against real SQLite and
schema metadata. They do not validate a complete registered migration, migration
runner replay/rollback, global Jest mock installation, mounted endpoints, shared
accounting service transactions, or the proposed full-command sentinel runner.
Those components do not exist yet and have explicit implementation acceptance
tests in the plan.

The coverage map checks that all 35 test IDs are assigned; it does not claim
that those feature tests have been implemented or passed. No historical A–J
baseline was re-executed here; the synthetic fixture is deliberately not a full
historical GL reconstruction. The Rs 1,800 discrepancy remains an inherited
historical baseline to verify on an isolated historical backup during authorized
implementation.

Server and Flutter full suites, server lint/typecheck, Flutter analysis and l10n
checks were intentionally not run: only planning/document-verification artifacts
changed. The verifier separately type-checks the included TypeScript snippets.
No commits or external messages were made during this correction phase.

Next required user action: review and approve the corrected plan before Stage 0.
Stage C retains its separate evidence-review gate; historical activation and
repair remain outside this feature's authorization.
