# Flutter financial displays and report contracts

Owner: member C, flutter-reports. Audit-only work; production code, existing tests, and live financial data were not edited. The running desktop app was not driven because its data source could be a business database. All widget work uses an offline ProviderScope fixture; backend event replay uses a disposable-database audit fixture supplied by member A.

## Inventory and limits

The graph-first sweep returned all **973 Dart classes**, `has_more: false`, in `accounting-audit/evidence/flutter-graph-discovery.json`. Graph scope coverage reports three partial parse locations (activity_log.dart:10, json_helpers.dart:8, setting.dart:5); financial displays were additionally enumerated from direct source because graph method snippets often retain only Dart arrow signatures and cannot enumerate widget arguments or formatted expressions.

`python3 accounting-audit/tests/flutter_inventory.py` scanned **431 Dart files**, producing:

| Artifact | Scope |
|---|---|
| `accounting-audit/evidence/flutter-surfaces.csv` | 223 candidate financial/numeric surfaces and supporting files; source hashes, watched providers, repository imports, refresh calls |
| `accounting-audit/evidence/flutter-figures.csv` | 4,529 non-comment matching financial/numeric source lines; exact source/line/expression/context, candidate API dependencies, rounding, signs/labels, status |
| `accounting-audit/evidence/flutter-support.csv` | 2,468 model/provider/repository/calculation/print/export lines |
| `accounting-audit/evidence/flutter-inventory-summary.json` | Machine-readable counts and scope caveats |

This is an exhaustive **lexical candidate inventory for the declared patterns**, not a claim that every visible figure was exercised. It intentionally over-includes numeric quantities and data/control declarations to retain stock and state dependencies. Endpoint lists are import-closure candidates, not proven line-level data flow. Each candidate remains **NOT TESTED** unless a narrower scenario below supplies evidence. `.dart.part1/.dart.part2` owner-capital fragments are not compiled Dart sources and are excluded. A universal frontend correctness claim would be unsupported.

Status definitions: **PASS** means a named numerical or interaction assertion executed with evidence; **FAIL** means a reproduced discrepancy; **PARTIAL** means source mapping established but numerical/interaction dimensions remain untested; **NOT TESTED** means no valid result for that scenario. Passing general suites do not upgrade an untested row.

## Financial report mapping

Repository: `lib/data/repositories/report_repository.dart`; provider state: `lib/features/reports/report_providers.dart`; typed responses: `lib/data/models/report.dart`. `fromDate`/`toDate` are range query names; `asOfDate` is the point-in-time query name. Parent module refresh invalidates report providers in `lib/features/shell/module_refresh.dart:210`; each listed report also has its own refresh action, except detailed caveats below. Date providers trigger reads through `ref.watch`. This establishes code paths; no universal freshness claim is made.

