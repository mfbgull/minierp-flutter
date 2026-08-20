## Why

The Settings screen stacks each settings group (Company, Currency & Formatting,
Tax, Document Numbering, Other) as full-width cards in a single vertical column
inside a `ConstrainedBox(maxWidth: 900)`. On wide screens this wastes horizontal
space and forces unnecessary vertical scrolling. Arranging the cards in a
responsive 3-per-row grid uses the available width and shortens the page.

## What Changes

- Lay out the Settings section cards in a horizontal, wrapping grid — **3 columns
  on desktop**, fewer on narrow viewports — instead of one vertical column.
- Each card keeps its exact content and behavior: same fields, save / "unsaved"
  chip, and validation. No functional change.
- Keep the existing max content width (`maxWidth: 900`) and the date-range block
  placement at the top of the screen.

No API, database, schema, or backend changes.

## Capabilities

### New Capabilities

<!-- None — this is an implementation-only UI layout change with no new
     spec-level behavior. -->

### Modified Capabilities

<!-- None — requirements are unchanged; only the layout changes. -->

## Impact

- **Code:** `lib/features/settings/settings_screen.dart` — the layout region in
  `build()` that currently wraps the section cards in a vertical `Column`
  (inside `SingleChildScrollView` → `Center` → `ConstrainedBox(maxWidth: 900)`).
- **Providers / repositories / API contracts:** unchanged.
- **Other screens:** unchanged.
