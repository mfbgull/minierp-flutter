-- Rollback for add-owner-equity.sql
-- Refuses to drop equity accounts still referenced by journal history
-- (FKs are ON; deleting a referenced COA row would fail anyway — this
-- makes the intent explicit and keeps partial rollbacks readable).

DROP TABLE IF EXISTS owner_withdrawal_items;
DROP TABLE IF EXISTS owner_withdrawals;
DROP TABLE IF EXISTS owner_capital;

DELETE FROM chart_of_accounts
WHERE text_code IN ('owner_capital', 'owner_drawings')
  AND id NOT IN (SELECT account_id FROM journal_lines);

DELETE FROM settings WHERE key LIKE 'CAP_last_no_%' OR key LIKE 'WD_last_no_%';
