# ACCT-009 implementation notes

The user selected implementation of accrual expenses, supplier bills, input tax
and advances in D13. Existing customer advances use the unapplied-cash workflow;
reuse its receive/apply/refund/void and reconciliation rules.

## Accrual expenses

`Credit` expenses recognize Dr 6000 / Cr 2115 when Recorded. Cash methods retain
their existing behavior. Expense payments recognize Dr 2115 / Cr cash, are
idempotent, and appear in operational cash totals and movement reports. An expense
with active payments cannot be cancelled or financially edited. Reverse its
payments first. Payments and reversals enforce accounting-period restrictions.
The expense row menu opens payment history, settlement and reversal controls.

## Supplier bills and input tax

Use a supplier bill document with the supplier's invoice number, bill/due dates,
net amount and an explicitly entered recoverable input-tax amount. Default tax
to zero; do not invent statutory tax rates. Non-stock bills recognize net expense
and input-tax receivable separately against supplier AP. The non-stock bill flow
is implemented with shared supplier payments and reversals. Recording a non-stock
bill requires both purchases:create and expenses:approve, preserving the existing
expense-approval boundary when recognizing its expense and payable. Stock-purchase tax
remains in progress: extend the existing purchase and PO/receipt documents, rather
than recording their inventory/AP a second time as a non-stock bill. Keep unit
costs and inventory valuation net of recoverable tax. Add tax to the payable and
reverse its proportional amount on purchase returns, including rounding residuals.

Stock implementation will keep `total_cost` and batch unit costs net, store a
separate recoverable-tax amount on each purchase/PO line, and include that tax in
supplier payables and payment ceilings. Receipts recognize only the tax on goods
actually received. Purchase-return headers and credit notes include net value plus
returned tax; line values and inventory GL remain net. Store tax per return line
and receipt line so partial returns/receipts and final rounding residuals reconcile.
Direct purchases now pass the mounted tax lifecycle, negative-tax rejection,
return-adjusted payment ceiling, and multi-line retry tests. Their widget test
confirms that a 100 net purchase plus 15 tax pays 115. PO receipts now allocate
tax proportionally, assigning the rounding remainder on final receipt. PO return
and receipt-void verification is in progress. Both purchase forms preserve tax
separately from net unit cost; the PO tax edit and repository run passed 107 tests.

Add bill allocations to the shared supplier-payment writer, preserving supplier
isolation, balance ceilings, funds/period checks, payment reversals, AP aging and
the AP-to-supplier-ledger invariant. Paid bills require payment reversal before
void. New accounts must avoid 1300 (employee loans), 1310 (salary advances) and
2110 (customer unapplied cash); use 1320 for recoverable input tax.

## Supplier advances

The implementation uses a separate asset account 1330 and a supplier prepayment document. Receipt of
goods does not itself consume an advance. Explicit application settles a supplier
payable (Dr 2000 / Cr 1330) without new cash movement, through the shared supplier
allocation rules. Cash paid in advance appears in cash reporting at the original
payment date. Reject over-application, cross-supplier application and voiding an
advance with live applications. Preserve retry and reversal safety. Creating,
applying and voiding are implemented; supplier-detail tabs and searchable unpaid
document selection are present. Mounted regressions verify cash does not move on
application, retries replay, application reversal restores availability, and the
legacy payment editor cannot change advance funding.

## Integration defects found and corrected

- Duplicate supplier allocation targets could overpay a purchase: two 60 entries
  passed individual balance checks against a 100 purchase and posted 120. Reject
  duplicate targets in the shared supplier validator; the mounted test was red.
- Cumulative cash omitted expenses, expense payments and salaries older than the
  90-day scan window. Add their pre-window aggregates and include the boundary day
  consistently. Both historical cash regressions were red before the fix.
- Generic payment editing could move a bill settlement before its bill date or
  convert an advance application to cash. Mounted regressions reproduced both;
  source guards preserve the bill date and advance funding contract.
- New financial sources appear in the unified payments feed and cannot use
  unsupported generic bulk deletion. Mounted feed assertions and client source
  handling regressions passed in the 55-server / 120-client checkpoint.
- Returned purchases could still be paid at the original gross amount. Shared
  payable views now subtract posted returns, and the mounted overpayment test
  passes. The same view feeds advance targets and purchase balance displays.
- A multi-line purchase replay returned only its first line. An exact submission
  membership table now reconstructs the complete original array; replay is green.
- Report integration, bill reissue after void and advance rejection scenarios
  passed in the 8-suite / 66-test accounting checkpoint. The client tax report,
  direct-purchase tax/payment, PO tax edit and financial retry forms passed 15
  tests. Full phase gates and final UI QA remain pending.

This file describes implementation choices, not closure evidence. ACCT-009 stays
in progress until all four capabilities have working interfaces and regression
and accounting-invariant coverage.
