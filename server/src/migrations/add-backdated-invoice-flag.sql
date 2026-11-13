-- ACCT-006: a sale may legally predate its stock's purchase receipt
-- (paperwork dated before goods arrived). Such invoices are accepted with a
-- warning; this flag makes the population queryable for the Backdated sales
-- exception report (GET /api/invoices/backdated).
ALTER TABLE invoices ADD COLUMN backdated_before_receipt INTEGER NOT NULL DEFAULT 0;
