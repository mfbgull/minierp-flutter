# CODE-005: Extract seven Flutter rendering and export responsibilities

## TL;DR
> Summary:      Move seven coherent view/export clusters into named modules, preserving current behavior and public imports. Verify each extraction before starting the next.
> For whom:     ERP operators keep their existing workflows; programmers gain smaller files and explicit component boundaries.
> Deliverables: Seven extracted modules/clusters; focused characterization where needed; baseline, incremental and final verification evidence.
> Effort:       Large
> Risk:         Medium - financial forms have live concurrent changes and state/focus ownership must survive moves.

## Scope
### Affected user and ideal state
**Affected user:** Operators currently use invoice, purchase-order, return, supplier-payment, dashboard and date-picker workflows; CSV consumers use the existing export import. Their behavior stays stable. Programmers currently navigate rendering/export clusters embedded in large files and will use separately named modules with typed inputs. This plan closes the seven agreed extraction boundaries; it does not claim that every large file becomes small.

| Row | Statement | Reason |
|-----|-----------|--------|
| IS-1 | CSV callers retain their imports and byte-equivalent exports; order formatting and shared encoding have named independent modules. | Preserve the affected workflow while making its responsibility independently navigable. |
| GAP-1 | Existing builders are pure but the order family and encoding implementation share the platform export module. | The extraction boundary is currently implicit; changes are harder to isolate. |
| IS-2 | Invoice entry retains layout, keyboard focus, values and submission while layout composition becomes independently readable. | Preserve the affected workflow while making its responsibility independently navigable. |
| GAP-2 | Responsive composition is embedded in the financial form state class. | The extraction boundary is currently implicit; changes are harder to isolate. |
| IS-3 | Dashboard users retain chart values, empty state and refresh behavior; maintainers can change the chart through its own module. | Preserve the affected workflow while making its responsibility independently navigable. |
| GAP-3 | The independent sales/purchase chart rendering cluster lives in the dashboard orchestration file. | The extraction boundary is currently implicit; changes are harder to isolate. |
| IS-4 | Date selection, keyboard navigation, preset state and accessibility keep working through the calendar module boundary. | Preserve the affected workflow while making its responsibility independently navigable. |
| GAP-4 | The picker contains both range coordination and an independent keyboard-aware calendar implementation. | The extraction boundary is currently implicit; changes are harder to isolate. |
| IS-5 | PO users retain tax, quantity, price, expiry and payment-total behavior; the line view has an explicit typed boundary. | Preserve the affected workflow while making its responsibility independently navigable. |
| GAP-5 | The PO line rendering method closes over form state and includes newly added input-tax UI. | The extraction boundary is currently implicit; changes are harder to isolate. |
| IS-6 | Return users retain quantities, batch detail and financial preview while leaf rendering lives outside submission orchestration. | Preserve the affected workflow while making its responsibility independently navigable. |
| GAP-6 | The return dialog already has independent private view classes but still stores them beside settlement orchestration. | The extraction boundary is currently implicit; changes are harder to isolate. |
| IS-7 | Supplier payment users retain mixed allocations, seeded purchases and errors while row rendering has typed, state-free inputs. | Preserve the affected workflow while making its responsibility independently navigable. |
| GAP-7 | PO/direct-purchase allocation leaf views share the modal with controller ownership and submission. | The extraction boundary is currently implicit; changes are harder to isolate. |

