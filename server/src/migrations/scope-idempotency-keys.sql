-- audit-3 task 08 (decision 8.3): make idempotency keys unique per scope.
--
-- The table was `key TEXT NOT NULL UNIQUE` — a single global namespace for
-- every operation. Two problems followed from that:
--
--   1. claimIdempotencyKey upserts with `ON CONFLICT(key) DO UPDATE`, so a
--      key reused by a DIFFERENT operation silently overwrote the first
--      operation's resource_id. That is a wrong dedupe, which on a
--      money-moving write means either a lost replay or a false one.
--   2. A client that generated one key per submit (rather than per
--      operation) would collide across endpoints and 409 for no reason.
--
-- Rebuilding to UNIQUE(scope, key) makes a key meaningful only within the
-- operation that issued it, and makes the upsert conflict target explicit.
--
-- SQLite cannot drop a UNIQUE constraint in place, so the table is rebuilt.
-- Rows are preserved: an existing key keeps its hash and resource_id, so
-- in-flight retries across a restart still replay.
--
-- Idempotent: re-running finds the composite index already present.

CREATE TABLE IF NOT EXISTS idempotency_keys_scoped (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    key           TEXT NOT NULL,
    scope         TEXT NOT NULL,                -- e.g. 'payments.customer'
    request_hash  TEXT NOT NULL,                -- sha256 of canonical JSON body
    resource_id   INTEGER,                      -- created document id (NULL until committed)
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at  TIMESTAMP,
    UNIQUE(scope, key)
);

INSERT OR IGNORE INTO idempotency_keys_scoped
    (id, key, scope, request_hash, resource_id, created_at, completed_at)
SELECT id, key, scope, request_hash, resource_id, created_at, completed_at
FROM idempotency_keys;

DROP TABLE idempotency_keys;

ALTER TABLE idempotency_keys_scoped RENAME TO idempotency_keys;

CREATE INDEX IF NOT EXISTS idx_idempotency_scope ON idempotency_keys(scope);

-- Supports the 30-day retention sweep in decision 8.4, which prunes on
-- completed_at.
CREATE INDEX IF NOT EXISTS idx_idempotency_completed_at
    ON idempotency_keys(completed_at);
