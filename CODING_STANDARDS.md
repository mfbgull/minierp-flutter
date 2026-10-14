# Coding standards

Read at **review** time, not implementation time. The implementation agent carries
exploration, writing and debugging pressure; the reviewer receives a diff and is the
right place to enforce these.

Each rule says what to do and how it is checked. Rules a guardrail can check are marked
`[check]` — fix the check rather than restating the rule in prose.

---

## 1. Type safety

**Server (TypeScript)**

- No `any`, `as any`, or `@ts-ignore`. Prefer a narrow type or a type predicate.
- API responses get an explicit interface; shared models live in `src/types`.
- `[check]` `npm run typecheck` (with `strictNullChecks` on).

**Client (Flutter/Dart)**

- Casts are idiomatic here: `as`, `as dynamic`, and `!` are normal in widget tests
  (see `test/widget_test.dart` reading PlutoGrid's internal `stateManager`). Do not
  blanket-ban `as` — ban the *unjustified* one: every cast should sit next to the
  reason it is safe, or be replaced by a pattern match (`switch` on a sealed type).
- `flutter analyze` must stay at zero issues. That is the whole gate; there is no
  separate lint config to relax.

## 2. Database

- Prepared statements only. A value never reaches SQL through string concatenation.
- Every schema change ships a migration in `server/src/migrations/` and registers it in
  `server/src/config/database.ts`. A model change without its migration is incomplete.
- Writes that touch more than one table go in a transaction.
- `[check]` `npm run typecheck`; migrations are exercised by the suite booting a fresh DB.

## 3. Error handling

**Server:** controllers wrap in try/catch and return structured JSON
(`{ error: string }`). Never leak a stack trace to the client. A *client* mistake is a
4xx with an actionable message; reserve 500 for genuine server faults. When you find a
client error being reported as an opaque 500, promote it — see
`productionController.ts` (BOM/primary-output mismatch) for the pattern.

**Client:** async work is try/caught, failures surface as a toast, and every async
action has a loading state. No silent `catch {}` without a user-visible or logged path.

## 4. SQL and GL integrity (accounting-specific)

This is the domain where mistakes are expensive, so the reviewer should check it first.

- A journal entry is only valid if it balances; postings go through the shared
  accounting service, never hand-rolled `INSERT`s into `journal_lines`.
- Read `docs/REVERSAL-RULES.md` before touching any void/reversal path.
- Stock and GL must agree: a batch's value equals what was debited to inventory.
- Prefer fixing a rule at its **source** over filtering downstream. A guard that fixes
  one caller while another caller still produces the bad data is a half-fix — check
  whether the invariant belongs one layer up (e.g. don't stamp a meaningless expiry on
  a batch; don't just exclude it from the sweep).

## 5. Code shape

- Minimal diffs: change what the request needs, leave surrounding code alone. Prefer
  editing existing files over creating new ones.
- No full-file rewrites when a targeted edit will do.
- Extract duplicated logic only when you can name the shared concept; otherwise leave
  the near-duplicates.
- `[check]` `npm run lint` (server), `flutter analyze` (client).

## 6. UI

- Lists on desktop use Pluto-Grid. Do not introduce a second table/list system.
- New user-facing strings go in **both** `lib/l10n/en.arb` and `lib/l10n/ur.arb`.
  `[check]` `node scripts/l10n-drift.js` fails on orphaned keys and on the fallback gap
  regressing past its cap.

## 7. Performance

- No N+1 queries: batch reads, or push the work into SQL.
- Use indexes for any new filter column; add one in the migration with the column.
- On the client, avoid rebuilding heavy widgets on unrelated state changes; hoist
  providers so a form keystroke does not re-render a grid.

## 8. Product vs architecture

The user decides product, workflow, UX and business rules. The agent decides
architecture, API shape, schema, validation, security and error handling. Do not ask the
user to choose between implementation patterns (repository vs service layer, auth
strategy, controller structure) — pick the simplest one and say what you picked.

When a *product* decision is genuinely required (something with real trade-offs the user
must own), write it up in `audit/DECISIONS.md` rather than guessing, and mark the
finding accordingly in `audit/FINDINGS-STATUS.md`.