### Must have
- Use the latest working tree as baseline. The caller's accounting/new-UI changes are already present and are not refactor regressions.
- Characterize uncovered behavior before each move, then run existing mounted interaction tests. A newly discovered bug needs a failing regression before its separate fix.
- Preserve existing public exports, field keys, controller ownership, focus, localization, validation and API payloads.
- Read CODING_STANDARDS.md, docs/REVERSAL-RULES.md and audit/DECISIONS.md before execution. Audit context: audit/FINDINGS-STATUS.md:123 records CODE-005 as previously unscoped; the caller has now authorized these seven boundaries.

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No accounting, tax, fee, rounding, settlement, allocation or product behavior changes; no server/schema/API changes.
- No generated localization edits, dependencies, part files, blanket formatting, unrelated cleanup or artificial file-size targets.
- No reset, checkout, stash or whole-file restoration over other agents' work. Re-read target immediately before mutation; resolve ownership with the caller if it changed since baseline.
- No commits in this execution: none were requested. Commit descriptions below are reserved for later authorization.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: tests-before characterization with Flutter test/flutter_test; retain all existing tests. Red-before-green applies to defects, not a requirement to intentionally break a pure move.
- QA policy: every task has agent-executed scenarios, including mounted widgets driven by taps/typing/keys for UI behavior. Before extraction, new characterization tests mount existing public screens/dialogs and exercise the behavior being moved; they must not import nonexistent destination classes. After moving, keep those tests and add direct child assertions only where needed.
- Evidence: `<attemptDir>/task-<N>-<slug>.<ext>` — under ulw-loop, `<attemptDir>` is the `currentAttemptDir` from `omo-agent-toolkit ulw-loop status --json` (`.omo/evidence/ulw/<session>/<goalId>/a<attempt>`); outside ulw-loop use `.omo/evidence/`.
- Record command, exit status and untruncated test output in each evidence file. Before Task 1, capture `git status --short`, `git diff --stat` and baseline output using `flutter test test/core/csv_export_test.dart test/sales_invoice_form_page_test.dart test/widgets/date_range_picker_test.dart test/core/date_range_math_test.dart test/features/dashboard/dashboard_layout_controller_test.dart test/features/purchase_orders/purchase_order_tax_test.dart test/repositories/invoice_return_payload_test.dart`, `flutter test test/widget_test.dart --name "dashboard|purchase order form:|purchase order: submit rejection|invoice form: process return|supplier detail Record Payment modal posts PO allocations"`, plus `flutter analyze`. Reuse the caller's current-tree baseline evidence if those same checks already ran successfully. No coverage percentage is claimed.
- At each extraction checkpoint run `flutter analyze` and `git diff --check` in addition to task commands; all must pass before the next extraction. Diagnose baseline failures without weakening tests or overwriting another owner's edits.
- At final verification run `flutter test`, `flutter analyze` and `node scripts/l10n-drift.js`. This isolated refactor does not require rerunning the unchanged server suite; the caller's broader cross-stack audit must still run `scripts/check.sh` for its own final verification.

## Execution strategy
### Parallel execution waves
> Target 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Extract shared dependencies as Wave-1 tasks to maximize parallelism.

Explicit exception: the caller requires each extraction verified before the next, so implementation waves contain one atomic extraction each. Independent review in the final wave can run in parallel. This ordering avoids mixing regressions across seven financially sensitive screens and ongoing work.

Wave 1 (no dependencies):
- Task 1: Extract order CSV builders without changing import contracts; depends [].

Wave 2 (after Wave 1):
- Task 2: Extract invoice responsive layout composition; depends [1].

Wave 3 (after Wave 2):
- Task 3: Extract dashboard sales-versus-purchases panel; depends [2].

Wave 4 (after Wave 3):
- Task 4: Extract date picker calendar widgets and focus state; depends [3].

Wave 5 (after Wave 4):
- Task 5: Extract purchase order line editor with borrowed controllers; depends [4].

Wave 6 (after Wave 5):
- Task 6: Extract invoice return quantity row and position preview; depends [5].

Wave 7 (after Wave 6):
- Task 7: Extract supplier allocation row views; depends [6].

Critical path: Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 5 -> Task 6 -> Task 7

### Dependency matrix
| Task | Depends on | Blocks | Can parallelize with |
|------|------------|--------|----------------------|
| 1 | none | 2 | none (verification checkpoint) |
| 2 | 1 | 3 | none (verification checkpoint) |
| 3 | 2 | 4 | none (verification checkpoint) |
| 4 | 3 | 5 | none (verification checkpoint) |
| 5 | 4 | 6 | none (verification checkpoint) |
| 6 | 5 | 7 | none (verification checkpoint) |
| 7 | 6 | final review | none (verification checkpoint) |

## Todos
> Implementation + Test = ONE task. Never separate.
> Every task MUST have: References + Acceptance Criteria + QA Scenarios + Commit.

