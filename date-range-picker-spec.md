# Date Range Picker — Implementation Spec

Status: **in implementation** — Phase 0 (shared date math + `compactRange`), Phase 1 (server preferences store + week-aware `period=week`, §6) and Phase 2 (Flutter preference client, §6.2) are **done**; Phases 3–6 pending. §6 below reflects what Phases 1–2 actually built.
Source of reference: `D:/date-range-picker.html` (web prototype shared by the user)
Target app: `mini-erp-flutter` (Flutter desktop/Windows/Linux + web, Material 3, l10n en+ur)

---

## 1. Goal

Port the reference web date-range picker into the Flutter app as a **drop-in replacement** for the current two-button From/To row (`DateRangeFilter` in `lib/widgets/date_picker_helpers.dart`), used on **all ~24 screens**. The new picker is a single pill-shaped control:

```
[ ‹ ]  [ 📅 Aug 7 – 13, 2026 | This week ]  [ › ]
```

- Clicking the middle opens an **anchored popover**: presets sidebar + dual-month calendar.
- The **‹ ›** arrows shift the active range by one period.
- Picking a preset **applies instantly**; a custom range commits when the second (end) date is clicked.
- The widget also gains a **single-date mode** (for cash reconciliation) and **persisted preferences** (week-start day, default range, user-defined presets) synced **server-side per user**.

No changes to `pickDate` (still used by ~15 form dialogs for single document dates — invoice dates, PO dates, employee DOB, etc.).

---

## 2. Reference behavior (source of truth — from the HTML)

### 2.1 The bar
- `[prev] [calendar-icon + range text + preset chip] [next]` inside a rounded pill (`border-radius: 999px`).
- Range text format (tabular numerals; en-dashes exactly like the HTML — the same-month case has **no spaces** around the dash):
  - Same day → `Aug 13, 2026`
  - Same month & year → `Aug 7–13, 2026`
  - Same year → `Aug 7 – Sep 13, 2026`
  - Different years → `Aug 7, 2026 – Sep 13, 2027`
- Preset chip: matching preset label (`This week`, `Last 30 days`, …) or `Custom`.

### 2.2 Shift arrows (`‹ ›`)
- Move the whole range by one period, based on the *preset type* of the current selection:
  - `month` → ±1 month (start = 1st, end = month end)
  - `week` → ±7 days
  - `day` → ±1 day
  - `span` (7/30/90) → ±span days
  - `custom` → ± range length (start & end both shifted by N days)

### 2.3 The panel
- **Presets sidebar** (top→bottom): `Today`, `Yesterday`, `This week`, `Last week`, `Last 7 days`, `Last 30 days`, `Last 90 days`, `This month`, `Last month`, `Custom range`.
- **Dual-month calendar**: two adjacent months, Monday-first weekday row (`Mo Tu We Th Fr Sa Su`), 42-cell grid per month, adjacent-month days muted, today outlined, in-range days teal-filled, range start/end dark pills (rounded ends).
- **Footer hint**: `Pick a start date` → `Pick an end date` → `N days selected` (+ `1 day` singular).
- **Apply/Cancel** in the reference — **dropped** per interview (instant apply instead).

### 2.4 Selection flow (adapted for instant apply)
- Click a day → it becomes `start`.
- Click a second day → becomes `end`; if it is *before* start, the two swap. Range commits immediately (instant apply).
- Clicking the same day twice → single-day range.
- (Single-date mode) one click on a day commits that day immediately.

### 2.5 Dismissal
- Click outside the bar/panel closes it (discarding an incomplete start-only selection).
- `Escape` closes it.

---

