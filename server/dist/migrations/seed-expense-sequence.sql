-- Migration: seed expense numbering counters from existing maxima
-- (financial-audit-p0-remediation task 5.4 / EXP-05).
-- Expense numbers are EXP-YYMM-NNNN; the settings counter is per-month.
-- INSERT OR IGNORE keeps any counter already advanced past the max.

INSERT OR IGNORE INTO settings (key, value, description)
SELECT 'EXP_last_no_' || substr(expense_no, 5, 4),
       CAST(CAST(substr(expense_no, 10) AS INTEGER) AS TEXT),
       'Expense number sequence for month ' || substr(expense_no, 5, 4)
FROM expenses
WHERE expense_no LIKE 'EXP-____-____'
GROUP BY substr(expense_no, 5, 4)
HAVING MAX(CAST(substr(expense_no, 10) AS INTEGER));
