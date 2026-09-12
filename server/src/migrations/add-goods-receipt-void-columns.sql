-- Phase 4 (reversal-rules): goods-receipt void attribution.
-- GRNs move stock, so they are never hard-deleted (rule 1) — voiding
-- stamps attribution and appends reversal movements instead.

ALTER TABLE goods_receipts ADD COLUMN voided_at TEXT;
ALTER TABLE goods_receipts ADD COLUMN voided_by INTEGER;
ALTER TABLE goods_receipts ADD COLUMN void_reason TEXT;
