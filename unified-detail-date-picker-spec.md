# Unified Date Picker on Customer/Supplier Detail Pages — Corrected Specification

**Status:** Draft — implementation-ready. **Phases 1–3 executed 2026-09-03** (see §19 progress log); Phases 4–8 pending.
**Applies to:** Flutter client (`lib/`) + bundled Node/Express server (`server/`)
**Scope:** Customer and supplier detail pages only
**No DB schema or migration changes**

> **Parity-doc note:** Historical comments referenced `customer-module-spec.md` and `date-range-picker-spec.md`, but those files do not exist in this repository. They must not be treated as implementation dependencies. In-repository ground truth is the Flutter code, bundled server code, and reference components under `references/components/customer/` and `references/components/suppliers/`. Statement behavior is authoritative from the server `getStatement` / `SupplierLedger.getStatement` implementations and the Flutter statement tabs.

---

## 1. Request summary

A single unified date-range picker shall be added to the **customer detail page** and **supplier detail page**.

The picker shall:

1. Appear in the detail-page header beside **Record Payment**.
2. Control every data-bearing tab on that detail page.
3. Be shared by all tabs on that page instance.
4. Support normal date ranges and **All dates**.
5. Synchronize ranged selections with the application's global report range.
6. Keep **All dates** as a local page-only override.
7. Apply consistent filtered-empty behavior across tabs.
8. Preserve standing/current-position metrics where explicitly specified below.

The customer page has:

* Overview
* Invoices
* Ledger
* Payments
* Statement

The supplier page has:

* Overview
* POs
* Purchases
* Ledger
* Payments
* Statement

---

# 2. Core decisions

## D1 — Unified control

One page-level date range controls every applicable data view on the current detail page.

There must not be independent date pickers inside individual tabs after this change.

---

## D2 — Header placement

The picker is placed in the existing header row:

```text
[←]  Customer/Supplier identity…   [Record Payment]   [Date Range Pill]
```

Requirements:

* One row only.
* Identity area is the flexible area.
* Identity text truncates with ellipsis.
* Record Payment and the date pill must not wrap.
* The date pill may horizontally shrink only according to the existing widget's supported layout behavior.
* Verify both English and Urdu RTL layouts.

---

## D3 — Default range

When a detail-page instance is opened, its initial page range is a snapshot of:

```text
globalReportFromDateProvider
globalReportToDateProvider
```

The global range itself is seeded according to the application's existing report-range behavior:

* user's saved default range, or
* This month if no saved default applies.

The detail page therefore opens filtered by the current global period.

---

## D4 — Ranged commits are global

When the user commits a valid date range on a detail page, including:

* preset selection,
* custom range,
* previous-period arrow,
* next-period arrow,

the application shall:

1. update the page-local range,
2. update the global report range through the existing global-range mechanism.

Conceptually:

```text
Detail page range = selected range
Global report range = selected range
```

Use the existing `applyGlobalReportRange(...)` path rather than duplicating report-range propagation logic.

---

## D5 — All dates is local

Selecting **All dates** shall:

```text
Detail page from = null
Detail page to   = null
```

It shall **not** modify:

```text
globalReportFromDateProvider
globalReportToDateProvider
```

Therefore:

* Dashboard remains ranged.
* Reports remain ranged.
* Another newly opened detail page seeds from the current global ranged value.
* All dates does not leak from one detail-page instance to another.

---

## D6 — Range completeness invariant

A page range has only two valid states:

### State A — Active range

```text
from != null
to   != null
```

### State B — All dates

```text
from == null
to   == null
```

A half-range state is invalid:

```text
from != null && to == null
from == null && to != null
```

The implementation must never intentionally create or send a half-range state.

This invariant simplifies provider keys, endpoint behavior, empty-state logic, and UI behavior.

---

# 3. Corrected range-state architecture

## 3.1 Important correction: providers must be page-instance scoped

A plain global pair such as:

```dart
customerDetailFromDateProvider
customerDetailToDateProvider
```

would be unsafe if more than one customer detail page can coexist in the widget tree or navigation stack. One customer's local **All dates** selection could affect another page.

Therefore the page range must be scoped to the detail-page instance or equivalent stable page-session identity.

The implementation may use either:

### Option A — Preferred: one family state object

```text
CustomerDetailRangeArgs
  pageSessionId

CustomerDetailRangeState
  DateTime? fromDate
  DateTime? toDate
```

Equivalent supplier types are required.

### Option B — Family provider pairs

```text
customerDetailFromDateProvider(pageSessionId)
customerDetailToDateProvider(pageSessionId)
```

The same pattern applies to suppliers.

**Preferred implementation:** a single range-state object rather than independently mutable from/to providers. This enforces the complete-range invariant and prevents temporary half-range states.

---

## 3.2 Page-session initialization

The detail screen creates or receives one stable `pageSessionId`.

On first initialization only:

```text
pageRange = snapshot(current global range)
```

The page range must not continuously watch and overwrite itself from the global range.

Therefore:

* changing the range on the dashboard does not change an already-open detail page;
* a newly opened detail page gets the latest global range;
* local All dates remains local.