- [x] 1. Extract order CSV builders without changing import contracts

  What to do: Move buildSalesOrdersCsv, buildPurchaseOrdersCsv and buildQuotationsCsv into csv_order_builders.dart. Move sanitizeCsvCell and the existing generic grid encoder into csv_encoding.dart (rename the private encoder to buildGridCsv for cross-library use). Import the helper in both consumers. Re-export exactly the three builders and sanitizeCsvCell from csv_export.dart using show. Keep all existing signatures, headers, order, formatting, formula sanitization, numeric signs and saveCsv behavior. Do not export the new encoder from the compatibility entry point.
  Must NOT do: Change behavior, transfer controller ownership, modify another agent's hunks, or proceed before this task's checks pass.
  Closes: GAP-1

  Parallelization: Can parallel: NO | Wave 1 | Blocks: [2] | Blocked by: []

  References (executor has NO interview context - be exhaustive):
  - Pattern/API/Type: `lib/core/utils/csv_export.dart:105,244-327,1165-1170` — current implementation and constructor contracts to preserve; line numbers are discovery anchors and may shift with concurrent work.
  - Destination: `lib/core/utils/csv_order_builders.dart; lib/core/utils/csv_encoding.dart` — create these modules and update only their parent import/construction sites.
  - Test: `test/core/csv_export_test.dart:141-163,230-381` — existing assertions/fixture patterns; files marked new are created as part of this task.
  - External: none required; no framework/API migration or dependency change is planned.

  Acceptance criteria (agent-executable only):
  - [x] `flutter test test/core/csv_export_test.dart` exits 0 before extraction after characterization is added, and again after extraction.
  - [x] `flutter test test/core/csv_export_test.dart --name "strips|empty|numeric"` exits 0 before and after extraction.
  - [x] `flutter analyze` reports zero issues; `git diff --check` exits 0.
  - [x] Review `git diff -- lib/core/utils/csv_export.dart lib/core/utils/csv_order_builders.dart lib/core/utils/csv_encoding.dart`: responsibility is removed from parent, constructed/imported from destination, and no calculation/payload or unrelated hunks are altered.

  QA scenarios (MANDATORY - task incomplete without these):
  ```
  Scenario: csv happy path
    Tool:     bash
    Steps:    flutter test test/core/csv_export_test.dart
    Expected: All existing CSV tests pass through the original csv_export.dart import.
    Evidence: <attemptDir>/task-1-csv.txt

  Scenario: csv failure or edge
    Tool:     bash
    Steps:    flutter test test/core/csv_export_test.dart --name "strips|empty|numeric"
    Expected: Formula prefixes remain stripped, empty input keeps headers, and numeric negative values retain signs.
    Evidence: <attemptDir>/task-1-csv-error.txt
  ```

  Commit: NO | Message: `refactor(client): extract csv` | Files: [lib/core/utils/csv_export.dart, lib/core/utils/csv_order_builders.dart; lib/core/utils/csv_encoding.dart, task-specific tests]

