# Invoice Form Layout Spec

**Request short name:** invoice-form-layout
**Status:** Approved (interviewed) — ready for implementation
**Scope:** `lib/features/sales/sales_invoice_form_page.dart` (+ `payment_panel.dart`, tests, docs)
**Applies to:** New sales invoice form (`/sales/form`, create **and** edit modes)

---

## 1. Goals

The user requested six concrete changes to the new invoice form's layout and defaults:

1. **Payment section beside the line items** — line items grid on the **left**, payment section on the **right**.
2. **Grid fills maximum available vertical space** — no more fixed 260px grid inside a page-wide scroll view.
3. **Save / Cancel (and Delete in edit mode) below the payment section** — in the right column, as a separate row beneath the payment panel.
4. **Discount scope defaults to Per Item** — the `DiscountScope.item` chip is selected by default for new invoices.
5. **Notes below the Subtotal / Tax % / Grand Total section** — notes field sits directly under the totals card.
6. **Status dropdown on the same row as Customer and the date pickers** — one header row: Customer | Invoice Date | Due Date | Status.

---

## 2. Current state (as-is)

Summarized from `sales_invoice_form_page.dart`:

| Aspect | Today |
|---|---|
| Page scroll | Whole form wrapped in `SingleChildScrollView` (one scroll unit) |
| Header rows | Row 1: Customer (flex 3) \| Invoice Date (flex 2) \| Due Date (flex 2). Row 2: Status dropdown (Expanded) \| discount-scope toggle (Expanded) |
| Grid | Fixed height `_gridHeight = 260` (`SizedBox(height: 260)`) |
| Under grid | Row: "Add item" button (left) + grand total text (right) |
| Split | `LayoutBuilder` at ≥720px: `Row [ Expanded(totals+grid), SizedBox(width: 330, PaymentPanel) ]`; below 720px: stacked `Column` |
| Totals card | Subtotal, Tax (computed), Discount row + invoice discount input **only in invoice scope**, Divider, Grand Total |
| Notes | Full-width field below the split, above the error banner and buttons |
| Buttons | Bottom row: Delete (edit only) \| spacer \| Cancel \| Save |
| Discount default | `DiscountScope.invoice` (create **and** edit-fallback) |
| Tax | Computed only from per-line `tax` rates (`calculateTax`); no invoice-level tax % field |

---

## 3. Target layout (to-be)