## 3. Interview decisions (locked)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Rollout scope | **Everywhere** — replace the two-button `DateRangeFilter` on all ~24 screens (reports, lists, dashboard) |
| 2 | Shift arrows | **Keep on the bar** (`‹ ›`) |
| 3 | Preset chip | **Keep**, labels localized (en + ur) and theme-aware |
| 4 | Apply semantics | **Instant apply** — no Apply/Cancel; presets commit on click, custom range commits on end-date click |
| 5 | Color palette | **App theme colors** (Material 3 green accent, surface/outline tokens) — no brass/teal palette |
| 6 | Panel style | **Anchored popover** under the pill |
| 7 | Dark mode | **Both modes** (full light + dark) |
| 8 | Calendar layout | **Dual month** side by side with month-pair paging |
| 9 | No-filter state | **"All dates" preset at top + clear icon** beside the pill (list screens) |
| 10 | Future dates | **Cap at today** (no future dates selectable) |
| 11 | Custom flow | **Commit on end pick**; closing early discards a start-only selection |
| 12 | Ruler strip | **Skipped** — no 30-tick ruler |
| 13 | Narrow panes | **Overlay + scroll** — popover overflows the toolbar/pane, clamped to window edges, never clipped |
| 14 | Keyboard | **Full keyboard nav** (arrows move day focus, Enter selects, Escape closes, Tab between regions) |
| 15 | Locale/RTL | **Monday-first, no RTL mirror** — panel stays LTR in Urdu (only text is localized) |
| 16 | Single-date mode | **Yes** — reduced preset set (Today, Yesterday, This month, tap-a-day) for cash reconciliation |
| 17 | Default ranges | **Switch to "This week"** everywhere (reports **and** list screens) on first open |
| 18 | Widget name | **Drop-in `DateRangeFilter`** — keep class name + constructor params; call sites change minimally |
| 19 | Old widget | **Delete** `DateRangeFilter`/`DateFilterButton`/`pickFilterDate` + their tests; keep `pickDate` (form dialogs) |
| 20 | Default-range control | **Both**: a *"Set as default range"* action in the picker **and** user-defined custom presets (add/remove) |
| 21 | Week start | **Configurable: Monday / Saturday / Sunday** (default Monday), switchable from **both** the picker popover and the Settings screen |
| 22 | Persistence | **Server-side per user** (new preferences endpoint + table, synced across devices) |

---

## 4. New widget design

### 4.1 Structure & files

New shared widget in `lib/widgets/date_range_picker.dart` (internals private to it), and the existing `lib/widgets/date_picker_helpers.dart` is **renamed** to `lib/widgets/date_picker.dart` (all imports updated; it keeps only `pickDate` + its doc — see §7.4).

- `DateRangeFilter` — **kept name** (drop-in). Now a `ConsumerStatefulWidget`:
  - Same constructor params: `fromProvider`, `toProvider`, `onChanged`, `onClear`, `showClear`, plus optional `width`/`height` (accepted but ignored — the pill self-sizes; kept so existing call sites compile untouched). New params:
    - `mode` — `DateRangeMode.range` (default) | `DateRangeMode.singleDate`
    - `dateProvider` — used only in `singleDate` mode (e.g. `reportReconciliationDateProvider`)
    - `showAllDates` — default `true`; report screens pass `false` (reports never have a no-filter state)
  - Private internals: `_PillBar`, `_RangePopover` (OverlayPortal), `_PresetsPanel`, `_MonthPair`/`_MonthGrid`, `_DayCell`.

### 4.2 Popover technology

- **New pattern for the codebase** (no `OverlayPortal`/`LayerLink` usage exists yet — verified via search). Use `CompositedTransformTarget` (on the pill) + `CompositedTransformFollower` (on the panel) inside an `OverlayPortal`, so the panel renders above the toolbar/screens.
- **Positioning**: aligned to the pill's left edge, top = below the pill + ~8px. If the panel would overflow the *window* (not the pane), clamp horizontally and/or flip vertically; if the window is narrower than the panel, the panel content scrolls horizontally/vertically. Never clipped by the pane.
- **Barrier behavior**: `OverlayPortal`'s controller shows the panel; a tap on the modal barrier (or anywhere outside the bar+panel) closes it. `Escape` closes it.

### 4.3 Pill bar

```
[IconButton ‹] [InkWell: 📅  "Aug 7 – 13, 2026"  chip("This week")] [IconButton ›]
```

- One rounded pill (`StadiumBorder`/`borderRadius: 999`), `OutlinedButton`-like styling using theme `outline`/`outlineVariant` border + `surface` fill.
- Tooltips: `Previous period` / `Next period` on the arrows; the main button's tooltip is the full date text.
- Preset chip: small `Container` pill, `primaryContainer`/`onPrimaryContainer` colors, uppercase `labelSmall`, localized.
- **Bar text**:
  - Range mode, both dates set → compact text per §2.1 formatting rules (new `Formatters.compactRange` helper, tabular figures).
  - Range mode, both null → `All dates` (localized), no chip.
  - Range mode, exactly one date set → that date formatted (`Formatters.date`); no chip. (Mixed state is only reachable via legacy writes; the picker itself always writes both.)
  - Single-date mode → `Formatters.date(date)`; chip shows matched single-date preset or `Custom`.
