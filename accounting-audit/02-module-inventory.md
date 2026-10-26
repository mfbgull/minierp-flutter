# Accounting module inventory and repository reconnaissance

This is a source-grounded inventory, not a claim that every line was semantically audited. The file/figure registers retain unverified entries explicitly.

Repository revision and protected-file hashes: [source-baseline.json](evidence/source-baseline.json). Repository graph tree: [graph-repository-tree.json](evidence/graph-repository-tree.json). Financial backend file inventory and detailed lifecycle register: [backend workstream](workstreams/backend-controls.md). Frontend figure discovery and report mappings: [Flutter workstream](workstreams/flutter-reports.md).

## Implemented layers

| Layer | Actual location | Audit relevance |
|---|---|---|
| Flutter startup/routing | `lib/main.dart`, `lib/core` | Session, routes, navigation, shared number/date/currency helpers |
| Flutter features | `lib/features` | 24 feature directories including financial transactions, dashboard, reports, forecasts, settings and shell |
| Data contracts and HTTP | `lib/data/models`, `lib/data/repositories` | Typed API mapping, Dio requests, source-value preservation |
| Shared presentation/exports | `lib/widgets`, `lib/core` | Tables, statements, currency formatting, CSV/PDF/printing |
| HTTP registration | `server/src/app.ts`, `server/src/routes` | Mounted routes, permissions, middleware and channel parity |
| Controllers | `server/src/controllers` | Input schemas, route-level date/amount validation, model calls |
| Models | `server/src/models` | Documents, inventory/subledger mutation, report queries and transaction boundaries |
| Services | `server/src/services` | Shared accounting/cash/payment/credit/return logic; report engine; forecast and audit logs |
| SQLite schema and migration boot | `server/src/config/database.ts`, `server/src/migrations` | Actual schema ledger, fresh boot, integrity guards and registered migration order |
| Existing tests | `server/src/__tests__`, service tests, `test`, `integration_test` | Supporting regression evidence; distinct from new audit-only oracle/widgets |
| Maintenance tools | `server/scripts`, `scripts` | Reconciliation, repairs, migration/history tools and CI parity; no financial repair script executed |
| Native wrappers/assets | platform directories, assets and Flutter configuration | Transport/build context; not presumed financial posting authority |

The graph has best-effort SQL parsing gaps; the saved coverage metadata records all 62 server/src and three lib gaps. Direct source was used for schema/configuration and affected ranges. An index is not a completeness guarantee.

## Domain-to-implementation register

| Domain | Actual models/services | Creation/edit/reversal/deletion scope |
|---|---|---|
| Sales invoices | Invoice, InvoiceCreationService, PaymentRecordingService, salesDocumentValidation | Create/update/cancel/void; financial write keys; original batch COGS |
| POS and mobile | POS controller, MobileInvoice and mobile invoice controller | Shared invoice path plus channel-specific validation and response contracts |
| Quotations | Quotation | Draft/edit/convert/delete; financial effect begins with downstream document |
| Sales orders/reservations | SalesOrder, StockReservation | Submit/fulfill/edit/cancel, reservations/release and invoice linkage |
| Sales returns and settlements | InvoiceReturn, invoiceReturnService, returnMath | Return, restocking fee, cash/credit settlement, settlement void/reissue and COGS restoration |
| Customer balances and credit | Customer, Payment, creditReconciliation, UnappliedCash, unappliedCashService | Receipt/allocation/refund/reversal; return credit distinct from unapplied cash liability |
| Direct purchasing | Purchase | Purchase/edit/void, inventory/tax/payable and supplier subledger |
| PO and goods receipt | PurchaseOrder | Commitment, submit, partial receipt, payment, receipt void and PO cancel |
| Supplier returns/refunds | PurchaseReturn, SupplierRefund, SupplierLedger | Paid/unpaid/part-paid return credit, application/refund and void |
| Supplier service bills/advances | SupplierBill, SupplierPrepayment, SupplierPaymentService | Accrual/input tax, partial settlement, prepayment create/apply/refund/void |
| Inventory master and locations | Item, Warehouse | Standard/selling costs, opening quantity, warehouse/system location and deletion guards |
| Inventory movement/cost | StockMovement, inventoryEffectiveDate, cash/date guards | IN/OUT, batch selection, FIFO/FEFO, transfers/reversal, legacy valuation and costs |
| Stock count and loss | PhysicalCount, inventory controller, expiryDetection | Count/post/correct, damage relocation and separate write-off, expired/short/obsolete stock |
| Expenses and unpaid expenses | Expense, ExpensePayment | Draft/record/credit accrual, pay/partial pay, cancel/delete and category maps |
| Payroll and employee lending | Employee, EmployeeLoan, salary/loan controller paths | Full/partial/advance, carryover, repayment/deduction/write-off, payment void/delete |
| Business owner equity | OwnerCapital, OwnerWithdrawal | Capital, cash/goods drawings, edits and reversal; goods use cost |
| Owner personal loans | ownerPersonalLoansController | Separate personal memorandum loans/repayments/borrower merge; no business GL assumed |
| Manufacturing | BOM, Production, StockMovement, AccountingService | Recipe/version, material consumption, joint outputs, overhead accrual, cancellation/reversal |
| Accounting and cash | Period, AccountingService, cashService, cashBalanceGuard | Journal/period controls, opening balances, reconciliation and reversals; dedicated cash-transfer route unverified |
| Reports | Reports, arAging, Dashboard, CustomReport, reportQueryEngine, entityRegistry | Dated statements/aging, operational aggregations, custom selected-field expressions |
| Forecasts/configuration/security | forecastService, Settings, preferences, DashboardLayout, Role, activityLogger | Indirect inventory/cash presentation, cash-opening settings, authorizations, auditability |

## Scope boundaries

- No carton conversion engine or serial-number accounting workflow was established from current source discovery. A unit-of-measure label is not proof of quantity conversion. These requested cases remain unsupported/unverified rather than being simulated as a nonexistent feature.
- Every discovered workflow is assigned a status in [module coverage](03-coverage-matrix.md) and the finer backend/Flutter registers. A single feature directory may include many unrun edit/delete/reversal variants.
- Existing suites cover additional behavior, but do not establish an independent expected economic value for every route or figure.

Final bounded extensions are documented in [sales channels](workstreams/sales-channel-extension.md) and [payables/cash counts](workstreams/payable-cash-extension.md). Inventory counts and original graph artifacts refer to the audit snapshot, not later added source/tests. [Final source state](evidence/final-source-state.json) records10 changed baseline files and17 added protected-scope files without modifying them.