### 3.1 Wide screens (form width ≥ 720px) — fixed-height two-column layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ AppBar: title (+ Print A4 / Process Return in edit mode)                     │
├─────────────────────────────────────────────────────────────────────────────┤
│ Header row (no page scroll):                                                 │
│   [ Customer (flex 3) ] [ Invoice Date (flex 2) ] [ Due Date (flex 2) ]      │
│   [ Status (flex 2) ]                                                         │
├───────────────────────────────────┬─────────────────────────────────────────┤
│ LEFT COLUMN (Expanded)           │ RIGHT COLUMN (fixed 330px)               │
│                                   │                                         │
│  Items heading row:               │  Payment panel                           │
│   "Items" · [scope toggle] ·      │   (fills remaining column height;        │
│    [+ Add item]                   │    contents scroll internally)           │
│  Line-items grid                  │                                         │
│   (Expanded — fills all remaining │  Error banner (validation errors,        │
│    vertical space, min ~320px,    │   pinned above buttons)                  │
│    scrolls internally)            │                                         │
│  Totals card                      │  Buttons row (separate from panel):      │
│   Subtotal                        │   [Delete (edit)] [Cancel] [Save]        │
│   Discount (always visible)       │   — right-aligned                        │
│   Tax % input · Tax (computed)    │                                         │
│   Grand Total                     │                                         │
│  Notes field (below totals)       │                                         │
└───────────────────────────────────┴─────────────────────────────────────────┘
```

Key properties:

- The **outer page scroll is removed** on wide screens. The `body` is a fixed-height layout; the grid and the payment panel are the two elements that scroll internally.
- The left column is a `Column`: heading row (shrink), grid (`Expanded`, min height ~320px), totals card (shrink), notes (shrink).
- The right column is a `Column`: payment panel (`Expanded`, internal scroll), error banner (shrink, when present), buttons row (shrink, pinned at bottom).
- "Add item" button and the discount-scope toggle live on the **Items heading row** (top of the left column). The standalone "Grand total" text that currently sits next to "Add item" is **removed** (grand total now lives in the totals card).

**Short-window fallback (height):** the fixed-height layout must not overflow when the window is too short for heading + min-grid + totals + notes. When the available height cannot fit the left column's fixed sections (heading row + totals card + notes) **plus** the 320px min grid height, the **left column becomes vertically scrollable as a whole** (grid keeps its min height inside the scroll) — the right column behavior is unchanged. If this is undesirable, the alternative is dropping to the §3.2 stacked scrollable layout below a height threshold (e.g. 600px); choose one during implementation, defaulting to the left-column scroll.

### 3.2 Narrow screens (form width < 720px) — stacked scrollable layout

Current stacking behavior is kept, with the new ordering and the new header row:

```
Header row (wraps): Customer | Invoice Date | Due Date | Status
Items heading row: "Items" · [scope toggle] · [+ Add item]
Line-items grid (min ~320px height; page scrolls as before)
Totals card (Subtotal / Discount / Tax % · Tax / Grand Total)
Notes field
Payment panel
Error banner
Buttons row: [Delete (edit)] [Cancel] [Save]
```

The narrow layout keeps the page-level `SingleChildScrollView` (the grid keeps its min height here rather than expanding).

---

## 4. Section-by-section requirements

### 4.1 Header row (Customer / Dates / Status)

- **All four fields on one row**, replacing today's two rows.
  - Customer select (flex 3, unchanged `SearchableSelect<int>`, `autoOpen: !_isEdit`, Alt+C popup signal, customer→grid handoff all preserved).
  - Invoice Date (flex 2), Due Date (flex 2) — existing `_dateField` pickers.
  - **Status dropdown (flex 2)** — the existing `SearchableSelect<String>` over `_statusValues`, moved up from row 2 onto this row.
  - At widths near the 720px breakpoint the row is tight (long labels like "Partially Paid"). Use `Flexible`/ellipsis on the status select and allow the row to handle slightly constrained widths gracefully; the `ConstrainedBox(maxWidth: 1200)` and flex ratios above are the normal-case arrangement.
- Row 2 (status + scope toggle) is deleted.

### 4.2 Discount scope

- **Default = Per Item (`DiscountScope.item`)** for new invoices:
  - Change `DiscountScope _scope = DiscountScope.invoice;` default to `DiscountScope.item`.
  - **Edit mode honors the saved scope** (decided): initialize from the saved invoice — `invoice?.discountScope == 'item' ? DiscountScope.item : DiscountScope.invoice` (unchanged). Editing an invoice that used invoice-level discounting keeps its discount input and `discount_value` round-trips untouched — no risk of silently zeroing a real invoice-level discount on save.
- The **discount column** in the grid becomes **visible by default** (since `hideColumn` is only called when scope is invoice).
- Toggle placement: the **Invoice / Per-Item chips move to the Items heading row** (top of the left column / top of the stacked form), next to the "Items" label and "Add item" button. Suggested arrangement: `"Items" heading` on the left; `[scope toggle chips]` and `[+ Add item]` on the right.
- Toggle mechanics stay identical: `_setScope` hides/shows the discount column via `manager.hideColumn`, without rebuilding the grid.
- Switching to Invoice scope still reveals the invoice-level discount input inside the totals card (unchanged), and `_buildBody()` still sends `discount_scope` / `discount_type: 'flat'` / `discount_value` accordingly.

### 4.3 Main split & breakpoint

- Keep the **720px width breakpoint** (existing `LayoutBuilder` logic).
- Above it: fixed-height two-column layout (§3.1). Below it: stacked scrollable layout (§3.2).
- Payment column width stays **330px**.

### 4.4 Left column

1. **Items heading row** — "Items" label, discount-scope toggle, "Add item" button (moved up from below the grid).
2. **Line-items grid**
   - Fills **all remaining vertical space** (`Expanded` in the fixed layout), instead of `SizedBox(height: 260)`.
   - **Minimum height ≈ 320px** so it stays usable on short windows (raised from 260px).
   - Scrolls internally (PlutoGrid's native scrolling).
   - The grid's `SizedBox(height: _gridHeight)` wrapper is replaced by the expanded container; the loading placeholder keeps a sensible min height too.
3. **Totals card** (always rendered, contents per scope):
   - **Subtotal** row.
   - **Discount row — always visible.** Per-item scope: aggregate of line discounts (`calculateDiscount(items, DiscountScope.item, …)` — already returns the sum). Invoice scope: the invoice-level discount amount, with the invoice discount input shown beside/above it (unchanged from today).
   - **Tax % input + computed Tax row.** A new editable **Tax %** field in the totals card, alongside the existing computed Tax amount row.
     - *Semantics (decided — see §8.13):* the Tax % field **writes its parsed value to every filled line** (each line's `tax` cell), including an explicit `0` (clears the applied rate from all lines). An **empty** field is a no-op — per-line taxes as entered are respected until the field is used. The computed Tax row reflects the sum via the existing `calculateTax` path. New lines added afterwards default to 0 as today.
     - Rationale: zero changes to the calculation engine, API contract, or server schema (`tax_rate` stays per-item), and the displayed tax is always the truth used in the total.
   - **Grand Total** row (bold, unchanged).
4. **Notes field** — directly below the totals card (moved out of full-width position). Same `TextFormField` (`_notesController`, `maxLines: 2`, `submitOnEnter` contract untouched — multi-line keeps Enter = newline).

### 4.5 Right column

1. **Payment panel** (`PaymentPanel`, 330px)
   - Fills the available column height; **its content scrolls internally** when taller than the column (edit mode: payment history + form can exceed the viewport). Implementation: bound the panel's height (e.g. `Expanded` in the column) and wrap its body in a scroll view; the buttons stay pinned below.
   - All existing panel behavior unchanged: record-payment checkbox (create), payment date, per-method rows, payment history + edit/delete (edit), Record Payment button (edit), payment/balance summary, Shift+Enter → `focusFirstAmount`.
   - The edit-mode **Record Payment button scrolls with the panel body** (it is part of the panel content, reachable by scrolling) — it must not be pinned; only the page-level buttons row is pinned.
   - **Focus-into-view:** Shift+Enter (`focusFirstAmount`) and any payment-field focus must bring the focused field into view within the panel's internal scroll (existing `FocusNode` + `Scrollable.ensureVisible` semantics) so the shortcut still works when the panel is scrolled.
2. **Error banner** — validation/API error message, rendered **above the buttons row** (pinned, not scrolled), replacing its current position between notes and buttons. *(Decided — see §8.14.)*
   - **Auto-dismiss:** the banner **disappears automatically after 5 seconds** (decided via review follow-up). Implementation: a `Timer` in the page state that clears `_error` (→ banner hidden) after 5s; showing a new error while one is visible cancels the pending timer and restarts the 5s window; the timer is cancelled in `dispose()`. Re-triggering the same validation error (e.g. tapping Save again) restarts the window.
3. **Buttons row** — a **separate row below the payment panel** (not inside the panel card), right-aligned:
   - Edit mode: **Delete** (outlined, error color) then Cancel then Save.
   - Create mode: Cancel then Save.
   - Existing enabled/disabled + spinner behavior for `_submitting` preserved.

### 4.6 Grand total text cleanup

The "Grand total: …" `Text` that currently sits in the row beneath the grid (next to "Add item") is **removed** — the totals card is now the single source of that display.

---

## 5. Behaviors that must be preserved (invariants)

These are existing, tested behaviors — the layout change must not regress them:

- **Global shortcuts** (spec `docs/invoice-form-keyboard-spec.md` §7): Alt+C (customer popup), Shift+Enter (focus first payment amount), Ctrl+S (save), Ctrl+P (save + print). Registered on `HardwareKeyboard`; must keep firing while a grid cell editor holds focus.
- **Grid interaction model**: single-cell edit, arrow/Enter/Tab/Escape navigation (`GridNavController`), customer→grid focus handoff, item search dropdown, loose-line amount editing, price-history hint on rate edit, and the **edit-mode first-row focus on load** (`_maybeFocusFirstRow` — focus jumps to the first row's description cell once the grid is loaded).
- **Calculation engine** (`invoice_calculations.dart`): `calculateSubtotal` / `calculateTax` / `calculateDiscount` / `calculateTotal` untouched.
- **API contract** (`_buildBody`): unchanged shape — `invoice_no` (create), `customer_id`, `invoice_date`, `due_date`, `status`, `discount_scope`, `discount_type`, `discount_value`, `items[]`, `total_amount`, `notes`, `deleted_payments` (edit). Only the **default `discount_scope`** changes for new invoices (`'item'` instead of `'invoice'`).
- **Payment posting**: create mode posts methods after invoice save; edit mode records immediately via panel button.
- **Create default "Record payment now" checked** with one Cash method row — unchanged.

---

## 6. Affected files

| File | Change |
|---|---|
| `lib/features/sales/sales_invoice_form_page.dart` | Main layout restructure: header row merge, fixed-height split, grid expand, totals/notes re-parenting, buttons into right column, scope default flip, remove grand-total-under-grid, remove `_gridHeight` fixed height (keep min), error banner relocation |
| `lib/features/sales/payment_panel.dart` | Make the panel content internally scrollable within a bounded height (edit mode overflow) — otherwise presentational behavior unchanged |
| `test/sales_invoice_form_page_test.dart` | Add new create-mode default-scope coverage (see §7); no existing assertions need changing |
| `docs/invoice-form-keyboard-spec.md` | Optional: note the new header-row/shortcut layout unchanged |

---

## 7. Test impact

Verified during implementation (37/37 form tests pass):

- `test/sales_invoice_form_page_test.dart` — the `'discount scope: …'` test **pumps create mode** and asserted the old invoice-scope default, so it **was updated**: it now asserts per-item is selected by default, the discount column is visible by default, and the Per-Item `ChoiceChip.selected` is true; it still verifies Invoice scope hides the column and Per Item reveals it. Coverage for the create-mode default (spec §7 items a–b) lives in this test.
- The `'Ctrl+S commits the in-flight cell before saving'` create-mode test now also asserts the body sends `discount_scope: 'item'` and `discount_value: 0` (spec §7 item c).
- Five keyboard-walk / arrow-boundary tests relied on the old invoice-scope default (hidden discount column → `qty → rate → tax` Tab order, and an unambiguous `find.text('0')` tax tap). Each now taps the **Invoice** chip first to pin the walk; the per-item default otherwise inserts a discount cell into the walk.
- `'grid-click while the customer popup is open …'` — in the fixed layout the popup's option list covers the first row's **left** cells, so the test now taps an **amount cell** (right of the popup list, under the full-screen barrier) to keep its intent: a barrier-swallowed grid click closes the popup without entering a cell.
- The `discount_scope: 'invoice'` assertions in `test/widget_test.dart`, `test/repositories/repositories_test.dart`, and `test/models_test.dart` are **server-fixture/repository tests** and were confirmed unaffected.
- Run `flutter analyze` and `flutter test` (at minimum `test/sales_invoice_form_page_test.dart` + `test/widget_test.dart`) after implementing.

---

## 8. Assumptions & decisions (made during interview)

1. **Fixed-height layout** on wide screens — outer page scroll removed; grid + payment panel are the internal-scroll regions. *(Interview: Round 1 Q1)*
2. **Totals + Notes live in the left column**, under the grid. *(Round 1 Q2)*
3. **720px breakpoint kept**; below it the form stacks and scrolls as today. *(Round 1 Q3)*
4. **All three buttons (Save / Delete / Cancel) below the payment section in the right column, as a separate row** — not inside the panel card. *(Round 2 Q1 custom answer + Q2)*
5. **Payment panel stays 330px** wide. *(Round 2 Q3)*
6. **Payment panel scrolls internally** when taller than the column; buttons stay pinned below. *(Round 2 Q4)*
7. **Scope toggle lives on the Items heading row**, above the grid. *(Round 3 Q1)*
8. **Discount row always visible in the totals card** (aggregate of line discounts in per-item mode). *(Round 3 Q2)*
9. **Editable Tax % input added to the totals card** in addition to the computed Tax row. *(Round 3 Q3)*
10. **"Add item" button above the grid** (Items heading row). *(Round 3 Q4)*
11. **Grid minimum height ≈ 320px.** *(Round 3 Q5)*
12. **Edit mode initializes scope from the saved invoice** — the per-item default applies to **new invoices only** (resolved via interview follow-up; option "Honor saved scope" chosen). Rationale: forcing per-item in edit mode would hide the invoice-level discount input and `_buildBody()` would then send `discount_value: 0` on save, silently wiping a real invoice-level discount.
13. **Tax % field semantics: per-line (client-side)** — resolved via interview follow-up (option "Per-line (client-side)" chosen). The field **writes its parsed value to all filled lines' existing `tax` cells** — including an explicit `0` (clears the applied rate; this was an implementation-review fix, since a `rate <= 0` early-return made the field unable to undo its own application). An **empty** field is a no-op, so untouched per-line values are respected. The computed Tax row and grand total are derived from those lines through the existing `calculateTax` path. No calculation-engine, API, or server-schema changes. The alternative (a true invoice-level tax field on the `invoices` table) was considered and rejected for this change: it would require a DB migration, server model/controller changes, GL tax-payable posting changes, tax-summary report changes, and PDF changes — out of scope for a form-layout task.
14. **Error banner: right column, pinned above the buttons, auto-dismissing after 5 seconds** (resolved via review follow-up; custom answer — placement "Right column, above buttons" plus "show for 5 seconds and then disappear"). Always visible next to Save/Cancel while shown; a `Timer` clears `_error` after 5s (restarted on re-trigger, cancelled on `dispose`).

## 8b. Review fixes (gap closure)

Applied during the pre-implementation review:

1. **Test impact corrected (§7):** verified no form test pumps create mode; the line-507 discount test is edit-mode with an invoice-scope fixture and keeps passing. Spec now requests new create-mode default-scope coverage instead of changing existing assertions.
2. **Short-window fallback added (§3.1):** fixed-height layout must not overflow; default is the left column scrolling as a whole below the fit threshold, with the stacked-height-threshold alternative noted.
3. **Record Payment button + focus-into-view (§4.5):** panel-body button scrolls with content; Shift+Enter/payment focus must scroll the target field into view inside the panel.
4. **Header-row tight widths (§4.1):** status select must tolerate constrained widths near the 720px breakpoint (Flexible/ellipsis).
5. **Error banner decided (§4.5/§8.14):** right column, pinned above the buttons, **auto-dismissing after 5 seconds** (Timer-based; re-trigger restarts the window; cancelled on dispose).

End-to-end consistency review (pre-implementation):

6. **§6 aligned with §7:** the affected-files table no longer claims existing default-scope assertions need updating — it now says new create-mode coverage only. *(Later corrected again during implementation — see §8b.9.)*
7. **§5 invariant added:** edit-mode first-row focus on load (`_maybeFocusFirstRow`) listed with the other grid behaviors to preserve.

Implementation-time adjustments:

8. **Test-impact analysis corrected (§7):** the earlier "no create-mode pump exists" claim was wrong — the discount-scope test **is** create mode and asserted the old default. It was updated (not just extended), along with the five keyboard-walk tests and the grid-click test (see §7).
9. **Buttons row wraps:** Delete + Cancel + Save overflow the 330px right column in edit mode, so `_buildButtonsRow` uses a `Wrap(alignment: end)` instead of a `Row` — the trio wraps when tight instead of overflowing.
10. **Popup/grid overlap:** in the fixed layout the auto-opened customer popup's option list covers the first row's left cells while open (transient — the popup is dismissed on select/Escape). Accepted as-is; no form change needed.

## 9. Out of scope

- Calculation-engine changes (`invoice_calculations.dart`, `invoice_line_calc.dart`) — none intended.
- Server/API schema changes — none (tax % handled client-side per §4.4/§8.13).
- Payment panel feature changes (methods, history, posting) — layout/scroll only.
- Other forms (quotations, sales orders, purchase orders) — invoice form only.
