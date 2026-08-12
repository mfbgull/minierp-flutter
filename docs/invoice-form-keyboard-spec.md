# Invoice Form — Keyboard & Focus Flow Spec

**Short name:** invoice-form-keyboard
**Status:** Draft — gathered from a 5-round interview with the product owner (2026-08-11)
**Files in scope (current implementation):**
- `lib/features/sales/sales_invoice_form_page.dart` — page, customer select, grid assembly
- `lib/features/sales/line_items_grid.dart` — `GridNavController`, `LineRowData`, `resolveTarget`
- `lib/features/sales/line_cells.dart` — `DescriptionCell` (item search), `LineCell`, `SerialCell`, `RemoveCell`
- `lib/features/sales/calculations/invoice_line_calc.dart` — packed/loose line math (`applyLineFieldUpdate`, `calcItemLine`, `lineIssue`)
- `lib/features/sales/models/sales_forms.dart` — `DiscountScope`, `EditedField`, line interfaces
- `lib/widgets/searchable_select.dart` — the customer dropdown widget
- `test/sales_invoice_form_page_test.dart` — existing widget tests (several will need updating)

---

## 1. Goal

Make the invoice creation form a fast, keyboard-driven data-entry surface:

1. **On load (create mode):** the customer field is focused and its search popup opens automatically.
2. **After a customer is selected:** focus jumps into the grid's first-row item (description) cell, **in edit mode, but with the dropdown closed**.
3. **Typing in the item cell** opens the item-search dropdown below the cell; the dropdown is navigable with ↑/↓; Enter (or Tab) selects the highlighted item.
4. **After an item is selected:** focus moves to the quantity cell in edit mode (pre-filled `1`, text selected).
5. **Arrow keys navigate the grid** cell by cell; each move commits the in-flight cell first.
6. **Loose items:** the amount (last) cell becomes editable; editing amount recalculates quantity. Packed items keep a read-only, computed amount.
7. **Global shortcuts:** Alt+C (customer), Shift+Enter (payments amount), Ctrl+S (save), Ctrl+P (save + print).

> **Baseline note:** a large part of the grid interaction (arrow navigation, item dropdown, loose amount math) already exists and is tested. The gaps are: customer auto-focus, the customer→grid handoff, open-dropdown-only-after-typing, requiring a real item match, the loose "flip" model, Shift+Tab, all-active-items pool, and the global shortcuts. The spec below describes the **complete target behavior** regardless of what exists today.

---

## 2. On-load focus flow

### 2.1 Create mode (no invoice passed)

