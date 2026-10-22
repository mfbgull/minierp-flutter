# MiniERP

First and Most important rule. Always call me or say my name Gull before every conersation or reply. Most important rule do not by pass this.

Flutter desktop client + Node/Express/SQLite backend in one repo.

- **Client** (repo root): Flutter, Riverpod for state, Dio for HTTP, go_router for
  routing, Pluto-Grid for desktop lists.
- **Server** (`server/`): Node, Express, TypeScript, better-sqlite3, layered —
  routes → controllers → models → `config/database.ts`.

---

## Dummy historical data

For non-production test/dummy records only, treat existing accounting gaps as known legacy noise. Do not repair or repeatedly re-audit them unless explicitly requested. They are not implementation blockers. However, do not weaken integrity checks or tests. Instead, isolate legacy gaps using clean fixtures, fresh test databases, or an explicit allowlist. Ensure all new transactions satisfy accounting invariants and add regression tests. If a gap can be reproduced by current logic, or if any record may be real, stop and investigate.

## Check before you finish

There is no `package.json` at the repo root; each side has its own commands.

```bash
scripts/check.sh --quick    # typecheck + lint + analyze, fast
scripts/check.sh            # everything CI runs (two suites, ~10 min each)
```

Individually:

| Where | Command |
|---|---|
| `server/` | `npm run typecheck` |
| `server/` | `npm run lint` |
| `server/` | `npm test` |
| root | `flutter analyze` |
| root | `flutter test` |
| root | `node scripts/l10n-drift.js` |

These are exactly the gates `.github/workflows/ci.yml` runs. Changing one means
changing both — a local check that passes while CI fails teaches you to ignore it.

A green build is not a verified change. For anything touching an interface, exercise it
the way the user will: a mounted route, a real POST body, a widget driven by taps.

### Risk-based test execution

Do not run the full test suites after every fix. Use incremental, risk-based testing
without compromising regression coverage.

- **After each fix:** Run the directly affected tests and relevant regression tests.
  Follow the dependency path to include tests for affected callers and consumers.
- **Shared or critical logic:** For changes involving accounting, GL, payments,
  inventory, FIFO/FEFO, stock batches, database transactions, or reversals, run
  relevant dependent-module tests and the accounting invariants A–J.
- **Static checks:** Run typecheck, lint, analyze, and l10n drift checks as relevant
  to the changed files. Use `scripts/check.sh --quick` at suitable checkpoints.
- **Before a commit:** Ensure affected tests and relevant static checks pass.
  A focused commit does not require both complete test suites every time.
- **At the end of a completed task or implementation phase:** Run the full suite
  for each affected side. Run `scripts/check.sh` when both sides or their shared
  API contracts are affected, or when preparing a release or final CI verification.
- **Unchanged side:** Do not rerun its full suite solely out of habit. Server-only
  changes do not automatically require all Flutter tests, and vice versa, unless
  behavior, API contracts, or dependencies could affect that side.
- **Failures:** Investigate targeted failures before expanding the test scope.
  Never weaken, delete, or bypass valid tests to make a change appear green.
- **Report:** State which tests and checks ran, their results, and which full suites
  were intentionally not rerun. Do not claim full-suite verification unless it ran.

The CI gates remain unchanged. This policy controls *when* to run them locally,
not what CI requires.

---

## Read before you edit

- [`CODING_STANDARDS.md`](CODING_STANDARDS.md) — the rules the reviewer enforces:
  typing, SQL/GL integrity, error handling, UI, performance.
- [`docs/`](docs/) — `REVERSAL-RULES.md` (accounting void/reversal invariants),
  `API.md`, `DATABASE.md`, `DESIGN.md`, `audit-coverage-ledger.md`, `bugs.md`.
- [`audit/FINDINGS-STATUS.md`](audit/FINDINGS-STATUS.md) — live status of every audit
  finding (GREEN / PARTIAL / OPEN-DECISION). Read this instead of re-deriving status.
- [`audit/DECISIONS.md`](audit/DECISIONS.md) — why a decision was taken, and which
  ones are waiting on the user. A new product call goes here, not into a guess.
- [`server/STRICT_NULL_CHECKS.md`](server/STRICT_NULL_CHECKS.md) — null-safety history
  on the server.

---

## Invariants

These are the ones worth having in every agent's window. Everything else lives in
`CODING_STANDARDS.md`.

- **Accounting is the expensive domain.** Journal entries go through the shared
  accounting service and must balance; stock batches and GL must agree. Read
  `docs/REVERSAL-RULES.md` before touching any void or reversal path.
- **Schema changes ship a migration**, registered in `server/src/config/database.ts`.
- **Prepared statements only.** No SQL built by string concatenation.
- **No secrets in logs or error responses**, and no stack traces to clients.
- **Fix the source, not the symptom.** A guard that fixes one caller while another still
  produces the bad data is a half-fix — move the invariant up a layer.
- **Red before green.** Write the failing test first, watch it fail, then fix. A test
  written after the fix proves nothing about whether it would have caught the bug.

## Product vs architecture

You decide product, workflow, UX and business rules. The agent decides architecture,
API shape, schema, validation, security and error handling — pick the simplest option
and say what you picked rather than asking. A genuinely open product call (one with
real trade-offs you must own) is written up in `audit/DECISIONS.md` and left marked
OPEN-DECISION, not guessed.

## Fallow CRAP cleanup status (2026-10-22)

Plan: [`.omo/plans/fallow-crap-cleanup-2026-10-22.md`](.omo/plans/fallow-crap-cleanup-2026-10-22.md).

- **Phases 1–4 complete** (`8bb623b9`, `1711b2a1`, `0e245f40`): all eight D.1b
  findings are below CRAP 30. Added 37 targeted tests across seven suites; extracted
  `toSalaryHistoryRow`, `upsertCashReconciliationEntries`,
  `postInventoryReconciliationEntry`, `verifySnapshotAt`, and the archive-guard parser.
- **Final verification (Phase 4):** 176/176 suites and 1534/1534 tests passed (exit 0);
  `scripts/check.sh --quick` passed; the final Fallow scan is structural 0, duplicate
  groups 4, health 145, with all eight D.1b targets absent. The Phase 3 commit audit and
  the working-tree gate both exit 0. Ledger D.1b and E are updated.
- **Remaining:** the 64 original CRAP-only findings and 72 pre-existing newly reported
  findings remain documented but were out of scope for this cleanup.
