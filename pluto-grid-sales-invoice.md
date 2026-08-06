# PROMPT — Replicate the MiniERP `/sales/invoice` page in Flutter with PlutoGrid (AG-Grid-style keyboard navigation)

You are a senior Flutter engineer working in the MiniERP project. Your task is to replicate ONE page — the classic **sales invoice creation/edit page** at `http://localhost:3010/sales/invoice` (the non-V2 page) — as a **desktop Flutter screen** using **PlutoGrid**, with cell keyboard navigation that matches this app's AG-Grid navigation style **exactly**.

This is NOT the invoice V2 page (`/sales/invoice-v2`). Do not use `useInvoiceV2Keyboard.ts` or the V2 components. The classic page is the spec.

---

## 1. Context & prerequisites

- Repo: `/home/fawad/ai/minierp`. Backend: Node/Express/SQLite at `server/` — **do NOT modify it**. The Flutter app talks to it over HTTP (`http://localhost:3011/api`).
- Start the server if not running: `cd server && node dist/server.js` (port 3011). Login: `admin` / `admin123` (returns JWT as an httpOnly cookie named `token`; the Flutter app must login via `POST /api/auth/login`, receive the cookie via a cookie jar, and send it on every request — replicate what `client/src/utils/api.ts` does; treat the API base as `http://localhost:3011/api`).
- The web app runs on port 3010 — open `http://localhost:3010/sales/invoice` in a browser and **use it interactively as the reference behavior**.
- Flutter project: create it in this repo (e.g. `flutter_app/` or follow the existing scaffold if one exists). Desktop target only. State management: Riverpod. HTTP: dio + cookie jar. Grid: **PlutoGrid** (`pluto_grid` package).
- This is a desktop-only feature. No mobile UI, no responsive breakpoints, no mobile wizard — those are explicitly out of scope.

## 2. Source-of-truth files — READ THESE FIRST

All are inside the repo. The ones marked (kit) are also bundled in `flutter-migration-kit/` if the original path is unavailable:

1. `client/src/pages/sales/SalesInvoicePage.tsx` (kit: `flutter-migration-kit/references/pages/sales/`) — page state machine, submit, edit-mode loading, keyboard shortcuts, price-history trigger, focus management
2. `client/src/components/invoice/InvoiceItemsTable.tsx` (kit: `flutter-migration-kit/references/components/invoice/`) — grid structure, columns, cells wiring, totals row, price-hint overlay
3. `client/src/components/shared/GenericSearchableCell.tsx` (kit) — item search cell: dropdown filtering, selection, keyboard rules
4. `client/src/components/shared/GenericEditableCell.tsx` (kit) — numeric/text cell: edit mode, save-on-nav, **the core navigation rules**
5. `client/src/utils/focusCell.ts` (kit: `references/utils/focusCell.ts`) — focus management/race suppression; replicate the *behavior* (focus new cell input, select text), not the DOM
6. `client/src/components/invoice/InvoiceFormHeader.tsx` (kit) — header: customer search, invoice no, status, notes/terms, submit button
7. `client/src/components/invoice/InvoicePaymentPanel.tsx` (kit) — payment section: record-payment toggle, methods, existing payments
8. `client/src/components/invoice/PriceHistoryHint.tsx` + `KeyboardShortcutsHelp.tsx` (kit)
9. `client/src/utils/invoiceCalculations.ts` (kit: `flutter-migration-kit/calculations/invoiceCalculations.ts` + `invoiceCalculations.test.ts`) — `FIELD_ORDER_ITEM = ['description','quantity','rate','discountValue','tax','amount']`, `FIELD_ORDER_INVOICE = ['description','quantity','rate','tax','amount']`, `getFieldOrder`, `getNextField`, `calculateItemTotal/Tax/Discount/Total`, `generateInvoiceNo`, `padItemsToMinimum`, `createDefaultInvoice`
10. `client/src/utils/invoiceLineCalc.ts` (kit: `calculations/invoiceLineCalc.ts`) — `applyLineFieldUpdate` (packed/loose driver-field logic) and `lineIssue`
11. `client/src/utils/invoiceRules.ts` (kit: `calculations/invoiceRules.ts`) — `filterFilledItems`, `isValidPaymentAmount`, `doesPaymentExceedBalance`, `preparePaymentData`, `validateInvoiceSubmission`
12. `client/src/schemas/validation-schemas.ts` (kit: `schemas/validation-schemas.ts`) — invoice zod schema → port as Dart validators (same messages)
13. `client/src/types` invoice types (kit: `types/client-types.ts`) — `InvoiceFormState`, `InvoiceFormItem`, `PriceHintState`, `InvoiceSubmitData`
14. `client/src/pages/sales/SalesInvoicePage.css` + `styles/global.css` — visual layout (dense table, two-column split, dropdown styling)

