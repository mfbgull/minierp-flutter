## Context

`SettingsScreen` (`lib/features/settings/settings_screen.dart`) currently lays
its section cards (Company, Currency & Formatting, Tax, Document Numbering,
Other) in a **vertical `Column`** inside `SingleChildScrollView` → `Center` →
`ConstrainedBox(maxWidth: 900)`. Each card is therefore full-width (up to 900px)
and stacked top-to-bottom. The cards have **variable heights** (different field
counts per section). The app's mobile breakpoint is 768px (AGENTS.md).

## Goals / Non-Goals

**Goals:**
- Arrange the settings section cards in a responsive grid: **3 columns on
  desktop**, 2 on tablet, 1 on mobile.
- Preserve each card's content, save / "unsaved" chip, and validation behavior.
- Keep the date-range block and the header `Row` (subtitle + refresh) unchanged.

**Non-Goals:**
- No change to the settings data model, API, or bulk-save logic.
- No change to the date-range block layout (stays at the top, full width).
- No new theming, typography, or copy changes.

## Decisions

- **Use `Wrap`, not `GridView`, for the card container.** Section cards have
  variable heights; `GridView` with a fixed `childAspectRatio` would clip or
  stretch content into uniform cells, whereas `Wrap` flows variable-height cards
  into rows naturally with consistent `spacing`/`runSpacing`.
- **Compute per-card width responsively** from the available width (the
  `ConstrainedBox(maxWidth: 900)` column). Pick column count by threshold:
  3 when width ≥ ~768px, 2 on tablet, 1 on mobile. Card width =
  `(availableWidth - (count - 1) * spacing) / count`. This honors the explicit
  "3 in a row" on desktop while staying usable on small screens.
- **Keep `maxWidth: 900` and `spacing: 16`** (matches the current
  `SizedBox(height: 16)` gaps between cards) and `WrapAlignment.center`.
- **Keep the date-range section above the grid** as-is.

**Alternatives considered:**
- `GridView.count(crossAxisCount: 3)` — rejected: uniform cells force equal
  heights, clipping variable content.
- Fixed 3 columns regardless of viewport — rejected: unusable on mobile.

## Risks / Trade-offs

- [Risk] Overly narrow cards if a small desktop window is forced to 3 columns →
  **Mitigation:** degrade to 2 / 1 columns via width thresholds.
- [Risk] Uneven row heights inside a `Wrap` (a row aligns to its tallest card) →
  acceptable; vertical `runSpacing` keeps gaps consistent.
- [Risk] `LayoutBuilder` inside `SingleChildScrollView` reports the scroll
  viewport width → fine, since the content is capped at `maxWidth: 900` and
  centered.

## Migration Plan

Purely additive layout change — no data or API migration. Rollback = revert the
single file.

## Open Questions

None.
