# CODE-005 extraction verification

Execution is sequential. Existing accounting and UI changes are the baseline.
Root owns final full Flutter/CI verification. No commits are requested.

## 1. CSV builders and encoding (complete)

- Baseline scenario: original-import CSV builders, string sanitization, numeric signs, headers and report exports.
- Invocation: `flutter test test/core/csv_export_test.dart`.
- Binary observable: exit 0, `+25: All tests passed!`.
- Captured artifact: `build/audit-checks/code005-1-before.log`.
- Move: order builders into `csv_order_builders.dart`; sanitizer and generic encoder into `csv_encoding.dart`; the original entry point explicitly re-exports existing public functions.
- Existing documentation comments moved with their implementations; the encoder reference was renamed to match its new public helper name.

Post-extraction invocation: `flutter test --no-pub test/core/csv_export_test.dart`; exit 0, 25 passed in `build/audit-checks/code005-1-after.log`.
Edge invocation: `flutter test --no-pub test/core/csv_export_test.dart --name 'strips|empty|numeric'`; exit 0, 5 passed in `build/audit-checks/code005-1-edge.log`.
Focused analysis invocation: `dart analyze lib/core/utils/csv_export.dart lib/core/utils/csv_order_builders.dart lib/core/utils/csv_encoding.dart`; exit 0, no issues in `build/audit-checks/code005-1-focused-analyze.log`.
Full `flutter analyze --no-pub` found one root-owned purchase-form lint (subsequently fixed by root), captured in `build/audit-checks/code005-1-analyze.log`. Root authorized focused per-phase analysis and owns final whole-project checks.

## 2. Invoice layout (complete)

Added mounted public-page characterization in `test/sales_invoice_form_page_test.dart`, using a filled invoice and resizing across width/height boundaries.
Baseline invocation: `flutter test --no-pub test/sales_invoice_form_page_test.dart`.
Red observable: `invoice layout boundaries retain filled grid on resize` fails at 720 x 716 window with 279px horizontal and 56px vertical overflow before extraction. Artifact: `build/audit-checks/code005-2-before.log`.
The coordinator explicitly authorized fixing this discovered defect before extracting. The stacked layout now handles windows below 1100px width or 800px body height; compact heading composition wraps. Existing normal desktop layout and accounting calculations remain intact. Boundary checks retain the original failing dimensions and add the corrected thresholds.

The baseline suite finished with 60 passing tests and only the new resize regression failing. Targeted fix invocation: `flutter test --no-pub test/sales_invoice_form_page_test.dart --plain-name 'invoice layout boundaries retain filled grid on resize'`; exit 0, one test passed in `build/audit-checks/code005-2-responsive-green.log`.
Composition is now extracted into `lib/features/sales/widgets/invoice_form_layout.dart`; existing layout comments moved with the implementations. Post-extraction validation passed: `flutter analyze --no-pub` reports no issues.

## 3. Dashboard sales-versus-purchases panel (complete)

Characterization added first in `test/features/dashboard/sales_vs_purchases_panel_test.dart` (empty, sales-only and purchases-only zero-valued series, mounted through `DashboardScreen`).
Move: the panel plus its `DayBars`, `Bar` and `LegendDot` implementations moved together into `lib/features/dashboard/panels/sales_vs_purchases_panel.dart`; only `SalesVsPurchasesPanel` is public, the helpers stay private. The parent imports the module and constructs the public widget; `List<DayTotal>` inputs, the max-value fold, the minimum bar height, date ordering, the empty state, colours and constraints are unchanged.
Verification: `flutter test --no-pub test/features/dashboard/dashboard_layout_controller_test.dart test/features/dashboard/sales_vs_purchases_panel_test.dart` -> 18 passed. `flutter test --no-pub test/widget_test.dart --name "dashboard"` -> 8 passed. `flutter analyze --no-pub` -> no issues. `git diff --check` -> exit 0.

## 4. Date picker calendar widgets and focus state (complete)

Move: `CalendarHeader`, `MonthGrid` and `MonthGridState` moved into `lib/widgets/date_range_calendar.dart` as `DateRangeCalendarHeader`, `DateRangeMonthGrid` and `DateRangeMonthGridState`. All constructor fields, the `drp-day-YYYY-MM-DD` key strings, the per-cell `FocusNode` lifecycle, `requestFocusForDay`, arrow/Home/End/PageUp/PageDown handling and the localisation lookups are unchanged. The parent's `GlobalKey` generic types and construction sites were updated; popover, range/provider state, persistence and preset policy stayed in `date_range_picker.dart`.
Verification: `flutter test --no-pub test/widgets/date_range_picker_test.dart test/core/date_range_math_test.dart` -> 55 passed. `flutter test --no-pub test/widgets/date_range_picker_test.dart --name "Escape|discards|precedes|immediately|PageUp|dark"` -> 6 passed. `flutter analyze --no-pub` -> no issues. `git diff --check` -> exit 0.