This is the accepted v1 behavior.

---

## 3.3 Single range commit API

Do not let every tab manually implement range mutation.

Create one page-level operation conceptually equivalent to:

```text
setDetailPageRange(pageSessionId, from, to)
```

Rules:

### Valid ranged commit

If both values are non-null:

1. write the page range,
2. call the existing global range update mechanism.

### All dates commit

If both values are null:

1. write null/null to the page range,
2. do not modify global range.

### Invalid half-range

Reject or normalize before state is committed.

All picker actions must use this same path.

---

# 4. Picker configuration

Use the existing:

```text
DateRangeFilter
```

Configuration:

```text
mode: DateRangeMode.range
showAllDates: true
```

The picker receives the current page range state.

The existing picker API should be reused where possible. However, if the current widget writes directly to two arbitrary providers and cannot enforce page-instance scope or the local/global commit rules cleanly, add a narrow callback or state-binding abstraction rather than duplicating picker behavior.

Do not redesign the picker unless required for these semantics.

---

# 5. Date boundary contract

All filtering must use a single documented date convention.

## 5.1 Date-only fields

For fields such as:

```text
invoiceDate
po_date
```

where the stored value is a business date rather than a timestamp:

```text
field >= startDate
AND field <= endDate
```

Both boundaries are inclusive.

---

## 5.2 Timestamp/date-time ledger fields

For ledger or transaction timestamps, the implementation must first verify the actual column type and current statement-query convention.

The new ledger filtering must exactly match the existing statement date semantics.

Do not independently invent:

```text
23:59:59
```

bounds if the project already uses another convention.

The customer and supplier ledger implementations must use the same inclusive business-date behavior as their corresponding statement implementations.

---

## 5.3 Null range

When the page range is All dates:

* omit both query parameters;
* do not send empty strings;
* do not send `"null"`.

Example:

```text
Active:
?fromDate=2026-03-01&toDate=2026-03-31

All dates:
(no date parameters)
```

---

# 6. Customer detail behavior

## 6.1 Overview

The Overview continues to fetch and retain the existing unfiltered data sources.

No new server endpoint is required solely for the customer Overview.

### Period-scoped figures

Only these two figures react to the page range:

* Total Invoiced
* Total Received

The cohort is:

```text
Invoices whose invoiceDate is within the active inclusive range.
```

For that cohort:

```text
Total Invoiced = existing total-invoiced calculation over cohort
Total Received = amount paid so far for invoices in that cohort
```

Payments made outside the selected date period still count toward Total Received if they belong to an invoice whose `invoiceDate` belongs to the cohort.

This is intentional.

### Standing/lifetime figures

These remain based on the existing full unfiltered data:

* Outstanding
* credit footer
* invoice-status bars
* Avg. Days to Pay
* top quick-stats bar

The distinction must be documented in a short code comment near the cohort calculation.

### Active-range annotation

When a range is active, Total Invoiced and Total Received display a compact period annotation.

When All dates is selected, no additional period annotation is required.

### Empty cohort

If an active range contains no invoices:

* Total Invoiced = 0.00
* Total Received = 0.00
* show `commonNoRecordsInPeriod` below the activity cards
* do not show the hint beneath Overview

Other Overview sections continue displaying their normal lifetime/current values.

---

## 6.2 Invoices

Add nullable date values to `CustomerInvoicesArgs`.

The paged request uses:

```text
start_date
end_date
```

because these are the parameter names already used by the invoice endpoint.

On range change:

1. provider arguments change,
2. page resets to page 1,
3. filtered data refetches.

The range itself must be part of the provider key.

Do not rely on manual invalidation alone.

---

## 6.3 Payments

Add nullable range values to `CustomerPaymentsArgs`.

Use:

```text
fromDate
toDate
```

matching the existing payments endpoint.

On range change:

1. reset to page 1,
2. fetch using the new provider key.

---

## 6.4 Ledger

Customer ledger provider arguments become range-aware:

```text
customerId
fromDate?
toDate?
```

Request:

```text
GET /customers/:id/ledger?fromDate&toDate
```

when active.

When All dates:

```text
GET /customers/:id/ledger
```

The returned array is the single source for:

* grouping,
* grid rows,
* totals footer,
* CSV export,
* PDF export,
* image export,
* print output.

Exports must not accidentally use a separately cached unfiltered ledger list.

### Ledger balance rule

A date range narrows visible rows only.

The server-stored per-row running Balance values remain full-history balances and are not recalculated as period-only balances.

### Grouping edge case

If a payment row belongs to an invoice outside the selected range, and its invoice/header row is absent from the ranged result, render the payment as an ungrouped ledger entry.

Do not manufacture an orphan invoice header.

### Customer footer

Preserve the existing footer formula over the visible filtered rows.

Do not redefine the footer as a statement closing balance.

---

## 6.5 Statement

Remove the statement-local picker and statement-local date state.

The statement watches the page range.

`CustomerStatementArgs` must support nullable dates.

### Active range

Send:

```text
fromDate
toDate
```

