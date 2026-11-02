# audit/archive

Historical investigation reports and dated audit documents. Markdown reports
stay tracked in git.

Run artifacts were removed from git on 2026-11-02 to shrink the repository:
`.omo/` (agent session evidence, 88 MB), `screenshots/` (11 MB), `baseline/`
and `.codegraph/`. They are machine-generated and not inputs to any check.

Backup: `../../minierp-artifact-archives/minierp-audit-archive-artifacts-2026-11-02.zip`
(24 MB compressed, 432 files). Extract any subfolder back into this directory
to restore it. These paths are now gitignored so re-added artifacts stay out.
