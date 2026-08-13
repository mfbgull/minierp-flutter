-- Opening (seed) balances for the cash accounts — the money a new
-- business starts with. The cash-position figures are
--   balance = opening + inflows − outflows
-- so the drawer/till doesn't start at zero. One row per tracked
-- account; idempotent (INSERT OR IGNORE + upserts preserve edits).

CREATE TABLE IF NOT EXISTS opening_balances (
    account_key TEXT PRIMARY KEY,   -- 'cash' | 'bank' | 'easypaisa' | 'jazzcash' | 'upaisa'
    amount      DECIMAL(15,2) NOT NULL DEFAULT 0,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO opening_balances (account_key, amount) VALUES
    ('cash', 0),
    ('bank', 0),
    ('easypaisa', 0),
    ('jazzcash', 0),
    ('upaisa', 0);
