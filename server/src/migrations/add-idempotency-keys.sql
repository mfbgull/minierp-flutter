-- P11: request idempotency keys for safely retryable document creation.
--
-- A client timeout after the server committed a create request used to
-- make the retry create a SECOND invoice (double stock consumption, double
-- GL). The client sends an `Idempotency-Key` header; the first accepted
-- request stores its payload hash and the created resource id here. A
-- retry with the same key + same payload replays the stored result; the
-- same key with a materially different payload is rejected.
--
-- Idempotent: safe to re-run on every server start.

CREATE TABLE IF NOT EXISTS idempotency_keys (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    key           TEXT NOT NULL UNIQUE,
    scope         TEXT NOT NULL,                -- e.g. 'invoice_create'
    request_hash  TEXT NOT NULL,                -- sha256 of canonical JSON body
    resource_id   INTEGER,                      -- created document id (NULL until committed)
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at  TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_idempotency_scope ON idempotency_keys(scope);