- [x] 2. Extract invoice responsive layout composition

  What to do: Create InvoiceFormWideLayout and InvoiceFormNarrowLayout with typed Widget slot inputs plus nullable errorBanner and gridMinHeight. Replace only the two composition methods/calls. Keep breakpoint selection in the page (width >=720 and height >=660), grid minimum 320, payment column width 250, padding and child ordering. Controllers, providers, keys, grid instance and submit behavior remain owned by the page. Add mounted boundary characterization at 719/720 width and 659/660 height before moving code; resize a filled form and assert values and grid state survive.
  Must NOT do: Change behavior, transfer controller ownership, modify another agent's hunks, or proceed before this task's checks pass.
  Closes: GAP-2

  Parallelization: Can parallel: NO | Wave 2 | Blocks: [3] | Blocked by: [1]

  References (executor has NO interview context - be exhaustive):
  - Pattern/API/Type: `lib/features/sales/sales_invoice_form_page.dart:91,1556-1600,2077-2185` — current implementation and constructor contracts to preserve; line numbers are discovery anchors and may shift with concurrent work.
  - Destination: `lib/features/sales/widgets/invoice_form_layout.dart` — create these modules and update only their parent import/construction sites.
  - Test: `test/sales_invoice_form_page_test.dart:354-515,1429; new test/features/sales/invoice_form_layout_test.dart` — existing assertions/fixture patterns; files marked new are created as part of this task.
  - External: none required; no framework/API migration or dependency change is planned.

  Acceptance criteria (agent-executable only):
  - [x] `flutter test test/sales_invoice_form_page_test.dart test/features/sales/invoice_form_layout_test.dart` exits 0 before extraction after characterization is added, and again after extraction.
  - [x] `flutter test test/sales_invoice_form_page_test.dart --name "no-match|timed-out|retry|keyboard"` exits 0 before and after extraction.
  - [x] `flutter analyze` reports zero issues; `git diff --check` exits 0.
  - [x] Review `git diff -- lib/features/sales/sales_invoice_form_page.dart lib/features/sales/widgets/invoice_form_layout.dart`: responsibility is removed from parent, constructed/imported from destination, and no calculation/payload or unrelated hunks are altered.

  QA scenarios (MANDATORY - task incomplete without these):
  ```
  Scenario: invoice-layout happy path
    Tool:     bash
    Steps:    flutter test test/sales_invoice_form_page_test.dart test/features/sales/invoice_form_layout_test.dart
    Expected: Existing mounted invoice interactions and new breakpoint/resize assertions pass without overflow or lost values.
    Evidence: <attemptDir>/task-2-invoice-layout.txt

  Scenario: invoice-layout failure or edge
    Tool:     bash
    Steps:    flutter test test/sales_invoice_form_page_test.dart --name "no-match|timed-out|retry|keyboard"
    Expected: Invalid item selection remains blocked and retry/keyboard behavior passes existing assertions.
    Evidence: <attemptDir>/task-2-invoice-layout-error.txt
  ```

  Commit: NO | Message: `refactor(client): extract invoice-layout` | Files: [lib/features/sales/sales_invoice_form_page.dart, lib/features/sales/widgets/invoice_form_layout.dart, task-specific tests]

- [x] 3. Extract dashboard sales-versus-purchases panel

  What to do: Move the panel and its DayBars, Bar and LegendDot implementation together. Expose only SalesVsPurchasesPanel; keep its helpers private. Preserve List<DayTotal> inputs, math, labels, date ordering, empty state, colors and constraints. Change the parent construction/import only; retain math imports still used by other panels. Add bounded mounted panel tests for empty and one-sided zero-valued series before extraction.
  Must NOT do: Change behavior, transfer controller ownership, modify another agent's hunks, or proceed before this task's checks pass.
  Closes: GAP-3

  Parallelization: Can parallel: NO | Wave 3 | Blocks: [4] | Blocked by: [2]

  References (executor has NO interview context - be exhaustive):
  - Pattern/API/Type: `lib/features/dashboard/dashboard_screen.dart:870-1055` — current implementation and constructor contracts to preserve; line numbers are discovery anchors and may shift with concurrent work.
  - Destination: `lib/features/dashboard/panels/sales_vs_purchases_panel.dart` — create these modules and update only their parent import/construction sites.
  - Test: `test/widget_test.dart:6788,6921-7015; test/features/dashboard/dashboard_layout_controller_test.dart; new test/features/dashboard/sales_vs_purchases_panel_test.dart` — existing assertions/fixture patterns; files marked new are created as part of this task.
  - External: none required; no framework/API migration or dependency change is planned.

  Acceptance criteria (agent-executable only):
  - [x] `flutter test test/features/dashboard/dashboard_layout_controller_test.dart test/features/dashboard/sales_vs_purchases_panel_test.dart` exits 0 before extraction after characterization is added, and again after extraction.
  - [x] `flutter test test/widget_test.dart --name "dashboard"` exits 0 before and after extraction.
  - [x] `flutter analyze` reports zero issues; `git diff --check` exits 0.
  - [x] Review `git diff -- lib/features/dashboard/dashboard_screen.dart lib/features/dashboard/panels/sales_vs_purchases_panel.dart`: responsibility is removed from parent, constructed/imported from destination, and no calculation/payload or unrelated hunks are altered.

  QA scenarios (MANDATORY - task incomplete without these):
  ```
  Scenario: dashboard-panel happy path
    Tool:     bash
    Steps:    flutter test test/features/dashboard/dashboard_layout_controller_test.dart test/features/dashboard/sales_vs_purchases_panel_test.dart
    Expected: Chart empty/one-sided data and existing layout persistence assertions pass.
    Evidence: <attemptDir>/task-3-dashboard-panel.txt

  Scenario: dashboard-panel failure or edge
    Tool:     bash
    Steps:    flutter test test/widget_test.dart --name "dashboard"
    Expected: Mounted dashboard refresh, missing-layout fallback and boot-failure retry tests pass.
    Evidence: <attemptDir>/task-3-dashboard-panel-error.txt
  ```

  Commit: NO | Message: `refactor(client): extract dashboard-panel` | Files: [lib/features/dashboard/dashboard_screen.dart, lib/features/dashboard/panels/sales_vs_purchases_panel.dart, task-specific tests]

