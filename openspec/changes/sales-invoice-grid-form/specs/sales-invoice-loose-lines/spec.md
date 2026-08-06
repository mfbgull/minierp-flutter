## ADDED Requirements

### Requirement: Packed and loose line behavior
Each line SHALL be treated as packed (computed) or loose (typed amount) according to its `sale_type`. For packed lines the amount column is READ-ONLY and derived from quantity × rate after tax/discount via the driver-field rule (`applyLineFieldUpdate`: editing quantity or rate recomputes amount). For loose lines the amount column is editable; editing amount recomputes rate. A loose line whose quantity × rate ≠ typed amount SHALL show a `lineIssue` indicator under the cell (severity error → red, warning → amber). The unit-of-measure badge SHALL display next to quantity when not editing.

#### Scenario: Packed line computes amount
- **WHEN** a packed line's quantity or rate changes
- **THEN** amount recomputes and the amount cell is read-only

#### Scenario: Loose line computes rate from amount
- **WHEN** a loose line's amount is edited
- **THEN** rate recomputes from amount via `applyLineFieldUpdate`

#### Scenario: Loose-line mismatch warning/error
- **WHEN** a loose line's quantity × rate differs from its typed amount
- **THEN** a `lineIssue` indicator appears under the amount cell (error → red, warning → amber)

#### Scenario: Unit-of-measure badge
- **WHEN** the quantity cell is not editing on a line with a unit_of_measure
- **THEN** the unit-of-measure badge shows next to the quantity