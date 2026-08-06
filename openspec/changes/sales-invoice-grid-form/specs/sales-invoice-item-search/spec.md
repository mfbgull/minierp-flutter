## ADDED Requirements

### Requirement: In-cell item search dropdown on the description cell
Entering edit mode on the description cell SHALL open a searchable dropdown after ~50 ms, anchored below the cell. The selectable pool SHALL be items where `is_finished_good === true` OR `is_purchased === true` (raw materials excluded). Typing SHALL filter by `item_name` OR `item_code` using a case-insensitive substring match; empty input SHALL show the first 10 items. Each option SHALL display item_name (bold), item_code, `Stock: <current_stock>`, and the formatted `standard_selling_price`. The highlighted row SHALL scroll into view.

#### Scenario: Open the dropdown on edit
- **WHEN** the description cell enters edit mode
- **THEN** a filtered dropdown appears after ~50 ms anchored under the cell

#### Scenario: Filter by name or code
- **WHEN** the user types a substring
- **THEN** matching items (by item_name or item_code, case-insensitive) appear; empty input shows the first 10 items

#### Scenario: No match
- **WHEN** the typed text matches no item
- **THEN** the dropdown shows "No products found" and Enter commits the free text as the description

#### Scenario: Keyboard select and move to quantity
- **WHEN** the user presses ArrowDown/ArrowUp while the dropdown is open
- **THEN** the highlight moves with wrap-around
- **WHEN** the user presses Enter or Tab while an item is highlighted
- **THEN** the item is selected: item_id/description/rate (standard_selling_price)/sale_type/uom/qty_decimal_precision/rounding_step are set, amount resets to 0, and focus moves to the quantity cell
- **WHEN** the user presses Escape
- **THEN** the dropdown closes and the cell stays editing

#### Scenario: Click select
- **WHEN** the user clicks an option
- **THEN** the item is selected and focus moves to the quantity cell

#### Scenario: Blur commit
- **WHEN** the user blurs the cell
- **THEN** the highlighted selection commits or the dropdown closes, unless navigation is in progress