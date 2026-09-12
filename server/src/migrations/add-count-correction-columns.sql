-- Migration: count-correction workflow (reversal-rules Phase 4)
-- Adds idempotency/audit markers to physical_counts for corrections of
-- COMPLETED counts. POSTED counts remain immutable; corrections are a
-- single-shot reversal + re-application recorded on the original count.

ALTER TABLE physical_counts ADD COLUMN corrected_at TEXT;
ALTER TABLE physical_counts ADD COLUMN corrected_by INTEGER REFERENCES users(id);
