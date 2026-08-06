## Why

The classic `/sales/invoice` page — the app's core data-entry surface — is only partially ported. `lib/features/sales/sales_invoice_form_page.dart` already renders an editable PlutoGrid with create/edit/delete and DTO round-tripping, but it falls short of the web client's signature behavior: the AG-Grid-style keyboard navigation model, the in-cell item-search dropdown, the payment panel, price-history hints, and item-scope discounts. Desktop power users run this screen almost entirely from the keyboard; without the matching navigation rules the port feels alien next to the reference app.

## What Changes

**Upgrade `sales_invoice_form_page.dart` (and its supporting models/repos) to match the `pluto-grid-sales-invoice.md` reference spec — not greenfield, a completion of the existing grid form.**

New capabilities / behaviors being added:
- **AG-Grid keyboard navigation** replacing PlutoGrid's default key handling (arrow commit-and-move, caret-aware Left/Right in text cells, Ctrl+Arrow up/down steppers on number cells, Enter at last row appends a focused row, Tab wrap, Escape revert, display-mode navigation, stale-navigation race protection). No V2 keyboard hook — classic page rules only.
- **Item search cell** — in-cell dropdown (client-side filter over `item_name`/`item_code`, phantom-spaced pool of fins/hcs/finished/purchased goods, stock + selling price shown, wrap-around highlight, Enter/Tab select-and-move-to-Qty, Escape closes, blur-commit, "No products found" free-text fallback).
- **Drop-down of price-history hint** on rate-cell edit; click-outside close; must not steal focus.
- **Discount scope radio (Invoice vs Item)** — drops/adds the `discountValue` column and recalculates totals. Today the page hardcodes `'invoice'` scope.
- **Loose vs packed lines** — packed `amount` read-only (qty×rate after tax/discount); loose `amount` editable with `lineIssue` mismatch warnings (amber) / errors (red).
- **Payment panel** — record-payment toggle, payment date/notes, per-method rows, add/remove method, authorization amount≤remaining-balance, and existing-payment edit/delete/edit within invoice mode, using the server's `/invoices/:id/payments` + per-method POST.

Existing infrastructure kept as-is (NOT rewritten):
- PlutoGrid grid + `_GridLine` (`CalculableLine`/`FillableLine`) adapter
- Ported calc files + test parity (`invoice_calculations`, `invoice_line_calc`, `invoice_rules`)
- Route `/sales/form`, create/update/delete DTO shape, l10n keys

## Capabilities

### New Capabilities
- `sales-invoice-keyboard-nav`: Full AG-Grid-identical keyboard interaction across cells, rows, and editing modes.
- `sales-invoice-item-search`: In-cell item search dropdown with client filter and keyboard select.
- `sales-invoice-payment-panel`: Record-payment form, per-method entry, existing-payment edit/delete, balance authorization.
- `sales-invoice-discount-scope`: Invoice vs Item discount scope radio with dynamic discount column and recalculation.
- `sales-invoice-loose-lines`: Editable amount for loose lines with `lineIssue` indicators; read-only computed amount for packed lines.
- `sales-invoice-price-history`: Price-history hint overlay on rate edit, click-outside close.

### Modified Capabilities
- `sales-invoice-form`: The existing invoice form page gains the above as new behavior; no existing spec requirement changes (there are no main specs yet).

## Impact

**Code (Flutter):**
- `lib/features/sales/sales_invoice_form_page.dart` (887 → split), likely a new grid sub-widget for the keyboard nav + search cell + payment panel.
- `lib/features/sales/calculations/*.dart` — reuse only; minor additions for loose-line driver-field if the ported `applyLineFieldUpdate` already covers it (verify).
- New payment repository methods in `lib/data/repositories/invoice_repository.dart` (GET `/invoices/:id/payments`, POST `/invoices/:id/payments`).
- l10n additions in `lib/l10n/{en,ur}.arb` (many keys already present — payment, etc.).
- Tests: extend `test/sales_invoice_form_page_test.dart` + `test/calculations/*` with keyboard-nav, search-filter, payment, and lineIssue cases.

**Dependencies:** No new packages; `pluto_grid` already in use. Grid `GridKeyListener`/`onKeyEvent` may require verifying the installed pluto_grid version supports edge-event suppression.

**Non-API / internal:** No backend change. This is purely a client screen.

**Explicitly NOT done here:** V2 invoice page/hook, mobile views, POS/SO/quotes, PDF/thermal, backend edits.