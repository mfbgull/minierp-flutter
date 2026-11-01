# Invoice Form Alignment Spec

## Problem statement
"The payment section and the subtotal discount tax and grandtotal section in the new invoice form are not aligned on the right side check them and ask me for the layout."

## Context
- Form: Sales Invoice Form at `/sales/form` (create/edit invoice) - `lib/features/sales/sales_invoice_form_page.dart`
- Layout: Wide/Desktop layout (two-column layout when width >= 1100px and height >= 800px) - `lib/features/sales/widgets/invoice_form_layout.dart`
- Route: Defined in `lib/features/sales/sales_routes.dart`

## Current layout (before change)
**Wide layout (`InvoiceFormWideLayout`):**
- Left column (expanded): heading, grid (expanded), totals card, notes
- Right column (width 250px): payment panel (expanded, aligned top center), error banner, buttons

Totals card (`_buildTotalsCard`) contains:
- Left side: Discount field (if invoice scope) and Tax % field
- Right side: Subtotal, Discount, Tax, Grand Total rows, plus Credit section if applicable, plus Return position rows if applicable

Payment panel (`PaymentPanel`) contains payment form, existing payments (edit mode), payment summary

## Desired layout (after change)
**Wide layout:**
- Left column (expanded): heading, grid (expanded), notes (totals moved out)
- Right column (width 250px): totals card (above), payment panel (below totals), error banner, buttons at bottom
- Both totals section and payment section on the right side, aligned vertically
- Totals above payment
- Notes stay under the grid on the left
- Right column width stays at 250px
- No other elements moved to right column

**Narrow layout:** Unchanged - stacked vertically as before (heading, grid, totals, notes, panel, error banner, buttons). Issue only occurs in wide layout.

## Implementation
Modified `lib/features/sales/widgets/invoice_form_layout.dart`:
- Moved `totals` from left column to right column
- Removed `totals` from left column (left column now has heading, grid, notes)
- Restructured right column to: totals, spacing, scrollable area containing panel and error banner, spacing, buttons
- Changed right column to use `SingleChildScrollView` for the middle section to accommodate both totals and panel

## Files involved
- `lib/features/sales/widgets/invoice_form_layout.dart` - Layout structure
- `lib/features/sales/sales_invoice_form_page.dart` - Builds and passes widgets to layout
- `lib/features/sales/payment_panel.dart` - Payment section widget
- `test/sales_invoice_form_page_test.dart` - Tests for invoice form

## Questions answered
1. Form: Sales Invoice Form (/sales/form)
2. Layout: Wide/Desktop layout
3. Desired: Both on right side, stacked/aligned (totals above payment)
4. Order: Totals above payment
5. Notes: Stay under grid on left
6. Alignment details: No specific alignment issues mentioned
7. Right column width: Stay at 250px
8. Other elements: Nothing else moved
9. Reference: No reference
