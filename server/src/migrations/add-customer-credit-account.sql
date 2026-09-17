-- Add Customer Credit account to chart of accounts
-- Used by credit offset feature: Dr Customer Credit / Cr AR
-- This is a contra-asset account (normal balance: credit) that offsets AR (1100).

INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description) VALUES
    ('1110', 'Customer Credit', 'asset', 'credit', 'customer_credit', 'Customer credit balances from returns/overpayments — contra-asset offsetting AR');