## 3. Screen anatomy (must match)

```
┌─ Header bar ───────────────────────────────────────────────────┐
│ Back | New Invoice        Customer [searchable select]         │
│ Invoice No [auto] | Status | Notes | Terms | [Save/Update]     │
├─ Line Items header ────────────────────────────────────────────┤
│ "Line Items" + shortcuts help | Discount: ( ) Invoice ( ) Item │
│ Invoice Date [date] | Due Date [date] | [+ Add Item]           │
├─ LEFT: items grid (PlutoGrid)      ── RIGHT: payment panel ────┤
│ # | Description | Qty | Rate |    │ Record payment [toggle]    │
│   [Disc %] | Tax % | Amount | 🗑   │ Payment date | Notes       │
│                                   │ Methods: method/amount/ref │
│ [+ new empty row at bottom]       │ [+ Add method] [Record]    │
│                                   │ Existing payments list     │
│ Totals: Subtotal, Discount, Tax,  │ (edit/delete, edit mode)   │
│ Total                              │                            │
└────────────────────────────────────────────────────────────────┘
```

- The **discount column exists only when discount scope = Per Item** (columns: description, quantity, rate, discountValue, tax, amount). Invoice scope = 5 editable columns (no discountValue column).
- Packed items: amount column is READ-ONLY (computed). Loose items (`sale_type === 'loose'`): amount is editable; `lineIssue(item)` shows a warning/error line under the cell when qty×rate ≠ amount (severity error → red, warning → amber).
- Unit-of-measure badge next to quantity when not editing (`unit_of_measure`).
- The grid always keeps at least one empty row at the bottom (pad-to-minimum on load/edit).
- Two-column split: items grid left, payment panel right (desktop layout; no stacking).

## 4. Data & API contract (replicate exactly)

