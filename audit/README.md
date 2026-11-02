# Audit workspace

Live documents used by development and CI:

- `DECISIONS.md` — product calls and open decisions (referenced by `AGENTS.md`).
- `FINDINGS-STATUS.md` — current status of every audit finding.
- `fallow-remediation-2026-10-26.md` — active remediation ledger and evidence.
- `fallow-baselines/` — committed Fallow baselines loaded by `.fallowrc.json`
  and the CI audit gate. Do not remove or regenerate without a deliberate
  re-baseline.
- `fallow-tools/` — helper scripts and captured Fallow snapshots referenced by
  the remediation ledgers.

`archive/` holds historical investigation reports, dated audit packages and
patches. They are kept for reference and are not part of the development or
CI workflow. Generated evidence (screenshots, `.omo` session artifacts) was
moved out of git on 2026-11-02 — see `archive/README.md` for the backup.
