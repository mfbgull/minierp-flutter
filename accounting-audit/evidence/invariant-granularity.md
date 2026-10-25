# Invariant A aggregation coverage

Executed in an in-memory SQLite database using Python sqlite3 on 2026-10-25. Reproduce: `python3 accounting-audit/tests/invariant-granularity.py`.

Source: `server/src/__tests__/helpers/accountingInvariants.ts:130-143`. `glImbalances` groups active journal lines by reference type/id, and separately checks the whole-ledger difference. It does not group by individual journal entry.

Synthetic input: entry 1 debits Rs 10, entry 2 credits Rs 10, both under the same synthetic reference. Reference-group violations: `[]`. Per-entry violations: `[[1,10.0],[2,-10.0]]`.

Conclusion: A alone does not establish that every journal entry balances. The new lifecycle oracle also checks individual journal-entry groups. This is a demonstrated coverage limitation, **not evidence that a production transaction path writes such entries**. Shared posting normalizes balanced lines; application and database controls must be assessed separately. No financial defect severity is assigned to this synthetic demonstration.

An initial attempt to load better-sqlite3 in the context-mode JavaScript runtime failed because that runtime uses Bun. It performed no successful DB open. The successful probe used Python SQLite entirely in memory.

## Invariant F sign coverage

`arImbalances` at lines 278–288 compares `abs(GL1100 + GL1110)` with `abs(sum(current_balance) - sum(credit_balance))`. An asset of Rs 10 and a customer net credit obligation of Rs 10 therefore compare equal even though their signed difference is Rs 20. The same reproducible script checks this with integer paise. This is an additional coverage limitation, not proof of a transaction path creating that exact state. Findings use signed differences as well as the existing helper's diagnostic; an absolute-value diagnostic must not be presented as the full economic discrepancy.