| Screen / figures | API and authoritative basis | Client calculation / formatting / status |
|---|---|---|
| Profit & loss: revenue, COGS, gross profit, expense categories/total, net profit, margins | `/reports/profit-loss`; Reports.ts:403; GL period revenue credits−debits, COGS debits−credits, other expenses debits−credits; gross=revenue−COGS; net=gross−expenses; margin denominator revenue when >0 | Typed API values, currency formatter and decimal percent; **PASS** retail totals/display/refresh; **FAIL F-043** category total10 differs from authoritative20. Other scenarios remain untested. |
| Income statement: revenue, COGS, expenses, gross/net | `/reports/income-statement`; Reports.ts:570 delegates to same P&L | Direct API fields. **PARTIAL**, source agreement with P&L, no mounted interaction. |
| Balance sheet: inventory, AR, cash, AP, equity details, totals, balanced badge | `/reports/balance-sheet`; Reports.ts:457, all chart-account GL balances as of date, contra normal sides adjusted; equity=retained+capital−drawings+net income | **FAIL F-040**, model/screen/export drop other assets, tax payable, other liabilities. API totals/badge retained. **FAIL F-041**, export quoting. Owner drawings retain negative API sign. YTD labels are attached to cumulative balances; multi-year label accuracy not executed. |
| Trial balance: per-account debit/credit/normal balance; totals; balanced | `/reports/trial-balance`; Reports.ts:587 uses journal_lines via getAllAccountBalances, includes zero accounts | **PASS** retail model debit/credit totals11490; **PARTIAL** overall, grid not mounted. No local recomputation of account balances; grid number `#,###.00`; normal-side disclosure not independently assessed. |
| General ledger: debit, credit, balance per row | `/reports/general-ledger`; Reports.ts:631; active journal_lines within selected range; partitioned window sum debit−credit | Direct values in grid/CSV; **PARTIAL**. Opening balances before range are not included in SQL window; no carry-in fixture was executed here, so no new confirmed finding. |
| Cash flow: inflow, outflow, net, signed movements | `/reports/cash-flow`; Reports.ts:887; cumulative cashService flows at end minus before start; net=in−out | **PASS** retail net model mapping10170; **PARTIAL** overall. Direct totals, signed movement amount; search filters displayed rows, export uses full report. Movement UI, every payment method and reversal not tested here. |
| Cash reconciliation: opening/in/out/expected/count/variance and summary | `/reports/cash-reconciliation` GET/POST; server expected balances and saved counts | Local draft counts/variance plus server values; currency; **PARTIAL**, no save executed. |
| AR aging: outstanding/current/1–30/31–60/61–90/>90, totals | `/reports/ar-aging`; server aging as of selected date | **PASS** retail total mapping30; **PARTIAL** overall. API buckets/summary, grid/footer formatting. Due-date boundaries not verified by mounted UI. |
| AP aging: same supplier buckets | `/reports/ap-aging`; Reports.ts:317, supplier-ledger basis | **PASS** retail total mapping700; **PARTIAL** overall. Bills, returns and prepayments lifecycle delegated to backend workstreams. |
| AR summary: invoiced/paid/outstanding, current/aged buckets, counts/status breakdown | `/reports/ar-summary` | Direct typed fields and local presentation; **PARTIAL**, existing test only parses model fixture, not independent accounting verification. |
| DSO: DSO, average receivables, credit sales, total sales/AR, average invoice | `/reports/dso`, range parameters | Direct typed values; currency/decimal days; **PARTIAL**, methodology and zero-sales semantics not independently executed. |
| Customer statements and drilldown: opening/debits/credits/closing | `/reports/customer-statements`; customer repository statement drilldown | API summary rows; detailed ledger formatting/export; **PARTIAL**, no full statement UI lifecycle executed. |
| Top debtors and drilldown: outstanding/invoiced/count | `/reports/top-debtors`, limit/asOfDate | API values; **PARTIAL**. Limit and historic as-of reconciliation untested. |
| Tax summary: output/input/net tax | `/reports/tax-summary` | Direct API fields; **PARTIAL**, UI-to-tax posting replay not executed. |
| Batch traceability: batch original/remaining/sold quantity, unit cost, totals | `/reports/batch-traceability/:itemId` | Direct fields, counts/decimal formatting and CSV; **PARTIAL**, batch drilldown fixture not executed. |
| Expiry: remaining quantity, unit cost, value/writeoff preview | `/reports/expiry`, warehouse/status/threshold; writeoff flow | Local displayed quantity×cost where present and server batches; **PARTIAL**, actual writeoff intentionally not executed by this workstream. |
| Inventory valuation: sellable/reserved/expired/damaged/written-off/physical quantity/value | `/reports/inventory-valuation` | Typed model exists and InventoryValuationScreen exists, but no import/caller/route is wired in production. **NOT TESTED as a navigable UI**; model replay separately testable. |

The report hub and catch-all route map contain **16 report slugs** (`reports_dashboard_screen.dart:19`, `reports_routes.dart:45`). Item-aging, custom-report builder/query output, sales/purchase summary reports, and production/BOM reports have backend capabilities but no corresponding Flutter report screen in this route map. This is a frontend coverage/product gap, not evidence of incorrect backend mathematics. No new route was added.