### All dates

Omit date parameters.

The server must return full history.

The Statement must preserve:

* opening balance/framing,
* transaction rows,
* closing balance/framing,
* summary card.

All dates means **full-history statement**, not a raw ledger view.

Before implementation is complete, explicitly verify this behavior with both parameters omitted. If the current server does not return the intended full-history statement, fix that behavior before wiring All dates.

---

# 7. Supplier detail behavior

Supplier behavior mirrors customers except where the underlying data model differs.

## 7.1 Overview

### Period-scoped figures

These are filtered by POs whose:

```text
po_date
```

falls within the active inclusive range:

* Total PO Value
* Total POs
* Draft bar
* Submitted bar
* Partial bar
* Completed bar

Each included PO is counted according to its **current status**, not its status during the historical period.

### Current Balance

Current Balance remains as-of-now and unfiltered.

It must continue matching the standing supplier balance used by the top quick-stats area.

### Data source

Do not duplicate PO summary calculations in the Flutter widget.

Extend the existing supplier PO-summary endpoint/provider to accept optional range bounds.

Provider arguments become conceptually:

```text
SupplierPOSummaryArgs(
  supplierId,
  fromDate?,
  toDate?
)
```

Repository request parameter names remain:

```text
start_date
end_date
```

to match the purchase-order endpoint convention.

All dates omits those parameters.

### Existing aggregation behavior

Do not silently change pre-existing PO-summary semantics.

In particular, if current server totals and status buckets have an existing inclusion/exclusion difference for Draft or Cancelled rows, preserve that behavior unless separately approved as another change.

---

## 7.2 POs

Add nullable range values to the paged provider arguments.

Use:

```text
start_date
end_date
```

Reset to page 1 when the range changes.

---

## 7.3 Purchases

Add nullable range values to the paged provider arguments.

Use:

```text
start_date
end_date
```

Reset to page 1 when the range changes.

Before implementation, verify route validation does not strip these query parameters.

---

## 7.4 Ledger

Add optional:

```text
fromDate
toDate
```

server support.

The range must be part of the provider key.

The same returned list drives:

* grid,
* footer,
* exports.

### Supplier footer

Preserve the existing formula over the visible set:

* debit = sum of shown rows,
* credit = sum of shown rows,
* balance = last shown row's stored balance.

Do not redefine this as the period net balance.

---

## 7.5 Payments

Use nullable:

```text
fromDate
toDate
```

in the provider arguments and endpoint request.

Reset pagination to page 1 on range change.

---

## 7.6 Statement

Remove the tab-local picker.

Use the page range.

Null/null means:

```text
full-history statement
```

with opening and closing framing preserved.

---

# 8. Server changes

No database schema changes or migrations are required.

## 8.1 Customer ledger

Update:

```text
server/src/controllers/customersController.ts
server/src/models/Customer.ts
server/src/routes/customers.ts
```

Requirements:

1. Parse optional `fromDate` and `toDate`.
2. Validate optional query values using project conventions.
3. Pass dates into `CustomerModel.getLedger(...)`.
4. Apply the same date-boundary semantics used by the customer statement query.
5. Preserve existing filters such as `voided = 0`.
6. Use prepared statements.
7. Omit date predicates when both dates are absent.

---

## 8.2 Supplier ledger

Update:

```text
server/src/controllers/suppliersController.ts
server/src/models/Supplier.ts
server/src/routes/suppliers.ts
```

Use the same rules as the customer ledger.

Reuse the supplier statement's established date handling where applicable.

---

## 8.3 Supplier PO summary

Update:

```text
server/src/controllers/purchaseOrderController.ts
server/src/models/PurchaseOrder.ts
```

Add optional:

```text
start_date
end_date
```

to the summary-by-supplier path.

Filter by:

```text
po_date >= start_date
po_date <= end_date
```

when a range is active.

No parameters means existing all-time behavior.

Use prepared statements.

---

## 8.4 Existing endpoint validation audit

Verify all endpoints used by this feature:

### Customer

```text
GET /invoices
GET /payments
GET /customers/:id/ledger
GET /customers/:id/statement
```

### Supplier

```text
GET /purchase-orders
GET /purchases
GET /suppliers/:id/ledger
GET /payments
GET /suppliers/:id/statement
GET /purchase-orders/summary/supplier/:supplierId
```

For every route:

1. confirm expected parameter names,
2. confirm validation accepts those parameters,
3. confirm validation does not strip them,
4. confirm null range omits them,
5. confirm active range uses inclusive bounds.

Do this before assuming existing controllers already receive the values.

---

# 9. Provider and pagination contract

Every server-backed filtered dataset must include the effective range in its provider identity.

Examples:

