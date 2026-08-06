## ADDED Requirements

### Requirement: AG-Grid-equivalent keyboard navigation across the item grid
The line-items PlutoGrid SHALL implement the classic (non-V2) web grid's keyboard navigation as its default behavior for editable cells. One cell is in edit mode at a time, tracked by row id + field. All navigation commits the current cell's in-flight value before moving (except Escape, which reverts). Stale navigation from rapid key presses MUST be discarded (a navigation token + microtask/timer sequencing) so focus never commits twice or loses the target cell.

#### Scenario: ArrowUp/ArrowDown commit and move between rows
- **WHEN** a cell is in edit mode and the user presses ArrowUp or ArrowDown
- **THEN** the current cell commits and focus moves to the same column in the previous/next row; ArrowUp on the first row does nothing; ArrowDown on the last row does nothing (no row is appended)

#### Scenario: Column-walk when the target column does not exist
- **WHEN** navigation targets a column that an editable row does not expose (e.g. `amount` on a packed row, or the item-scope `discountValue` column absent in invoice scope)
- **THEN** focus walks the field order forward/backward and lands on the first navigable column of that row

#### Scenario: ArrowLeft/ArrowRight move between columns
- **WHEN** a cell is in edit mode and the user presses ArrowLeft or ArrowRight
- **THEN** for number cells navigation always occurs; for text cells navigation occurs only when the caret is at position 0 (left) or the end (right), otherwise the caret moves instead; ArrowLeft from the first column commits and moves to the previous row's last navigable column; ArrowRight from the last column stays editing (does nothing)

#### Scenario: Caret-movement preserved in text cells
- **WHEN** an editable text cell has the caret in the middle and the user presses ArrowLeft or ArrowRight
- **THEN** the caret moves within the text; navigation SHALL NOT fire

#### Scenario: Ctrl+Arrow steppers on number cells
- **WHEN** a number cell (quantity, rate, tax, discountValue) is editing and the user presses Ctrl+ArrowUp or Ctrl+ArrowDown
- **THEN** the value increments/decrements by 1, clamped so tax ≤ 100 and never below 0; navigation SHALL NOT occur

#### Scenario: Enter, Tab, and Escape in edit mode
- **WHEN** the user presses Enter in edit mode
- **THEN** the cell commits and, on the last row, a new empty row is appended with its description cell focused/selected; otherwise focus moves down
- **WHEN** the user presses Tab in edit mode
- **THEN** the cell commits, focus moves to the next field in the field order (`getNextField`); at end of row, if the last row, a new row is appended with its description focused, else focus moves to the next row's first field
- **WHEN** the user presses Escape
- **THEN** the temp value is reverted, edit mode is exited, focus does not move

#### Scenario: Display-mode navigation
- **WHEN** a cell is focused but not editing and the user presses Enter
- **THEN** the cell enters edit mode with its value selected
- **WHEN** a cell is focused but not editing and the user presses ArrowDown/ArrowUp
- **THEN** focus moves to the same column of the next/previous row (no commit needed)
- **WHEN** a cell is focused but not editing and the user presses ArrowRight or Tab
- **THEN** focus moves to the next field; Tab at the last row's last field appends a new row

#### Scenario: Race protection for rapid navigation
- **WHEN** keys are pressed faster than the navigation settle (React double-rAF equivalent)
- **THEN** a later navigation re-starts the sequencer and any superseded navigation is discarded