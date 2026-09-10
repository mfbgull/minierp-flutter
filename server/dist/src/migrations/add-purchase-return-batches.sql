-- Migration: per-line batch consumption ledger for purchase returns
-- (financial-audit-p0-remediation task 4.4 / PRET-05).
-- Records exactly which batches a return consumed so void restores the
-- same batches — create-then-void becomes a value-identity operation.
-- Live data: purchase_returns is empty, so no backfill is required.

CREATE TABLE IF NOT EXISTS purchase_return_batches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    return_line_id INTEGER NOT NULL REFERENCES purchase_return_items(id),
    batch_id INTEGER NOT NULL REFERENCES stock_batches(id),
    quantity DECIMAL(15,4) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_purchase_return_batches_line
  ON purchase_return_batches(return_line_id);
CREATE INDEX IF NOT EXISTS idx_purchase_return_batches_batch
  ON purchase_return_batches(batch_id);