- [x] 4. Extract date picker calendar widgets and focus state

  What to do: Move CalendarHeader, MonthGrid and MonthGridState into the calendar module; use DateRangeCalendarHeader, DateRangeMonthGrid and DateRangeMonthGridState names. Preserve all constructor fields, key strings, focus-node lifecycle, requestFocusForDay behavior, date semantics and localization. Update parent GlobalKey generic types and construction sites. Keep popover, range/provider state, persistence and preset policy in date_range_picker.dart. Use imports, not part files or a focus-controller redesign.
  Must NOT do: Change behavior, transfer controller ownership, modify another agent's hunks, or proceed before this task's checks pass.
  Closes: GAP-4

  Parallelization: Can parallel: NO | Wave 4 | Blocks: [5] | Blocked by: [3]

  References (executor has NO interview context - be exhaustive):
  - Pattern/API/Type: `lib/widgets/date_range_picker.dart:1117-1198 and MonthGridState remainder` — current implementation and constructor contracts to preserve; line numbers are discovery anchors and may shift with concurrent work.
  - Destination: `lib/widgets/date_range_calendar.dart` — create these modules and update only their parent import/construction sites.
  - Test: `test/widgets/date_range_picker_test.dart:213-365,442-636; test/core/date_range_math_test.dart` — existing assertions/fixture patterns; files marked new are created as part of this task.
  - External: none required; no framework/API migration or dependency change is planned.

  Acceptance criteria (agent-executable only):
  - [x] `flutter test test/widgets/date_range_picker_test.dart test/core/date_range_math_test.dart` exits 0 before extraction after characterization is added, and again after extraction.
  - [x] `flutter test test/widgets/date_range_picker_test.dart --name "Escape|discards|precedes|immediately|PageUp|dark"` exits 0 before and after extraction.
  - [x] `flutter analyze` reports zero issues; `git diff --check` exits 0.
  - [x] Review `git diff -- lib/widgets/date_range_picker.dart lib/widgets/date_range_calendar.dart`: responsibility is removed from parent, constructed/imported from destination, and no calculation/payload or unrelated hunks are altered.

  QA scenarios (MANDATORY - task incomplete without these):
  ```
  Scenario: calendar happy path
    Tool:     bash
    Steps:    flutter test test/widgets/date_range_picker_test.dart test/core/date_range_math_test.dart
    Expected: Mounted tap-selection, persisted week start, focus navigation and date arithmetic tests pass.
    Evidence: <attemptDir>/task-4-calendar.txt

  Scenario: calendar failure or edge
    Tool:     bash
    Steps:    flutter test test/widgets/date_range_picker_test.dart --name "Escape|discards|precedes|immediately|PageUp|dark"
    Expected: Cancel discards pending selection; reverse ranges, initial keyboard focus, month paging and dark mode retain assertions.
    Evidence: <attemptDir>/task-4-calendar-error.txt
  ```

  Commit: NO | Message: `refactor(client): extract calendar` | Files: [lib/widgets/date_range_picker.dart, lib/widgets/date_range_calendar.dart, task-specific tests]

