# search-permission-filtering Specification

## Purpose

Global search filters rows by the caller's module read permissions with one
permission resolution per request, hides inactive/cancelled records, and caps
per-entity results.

## Requirements

### Requirement: Search results respect module read permissions
The global-search endpoint SHALL skip an entity search when the caller lacks that entity's `<module>:read` permission; only the page list may additionally be filtered per-page permission. A user with zero module permissions SHALL receive zero entity rows. This gates *rows*, complementing the existing server-side `filterActions` gating of *actions*.

#### Scenario: Permissionless user sees nothing
- **WHEN** an authenticated user holding no module permissions runs a search
- **THEN** the response contains no invoice, payment, expense, employee, customer or supplier rows

#### Scenario: Payments-only user cannot see expenses
- **WHEN** a user with only `payments:read` searches a term matching both a payment and an expense
- **THEN** payments are returned and no expense row appears in the response

### Requirement: Permission set resolved once per request
Search SHALL resolve the caller's permission set exactly once per request and pass it down to all entity searches and action filtering; `filterActions` MUST NOT issue per-row permission or role queries. A keystroke's search SHALL execute O(entities) permission queries total, not O(result rows).

#### Scenario: Keystroke cost is bounded
- **WHEN** a search returns the maximum result count across all entities
- **THEN** the request performs a single permission resolution (plus the admin early-exit path) instead of one query chain per returned row

### Requirement: Search results respect record status
Invoice search SHALL exclude Cancelled invoices (or badge them explicitly); warehouse and employee search SHALL filter `is_active = 1`. Inactive customers/suppliers/items keep their existing `is_active = 1` behaviour.

#### Scenario: Terminated employee not findable
- **WHEN** an employee is deactivated and a user searches their name
- **THEN** no employee row is returned

#### Scenario: Cancelled invoice excluded
- **WHEN** an invoice is cancelled and its number is searched
- **THEN** the invoice does not appear as a normal result

### Requirement: Per-entity result cap enforced
The per-entity result limit SHALL be capped at 10 (the global-search spec's stated maximum) at controller and route validation; dead ranking helpers (`rankClause`/`rankParams`) with zero call sites SHALL be deleted.

#### Scenario: Limit cannot be inflated
- **WHEN** a client requests `limit=50`
- **THEN** each entity contributes at most 10 results