```text
CustomerInvoicesArgs(customerId, page, limit, fromDate?, toDate?)
CustomerPaymentsArgs(customerId, page, limit, fromDate?, toDate?)
CustomerLedgerArgs(customerId, fromDate?, toDate?)
CustomerStatementArgs(customerId, fromDate?, toDate?)

SupplierPOsArgs(supplierId, page, limit, fromDate?, toDate?)
SupplierPurchasesArgs(supplierId, page, limit, fromDate?, toDate?)
SupplierLedgerArgs(supplierId, fromDate?, toDate?)
SupplierPaymentsArgs(supplierId, page, limit, fromDate?, toDate?)
SupplierStatementArgs(supplierId, fromDate?, toDate?)
SupplierPOSummaryArgs(supplierId, fromDate?, toDate?)
```

The exact class names may follow project naming conventions, but the effective range must be part of equality/hash identity.

This prevents stale results from one range appearing under another range.

---

## Pagination rule

For every paged tab:

```text
Range changes
→ reset local page to 1
→ rebuild/watch provider with new range
→ fetch page 1
```

This reset must occur even if the previous page number is valid for the new range.

Otherwise a user could remain on page 5 after narrowing a range to only one page and receive an apparently empty result.

---

# 10. Empty-state rules

Add exactly two localization keys.

## English

```json
"commonNoRecordsInPeriod": "No records in the selected period",
"commonNoRecordsInPeriodHint": "Try a wider date range or choose All dates"
```

## Urdu

```json
"commonNoRecordsInPeriod": "منتخب مدت میں کوئی ریکارڈ نہیں ملا",
"commonNoRecordsInPeriodHint": "براہ کرم تاریخ کی حد وسیع کریں یا تمام تاریخیں منتخب کریں"
```

Run:

```text
flutter gen-l10n
```

after modifying both ARB files.

---

## 10.1 Fetch-based tabs

For:

* Invoices
* Payments
* Ledger
* Statement
* Supplier POs
* Supplier Purchases

### Active range + zero results

Show:

```text
commonNoRecordsInPeriod
commonNoRecordsInPeriodHint
```

### All dates + zero results

Show the existing module-specific true-no-data message.

Do not replace existing no-data copy globally.

---

## 10.2 Overview empty cohort

Customer Overview is special.

When an active range contains zero invoices:

* activity values are 0.00,
* show only:

```text
commonNoRecordsInPeriod
```

Do not show the hint because the rest of the Overview may still contain meaningful standing data.

---

## 10.3 Supplier Overview zero POs

When an active range produces a zero-PO summary:

* PO-derived period values show zero according to existing card formatting,
* Current Balance remains visible and unchanged,
* use the filtered-period empty treatment appropriate to the existing Overview layout.

Do not falsely show a global "supplier has no data" message because the supplier may have historical data outside the selected period.

---

# 11. Statement-specific edge cases

## Full history

All dates must still display a proper statement:

```text
Opening position
↓
Full transaction history
↓
Closing position
↓
Summary
```

## No transactions ever

If the account genuinely has no history:

* use the existing true-no-data behavior,
* unless the server intentionally returns a zero-balance statement frame as its existing contract.

Do not invent a different interpretation without checking the current endpoint behavior.

## Active period with no transactions

Use the filtered-empty message only if the statement response contract represents this as an empty result.

If the server returns synthetic opening/closing rows even when the period has zero transactions, the UI must distinguish:

```text
zero transaction rows in selected period
```

from:

```text
genuine account with no history
```

This must be verified against the actual statement response before implementation. Do not assume `array.isEmpty` alone is sufficient.

---

# 12. Header and layout edge cases

Test:

* long customer name,
* long supplier name,
* long email/phone metadata,
* narrow desktop width,
* Urdu RTL,
* large font/accessibility text if supported by the current app.

The identity area is the first area permitted to truncate.

The implementation must not cause:

* Record Payment wrapping,
* date pill wrapping,
* overlapping controls,
* clipped popup anchor.

If the current header cannot physically support both controls at the minimum supported width, use the project's existing responsive layout pattern. Do not silently allow controls to disappear.

---

# 13. Range and navigation edge cases

| Scenario                                  | Required behavior                                    |
| ----------------------------------------- | ---------------------------------------------------- |
| Open detail page                          | Snapshot current global range                        |
| Commit preset                             | Update page + global range                           |
| Commit custom range                       | Update page + global range                           |
| Use range arrows                          | Update page + global range                           |
| Select All dates                          | Page null/null only                                  |
| Open another detail page after All dates  | New page gets current global ranged value            |
| Change dashboard range while page is open | Existing page remains unchanged in v1                |
| Leave and reopen page                     | New page session snapshots current global range      |
| Switch tabs                               | Same page range remains active                       |
| Range changes on page 5 of paged tab      | Reset to page 1                                      |
| Request completes after range changed     | Old provider result must not render as current range |
| Range produces no rows                    | Filtered-empty state                                 |
| All dates produces no rows                | Existing true-no-data state                          |

---

# 14. Important implementation consistency rules

## Rule 1 — No duplicated range ownership

The Statement tab must not retain its own active range state after this feature is implemented.

All tabs read the detail page's range.

---

## Rule 2 — No manual refresh dependency

Changing the range must cause correct provider recomputation because the range is part of provider dependencies/keys.

Manual invalidation may still be used for mutation workflows, but the basic range change must not depend solely on explicit invalidation calls.

---

