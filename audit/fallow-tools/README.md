# fallow verification tools

Reproducible methodology behind `audit/fallow-verification-2026-10-20.md`.

These scripts re-verify fallow's findings with stricter rules than fallow applies, because
fallow's two largest false-positive classes both come from *name* matching rather than *module*
matching:

- it cannot see property access on a default-imported namespace, so every
  `export default { handler }` route module looks like dead code;
- it cannot resolve the owning class when a file uses `export default <ClassName>;`, and it does
  not track static-method calls at all.

| Script | What it does | Writes |
|---|---|---|
| `strict-verify.mjs` | Module-scoped re-verification of every `unused-export` / `unused-type` / `unused-enum-member` finding. Resolves each import site to the module it actually names, so a symbol consumed through a *different* module's identically-named export is not counted as a consumer. | `strict-verdicts.json` |
| `class-member-check.mjs` | Owner-scoped re-verification of every `unused-class-member` finding. A member of class `C` counts as used only via `C.member`, `C['member']` or `this.member` inside `C` — an identically-named method on another class is not a consumer. | `class-member-verdicts.json` |
| `verdict.mjs` | The first-pass verifier, kept because it classifies the *kind* of redundancy (`REDUNDANT-EXPORT` vs `CONFIRMED-DEAD`) that `strict-verify.mjs` collapses. | `verdicts.json` |
| `detail.mjs` | Prints the consumer evidence for one finding: `node detail.mjs <category> <symbol>`. | — |

The committed gate baselines live in `audit/fallow-baselines/` (not here) — this directory is
excluded from fallow's own analysis via `ignorePatterns` in `.fallowrc.json`.

## Running them

All three verifiers read the same analysis snapshot. Generate it first:

```bash
npx --yes fallow@3.34.1 --format json > audit/fallow-tools/snapshot.json
node audit/fallow-tools/strict-verify.mjs
node audit/fallow-tools/class-member-check.mjs
node audit/fallow-tools/verdict.mjs
```

`snapshot.json` is regenerable and is git-ignored.

The analyzer version is pinned: the baselines are only comparable against the analyzer that
produced them.
