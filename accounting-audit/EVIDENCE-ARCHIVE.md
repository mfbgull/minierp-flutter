# Evidence archive

`evidence/` held the raw run outputs (logs, coverage JSON, result manifests,
throwaway SQLite databases) cited by `10-verification-results.md`,
`06-report-verification.md`, and the `findings/F-*` reports.

It was removed from git on 2026-11-02 to shrink the repository. The conclusions
and tables in the markdown reports are the authoritative record.

Backup: `../../minierp-artifact-archives/minierp-accounting-audit-evidence-2026-11-02.zip`
(4.8 MB compressed, 768 files). Extract it to this directory as `evidence/`
to resolve any cited artifact.

`run-verification.cjs` recreates `evidence/` on its next run. The directory is
gitignored; new outputs are not committed.
