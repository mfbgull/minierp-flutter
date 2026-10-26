# MiniERP accounting integrity audit

**Assessment: release blocked. MiniERP is not demonstrated financially trustworthy for real business use.** The audit establishes16 confirmed defects: **2 Critical,6 High,7 Medium,1 Low**, plus one accounting-policy decision. Critical issues spend the same return credit twice and fabricate a full cash receipt from explicit zero POS tender. Balanced journals and correct-looking statement totals coexist with proven economic errors.

This is an evidence-based audit snapshot, not a certification that every workflow or displayed figure was executed. Discovered modules and financial surfaces have explicit statuses; broad numerical/UI verification remains partial. No production code or financial data was changed, no historical records repaired, and no fix implemented. Decision D15 is recorded as OPEN-DECISION in the existing audit decision log.

## Financial discrepancies that determine the assessment

| Priority | Proven economic result | Finding |
|---|---|---|
| Critical | Return credit60 consumed across invoices can be voided/reissued/spent again. Retained goods225 minus cash150 require receivable75; customer/invoice receivable15, undercollection60. GL75 is economically correct and disagrees with the operational ledger | [F-002](findings/F-002/finding.md) |
| Critical | POS cash_received0 becomes Cash17.35, invoice paid and stock released; no actual tender supplied | [F-073](findings/F-073/finding.md) |
| High | Sales and supplier returns can predate their source sale/acquisition, changing historical revenue/COGS/inventory/payables before the source events | [F-001](findings/F-001/finding.md) |
| High | Two settled salary periods expense1800 instead of2000; consumed advance200 remains an asset, overstating profit/assets/equity200 | [F-020](findings/F-020/finding.md) |
| High | Loan repayment accepted before disbursement creates a dated negative loan asset200 | [F-021](findings/F-021/finding.md) |
| High | Production pool0.02 creates negative output cost−0.01; inventory GL0.03 vs batch value0.02 and clearing−0.01 | [F-022](findings/F-022/finding.md) |
| High | Valid mixed-price count correction fails500 and rolls back; another correction silently erases an omitted item's shortage, overstating stock20 and understating loss20 | [F-024](findings/F-024/finding.md), [F-025](findings/F-025/finding.md) |
| Medium | Balance-sheet categories omitted, CSV currency split across cells, salary hint600 instead of800, P&L expense detail10 while total20 | [F-040](findings/F-040/finding.md), [F-041](findings/F-041/finding.md), [F-042](findings/F-042/finding.md), [F-043](findings/F-043/finding.md) |
| Medium | Fully voided lines retain9 active headers; duplicate reservation leaves3 units falsely reserved after release; omitted optional reservation line ID prevents release | [F-060](findings/F-060/finding.md), [F-071](findings/F-071/finding.md), [F-072](findings/F-072/finding.md) |
| Low | Repeated SO cancellation returns500 while correctly preventing another financial mutation | [F-070](findings/F-070/finding.md) |

Minimum reproductions establish existence and exact impact in synthetic fixtures; they are not estimates of losses in any live database. The count correction500 is a serious unavailable financial workflow with successful rollback, not a claim that its failed request committed corruption. P&L profit50 remains correct in the retail expense-breakdown finding.

## What independently reconciled

The requested retail lifecycle passes: purchase70 units at10, sell15 at15, three valid one-unit returns/refunds, resale2, one damaged unit and separate expense10. Gross sold17, returned3, net sold14, closing stock55, inventory550, net revenue210, net COGS140, damage10, operating expense10, profit50. Cash10,170, AR30, AP700 and equity10,050 reconcile to assets10,750. Actual API responses were replayed through Dart models and mounted P&L/balance-sheet widgets. The report window includes September–October and the execution-day damage posting.

Named partial-GRN/payment, tax residual/reversal, warehouse transfer/reversal, FEFO/nonexpiry, funds/stock rejection, idempotent retry/conflict, injected journal-failure rollback, and year-boundary cases also pass their bounded assertions. Positive attributable production overhead/cancellation, cost-based owner drawings/voids and ordinary single-cost stock-count correction reconcile independently. These passes do not override different failing branches.

Later extensions also reconcile ordinary quotation/SO conversion, guarded fulfillment/cancellation, POS cash/credit/split tenders and partial returns, supplier advances/application, expense accrual/settlement, opening replacement and cash counts. They expose the distinct POS/reservation/header failures above rather than giving those modules a blanket pass.

## Coverage, policy and release limits

- Supplier return credit across multiple purchase invoices was actually attempted: the public workflow returns500 and posts nothing. Aggregate AP15 remains correct; successful target allocation and supplier consumed-credit reversal are unsupported/unverified.
- F-023/D15: closing an accrual period blocks later payment of its unpaid expense/bill in an open period. Whether closure intentionally freezes future settlement requires an explicit policy decision. No guard was changed.
- Full native Flutter→API→database→reload workflows, mobile and remaining POS/SO/quotation/advance variants, every reversal/tax/discount/cash-wallet/aging boundary, custom templates, printing/export and crash/multi-process recovery remain incomplete. Carton conversion, serial workflows and a dedicated cash-transfer route were not established. A candidate source inventory is not an independently verified figure.
- Existing dummy historical discrepancies remain outside this audit. Fresh migrated fixtures and read-only evidence verification protect original business files. All1,172 protected source hashes matched through the2026-10-25 checkpoint. Later shared-workspace edits change10 of those files plus other configs/new files; those changes are preserved and not attributed to this audit. Findings retain snapshot evidence; unchanged core POS/reservation/accounting-service sources were rechecked. The earlier full suites do not certify the later working tree.

## Verification status

Independent expected-value detectors reproduce the defects; they are intentionally red. Full server test assertions passed **232 suites/1,918 tests**; Jest reported open handles and clean process exit was not captured after daemon recovery. Full Flutter passed **1,034 visible tests plus96 hidden loading checks**, exit0. Whole-repository Flutter analysis passed, no issues. The initial quick run failed on Fallow/audit-harness lint; later corrections do not rewrite that history. Exact scope, dates, exit limits and later source drift are in [verification](10-verification-results.md). No current-tree green-CI claim is made.

Independent adversarial reviewers verified the retained SQL/API/widget evidence and corrected overclaims, including the signed receivable comparison and supplier allocation coverage. Their approval covers inclusion of bounded findings, not comprehensive ERP correctness.

## Deliverables and recommended order

Start with the [findings register](08-findings-register.md) and [risk-ordered remediation proposal](09-remediation-roadmap.md). Supporting deliverables: [architecture/dependency map](01-accounting-architecture.md), [module inventory](02-module-inventory.md), [module audit matrix](03-coverage-matrix.md), [actual reconciliations](04-reconciliation-results.md), [scenario ledger](05-test-scenarios.md), [financial figure matrix](06-report-verification.md), [limitations](07-unverified-areas.md), [execution journal](audit-log.md) and individual finding folders with reproducible evidence.

Address credit entitlement/reversal integrity first, then count/valuation, production allocation, salary recognition and chronology, followed by financial presentation and remaining verification. Reassess release readiness only after authorized corrections and independent regressions; no repair authorization is assumed from this audit.