- **Clear icon** (`filter_alt_off_outlined`) rendered beside the pill under the same conditions as today: `onClear != null && (showClear?.call() ?? both null == false)`. It restores both providers to null and fires `onChanged`.

### 4.4 Panel layout

```
┌───────────────────────────────────────────────────────┐
│ ┌───────────┐  ┌────────────────────────────────────┐ │
│ │ Presets   │  │  ‹  Aug – Sep 2026            ›    │ │
│ │ (scroll)  │  │  ┌────────────┐ ┌────────────┐     │ │
│ │           │  │  │ Aug 2026   │ │ Sep 2026   │     │ │
│ │           │  │  │ Mo..Su grid│ │ Mo..Su grid│     │ │
│ └───────────┘  │  └────────────┘ └────────────┘     │ │
│                │  ┌────────────────────────────────┐ │ │
│                │  │ hint: "N days selected"        │ │ │
│                │  └────────────────────────────────┘ │ │
└───────────────────────────────────────────────────────┘
```

- **Width** ≈ 720–760px (presets 168px + calendar ~560px), matching the reference.
- **Presets sidebar** (scrollable `ListView`):
  - `All dates` (only when `showAllDates`) → sets both providers to null; label highlighted (e.g. `errorContainer`-ish/neutral "active" treatment) when both null.
  - Reference presets, computed relative to today with the **active week start** (§4.5).
  - **User-defined presets** (persisted, §6) appended below `Custom range`, each with a small remove (✕) affordance.
  - `Custom range` entry — active when current range doesn't match any preset.
  - Active preset = dark fill (`ink` equivalent → `onSurface`-inverse styling: `colorScheme.inverseSurface`/`onInverseSurface`).
- **Calendar header**: `‹  Aug – Sep 2026  ›` paging a month *pair* (anchor month + next).
- **Dual-month grids**: Monday/Saturday/Sunday-first per saved week start; 7-col × 6-row; adjacent-month days muted; today outlined; in-range fill = `primaryContainer` (or `secondaryContainer`), start/end = `primary`/`onPrimary` rounded pills.
- **Footer hint**: `Pick a start date` → `Pick an end date` → `N days selected` (`1 day`). Also carries the **"Set as default range"** action (§6.2) on the right, and (only in `range` mode with `showAllDates`) it's the only footer row — no Apply/Cancel.

### 4.5 Week start

- Stored preference: `monday` (default) | `saturday` | `sunday`.
- Affects **three** places:
  - the calendar grid's first column (weekday row + leading blanks),
  - the `This week` / `Last week` preset math (`startOfWeek(today, weekStart)`), and
  - the dashboard **`period=week` blocks** (Sales Summary + Expense Summary) — computed server-side (§6.3).
- Switchable from:
  - the picker popover (a small settings row in the footer, e.g. `Week starts on: [Mon|Sat|Sun]` segmented control), and
  - the app **Settings** screen.
- Persisted **server-side per user** (§6.1); local provider holds the active value; write-through on change.

### 4.6 Keyboard navigation (full)

- Focusable regions, in Tab order: bar arrows → bar main → (panel open) presets → month pager → day grid(s) → footer controls.
- Inside a day grid: `←↑→↓` move the focused day (across month boundaries where sensible), `Enter`/`Space` select (range or single-date per mode), `PageUp`/`PageDown` page the month pair, `Home`/`End` first/last day of the visible month, `Escape` closes the panel and returns focus to the pill.
- Focused day gets a visible focus ring (`focusColor`/`InkWell` focus highlight). All cells are real buttons (`Semantics` label: `Tuesday, August 11`).
- Note: `Escape` must not conflict with the app's screen-level shortcuts (`screen_shortcuts.dart` handles Ctrl+chords only — no conflict expected; verify during implementation).

### 4.7 Dates & bounds

- **Upper bound: today** for both range and single-date modes (`lastDate = today`), consistent with the current `pickFilterDate` cap. Lower bound `2000-01-01`.
- The panel calendar's default view anchors on `from` (or the single date, or today when null).
- All date math on local dates (no time component); reuse `isoDate` for writes and `Formatters` for display.