## Rule 3 — One mutation path

All range-changing UI actions use the same page-level commit logic.

Do not implement separate behavior for:

* presets,
* custom selection,
* arrows,
* All dates.

The difference between ranged and All dates behavior belongs in the shared commit logic.

---

## Rule 4 — No query-name normalization by assumption

Use the endpoint's actual parameter names:

| Data                | Parameters               |
| ------------------- | ------------------------ |
| Customer invoices   | `start_date`, `end_date` |
| Customer payments   | `fromDate`, `toDate`     |
| Customer ledger     | `fromDate`, `toDate`     |
| Customer statement  | `fromDate`, `toDate`     |
| Supplier POs        | `start_date`, `end_date` |
| Supplier purchases  | `start_date`, `end_date` |
| Supplier PO summary | `start_date`, `end_date` |
| Supplier ledger     | `fromDate`, `toDate`     |
| Supplier payments   | `fromDate`, `toDate`     |
| Supplier statement  | `fromDate`, `toDate`     |

Do not attempt to standardize these names as part of this feature.

---

# 15. Client file impact map

Expected Flutter files include:

```text
lib/features/customers/customer_detail_screen.dart
lib/features/customers/customer_overview_tab.dart
lib/features/customers/customer_invoices_tab.dart
lib/features/customers/customer_ledger_tab.dart
lib/features/customers/customer_payments_tab.dart
lib/features/customers/customer_statement_tab.dart
lib/features/customers/customer_providers.dart

lib/features/suppliers/supplier_detail_screen.dart
lib/features/suppliers/supplier_overview_tab.dart
lib/features/suppliers/supplier_pos_tab.dart
lib/features/suppliers/supplier_purchases_tab.dart
lib/features/suppliers/supplier_ledger_tab.dart
lib/features/suppliers/supplier_payments_tab.dart
lib/features/suppliers/supplier_statement_tab.dart
lib/features/suppliers/supplier_providers.dart

lib/data/repositories/purchase_order_repository.dart

lib/widgets/date_range_picker.dart
  only if needed to support the page-scoped range commit abstraction

lib/l10n/app_localizations_en.arb
lib/l10n/app_localizations_ur.arb
```

Expected server files include:

```text
server/src/controllers/customersController.ts
server/src/controllers/suppliersController.ts
server/src/controllers/purchaseOrderController.ts

server/src/models/Customer.ts
server/src/models/Supplier.ts
server/src/models/PurchaseOrder.ts

server/src/routes/customers.ts
server/src/routes/suppliers.ts
```

Also inspect purchase-order and purchase route schemas and update them only if existing validation would strip the newly supplied date parameters.

---

# 16. Recommended implementation order

## Phase 1 — Verify current contracts

Before changing UI:

1. inspect all endpoint query validation,
2. inspect actual ledger column/date semantics,
3. verify customer statement with no date parameters,
4. verify supplier statement with no date parameters,
5. verify supplier PO summary aggregation behavior,
6. verify whether statement responses can contain synthetic framing rows for an otherwise empty period.

Do not proceed based on assumptions for these contracts.

---

## Phase 2 — Server support

Implement and test:

1. customer ledger range,
2. supplier ledger range,
3. supplier PO-summary range,
4. route-query validation hygiene.

Then manually verify:

* lower boundary inclusion,
* upper boundary inclusion,
* omitted parameters,
* zero-result period,
* existing all-history behavior.

Run:

```text
cd server && npm run build
```

---

## Phase 3 — Range-state foundation

Implement page-instance-scoped range state.

Implement the single range commit path.

Verify:

* ranged commit updates global range,
* All dates does not update global range,
* newly opened detail pages snapshot global range,
* existing detail pages remain independent.

---

## Phase 4 — Customer data layer

Update:

* invoices,
* payments,
* ledger,
* statement provider arguments.

Ensure ranges are included in provider identity.

Ensure paged tabs reset to page 1.

---

## Phase 5 — Customer UI

Implement:

1. header picker,
2. remove statement picker,
3. Overview invoice cohort,
4. filtered-empty states,
5. ledger filtered exports/footer verification.

---

## Phase 6 — Supplier data layer and UI

Mirror the customer architecture.

Add the server-backed filtered PO summary.

Verify Current Balance remains unfiltered.

---

## Phase 7 — Localization

Add exactly:

```text
commonNoRecordsInPeriod
commonNoRecordsInPeriodHint
```

to English and Urdu.

Run:

```text
flutter gen-l10n
```

---

## Phase 8 — Tests and verification

Run:

```text
flutter analyze
flutter test
```

Add or update tests for:

### Range behavior

* page initializes from global range,
* preset updates page and global,
* custom range updates page and global,
* arrows update page and global,
* All dates clears only page state,
* no half-range state is committed.

### Customer

* Overview activity cards filter correctly,
* Overview standing metrics remain unchanged,
* invoices reset to page 1,
* payments reset to page 1,
* ledger refetches by range,
* statement has no local picker,
* All dates statement uses full history.

### Supplier