- Load on mount (new invoice): `GET /api/customers` (all, for search), `GET /api/inventory/items?limit=500` (all items — the searchable cell filters CLIENT-side), `GET /api/settings` (company name/email/phone/address/tax_id → invoice header), `GET /api/payment-terms` if shown.
- Customer select: on selection also call `GET /api/customers/:id/balance` → store `customer_current_balance`, `customer_credit_limit`, utilization %. **After customer selection, auto-focus the first row's description cell.**
- Edit mode (`/sales/invoice/:id/edit`): `GET /api/invoices/:id` (+ `GET /api/customers/:id/balance`, `GET /api/customers/:id`, `GET /api/invoices/:id/payments`), map items, pad to minimum, load existing payments.
- Price history: when a **rate** cell enters edit mode and item_id + customer_id are set, call `GET /api/sales/item-customer-history?item_id=:id&customer_id=:id`; if `transaction_count > 0` show the price-hint overlay (past prices, lowest, count) anchored under the rate cell; click-outside closes.
- Save (create): `POST /api/invoices` with `{ invoice_no, customer_id, invoice_date, due_date, total_amount, discount_scope, discount_type, discount_value, notes, terms, items: [{ item_id, description, quantity, unit_price, tax_rate, discount_type, discount_value }], record_payment?, payment: { payment_date, amount, payment_method, reference_no, notes } }` — only include `record_payment/payment` when the toggle is on. Update: `PUT /api/invoices/:id` (+ `status` from current, `deleted_payments` list when payments were removed).
- Record payment button: validates amount > 0 and ≤ remaining balance, then `POST /api/invoices/:id/payments` per method (sequentially for multiple methods).
- Validation (client-side, before submit): zod schema — required customer_id, invoice_date, due_date; at least one filled item (item_id set); item quantity > 0, rate ≥ 0, discount value ≥ 0, tax 0–100; show the same error messages (port from `validation-schemas.ts`). Show toast-style feedback for all errors (use the app's toast pattern).

## 5. THE KEYBOARD NAVIGATION SPEC — the core requirement

This is the AG-Grid-style navigation of this app. PlutoGrid's default behavior is NOT this — you must implement it. Read `GenericSearchableCell.tsx`, `GenericEditableCell.tsx` and `focusCell.ts` carefully and reproduce the following **exact** rules:

### 5.1 Model
- The grid is a matrix: rows = invoice items (stable `id` per row), columns = the field order for the current discount scope (see §2.9).
- Each cell has two modes: **display** (shows value, focusable, click/Enter/F2 enters edit) and **edit** (text/number input, value selected on focus).
- One cell can be in edit mode at a time, tracked as `<rowId>-<field>`.
- **Committing** a cell = persist its temp value to the item state + leave edit mode. Navigation ALWAYS commits the current cell first (except Escape, which reverts).
- Moving between cells must preserve the input value in-flight, commit it, focus the target cell's input and **select its text**.
- Rapid key presses must not race: a stale navigation must be discarded (the React code uses a navigation token + double rAF — replicate the same guarantee in Flutter with microtask/timer sequencing).

### 5.2 Arrow keys in EDIT mode
- **ArrowUp**: commit, move to the SAME column in the previous row. If that column doesn't exist in the target row (e.g. `amount` on a packed row), walk the field order forward and land on the first navigable column of that row. At the first row: do nothing.
- **ArrowDown**: commit, move to the SAME column in the next row (same column-walk fallback). At the last row: **do nothing** — only Enter creates a new row.
- **ArrowLeft/ArrowRight**: move to the previous/next column in the field order, skipping columns that don't exist (packed `amount`, item-scope-only `discountValue`).
  - For **number** cells: always navigate (no caret exists).
  - For **text** cells: only navigate when the caret is at position 0 (left) / at the end (right) — otherwise let the caret move.
  - ArrowLeft from the FIRST column: commit, then move to the previous row's LAST navigable column (the code implements this as row-up, keep the same observable behavior). ArrowRight from the LAST column: do nothing (stay editing).
- **Ctrl+ArrowUp / Ctrl+ArrowDown** (number cells only: quantity, rate, tax, discountValue): increment/decrement by 1; clamp: tax ≤ 100; values never below 0. Never used for navigation.

### 5.3 Enter / Tab / Escape
- **Enter** (edit mode): commit. If editing the LAST row → **append a new empty row and focus its description cell** (input selected). Otherwise move down (same as ArrowDown).
- **Tab** (edit mode): commit, move to the next field in the field order (`getNextField`); at the end of the row: if last row → append a new row and focus its description; else move to the next row's first field.
- **Escape**: revert the temp value, exit edit mode, do NOT move.

### 5.4 Display mode (cell focused, not editing)
- **Enter**: enter edit mode for the cell (value selected).
- **ArrowDown/ArrowUp**: move focus to the same column of the next/previous row (no commit needed).
- **ArrowRight**: enter edit mode of the next field; **Tab**: same; at last row's last field, Tab appends a new row.

### 5.5 The item-search (description) cell
- Entering edit mode opens a **dropdown** of searchable items after ~50 ms.
- Item pool: items where `is_finished_good === true` OR `is_purchased === true` (raw materials excluded).
- Typing filters by `item_name` OR `item_code`, case-insensitive substring. Empty input shows first 10 items.
- Dropdown option shows: item_name (bold), item_code, `Stock: <current_stock>`, formatted `standard_selling_price`. Highlighted row scrolls into view.
- **ArrowDown/ArrowUp** move the highlight (wrap around). **Enter/Tab** select the highlighted item → sets item_id, description=item_name, rate=standard_selling_price, sale_type, unit_of_measure, qty_decimal_precision, rounding_step, amount=0 — then **moves to the quantity cell**. **Escape** closes the dropdown (stays editing). Click selects + moves to quantity.
- If the typed text doesn't match anything: show "No products found", Enter commits the free text as description.
- Blur commits the highlighted selection (or closes the dropdown) — but never when navigation is in progress.

### 5.6 Row-level behaviors
- New rows appear at the bottom with the description cell focused/selected.
- Clicking any cell enters edit mode. Clicking a display cell's trash button removes the row (confirm not required).
- While editing the rate cell, the price-history hint may appear (see §4) — must not steal focus.
- Row serial numbers (1..n) update automatically when rows are added/removed.

## 6. Calculations (port 1:1, don't re-derive)

Port `invoiceCalculations.ts` (+ its tests), `invoiceLineCalc.ts` (driver-field logic: editing quantity or rate recomputes amount for packed lines; editing amount on loose lines recomputes rate — `applyLineFieldUpdate` is the exact rule), and `invoiceRules.ts` to Dart with the same test cases (keep test parity — these encode edge behavior like tax-after-discount precedence and rounding).

## 7. PlutoGrid implementation guidance

PlutoGrid does not ship this navigation model. Practical approach:
- Use PlutoGrid in **edit mode** for cells; set `gridKey` and attach a **`GridKeyListener`** (or wrap the grid in a `Focus` + `KeyboardListener` with `onKeyEvent`) to intercept arrows/Enter/Tab/Escape **before** PlutoGrid's own handlers, implementing §5.
- Column definitions: `#` (read-only), Description (custom cell renderer with search dropdown overlay), Qty (number), Rate (number), Discount (scope-dependent), Tax %, Amount (read-only for packed / editable for loose), delete (read-only action).
- For the description dropdown use an overlay positioned below the cell (same anchoring as the web app).
- Suppress PlutoGrid's default arrow navigation for editable cells so your rules run; keep its read-only list behaviors (column resize, header sort) untouched.
- Row identity: keep PlutoGrid row `key` = stable item id; when the items list changes (add/remove/scope switch), rebuild rows while preserving editing state semantics.
- Focus race protection: a navigation token + `Timer.run`/`Future.delayed` sequencing mirroring `focusCell.ts`; blur during navigation must not commit twice or lose the new cell.

## 8. Out of scope (do NOT build)

- The V2 invoice page and `useInvoiceV2Keyboard.ts`
- Mobile views, compact cards, responsive breakpoints, PWA
- Backend changes of any kind
- POS, quotations, sales orders, returns — only this page
- PDF/thermal printing (that's a separate task)

## 9. Acceptance criteria

1. Screen opens at `/sales/invoice` (new) and `/sales/invoice/:id/edit` (edit) with header, items grid, payment panel, totals.
2. Every keyboard rule in §5 works identically to the web app when exercised side by side (run the web app on 3010 and compare keystroke by keystroke).
3. Selecting an item from the search dropdown populates item_id/description/rate/uom and moves focus to Qty.
4. Packed lines compute amount from qty×rate after discount/tax; loose lines accept a typed amount and show lineIssue warnings on mismatch.
5. Price history hint appears on rate edit when history exists, with click-outside close.
6. Discount scope radio switches columns (discount column appears/disappears) and recalculates totals.
7. Save posts the exact payload shape of §4 (verify with the server's response — invoice created, stock movement + customer ledger updated server-side; verify in DB or via GET /api/invoices/:id).
8. Record payment validates amount ≤ balance and posts the payment; edit mode lists/edits/deletes existing payments.
9. Validation errors match the web app messages; toasts shown; no silent failures.
10. Ctrl+ArrowUp/Down steppers, Enter-at-last-row adds rows, Escape reverts — all matching §5.

## 10. Verification (must run, evidence required)

- `dart analyze` clean; your ported calculation tests green.
- Run the app against the live server; create an invoice end-to-end with keyboard only (Alt+I add item → search → Enter → qty → Enter → rate → Enter → … → save) and confirm the invoice appears in `GET /api/invoices`.
- Compare navigation behavior against `http://localhost:3010/sales/invoice` (web) — walk the matrix: arrows across columns/rows, last-row Enter, caret-position ArrowLeft/Right in text cells, Escape revert, Tab wrap, dropdown arrows/Enter/Escape.
- Report which behaviors match and any deviation with justification.