- [x] 5. Extract purchase order line editor with borrowed controllers

  What to do: Create PurchaseOrderLineRow with explicit typed Item list, selected item ID, quantity/price/tax controllers, calculated amount, expiry date, submitting/removal flags, index/key data and callbacks for selection, numeric changes, removal and expiry picking. Parent owns _PoLine, disposal, provider watch, setState, payment synchronization and date dialog. Move the existing validators and rendering unchanged. Preserve po-input-tax-$index and the newly added tax field. Add characterization for final-row removal disabled, tax invalid values and item-dependent expiry visibility before extraction.
  Must NOT do: Change behavior, transfer controller ownership, modify another agent's hunks, or proceed before this task's checks pass.
  Closes: GAP-5

  Parallelization: Can parallel: NO | Wave 5 | Blocks: [6] | Blocked by: [4]

  References (executor has NO interview context - be exhaustive):
  - Pattern/API/Type: `lib/features/purchase_orders/purchase_order_form_dialog.dart:63-93,705-848` — current implementation and constructor contracts to preserve; line numbers are discovery anchors and may shift with concurrent work.
  - Destination: `lib/features/purchase_orders/widgets/purchase_order_line_row.dart` — create these modules and update only their parent import/construction sites.
  - Test: `test/features/purchase_orders/purchase_order_tax_test.dart:13; test/widget_test.dart:12935-13129; new test/features/purchase_orders/purchase_order_line_row_test.dart` — existing assertions/fixture patterns; files marked new are created as part of this task.
  - External: none required; no framework/API migration or dependency change is planned.

  Acceptance criteria (agent-executable only):
  - [x] `flutter test test/features/purchase_orders/purchase_order_tax_test.dart test/features/purchase_orders/purchase_order_line_row_test.dart` exits 0 before extraction after characterization is added, and again after extraction.
  - [x] `flutter test test/widget_test.dart --name "purchase order form:|purchase order: submit rejection"` exits 0 before and after extraction.
  - [x] `flutter analyze` reports zero issues; `git diff --check` exits 0.
  - [x] Review `git diff -- lib/features/purchase_orders/purchase_order_form_dialog.dart lib/features/purchase_orders/widgets/purchase_order_line_row.dart`: responsibility is removed from parent, constructed/imported from destination, and no calculation/payload or unrelated hunks are altered.

  QA scenarios (MANDATORY - task incomplete without these):
  ```
  Scenario: po-line happy path
    Tool:     bash
    Steps:    flutter test test/features/purchase_orders/purchase_order_tax_test.dart test/features/purchase_orders/purchase_order_line_row_test.dart
    Expected: Tax edit/save and line callbacks/validation/expiry/removal tests pass with unchanged controller identity.
    Evidence: <attemptDir>/task-5-po-line.txt

  Scenario: po-line failure or edge
    Tool:     bash
    Steps:    flutter test test/widget_test.dart --name "purchase order form:|purchase order: submit rejection"
    Expected: Mounted create/edit/item replacement and submit-rejection tests retain current payload and error assertions.
    Evidence: <attemptDir>/task-5-po-line-error.txt
  ```

  Commit: NO | Message: `refactor(client): extract po-line` | Files: [lib/features/purchase_orders/purchase_order_form_dialog.dart, lib/features/purchase_orders/widgets/purchase_order_line_row.dart, task-specific tests]

