# Database isolation and scope

Verification started 2026-10-26 and continued 2026-10-27 against baseline
`843322e3c01adcfa13f7d40669487c77f04c532e` plus the working-tree changes.
No real financial database was opened for writing, copied, reconciled or repaired.
No commit, push or deployment was performed during verification. Gull subsequently
authorized commit and push; deployment and real financial-data changes remain outside scope.

Jest's unchanged `setupFiles` installs `helpers/installLiveDbGuard.ts` before
application imports. `setup.ts` assigns each suite a fresh `minierp-test-*`
directory before importing the database. `DATABASE_PATH` is a **directory**;
the database module appends `erp.db`. It refuses test imports without this variable.
the current Jest root defaults to gitignored `server/.tmp-test/` (overridable
with `TEST_TMPDIR`), not the system temp root. Model schema-clone fixtures also
use fresh system-temp `erp-fixture-*` directories. Neither path is a live database.
The guard rejects canonical live paths, symlinks and hardlinks to that database.
The new registered migrations 117–121 are exercised only on these fresh fixtures.
They do not backfill guessed historical ownership or count layers.

Shared teardown now stops and flushes the activity logger before deleting fixture
files or closing transports. A durable lifecycle regression reproduced the former
missing queued audit event and passed after that ordering fix; see the red/green
logs in this directory. It does not bypass foreign keys or discard queued errors.

The standalone reversal verifier creates a fresh `/tmp/minierp-verify-*` directory
and sets the database path before importing application code. An additional Node
preload restricted every SQLite constructor to that directory's `erp.db`.
Its completed run reported **79 passed, 0 failed**, exit 0. The preload was moved
out of the source tree after execution, rather than retaining an unused executable
audit helper. The retained command for revalidation is:

```sh
cd server
NODE_OPTIONS='--require=/tmp/minierp-remediation-db-guard.cjs' npm run verify:reversal-rules
```

The preload resolves the repository's SQLite dependency from `server/`, requires
an explicit `DATABASE_PATH`, resolves that directory physically, requires its path
to begin with the system temp directory plus `/minierp-verify-`, and requires the
constructor filename to equal that directory plus `/erp.db`. Any other constructor
throws before opening SQLite. Its exact source is retained in
`standalone-db-guard.txt`; copy that text to the temporary `.cjs` path if `/tmp`
is cleared. The regular Jest guards remain durable in the repository.

Sandbox execution initially blocked Supertest loopback listeners (`listen EPERM`)
and Flutter SDK cache writes. Those runs are environment failures, not red
accounting assertions. The mounted tests were rerun with the required permissions;
the database isolation guards remained installed.

The interrupted full check and coverage run have partial logs, not successful exit
statuses. Their results must not be counted as complete verification.
