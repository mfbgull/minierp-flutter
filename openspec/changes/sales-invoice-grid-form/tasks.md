## 1. Discovery & Foundation

- [x] 1.1 Confirm `pluto_grid` version and that a wrapper `Focus`+`KeyboardListener` can short-circuit arrow/Enter/Tab/Escape before PlutoGrid's internal editors (D1); spike in a scratch test if needed.
- [x] 1.2 Read reference files in `references/` fully: `pages/sales/SalesInvoicePage.tsx`, `components/invoice/*`, `components/shared/GenericEditableCell.tsx`, `GenericSearchableCell.tsx`, `utils/focusCell.ts`; extract the exact field orders and nav predicates to port (D2).
- [x] 1.3 Port field-order constants/functions (`FIELD_ORDER_ITEM`, `FIELD_ORDER_INVOICE`, `getFieldOrder`, `getNextField`) to `lib/features/sales/calculations/invoice_calculations.dart` (verify what exists already); add unit parity to `test/calculations/invoice_calculations_test.dart`.
- [x] 1.4 Verify `applyLineFieldUpdate` (loose driver-field) and `lineIssue` already ported in `invoice_line_calc.dart`; add Dart test parity if missing. Confirm `invoice_rules.dart` coverage for `isValidPaymentAmount`, `doesPaymentExceedBalance`, `preparePaymentData`, `validateInvoiceSubmission`.

## 2. Keyboard navigation (spec: sales-invoice-keyboard-nav)

- [x] 2.1 Add a navigation controller (token + `Timer.run` sequencing) implementing the §5 model: item+field edit-mode single cell, commit-before-move, Escape-revert, race discard (D3).
- [x] 2.2 Wire the wrapper key interceptor for ArrowUp/Down/Left/Right, Ctrl+Arrow, Enter, Tab, Escape in edit mode incl. caret-preservation for text cells and column-walk fallback (D1/D2).
- [x] 2.3 Implement display-mode navigation (Enter→edit+select, ArrowUp/Down move, ArrowRight/Tab next-field, last-cell Tab appends row).
- [x] 2.4 Implement row append on last-row Enter with description focused/selected; Ctrl+Arrow steppers (clamp tax ≤ 100, ≥ 0).
- [x] 2.5 Ensure row serial numbers refresh and trash-button removal works from the keyboard path without double-commit.

## 3. Item search cell (spec: sales-invoice-item-search)

- [x] 3.1 Precompute the searchable item pool (finished_good or purchased) from the 500-loaded items once per screen open.
- [x] 3.2 Build the in-cell description renderer + overlay-anchored dropdown with ~50 ms open, client filter by name/code (case-insensitive substring), empty→first 10, "No products found" fallback.
- [x] 3.3 Implement highlight wrap, Enter/Tab select → populate item fields + amount=0 + move to quantity; Escape closes; blur commits (unless navigating).
- [x] 3.4 Keep mouse click select working and aligned with keyboard select.

## 4. Discount scope & loose lines (specs: discount-scope, loose-lines)

- [x] 4.1 Replace hardcoded `'invoice'` scope with `DiscountScope` state; add Invoice/Item radio control; switching swaps the discount column via field order and recomputes totals.
- [x] 4.2 Add editable `amount` path for loose lines (write → recompute rate via `applyLineFieldUpdate`); keep packed amount read-only.
- [x] 4.3 Render `lineIssue` severity indicator (error/warn) under the amount cell; add the unit-of-measure badge on quantity display.

## 5. Payment panel (spec: sales-invoice-payment-panel)

- [x] 5.1 Add `InvoiceRepository` methods: `GET /invoices/:id/payments`, `POST /invoices/:id/payments` (per-method).
- [x] 5.2 Build the payment panel: record-payment toggle, payment date/notes, per-method rows, add/remove method, Record button.
- [x] 5.3 Wire authorization (`amount > 0`, ≤ remaining balance via ported rules) with toast feedback; sequential posting for multiple methods.
- [x] 5.4 Edit mode: load existing payments, list with edit/delete; deletions accumulate `deleted_payments` in the update payload.

## 6. Price history (spec: sales-invoice-price-history)

- [x] 6.1 On rate-cell edit (item+customer present) fetch `GET /sales/item-customer-history`; if `transaction_count > 0` show anchored overlay (past prices/lowest/count) without stealing focus.
- [ ] 6.2 Add gesture-barrier click-outside close that does not steal grid focus.

## 7. Validation, i18n & integration

- [x] 7.1 Port invoice zod validation messages to Dart validators with toast feedback for all errors (no silent failures).
- [x] 7.2 Add any missing l10n keys to `lib/l10n/{en,ur}.arb` (reuse existing where present: payments/recordpayment, etc.).
- [x] 7.3 Split page into `_LinesGrid` + payment-panel sub-widgets if the file growth warrants (D-risks); keep `/sales/form` route + create/edit/delete orchestration intact.

## 8. Tests & verification

- [ ] 8.1 Extend `test/sales_invoice_form_page_test.dart` with scenario-per-spec widget tests (keyboard walk, search, payment, loose-line, scope, price-hint).
- [ ] 8.2 Port/confirm calc test parity for field-order, loose driver-field, lineIssue, payment rules.
- [ ] 8.3 `dart analyze` clean; run the app against the live server; create an invoice end-to-end keyboard-only (Alt+I add → search → Enter → qty → rate → … → save) and confirm it appears via `GET /api/invoices`.
- [ ] 8.4 Walk the reference matrix side-by-side against `http://localhost:3010/sales/invoice`; record which behaviors match and any deviation with justification.

---

## Port notes / deviations

- **6.1 price history:** the client fetch + `PriceHistoryHint` overlay are implemented, but the server has **no** `GET /sales/item-customer-history` route — the hint always degrades to "no hint" (404), so it cannot be seen end-to-end until the endpoint is added.
- **6.2 click-outside close:** the hint is `IgnorePointer` and removed when a rate edit commits/leaves; add an explicit gesture-barrier when the endpoint ships.
- **8.1/8.2/8.3:** existing tests updated (`Widget A` display) and `flutter analyze`/`flutter test` are clean (210 pass), but scenario-per-spec widget tests + the live-server keyboard e2e are not added here.
