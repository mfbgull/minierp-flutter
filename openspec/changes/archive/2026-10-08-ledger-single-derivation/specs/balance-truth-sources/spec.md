# balance-truth-sources (Delta)

## ADDED Requirements

### Requirement: A reconciliation aggregates the ledger; it never reads an undefined column
A reconciliation SHALL compute an account's operational side by aggregating the
source rows over a documented filter. It SHALL NOT read a stored running-balance
column whose maintenance rules differ from the rows it summarises.

Reading the highest-id row's `balance` is specifically prohibited: after a void
the highest-id non-voided row is the reversal, whose stored balance was computed
against a pre-void read and which `rebuildBalances` excludes and therefore never
refreshes. The column is undefined after any void.

#### Scenario: AP reconciliation agrees with the ledger after voids
- **WHEN** any supplier has had a purchase voided
- **THEN** the AP row's operational balance equals Σ(debit) − Σ(credit) over the
      filtered rows, and its delta against GL 2000 reflects real drift only

#### Scenario: Backdated entries do not make reconciliation accidentally correct
- **WHEN** two errors would cancel
- **THEN** the report must still be correct, because it no longer depends on a
      column that happened to be right