## 5. Purchase order line editor with borrowed controllers (complete)

Characterization added first in `test/features/purchase_orders/purchase_order_line_row_test.dart`: last-row removal disabled, removal enabled and firing, removal disabled while submitting, input-tax rejection of negative and non-numeric values, required quantity/unit price, and expiry-control visibility driven by the selected item's `has_expiry`.
Move: the line rendering moved into `lib/features/purchase_orders/widgets/purchase_order_line_row.dart` as `PurchaseOrderLineRow`. It receives an explicit typed `List<Item>`, the selected item id, the borrowed quantity/price/tax controllers, the calculated amount, the expiry date, the submitting and removal flags, the line index and typed callbacks. The parent keeps `_PoLine`, controller disposal, the provider watch, `setState`, payment synchronisation and the date dialog. The validators and rendering are unchanged and the `po-input-tax-$index` key is preserved.
Verification: `flutter test --no-pub test/features/purchase_orders/purchase_order_tax_test.dart test/features/purchase_orders/purchase_order_line_row_test.dart` -> 9 passed. `flutter test --no-pub test/widget_test.dart --name "purchase order form:|purchase order: submit rejection"` -> 6 passed. `flutter analyze --no-pub` -> no issues. `git diff --check` -> exit 0.
A stale assertion was repaired here: `test/widget_test.dart` still expected the pre-input-tax PO create body, while the client (and the server's `purchase_order_items.input_tax_amount` column) now post `input_tax_amount`. The expectation was updated to the current schema; the production payload was not changed.

## 6. Invoice return quantity row and position preview (complete)

Characterization added first in `test/features/sales/invoice_return_views_test.dart`: batch-chip disclosure and its toggle callback, collapsed versus expanded batch/location breakdown, quantity edits reaching the parent, Enter-to-submit, over-quantity rejection, the 0.005 fee threshold on the position preview and the always-present returned/net/due rows.
Move: `ReturnLineRow` and `PositionPreview` moved into `lib/features/sales/widgets/invoice_return_views.dart` as `InvoiceReturnLineRow` and `InvoiceReturnPositionPreview`, keeping every typed parameter (`InvoiceItem`, `StockBatch` list, the borrowed controller, `InvoicePosition`), the autofocus flag, the Enter submission, the display rounding and the 0.005 fee threshold. The warehouse provider, settlement rows and drafts, fee and position calculation, validation, repository calls and submission stayed in the parent.
Verification: `flutter test --no-pub test/repositories/invoice_return_payload_test.dart test/features/sales/invoice_return_views_test.dart` -> 13 passed. `flutter test --no-pub test/widget_test.dart --name "invoice form: process return"` -> 3 passed. `flutter analyze --no-pub` -> no issues. `git diff --check` -> exit 0.
A second stale assertion was repaired here: `test/repositories/invoice_return_payload_test.dart` still expected `settlements` in the settle body, while the server reads `req.body.allocations` and the client now posts `allocations`. The expectation was updated to the wire contract the server actually consumes.

## 7. Supplier allocation row views (complete)

Characterization added first in `test/features/suppliers/supplier_payment_modal_test.dart` with a fake HTTP adapter: one PO (balance 600) plus one direct purchase (balance 400) against a total of 1000 post exact `po_allocations` and `purchase_allocations` arrays; an allocation line can be removed and re-added; auto-allocate fills the remaining amount from the PO balance; a seeded purchase survives an empty open-purchases response; and a rejected payment surfaces the server message.
Move: the four row views moved into `lib/features/suppliers/widgets/supplier_allocation_rows.dart` as `SupplierPoAllocationRow`, `SupplierAvailablePoRow`, `SupplierPurchaseAllocationRow` and `SupplierAvailablePurchaseRow`. They take the `PurchaseOrder`/`Purchase` model, the borrowed `TextEditingController` and typed callbacks instead of the parent's private `_Allocation`/`_PurchaseAllocation` holders. Allocation lists, controller creation and disposal, totals, allocation order, auto-allocation, the section empty/loading conditions (including `openPurchases.isEmpty && _purchaseAllocations.isEmpty`) and the submit logic stayed in the parent.
Verification: `flutter test --no-pub test/features/suppliers/supplier_payment_modal_test.dart` -> 5 passed. `flutter test --no-pub test/widget_test.dart --plain-name "supplier detail Record Payment modal posts PO allocations"` -> 1 passed. `flutter analyze --no-pub` -> no issues. `git diff --check` -> exit 0.

## Final state

All seven extractions are complete with their acceptance criteria and QA scenarios executed. `flutter analyze --no-pub` reports no issues and `git diff --check` exits 0 across the whole working tree. The full Flutter and server suites are run at phase completion by the root agent; no extraction-specific suite is left pending.