- [x] 6. Extract invoice return quantity row and position preview

  What to do: Move ReturnLineRow and PositionPreview into the new module as InvoiceReturnLineRow and InvoiceReturnPositionPreview. Keep all existing typed parameters (InvoiceItem, StockBatch list, borrowed text controller and InvoicePosition). Preserve batch disclosure, autofocus, Enter submission, rounding/display and fee threshold 0.005. Leave warehouse provider, settlement row/draft, fee calculation, position calculation, validation, repository calls and submission in the parent. Add mounted child tests for disclosure, controller edits/callbacks and fee threshold before the move.
  Must NOT do: Change behavior, transfer controller ownership, modify another agent's hunks, or proceed before this task's checks pass.
  Closes: GAP-6

  Parallelization: Can parallel: NO | Wave 6 | Blocks: [7] | Blocked by: [5]

  References (executor has NO interview context - be exhaustive):
  - Pattern/API/Type: `lib/features/sales/invoice_return_dialog.dart:712-930,969-1057` — current implementation and constructor contracts to preserve; line numbers are discovery anchors and may shift with concurrent work.
  - Destination: `lib/features/sales/widgets/invoice_return_views.dart` — create these modules and update only their parent import/construction sites.
  - Test: `test/widget_test.dart:9372-9524; test/repositories/invoice_return_payload_test.dart; new test/features/sales/invoice_return_views_test.dart` — existing assertions/fixture patterns; files marked new are created as part of this task.
  - External: none required; no framework/API migration or dependency change is planned.

  Acceptance criteria (agent-executable only):
  - [x] `flutter test test/repositories/invoice_return_payload_test.dart test/features/sales/invoice_return_views_test.dart` exits 0 before extraction after characterization is added, and again after extraction.
  - [x] `flutter test test/widget_test.dart --name "invoice form: process return"` exits 0 before and after extraction.
  - [x] `flutter analyze` reports zero issues; `git diff --check` exits 0.
  - [x] Review `git diff -- lib/features/sales/invoice_return_dialog.dart lib/features/sales/widgets/invoice_return_views.dart`: responsibility is removed from parent, constructed/imported from destination, and no calculation/payload or unrelated hunks are altered.

  QA scenarios (MANDATORY - task incomplete without these):
  ```
  Scenario: return-views happy path
    Tool:     bash
    Steps:    flutter test test/repositories/invoice_return_payload_test.dart test/features/sales/invoice_return_views_test.dart
    Expected: Payload tests and mounted disclosure/controller/fee-boundary assertions pass.
    Evidence: <attemptDir>/task-6-return-views.txt

  Scenario: return-views failure or edge
    Tool:     bash
    Steps:    flutter test test/widget_test.dart --name "invoice form: process return"
    Expected: Return creation, excess-quantity validation and server-rejection scenarios pass through the mounted dialog.
    Evidence: <attemptDir>/task-6-return-views-error.txt
  ```

  Commit: NO | Message: `refactor(client): extract return-views` | Files: [lib/features/sales/invoice_return_dialog.dart, lib/features/sales/widgets/invoice_return_views.dart, task-specific tests]

- [x] 7. Extract supplier allocation row views

  What to do: Move the four row views into the module as SupplierPoAllocationRow, SupplierAvailablePoRow, SupplierPurchaseAllocationRow and SupplierAvailablePurchaseRow. Accept PurchaseOrder/Purchase models, borrowed TextEditingController and typed callbacks rather than exposing _Allocation/_PurchaseAllocation. Keep all allocation lists, controller creation/disposal, totals, allocation order, auto-allocation, section empty/loading conditions and submit logic in parent. Preserve the seeded-purchase condition openPurchases.isEmpty && _purchaseAllocations.isEmpty. Before moving, add a dedicated mounted modal test with a fake repository/HTTP adapter for one PO plus one direct purchase: total 1000, allocations 600 and 400, assert exact posted arrays; remove/re-add and auto-allocate via taps. Add seeded purchase with empty open-purchases response and rejected submission cases.
  Must NOT do: Change behavior, transfer controller ownership, modify another agent's hunks, or proceed before this task's checks pass.
  Closes: GAP-7

  Parallelization: Can parallel: NO | Wave 7 | Blocks: [F1, F2, F3, F4] | Blocked by: [6]

  References (executor has NO interview context - be exhaustive):
  - Pattern/API/Type: `lib/features/suppliers/supplier_payment_modal.dart:112-127,550-735,806-1030` — current implementation and constructor contracts to preserve; line numbers are discovery anchors and may shift with concurrent work.
  - Destination: `lib/features/suppliers/widgets/supplier_allocation_rows.dart` — create these modules and update only their parent import/construction sites.
  - Test: `test/widget_test.dart:11562-11623; new test/features/suppliers/supplier_payment_modal_test.dart` — existing assertions/fixture patterns; files marked new are created as part of this task.
  - External: none required; no framework/API migration or dependency change is planned.

  Acceptance criteria (agent-executable only):
  - [x] `flutter test test/features/suppliers/supplier_payment_modal_test.dart` exits 0 before extraction after characterization is added, and again after extraction.
  - [x] `flutter test test/widget_test.dart --plain-name "supplier detail Record Payment modal posts PO allocations"` exits 0 before and after extraction.
  - [x] `flutter analyze` reports zero issues; `git diff --check` exits 0.
  - [x] Review `git diff -- lib/features/suppliers/supplier_payment_modal.dart lib/features/suppliers/widgets/supplier_allocation_rows.dart`: responsibility is removed from parent, constructed/imported from destination, and no calculation/payload or unrelated hunks are altered.

  QA scenarios (MANDATORY - task incomplete without these):
  ```
  Scenario: supplier-allocation happy path
    Tool:     bash
    Steps:    flutter test test/features/suppliers/supplier_payment_modal_test.dart
    Expected: Mounted mixed allocation, removal/re-addition, auto-allocation, seeded purchase and rejected submission tests pass; payload totals stay 1000 with PO 600 and purchase 400 in the explicit-allocation scenario.
    Evidence: <attemptDir>/task-7-supplier-allocation.txt

  Scenario: supplier-allocation failure or edge
    Tool:     bash
    Steps:    flutter test test/widget_test.dart --plain-name "supplier detail Record Payment modal posts PO allocations"
    Expected: Existing modal route still posts supplier_id=1, amount=1000 and one PO allocation of 1000.
    Evidence: <attemptDir>/task-7-supplier-allocation-error.txt
  ```

  Commit: NO | Message: `refactor(client): extract supplier-allocation` | Files: [lib/features/suppliers/supplier_payment_modal.dart, lib/features/suppliers/widgets/supplier_allocation_rows.dart, task-specific tests]