* PO summary filters correctly,
* Current Balance remains unchanged,
* POs reset to page 1,
* Purchases reset to page 1,
* ledger and payments filter correctly,
* statement mirrors customer behavior.

### Empty states

* active range + no results = filtered-empty copy,
* All dates + no data = existing module copy,
* customer empty invoice cohort = 0.00 + compact filtered-empty line.

### UI

* date pill is right of Record Payment,
* long identity truncates,
* English layout works,
* Urdu RTL layout works.

---

# 17. Explicitly out of scope

The following are not part of this change:

* reconstructing missing historical spec documents,
* changing other date pickers in the application,
* changing dashboard always-ranged behavior,
* changing report-range architecture beyond using its existing update path,
* changing quick-stat standing figures,
* redesigning statement accounting semantics,
* recalculating ledger row running balances,
* redefining ledger footer accounting formulas,
* silently fixing unrelated PO-summary aggregation behavior,
* database schema changes,
* database migrations,
* mobile product scope changes.

---

# 18. Final acceptance criteria

The feature is complete only when all of the following are true:

1. Customer and supplier detail pages each have one header-level date picker.
2. No tab retains an independent date picker or independent range state.
3. A valid selected range affects every applicable data tab.
4. Ranged selections synchronize with the global report range.
5. All dates clears only the current detail-page range.
6. Detail-page local range state cannot leak into another page instance.
7. Provider keys include the effective range where server data is range-dependent.
8. Every paged tab returns to page 1 after a range change.
9. Null ranges omit date parameters.
10. Ledger server filtering uses verified statement-compatible date semantics.
11. Ledger exports and footers use the same filtered rows displayed on screen.
12. Customer Overview filters only Total Invoiced and Total Received.
13. Supplier Overview filters PO-derived metrics but not Current Balance.
14. Statements preserve statement framing under All dates.
15. Filtered-empty and true-no-data states are distinct.
16. English and Urdu localization keys are present and generated.
17. `npm run build`, `flutter analyze`, and `flutter test` pass.
18. Manual verification succeeds in English, Urdu RTL, light mode, and dark mode where supported.

---

# 19. Implementation progress log

Running record of executed phases. Each entry lists what changed, how it was verified, and any decisions taken on the way. The spec text above stays authoritative for the remaining phases; entries below only record execution.

## 19.1 Phase 1 — Contract verification (executed 2026-09-03; report in chat, no code changed)

Verified against the code and the live dev DB (read-only copy):

- **Route validation audit (§8.4):** only `GET /payments` validates (`zodSchemas.dateRange`, merge-not-strip via `Object.assign`); invoices/POs/purchases/ledger/statement/summary routes are raw pass-through — nothing strips the new date params. No route-side changes needed beyond optional zod hygiene on the two ledger routes (done in Phase 2).
- **Date semantics (§5):** `transaction_date`, `invoice_date`, `payment_date`, `po_date` are TEXT `YYYY-MM-DD` — inclusive string bounds are correct everywhere; no timestamp/`23:59:59` concern exists.
- **Active-row asymmetry:** customer ledger/statement filter `voided = 0 AND reversed_by IS NULL`; supplier ledger/statement did **not** (voided purchase pairs were displayed). Both tables carry the columns. Decision: align supplier (executed Phase 2).
- **Statement full-history bug (blocker for All dates):** with `fromDate` omitted both statement models seeded `openingBalance` from the **latest** stored row, then the controller added the whole in-window net → closing ≈ 2× the current balance (verified live: customer −500.4 vs −250.2; supplier 4000 vs 2000). Fix (opening = 0 when `fromDate` omitted) executed in Phase 2.
- **Empty-period statements:** server returns `transactions: []` with `openingBalance == closingBalance` — no synthetic framing rows. Filtered-empty vs true-no-data is decided client-side from page-range state (§10.1), not the response shape.
- **PO summary aggregation (§7.1):** totals count every status (incl. Cancelled); buckets cover only Draft/Submitted/Partially Received/Completed — preserved byte-for-byte.
- **Cross-cutting:** ledger endpoints default to page 1 / limit 100 (`parsePageParams`) and the Flutter tabs send no paging — filtered sets inherit the ≤100-row first-page view (pre-existing, not to be silently redesigned by this feature).

## 19.2 Phase 2 — Server support (executed 2026-09-03)

Files: `server/src/models/Customer.ts`, `Supplier.ts`, `PurchaseOrder.ts`; `server/src/controllers/customersController.ts`, `suppliersController.ts`, `purchaseOrderController.ts`; `server/src/routes/customers.ts`, `suppliers.ts`. No DB schema/migration changes.

