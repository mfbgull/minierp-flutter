"""Demonstrate one existing invariant's coverage boundary; no application DB opens."""
import json
import sqlite3

db = sqlite3.connect(":memory:")
db.executescript("""
CREATE TABLE journal_lines (
  journal_entry_id INTEGER, reference_type TEXT, reference_id INTEGER,
  debit REAL, credit REAL, voided INTEGER
);
INSERT INTO journal_lines VALUES
  (1, 'SYNTHETIC', 1, 10, 0, 0),
  (2, 'SYNTHETIC', 1, 0, 10, 0);
""")
# Same aggregation grain as helpers/accountingInvariants.ts:130-143.
reference_violations = db.execute("""
SELECT reference_type, reference_id, ABS(SUM(debit) - SUM(credit)) AS diff
FROM journal_lines WHERE voided = 0
GROUP BY reference_type, reference_id HAVING diff > 0.005
""").fetchall()
entry_violations = db.execute("""
SELECT journal_entry_id, ROUND(SUM(debit) - SUM(credit), 2) AS diff
FROM journal_lines WHERE voided = 0
GROUP BY journal_entry_id HAVING ABS(SUM(debit) - SUM(credit)) > 0.005
""").fetchall()
assert reference_violations == []
assert entry_violations == [(1, 10.0), (2, -10.0)]
# arImbalances:278-288 compares absolute net balances, discarding sign.
signed_gl_minor = 1000
signed_customer_minor = -1000
reported_ar_difference_minor = abs(signed_gl_minor) - abs(signed_customer_minor)
signed_ar_difference_minor = signed_gl_minor - signed_customer_minor
assert reported_ar_difference_minor == 0
assert signed_ar_difference_minor == 2000
print(json.dumps({
    "scope": "Synthetic query-coverage demonstration, not a transaction-path defect",
    "reference_violations": reference_violations,
    "entry_violations": entry_violations,
    "ar_absolute_comparison_minor": reported_ar_difference_minor,
    "ar_signed_difference_minor": signed_ar_difference_minor,
}))
db.close()
