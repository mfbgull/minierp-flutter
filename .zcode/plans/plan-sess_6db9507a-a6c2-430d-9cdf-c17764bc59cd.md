Fix: Mimosa push-gate blocks all pushes on 10 verified false-positive HIGH findings

ROOT CAUSE (verified)
- Not a git hook. The Mimosa ZCode plugin intercepts Bash `git push`/`git commit` calls, runs a fresh deep scan each time, and denies when any non-advisory HIGH finding exists. `--no-verify` cannot help.
- Current persisted scan: 17 HIGH (10 non-advisory = the actual blockers), 29 MEDIUM advisories (never block). All 10 blockers map to the four verified false-positive clusters.
- Vendor-supported fix: inline `mimosa-ignore` / `mimosa-ignore-file` comments (default-on in the gate's own scan). Gate keeps full strength otherwise.

CHANGES (comments only, except step 2)
1. Add suppression comments with short rationale at the exact flagged sites:
   - server/src/middleware/auth.ts:74 — weak-crypto misfire (HS256 is explicitly configured)
   - server/src/config/database.ts:177 — admin123 dev fallback, documented dev-only in docs/README.md, API.md, PORTING.md
   - server/src/config/database.ts:2573 — internal migration-runner path helper
   - server/scripts/dev/audit-trace.ts:68 — dev-only migration replay tool
   - scripts/restore-l10n-labels.js:32 — command-injection FP (lang comes from hardcoded ['en','ur'])
   - tool/add_date_filter_edits.py:75,147,196,295 — one-off codemod script (file-level ignore)
   - verify-picker5.py:189 — ad-hoc localhost Playwright script
2. For database.ts:2573 and audit-trace.ts:68, first try a tiny behavior-preserving guard (resolve path inside migrations dir / restrict filename charset); if the finding clears naturally, skip its comment. Otherwise annotate.
3. Re-run deep scan (MCP security_scan_start → status). Assert: zero non-advisory HIGH findings.
4. Self-audit per AGENTS.md: cd server && npm run typecheck && npm run lint (comment-only edits expected clean).
5. End-to-end verify: `git push --dry-run` through Bash (matches gate regex, updates nothing remotely) — expect allow instead of deny.
6. Final report: file→finding→disposition table. Flag as optional follow-ups (not done): integrations.ts:22 advisory mass-assignment candidate worth a human look; server/.env JWT_SECRET still default-ish. No commits/pushes made — user's next real push should pass.

NOT doing: no gate softening/disabling, no behavior changes to app code, no dependency changes.