# Date Range Picker — Implementation Tasks

Companion to `date-range-picker-spec.md` (all decisions locked). This file breaks the spec into **concrete, ordered tasks** with owners, touched files, deliverables, and acceptance criteria.

**Owners** (roles — assign to whoever picks each up):
- **Flutter** — Dart client code (`lib/`, `test/`)
- **Server** — Node/Express/TypeScript + SQLite (`server/src/`)
- **QA** — test authoring/updating for both layers
- **Docs** — API/spec updates

**Order rationale:** the pure-Date math and the server preferences store have no dependencies and unlock everything else; the picker widget is the biggest Flutter chunk and can be built against a stubbed preferences provider; rollout happens last, in two sub-waves so each swap is reviewable.

---

## Phase 0 — Date math foundation (no dependencies)

**T0.1 — Shared week/range date helpers** · Owner: Flutter · Pure Dart, no widgets.
- New file `lib/core/utils/date_range_math.dart` (pure functions, fully unit-testable):
  - `startOfWeek(DateTime day, WeekStart weekStart)` / `endOfWeek(...)` (Mon/Sat/Sun first)
  - `WeekStart` enum + `weekStartIndex` mapping (Mon=1, Sat=6, Sun=0)
  - Preset range builders: `today`, `yesterday`, `thisWeek`, `lastWeek`, `lastNDays(n)`, `thisMonth`, `lastMonth`, `customRange`
  - `shiftRange(from, to, PresetType, direction)` — the `‹ ›` shift math (§2.2/§5.4)
  - `PresetType` enum (`day | week | span | month | custom`)
- Acceptance: every function returns normalized local dates (no time component); week math correct across month/year boundaries; **QA** adds unit tests (spec §9.1) in `test/core/date_range_math_test.dart` before this phase is closed.

**T0.2 — Compact range text formatter** · Owner: Flutter.
- `Formatters.compactRange(DateTime from, DateTime to, {String locale})` implementing §2.1 rules (same-day / same-month / same-year / cross-year), plus `daysInRange()` for the hint pluralization.
- Acceptance: `Aug 13, 2026` / `Aug 7 – 13, 2026` / `Aug 7 – Sep 13, 2026` / `Aug 7, 2026 – Sep 13, 2027`; unit tests in `test/core/formatters_test.dart`.

**T0.3 — Week-start-aware server week math** · Owner: Server.
- Shared helper in `server/src/utils/weekMath.ts`: `weekBounds(todayISO, weekStart): { from, to }` — inclusive UTC ISO bounds of the week containing `todayISO` (internally the `(dow - weekStartIndex + 7) % 7` offset, per spec §6.3).
- Acceptance: `npm run typecheck`; small unit test for offset across boundaries.

> **Milestone M0:** date math is solid on both layers. Nothing else can proceed safely without it.

---

## Phase 1 — Server preferences store

**T1.1 — Migration** · Owner: Server.
- `server/src/migrations/add-user-preferences.sql`: `user_preferences` table (`user_id INTEGER PRIMARY KEY REFERENCES users(id)`, `week_start TEXT NOT NULL DEFAULT 'monday'`, `default_range TEXT` JSON or NULL, `presets TEXT NOT NULL DEFAULT '[]'` JSON, `updated_at`), plus an index if the PK isn't enough.
- Register in `server/src/config/database.ts` as a guarded block (pattern: `IF NOT EXISTS` / existence check before `db.exec`), consistent with the other migrations.
- Acceptance: server boots against an existing DB without error; fresh DB gets the table; rollback note in `server/src/migrations/rollbacks/`.