---

## 5. Behavior rules (edge cases)

### 5.1 Instant-apply state machine (range mode)

| State | Action | Result |
|---|---|---|
| start & end set (committed) | open panel | pending cleared; calendar anchors on start; hint `Pick a start date` |
| no pending | click day A | pending.start = A; **bar updates immediately** to show A; hint `Pick an end date` |
| pending.start = A | click day B (B ≥ A) | pending.end = B; commit pair → write both providers, fire `onChanged`, close panel |
| pending.start = A | click day B (B < A) | swap: start = B, end = A; commit pair, fire `onChanged`, close panel |
| pending.start = A | click A again | commit single day A–A; fire `onChanged`, close panel |
| pending.start = A | close panel (outside tap / Escape) | discard; bar stays on last committed range; hint resets |

- Every committed write also updates the pill's preset chip via **preset matching** (§5.3).
- Report screens: committed pair always non-null (reports always have a range).

### 5.2 "All dates" / no-filter (list screens)

- `All dates` preset writes **both** providers to null (and single-date mode's `dateProvider` to null where supported) then fires `onChanged`. Bar shows `All dates`, no chip.
- The existing `onClear`/`showClear` contract is unchanged (the clear icon beside the pill remains).
- Dashboard note: the dashboard's `onChanged` calls `applyGlobalReportRange` only when `from != null && to != null` — unchanged; an "All dates" choice on the dashboard is a no-op for propagation (dashboard global range stays non-null).

### 5.3 Preset matching (for the chip)

- On any commit, compute the current `(from, to)` (or single date) and compare against every preset's computed range (built-ins + user presets). Exact match → that preset's label + "active" state in the sidebar; no match → `Custom` (active entry in sidebar).
- Preset comparison is exact-day comparison on `DateTime` (year/month/day), no time components.

### 5.4 Shift arrows (`‹ ›`)

- Behavior per §2.2, using the *matched preset type* of the current selection; `custom` shifts by range length; `All dates` state → arrows disabled.
- A shift **commits immediately** (instant apply) — writes providers, fires `onChanged`, keeps the panel state as-is if open.
- Chip updates via matching (§5.3); a shifted `this-week` no longer matches → chip flips to `Custom`.
- **Clamped at today** (locked in Phase 0 review): the › arrow is disabled when the shift would make the range *start* after today (`shiftRangeClamped` in `date_range_math.dart` returns null). A range may still contain future days (This week ends Sunday).

### 5.5 Single-date mode

- Used by the cash-reconciliation screen: pill shows one date, tap-a-day commits instantly, arrows shift by ±1 day.
- Preset set: `Today`, `Yesterday`, `This month`, `Custom` (custom = tap a day). No range-only presets.
- Provider: the screen's `reportReconciliationDateProvider` (via new `dateProvider` param). Null → pill shows today.

---

## 6. Persisted preferences (server-side per user)

### 6.1 Server work

New per-user preference store (AGENTS.md: migration required) — **implemented in Phase 1**.

- **Table** `user_preferences` (migration `server/src/migrations/add-user-preferences.sql` + symmetric rollback in `migrations/rollbacks/`):
  - `user_id INTEGER PRIMARY KEY` (FK users `ON DELETE CASCADE`) — the PK is what makes the upsert's `ON CONFLICT(user_id)` legal, `week_start TEXT NOT NULL DEFAULT 'monday'`, `default_range TEXT` (JSON-serialized `{from,to}` ISO dates, or NULL), `presets TEXT NOT NULL DEFAULT '[]'` (JSON array of `{id, name, from, to}`), `updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`.
  - SQLite has no native JSON column — JSON fields are stored as `TEXT` and parsed defensively in the model (a corrupt blob falls back per-field, never throws).
- **Endpoints** (auth-protected via `authenticateToken`; reuse the **`settings`** module permissions — `read` for GET, `update` for PUT — so a settings-capable user controls dashboard week start; no new permission entries):
  - `GET /api/preferences` → the current user's `{weekStart, defaultRange, presets}` (camelCase wire shape), in the standard `{success, data}` envelope.
  - `PUT /api/preferences` → **partial** update (fields not present keep their current value; `defaultRange: null` clears it), returns the saved merged object.
- Implemented as `models/UserPreferences.ts` (get/upsert, single-statement atomic write) + `controllers/preferencesController.ts` + `routes/preferences.ts` (mounted in `app.ts`), mirroring the existing `settings` pattern. Prepared statements only.
- **Backfill on read**: GET returns server defaults (`{monday, null, []}`) when no row exists — defaults are computed in memory, **no write-on-GET** (a row is only created by the first PUT).
- **PUT validation** (400 on violation): `weekStart` ∈ `{monday, saturday, sunday}`; `defaultRange` is `{from, to}` in `YYYY-MM-DD` with `from <= to` (lexicographic comparison is exact for the enforced zero-padded format) or explicit `null`; each preset is `{id, name, from, to}` with non-empty **unique** ids and `from <= to`.

### 6.2 Client consumption

- `PreferenceRepository` + `userPreferencesProvider` (FutureProvider) and a local `StateProvider` cache seeded at app boot (`app_shell.dart` init) so provider *initial values* and the picker can read synchronously; write-through on change (fire-and-forget with error toast per app conventions; `ApiFailure` → keep local value + toast).
- **Default range** — providers initialize to it:
  - `globalReportFromDateProvider`/`To`, all report From/To pairs, and list-screen pairs (sales, quotations, expenses, sales orders, invoice returns, activity log) seed from `defaultRange` when set, else `This week` (computed with saved week start). Implemented as a small shared initializer (`initialRange(ref)`-style helper) so each `StateProvider`'s `(ref) => …` reads the cached preference.
- **"Set as default range"** action (picker footer, both modes): persists the current committed `(from,to)` (or single date as a day range) via `PUT /preferences {defaultRange}`. Success toast `Default range set`; the label reflects that the next app open starts there.
- **User presets**: an `Add preset` affordance in the presets sidebar (bottom): captures the current committed range with a name prompt (dialog), appends to `presets`, persisted via `PUT /preferences`. Each user preset row has a ✕ remove. Server `presets` array is the source of truth.

### 6.3 Week-aware `period=week` dashboard blocks

Per decision Q1, the dashboard's **Sales Summary** and **Expense Summary** blocks stop being rolling 7-day windows and become calendar weeks aligned to the saved `week_start` — **implemented in Phase 1**.

- `server/src/models/Dashboard.ts`: `getSalesSummary(db, period = 'today', userId?)` / `getExpenseSummary(db, period = 'month', userId?)` build their WHERE clause through a shared `periodWhereClause(db, period, column, userId?)` helper. `period` goes through a whitelist `switch` (`today` | `week` | `month`); `column` is hard-coded by each caller (`invoice_date` / `expense_date`) — never user input.
- For `period === 'week'` **with** a `userId`, the bounds come from `weekBounds(todayISO, weekStart)` (`server/src/utils/weekMath.ts` — UTC math, the server twin of the Flutter `date_range_math.dart`): inclusive `{from, to}` where `from` is the week's first day per the saved `week_start` and `to = from + 6`. The user's `week_start` is read via `UserPreferences.getForUser(db, userId)` — an absent row backfills the `monday` default. Using the full week matches the picker's "This week"; trailing future days are harmless since no future data exists.
- The bounds are passed as **prepared-statement parameters** — `` `${column} BETWEEN ? AND ?` `` with `[from, to]` — no string-built SQL (AGENTS.md DATABASE rule).
- `week` **without** a `userId` keeps the legacy rolling 7-day window; unknown periods default to `today`. Only authenticated `period=week` is week-start-aware.
- The dashboard controllers already authenticate per-request and pass `req.user?.id` into the model functions, threading the same `req.user` used by the preferences routes.
- All other periods (`today`, `month`) and all other rolling-N-day queries (chart, production status, stock movement) stay rolling windows — only `period=week` changes.

### 6.4 Settings screen

- New **"Date & Range"** section: `Week starts on` (Monday/Saturday/Sunday radio or segmented), plus a read-only display + `Set current range as default` shortcut. Same write path as §6.2.
- Settings data is separate from the existing company-profile settings endpoint; do **not** mix — new endpoint (§6.1).

---

## 7. Call-site changes

### 7.1 Swap the pill in (19 current `DateRangeFilter` usages)

Report screens (12): `supplier_analysis`, `sales_summary`, `sales_by_item`, `sales_by_customer`, `purchase_summary`, `profit_loss`, `production_summary`, `expenses_report`, `dso`, `customer_statements`, `cash_flow`, `bom_usage`.

List screens (6): `sales_screen`, `sales_orders_screen`, `quotations_screen`, `expenses_screen`, `invoice_returns_screen`, `activity_log_screen`.

Dashboard (1): `dashboard_screen` (global range — keeps its `onChanged → applyGlobalReportRange` wiring).

Each call site:
- Stays `DateRangeFilter(fromProvider:…, toProvider:…, onChanged:…, onClear:…, showClear:…)` — params unchanged.
- Report screens: pass `showAllDates: false`.
- **Audit** each site for `width:`/`height:` params and drop them (pill self-sizes; params become accepted-but-ignored or are removed if nothing passes them — verify per-site).

### 7.2 Default-range updates in providers

- `lib/features/reports/report_providers.dart`:
  - `globalReportFromDateProvider`/`To` → seed from saved default range, else `this-week` (was `_monthsAgo(1)` → today).
  - All 13 report pairs → same seeding (was `_monthsAgo(1)`/`_monthsAgo(3)` → today).
  - `_monthsAgo`/`_today` helpers: keep `_today`; replace range seeding with the shared initializer (§6.2).
- `lib/features/activity_log/activity_log_providers.dart`: From/To default null → **saved default range** (initially this-week) — the activity log now opens filtered (decision Q2: lists follow the saved default).
- List-screen provider pairs (sales, quotations, expenses, sales orders, invoice returns): currently null → **saved default range** (initially this-week), same seeding as reports.
- All of the above still live in `_reportRangePairs` for `applyGlobalReportRange` — unchanged.

### 7.3 Single-date screen

- `cash_reconciliation_screen.dart`: replace its `pickDate` button (`_pickDate` → `reportReconciliationDateProvider`) with `DateRangeFilter(mode: singleDate, dateProvider: reportReconciliationDateProvider, …)`.

### 7.4 Deletions

- `lib/widgets/date_picker_helpers.dart` → **rename** to `lib/widgets/date_picker.dart`, keeping only `pickDate` + its doc. Update **all** imports of `date_picker_helpers.dart` (the ~19 screens, ~15 form dialogs, test files) to `date_picker.dart`. Remove `DateRangeFilter`, `DateFilterButton`, `pickFilterDate`.
- New `lib/widgets/date_range_picker.dart` holds the pill + popover widget (decision Q3: rename + new file).
- Update `test/widgets/date_picker_helpers_test.dart` → rename to `test/widgets/date_picker_test.dart` (keeps the `pickDate` groups; deletes `DateRangeFilter`/`DateFilterButton`/`pickFilterDate` groups) and add `test/widgets/date_range_picker_test.dart`. Update `test/widget_test.dart` (~line 6020 asserts From/To buttons — replace with pill assertions).

---

## 8. l10n (en + ur)

New keys (all camelCase, both `en.arb` and `ur.arb`):

- `drpPresetToday` / `Yesterday` / `This week` / `Last week` / `Last 7 days` / `Last 30 days` / `Last 90 days` / `This month` / `Last month` / `Custom range` / `Custom` / `All dates`
- `drpPickStart` (“Pick a start date”) / `drpPickEnd` (“Pick an end date”) / `drpDaysSelected` (“{count} days selected”, 0-plural) / `drpOneDay` (“1 day”)
- `drpPrevPeriod` (“Previous period”) / `drpNextPeriod` (“Next period”) / `drpOpenPicker` (bar tooltip)
- `drpWeekStartsOn` (“Week starts on”) / `drpWeekdayMonday` / `drpWeekdaySaturday` / `drpWeekdaySunday`
- `drpSetDefault` (“Set as default range”) / `drpDefaultSet` (“Default range set”) / `drpDefaultFailed` (“Couldn't save default range”)
- `drpAddPreset` (“Add preset”) / `drpPresetName` (“Preset name”) / `drpPresetAdded` (“Preset added”) / `drpPresetRemove` (“Remove preset”)
- `drpCustomRange` — tag fallback when nothing matches (may reuse `Custom`)
- `settingsWeekStart` (“Week starts on”) — Settings screen section + labels reuse `drpWeekday*`

Also: `dashboardGlobalDateRangeHint` stays as-is.

---

## 9. Tests

### 9.1 Unit (pure Dart — new `test/core/` or alongside)

- Preset math: `This week` / `Last week` for monday/saturday/sunday starts; `Last 7/30/90`; `This month`/`Last month` incl. year boundaries (Dec→Jan, Jan→Dec).
- Range text formatting (`Formatters.compactRange`): single day, same month, same year, cross-year; tabular/plural rules.
- Preset matching: exact match → label; near-miss → `Custom`.
- Shift math: week/month/day/span/custom by ±1.

### 9.2 Widget (`test/widgets/date_range_picker_test.dart` — renamed per §7.4)

- Pill renders compact text + chip; `All dates` when null.
- Tap pill → popover opens (presets + dual months); outside tap / Escape closes; start-only selection discarded on close.
- Preset click → providers written + `onChanged` fired + panel closes + chip updates.
- Custom two-click: commit on end pick; swap when end < start; same-day double-click = single day.
- Clear icon visibility rules (onClear/showClear contract preserved).
- Single-date mode: reduced presets; tap commits; arrows shift ±1 day.
- Keyboard: arrows move focus, Enter commits, Escape closes, PageUp/PageDown page months.
- Dark theme smoke test (theme brightness both modes).

### 9.3 Server — three suites implemented in Phase 1 (38 tests)

- `userPreferences.test.ts` (in-memory DB): defaults when no row exists; upsert + partial merge without clobbering; per-user isolation; clear-null; preset JSON round-trip; corrupt-row fallback.
- `preferences.test.ts` (HTTP, real app): GET defaults; partial PUT persists and doesn't clobber earlier fields; invalid `weekStart`; malformed and **reversed** `defaultRange`; reversed preset; **duplicate / empty preset ids**; single-day `from == to` accepted; clear via `null`; non-object body; 401 unauthenticated; **403 for a role lacking `settings` permission** (seeded `User` role).
- `dashboardWeek.test.ts` (in-memory): `period=week` aligned to monday/saturday/sunday; expense summary on a saturday week; rolling fallback without a user id; **monday fallback for a user id with no preference row**; `today`/`month` unchanged; cancelled invoices excluded. (`weekBounds` rollover across month/year boundaries is covered in Phase 0's `weekMath.test.ts`.)

### 9.4 Existing suites to update

- `test/widget_test.dart` (~6020) — From/To button expectations → pill.
- Any screen tests asserting `From`/`To` button labels (grep `find.text('From')` / `'To'` in `test/`).

---

## 10. Validation (definition of done)

- `flutter analyze` — 0 issues.
- `flutter test` — full suite green (updated + new tests).
- `server/`: `npm run typecheck`, `npm run lint`, `npm run test` (or the repo's equivalents — see `server/package.json`).
- Migration present for `user_preferences`.
- Manual: run the app; verify dashboard popover in light + dark, narrow-pane overflow, preset shift arrows, week-start toggle + Settings screen, default-range persistence across restart, reconciliation single-date mode. (browser-use/webapp-testing if a web build is used.)

---

## 11. Explicitly out of scope

- Ruler strip (decision #12).
- RTL layout mirroring (decision #15 — Urdu keeps LTR layout; text localized only).
- The `paper/brass/teal` palette (decision #5).
- Changing `pickDate` / form-dialog single-date pickers.
- Mobile bottom-sheet presentation (decision #13 — overlay overflow instead).

## 12. Resolved open questions (locked)

All three open questions from the original draft were resolved with the user on 2026-08-13:

1. **Week-start scope → extend to `period=week` too.** The dashboard Sales Summary / Expense Summary blocks (`period=week`) become calendar weeks aligned to the saved `week_start`, computed server-side (§6.3). All other rolling-N-day queries stay as-is. No other week-based features exist in the app (the chart, production status, and stock movement are all rolling windows).
2. **List defaults → follow the saved default range.** All six list screens (sales, quotations, expenses, sales orders, invoice returns) **and** the activity log seed their From/To from the saved default range (initially “This week”), identical to report screens. They open pre-filtered by default; “All dates” is still available via the preset + clear icon.
3. **File layout → rename + new file.** `date_picker_helpers.dart` becomes `date_picker.dart` (only `pickDate`; all imports updated) and the new widget lives in `date_range_picker.dart`. Test files renamed accordingly.

No further open questions remain.