## Final verification wave (MANDATORY - after all implementation tasks)
> Runs in PARALLEL. ALL must APPROVE. Surface results to the caller and wait for an explicit "okay" before declaring complete.
- [x] F1. Plan compliance audit - every task done, every acceptance criterion met; verify seven destination clusters are used, not duplicate dead implementations.
- [x] F2. Code quality review - diagnostics clean, idioms match, no dead code; verify all controllers/provider/submission state stays with its original owner and diff preserves concurrent edits.
- [x] F3. Real manual QA - every QA scenario executed with evidence captured; mounted interaction tests exercise the real widgets. Capture final `flutter test`, `flutter analyze`, `node scripts/l10n-drift.js` and `git diff --check` output. Any baseline/final mismatch must be classified with evidence, not dismissed.
- [x] F4. Ideal-state fidelity - delivered behavior checked against every IS row 1:1; a shortfall becomes new task rows, never a note; nothing Must-NOT-Have introduced.

The caller is the coordinating agent for this plan; report the evidence and approval results to that agent. No source implementation or validation is claimed by this planning deliverable.

## Commit strategy
- No commit is authorized by this plan execution. Keep logical changes reviewable and report their files.
- If later authorized: one logical change per commit. Conventional Commits (`<type>(<scope>): <subject>` body + footer).
- Atomic: every commit builds and passes tests on its own.
- No "WIP" / "fix typo squash later" commits on the final branch - clean up before merge.
- Reference the plan file path in the final commit footer: `Plan: .omo/plans/code-005-client-extractions.md`.

## Success criteria
| IS | Delivering task(s) | Proving QA scenario | Evidence |
|----|--------------------|---------------------|----------|
| IS-1 | 1 | csv happy path; csv failure or edge | <attemptDir>/task-1-csv.txt; <attemptDir>/task-1-csv-error.txt |
| IS-2 | 2 | invoice-layout happy path; invoice-layout failure or edge | <attemptDir>/task-2-invoice-layout.txt; <attemptDir>/task-2-invoice-layout-error.txt |
| IS-3 | 3 | dashboard-panel happy path; dashboard-panel failure or edge | <attemptDir>/task-3-dashboard-panel.txt; <attemptDir>/task-3-dashboard-panel-error.txt |
| IS-4 | 4 | calendar happy path; calendar failure or edge | <attemptDir>/task-4-calendar.txt; <attemptDir>/task-4-calendar-error.txt |
| IS-5 | 5 | po-line happy path; po-line failure or edge | <attemptDir>/task-5-po-line.txt; <attemptDir>/task-5-po-line-error.txt |
| IS-6 | 6 | return-views happy path; return-views failure or edge | <attemptDir>/task-6-return-views.txt; <attemptDir>/task-6-return-views-error.txt |
| IS-7 | 7 | supplier-allocation happy path; supplier-allocation failure or edge | <attemptDir>/task-7-supplier-allocation.txt; <attemptDir>/task-7-supplier-allocation-error.txt |
- Every IS row above has a delivering task and a proving scenario; all QA scenarios pass with captured evidence; F1-F4 approved; commit history unchanged unless separately authorized.