- Customer + supplier `getLedger` accept optional `fromDate`/`toDate` — inclusive `transaction_date` bounds on both the count and page query (envelope consistent). Controllers parse them; both ledger routes gained optional zod date-range validation.
- `PurchaseOrder.getSummaryBySupplier(supplierId, db, {startDate, endDate})` filters `po_date` inclusively (same clause as the PO list); controller reads `start_date`/`end_date`.
- **Decisions executed:** (1) supplier ledger/statement aligned to the customer active-set filter — voided originals + reversal rows no longer listed/stated; (2) supplier statement gained the `(transaction_date, id)` tiebreak; (3) full-history statements now open at 0 (the Phase-1 blocker).
- Verified: `npm run typecheck` + `npm run build` clean; jest suites (ledgerIntegrity, models, supplierPurchasesFilter, apReporting, stockTransfer, physicalCountBatchSync, glSoftDelete, paymentGuards, moneyPaths, auditTrail, purchaseVoid, purchaseReturn) green. Compiled-model harness on a real-DB copy: same-day inclusive bounds, zero-period (`rows 0 / total 0`), paged range envelope (1 of 3), toDate-only, statement closings equal current balances, supplier ledger 7→5 active rows, PO summary inclusive August range with Cancelled in totals/out of buckets.
- Pre-existing noise, not from this change: `controllers.test` (8) and `softDelete.test` (7 — create returns 201 vs expected 200) failures from the WIP tree.

## 19.3 Phase 3 — Range-state foundation (executed 2026-09-03)

Files: `lib/features/reports/report_providers.dart` (+`setGlobalReportRange`), `lib/features/customers/customer_providers.dart`, `lib/features/suppliers/supplier_providers.dart`, new `test/features/detail_page_range_test.dart`.

- Per-module session counters (`nextCustomerDetailSession` / `nextSupplierDetailSession`) scope a range to one detail-page instance.
- `customerDetailFromDateProvider` / `ToDateProvider` (+ supplier mirror): `StateProvider.family<DateTime?, int>`, seeded **once** via `ref.read` from the global pair (snapshot-on-open, no live-follow; new pages seed from the current global value).
- `commitCustomerDetailRange` / `commitSupplierDetailRange`: the single commit rule — complete ranged pair → `setGlobalReportRange` (global pair + every report pair); All dates (null/null) → page-local only; half-range asserted (unreachable through the picker, which always commits both sides).
- **Design choice (§3.1):** Option B (family provider pairs) over the preferred state-object — `DateRangeFilter` requires an explicit `StateProvider<DateTime?>` pair and always writes both sides atomically, so pairs plug into the existing picker with zero widget changes.
- Verified: 5 widget-test cases cover snapshot-on-open/independence, ranged commit → global + report pairs, All dates local-only, supplier mirror. `flutter analyze` clean on touched files; picker + preferences suites green.
- Accepted: family state is not disposed per closed page (trivial; matches the always-alive global/report pairs).

## 19.4 Phase 4 — Customer data layer (executed 2026-09-03)

Files: `lib/features/customers/customer_providers.dart`, `lib/data/repositories/customer_repository.dart`.

