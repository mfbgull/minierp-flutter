-- Production Overhead Payable Migration
-- DECISIONS.md D6: production overhead is NOT recorded as a separate expense.
-- It is capitalised once into inventory and accrued as an unpaid payable until
-- settled, so entering a production does not imply a cash outflow.
--
-- A dedicated liability is required rather than account 2000 (Accounts
-- Payable): GL 2000 is reconciled against the supplier ledger in the AP
-- integrity check, so accruing overhead there would report a phantom delta.
--
-- Idempotent: safe to re-run on every server start.

INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description)
VALUES (
    '2200',
    'Accrued Production Overhead',
    'liability',
    'credit',
    'production_overhead_payable',
    'Unpaid overhead absorbed into production inventory, owed until settled'
);
