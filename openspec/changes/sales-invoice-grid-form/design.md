## Context

The classic `/sales/invoice` page is the app's highest-frequency data-entry surface. The Flutter port already has a working PlutoGrid-based form (`lib/features/sales/sales_invoice_form_page.dart`, 887 lines) with create/edit/delete, an `_GridLine` adapter over the ported calc functions, and DTO round-tripping. What is missing is the web client's *interaction model*: the AG-Grid keyboard navigation, the in-cell item-search dropdown, the payment panel, price-history hints, and item-scope discounts. The reference spec is `pluto-grid-sales-invoice.md`; the source React files live in `references/` (e.g. `references/components/shared/GenericEditableCell.tsx`, `GenericSearchableCell.tsx`, `references/utils/focusCell.ts`, `references/pages/sales/SalesInvoicePage.tsx`). Calc layer (`invoice_calculations.dart`, `invoice_line_calc.dart`, `invoice_rules.dart`) is already ported with test parity. Backend is out of scope. The spec's cookie-jar auth preamble is stale — this repo uses Bearer-token auth (`PORTING.md`).

**Key constraint:** PlutoGrid does not ship this navigation model. §5 of the spec must be implemented on top of (and, for arrows/Enter/Tab/Escape, prior to) PlutoGrid's own key handling.

## Goals / Non-Goals

**Goals:**
- AG-Grid-equivalent keyboard nav (commit-and-move, caret-aware arrows, Ctrl+steppers, Enter-appends-row, Tab-wrap, Esc-revert, display-mode nav, race protection) over the item grid.
- In-cell item-search dropdown (client filter, ~50 ms open, keyboard select → move to Qty, escape close, free-text fallback).
- Discount scope radio (Invoice/Item) with dynamic discount column and recalculation.
- Loose vs packed lines (read-only computed amount vs editable amount with `lineIssue` indicators).
- Payment panel (record-payment toggle, per-method rows, existing-payment edit/delete, balance authorization).
- Price-history hint on rate edit, click-outside close.
- Reuse the already-ported calc layer; no backend changes; no new packages.

**Non-Goals:**
- V2 invoice page and `useInvoiceV2Keyboard.ts`.
- Mobile views, breakpoints, compact cards, PWA.
- POS / quotations / SO / returns.
- PDF/thermal printing.
- Backend modifications.
- Rewriting the existing grid/adapter or the calc layer.

## Decisions

