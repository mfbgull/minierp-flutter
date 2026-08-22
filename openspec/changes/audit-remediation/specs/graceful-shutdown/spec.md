# Spec: graceful-shutdown (Delta)

## ADDED Requirements

### Requirement: Bounded shutdown drains WAL and closes DB
Every termination path (SIGTERM, SIGINT, SIGHUP, unhandledRejection, uncaughtException, rollback CLI exits, env-validation exit) SHALL close the HTTP server with a bounded timeout that force-closes keep-alive connections (`closeAllConnections`), flush queued audit logs, run a WAL checkpoint, call `db.close()`, and only then exit.

#### Scenario: Idle client cannot block shutdown
- **WHEN** SIGTERM arrives while an idle Flutter client holds a keep-alive connection
- **THEN** shutdown completes within the configured timeout with db.close() invoked

#### Scenario: SIGHUP is handled
- **WHEN** the process receives SIGHUP
- **THEN** it performs the same graceful sequence as SIGTERM instead of dying by default disposition

### Requirement: Environment validation precedes database open
Required-environment validation SHALL run before importing/opening the database so a missing JWT_SECRET cannot execute boot migrations and then hard-exit without closing.

#### Scenario: Missing secret mutates nothing
- **WHEN** the server starts without JWT_SECRET
- **THEN** the process exits before any migration or DB connection is created

### Requirement: Desktop session teardown stops the server
The desktop launcher lifecycle SHALL provide a quit hook so closing the Flutter window signals the Node server for graceful shutdown instead of orphaning it until logout.

#### Scenario: Closing the app window shuts down cleanly
- **WHEN** the user closes the desktop application window
- **THEN** the bundled server receives a termination signal and completes the graceful sequence
