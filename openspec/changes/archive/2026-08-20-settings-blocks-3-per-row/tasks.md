## 1. Layout refactor

- [x] 1.1 In `SettingsScreen.build()`, replace the vertical `Column` of
  `_sectionCard` widgets (the `for (final section in sections) ...` block) with
  a responsive `Wrap` container (`spacing: 16`, `runSpacing: 16`,
  `alignment: WrapAlignment.center`).
- [x] 1.2 Compute the per-card width from the available width (via
  `LayoutBuilder`, or derived from the `maxWidth: 900` constraint) choosing 3
  columns on desktop (≥ ~768px), 2 on tablet, 1 on mobile; wrap each
  `_sectionCard` in a `SizedBox(width: cardWidth)`.
- [x] 1.3 Keep the date-range section and the header `Row` (subtitle + refresh)
  unchanged, positioned above the new grid.

## 2. Verification

- [x] 2.1 Run `dart analyze lib/features/settings/settings_screen.dart` — zero
  errors.
- [ ] 2.2 Manually verify on desktop (3 columns), tablet width (2 columns), and
  mobile width (1 column) that cards flow correctly and the save / "unsaved"
  chip behavior is intact.