- Repository: `customerRepository.ledger(id, {fromDate, toDate})` accepts an optional inclusive range (`?fromDate&toDate`, nulls omitted — same `?key` convention as `statement`).
- `CustomerInvoicesArgs` / `CustomerPaymentsArgs` gained nullable `fromDate`/`toDate`; the paged providers add them as the endpoints' own param names (`start_date`/`end_date` for invoices, `fromDate`/`toDate` for payments — spec §14 Rule 4). Nulls are omitted by `PagedRequest.toQuery`, satisfying §5.3 (no empty-string/"null" params).
- New `CustomerLedgerArgs{customerId, fromDate?, toDate?}` + `customerLedgerRangedProvider` (the Ledger tab's feed under the page range). The existing int-keyed `customerLedgerProvider` stays as the **full-history** feed for the quick-stats/Overview/dialog (spec D2/D14 — standing metrics must never re-key to the page range).
- `CustomerStatementArgs` from/to became nullable (full-history statement = omit params).
- `invalidateCustomerQueries` now bumps a new `customerLedgerVersionProvider` so the ranged ledger refreshes the currently-viewed range after mutations.
- **Note on "paged tabs reset to page 1":** the reset fires where the tab watches the page range — the Phase-5 session wiring. Nothing mutates a page range yet (no pill), so there is no range change to reset from in Phase 4; the reset logic ships with the session watch.
- Also repaired two stale test files that had regressed to pre-fix state (`pos_screen_test.dart` — `PosItem` lost `barcode`, now `category`; `repositories_test.dart` — `salaryHistory` returns per-`pay_period` `SalaryMonthSummary` rows). Both suites pass; `flutter analyze` back to 0 errors.

## 19.5 Phase 5 — Customer UI (executed 2026-09-03)

Files: `lib/features/customers/customer_detail_screen.dart`, `customer_statement_tab.dart`, `customer_invoices_tab.dart`, `customer_payments_tab.dart`, `customer_ledger_tab.dart`, `customer_overview_tab.dart`, `customer_providers.dart`, new `lib/widgets/filtered_empty_state.dart`, `lib/l10n/en.arb` + `ur.arb` (regenerated).

- Detail screen: per-instance `_sessionId = nextCustomerDetailSession()`; header gains the unified `DateRangeFilter` pill right of Record Payment (bound to the session pair, `showAllDates: true`, `onChanged` = `commitCustomerDetailRange`). All five tabs receive `sessionId`.
- Statement tab: **local pill and `_from`/`_to` state removed**; it now derives `CustomerStatementArgs` from the session range via `customerDetailRangeIso`. Null range → full-history statement (opening 0 after the Phase-2 fix); the opening framing row shows `(fromDate)` only for ranged statements. Filtered-empty → `FilteredEmptyState`.
- Invoices/Payments tabs: `fromDate`/`toDate` from the session range ride in `CustomerInvoicesArgs` / `CustomerPaymentsArgs` (endpoint-specific param names, §14 Rule 4); a `ref.listen` on both session halves resets `_page = 1` on any range change (§9); empty-with-active-range → `FilteredEmptyState`, true-no-data keeps the module message.
- Ledger tab: switched from the int-keyed full-history feed to `customerLedgerRangedProvider(CustomerLedgerArgs(customerId, from, to))`; exports/footer operate on the filtered set; filtered-empty state under an active range.
- Overview: cohort = invoices whose `invoiceDate` ∈ active inclusive range, filtered client-side from the already-fetched full list (no new endpoint). Only Total Invoiced (`calculateTotalInvoiced`) and Total Received (`calculateTotalPaid` — sums cohort invoices' `paidAmount`, so payments outside the period still count, spec §6.1 intentional) react; Outstanding / credit footer / status bars / Avg. Days to Pay / quick-stats stay lifetime. Active range renders a compact `from – to` annotation on the two cards; empty cohort shows `commonNoRecordsInPeriod` below the cards (no hint, §10.2). Intentional-distinction note documented in a comment at the cohort calculation.
- l10n (pulled forward from Phase 7): `commonNoRecordsInPeriod` + `commonNoRecordsInPeriodHint` in en/ur.
- Verified: `flutter analyze` 0 errors on touched files; Phase-3 range tests (5) green; customers widget-test group (11) green; customer detail-page tests green.

## 19.6 Phase 6 — Supplier mirror (executed 2026-09-03)

Files: `lib/features/suppliers/supplier_detail_screen.dart`, `supplier_statement_tab.dart`, `supplier_pos_tab.dart`, `supplier_purchases_tab.dart`, `supplier_payments_tab.dart`, `supplier_ledger_tab.dart`, `supplier_overview_tab.dart`, `supplier_providers.dart`, `lib/data/repositories/supplier_repository.dart`, `purchase_order_repository.dart`.

- Repositories: `supplierRepository.ledger(id, {fromDate, toDate})` (inclusive `?fromDate&toDate`, nulls omitted); `purchaseOrderRepository.summaryBySupplier(id, {startDate, endDate})` (`?start_date&end_date` — the PO convention).
- Providers: `SupplierLedgerArgs` + `supplierLedgerRangedProvider` (+ `supplierLedgerVersionProvider`); `SupplierPOSummaryArgs{supplierId, fromDate?, toDate?}` — `supplierPOSummaryProvider` converted from int-keyed to the args family (only the Overview consumed it), range-aware via `supplierPOSummaryVersionProvider`; nullable dates on `SupplierPurchaseOrdersArgs` / `SupplierPurchasesArgs` (`start_date`/`end_date`) and `SupplierPaymentsArgs` (`fromDate`/`toDate`), all in `==`/`hashCode` (§7.2/7.3/7.5 + §14 Rule 4); `SupplierStatementArgs` from/to nullable; new `supplierDetailRangeIso` watch-accessor mirroring the customer one.
- Detail screen: `_sessionId = nextSupplierDetailSession()`, header pill right of Record Payment (session pair, `showAllDates`, `commitSupplierDetailRange`), sessionId on all six tabs.
- Tabs (customer mirrors): Statement — local pill/state removed, session range + nullable args, full-history framing (opening row label matches the summary tile, `(fromDate)` suffix when ranged); POs/Purchases/Payments — range in args + `ref.listen` page-1 reset + `FilteredEmptyState` under an active range; Ledger — `supplierLedgerRangedProvider`, same list drives grid/footer/exports (§7.4), filtered-empty state; Overview — ranged PO summary (`po_date` cohort, counted by current status), only Total PO Value / Total POs + the four status bars react, Current Balance stays as-of-now lifetime (§7.1/§13), `from – to` annotation on the two ranged cards, zero-PO period line (`commonNoRecordsInPeriod`, no hint — §10.3).
- `invalidateSupplierQueries` now bumps ledger/statement/PO-summary versions so the currently-viewed range refetches after mutations.
- Verified: `flutter analyze` 0 errors project-wide (37 pre-existing warnings/infos); Phase-3 range tests 5/5; full suppliers widget group 6/6; **bonus fix** — the pre-existing `supplier detail Statement tab shows the running balance` failure now passes (its root cause was the statement tab's English-hardcoded/range framing labels, which the session-range rewrite consolidated).

## 19.7 Remaining phases

Phase 7 (l10n remainder) was pulled forward into Phase 5 (both keys already in en/ur, generated). Phase 8 (acceptance-criteria tests/manual verification incl. English/Urdu RTL + dark mode, §18 items 17–18) remains.

