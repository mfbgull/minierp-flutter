# Period Protection Primitive — execution plan (2026-11-09)

OpenSpec change: `openspec/changes/period-protection-primitive/` (0/20 tasks).
Buyer: Gull picked this after use-cr-balance-in-invoice.

## Verified current state (before work)

- `assertPeriodNotClosed` = status+date-range based (`getClosedPeriodCovering`),
  shared classification maps `inside closed accounting period` → 409
  (`server/src/utils/businessRuleError.ts`).
- Guarded today: 20+ files including `postLegacyStockEntry` (0.2 done),
  `models/SupplierRefund.ts` (1.2 guard done, done-when test missing),
  payments/invoices/expenses/purchase-void controllers, POS, party-adjustment,
  store-credit, bill/prepayment, expense-payment services.
- `closedPeriodImmutability.test.ts` exists with 8 cases (payments ×3,
  invoice cancel, expense edit, purchase void, sales-return void, open-period
  control). Missing totals/invariant assertions from tasks 4.2/4.3.
- Explicit admin period opening exists: `POST /api/accounting/periods`
  (`PeriodModel.openPeriod`, admin-gated, `periodOpen` schema). Task 2.3
  endpoint done; test missing.
- `postEntry` auto-creates an open period from any outside date (2.2 open).
- NOT guarded: `voidJournalLinesByReference` (0.1), `Purchase.void` /
  `Invoice.cancel` model layer (0.3), `PurchaseOrderModel.voidGoodsReceipt`
  (1.1), `restoreInvoice` (1.3), no future-date rejection (2.1).

## Decisions (architecture)

- D-plan 1: `voidJournalLinesByReference` guards by reading the affected
  entries' `entry_date`s first, asserting each distinct date before any
  `UPDATE`. Assertion inside the primitive; no caller knowledge needed.
- D-plan 2: model-layer guards: `Purchase.void` asserts on `purchase_date`;
  `Invoice.cancelInvoiceInternal` asserts on `invoice_date`; both before the
  write transaction.
- D-plan 3: `voidGoodsReceipt` guards inside the model transaction on
  `receipt.receipt_date`; controller catch gains the shared closed-period →
  409 mapping (minimal edit, mirrors sibling controllers).
- D-plan 4: `restoreInvoice` asserts on `invoice.invoice_date` before its
  transaction; `handleBusinessError` already returns 409. Batch-faithful
  COGS re-posting on restore is NOT in this change's task list (task 1.3 is
  only the guard); the delta spec's COGS sentence becomes BUG-010 in
  `docs/bugs.md` with evidence instead of a silent spec rewrite.
- D-plan 5: new `AccountingService.assertDocumentDateNotFuture(db, date, what)`
  throws `BusinessRuleError(400)` when date > today (UTC). Call sites:
  invoice create/update, purchase create, goods-receipt create, stock
  movement create (adjustment). `postEntry` keeps auto-create for dates
  ≤ today, refuses future dates without an explicitly open covering period
  (2.2). POS path already has its own date discipline; falls under these
  call sites as far as trivially shared.
- D-plan 6: task 3.1 is verified by evidence (closure detected only via
  `status`) plus regression tests with a non-calendar period name.
- D-plan 7 (session 3, 2.1 consolidation): the future-date guard lives at
  TWO places only — `postEntry` 's Phase-2.2 branch (the single choke point
  every GL-posting document path flows through) and one explicit
  controller guard on `inventoryController.createStockMovement`, whose GL
  path bypasses `postEntry`. NO duplicate checks at the already-green
  sites; verified instead: each path's catch maps the propagated
  `BusinessRuleError` to the correct client status — recordPurchase and
  createInvoice via `handleBusinessError` (400), updateInvoice via its
  trailing `handleBusinessError` delegation (400 — regression case added:
  a future date on an invoice update is refused with 400, not 500),
  createGoodsReceipt via its explicit `instanceof BusinessRuleError`
  branch (400). "At the controller" (tasks.md 2.1) is met by the observable
  contract: every HTTP create path refuses a future date with 400 before
  any persisted write (snapshot-identical, no period row) — five cases
  green (purchase, invoice, invoice-update, GRN dated 2030-01-01 per the
  done-when verbatim, stock adjustment). The stock-movement catch also
  maps `inside closed accounting period` → 409, and task 0.2's HTTP
  regression (ACCT-005: adjustment dated 2026-01-15, 2026-01 closed → 409,
  GL 1200/7100 no lines) proves that branch.

## Task mapping (tasks.md → work)

- 0.1 primitive guard + done-when test (direct call, closed period).
- 0.2 already done; add regression proving 409 via HTTP for closed-period
  stock movement.
- 0.3 model guards + direct-model-call tests.
- 1.1 GRN void guard + PUR-003-style HTTP test (409, GL 1200/2000 unchanged).
- 1.2 supplier refund closed-period HTTP regression.
- 1.3 restore guard + HTTP test.
- 2.1 future-date 400 across the four domains + no period created.
- 2.2 postEntry future-date refusal + postEntry inside an admin-opened future
  period still succeeds.
- 2.3 explicit open test (non-admin denied, admin succeeds).
- 3.1 non-calendar closed name → 409 on a mutating path (payment void).
- 4.x extend `closedPeriodImmutability.test.ts`: snapshot GL/ledger/stock
  totals before refusals; byte-identical totals after; invariant suite call.
- 5.x full gates; update proposal (residual-gap block → verified state);
  archive via `node scripts/openspec-archive-guard period-protection-primitive -- -y`.

## Test-runner notes

- `npx jest` inside `server/` sets TEST_ADMIN_PASSWORD from setup.ts; targeted
  red-first runs before each fix, full suite before commit.
- Blast-radius watch: primitive-level guard can surface in any suite that
  voids closed-period journal groups inside its own flow. Triage each
  breakage: correct refusal (fix expectation) vs legitimate flow blocked
  (revisit design).