- The **customer field is focused on load**, and its **search popup opens automatically** (the popup's filter TextField is focused so the user can type immediately).
  - Auto-open happens immediately on first frame — it does **not** wait for the customers list to finish loading. If the list is empty/loading, the popup shows "No results"/empty until data arrives (acceptable).
  - Implementation: `SearchableSelect` gains an opt-in `autoOpen` flag (or an exposed controller/GlobalKey the page calls after first build). This must not affect other uses of `SearchableSelect` (toolbar filters, status select, etc.).
- When the customer popup closes **without a selection** (Escape / outside tap), the field stays focused; nothing else changes.

### 2.2 Edit mode (invoice passed)

- **No customer auto-focus.** The customer is already set.
- After the line items finish loading, focus the **first row's item (description) cell directly in edit mode** (dropdown closed). If the invoice has no items (a single empty row), the same applies to that empty row.

### 2.3 Customer → grid handoff (both modes, any time the customer changes)

- Whenever a customer is **selected** (create: via popup; edit: changed via popup), focus moves to the **first row's item cell and enters edit mode** with the **dropdown closed** (it opens only when typing starts — §4).
- This applies even if rows already contain items (i.e. the user changed the customer mid-form).
- The page already rebuilds safely on customer select (`setState`); the handoff must be scheduled after that rebuild (post-frame / nav-token pattern).

---

## 3. Customer field behavior

- Uses the existing `SearchableSelect<int>` (customers provider `invoiceCustomersProvider`).
- Existing behavior is preserved: popup has a filter TextField on top, options below, ↑/↓ highlight, Enter/Tap select, Escape/outside closes.
- New: `autoOpen` on load (create mode) and via Alt+C (§7).
- Selection keeps writing `_customerId` and then triggers §2.3.
- Dismissal behavior is preserved and specified in §8 items 15–17: an outside click (including on the grid) closes the popup without passing the click through; Escape closes it and leaves the field focused; after typing, the first match is auto-highlighted and ↑/↓ navigate with wrap-around, Enter/Tab selects, and a no-match list makes arrows/Enter inert.

---

## 4. Item cell & the search dropdown

### 4.1 Edit-mode entry

- Entering edit mode on the description cell does **NOT** open the dropdown (removes the current ~50 ms auto-open timer behavior).
- The editor TextField is focused with the existing description text selected (as today).

### 4.2 Open-on-type

- The dropdown opens **only after the user types at least one character** — showing the matching items, or "No products found" when nothing matches (§4.4). (Removes the first-10-items auto-open.)
- Filtering: case-insensitive substring on `item_name` OR `item_code` (as today).
- If the typed text matches nothing: the dropdown panel shows "No products found" and **Enter and Tab are blocked** (§4.4).
- If the user deletes all text, the dropdown closes (no first-10-items fallback).
- The dropdown UI (bold name + code, "Stock: X", formatted selling price, highlight, scroll-into-view) stays as-is.
- If the item pool hasn't loaded yet when the user types, the dropdown shows "No products found"; it re-filters automatically once the pool arrives (§4.5).

### 4.3 Item pool — ALL active items

- Change `_searchPool` from `isFinishedGood || isPurchased` to **every active item** (raw materials included). "Active" = the item's active flag (default true).
- Pool is still loaded once via `invoiceItemsProvider` (`GET /inventory/items`); filtering stays client-side.

### 4.4 Selection rules

- **↑/↓** move the highlight (wrap around — as today). **Enter/Tab** select the highlighted item.
- **Escape** closes the dropdown, stays editing (as today).
- **No match + Enter/Tab → blocked.** Enter and Tab do nothing when the filtered list is empty ("No products found" stays visible); the cell keeps editing. (Change from today, where Enter/Tab committed the typed text as a free-form description.)
- **No free-text lines.** Unmatched typed text is never committed as a line: ArrowRight from the description cell is blocked until an item is selected, and navigating away via ↑/↓ (or Escape) **discards** the unmatched text, leaving the row item-less. The only exits from the cell are selecting an item (moves to qty), Escape (revert), or up/down navigation (discard + move). (Review fix — previously the spec was silent on Tab/navigation, and the old code committed free text.)
- **Item selection** writes the same defaults as today (`_onItemSelected`): `item_id`, `description = item_name`, `rate = standard_selling_price ?? standard_price ?? 0`, `tax = 0`, `quantity = 1`, `amount = 0`, `sale_type`, `unit_of_measure`, `qty_decimal_precision`, `rounding_step`, `discount_value = 0`, `discount_type = flat`, and resets the loose amount-driven flag (§5.3). Then focus moves to the **quantity cell in edit mode** ("1" selected).

### 4.5 Dropdown robustness

- **Rapid typing:** filtering runs synchronously per keystroke (no debounce) so arrow navigation stays deterministic. After every filter the highlight clamps to `[0, len-1]` and re-scrolls into view; if the list shrinks below the current highlight it is clamped (the wrap-around logic never indexes out of range). A fast Enter mid-frame is safe: filtering is synchronous, so `_selectedIndex` always refers to the just-filtered list by the time the next key event is processed.
- **Item pool loads after the dropdown opened:** if the user typed a query before `invoiceItemsProvider` resolved (pool empty → "No products found"), the description cell re-runs the last query automatically when `widget.items` changes (`didUpdateWidget`), refreshing the dropdown with matches and resetting the highlight to the first match (or "No products found" if still no match). No re-typing needed.
- **Duplicate selection:** the same item may appear on multiple lines — duplicates are allowed, and each line keeps independent rate/qty/amount/discount/flip state. Selection is idempotent: a double-Enter or double-tap cannot fire twice; once the overlay is closed the second activation is a no-op (guarded on `_open`).

---

## 5. Line math — packed vs loose

### 5.1 Packed items (unchanged)

- Amount is **read-only** and computed: `amount = qty × rate` (after per-line discount/tax in the totals layer, as today).
- Quantity edits recompute amount.

### 5.2 Loose items — "amount-driven once touched" flip model

This replaces the current per-edit `lastEditedField` behavior with a **sticky per-line flag**:

| State | Editing Quantity | Editing Amount |
|---|---|---|
| **Not flipped** (fresh loose line) | amount := qty × rate (qty drives, like packed) | **flip := true**, then qty := roundToStep(amount ÷ rate) |
| **Flipped** (amount was touched) | amount := qty × rate (qty stays editable, recomputes amount) | qty := roundToStep(amount ÷ rate) |

- "Flipped" means the line remembers that amount was edited at least once; from then on an amount edit always recomputes qty.
- Editing qty **never** un-flips the line; the flag is one-way within a line's lifetime.
- Rounding: reuse the existing `roundToStep` with `rounding_step ?? 10^-qty_decimal_precision` (unchanged).
- Error/warning display under the amount cell (`lineIssue`) stays.

### 5.3 Zero-rate rule

- When **rate ≤ 0** and the user edits the amount on a loose line: **the quantity wins** — the amount edit is accepted but qty is **not** recomputed (no division by zero), and no blocking error is raised. (Custom decision: no error banner in this case; `lineIssue`'s ZERO_RATE behavior may be relaxed or kept only for display parity — implementation detail, must not block entry.)
- The flip still happens (line becomes amount-driven) but qty stays put until a positive rate exists.

### 5.4 Flip reset

- The flag resets to "not flipped" **when the item in the row changes** (re-selecting a different item in the same row) and for any **newly added row**. A fresh item = fresh defaults.

### 5.5 Calculation-layer change

- Extend `applyLineFieldUpdate` / `calcItemLine` with an explicit `amountDriven` (bool) input instead of relying solely on `lastEditedField`, so the flip semantics live in the shared calc layer (keep the existing interface/test suite working; add new cases for the flip + zero-rate rules). A new hidden `PlutoCell` (e.g. `amount_driven`) is added to `_emptyCells()` in the page.

---

## 6. Grid keyboard navigation (target matrix)

All of these exist today except **Shift+Tab**; keep and verify the rest:

### 6.1 Edit mode

- **ArrowUp / ArrowDown:** commit current cell, move to same column of prev/next row (column-walk fallback if the column is absent — e.g. amount on a packed row). First/last row: **do nothing**.
- **ArrowLeft / ArrowRight:** commit, move to prev/next column in the field order, skipping non-navigable columns (packed amount; discountValue when scope = Invoice). Text cells respect caret position (only navigate at start/end). ArrowLeft from the first column wraps **up** to the previous row's same column (row-up — matching today's `resolveTarget` and the porting spec); at the first row it does nothing. At the last column ArrowRight does nothing (stays). (Review fix — the draft wrongly said ArrowLeft at the first column does nothing.)
- **Ctrl+ArrowUp / Ctrl+ArrowDown:** step ±1 on number cells (qty, rate, tax, discount); tax clamps ≤ 100; never below 0. Never navigates.
- **Enter:** commit; on the last row → append a new row and focus its description cell in edit mode; otherwise move down.
- **Tab:** commit, next field; end-of-row: last row → append + focus description; else next row's first navigable field.
- **Shift+Tab (NEW):** commit, previous field; start-of-row: previous row's last navigable field; first row first field → do nothing.
- **Escape:** revert in-flight value, exit edit mode, no move.

### 6.2 Display mode (cell focused, not editing)

- **Enter:** enter edit mode (value selected).
- **ArrowUp/ArrowDown:** move display focus same column prev/next row.
- **ArrowRight / Tab:** display-focus the next field (wrap to next row's first field at row end; appends at last row's last field — today's behavior).
- **Shift+Tab (NEW):** display-focus the previous field (wrap to previous row's last field).

### 6.3 Row behavior (unchanged)

- Always ≥ 1 empty row at the bottom; Add Item button appends; Enter-at-last-row appends; trash icon removes the row; serial numbers renumber.
- The grid keeps a single editing cell at a time; navigation commits before moving; the nav-token/Timer sequencing stays.

---

## 7. Global page shortcuts (NEW)

Captured on the whole page — **active even while a text field / cell editor is focused** (owner's decision; only these specific combinations are intercepted, plain typing is never affected).

| Shortcut | Action |
|---|---|
| **Alt+C** | Focus the customer field and open its search popup (keeps Ctrl+C = copy everywhere; chosen to avoid the copy conflict) |
| **Shift+Enter** | Commit any in-flight grid edit, ensure the "Record payment" checkbox is ON (turn it on if off), then focus the **first payment method's Amount field** |
| **Ctrl+S** | Same as the Save button (validate + create/update; toasts on failure) |
| **Ctrl+P** | Validate + save (create) or update (edit), then generate & print the A4 PDF from the saved invoice — i.e. "save and print". If validation fails, nothing is saved or printed |

Notes:
- Ctrl+S / Ctrl+P reuse `_submit()` / `_printInvoice()` paths; Ctrl+P = submit-then-print chained after a successful save.
- Alt+C must work in both modes (edit mode opens the customer popup for changing the customer; selecting a new customer triggers §2.3). Alt+C while the popup is already open re-focuses its filter (no-op reopen).
- Ctrl+S / Ctrl+P commit any in-flight grid edit first (`_nav.commitCurrent()`), so the cell being edited is included in the save — the Save button should do the same (§8.22).
- Shift+Enter focus detail: the in-flight grid edit is committed first; if "Record payment" must be flipped on, the focus request waits one frame for the panel to rebuild; the amount field is focused with its text selected; a default method row is always guaranteed (§8.20).
- Consider a small shortcuts-help hint on the page (e.g. under the line-items header) listing the new keys.

---

## 8. Edge cases

1. **Customer list still loading when the popup auto-opens** → popup shows no results; data appears when loaded (no crash, no stale overlay).
2. **Customer selected while the grid is mid-edit** → the in-flight cell is committed before the handoff to the first row.
3. **Row removed while it is the editing/display target** → stale targets dropped (already handled by `handleRowRemoved`).
4. **Packed line, discount scope = Invoice** → field order is qty → rate → tax → amount(read-only); ArrowRight from tax does nothing; discount column hidden.
5. **Discount scope = Item** → discount column exists and participates in the walk (unchanged).
6. **Loose line with qtyDecimalPrecision/roundingStep** → amount → qty uses the existing step rounding (unchanged).
7. **Item with no selling price (rate 0)** → loose flip allowed, qty not recomputed (§5.3); packed lines just bill qty × 0 = 0.
8. **Duplicate/empty typed text, then Enter** → blocked while "No products found" (§4.4).
9. **Alt+C pressed while a cell is being edited** → the cell's in-flight value is committed (blur/commit), then the customer popup opens.
10. **Shift+Enter with no payment methods** → create mode always has one default Cash row; if the list were empty (future), add a default row before focusing.
11. **Rapid typing in the item dropdown** → filter runs synchronously per keystroke; highlight clamped to `[0, len-1]` and scrolled into view after each filter; a shrunken list clamps the stale highlight; no debounce (§4.5).
12. **Item pool loads after the dropdown opened** (user typed before items resolved) → the cell re-filters the last query on `widget.items` change; matches appear without re-typing; highlight resets to the first match (§4.5).
13. **Duplicate item selection** → duplicates allowed across lines; each line independent; selection is idempotent (double-Enter/tap is a no-op) (§4.5).
14. **Saving with an empty-but-flipped loose line** (item selected, amount touched, derived qty = 0) → Save is blocked by the existing qty > 0 rule with the "Quantity must be greater than zero" error; the inline "Amount results in zero quantity" warning already flags the line. Consider wording the save error to hint at entering an amount for loose lines. A flipped line always has an item (flip only happens after item selection), and free-text lines no longer exist (§4.4), so a line without an item can never be flipped (§5.3, §4.4).
15. **Customer popup open + grid clicked** → the popup's full-screen barrier swallows the click and closes the popup (current `HitTestBehavior.opaque` barrier); the click does **not** pass through, so no grid cell is entered and nothing in the grid changes. No customer selected → no §2.3 handoff. Consequence of auto-open on load: a user who skips the customer search needs a second click to interact with the grid — predictable and acceptable; if it later feels slow, consider an opt-in click-through dismissal mode for the customer field only (decision point, not in scope now) (§3).
16. **Escape from the customer popup** → closes the popup without selecting anything; the customer field stays focused (trigger mode), ready to reopen with Enter/Space/Tap or Alt+C. No customer selected → no grid handoff. A second Escape is a no-op (popup already closed) (§3).
17. **Arrows in the customer popup after typing** → typing filters the list and auto-highlights the first match (`_selectedIndex = 0`, same model as the item dropdown); ↑/↓ move the highlight with wrap-around and scroll-into-view; Enter/Tab selects the highlighted option; when the filter matches nothing the list is empty, so ↑/↓ and Enter are inert (no highlight to move/select) and Escape still closes (§3).
18. **Items load late while the customer popup is open** → the item pool (`invoiceItemsProvider`) is independent of the customer popup's list, so the popup is unaffected — no crash, no stale list, and typing in the popup filters customers normally. If the user selects a customer before items arrive, the §2.3 handoff proceeds normally and the item cell shows "No products found" while typing until the pool resolves, then auto-refilters (§4.5). If items arrive while the popup is still open, the pool is simply ready whenever the handoff happens (§2.1, §4.2, §4.5).
19. **Selecting a customer with an empty grid vs a grid with rows** → the §2.3 handoff always targets the **first row's** description cell in edit mode, whether the grid holds only the initial empty row or already-filled rows (edit mode / mid-form customer change). If the first row already has an item/description, its text is **pre-selected** in the editor and typing replaces it; re-selecting an item resets the line's loose flip (§5.4); Escape reverts and leaves the row unchanged. The grid is guaranteed ≥ 1 row (pad-to-minimum); defensively, if the row list were empty the handoff appends an empty row before focusing. A filled first row must not disturb other rows (single editing cell, §6.3).
20. **Keyboard focus after Shift+Enter opens the payment panel** → sequence: commit any in-flight grid edit → in create mode, if "Record payment" is OFF, flip it ON (the panel rebuilds, so the amount field may not exist in the same frame — the focus request must wait one frame / post-frame) → ensure at least one payment-method row exists (append a default Cash row if the list were ever empty, §8.10) → focus the **first method's Amount field with its existing text selected** (typing replaces, matching the grid model). The page scrolls the field into view via standard focus behavior (works because the field is built and laid out). Pressing Shift+Enter again while already in the panel re-focuses the first amount field; afterwards Tab walks the panel's fields normally (§7, §8.10).
21. **No-match Tab & navigation** → Tab is blocked like Enter while "No products found" is shown; ArrowRight from the description cell is blocked until an item is selected; ↑/↓ navigation away discards the unmatched text — no free-text lines can ever reach the saved invoice (§4.4).
22. **Ctrl+S / Ctrl+P while a cell is being edited** → the in-flight cell is committed first (`_nav.commitCurrent()`), so the edit is included; the Save button should behave identically (§7).
23. **ArrowLeft from the first column** → wraps up to the previous row's same column (row-up); at the first row it does nothing (§6.1).
24. **Unmatched text + save** → unmatched typed text is discarded on navigation/Escape, so a submitted invoice never contains a free-text line with `item_id` 0 and only a description (§4.4, §8.21).

---

## 9. Out of scope

- Invoice V2 page, quotations, sales orders, returns, POS.
- Backend/API changes.
- Mobile layouts/responsive.
- Changing the price-history hint behavior on the rate cell (stays as-is).
- Changing existing Ctrl+C copy behavior (stays as-is everywhere).

---

## 10. Tests

Widget tests to add/update in `test/sales_invoice_form_page_test.dart` (and calc unit tests in `test/calculations/invoice_line_calc_test.dart`):

1. **Customer auto-focus:** create mode → customer popup is open on load, filter focused.
2. **Customer → grid handoff:** selecting a customer focuses the first row's description cell in edit mode with **no** dropdown open.
3. **Open-on-type:** entering the description cell does not open the dropdown; typing a character opens it; deleting all text closes it.
4. **No-match Enter blocked:** typing gibberish + Enter keeps the cell editing, does not commit free text.
5. **Shift+Tab:** walks to the previous cell in edit and display modes (including wrap to previous row's last field).
6. **Loose flip:** amount edit flips the line; subsequent qty edit recomputes amount; amount edit recomputes qty; flip persists across edits; **resets when the item is re-selected**.
7. **Zero rate:** amount edit on a loose line with rate 0 keeps qty unchanged, no blocking error.
8. **Alt+C / Shift+Enter / Ctrl+S / Ctrl+P** dispatch to the right handlers (focus customer popup / payment amount; save; save-then-print).
9. **Item pool:** a raw-material-only item (is_raw_material) now appears in the dropdown.
10. **Update existing tests** that assume the dropdown auto-opens on edit-mode entry (they must type first) and that Enter commits free text.
11. **Rapid typing:** enter a multi-character query in one `enterText` — highlight stays valid, no out-of-range index, dropdown shows matches.
12. **Pool late-load:** pump the form with the items provider unresolved, type in the description cell ("No products found"), then resolve the provider → matches appear without re-typing.
13. **Duplicate items:** select the same item on two lines → both persist independently; double-tap/Enter on an option doesn't double-fire.
14. **Empty flipped loose line:** flip a loose line (amount edit), then set amount/qty to 0 → Save shows the quantity error and does not submit.
15. **Popup + grid click:** auto-open the popup (create mode), tap a grid cell → popup closes, the grid cell is NOT in edit mode (no click-through), no customer selected.
16. **Escape from popup:** auto-open, press Escape → popup closed, customer field still focused, no selection, no grid handoff; Enter/Space reopens it.
17. **Arrows after typing:** open the popup, type a partial name → first match highlighted; ArrowDown/ArrowUp move the highlight (wrap); Enter selects; type gibberish → no matches → arrows/Enter inert, Escape closes.
18. **Items load while popup open:** auto-open the popup with the items provider unresolved; resolve items while the popup is open → popup still shows customers, no crash; then select a customer and type in the item cell → the pool filters correctly.
19. **Filled vs empty grid handoff:** (a) create mode — select a customer → the first row's empty description cell is in edit mode, dropdown closed; (b) pre-fill a row (edit mode), then select/change a customer → the first row's description is in edit mode with its text selected; typing replaces it; Escape leaves the row unchanged.
20. **Shift+Enter focus timing:** create mode with "Record payment" unchecked → Shift+Enter → checkbox turns on, the first Amount field is focused with text selected; with it checked → Shift+Enter directly focuses the field; verify the in-flight grid edit was committed first.
21. **No-match Tab blocked:** type gibberish → Tab keeps the cell editing, no free-text commit.
22. **No-match navigation discards:** type gibberish → ArrowDown moves to the next row and the typed text is NOT stored as a description (row stays item-less); the submitted body never contains a free-text line.
23. **ArrowLeft first-column wrap:** from a row's first editable cell, ArrowLeft moves up to the previous row's same column; at the first row it stays.
24. **Ctrl+S commits the in-flight cell:** type a value in the qty editor, press Ctrl+S without leaving the cell → the submitted body contains the new qty.

---

## 11. Acceptance criteria

1. On opening the new-invoice form, the customer popup is open and its filter is focused.
2. Selecting a customer puts the first line's item cell into edit mode (dropdown closed until typing).
3. Typing in the item cell filters all active items; ↑/↓ + Enter selects; no-match Enter is blocked; Escape closes.
4. Item selection → qty cell in edit mode with "1" selected; ArrowRight/Tab walk continues through rate → (discount if Item scope) → tax → amount.
5. Loose lines: amount editable, amount→qty recompute with rounding; flip persists and resets on item change; rate 0 keeps qty; packed amount read-only.
6. Shift+Tab navigates backward; Enter-at-last-row appends; Escape reverts.
7. Alt+C, Shift+Enter, Ctrl+S, Ctrl+P perform their actions from anywhere on the page, including inside cell editors.
8. `flutter analyze` clean; all updated/new widget + calc tests green.
9. Rapid typing, late-loading item pool, duplicate selections, and zero-quantity flipped loose lines behave as described in §4.5 / §8 (items 11–14).
10. Customer popup dismissal & keys behave as described in §8 (items 15–17): outside-click closes without click-through, Escape keeps the field focused, and ↑/↓ + Enter work over the filtered options.
11. Items-loading-during-popup, empty-vs-filled grid handoff, and Shift+Enter payment focus behave as described in §8 (items 18–20).
12. No-match cells cannot leak free-text lines (Enter/Tab/ArrowRight blocked, ↑/↓ navigation discards unmatched text), ArrowLeft wraps from the first column, and Ctrl+S/Ctrl+P commit the in-flight cell before saving (§4.4, §6.1, §7).

---

## 12. Interview decisions log

| # | Question | Decision |
|---|---|---|
| 1 | Customer field on load | Focus + **auto-open search popup** (immediately, not waiting for list load) |
| 2 | After customer select | First row item cell focused; **round 5 clarified: direct edit mode, dropdown closed** (supersedes the earlier "display mode" pick) |
| 3 | Edit mode focus | No customer auto-focus; **focus the grid's first item cell on load** |
| 4 | Dropdown timing | **Open only after typing** (removes auto-open on edit entry) |
| 5 | No-match Enter | **Blocked** — a real item is required |
| 6 | Qty default | Keep **1** (text selected) |
| 7 | Loose direction | **Flip model** — qty drives until the first amount edit, then amount-driven permanently for that line |
| 8 | Zero rate | **Quantity wins** — no qty recompute, no blocking error |
| 9 | Add-row keys | **Enter only** (ArrowDown at last row does nothing) |
| 10 | Tab keys | **Tab = next, Shift+Tab = prev** (both modes) |
| 11 | Packed last-cell wrap | **Do nothing** on ArrowRight/Tab from Tax |
| 12 | Ctrl+C conflict | Use **Alt+C** for customer (keep Ctrl+C = copy) |
| 13 | Shortcut scope | **Always active, even in editors** |
| 14 | Ctrl+P in create | **Save then print** |
| 15 | Shift+Enter target | **Ensure Record-payment on, then focus first payment Amount field** |
| 16 | Item pool | **All active items** (raw materials included) |
| 17 | Tests | **Yes — widget tests + calc tests**, plus the new shortcut keys |
| 18 | Current-state framing | **Untested — spec the whole flow end-to-end** |
| 19 | Rapid typing in the dropdown | Synchronous filtering per keystroke (no debounce); highlight clamped + scrolled after every filter (§4.5) |
| 20 | Pool loads after dropdown opened | Re-run the last query automatically when the pool arrives (§4.5) |
| 21 | Duplicate item selection | Allowed across lines; selection idempotent — no double-fire (§4.5) |
| 22 | Save with empty flipped loose line | Blocked by the qty > 0 validation; inline zero-quantity warning already flags it (§8) |
| 23 | Customer popup open + grid click | Popup closes on outside tap (opaque barrier); click does not pass through; no handoff; a second click interacts with the grid (§8.15) |
| 24 | Escape from customer popup | Closes the popup, field stays focused, no selection/handoff; Enter/Space reopens (§8.16) |
| 25 | Arrows in customer popup after typing | First match auto-highlighted; ↑/↓ wrap; Enter/Tab selects; no-match arrows/Enter inert (§8.17) |
| 26 | Items load while customer popup open | Popup unaffected (separate provider); grid covered by the pool late-load refilter (§8.18) |
| 27 | Customer select: empty vs filled grid | Handoff always targets the first row in edit mode; pre-selected text, typing replaces; pad-to-minimum guard (§8.19) |
| 28 | Shift+Enter focus after panel opens | Commit grid first; flip record-payment on; wait one frame for the rebuild; focus the first amount field with text selected; ≥1 method row guaranteed (§8.20) |
| 29 | No-match Tab / navigation | Tab blocked like Enter; ↑/↓ navigation discards unmatched text — no free-text lines (§4.4) |
| 30 | ArrowLeft from first column | Wraps up to the previous row's same column (matches current `resolveTarget`) (§6.1) |
| 31 | Ctrl+S / Ctrl+P with in-flight edit | Commit the in-flight cell first, like Shift+Enter and the Save button (§7, §8.22) |
| 32 | Dropdown opening condition | Opens on the first typed character, showing matches OR "No products found" (draft contradiction fixed) (§4.2) |

---

## 13. Spec vs current code — implementation diff list

Walk-through of the target spec against today's code (2026-08-11). Each row: where the code sits now, what conflicts, and the change needed. "✓ compliant" = already matches; no change.

### 13.1 `lib/widgets/searchable_select.dart`

| # | Spec ref | Current code | Conflict / change needed |
|---|---|---|---|
| S1 | §2.1, §3, §7 (Alt+C) | Popup opens only on tap / Enter / Space; no `autoOpen` param, no controller | **Missing API.** Add an opt-in `autoOpen` flag (or exposed controller/GlobalKey) so the page can open the customer popup after first frame (create mode) and from Alt+C. Must not affect other `SearchableSelect` usages (toolbar filters, status select, payment method rows) |

### 13.2 `lib/features/sales/sales_invoice_form_page.dart`

| # | Spec ref | Current code | Conflict / change needed |
|---|---|---|---|
| S2 | §2.1 | Customer `SearchableSelect<int>` never focused; no popup on load | **Missing.** Pass `autoOpen` in create mode; ensure it opens after first frame (post-frame or after customers provider first resolves) |
| S3 | §2.3 | `onChanged: (value) => setState(() => _customerId = value)` only | **Missing.** After selection: `_nav.commitCurrent()` (in-flight cell first, §8.2), then schedule the first row's description cell into **edit mode** via the nav-token/`Timer.run` pattern, guarded on the grid being loaded (`_gridStateManager != null`); if a customer is selected before the grid exists, defer the handoff until `onLoaded` |
| S4 | §2.2 | Edit mode loads lines via `_setLines`/`_loadInvoiceDetail`; no initial focus move | **Missing.** After items load AND grid `onLoaded`, focus the first row's description cell in edit mode (no dropdown). Note `_setLines` can run before `onLoaded`, so the focus must be queued until the grid exists |
| S5 | §4.3 | `_searchPool` filters `it.isFinishedGood \|\| it.isPurchased` | **Change.** Include **all active items** (raw materials too); respect the item's active flag |
| S6 | §7 | No page-level key handling; `_submit` and edit-mode `_printInvoice` exist | **Missing.** Add global combos Alt+C / Shift+Enter / Ctrl+S / Ctrl+P. **Key dispatch caveat:** grid cells' `FocusNode.onKeyEvent` returns `handled` for Enter/Tab/arrows, so a plain `CallbackShortcuts` wrapper will not see those combos. To honor "always active even in editors", register a `HardwareKeyboard.instance.addHandler` (runs before the focus chain) or thread the shortcut handler into the cells |
| S7 | §7 (Shift+Enter) | First payment Amount TextField lives inside `PaymentPanel`; page has no handle to it | **Missing plumbing.** Ensure `_recordPayment = true`, then focus the first method's amount field (see P1). Also: Shift+Enter must not trigger the cell-level Enter/append/select — handled by the global interceptor in S6 |
| S8 | §7 (Ctrl+P) | `_printInvoice` is edit-mode-only (reads `widget.invoice!`); print button renders only in edit AppBar | **Missing create path.** Ctrl+P = validate + save (create) or update (edit), then fetch the saved invoice and print. Refactor `_printInvoice` to accept the saved invoice id (works for both modes). Ctrl+S / Ctrl+P (and the Save button) must `_nav.commitCurrent()` before validating/submitting (§7, §8.22) |
| S9 | §5.5 | `_emptyCells()` has `last_edited` but no `amount_driven` cell | **Add.** Hidden `amount_driven` PlutoCell in `_emptyCells()`; reset it to false in `_onItemSelected` (item change = reset, §5.4) |

### 13.3 `lib/features/sales/line_items_grid.dart`

| # | Spec ref | Current code | Conflict / change needed |
|---|---|---|---|
| S10 | §6.1, §6.2 | `handleEditKey`/`handleDisplayKey` Tab cases fire on `LogicalKeyboardKey.tab` regardless of Shift → Shift+Tab = next field | **Missing Shift+Tab.** In the Tab branches check `HardwareKeyboard.instance.isShiftPressed`; Shift+Tab = commit + previous field (mirror `nextField()` with a `previousField()`; wrap to previous row's last navigable field; first-row-first-field → no-op). Apply to both edit and display modes |
| S11 | §5.5 | `LineRowData` derives `lastEditedField` from the `last_edited` cell; no `amountDriven` accessor | **Add.** `amountDriven` getter/setter over the new cell; include in `applyPatch`; pass into `CalcItemLineInput`/`applyLineFieldUpdate` from `_applyDriver` |
| S12 | §5.5 | `applyPatch` writes qty/amount/rate/lastEditedField only | **Change.** Also write `amountDriven` |
| S13 | §4.4 (minor) | `DescriptionCell` ArrowRight calls `moveToCell(row, quantity)` without committing in-flight description text | **Resolved in review.** ArrowRight (and Enter/Tab) from a description cell with no selected item are **blocked**; unmatched text is discarded on ↑/↓ navigation or Escape — no free-text lines (§4.4, §8.21) |

### 13.4 `lib/features/sales/line_cells.dart` (`DescriptionCell`)

| # | Spec ref | Current code | Conflict / change needed |
|---|---|---|---|
| S14 | §4.1 | `_scheduleOpenOnce()` + 50 ms `_openTimer` auto-open the dropdown on edit-mode entry | **Remove.** No auto-open on entry; dropdown appears only after typing |
| S15 | §4.2 | `_filter('')` → `pool.take(_initialLimit)` (first 10 items, empty query) | **Change.** Empty query → dropdown closed / no list |
| S16 | §4.4 | With `_filtered.isEmpty`, Enter falls through to `nav.commitEnterSearchable(...)` (commits free text) | **Change.** When no match, Enter is **blocked**: return `handled`, stay editing, keep "No products found" visible |
| S17 | §4.2, §4.5 | `_filtered` captured from `widget.items`; no re-filter when the pool arrives late | **Add.** `didUpdateWidget` — if editing with a non-empty query and `widget.items` changed, re-run `_filter(query)` (matches appear without re-typing; highlight resets to first match) |
| S18 | §4.5 | `_selectItem` fires `onItemSelected` unconditionally; double-tap/Enter can fire twice | **Add.** Idempotency guard (no-op once the overlay is closed / on `_open == false`) |
| S19 | §4.5 | `_filter` resets `_selectedIndex` to 0/-1 and `_scrollToSelected` scrolls; wrap uses modulo | ✓ compliant (reset-to-0 already prevents stale indices). Optional: explicit clamp for defense only |

### 13.5 `lib/features/sales/calculations/invoice_line_calc.dart`

| # | Spec ref | Current code | Conflict / change needed |
|---|---|---|---|
| S20 | §5.3 | `calcItemLine` returns `CalcItemLineError(zeroRate, error, 'Rate must be greater than 0')` on amount edit with rate ≤ 0; `lineIssue` renders it in red under the amount cell | **Change.** Rate ≤ 0 + amount edit → accept amount, **keep qty unchanged, no error** (qty wins, §5.3). Relax `calcItemLine` and `lineIssue` accordingly |
| S21 | §5.2, §5.5 | `applyLineFieldUpdate` uses per-edit `lastEditedField`; no sticky flip flag | **Note + change.** The flip model is behaviorally near-identical to last-edited-wins for qty/amount/rate sequences, so the main work is introducing the explicit `amountDriven` input (`CalcItemLineInput` + `applyLineFieldUpdate` + `calcItemLine`) for spec fidelity and wiring it through the grid (S11/S12). Existing calc tests must stay green; add flip + zero-rate cases |

### 13.6 `lib/features/sales/payment_panel.dart`

| # | Spec ref | Current code | Conflict / change needed |
|---|---|---|---|
| S22 | §7 (Shift+Enter) | Amount TextFields use private per-method `TextEditingController`s; no FocusNode/GlobalKey exposed | **Add.** Public focus hook for the first method's amount field (e.g. `GlobalKey<State>` + `focusFirstAmount()`, or a FocusNode passed into `_methodRow` and attached to the first amount TextField) |

### 13.7 Already compliant (no change)

- §6.1 arrows/Enter/Escape/Ctrl+arrows (incl. ArrowLeft first-column row-up wrap), §6.2 display-mode arrows/Enter/Tab, §6.3 row lifecycle + nav token → `GridNavController`/`resolveTarget` ✓
- §8.3 row-removed stale targets (`handleRowRemoved`) ✓
- §8.4 packed + Invoice scope (amount not navigable; ArrowRight no-op) ✓
- §8.5 Item-scope discount column ✓
- §8.6 loose step rounding (`roundToStep`) ✓
- §8.10 default Cash payment method row on create ✓
- §8.14 save blocked on qty ≤ 0 (`_submit` → `_invalidQuantityMessage`) ✓
- §5.4 flip reset on item change — already happens via `_onItemSelected` setting `lastEditedField = null` ✓ (keep once `amount_driven` replaces it)
- §8.15–17 customer popup outside-click / Escape / arrow-after-typing — already implemented in `SearchableSelect` (opaque outside-tap barrier closes without click-through, Escape closes and leaves the trigger focused, ↑/↓ wrap-around with first-match auto-highlight on type) ✓

### 13.8 Tests (`test/sales_invoice_form_page_test.dart`)

- **Break:** tests that tap `DescriptionCell` and expect the dropdown to auto-open (e.g. 'selecting an item closes the dropdown for good', 'item search: Escape…', 'item search: unmatched query…') must type first (spec §10.3/§10.10); the 'no-match Enter commits free text' assumption flips to blocked.
- **New:** spec §10 items 1–24 (customer auto-open, handoff, open-on-type, no-match block incl. Tab + navigation discard, Shift+Tab, loose flip + reset, zero rate, shortcuts incl. in-flight commit, all-active pool, rapid typing, pool late-load, duplicates, empty flipped line, popup click/Escape/arrows, items-loading-during-popup, filled-vs-empty grid handoff, Shift+Enter focus timing, ArrowLeft wrap) plus calc tests in `test/calculations/invoice_line_calc_test.dart` (flip persistence, zero-rate keeps qty).

### 13.9 New edge cases (§8.18–20) — implementation touchpoints

- §8.18 (items load while the customer popup is open): **no new code** — the customer popup is independent of the items provider; grid-side behavior is already covered by S17 (pool late-load refilter).
- §8.19 (empty vs filled grid handoff): S3/S4 must pre-select the first row's existing description text when entering edit mode, defensively pad-to-minimum if the row list is ever empty, and leave other rows untouched.
- §8.20 (Shift+Enter payment focus): S22's focus hook must (a) run **post-frame** when flipping `_recordPayment` (the amount field is not built in the same frame), (b) select the field's text on focus, and (c) rely on the guaranteed default Cash row (§8.10).