**D1 — Intercept keys *before* PlutoGrid's handlers.** Wrap the grid in a `Focus` + `KeyboardListener` (or `GridKeyListener` with an early-return short-circuit) and implement §5 in a single key-event handler that `onKeyDown`-short-circuits arrows/Enter/Tab/Escape for editable cells, while PlutoGrid's own read-only behaviors (column header sort, resize) remain untouched (they don't use those subset of keys). 
- *Alt:* Rewriting PlutoGrid's navigation via its mode APIs. Rejected — too fragile across pluto_grid versions; a top-level interceptor is deterministic and matches how AG-Grid conceptually exposes these handles.

**D2 — Field-order as the single navigation source of truth.** Port `FIELD_ORDER_ITEM`/`FIELD_ORDER_INVOICE`, `getFieldOrder`, `getNextField` to Dart and drive every arrow/Tab decision from it, so scope changes (D6) automatically alter column-walk behavior. The `_GridLine` adapter already implements `CalculableLine`/`FillableLine`; keep that and add a per-row "navigable columns" predicate (skipping packed `amount`, and the discount col when absent).
- *Alt:* hard-code movement per column. Rejected — duplicates logic that already lives in `invoice_calculations`.

**D3 — Navigation sequencer with a token for race protection.** Mirror `focusCell.ts`'s double-rAF with a navigation token + `Timer.run`/`Future.delayed` sequencing. A new navigation invalidates the pending one; cell edit commit is idempotent (guarded so blur during a nav never commits twice). Edge selection uses `TextEditingController.selection` (select-all on enter) so the in-flight value is preserved and re-focused.

**D4 — Search dropdown as a per-cell renderer + repositioned `Overlay`.capture.** A custom cell renderer for the description column opens a `Overlay`/`CompositedTransform`-anchored result list positioned below the cell. Filtering is client-side over the 500-loaded items; the pool is fins/hcs/purchased-only items precomputed once. Highlight wrap, Enter/Tab selects → set item fields + immediate move-to-Qty (D1's handler).
- *Alt:* a modal picker (the existing `searchable_select.dart`) — rejected: loses in-cell anchoring and inline keyboard flow, which is the point of the classic page.

**D5 — Payment panel as a sibling panel bound to the same form state.** `GET /invoices/:id/payments` and per-method `POST /invoices/:id/payments` added to `InvoiceRepository`. Panel derives `remaining_balance` from A/R + recorded payments; authorization uses ported `isValidPaymentAmount`/`doesPaymentExceedBalance`/`preparePaymentData`. In edit mode, deletions accumulate a `deleted_payments` list folded into the update payload.

**D6 — Discount scope as state, not a hardcode.** Replace the current hardcoded `'invoice'` scope with a `DiscountScope` field (`model` already has the enum). Switching scope swaps the column set via D2's field order and recomputes totals through the existing `_GridLine` adapter.

**D7 — Loose-line handling.** The adapter already computes amount for packed lines; add an editable ("loose") path where `amount` writing routes through `applyLineFieldUpdate` to recompute `rate`, and a `lineIssue`-driven under-cell severity flag (error/warn) rendered by the custom amount cell. Add `unit_of_measure` badge on the quantity display.

**D8 — Price-history overlay.** Reuse the D4 overlay anchoring. Fetch `GET /sales/item-customer-history?item_id&customer_id` on rate-cell edit when item+customer present; if `transaction_count > 0` render past prices/lowest/count under the rate cell; dismiss on tap-outside via a route-level gesture barrier that does not steal grid focus.

## Risks / Trade-offs

- **[PlutoGrid swallows arrow keys in its internal editors]** → Mitigation: a `Focus` at the grid wrapper + `KeyboardListener` that inspects `RawKeyEvent.hardwareKeyboard` and returns early before PlutoGrid reaches its own action; verify with an interactive dev run across pluto_grid's installed major version (any of its editor focuses fire global key events we catch first).
- **[Race between PlutoGrid's blur (row deletion / `removeAllRows` while typing) and our edit-commit]** → Mitigation: `Timer.run`-sequenced commit with a token; commit is idempotent; deletion path bypasses commit for the removed row id (mirrors the `onChanged`-during-`dispose` guard already noted in the page header comment).
- **[The existing `.dart` file will grow large]** → Mitigation: split into a grid sub-widget (`_LinesGrid`) + payment panel widget + a small nav controller, while keeping the page's submit/load orchestration it now has. Keeps the diff reviewable.
- **[In-cell dropdown + keyboard + mouse on Linux desktop]** → Mitigation: over-anchor the overlay, use a `MouseRegion`dense row highlights; sample side-by-side against the reference on 3010 (the acceptance walk) for the most-used: type-ahead filter, Enter-down-to-Qty, and cross-rows arrows.
- **[Wall of behavioral parity from a giant reference doc]** → Mitigation: implement scenario-by-scenario against the specs (`specs/*`) and keep every scenario as a widget test in `test/sales_invoice_form_page_test.dart` so interactive parity is provable (AC #9/#10).

## Migration Plan

No backend or schema change. Flutter-only: implement within `lib/features/sales/`, extend `InvoiceRepository`, add l10n keys, add tests. Rollback = revert the feature-scale commit; the page keeps its existing grid form.

## Open Questions

- Does `pluto_grid`'s installed version let us Short-circuit arrow/Enter/Tab/Escape from a wrapper `KeyboardListener` before its internal editors, or do we need a fork/subclass of a single editor action? (resolve first — D1 detail).
- Exact `keys` for discounts in invoice-scope vs item-scope totals: confirm that the already-ported `invoice_calculations.dart` charts exactly the reference's tax-after-discount precedence (tests will confirm; adjust compute, not scope).
- `Deleted_payments` payload field: confirm `data/models/invoice.dart` `Invoice` already expects it, or add to the update body map only.