## Other financial surfaces

Every matching source expression is in the CSV inventory; this table identifies the principal sources and remaining verification dimensions.

| Surface group | Figures / source / local formulas | Refresh and status |
|---|---|---|
| Dashboard | `/dashboard/boot` combines summary/KPIs/cash/AR/top customers; catalog contains stock value, sales revenue, gross/net profit, AR, expenses, payables, outstanding loans, turnover/days metrics; panel sales-vs-purchases and cash-account drilldowns | `dashboardBootProvider` is authoritative composite; derived block providers read its future. `invalidateDashboardBlocks` invalidates boot. **PARTIAL**, no complete multi-KPI replay. |
| Customer overview/invoices | `customer_providers`, customer/invoice repositories; total invoiced=max(total−returned+fee,0), paid=sum paidAmount, outstanding=sum balanceAmount; utilization=balance/limit×100 | Detail providers and module/list invalidation; **PARTIAL**; cancelled/voided and pagination edge cases not executed. |
| Customer ledger/statement | `calculateLedgerTotals`: summary debit/credit excludes RETURN/REFUND and returned-invoice-linked entries; balance uses all debits−all credits; grouped display in ledger_grouping | API detail fetch, local grouping, currency/fixed2; **PARTIAL**. Split-payment linkage to mixed returned/active invoices is not independently verified. |
| Unapplied cash receive/apply/refund/reverse | Server available/date-eligible cash, selected allocations and remaining preview; drafts retain retry identity | `invalidateUnappliedCash` and customer/payment refresh helpers; **PARTIAL**; existing focused suites owned by root, no independent new UI lifecycle here. |
| Supplier overview/ledger/statements | Supplier current/outstanding balance, ledger debit/credit/running balance, purchase/payment totals | Supplier repository/provider and refresh; **PARTIAL**, signs/lifecycle not mounted here. |
| Supplier bills/prepayments/refunds | Bill net/tax/gross/balance; advance available amount; application target balance; refund amount | Supplier accounting repository, bill/prepayment providers; local amount validation against source/target; **PARTIAL**, backend lifecycle proof belongs to oracle. |
| Sales/POS/invoice entry/detail/returns | Line qty×price, discounts/tax, total/paid/balance, return fee/refund; persisted invoice values and local draft calculators | Invoice and POS providers, idempotent write keys, reload after mutations; **PARTIAL**. Fractional and rounding parity not newly exercised here. |
| Quotations/sales orders/purchase orders | Draft qty×rate/discount/tax/totals; persisted order balance/paid/received | Module providers and dialog invalidation; **PARTIAL**, these previews are not GL authority. |
| Purchases/returns/supplier refunds | Cost/tax/gross/paid/balance, returned amount and credit/refund | Persisted repository data plus draft form calculations; **PARTIAL**, posted-cost reconciliation delegated to oracle. |
| Payments/hub/details/receipts | Signed cash movement kind, amount, allocations, AR balance trails; advance/refund kind-specific receipt labels | `invalidateCashMovementProviders` invalidates payment/summary/cash providers; derived dashboard invalidation alone may retain boot cache until module refresh, not executed. **PARTIAL**. |
| Expenses and expense payments | Amount/paid/outstanding and individual payment amounts from API; amount guard against outstanding | Expense providers and payment-dialog reload; **PARTIAL**, unpaid-expense GL tested by backend workstream only. |
| Stock/items/batches/ledger/counts | Quantity, standard/selling/actual cost, item/stock value, batch cost, movement value; running ledger quantity oldest→newest | Inventory module refresh; **PARTIAL**, operational valuation vs GL authority varies by surface and is not universally verified. |
| Production/BOM | `bomMaterialCost`=Σqty×standard cost; preview=materials+overhead; single-output CPU=cost/qty; joint allocation relative sales value, quantity fallback, last line rounding remainder | Advisory previews, backend recomputes actual FIFO/FEFO cost; mixed-unit CPU hidden for multi-output per prior decision D11. **PARTIAL**, no new mounted production scenario. |
| Owner capital/drawings/summary | Persisted entries, current capital/drawings/equity totals and withdrawal amount; optional costs | Owner equity repository/providers; form `_invalidateAll` and module refresh. **PARTIAL**, no owner UI mutation executed. |
| Personal loans/borrowers | Lent/repaid/pending summaries, principal/balance/installments, payment/repayment receipts | Personal loan repository/providers, tab summaries; **PARTIAL**; writeoff/repay lifecycle backend-owned. |
| Payroll/employee salary/history | Employee salary; month total_paid/remaining/advance; details/reprint; pay dialog recomputes remaining | **FAIL F-042**: mounted dialog shows600 vs backend remaining800; source backend fixture captured. Backend F-020 is a separate GL advance-clearance issue. |
| Employee loans | Principal/repaid/balance/monthly installment/repay preview | Loan providers; **PARTIAL**, no independent new loan UI interaction. |
| Forecast dashboard/demand/trends/accuracy | API quantities/confidence/trends/safety stock/reorder point, actual/predicted series, MAPE; nonmonetary decision inputs with inventory impact | Forecast providers and module refresh; **NOT TESTED numerically**. Do not treat model confidence or forecast quantities as accounting amounts. |
| Printing/CSV/ledger exports | Invoice/thermal invoice/returns/quotation/PO/SO/payment/personal-loan PDFs; shared CSV and ledger export | Source-enumerated in candidate/support CSV; **FAIL F-041 for balance-sheet CSV only**, all other printed documents **NOT TESTED visually** in this workstream. No invented screenshots/PDF verification. |