**T1.2 — Model + controller + routes** · Owner: Server.
- `server/src/models/UserPreferences.ts` (mirror `Settings.ts`): `getForUser(db, userId)` (returns server defaults in memory when no row exists — **no write-on-GET**; a row is only created by the first PUT), `updateForUser(db, userId, partial)` (merges partial onto current, single-statement upsert `ON CONFLICT(user_id)`; JSON fields stored as TEXT and parsed defensively). **Validation lives in the controller**, not the model (matches the codebase's controller-validates pattern).
- `server/src/controllers/preferencesController.ts` (mirror `settingsController.ts`): `getPreferences`, `updatePreferences` — read/write from `req.user.id`, structured `{success, data}` envelope; PUT validates `week_start` enum `['monday','saturday','sunday']`, `default_range` shape `{from,to}` ISO **with `from <= to`** (or explicit `null` to clear), `presets` array of `{id,name,from,to}` with non-empty **unique** ids and `from <= to`.
- `server/src/routes/preferences.ts`: `GET /` + `PUT /` guarded by `requirePermission('settings', 'read'|'update')` (matches the existing settings permission module) — confirmed during review.
- Mount in the app's route aggregator alongside the other route files.
- Acceptance: `npm run typecheck`, `npm run lint`; **QA** adds controller tests (spec §9.3): default-row backfill, partial update persists, per-user isolation, invalid enum/shape → 400, reversed-range + duplicate/empty preset id → 400, clear-null, 403 for a non-settings role.

**T1.3 — Week-aware `period=week` dashboard blocks** · Owner: Server. Depends on T1.1.
- `server/src/models/Dashboard.ts` `getSalesSummary`/`getExpenseSummary`: for `period === 'week'`, look up the requester's `week_start` (via `UserPreferences.getForUser`), compute `weekBounds` (T0.3), and filter with parameterized `date(...)` bounds. The dashboard controller passes `req.user.id` down.
- Keep `today`/`month` and all other rolling-N-day queries untouched.
- Acceptance: dashboard Sales/Expense Summary `week` blocks return the calendar week per saved start day (verified via controller tests with a seeded preference).

> **Milestone M1:** preferences are persisted and the `period=week` blocks are week-aware. Server side complete.

---

## Phase 2 — Flutter preference client

**T2.1 — Preference model + repository** · Owner: Flutter.
- `lib/data/models/user_preferences.dart` (mirror `Setting`): `UserPreferences { weekStart, defaultRange (from/to?), presets: List<UserPreset> }` + JSON parsing with the existing `asString`/`asNum` conventions.
- `lib/data/repositories/preferences_repository.dart` (+ `ApiEndpoints.preferences` in `lib/core/api/endpoints.dart`): `get()`, `update({weekStart, defaultRange, presets})` returning `ApiResult<UserPreferences>`.

**T2.2 — Providers + boot cache** · Owner: Flutter. Depends on T2.1.
- `lib/features/preferences/preference_providers.dart`:
  - `userPreferencesProvider` (FutureProvider, `GET /api/preferences`)
  - `weekStartProvider` (`StateProvider<WeekStart>`, seeded from cache) and `activeDefaultRangeProvider`
  - A small **synchronous cache** (`SharedPreferences` — already a dependency) so `StateProvider` initializers can read the week start / default range before the network resolves: `main()` preloads `SharedPreferences.getInstance()` + fires the server fetch; cache is the seed, server response wins on arrival (write-through per spec §6.2).
- Acceptance: providers expose current values synchronously at first read; changing week start or default range persists via `PUT /preferences` with a toast on failure.

> **Milestone M2:** the Flutter app can read and write preferences. The widget and the settings UI both consume this.

---

## Phase 3 — The picker widget

**T3.1 — Widget skeleton: pill bar + popover** · Owner: Flutter. Depends on M2.
- New `lib/widgets/date_range_picker.dart` with the **kept** `DateRangeFilter` class (drop-in params from spec §4.1 + new `mode`, `dateProvider`, `showAllDates`).
- Pill bar (`_PillBar`): `‹`/`›` arrows + calendar icon + range text + preset chip (localized, theme-aware), `StadiumBorder`, tooltips; clear icon beside the pill with the existing `onClear`/`showClear` contract (§4.3).
- Popover (`_RangePopover`): `CompositedTransformTarget` + `CompositedTransformFollower` inside `OverlayPortal`, positioned under the pill, clamped to window edges, content scrolls when the window is narrower (§4.2, decision #13). Barrier tap + `Escape` close.
- Acceptance: pill renders compact text + chip from the providers; popover opens/closes correctly; **QA** starts `test/widgets/date_range_picker_test.dart`.

**T3.2 — Dual-month calendar** · Owner: Flutter. Depends on T3.1 + T0.1.
- `_MonthPair`/`_MonthGrid`/`_DayCell`: two adjacent months, week-start-aware grids (from `weekStartProvider`), muted adjacent-month days, today outline, in-range fill, start/end pills; month-pair pager header `‹ Aug – Sep 2026 ›`; `lastDate` capped at today (§4.7).
- Selection state machine per §5.1 (instant apply, commit on end pick, swap on reverse, same-day = single day, discard on close).

**T3.3 — Presets sidebar + matching** · Owner: Flutter. Depends on T3.2.
- Preset list: `All dates` (only when `showAllDates`) → null providers; built-ins computed with active week start; **user-defined presets** from `UserPreferences` with ✕ remove + an `Add preset` affordance (name dialog, spec §6.2); `Custom` fallback.
- `matchPreset(from, to)` for the chip + active entry (§5.3); `shiftRange` wiring for the `‹ ›` arrows (§5.4, disabled on `All dates`).
- **Footer**: hint `Pick a start date` / `Pick an end date` / `N days selected`; week-start segmented control (`drpWeekStartsOn`); **Set as default range** action (spec §6.2).

**T3.4 — Single-date mode + keyboard nav** · Owner: Flutter. Depends on T3.3.
- `DateRangeMode.singleDate`: reduced presets (Today, Yesterday, This month, tap-a-day), pill shows `Formatters.date`, arrows shift ±1 day (§5.5).
- Full keyboard nav (§4.6): arrow-key day focus across month boundaries, Enter/Space select, PageUp/PageDown paging, Home/End, Escape returns focus to pill; `Semantics` labels per day; verify no clash with `screen_shortcuts.dart`.
- Acceptance: **QA** widget tests for both modes + keyboard (spec §9.2); dark-theme smoke test.

> **Milestone M3:** the widget is complete and testable in isolation against the preferences providers.

---

## Phase 4 — Rollout (swap + provider defaults + renames)

**T4.1 — Rename helpers file** · Owner: Flutter. (Do this first in the phase — it touches the most files.)
- `git mv lib/widgets/date_picker_helpers.dart lib/widgets/date_picker.dart`; keep only `pickDate` + doc; remove `DateRangeFilter`, `DateFilterButton`, `pickFilterDate`.
- Update **all** imports (`~19` screens + `~15` form dialogs + test files) from `date_picker_helpers.dart` → `date_picker.dart`.
- `git mv test/widgets/date_picker_helpers_test.dart test/widgets/date_picker_test.dart`; delete the `DateRangeFilter`/`DateFilterButton`/`pickFilterDate` test groups.
- Acceptance: `flutter analyze` clean.

**T4.2 — Provider default seeding** · Owner: Flutter. Depends on T2.2.
- `lib/features/reports/report_providers.dart`: seed `globalReportFromDateProvider`/`To` and all 13 report pairs from the saved default range, else `This week` (via T0.1) — replace `_monthsAgo` usage; keep `_reportRangePairs` + `applyGlobalReportRange`.
- List screens (`sales`, `sales_orders`, `quotations`, `expenses`, `invoice_returns`) + `activity_log_providers.dart`: null defaults → saved default range (decision Q2, spec §7.2).
- Acceptance: all screens open on `This week` (or saved default) on first launch; report/list `StateProvider` initializers read the cache synchronously.

**T4.3 — Swap the 19 call sites (wave A: dashboard + reports)** · Owner: Flutter.
- Dashboard (`dashboard_screen.dart`) keeps `onChanged → applyGlobalReportRange`.
- 12 report screens: `DateRangeFilter(..., showAllDates: false)`; drop any `width`/`height` args (audit per-site).
- Acceptance: reports filter correctly through the pill; `flutter analyze` clean.

**T4.4 — Swap the 6 list screens (wave B)** · Owner: Flutter.
- `sales_screen`, `sales_orders_screen`, `quotations_screen`, `expenses_screen`, `invoice_returns_screen`, `activity_log_screen`: pill with `showAllDates: true` (default); `onClear`/`showClear` preserved.
- Acceptance: "All dates" preset + clear icon restore the no-filter state and refetch.

**T4.5 — Single-date screen** · Owner: Flutter. Depends on T3.4.
- `cash_reconciliation_screen.dart`: replace `_pickDate` + its `pickDate` button with `DateRangeFilter(mode: singleDate, dateProvider: reportReconciliationDateProvider, ...)`.
- Acceptance: reconciliation date changes through the pill; existing screen behavior (single date → report refetch) unchanged.

> **Milestone M4:** the whole app runs on the new picker.

---

## Phase 5 — Settings screen + l10n

**T5.1 — Settings "Date & Range" section** · Owner: Flutter. Depends on T2.2.
- `lib/features/settings/settings_screen.dart` + `settings_providers.dart`: new grouped section with `Week starts on` (Mon/Sat/Sun segmented or radio) and a `Set current range as default` shortcut; write path via the preferences providers (spec §6.4); do **not** touch the company-profile settings endpoint.

**T5.2 — l10n keys** · Owner: Flutter. Depends on T3.x labels.
- Add all keys from spec §8 to `lib/l10n/en.arb` + `ur.arb` (camelCase, same names), then `flutter gen-l10n` (the project uses `generate: true` + `l10n.yaml`); regenerate `app_localizations*.dart`.
- Acceptance: no missing-key analyzer failures; Urdu labels render (RTL text, LTR layout per decision #15).

**T5.3 — API docs** · Owner: Docs.
- `docs/API.md`: document `GET/PUT /preferences` and the changed `period=week` semantics (§6.3).

> **Milestone M5:** feature-complete.

---

## Phase 6 — Hardening & validation

**T6.1 — Test pass** · Owner: QA. Covers T0.1–T5.1.
- New: `test/core/date_range_math_test.dart`, `test/core/formatters_test.dart` (compactRange), `test/widgets/date_range_picker_test.dart` (both modes + keyboard + dark theme), preferences provider tests.
- Updated: `test/widgets/date_picker_test.dart` (pickDate only), `test/widget_test.dart` (~L6020 From/To → pill), any screen tests asserting `From`/`To` labels.
- Server: preferences controller tests (T1.2) + `period=week` boundary tests (T1.3).

**T6.2 — Full validation** · Owner: Flutter + Server.
- `flutter analyze` → 0 issues; `flutter test` → green.
- `server/`: `npm run typecheck`, `npm run lint`, `npm run test` → green.
- Migration present for `user_preferences` (spec §10).

**T6.3 — Manual QA checklist** · Owner: QA (with Flutter/Server on call).
- Dashboard popover: light + dark; narrow-pane overflow; preset chips; `‹ ›` shift; week-start toggle; "Set as default range" persists across restart; "All dates" on a list screen; reconciliation single-date mode; Urdu locale sanity check.
- Follow-up: **code-reviewer pass** on the final diff before merge (AGENTS.md self-audit: no suppressed errors, no API drift).

---

## Risk & sequencing notes

- **T4.1 (rename) first within Phase 4** — it has the widest blast radius (~35 import sites); doing it before the swaps keeps the two changes separable in review.
- **T2.2 boot cache** is the trickiest Flutter piece (synchronous provider seeding vs async server preferences). Keep the contract explicit: *local cache = seed, server = truth*; if this slips, list screens could flash unfiltered data. Mitigation: seed `StateProvider`s from the cache, refetch from server on boot.
- **T1.3 requires `req.user` in the dashboard controller** — verify the controller's handler signature passes `AuthRequest`; if not, widen it (small, contained change).
- **Permission module for `/preferences`** — reuse `settings` module permissions unless review flags a better fit; no new permission entries unless required.
- **Shift arrows are clamped at today (decided during the Phase 0 review).** A forward shift that would make the range start after today is refused — the widget uses `shiftRangeClamped` (null → disable the › arrow). A range may still *contain* future days (This week ends Sunday).
- Everything in Phase 4+ depends on M3; phases 0–2 can proceed in parallel on separate branches if desired.
