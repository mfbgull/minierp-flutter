## ADDED Requirements

### Requirement: Discount scope selection and dynamic discount column
The invoice form SHALL expose an Invoice vs Item discount scope control. Item scope SHALL render the `discountValue` editable column between rate and tax and produce the 6-column field order (`description, quantity, rate, discountValue, tax, amount`); invoice scope SHALL hide the discount column and use the 5-column order (`description, quantity, rate, tax, amount`). Switching scope SHALL recalculate all line totals and the invoice totals. Today the page hardcodes invoice scope; this replaces that with a real radio.

#### Scenario: Switch to per-item scope
- **WHEN** the user selects Item discount scope
- **THEN** the discountValue column appears and the field order gains discountValue between rate and tax
- **THEN** totals recompute using the per-item discount value

#### Scenario: Switch to invoice scope
- **WHEN** the user selects Invoice discount scope
- **THEN** the discountValue column is removed and the field order returns to 5 columns
- **THEN** totals recomputed with the invoice-level discount value only

#### Scenario: Keyboard column-walk honors the active scope
- **WHEN** navigating columns
- **THEN** the current scope's field order (getFieldOrder) is used for next/prev/target-column fallback, skipping the discount column when it does not exist