## Confirmed findings and evidence

- `accounting-audit/findings/F-040/finding.md`: missing nonzero balance-sheet categories, real mounted screen and actual exported CSV.
- `accounting-audit/findings/F-041/finding.md`: unescaped currency commas split balance-sheet CSV cells.
- `accounting-audit/findings/F-042/finding.md`: payroll remaining-balance hint double-subtracts carryover; exact backend fixture and mounted dialog output.
- `accounting-audit/tests/flutter_reports_test.dart`: intentionally failing expectations; audit-only, does not alter existing regression gates.

Exact baseline invocation: `flutter test --no-pub accounting-audit/tests/flutter_reports_test.dart --reporter expanded`. The retained `flutter-report-regressions.log` and `.exit` are the final run, not an inherited report. Earlier harness compilation failure (wrong loans-provider fixture type) was corrected in audit-only code and is not an application finding.

`flutter-balance-sheet-widget.json` contains the independent fixture, actual rendered Text widgets, expected missing categories and visible-component arithmetic. `flutter-balance-sheet.csv` is generated by the production builder. `flutter-csv-observation.json` records expected three cells vs actual four. Live desktop screenshots are intentionally excluded; any PNG present is from the isolated mounted widget.

Root owns static checks and full suites. This workstream does not claim the full Flutter or backend suite passed and did not duplicate their complete execution. Unexecuted routes, printing, date/locale combinations, cache freshness and financial lifecycle permutations remain explicit coverage debt.

## Final executed scenario register

The final replay resolves the pending retail checkpoints above. It does not upgrade unrelated dates, categories, routes, or print variants.

Source: `accounting-audit/evidence/oracle-run-AbsZeT/api-events.json`. All seven report responses used here are HTTP200 with the actual supported query names. Previous exploratory `oracle-run-bFQ2pm` calls used incorrect aliases and are **not** cited as passing report evidence. Final retail horizon is September1–October31, including the October25 damaged-stock writeoff; inventory valuation is inherently current and returns October25 rather than accepting a historical date.

