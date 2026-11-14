# ledger-append-only (Delta)

## ADDED Requirements

### Requirement: One exclusion rule on both sides of every ledger net
A derivation over `customer_ledger` or `supplier_ledger` SHALL exclude rows
where `voided = 1` **and** rows where `reversed_by IS NOT NULL`, on both the
debit side and the credit side.

A void marks the original `voided = 1` and appends an equal-and-opposite
`REVERSAL:*` row carrying `reversed_by` pointing at the original. Excluding the
original's debit while counting the reversal's credit charges the void twice.

#### Scenario: A voided purchase leaves the correct AP
- **WHEN** purchases of 100 and 200 exist and the 100 one is voided
- **THEN** AP aging reports 200, not −100

#### Scenario: Voiding the only purchase reports zero
- **WHEN** the only purchase of 300 is voided
- **THEN** AP aging reports 0, not a negative payable

#### Scenario: A genuine credit note is still counted
- **WHEN** a purchase of 500 has a 200 purchase-return credit note against it
- **THEN** AP aging reports 300

### Requirement: A running balance has one canonical ordering
A reader of a ledger's stored `balance` column SHALL order by `id`, matching the
ordering `rebuildBalances` uses to maintain it. Ordering by `transaction_date`
disagrees with the writer on any backdated entry, because a document entered
later with an earlier date sorts ahead of entries that already settled it.

#### Scenario: A backdated entry does not change the reported position
- **WHEN** a purchase dated 2026-05-01 for 100 exists and a purchase backdated to
      2026-01-15 for 50 is added
- **THEN** `rebuildBalances`, `getBalance`, `computeAPAging`, `getGLReconciliation`
      and `suppliers.current_balance` all report 150

#### Scenario: A new entry seeds from a maintained row
- **WHEN** a ledger entry is appended
- **THEN** its stored balance is seeded from the last row that `rebuildBalances`
      would also read — never from a reversal row, whose stored balance nothing
      refreshes