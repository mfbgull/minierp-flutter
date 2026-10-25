# Accounting module audit matrix

These are conservative **module-wide** statuses. PASS is reserved for a named bounded scenario; PARTIAL means meaningful evidence exists but variants remain unrun. FAIL means a reproduced defect in that dimension. UI means an executed mounted widget/interaction, not source reading. Details: [backend register](workstreams/backend-controls.md), [oracle scenarios](workstreams/financial-oracle.md), [Flutter register](workstreams/flutter-reports.md).

| Module / workflow | Static Review | Dynamic Test | GL Reconciled | UI Verified | Findings / limits |
|---|---|---|---|---|---|
| Specified retail lifecycle | PARTIAL | PASS | PASS | PARTIAL | Three returns, resale, damage and expense; report widgets replay actual API |
| Quotations/conversion | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Nonposting until conversion; independent conversion fixture absent |
| Sales orders/fulfillment/reservations | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Submit/fulfill/cancel/release paths mapped |
| Sales invoices: cash/credit | PARTIAL | PARTIAL | PARTIAL | PARTIAL | Create/payment/reversal tested; edit/discount/tax combinations incomplete |
| POS/walk-in/mobile invoices | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Shared creation does not prove channel parity; external mobile consumer absent |
| Sales returns/refunds | PARTIAL | FAIL | FAIL | NOT TESTED | F-001 chronology; F-002 consumed-credit regeneration |
| Resale of returned goods | PARTIAL | PASS | PASS | NOT TESTED | Scoped quantity/cost/revenue case passes |
| Customer payments/allocations | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Partial/exact/refund ceilings/reversal sample; edits incomplete |
| Return credits and settlement void/reissue | PARTIAL | FAIL | FAIL | NOT TESTED | Critical F-002 actual duplicate spending |
| Unapplied receipts/liability | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Receipt/application/refund sample and extended invariants |
| PO commitment + partial GRN/payment | PARTIAL | PASS | PASS | NOT TESTED | Named bounded scenario; PO itself not acquisition |
| PO cancellation/GRN reversal | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Tax residual/reversal sample; complete variants unrun |
| Direct purchases: cash/credit/edit/void | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Multiple fixtures; edit/void lifecycle incomplete |
| Supplier returns: unpaid/partial/paid | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Refund/credit variants; dependent reversal variants incomplete |
| Supplier credit split across invoices | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Split-credit fixture; complete edit/reversal combinations unrun |
| Supplier bills/input tax/later payments | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Accrual and closed-source payment test; F-023 policy disposition |
| Supplier prepayments/refunds | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Mapping; an invariant passing with no positive fixture is not verification |
| Items/opening stock/master deletion | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Fixture creation; opening/edit/delete variants incomplete |
| Carton/unit conversion | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | No conversion engine established; UOM label insufficient |
| Serial-number accounting | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | No executed serial workflow established |
| Batches/FIFO/FEFO/expiry | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Date/FEFO/nonexpiry examples; all location/status variants unrun |
| Warehouse transfer/reversal | PARTIAL | PASS | PASS | NOT TESTED | Bounded relocation and reversal, company-value neutrality |
| Damage relocation/write-off | PARTIAL | PASS | PASS | NOT TESTED | Exact-once loss/quantity/value in two scenarios |
| Physical count/correction | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | No independent clean count/post/correct fixture |
| Expired/lost/stolen/obsolete stock | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Loss mapping and expiry selection; not every reason executed |
| Cash/bank/wallet payments/transfers | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Cash/bank/funds sample; wallets and full transfer matrix unrun |
| Cash count/reconciliation/opening edits | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Mapped controls; no independent physical count |
| Operating expenses/categories | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Paid expense/accrual; edit/cancel/category variants incomplete |
| Expense payable/later settlement | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | F-023 restriction, policy disposition required |
| Salary/advance/carryover | PARTIAL | FAIL | FAIL | FAIL | F-020 expense/asset; F-042 dialog remaining |
| Employee loans/repayments | PARTIAL | FAIL | FAIL | NOT TESTED | F-021 chronology; write-off/reversal variants unrun |
| Payroll deductions/loan deductions | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Source/policy mapping; no independent deduction fixture |
| Owner capital | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Funding exact; edit/void incomplete |
| Owner cash/goods drawings | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Cost/equity classification source-mapped only |
| Owner personal memorandum lending | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Separate personal scope; no business GL assumed |
| BOM/recipe/versioning | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Recipe lifecycle mapped only |
| Production/joint outputs | PARTIAL | FAIL | FAIL | NOT TESTED | F-022 negative residual cost and inventory/clearing drift |
| Positive overhead/cancellation | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Zero-overhead probe does not verify capitalization/payable settlement |
| Journals/trial balance/general ledger | PARTIAL | PARTIAL | FAIL | PARTIAL | Balanced journals coexist with F-002/F-022 economic drift |
| Period closure/year boundary | PARTIAL | PASS | PASS | NOT TESTED | Bounded closure refusal and 31-Dec/1-Jan reconciliation |
| Backdating/source chronology | PARTIAL | FAIL | FAIL | NOT TESTED | Early sale blocked; early return/loan repayment accepted |
| Duplicate requests/idempotency | PARTIAL | PASS | PASS | NOT TESTED | Same-key replay/conflict and single-process request sample |
| Failure atomicity | PARTIAL | PASS | PASS | NOT TESTED | Injected journal failure rolls back; crash/power loss unrun |
| Dashboard/trends | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | API/source captures; cache/live refresh not fully exercised |
| Profit & Loss | PARTIAL | FAIL | FAIL | FAIL | Retail totals pass; F-020 source misposting; F-043 missing loss detail |
| Balance sheet | PARTIAL | FAIL | FAIL | FAIL | Retail equation passes; F-020/F-022 propagate; F-040 omitted categories |
| Cash flow | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | API/model sample; complete refund/transfer/opening matrix absent |
| Party ledgers/aging | PARTIAL | FAIL | FAIL | NOT TESTED | Retail/split samples pass; F-002/chronology fail; bucket boundaries incomplete |
| Sales/purchase/returns reports | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Selected APIs; all filters/groups/export variants unrun |
| Inventory valuation/movement/traceability | PARTIAL | FAIL | FAIL | NOT TESTED | Retail passes; F-022 invalid layer; unrouted valuation screen |
| Production/owner/expense reports | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Selected economic probes; incomplete figure-by-figure execution |
| Custom report engine | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Entity/expression mapping; independent templates absent |
| Forecasts/demand/accuracy | PARTIAL | NOT TESTED | NOT TESTED | NOT TESTED | Planning outputs, no accounting certification |
| CSV/PDF/printing | PARTIAL | FAIL | NOT TESTED | PARTIAL | F-041 actual CSV corruption; other print/export views unverified |
| Migrations/replay/repair | PARTIAL | PARTIAL | PARTIAL | NOT TESTED | Fresh boot; historical replay/WAL copy/repairs not run |
| Permissions/audit logs | PARTIAL | PARTIAL | NOT TESTED | NOT TESTED | Admin-auth requests; full role/denial/auditability matrix not repeated |

PASS rows never override broader workflow failures or unrun variants. Existing full-suite results are supporting evidence and do not upgrade these statuses. No fixes or accounting-policy changes are implemented.