| Scenario / scope | Expected | Actual | Status / artifact |
|---|---|---|---|
| Actual P&L response → Dart model | Revenue210, COGS140, net50 | 210/140/50 | **PASS**, flutter-oracle-models.json |
| Actual BS response → Dart model | Cash10170, AR30, AP700, stock550, equity10050; balanced asOfOct31 | All exact | **PASS for this fixture**, flutter-oracle-models.json; nonzero omitted categories remain F-040 |
| Actual trial balance → Dart model | Debit=credit11490 | 11490/11490, balanced | **PASS for model mapping**, flutter-oracle-models.json; grid not mounted |
| Actual cash flow → Dart model | In10225−out55=net10170 | Net10170 | **PASS for net mapping**, flutter-oracle-models.json; movement UI untested |
| Actual AR/AP aging → Dart models | AR30, AP700 | 30/700 | **PASS for total mapping**, flutter-oracle-models.json; aging bucket boundary scenarios untested |
| Actual inventory valuation → Dart model | Physical55 units/value550 | 55/550 | **PASS for model mapping**, flutter-oracle-models.json; screen is not routed |
| Actual P&L mounted screen + refresh tap | 210/140/70/20/50; refresh loads provider twice | Exact displayed totals; provider calls1→2 | **PASS**, flutter-oracle-pnl-widget.json and flutter-oracle-replay.log |
| Actual BS mounted screen | Inventory550, AR30, cash10170, equity10050 and Balanced | Exact visible text | **PASS for this fixture**, flutter-oracle-balance-widget.json |
| F-040 nonzero BS categories | Other assets400, tax60, other liabilities70 visible | All absent; totals retain amounts | **FAIL**, flutter-balance-sheet-widget.json and readable flutter-balance-sheet.png |
| F-041 CSV currency cell | 3 cells with complete Rs.1,000.00 | 4 cells; amount split | **FAIL**, flutter-csv-observation.json / flutter-balance-sheet.csv |
| F-042 salary carryover hint | Salary1000−paid200=remaining800 | Hint600 | **FAIL**, flutter-salary-carryover-widget.json / flutter-payroll-api-fixture.json |
| F-043 category breakdown | Operating10+damage10=total20 explained | Only Office Supplies10 under Expenses by Category; Total Expenses20 | **FAIL**, flutter-pnl-breakdown.json and actual mounted flutter-oracle-pnl-widget.json |

Positive invocation: `FLUTTER_AUDIT_ORACLE=accounting-audit/evidence/oracle-run-AbsZeT/api-events.json flutter test --no-pub accounting-audit/tests/flutter_oracle_reports_test.dart --reporter expanded --exclude-tags known-defect` → three tests, exit0; `flutter-oracle-replay.log/.exit`.

F-043 failing invocation: same command with `--tags known-defect` → one intentionally failing reconciliation assertion; `flutter-pnl-breakdown.log/.exit`. F-040/F-041/F-042 are the three intentionally failing tests in `flutter_reports_test.dart`. No production fix was authorized or made.

The bundled Inter font was explicitly loaded for the balance-sheet screenshot; it is a real RepaintBoundary rendering of the mounted fixture. Test-environment icon glyphs remain squares, so this PNG is used only to corroborate readable amounts/layout, not icon fidelity. Its exact Text values are independently captured in JSON. No live desktop or real-data screenshot was taken.

The P&L fixture provider is intentionally overridden, so its toolbar's default current-month filter is not the source of the replayed response; the response's rendered period is September1–October31. That fixture-specific date mismatch is **not** reported as an application bug. This replay proves model/display arithmetic and a refresh callback, not a live-network route/date integration.

Finding detail: `accounting-audit/findings/F-043/finding.md`. The breakdown issue is a display-completeness defect; final net profit50 remains correct.

Adversarial review improved the F-041 detector to parse quoted CSV cells and doubled quotes. Its self-check accepts a correctly quoted currency cell; the targeted `--plain-name F-041` rerun is captured in `flutter-csv-regression.log/.exit`. This avoids a test that would reject a valid future escaping fix. The earlier full three-defect run remains evidence for F-040/F-042.

Scoped harness analysis: `flutter analyze --no-pub accounting-audit/tests` → exit0, no issues, `flutter-harness-analyze.log/.exit`. Initial root quick saw two audit-harness lint issues (missing if braces and redundant typed_data import); both were corrected without changing production or analyzer policy.
