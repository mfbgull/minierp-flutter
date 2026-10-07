# `MINIERP-CONSOLIDATED-FORENSIC-AUDIT.md`

```markdown
# MiniERP — Consolidated Forensic Audit
## Deduplicated & Unified Across Four Audit Artifacts

**Sources merged:**
- `audit-purchases-ap-report.md` — Purchases & AP (PUR-001…PUR-016)
- `CONSOLIDATED-AUDIT.md` — Cross-domain consolidated (C-xx, H-xx, M-xx, CODE-xx, SEC-xx, DB-xx, GL-xx, TEST-01)
- `forensic-audit-full.md` — Full-stack forensic (ACCT-001…ACCT-007, CODE-001…CODE-004)
- `SALES-FORENSIC-AUDIT.md` — Sales (SALES-001…SALES-022)

**Target:** `github.com/mfbgull/minierp-flutter` @ `8ed73cf2` (working tree)
**Stack:** Flutter desktop client (397 files / ~134k LOC) + Node/Express 5 + better-sqlite3 12 + zod 4 (~80k LOC TS) + SQLite (86 tables, 86 migrations)
**Method:** read-only static trace **plus execution of the real model code against throwaway databases**. Every quantitative claim was measured, not reasoned. The live databases were never opened for writing. All artifacts live in `/tmp/opencode/paudit/`, `/tmp/audit-reports/`, `/tmp/sales-audit/`.
**Verification basis:** backend suite **114 suites / 993 tests green**; `npx tsc --noEmit` clean; `npx eslint` 0 errors.

---

# Part 0 — Duplicate Issue Map

This is the core deliverable: every finding that appeared in **two or more** source artifacts, mapped to one canonical ID. The canonical ID is chosen as the most descriptive/earliest, and all source IDs are listed.

| Canonical ID | Issue | Sources | Severity |
|---|---|---|---|
| **PUR-001** | Purchase void double-reverses inventory; phantom 7200; wrong period | `audit-purchases-ap-report.md` PUR-001 · `CONSOLIDATED-AUDIT.md` C-03 · `forensic-audit-full.md` ACCT-001 | **CRITICAL** |
| **PUR-002** | AP aging double-counts reversal credits (`reversed_by IS NULL` missing) | `audit-purchases-ap-report.md` PUR-002 · `CONSOLIDATED-AUDIT.md` H-01 · `forensic-audit-full.md` ACCT-002 | **HIGH** |
| **PUR-003** | GRN void has no closed-period guard | `audit-purchases-ap-report.md` PUR-003 · `CONSOLIDATED-AUDIT.md` H-02 + GL-001 · `forensic-audit-full.md` ACCT-006 | **HIGH** |
| **PUR-004** | Four competing definitions of current AP position | `audit-purchases-ap-report.md` PUR-004 + PUR-011 · `CONSOLIDATED-AUDIT.md` H-04 | **HIGH** |
| **PUR-005** | Future-dated documents accepted; auto-create open period | `audit-purchases-ap-report.md` PUR-005 · `CONSOLIDATED-AUDIT.md` CODE-05 · `forensic-audit-full.md` ACCT-005 (sibling) · `SALES-FORENSIC-AUDIT.md` SALES-011 | **MEDIUM** |
| **PUR-006** | AP aging ignores `asOfDate` | `audit-purchases-ap-report.md` PUR-006 · `CONSOLIDATED-AUDIT.md` M-01 | **MEDIUM** |
| **PUR-007** | Cross-PO line receipt (no `poItem.po_id === po_id` check) | `audit-purchases-ap-report.md` PUR-007 · `CONSOLIDATED-AUDIT.md` M-01 | **MEDIUM** |
| **PUR-008** | No price-variance / landed-cost mechanism; three-way match absent | `audit-purchases-ap-report.md` PUR-008 · `CONSOLIDATED-AUDIT.md` M-01 + §2 (GRNI) | **MEDIUM** |
| **PUR-009** | `roundQty` applied to money; unrounded `unit_price` into batch | `audit-purchases-ap-report.md` PUR-009 · `CONSOLIDATED-AUDIT.md` M-01 · `SALES-FORENSIC-AUDIT.md` SALES-020 | **MEDIUM** |
| **PUR-010** | GRN client idempotency key never sent; partial double-receive | `audit-purchases-ap-report.md` PUR-010 · `CONSOLIDATED-AUDIT.md` M-01 | **MEDIUM** |
| **PUR-012** | No lower-bound quantity guard in receipt model | `audit-purchases-ap-report.md` PUR-012 | **LOW** |
| **PUR-013** | Receipts accept a warehouse different from the PO's | `audit-purchases-ap-report.md` PUR-013 | **LOW** |
| **PUR-014** | `purchases.balance_amount` no floor at zero | `audit-purchases-ap-report.md` PUR-014 | **LOW** |
| **PUR-015** | `backfillGlPreposting` re-posts voided purchases; no ledger leg on receipts | `audit-purchases-ap-report.md` PUR-015 · `CONSOLIDATED-AUDIT.md` M-01 | **LOW** |
| **PUR-016** | Duplicate-PO-commitment fix residual on live data | `audit-purchases-ap-report.md` PUR-016 | **INFO** |
| **SALES-005** | Edit paid invoice to zero total voids revenue, posts nothing | `SALES-FORENSIC-AUDIT.md` SALES-005 · `CONSOLIDATED-AUDIT.md` H-05 | **HIGH** |
| **SALES-007** | Soft-deleted invoices remain in every AR surface | `SALES-FORENSIC-AUDIT.md` SALES-007 · `CONSOLIDATED-AUDIT.md` H-06 | **HIGH** |
| **SALES-002** | Negative `tax_rate` accepted; revenue inflated, no 2100 | `SALES-FORENSIC-AUDIT.md` SALES-002 · `CONSOLIDATED-AUDIT.md` H-08 | **HIGH** |
| **SALES-016** | Quotation tax and discount dropped schema-deep | `SALES-FORENSIC-AUDIT.md` SALES-016 · `CONSOLIDATED-AUDIT.md` H-07 | **HIGH** |
| **SALES-011** | Future-dated sale auto-creates open accounting period | `SALES-FORENSIC-AUDIT.md` SALES-011 · `CONSOLIDATED-AUDIT.md` CODE-05 · `audit-purchases-ap-report.md` PUR-005 | **MEDIUM** |
| **SALES-010** | Backdated to closed period returns HTTP 500 not 409 | `SALES-FORENSIC-AUDIT.md` SALES-010 · `CONSOLIDATED-AUDIT.md` CODE-04 | **MEDIUM** |
| **SALES-012** | Duplicate `invoice_no` via PUT → HTTP 500; no per-item validation | `SALES-FORENSIC-AUDIT.md` SALES-012 · `CONSOLIDATED-AUDIT.md` CODE-06 | **MEDIUM** |
| **SALES-014** | Cancelled invoices are terminal; no reinstate | `SALES-FORENSIC-AUDIT.md` SALES-014 · `CONSOLIDATED-AUDIT.md` CODE-07 | **LOW** |
| **SALES-018** | Non-numeric money blocked only by accidental NOT NULL | `SALES-FORENSIC-AUDIT.md` SALES-018 · `CONSOLIDATED-AUDIT.md` CODE-03 | **LOW** |
| **CODE-001** | Period protection is a call-site convention, not a primitive property | `forensic-audit-full.md` CODE-001 · `CONSOLIDATED-AUDIT.md` GL-001 + H-02 (same class) · `SALES-FORENSIC-AUDIT.md` SALES-013 (no period guard on restore) | **HIGH** |
| **CODE-002** | `postFinancialEntryForAdjustment` silent on zero value | `forensic-audit-full.md` CODE-002 | **LOW** |
| **CODE-003** | `glTotals` sums debit and credit separately → blind to credit-side defects | `forensic-audit-full.md` CODE-003 · `CONSOLIDATED-AUDIT.md` TEST-01 · `audit-purchases-ap-report.md` PUR-001 guard gap | **HIGH** |
| **CODE-004** | Positive observations / non-findings adjudicated | `forensic-audit-full.md` CODE-004 | **INFO** |
| **CODE-005** | No shared typed invoice-item schema | `CONSOLIDATED-AUDIT.md` CODE-01 · `SALES-FORENSIC-AUDIT.md` SALES-003 + SALES-018 (symptoms) | **HIGH** |
| **CODE-006** | Client/server discount cap divergence | `CONSOLIDATED-AUDIT.md` CODE-02 · `SALES-FORENSIC-AUDIT.md` SALES-006 (secondary) | **MEDIUM** |
| **ACCT-003** | Zero-cost adjustment/opening batches understate COGS | `forensic-audit-full.md` ACCT-003 · `CONSOLIDATED-AUDIT.md` C-04 (related flag-on COGS) | **MEDIUM-HIGH** |
| **ACCT-004** | AR aging does not foot when `due_date` is NULL | `forensic-audit-full.md` ACCT-004 · `SALES-FORENSIC-AUDIT.md` SALES-017 | **MEDIUM** |
| **ACCT-007** | Supplier-refund void has no closed-period guard | `forensic-audit-full.md` ACCT-007 · (covered structurally by CODE-001) | **LOW-MEDIUM** |
| **C-01** | Void of `adjust` settlement pays cash twice | `CONSOLIDATED-AUDIT.md` C-01 | **CRITICAL** |
| **C-02** | `refund_expected` on unpaid doc fabricates cash | `CONSOLIDATED-AUDIT.md` C-02 | **CRITICAL** |
| **C-04** | Flag-on COGS at standard cost; layer never relieved | `CONSOLIDATED-AUDIT.md` C-04 · (related to ACCT-003) | **CRITICAL** (gated) |
| **C-05** | Return void books phantom shrinkage (7200) | `CONSOLIDATED-AUDIT.md` C-05 | **CRITICAL** |
| **C-06** | PO-return layer key mismatch; feature dead | `CONSOLIDATED-AUDIT.md` C-06 | **CRITICAL** |
| **H-03** | Refunds not capped by collected cash | `CONSOLIDATED-AUDIT.md` H-03 | **HIGH** |
| **H-04** | Four AP-position definitions (see PUR-004) | `CONSOLIDATED-AUDIT.md` H-04 | **HIGH** |
| **SEC-001** | SQL injection via unquoted column name | `CONSOLIDATED-AUDIT.md` SEC-001 | **CRITICAL** |
| **SEC-002** | Catch-all validator validates nothing | `CONSOLIDATED-AUDIT.md` SEC-002 | **CRITICAL** |
| **SEC-003** | HTTP response sent inside DB transaction | `CONSOLIDATED-AUDIT.md` SEC-003 | **HIGH** |
| **SEC-004** | Raw SQLite error text returned to client | `CONSOLIDATED-AUDIT.md` SEC-004 | **HIGH** |
| **DB-001** | `goods_receipt_items` has zero indexes | `CONSOLIDATED-AUDIT.md` DB-001 | **HIGH** |
| **DB-002** | No DB-level debit==credit enforcement | `CONSOLIDATED-AUDIT.md` DB-002 | **HIGH** |
| **DB-003** | Migration checksums skip ~74% of applied migrations | `CONSOLIDATED-AUDIT.md` DB-003 | **HIGH** |
| **GL-002** | Master GL-balance assertion can be deleted; A–D have no planted-drift tests | `CONSOLIDATED-AUDIT.md` GL-002 · `forensic-audit-full.md` (related CODE-003) | **HIGH** |
| **GL-003** | Stored float artefact `166.79999999999998` live | `CONSOLIDATED-AUDIT.md` §7c · `forensic-audit-full.md` §0 | **MEDIUM** |
| **GL-004** | Closed-period bypass via non-calendar period names | `CONSOLIDATED-AUDIT.md` GL-004 | **MEDIUM** |
| **GL-005** | `stock-authority-map.md` "single history writer" claim false | `CONSOLIDATED-AUDIT.md` GL-005 | **MEDIUM** |
| **GL-006** | Unrounded money reaches `journal_lines` outside `postEntry` | `CONSOLIDATED-AUDIT.md` GL-006 | **MEDIUM** |
| **GL-007** | 5 money-moving endpoints have no idempotency | `CONSOLIDATED-AUDIT.md` GL-007 | **MEDIUM** |
| **SALES-001** | Invoice-scope discount never reduces tax base | `SALES-FORENSIC-AUDIT.md` SALES-001 | **HIGH** |
| **SALES-003** | `tax_rate > 100%` accepted on invoice path | `SALES-FORENSIC-AUDIT.md` SALES-003 | **MEDIUM** |
| **SALES-004** | `PUT /api/invoices/:id` not idempotency-keyed; inline payment bypasses writer | `SALES-FORENSIC-AUDIT.md` SALES-004 | **HIGH** |
| **SALES-006** | Header discount ≥ line total → zero-value invoice relieves stock | `SALES-FORENSIC-AUDIT.md` SALES-006 | **MEDIUM-HIGH** |
| **SALES-008** | `INVOICE_SETTLEMENT` ceiling ignores prior payments | `SALES-FORENSIC-AUDIT.md` SALES-008 | **HIGH** |
| **SALES-009** | Client `amount` override accepted on packed lines | `SALES-FORENSIC-AUDIT.md` SALES-009 | **MEDIUM-HIGH** |
| **SALES-013** | `restoreInvoice` no period guard; stale COGS | `SALES-FORENSIC-AUDIT.md` SALES-013 | **MEDIUM** |
| **SALES-015** | Multi-warehouse sales never split | `SALES-FORENSIC-AUDIT.md` SALES-015 | **MEDIUM** |
| **SALES-017** | SO→invoice conversion drops due date | `SALES-FORENSIC-AUDIT.md` SALES-017 | **MEDIUM** |
| **SALES-019** | POS split-tender creates unbounded AR on WALK-IN | `SALES-FORENSIC-AUDIT.md` SALES-019 | **MEDIUM** |
| **SALES-021** | `createLedgerEntry` seeds balance without `reversed_by` filter | `SALES-FORENSIC-AUDIT.md` SALES-021 | **LOW** |
| **SALES-022** | Stale documentation on return-ledger date | `SALES-FORENSIC-AUDIT.md` SALES-022 | **INFO** |

---

# Part 1 — Executive Summary

**Overall risk rating: HIGH.**

The double-entry engine is genuinely strong — one posting chokepoint (`accountingService.ts:306-311`) enforces exact integer minor-unit balance with zero epsilon, foreign keys are enforced in production, all 35 route files apply `authenticateToken`, and no unbalanced entry exists anywhere in the live database. But **every high-severity finding is balanced-but-wrong**: a journal entry debits and credits in equal measure, so invariants A–E stay green while inventory is destroyed, cash is fabricated, or revenue is inflated.

This is precisely the failure mode `known-issues.md` §4 documents — *"a green suite bounds the questions it asks"* — and it has recurred in at least six independent forms across four audit passes.

**Live-data impact already present:**
- `purchases.id=38` carries an active `Dr 7200 5000 / Cr 1200 5000` beside a fully voided original group (PUR-001). The originating movement is `stock_movements.id=120`, `reference_doctype='PURCHASE_VOID'`, `financial_posted=1`. GL 1200 net for this void = **−5000**; GL 7200 = **+5000**. Correct answer: 0/0.
- AP aging reports supplier 1 as **−4,000** where the truth is **+1,000** (PUR-002). The double-counted reversal credits total **5,000**; correct credits 19,150 vs coded 24,150; debits 20,150 → coded aging = −4,000, correct = +1,000, which ties to `suppliers.current_balance = 1000`.
- A stored float artefact exists at `journal_lines.id 297/298` (`journal_entry_id 46`): **`166.79999999999998`** (GL-003).

**Top 5 Accounting Issues:**
1. **Cash paid twice for one customer entitlement (C-01).** Voiding an `adjust` settlement frees the cumulative cap without unwinding the application; the same return can then be settled again by another type. **Proven: 1,600 of bank cash paid out for a 1,600 entitlement already credited to the customer.**
2. **Cash fabricated out of nothing (C-02).** `refund_expected` is accepted on a *fully unpaid* source document. Measured: a 100 purchase, fully returned as `refund_expected`, books `Dr Cash 100` with no money ever received.
3. **Purchase void double-reverses inventory (PUR-001).** Voiding a purchase posts a second inventory credit on top of voiding the original. GL 1200 goes to **−500** (a credit balance on a debit-normal asset) plus a phantom `Dr 7200` shrinkage. **Already on live data**: `purchases.id=38` carries an active `Dr 7200 5000 / Cr 1200 5000` beside a fully voided original group (10× larger than one source reported).
4. **COGS at standard cost instead of layer cost, and the layer never relieved (C-04, PROVEN).** With `feature_batch_locations='1'`, a purchase-created batch yields COGS at `items.standard_cost` (**999**) instead of the real layer cost (**100**), `batchId: null`, and `quantity_remaining` frozen at **20** after selling 5. The layer is never relieved, so it can be consumed again.
5. **Return void books a phantom shrinkage expense (C-05)** and **return void of a refund_expected return never reverses the supplier refund (C-02 family)** — leaving phantom cash, a spurious AP of 200, and `suppliers.current_balance` overstated by 100 after a "successful" void.

**Top 5 Code / Architecture Issues:**
1. **Four different definitions of "current AP position"** — `getGLReconciliation` (`MAX(id)`), `SupplierLedger.getBalance` (`transaction_date DESC`), `rebuildBalances` (`id ASC`), `computeAPAging` (`SUM` with no date filter). They disagree on any backdated entry; the supplier-balance API serves **100** where the GL, the subledger and the invariants all say **150**.
2. **The PO-return path is broken in production and masked by its own test fixture (C-06).** `PurchaseReturn` looks up the cost layer by `source_id = purchase_order_items.id`, but production writes `source_id = goods_receipt_items.id`. Measured: the simplest 1-line PO return fails 100% with *"Insufficient stock in the source batch"*. `purchaseReturn.test.ts:197-211` hand-writes `source_id = poItemId`, which production never does.
3. **One shared typed invoice-item schema is missing (CODE-005).** `validation.ts` uses `items: z.array(z.any())`; `validateInput`, `createInvoice` and `updateInvoice` each re-derive different partial checks. This single gap is the root of at least 5 separate findings.
4. **Client/server monetary divergence in discount handling (CODE-006).** The client caps an invoice-scope discount at the tax-exclusive subtotal; the server caps at the tax-inclusive `linesTotal`. A discount above the subtotal makes the invoice unsavable (HTTP 400).
5. **Tax is computed before an invoice-scope discount is applied (SALES-001),** so output tax is charged on gross consideration. The discount reduces revenue/AR but never the tax base.

**Immediate triage order:**
1. **PUR-001** (one-line fix; live data already affected, 5,000 phantom)
2. **PUR-002** (one-line SQL fix; live aging report already wrong by 5,000)
3. **PUR-003** (period guard on GRN void — same primitive as PUR-001's sibling)
4. **C-01 / C-02 / C-05 / H-03** (cash-fabrication and double-payment paths; not yet observed on live data but fully reachable)
5. **C-06** (PO-return feature completely dead in production; masked by a test fixture)

**Not fixable by repair:** the absence of a GRNI account and a supplier-invoice entity (PUR-008) requires schema + flow addition, not a patch. Until that exists, "accrued/uninvoiced receipts" is not a number this system can produce.

---

# Part 2 — Chart of Accounts (Live, `is_active = 1`)

| Code | Name | Type | Normal balance |
|---|---|---|---|
| 1000 | Cash | asset | debit |
| 1010 | Bank | asset | debit |
| 1020 | Easypaisa / Mobile Wallet | asset | debit |
| 1030 | JazzCash | asset | debit |
| 1040 | UPaisa | asset | debit |
| 1100 | Accounts Receivable | asset | debit |
| 1110 | Customer Credit | asset | credit (contra-asset) |
| **1200** | **Inventory Asset** | asset | debit |
| 1300 | Employee Loan Receivable | asset | debit |
| **2000** | **Accounts Payable** | liability | credit |
| 2100 | Tax Payable | liability | credit |
| 3000 / 3100 / 3200 / 3300 | Owner's Equity / Retained Earnings / Owner Capital / Owner Drawings | equity | — |
| 4000 / 4100 / 4150 | Sales Revenue / Sales Returns / Restocking Fee Income | revenue | — |
| 5000 / 6000 / 6100 / 6300 | COGS / Operating Expenses / Wages / Loan Write-off | expense | debit |
| 7000 | Production Clearing | expense | debit |
| 7100 | Inventory Correction | expense | debit |
| **7200** | **Inventory Shrinkage** | expense | debit |
| 7201–7204 | Expired / Damaged / Shortage / Obsolete Goods Loss | expense | debit |

Seeded at `server/src/migrations/add-gl-foundation.sql:36-52`, extended by `add-cash-accounts.sql`. **There is no goods-received-not-invoiced (GRNI) account.**

---

# Part 3 — Consolidated Findings

Severity: **CRITICAL** (live books wrong / silent misstatement / cash fabricated) · **HIGH** (material reporting or control failure) · **MEDIUM** (real defect, bounded or conditional) · **LOW** (hygiene / latent) · **INFO** (assessment).

Every finding includes all source-artifact IDs so no reader has to cross-reference.

---

## CRITICAL

### PUR-001 · Purchase void reverses inventory twice, books phantom 7200, and dates the reversal "today"
**Sources:** `audit-purchases-ap-report.md` PUR-001 · `CONSOLIDATED-AUDIT.md` C-03 · `forensic-audit-full.md` ACCT-001

**Files:** `server/src/models/Purchase.ts:661-675` (and `:654-657`); mechanism `server/src/models/StockMovement.ts:213-223` and `:455-470`

`Purchase.void` voids the original `Dr 1200 / Cr 2000` group, then requests a *second* inventory effect through `recordMovement` with `movement_type: 'ADJUSTMENT'`. `recordMovement` routes every ADJUSTMENT to `postFinancialEntryForAdjustment`, posting `Dr 7200 / Cr 1200`. `skipAdjustmentFinancialPosting` — the flag introduced for precisely this class (`known-issues.md` item 1) — is not set. The GRN void path does the equivalent with a raw INSERT and is correct (`PurchaseOrder.ts:722-740`); the asymmetry is the defect.

**Measured (clean DB, supplier-linked 10 @ 50 = 500):**
- After create: `1200 {dr:500}`, `2000 {cr:500}`
- After void: `1200 {dr:0, cr:500}`, `2000 {dr:0, cr:0}`, `7200 {dr:500, cr:0}`
- Correct: `1200 = 0`, `7200 = 0`. Inventory reversed 200%, plus phantom shrinkage.
- Supplier-less 3 @ 10 = 30: `1200 {dr:0, cr:30}`, `7200 {dr:30, cr:0}` — credit balance on a debit-normal asset.
- `movement_date = new Date()` (`Purchase.ts:671`), not `purchase_date` — cross-period. Measured: purchase 2026-01-15, leg 2026-10-06.

**Live database:** `purchases.id 38` (`PURCH-2026-0038`, `total_cost 5000`, `voided_at 2026-08-24 14:46:55`) has both original lines `voided = 1` **and** an active `stock_adjustment` pair `reference_id 120`: `Dr 7200 5000 / Cr 1200 5000`. Net GL 1200 = −5000 (credit balance on a debit-normal asset); GL 7200 = +5000 phantom shrinkage. `stock_movements.id=120`, `reference_doctype='PURCHASE_VOID'`, `financial_posted=1`.

**Guard gap — `known-issues.md` §4 recurring.** `server/src/__tests__/supplierlessPurchase.test.ts:260` asserts `glTotals(db,'1200').debit ≈ 0`. `glTotals` (`:94-104`) sums debit and credit **separately**, so `debit = 0` is satisfied while `credit = 30`. Measured: all three shipped assertions pass (`1000.credit=0`, `2000.credit=0`, `1200.debit=0`) while the unasserted `1200.credit = 30` and `7200.debit = 30`.

**Fix:**
1. Add `skipAdjustmentFinancialPosting: true` to the `recordMovement` payload (`Purchase.ts:662-672`).
2. Pass `movement_date: purchase.purchase_date` instead of `new Date()`.
3. Tighten the test to assert `glTotals(db,'1200').credit ≈ 0` **and** `glTotals(db,'7200').debit ≈ 0`, and add `expectAllInvariantsHold` after the void — one call would have caught it.
4. **Live-data repair:** for each voided purchase, check for an active `stock_adjustment` pair with `reference_doctype='PURCHASE_VOID'`; void it via `voidJournalLinesByReference('stock_adjustment', <movement_id>)` inside a transaction. On the current live DB that is `reference_id 120` (5,000).

**Standard.** Reversing a document voids the original entry; it never posts a second one. Where a stock reversal is also required, write the movement without a financial leg — the `voidGoodsReceipt` pattern.

---

### C-01 · Void of an `adjust` settlement pays cash twice for one entitlement
**Source:** `CONSOLIDATED-AUDIT.md` C-01

**Flow:** Sales Returns · **File:** `invoiceReturnService.ts:1111` (`payment_id: null`) → `:1269`

`applyAdjust` creates a real payment + allocation but records `payment_id: null`. `revertSettlement`'s adjust branch is gated on that field, so the allocation is never voided and the `CREDIT_OFFSET` GL group is never voided — while the settlement is marked void and `syncSettledAmount` frees the cap.

**Impact (measured):** after a "successful" void the target invoice keeps `paid_amount 1600 / balance 0` with two live `CREDIT_OFFSET` lines. Freed cap ⇒ the same return settles again: `adjust 1600 → void → refund 1600`, **GL 1010 delta −1600**. Real cash out, twice.

**Fix:** capture `recordCustomerPayment(...).paymentId` into the settlement row; void the `CREDIT_OFFSET` group in the adjust branch (mirroring the refund branch at `:1246`).

---

### C-02 · `refund_expected` on an unpaid document fabricates cash
**Source:** `CONSOLIDATED-AUDIT.md` C-02

**Flow:** Purchase Returns · **File:** `PurchaseReturn.ts:466-484` (disposition gate), `SupplierRefund.ts`

**Impact (measured):** purchase 100 unpaid → return all goods with `refund_expected` ⇒ `Dr Cash 100 / Cr AP 100` posted with **no money received**. A user can manufacture a cash asset and an AP credit from nothing.

**Fix:** require cash-collected > refund amount before honouring `refund_expected`.

---

### C-04 · Flag-on COGS at standard cost; cost layer never relieved
**Source:** `CONSOLIDATED-AUDIT.md` C-04 · (related to `forensic-audit-full.md` ACCT-003)

**Flow:** Warehouses/Valuation · **File:** `StockMovement.ts:690`, `:928-935`

`syncBatchStockByLocationForNewBatch` (`:690`) is wired **only** into physical-count (`PhysicalCount.ts:695`) and transfer-mirror paths (`:1156`, `:1297`, `:1409`). `Purchase.ts`, `PurchaseOrder.ts` and `Production.ts` contain **zero** references to `batch_stock_by_location`. So with the flag on, a purchase-created batch has no location coverage ⇒ `consumeFromOldestBatches` takes the legacy branch and returns `{batchId: null, unitCost: items.standard_cost}`.

**Impact (measured, flag ON, layer cost 100, `standard_cost` 999):** consuming 5 units returned `unitCost: 999, batchId: null`, and `stock_batches.quantity_remaining` stayed at **20**. Three consequences: COGS overstated 10×; the layer is never relieved so it can be re-consumed; `Invoice.ts` keys the return-restore loop on `batch_id`, so returns can never restore the right layer.

**Gating:** the flag defaults to `'0'` (`add-batch-location-model.sql:24`), so there is **no current production impact**. This is a trap: flipping the flag silently corrupts COGS on every sale of purchased goods.

**Fix:** call `syncBatchStockByLocationForNewBatch` from every batch-creation site; or delete the flag and the location table until they are finished.

---

### C-05 · Return void books a phantom shrinkage expense
**Source:** `CONSOLIDATED-AUDIT.md` C-05

**Flow:** Sales Returns · **File:** `invoiceReturnService.ts:1426-1440`

Voiding a return records a negative ADJUSTMENT posting `Dr 7200 / Cr 1200`. The create-side twin at `Invoice.ts:738` correctly sets `skipAdjustmentFinancialPosting: true`; the void side does not. This **falsifies `known-issues.md` item 1's "only setter" claim** — there is a fourth setter.

**Impact (measured):** void of a 2-unit return at cost 100 ⇒ **−200 net profit**, invariant H breaks 0 → −200. Non-additive across voids.

**Fix:** add `skipAdjustmentFinancialPosting: true` at `:1426`.

---

### C-06 · PO-return path broken in production, masked by its test
**Source:** `CONSOLIDATED-AUDIT.md` C-06

**Flow:** Purchase Returns · **File:** `PurchaseReturn.ts:462-470` vs `PurchaseOrder.ts:950-960`

The return looks up the cost layer with `source_type='GOODS_RECEIPT' AND source_id = <purchase_order_items.id>`, but `addReceipt` writes `source_id = <goods_receipt_items.id>`. Independent autoincrement sequences.

**Impact (measured):** a 1-line PO receipt then return **fails 100%** — *"Insufficient stock in the source batch for W: available 0, required 2."* Where ids coincidentally collide, it silently consumes another receipt's layer (saved only by the `item_id` guard). The PO return feature is non-functional.

**Why CI is green:** `purchaseReturn.test.ts:197-211` seeds `source_id = poItemId` — a shape production never writes.

**Fix:** key the lookup on the receipt item id; make the test fixture go through `addReceipt`.

---

### SEC-001 · SQL injection via unquoted column name — **verified reachable**
**Source:** `CONSOLIDATED-AUDIT.md` SEC-001

`forecastService.ts:1167-1183`. `setModelConfig` iterates `Object.entries(config)` and splices **`key` raw and unquoted** into SQL:
```ts
sets.push(`${key} = ?`);                                  // :1170
db.prepare(`UPDATE forecast_model_config SET ${sets.join(', ')} WHERE item_id = ?`)   // :1177
```
Values are bound; **keys are not**. The route `PUT /api/forecasts/models/:itemId` (`routes/forecasts.ts:26`) applies `validateZodBody(zodBodySchemas.modelConfig)` — but that schema is `z.object({}).passthrough()` (`validation.ts:302`), which **validates nothing**. Controller spreads `{ item_id: itemId, ...req.body }` (`forecastsController.ts:157`).

**Impact:** any user holding only the low-tier `forecasts:create` permission can write arbitrary columns and inject arbitrary SQL expressions/subqueries into `forecast_model_config`, giving a boolean/read oracle over any table. `better-sqlite3.prepare()` refuses multiple statements, so no stacked `DROP` — but this is a genuine read/write primitive.

**Fix:** strict zod schema; iterate a hardcoded field→value map and reject unknown keys.

---

### SEC-002 · The catch-all validator validates nothing
**Source:** `CONSOLIDATED-AUDIT.md` SEC-002

`validation.ts:78` — `object: z.object({}).passthrough()` is used on ~20 mutating routes. This is the systemic enabler of SEC-001.

---

## HIGH

### PUR-002 · AP aging double-counts ledger reversal credits; reports AP as 0 or negative
**Sources:** `audit-purchases-ap-report.md` PUR-002 · `CONSOLIDATED-AUDIT.md` H-01 · `forensic-audit-full.md` ACCT-002

**File:** `server/src/models/Reports.ts:355-358` (credit side of `computeAPAging`)

```sql
SELECT supplier_id, SUM(credit) FROM supplier_ledger
WHERE voided = 0 AND credit > 0 GROUP BY supplier_id
```

This omits `reversed_by IS NULL`. `ledgerUtils.reverseLedgerEntry` (`ledgerUtils.ts:104-137`) inserts an equal-and-opposite `REVERSAL:*` row with `reversed_by = <original id>` and `voided = 0`, and marks the original `voided = 1`. **Every** other consumer excludes `reversed_by` — `rebuildBalances` (`SupplierLedger.ts:91`), `getBalance` (`:68`), `getGLReconciliation` (`Reports.ts:1302`, `:1306`), invariant D (`__tests__/helpers/accountingInvariants.ts:132`, `:136`), `getSupplierBalances` (`SupplierLedger.ts:136`). AP aging alone counts it, so a void is charged twice: the original debit is dropped **and** the reversal credit is applied against a different, still-live debit.

**Measured (probe):**
- Purchases 100 (2026-01-05) + 200 (2026-01-06); void the 100 one. True AP = **200** (GL 2000 credit 200, `suppliers.current_balance` 200, `getBalance()` 200). `getAPAgingReport` → **`totalPayables = 100`**.
- Purchases 100/200/300; void the 300 one. True AP = **300**. `getAPAgingReport` → **`totalPayables = 0`**. AP disappears entirely.
- **Live database, supplier 1:** `suppliers.current_balance = 1000`; aging gross debits 20150; aging credits counted 24150; aging reported AP = **−4000** — a negative payable. Under-report = **5000**. Correct credits (with `reversed_by IS NULL`) = 19150; correct AP = 20150 − 19150 = **+1000**, which ties to `current_balance` exactly.

**Guards blind to it.** Measured on the same state: `apImbalances() = []`, `supplierApImbalances() = []`, `getGLReconciliation` AP `delta: 0`.

**Fix:** Add `AND reversed_by IS NULL` to `Reports.ts:356-358`, matching `SupplierLedger.ts:91`.

**Standard.** A reversal row is the correction half of a voided pair; counting it while also excluding the original double-counts the correction. One ledger, one exclusion rule.

---

### PUR-003 · GRN void has no closed-period guard; the purchase void has one
**Sources:** `audit-purchases-ap-report.md` PUR-003 · `CONSOLIDATED-AUDIT.md` H-02 + GL-001 · `forensic-audit-full.md` ACCT-006

**Files:** `server/src/controllers/purchaseOrderController.ts:315-345` vs `server/src/controllers/purchaseController.ts:268`

`voidPurchase` calls `AccountingService.assertPeriodNotClosed(db, purchase.purchase_date, …)`. `voidGoodsReceipt` has no equivalent, and `AccountingService.voidJournalLinesByReference` (`accountingService.ts:1402-1428`) is a bare `UPDATE journal_lines SET voided = 1` with no period logic. Period protection exists only where a caller remembers to add it — an open-by-default primitive.

**Measured:** With period `2026-03` closed, a GRN dated 2026-03-05 voided **successfully**: `GL 1200 1600 → 1100`, `GL 2000 1600 → 1100`. A closed period's journal entry was un-posted and the stock/AP reversal applied inside it. `assertPeriodNotClosed` throws correctly for the same date (`"GRN is dated 2026-03-05 inside closed accounting period '2026-03'"`), proving the guard exists and simply is not called.

**Fix:** Call `AccountingService.assertPeriodNotClosed(db, receipt.receipt_date, …)` in `voidGoodsReceipt` before the model call, and move the check into `voidJournalLinesByReference` so no caller can bypass it. See also CODE-001.

**Standard.** A closed period is immutable; any mutation of a dated financial line — including an un-void — is blocked at the primitive, not at the call site.

---

### PUR-004 · Four competing definitions of current AP position
**Sources:** `audit-purchases-ap-report.md` PUR-004 + PUR-011 · `CONSOLIDATED-AUDIT.md` H-04

**Files:**
- `Reports.ts:1300-1310` (`MAX(id)` over `voided = 0` rows)
- `SupplierLedger.ts:66-71` (`getBalance`: `ORDER BY transaction_date DESC, id DESC`)
- `SupplierLedger.ts:89-93` (`rebuildBalances`: `ORDER BY id ASC`)
- `Reports.ts:334-341` (`computeAPAging`: `SUM(debit) - SUM(credit)` with no date filter)

They disagree on any backdated entry. `getGLReconciliation` reads the `MAX(id)` row's stored `balance`; after a `reverseLedgerEntry` the highest-id non-voided row **is** the reversal row, and `rebuildBalances` updates only rows matching `voided = 0 AND reversed_by IS NULL`. Reversal rows therefore keep the one-off value `reverseLedgerEntry` computed against a pre-void read (`ledgerUtils.ts:113-119`) and are never refreshed.

**Measured:** Purchases 100/200/300, void the 300 one: reconciliation row `{gl_balance: 300, operational_balance: 300, delta: 0}` — correct *only* because the two errors cancel. On a two-purchase variant the same read returned `operational_balance` off the true net. The column is undefined after a void, so correctness here is accidental.

**Backdated measurement (PUR-011):** Purchases dated 2026-05-01 (100) then backdated 2026-01-15 (50), same supplier:
```
rebuildBalances (id order)  → suppliers.current_balance = 150
SupplierLedger.getBalance() → 100
```
`GET /api/purchase-orders/suppliers/:id/balance` (`purchaseOrderController.ts:472-488`) therefore serves **100** while the GL, `suppliers.current_balance`, invariant G and `getGLReconciliation` all say **150**. Invariant D reads `current_balance`, not `getBalance`, so it is blind to this.

**Fix:** Compute the AP side as `SUM(debit) - SUM(credit)` over `voided = 0 AND reversed_by IS NULL` grouped by supplier — the expression invariant D already uses (`__tests__/helpers/accountingInvariants.ts:132-136`). Make `getBalance` order by `id DESC` over the same filtered set `rebuildBalances` uses, or return `suppliers.current_balance` directly.

**Standard.** A reconciliation aggregates the ledger. It does not trust a denormalised running column whose maintenance rules differ from the ledger's own. A running balance has one canonical ordering.

---

### PUR-005 · Future-dated documents accepted and silently open future accounting periods
**Sources:** `audit-purchases-ap-report.md` PUR-005 · `CONSOLIDATED-AUDIT.md` CODE-05 · `forensic-audit-full.md` ACCT-005 (sibling) · `SALES-FORENSIC-AUDIT.md` SALES-011

**Files:** `server/src/services/accountingService.ts:313-347`; `server/src/services/InvoiceCreationService.ts:61-76`; `server/src/controllers/inventoryController.ts:578-621` (ACCT-005 sibling)

No upper bound on `po_date`, `receipt_date`, `purchase_date`, `invoice_date` or any adjustment date anywhere in the purchase or sales path. `postEntry` reads "no open period covers the entry date" as an instruction to create one: it inserts the calendar-month period as `open` and logs a warning.

**Measured:**
- A GRN dated `2030-01-01` was accepted and created `accounting_periods {period_name: '2030-01', status: 'open'}`. That period then accepts postings, so period-close discipline is bypassable by future-dating.
- A future-dated sale (`2099-12-31`) succeeded and auto-created an open period `2099-12` (`SALES-FORENSIC-AUDIT.md` §7 SALES-011).
- **ACCT-005 sibling:** With period `2026-01` closed and a manual stock adjustment dated `2026-01-15`, the adjustment posted `GL 1200 {dr:100}, 7100 {cr:100}` into the closed period — because `postLegacyStockEntry` (`accountingService.ts:434`) performs no period check and `createStockMovement` adds none.

**Fix:** Reject a document date later than today at the controller; require an explicit "open period" action rather than auto-creating one from a document date. For ACCT-005 specifically, call `assertPeriodNotClosed(db, movement_date, ...)` in `createStockMovement`, or move the check into `postLegacyStockEntry`.

**Standard.** A document date *selects* a period; it never *creates* one.

---

### PUR-006 · AP aging ignores `asOfDate`
**Source:** `audit-purchases-ap-report.md` PUR-006 · `CONSOLIDATED-AUDIT.md` M-01

**File:** `server/src/models/Reports.ts:334-341` (`debitRows`): `WHERE sl.voided = 0 AND sl.debit > 0` — no `transaction_date <= asOfDate`. The credit query at `:352-354` likewise.

**Measured:** With a purchase dated `2031-01-01` of 500 on the books, `getAPAgingReport('2026-01-01')` returned `totalPayables = 600`, including the 2031 purchase — and bucketed it `current_amount`, because `Reports.ts:379-381` treats `ageDays <= 0` as current. Every historical AP aging figure is overstated by all future-dated purchases.

**Fix:** Add `AND sl.transaction_date <= ?` to both queries in `computeAPAging`, bound to `asOfDate`.

**Standard.** An as-of report filters on the as-of date on **both** sides of the net.

---

### PUR-007 · A goods receipt can be booked against a line item belonging to a different purchase order
**Source:** `audit-purchases-ap-report.md` PUR-007 · `CONSOLIDATED-AUDIT.md` M-01

**File:** `server/src/models/PurchaseOrder.ts:876-889` and `:921-926`

The `po_item_id` lookup is `SELECT * FROM purchase_order_items WHERE id = ?`. **`poItem.po_id` is never compared to the route's `po_id`** — in either the validation loop or the write loop.

**Measured:** PO-A (supplier SUP-A, line price 100) and PO-B (supplier SUP-B, line price 777), both Submitted. A receipt posted on **PO-A** with **PO-B's** `po_item_id`, qty 5, was accepted:
```
GOODS_RECEIPT GL = Dr 1200 3885 / Cr 2000 3885     ← 5 × 777 (PO-B's price)
supA ledger       = GOODS_RECEIPT debit 3885        ← PO-A's supplier
poA/poB received  = PO-B advanced by 5               ← PO that does not own the goods
```
Inventory valued at another PO's price, payable raised against the wrong supplier, receipt progress booked to the wrong PO.

**Fix:** Assert `poItem.po_id === po_id` in both loops; also validate in the controller.

---

### PUR-008 · No price-variance or landed-cost mechanism exists; three-way match absent
**Source:** `audit-purchases-ap-report.md` PUR-008 · `CONSOLIDATED-AUDIT.md` M-01 + §2 (GRNI analysis)

**Files:** `server/src/models/PurchaseOrder.ts:957`, `:977`, `:1016`; client `lib/features/purchase_orders/receive_goods_dialog.dart:150-156`; schema `server/src/middleware/validation.ts:159-164`

Batch `unit_cost = poItem.unit_price` (`:957`); movement `unit_cost = poItem.unit_price` (`:977`); `totalAmount += roundQty(received_qty × poItem.unit_price)` (`:1016`). The receipt payload carries only `{po_item_id, received_quantity}` and the Zod schema is `items: z.array(z.any()).min(1)` — **no cost field exists anywhere in the flow**.

**Impact:** Price variance is not mis-posted, it is *unrepresentable*. The system has no way to record what the supplier actually billed. The variance can only be forced by editing the PO (Draft only) or by re-keying the delivery as a direct purchase, which posts a **second, independent** `Dr 1200 / Cr 2000` for the same goods. Inventory and AP are permanently at PO price; landed cost never reaches 1200; there is no variance account (receipts touch only 1200 and 2000).

**GRNI analysis (from `audit-purchases-ap-report.md` §2):**
- `grep -rn "supplier_invoice|supplierInvoice|vendor_invoice" server/src` → **0 hits**. There is no supplier-invoice entity.
- `grep -rn "GRNI|goods.received.not.invoiced|2050|Accrued|accrued" server/src lib/` → **0 hits**. No GRNI account.
- The GRN credits **2000 Accounts Payable** directly (`PurchaseOrder.ts:1028-1035` → `accountingService.ts:596-597`). 2000 conflates received-and-invoiced, received-not-invoiced, and legacy rows with no dimension to separate them.
- `purchases.invoice_no VARCHAR(100)` (`add-purchases-table.sql:14`) is free-text with no index and no uniqueness; live DB has no index on it and no duplicate values.

**Fix:** Add an optional per-line `unit_cost`/`landed_cost` to the receipt; post the receipt at the received cost; route `(received_cost − po_price) × qty` to a purchase-price-variance P&L account; add a guard forbidding recording a supplier invoice as a direct purchase for goods already received via a GRN. For GRNI: introduce a `2xxx Goods Received Not Invoiced` liability account; credit it (not 2000) at `PurchaseOrder.ts:1028`; add a `supplier_invoices` table + `SUPPLIER_INVOICE` reference type; post the reclassifying entry `Dr GRNI / Cr 2000` on invoice receipt.

---

### PUR-009 · `purchases.total_cost` is rounded to quantity precision (3 dp), not money precision
**Sources:** `audit-purchases-ap-report.md` PUR-009 · `CONSOLIDATED-AUDIT.md` M-01 · `SALES-FORENSIC-AUDIT.md` SALES-020

**File:** `server/src/models/Purchase.ts:185` — `const totalCost = roundQty(quantity * unit_cost)` (`roundQty` from `server/src/utils/quantity`). Compare `PurchaseOrder.ts:139` and `:173`, which use `addCurrency`/`multiplyCurrency`/`roundCurrency`.

**Measured:** Purchase 3 @ 33.333:
```
purchases.total_cost  = 99.999
supplier_ledger.debit = 99.999
GL Cr 2000            = 100.00     ← postEntry normalises to 2 dp (accountingService.ts:273)
```
Subledger AP and GL AP differ by 0.001 per affected purchase, permanently. `purchases.balance_amount` (`Purchase.ts:393`, `:491`) is computed from the 3-dp `total_cost`, so the document's own "Amount Due" disagrees with the GL.

**Related, distinct:** the GRN path writes `poItem.unit_price` into `stock_batches.unit_cost` unrounded (`PurchaseOrder.ts:957`) while the GL posts the 2-dp line total (`:1026`). Measured: 7 @ 3.335 → batch value 23.345 vs GL `Dr 1200 23.35` — a 0.005 divergence per receipt accumulating against invariant H. Both sit under the `> 0.005` tolerance in `__tests__/helpers/accountingInvariants.ts:247`, so neither is caught. (SALES-020 records the same class at `InvoiceCreationService.ts:206` and `invoiceController.ts:571`.)

**Fix:** `roundCurrency(quantity * unit_cost)` at `Purchase.ts:185`; round `unit_price` to 2 dp before it reaches `stock_batches` in `addReceipt`; at `InvoiceCreationService.ts:206`/`invoiceController.ts:571`, use `addCurrency(cogsAmount, multiplyCurrency(entry.consumed, entry.unitCost))`.

**Standard.** Money is rounded once, at the boundary, to the currency's minor unit. A quantity-precision rounding function must never be applied to money.

---

### PUR-010 · The GRN client's idempotency key is never sent; a duplicated partial receipt double-receives
**Source:** `audit-purchases-ap-report.md` PUR-010 · `CONSOLIDATED-AUDIT.md` M-01

**Files:** `lib/data/repositories/purchase_order_repository.dart:171-180`; `lib/features/purchase_orders/receive_goods_dialog.dart:128-156`

`createReceipt` takes no `idempotencyKey` parameter and the dialog sends none, so the server's `PURCHASE_ORDER_RECEIPT` guard (`server/src/controllers/purchaseOrderController.ts:391-401`) is **dead code from this client**. `receive_goods_dialog.dart:128-142` also has **no `if (_saving) return;` early guard** in `_save()` — it relies on the button being disabled (`onPressed: _saving ? null : _save`, `:307`) and on `onFieldSubmitted: submitOnEnter(_save)` (`:377`) not racing. Compare the direct-purchase client, which does send a payload-derived key (`lib/features/purchases/purchase_form_dialog.dart:216-240`).

**Measured at the model level:** Four sequential 6-unit attempts against a 10-unit line: first accepted, next three rejected (`"Cannot receive more than pending quantity (4)"`). A *full* line is therefore protected by the pending check. But a **partial** receipt leaves pending > 0, so a duplicated request is accepted: 5 of 10 submitted twice yields two receipts, two cost layers, two `Dr 1200 / Cr 2000` pairs, and `received_quantity = 10`. Indistinguishable from a genuine second delivery.

**Fix:** Add `idempotencyKey` to `createReceipt`, derived from the payload as `purchase_form_dialog.dart:216` does; add `if (_saving) return;` at the top of `_save`.

---

### SALES-005 · Editing an invoice down to a zero total voids the original GL, posts nothing, leaves a bare `Cr 1100`
**Sources:** `SALES-FORENSIC-AUDIT.md` SALES-005 · `CONSOLIDATED-AUDIT.md` H-05

**Files:** `server/src/controllers/invoiceController.ts:578`, `:588`; `server/src/services/accountingService.ts:525`

`updateInvoice` is **void-then-repost** with no floor on the repost:
```ts
// invoiceController.ts:578-595
AccountingService.voidJournalLinesByReference(db, 'INVOICE', invoiceId, {…});
const updatedTaxAmount = InvoiceModel.getInvoiceTaxTotal(db, invoiceId);
AccountingService.postInvoiceEntry(db, { … totalAmount: totalAmountNum, … });
```
and `postInvoiceEntry` returns `null` rather than throwing when the total is non-positive:
```ts
// accountingService.ts:525
if (!args.totalAmount || args.totalAmount <= 0) return null;
```
The only over-payment guard (`:437`) covers a **new** payment in the same request; nothing prevents editing the **lines** of an invoice that already carries payments.

**Measured (scenario M — a 400.00 invoice fully paid 400.00, then edited so the lines total 0.00):**
```
invoice row : { status:'Paid', total_amount:0, paid_amount:400, balance_amount:0, payment_status:'Paid' }

live GL lines touching this invoice:
  INVOICE   1100 Accounts Receivable   D=400  C=0     voided=1   ← original sale DEBIT removed
  INVOICE   4000 Sales Revenue         D=0    C=400   voided=1
  INVOICE   5000 Cost of Goods Sold    D=200  C=0     voided=1
  INVOICE   1200 Inventory Asset       D=0    C=200   voided=1
  PAYMENT   1000 Cash                  D=400  C=0     voided=0   ← payment survives
  PAYMENT   1100 Accounts Receivable   D=0    C=400   voided=0   ← bare CREDIT, no offsetting debit
```
Result: **GL `1100` carries a 400.00 credit for which no sale exists; GL `4000` carries no revenue at all.** The sub-ledger says "Paid, balance 0". The **trial balance stays perfectly balanced**, so invariant A passes and nothing alerts. A later `getGLReconciliation` AR pairing reports a delta of 400.00.

**Fix:** Before voiding, reject the edit when the invoice already has recorded payments/credit and the recomputed `totalAmountNum` is `<= 0` (or `< paid_amount`) — mirror `Invoice.ts:1091-1102`'s paid-lock, which `cancelInvoiceInternal` already has and `updateInvoice` does not. Alternatively, when `totalAmountNum <= 0` and payments exist, post an explicit balancing reversal (`Dr 4000 / Cr 1100` for the residual) instead of silently voiding.

**Accounting reference.** IAS 1.27 / IFRS 15.25 — a receivable may not be derecognised without derecognising the corresponding revenue.

---

### SALES-007 · Soft-deleted invoices remain in every AR surface, producing an AR/GL divergence equal to the deleted invoice total
**Sources:** `SALES-FORENSIC-AUDIT.md` SALES-007 · `CONSOLIDATED-AUDIT.md` H-06

**Files:** `server/src/controllers/invoiceController.ts:753-754`; `server/src/utils/reportSql.ts:68-70`

`deleteInvoice` performs an AUD-06 soft delete: the row survives with `status = 'Deleted'`, `deleted_at` stamped — but **`balance_amount` is left at its full value**. `AR_OUTSTANDING` excludes only `('Cancelled','Draft')`:
```ts
// reportSql.ts:68-70
export const AR_OUTSTANDING = (alias = ''): string =>
  `${p}balance_amount > 0 AND ${p}status NOT IN ('Cancelled', 'Draft')`;
```
No AR surface filters `deleted_at IS NULL` — `grep -rn "deleted_at" src/` shows the predicate exists only in `models/Invoice.ts:285, 331` and `models/Customer.ts:105, 127`, `models/Item.ts:115`. AR aging, top debtors, DSO, receivables summary, dashboard AR cards and the `getGLReconciliation` AR pairing read `invoices` directly.

**Measured (scenario K — a 400.00 invoice soft-deleted, GL lines voided as `deleteInvoice` does):**
```
AR_OUTSTANDING rows            : { n: 9, total: 3056.00 }
GL 1100 (debit-normal, live)   : { net: 2656.00 }
=> getGLReconciliation AR delta = 3056.00 − 2656.00 = 400.00   == exactly the deleted invoice
```

**Fix:** Add `'Deleted'` to `AR_OUTSTANDING` **and** filter `deleted_at IS NULL` inside `AR_OUTSTANDING` itself so a future soft-delete status cannot repeat the bug. Then re-examine every `netRevenueSum` consumer (`Reports.ts:122, 1083, 1091, 1098`), which filters only `NET_REVENUE_STATUS` = `status != 'Cancelled'` (`reportSql.ts:43-44`) and therefore also counts deleted invoices as revenue.

---

### SALES-002 · Negative `tax_rate` accepted; GL silently credits revenue with the tax-inclusive total and omits `2100`
**Sources:** `SALES-FORENSIC-AUDIT.md` SALES-002 · `CONSOLIDATED-AUDIT.md` H-08

**Files:** `server/src/services/accountingService.ts:533-556`; `server/src/services/InvoiceCreationService.ts:71-75`; `server/src/middleware/validation.ts:104-108`

Two compounding defects:
1. No bound on `tax_rate` for `POST /api/invoices`. `validateInput` (`InvoiceCreationService.ts:71-75`) checks `item_id`, `quantity`, `unit_price` and never `tax_rate`; the zod schema is `items: z.array(z.any())` (`:107`), which validates nothing.
2. `postInvoiceEntry` selects the 3-line vs 2-line form with **`if (taxAmount > 0)`** (`accountingService.ts:536`). A *negative* `taxAmount` fails that test, so it takes the 2-line no-tax branch and credits `4000` with the **full `totalAmount`**, which already nets out the negative tax. `2100` is never touched.

**Measured (scenario E — 2 @ 100, `tax_rate: -50`):**
```
invoice_items : { amount: 100.00, net_amount: 200.00, tax_amount: -100.00 }   ← negative tax STORED
GL            : Dr 1100  100.00
                Cr 4000  100.00      ← revenue = gross (200) − tax (100); the tax vanished into revenue
                (no 2100 line)
Dr 5000 / Cr 1200 : 100.00 / 100.00  ← COGS posted normally
```
Revenue is **overstated by 100.00 on a 200.00 sale (+100%)**, and a negative liability is never recognised.

**Fix:** (a) Reject `tax_rate < 0` (and `> ` a configured cap) in `InvoiceCreationService.validateInput` and in a typed zod item schema, matching `validation.ts:181`. (b) Change `if (taxAmount > 0)` to `if (taxAmount !== 0)` so a negative tax can never silently take the no-tax branch.

**Accounting reference.** IAS 1.34 / IFRS 15 B5 — revenue is recognised at the fair value of the consideration; a negative output tax is not revenue.

---

### SALES-016 · Quotation → sales order → invoice silently drops line tax (and discount) end-to-end
**Sources:** `SALES-FORENSIC-AUDIT.md` SALES-016 · `CONSOLIDATED-AUDIT.md` H-07

**Files:** `server/src/models/Quotation.ts:595-605`; `server/src/models/SalesOrder.ts:649-655`; `server/src/migrations/add-full-sales-cycle.sql`

`quotation_items` **has** `tax_rate`, `discount_type`, `discount_value` (`Quotation.ts:39, 62`; schema `add-full-sales-cycle.sql:38-42`). `sales_order_items` **has none** — verified on the DB copy:
```sql
CREATE TABLE sales_order_items (
  id, so_id, item_id, quantity, delivered_quantity, unit_price, amount,   -- no tax, no discount
  …
);
```
`convertToSalesOrder` writes only those columns:
```ts
// Quotation.ts:595-605
const soItemStmt = db.prepare(`
  INSERT INTO sales_order_items (so_id, item_id, quantity, unit_price, amount)
  VALUES (?, ?, ?, ?, ?)`);
```
and `convertToInvoice` then hard-codes the discount off and omits tax:
```ts
// SalesOrder.ts:649-655
items: (salesOrder.items || []).map((item) => ({
  item_id: item.item_id, quantity: item.quantity, unit_price: item.unit_price,
  amount: item.amount, discount_type: 'none' as const,     // ← no tax_rate
})),
```

**Financial impact.** Tax negotiated and recorded on a quotation is **never** recognised: `invoice_items.tax_rate` is 0 → `getInvoiceTaxTotal` returns 0 → `postInvoiceEntry` takes the 2-line branch → **no `Cr 2100 Tax Payable` at all**. The invoice header total equals the quotation total (because `item.amount` is passed as the `amount` override), so the *arithmetic* reconciles while the *tax* silently disappears. Revenue is understated by the tax relative to a direct invoice of the same goods, and output tax liability is understated by 100% on the entire quotation-driven share of sales.

**Fix:** Add `tax_rate DECIMAL(5,2) DEFAULT 0`, `discount_type VARCHAR(20) DEFAULT 'percentage'`, `discount_value DECIMAL(15,2) DEFAULT 0` to `sales_order_items` via a migration; backfill from `quotation_items`; carry them through `Quotation.convertToSalesOrder` and `SalesOrder.convertToInvoice`.

---

### SALES-004 · `PUT /api/invoices/:id` is not idempotency-keyed and records payments outside the payment writer
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-004

**Files:** `server/src/controllers/invoiceController.ts:426-465`; `lib/features/sales/sales_invoice_form_page.dart:1069-1076`

The update path records an inline payment by calling the **model** directly rather than `PaymentRecordingService`:
```ts
// invoiceController.ts:445-465
const newPaymentNo = InvoiceModel.generatePaymentNoAtomic(db);
const newPaymentId = InvoiceModel.createPayment(db, newPaymentNo, parsedCustomerId, …);
InvoiceModel.createPaymentAllocation(db, newPaymentId, invoiceId, newPaymentAmount);
InvoiceModel.createLedgerEntry(db, parsedCustomerId, 'PAYMENT', newPaymentNo, …);
AccountingService.postPaymentEntry(db, { paymentId: newPaymentId, … });
```
That bypasses `PaymentRecordingService.recordCustomerPayment` (`services/PaymentRecordingService.ts:33-83`), which is the **only** place `beginIdempotentWrite` / `claimIdempotencyKey` (`:34-51`, `:77-80`) is applied to customer payments. `assertNoActivePosting` (`accountingService.ts:1065`) is not called either — its only callers are `OwnerCapital.ts:69` and `OwnerWithdrawal.ts:225, 286`.

The Flutter client only sends an `Idempotency-Key` on **create**:
```dart
// sales_invoice_form_page.dart:1071-1076
final result = _isEdit
    ? await invRepo.update(widget.invoice!.id, body)          // ← no key
    : await invRepo.create(body, idempotencyKey: _createIdempotencyKeyFor(body));
```

**Financial impact.** A retried `PUT` (client timeout, user double-tap, proxy retry) creates **two `payments` rows, two `payment_allocations`, two `Dr 1000 / Cr 1100` journal entries, and two `customer_ledger` PAYMENT credits** for one intended receipt. Cash is overstated in the GL and in `collectFlows`; `paid_amount` is double-inflated and `balance_amount` clamps to 0. There is no GL/AR divergence — both sides move together — which is precisely why it is invisible to invariants A–E.

**Fix:** (a) Wrap the inline-payment block in `startIdempotentRequest(db, req.headers, IDEMPOTENCY_SCOPES.PAYMENT_CUSTOMER, hashRequestPayload(req.body))` + `claimIdempotencyKey`, matching `invoiceController.ts:1025-1033`. (b) Prefer routing through `PaymentRecordingService.recordCustomerPayment({ mode: 'INVOICE_SETTLEMENT', … })` so the allocation ceiling (`paymentValidation.ts:64-84`) and the period guard (`paymentWriterCore.ts:30-32`) apply. (c) Add `assertNoActivePosting` for the invoice's own `INVOICE` reference inside the transaction.

---

### SALES-008 · `INVOICE_SETTLEMENT` allocation ceiling ignores payments already received → overpayment accepted, leaving a credit balance in a debit-normal asset
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-008

**File:** `server/src/services/paymentValidation.ts:31-40`
```ts
function allocationCeiling(mode, invoice): AllocationCeiling {
  if (mode === 'REFUND') return null;
  if (mode === 'INVOICE_SETTLEMENT') {
    return { amount: parseCurrency(invoice.total_amount) - parseCurrency(invoice.returned_amount) };
  }
  return { amount: parseCurrency(invoice.balance_amount) };
}
```
The `INVOICE_SETTLEMENT` branch uses the invoice **gross total**, not the outstanding balance — so it ignores everything already collected.

**Measured (scenario O — a 500.00 invoice, then a 200.00 partial payment, then a second 400.00 payment):**
```
after payment 1 (200): { status:'Overdue', paid_amount:200, balance_amount:300 }
   GL: Dr 1000 200.00 / Cr 1100 200.00
payment 2 of 400 ACCEPTED (ceiling was 500, remaining was 300) → 100.00 OVERPAYMENT
   GL: Dr 1000 400.00 / Cr 1100 400.00
final: { paid_amount: 600, balance_amount: 0 }        ← clamped by ledgerUtils.ts:177
```
Consequences:
1. GL `1100` (asset, debit-normal) now carries a **credit balance** of 100.00 for that invoice.
2. `balance_amount` clamps to 0, so `AR_OUTSTANDING` (`balance_amount > 0`) **drops the invoice entirely** — the operational AR loses 300.00 while GL `1100` still holds the credit. That is a live, quantified AR-vs-GL break.
3. `payment_status` reports `'Overpaid'` **only if the return status is `'None'`** (`ledgerUtils.ts:220-221`); the Overdue branch at `:232-237` then overwrites it. MEASURED: status came back `'Overdue'`, not `'Overpaid'`.
4. Per `known-issues.md` item 6 the H9 policy routes overpayments to **`1110 Customer Credit`**; `postPaymentEntry` (`accountingService.ts:602-604`) *always* credits `1100`.

**Fix:** Change the `INVOICE_SETTLEMENT` ceiling to `max(0, balance_amount)` — the outstanding amount, which is what `ledgerUtils.ts:173-177` already computes. If overpayment is a legitimate business case, make it an explicit mode with an explicit posting (`Dr 1100 / Cr 1110`).

---

### H-03 · Refunds not capped by collected cash on the settlement path
**Source:** `CONSOLIDATED-AUDIT.md` H-03

**File:** `invoiceReturnService.ts:965-1001` vs the capped legacy path `:1133`

**Measured:** **600 of cash paid out on an invoice where cash collected was 0** (settled entirely by store credit). Any store-credit-settled invoice is convertible to cash on return. Violates REVERSAL-RULES §1.12.

**Fix:** Cap refunds at cash actually collected on the invoice.

---

### GL-002 · The master GL-balance assertion can be deleted and all 993 tests stay green
**Source:** `CONSOLIDATED-AUDIT.md` GL-002 · (related `forensic-audit-full.md` CODE-003)

`expectAllInvariantsHold` (`__tests__/helpers/accountingInvariants.ts:288-298`) *does* call all nine collectors — **none is exported-but-unasserted.** But only **E, F, G, H, I** have planted-drift meta-tests proving the master's line is live. **A, B, C, D have none.** The helper's own docstring claims *"every one has a planted-drift guard"* — **that claim is false for A, B, C, D.** Deleting the entire GL-balance assertion at `:290` leaves the suite green. This is `known-issues.md` §4 recurring at the top of the hierarchy.

**Fix:** Add planted-drift meta-tests for A, B, C, D; correct the docstring.

---

### CODE-001 · Period protection is a call-site convention, not a property of the primitives
**Sources:** `forensic-audit-full.md` CODE-001 · `CONSOLIDATED-AUDIT.md` GL-001 + H-02 · `SALES-FORENSIC-AUDIT.md` SALES-013 (no period guard on restore)

`assertPeriodNotClosed` exists and is correct, but it is invoked at **22 call sites** while the primitives it protects are open by default:
- `voidJournalLinesByReference` (`accountingService.ts:1402`) — bare `UPDATE`, no period logic.
- `postLegacyStockEntry` (`accountingService.ts:434`) — no period logic.
- `recordMovement`'s adjustment-financial hook (`StockMovement.ts:213-223`).
- `restoreJournalLinesByReference` (`accountingService.ts:1443-1468`) — bare `UPDATE voided = 0`.

PUR-003, ACCT-005, ACCT-007 and SALES-013 are the same defect observed at four different call sites. The pattern "the guard exists but this caller forgot it" has already produced at least one prior remediation round (the customer-payment paths are guarded in three places), which is evidence the convention does not hold under change.

**Fix:** Move the check into the primitives — `voidJournalLinesByReference`, `postLegacyStockEntry` and `restoreJournalLinesByReference` — so a caller cannot bypass it by omission. This converts four findings into zero.

---

### SEC-003 · HTTP response sent inside a DB transaction
**Source:** `CONSOLIDATED-AUDIT.md` SEC-003

`employeeController.ts:688` — `res.status(201).json(...)` executes inside the `db.transaction()` callback opened at `:653`. The client receives 201 for a loan that may still fail to commit; a retry double-posts.

---

### SEC-004 · Raw SQLite error text returned to the client in 24 places
**Source:** `CONSOLIDATED-AUDIT.md` SEC-004

`inventoryController` ×9, `purchaseOrderController` ×6, `employeeController` ×4, `invoiceController` ×2, `salesController` ×2, `invoiceReturnController` ×2, `purchaseReturnController` ×2, `expenseController` ×1. Leaks table/column/constraint names. `errorHandler.ts:20` correctly keeps stacks server-side — these are separate raw-message paths.

---

### DB-001 · `goods_receipt_items` has zero indexes
**Source:** `CONSOLIDATED-AUDIT.md` DB-001

All three FK columns (`receipt_id`, `po_item_id`, `item_id`) unindexed; `PRAGMA index_list` is empty. Every parent delete/update full-scans the goods-receipt hot path. The existing `add-missing-fk-indexes.sql` does not cover it.

---

### DB-002 · debits == credits has zero database enforcement
**Source:** `CONSOLIDATED-AUDIT.md` DB-002

`add-gl-foundation.sql:57-72` gives `journal_lines` only *per-line* CHECKs (`debit=0 OR credit=0`). **No cross-line CHECK, no trigger.** Enforcement is application-only at `accountingService.ts:306`, plus a boot post-condition at `database.ts:2974-2983`.

**Why this matters:** the FK-OFF, non-transactional rebuild path (`database.ts:114-127`) and the `--rollback` CLI execute raw SQL with no such guard. This is precisely why every C-rated finding is "balanced-but-wrong" in the app layer yet could be trivially unbalanced at the DB layer.

---

### DB-003 · Migration checksum verification skips ~74% of applied migrations
**Source:** `CONSOLIDATED-AUDIT.md` DB-003

73 of 99 ledger rows carry checksum `'inline'` (all `fn.*` runner keys, whose key names a function rather than a file), and `verifyMigrationChecksums` **skips them** (`database.ts:181`). Verification does run at boot (`:1594`, before `listen`) — so editing an already-applied `.sql` executed by an inline runner is **invisible**.

---

### SALES-001 · Invoice-scope (header) discount never reduces the tax base
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-001

**Files:** `server/src/utils/currency.ts:74-76`, `:145-151`

Line tax is computed on the post-item-discount net (`currency.ts:74-75`). The invoice-scope discount is then subtracted from `linesTotal` — which *already contains tax* — at `currency.ts:151`. It therefore reduces revenue and AR but leaves `2100 Tax Payable` untouched. The identical discount expressed as an **item**-scope discount reduces the tax base.

**Measured, same trade both ways (4 @ 100, 10% tax, 10% discount):**

| Scope | `Cr 4000` | `Cr 2100` | `Dr 1100` |
|---|---|---|---|
| item-scope | 360.00 | **36.00** | 396.00 |
| invoice-scope | 360.00 | **40.00** | 400.00 |

**Output tax overstated by 4.00 (11.1%) purely from the discount scope**, and the AR/revenue side also disagrees by 4.00.

**Fix:** Allocate the header discount pro-rata across lines *before* the tax step and recompute per-line tax — i.e. move the header discount into `decomposeLineAmount` as a second discount term, mirroring `invoiceReturnService.allocateHeaderDiscount` on the return side.

**Accounting reference.** IAS 21.12; IFRS 15 B5–B8 and B34 — discounts reduce the transaction price and therefore the taxable consideration.

---

### SALES-009 · Client-controlled `amount` override accepted on **packed** lines; `invoice_items` desynchronises from `unit_price × quantity`
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-009

**Files:** `server/src/utils/currency.ts:62-65`, `:29-32`; `server/src/middleware/validation.ts:107`

`decomposeLineAmount` honours an `amount` override whenever it is positive, with **no check that the item is a loose/amount-driven sale**:
```ts
// currency.ts:62-65
const override = parseCurrency(args.amount);
const gross = override > 0
  ? roundCurrency(override)
  : multiplyCurrency(args.quantity, args.unit_price);
```
The docstring at `currency.ts:29-32` states the override is for *"loose amount-driven lines"*. Only the **client** enforces the restriction:
```dart
// sales_invoice_form_page.dart:948
if (line.isLoose) 'amount': line.amount,
```
The server never checks `items.sale_type`. POS is accidentally protected (`validation.ts:177-184` declares item fields explicitly); `POST /api/invoices` is not (`items: z.array(z.any())`).

**Measured (scenario N — `sale_type = 'packed'`, quantity 1, `unit_price` 10, `amount` 999999):**
```
stored line : { quantity:1, unit_price:10, amount:999999, net_amount:999999, tax_amount:0, sale_type:'packed' }
GL          : Dr 1100 999999.00 | Cr 4000 999999.00 | Dr 5000 50.00 | Cr 1200 50.00
```
The stored row is **internally inconsistent**: `unit_price × quantity = 10 ≠ amount = 999999`. Gross margin on that line reads as 999,999 − 50. The entry is balanced, so no invariant fires.

**Fix:** Reject `amount` on a line whose `items.sale_type != 'loose'`, inside `InvoiceCreationService.create` (where `item_id` is available). Add the corresponding zod refinement.

---

### CODE-005 · No shared typed invoice-item schema (root cause of ≥5 findings)
**Sources:** `CONSOLIDATED-AUDIT.md` CODE-01 · `SALES-FORENSIC-AUDIT.md` SALES-003 + SALES-018 (symptoms)

`validation.ts` uses `items: z.array(z.any()).min(1)` with `.passthrough()`; `validateInput`, `createInvoice` and `updateInvoice` each re-derive different partial checks. This single gap is the root of SALES-002, SALES-003, SALES-009, SALES-012, SALES-018 and half of SALES-015.

**Fix:** One shared `invoiceItemSchema` (item_id / quantity / unit_price / tax_rate / discount_type / discount_value / amount) applied at `validation.ts`, `InvoiceCreationService.validateInput`, `Invoice.createInvoice` and `invoiceController.updateInvoice`. Closes five findings in one commit.

---

## MEDIUM

### CODE-006 · Client/server discount cap divergence
**Sources:** `CONSOLIDATED-AUDIT.md` CODE-02 · `SALES-FORENSIC-AUDIT.md` SALES-006 (secondary)

Client caps an invoice-scope discount at the tax-exclusive `subtotal`; the server caps at the tax-inclusive `linesTotal`. A discount above the subtotal makes the invoice unsavable (HTTP 400 `total_amount disagrees with line items`). The Flutter form is therefore *unusable* for any invoice-scope discount ≥ the pre-tax subtotal, while other API clients silently create the zero-value stock loss (see SALES-006).

**Fix:** Cap at the same base in both — either `subtotal` in `currency.ts:151` or `linesTotal` in `invoice_calculations.dart:116`.

---

### SALES-006 · Header discount ≥ line total → zero-value invoice relieves stock and posts COGS with no revenue
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-006

**Files:** `server/src/utils/currency.ts:151`; `server/src/services/accountingService.ts:525`; `server/src/services/InvoiceCreationService.ts:190-214`

`computeInvoiceGrandTotal` clamps the header discount to `linesTotal`, so an over-large discount drives the header total to exactly `0`. Stock consumption and `postCOGSEntry` run *before* the revenue posting and are not conditional on the total.

**Measured (scenario R — 1 @ 100 with 10% tax, flat header discount 5000):**
```
server grand total              = 0.00
Dr 5000 Cost of Goods Sold 50.00 | Cr 1200 Inventory Asset 50.00
(no 1100 line, no 4000 line, no 2100 line at all)
```
**Inventory worth 50.00 left the building and a COGS charge was booked against zero revenue.** The invoice's `total_amount = 0`, so `AR_OUTSTANDING` excludes it.

**Fix:** (a) Make the client and server clamp to the same base (CODE-006). (b) Add a floor: reject `discount_value` whose clamped discount would make the header total `< 0`, and reject a zero/negative grand total on a line-bearing invoice. (c) Guard `postCOGSEntry` on `totalAmount > 0`.

---

### SALES-003 · `tax_rate > 100%` accepted on the invoice path (POS is bounded)
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-003

**Measured (scenario D — 2 @ 100, `tax_rate: 500`):**
```
Dr 1100 1200.00 | Cr 4000 200.00 | Cr 2100 1000.00 | Dr 5000 100.00 | Cr 1200 100.00
```
Output tax exceeds goods value 5×. Fixed by CODE-005.

---

### SALES-010 · Backdating a sale into a CLOSED accounting period returns HTTP 500, not 409
**Sources:** `SALES-FORENSIC-AUDIT.md` SALES-010 · `CONSOLIDATED-AUDIT.md` CODE-04

**Files:** `accountingService.ts:355-360`; `businessRuleError.ts:32-47`; `InvoiceCreationService.ts` (absence)

The invoice-**create** path is the only money-moving sales write with no closed-period pre-check. `postEntry` throws `"No open accounting period covers …"` and `CLASSIFY_PATTERNS` only matches `/inside closed accounting period/i` — so it falls through to **HTTP 500**.

**Fix:** Add `AccountingService.assertPeriodNotClosed(this.db, input.invoiceDate, …)` at the top of `InvoiceCreationService.create` (inside the transaction); add `[/No open accounting period covers/i, 409]` to `CLASSIFY_PATTERNS`.

---

### SALES-012 · `PUT /api/invoices/:id` accepts a duplicate `invoice_no` (→ HTTP 500) and performs no per-item validation
**Sources:** `SALES-FORENSIC-AUDIT.md` SALES-012 · `CONSOLIDATED-AUDIT.md` CODE-06

**Measured (scenario J):** Writing a duplicate `invoice_no` throws `SQLITE_CONSTRAINT_UNIQUE` → **HTTP 500**. Two invoices then share one `invoice_no`, which breaks `reverseStockForItems`'s `WHERE reference_docno = ?` lookups (`Invoice.ts:607-617`) and `getReturnHistory`'s join (`Invoice.ts:1371`) — the stock-reversal machinery is keyed on `reference_docno`, not on `invoice_id`. Also: `quantity <= 0` → bare `Error` at `StockMovement.ts:822-824` → HTTP 500; `unit_price < 0` → negative line amount → SALES-005 path.

**Fix:** (a) Call a shared `validateInvoiceItems(items)` from `InvoiceCreationService.validateInput`, `Invoice.createInvoice` **and** `invoiceController.updateInvoice`. (b) Before `InvoiceModel.updateInvoice`, `SELECT id FROM invoices WHERE invoice_no = ? AND id <> ?` and 409 on a hit. (c) Map `SQLITE_CONSTRAINT_UNIQUE` to 409.

---

### SALES-013 · `POST /api/invoices/:id/restore` has no closed-period guard, and re-consumes stock at *today's* FIFO layers while un-voiding the *original* COGS line
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-013 · (covered structurally by CODE-001)

**Files:** `invoiceController.ts:789-918`; `accountingService.ts:1443-1468`

Three defects:
1. **No closed-period guard.** Delete in an open period → close the period → restore → `restoreJournalLinesByReference` un-voids lines dated **inside the closed period**.
2. **Stale COGS cost.** Restore re-consumes FIFO at `:823-828` and records new SALE movements, but **posts no COGS** — it only un-voids the old `Dr 5000 / Cr 1200` at their **original** layer cost (`:854`). Any intervening purchase/receipt changes which layers are oldest, and then GL `1200`/`5000` no longer equals the layer value relieved from `stock_batches`.
3. **Asymmetric undo.** `deleteInvoice` sets `payment_allocations.amount = 0` (`:736`) and may void the payment's GL lines (`:740`) and delete the payment row (`:743`). `restoreInvoice` reverses **none** of that.

**Fix:** (a) `assertPeriodNotClosed` at the top of `restoreInvoice` — or inside `restoreJournalLinesByReference`. (b) Post COGS at the newly-consumed cost and void the un-voided original, as `updateInvoice` does at `invoiceController.ts:578-604`. (c) Mirror `:736-747` in reverse.

---

### SALES-015 · Multi-warehouse sales are never split across warehouses
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-015

**Files:** `InvoiceCreationService.ts:180`; `Invoice.ts:537-588`

One warehouse is resolved **per line** and only that warehouse is drawn down. `findWarehouseForItem` returns a **single** id. When an explicit warehouse is given it validates, **warns, and proceeds anyway** on insufficiency (`Invoice.ts:546-551`, `:567-572`).

**Measured (scenario Q — item stocked WH-A = 3 @ 50 and WH-X = 5 @ 80; sale of 6 with explicit `warehouse_id = WH-A`):**
```
#### Q THREW: I4: sellable stock 3, requested 6
```
The entire 6-unit sale is **refused** even though 8 units are on hand elsewhere, and the same 6 units would have succeeded from WH-X at a *different* cost (80 vs 50) — so the FIFO-cost that reaches the GL depends on which warehouse the operator happens to pick.

**Fix:** Either implement cross-warehouse line splitting (consume from selected warehouse first, then spill), or make the rejection an explicit 400 with available quantities surfaced.

---

### SALES-017 · SO→invoice conversion drops the due date, so converted invoices can never age
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-017 · (related `forensic-audit-full.md` ACCT-004)

**Files:** `SalesOrder.ts:645`; `InvoiceCreationService.ts:61-65`, `:121`; `Invoice.ts:804`
```ts
// SalesOrder.ts:645
dueDate: invoiceData?.due_date ?? null,     // null, not undefined
```
```ts
// InvoiceCreationService.ts:121
const dueDate = input.dueDate === undefined ? defaultDueDate(input.invoiceDate) : input.dueDate;
```
`null !== undefined`, so the `+15 days` default is **skipped**, and `createInvoice` then writes `data.due_date || null` → `NULL`.

**Financial impact.** Every sales-order-converted invoice has `due_date = NULL`. `updateInvoiceStatus` only computes `Overdue` when `invoice.due_date` is truthy (`ledgerUtils.ts:235`), and `AR_OUTSTANDING` buckets on `julianday(i.due_date)` (`Reports.ts:11-14`), where `NULL` yields `NULL` → every bucket `CASE` falls to `ELSE 0`. Result: the invoice is **excluded from every AR aging bucket** while still contributing its `balance_amount` to `total_outstanding` and `totalReceivables` totals. AR aging totals therefore cannot be reconciled against their own buckets for any shop that sells via sales orders.

**Fix:** `dueDate: invoiceData?.due_date ?? undefined` at `SalesOrder.ts:645`, or make `InvoiceCreationService.ts:121` treat `null` like `undefined` (`input.dueDate == null`). The second is better.

**Also see ACCT-004 (from `forensic-audit-full.md`):** AR aging does not foot when `due_date` is NULL. `Reports.ts:7-26` — every bucket uses `julianday(?) - julianday(i.due_date)`; with NULL every comparison is NULL, so the CASE yields NULL→excluded from all five buckets, while `SUM(i.balance_amount)` in the same SELECT still counts the invoice. `invoices.due_date` is nullable (`init.sql:236`). The create path is safe — `InvoiceCreationService` computes a 15-day `defaultDueDate` (`:61-65`) when the client omits it (`:121`). But `invoiceController.updateInvoice` passes `req.body.due_date` straight through (`:415`→`:471`) with no guard, and `InvoiceModel.updateInvoice` writes it raw (`Invoice.ts:966`).

**Measured (ACCT-004):** three invoices 100/200/300, the first with NULL `due_date`: `totalReceivables = 600, buckets sum = 500 → FOOT? false`.

**Fix:** require a non-empty `due_date` in `updateInvoice` and `InvoiceModel.updateInvoice`; and/or use `COALESCE(i.due_date, i.invoice_date)` in both aging queries.

---

### SALES-019 · POS split tender can create an unbounded AR credit sale on the single shared `WALK-IN` customer
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-019

**Files:** `posController.ts:28-43`, `:178`, `:188-190`, `:236-254`

The presence of a `payments` array — **including an empty one** — selects the split-tender path, and that path drops the cash guard entirely:
```ts
// posController.ts:178, 188-192
const usesLegs = Array.isArray(body.payments);
const legs: PosPaymentLeg[] = usesLegs ? body.payments! : [{ amount: 0, payment_method: 'Cash' }];
if (!usesLegs) { /* cashReceived >= total guard lives HERE only */ }
```
`body.payments: []` therefore bypasses the guard: `legs = []` → `legsTotal = 0` → `balanceAmount = totalAmount` → `status = 'Unpaid'`. The customer is the **single shared row** created by `ensureWalkinCustomer()`, and POS passes no `creditOffset` (`:236-254`), so store credit cannot be applied at the till.

**Impact.** Every charge-later POS sale accumulates on one customer id. `AR_OUTSTANDING` reports a single "Walk-in Customer" row aggregating every credit sale, and `Dr 1100` carries the matching balance with **no per-transaction counterparty** — the receivable is not collectible from anyone. No ceiling, no credit-limit check (`customers.credit_limit` exists but is never consulted), no write-off path.

**Fix:** Require a non-empty `payments` array whenever the split path is chosen (or an explicit `charge_later: true` with a real customer); refuse POS credit sales against `WALK-IN`.

---

### ACCT-003 · Zero-cost adjustment/opening batches understate COGS
**Source:** `forensic-audit-full.md` ACCT-003 · (related `CONSOLIDATED-AUDIT.md` C-04)

**File:** `server/src/models/StockMovement.ts:143` in `recordMovement`:
```ts
const unitCost = data.unit_cost || 0;   // ← falls back to 0, never to standard_cost
```
An incoming movement with no `batch_id` and no `unit_cost` creates a cost layer at **0**. `consumeFromOldestBatches` (`:815`) then returns `unitCost: batch.unit_cost` for that layer, and `InvoiceCreationService` accumulates `cogsAmount += entry.consumed * entry.unitCost` → 0. Revenue is recognised with zero COGS; gross profit is overstated by the full cost of the units.

This is **reachable from the shipped UI**: `stock_adjustment_dialog.dart:85-90` posts `POST /api/inventory/stock-movements` with `item_id`, `warehouse_id`, `quantity`, `movement_type: 'ADJUSTMENT'` and **no `unit_cost`**. `createStockMovement` (`inventoryController.ts:578-583`) does not require or default one.

**Measured (probe, `standard_cost` 40, +10 units, no `unit_cost`):**
```
new batch unit_cost = 0, remaining = 10
adjustment GL lines = 1200 Dr 400 / 7100 Cr 400   ← GL used the standard_cost fallback
consumption = [{"batchId":1,"consumed":10,"unitCost":0}]
COGS derived from batch layers = 0
GL added: 400  COGS recognized: 0  understatement: 400
```
The GL is *not* wrong here — `postFinancialEntryForAdjustment` (`StockMovement.ts:421-432`) correctly falls back caller cost → batch cost → `items.standard_cost`. The defect is that the **batch layer** misses the same fallback, so the two diverge.

**Fix:** In `recordMovement`, default the new batch's `unit_cost` to `items.standard_cost` when `data.unit_cost` is absent; reject or warn when both are 0.

---

### CODE-002 · `postFinancialEntryForAdjustment` is silent on zero value
**Source:** `forensic-audit-full.md` CODE-002

`StockMovement.ts:469` — `if (value === 0) return;`. When caller cost, batch cost and `standard_cost` are all 0 the adjustment posts no GL and creates no audit trail. This is the "free goods enter inventory invisibly" case. Should log a warning rather than return quietly.

---

### ACCT-007 · Supplier-refund void has no closed-period guard
**Source:** `forensic-audit-full.md` ACCT-007 · (covered structurally by CODE-001)

`SupplierRefund.void` (`supplierRefundController.ts:141-152` → `SupplierRefund.ts:213`) reverses the ledger entry and posts the contra inside the transaction, but neither the controller nor the model checks the refund's period. Compare `Payment.ts:474-476`, `:613` and `paymentWriterCore.ts:31`, all of which guard the customer payment side.

**Fix:** Add `assertPeriodNotClosed(db, refund.refund_date, …)` at the top of `SupplierRefund.void` — or move the check into the primitive (CODE-001).

---

### GL-003 · Stored float artefact `166.79999999999998` live
**Sources:** `CONSOLIDATED-AUDIT.md` §7c · `forensic-audit-full.md` §0

`stock_movements.id=125` (`RETURN`, `INV-2026-242236`) posts `Dr 1200 166.79999999999998 / Cr 7100 166.79999999999998`. A stored binary-float in a money column, and the sales-return restock lands in **7100 Inventory Correction** (an expense account) rather than reversing 5000 COGS.

`PRAGMA table_info(journal_lines)` → `debit:DECIMAL(15,4), credit:DECIMAL(15,4)` on both scratch DBs, matching `add-gl-foundation.sql`. `docs/integer-money-migration-plan.md:3` states verbatim: **"Status: DESIGN / PLANNING DOCUMENT — NOT IMPLEMENTED"**. The residue that *is* real: **8 rows** carry a REAL `debit` and 8 a REAL `credit`, across **7 `journal_entry_id`** values (16 line rows, not 7), and `customer_ledger.balance` has **12 REAL** rows.

`postEntry` protects new lines via `roundCurrency` (`accountingService.ts:263`), but **three writers bypass it** — `scripts/repair-stock.ts:157`, `src/config/database.ts:1148`, and `backfillGlPreposting.ts:119` — and any of them can inject a fresh REAL.

**Fix:** Execute the integer-money migration; fix the three bypass writers; correct the stale `>0.01` tolerance line in `integer-money-migration-plan.md:316-317`.

---

### GL-004 · Closed-period bypass via non-calendar period names
**Source:** `CONSOLIDATED-AUDIT.md` GL-004

`postEntry` derives `period_name` from `YYYY-MM` and uses `ON CONFLICT(period_name) DO NOTHING` (`:327-333`). `Period.ts:91-101` accepts **arbitrary** ranges. A closed custom period (`FY2026-Q2` = Jan–Mar) does not collide, so an entry dated inside it auto-creates a fresh `2026-01` open period and **posts into a closed period**.

---

### GL-005 · `stock-authority-map.md`'s "single history writer" claim is false
**Source:** `CONSOLIDATED-AUDIT.md` GL-005

The map asserts `stock_movements` is written only by `StockMovement.ts`. **At least 8 production sites write it outside that hub**: `Purchase.ts:230`, `PurchaseOrder.ts:725,966`, `PhysicalCount.ts:340,600,657`, `Production.ts:220,299`, `inventoryController.ts:1268`. The map's own line citations are also ~6 lines stale.

---

### GL-006 · Unrounded money reaches `journal_lines` outside `postEntry`
**Source:** `CONSOLIDATED-AUDIT.md` GL-006

`repair-stock.ts:157`, `database.ts:1148-1150`, `backfillGlPreposting.ts:119` insert raw `uncovered * unitCost`. This is a live path to introduce *new* REAL artefacts — the class of defect already present as `166.79999999999998`.

---

### GL-007 · 5 money-moving endpoints have no idempotency
**Source:** `CONSOLIDATED-AUDIT.md` GL-007

`POST /api/purchase-returns`, `inventory/stock-movements`, `inventory/stock-transfers`, `inventory/physical-counts/complete`, `inventory/damaged/transfer`, `owner-equity/personal-loans/:id/repayments` — zero idempotency references. A client-sent key is also entirely **optional**: `startIdempotentRequest` returns `key: null` when the header is absent (`idempotency.ts:181`), so even correctly-guarded endpoints degrade to unguarded if a client omits it.

---

### DB-004 · 12 `.sql` migrations are dead code
**Source:** `CONSOLIDATED-AUDIT.md` DB-004

Never referenced by any `runLedgered` call: `add-full-sales-cycle.sql`, `add-sales-table.sql`, `add-customer-ar-fields.sql`, `cleanup-orphaned-stock-batches.sql` + 8 more. The source tree is not reproducible from the ledger, and several contain **non-idempotent** `INSERT`s that would duplicate rows if ever wired in.

---

### DB-005/006/007/008 · Four financial invariants enforced only in application code
**Source:** `CONSOLIDATED-AUDIT.md` DB-005–008

`stock_movements.quantity` has no CHECK · cumulative return qty ≤ line qty (schema comment admits "enforced in service") · payment allocation ≤ invoice balance · `received_quantity <= quantity`. Each is bypassable by raw SQL, a repair script, or a future writer.

---

### SALES-021 · `createLedgerEntry` seeds the running balance without the `reversed_by IS NULL` filter (latent)
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-021

`Invoice.ts:906-927` vs `ledgerUtils.ts:28-33`. `Invoice.ts`'s version picks the **newest** row regardless of position in `(transaction_date, id)` order. For a backdated invoice it reads a *later* row's balance as its seed. **Currently masked** because every caller immediately calls `rebuildLedgerBalances`. **Failure mode if the rebuild is ever removed:** every `customer_ledger.balance` from the insert onward is wrong.

**Fix:** Delete `InvoiceModel.createLedgerEntry` and route all callers through `ledgerUtils.createLedgerEntry`. One writer, one predecessor rule.

---

## LOW

### PUR-012 · No lower-bound quantity guard in the receipt model; a DB CHECK is the only backstop
**File:** `server/src/models/PurchaseOrder.ts:876-889` checks only `received_quantity > pending`. Zero and negative pass.

**Measured:** `received_quantity: -6` was accepted by `addReceipt` and rejected only by a table CHECK, surfacing as a **500** carrying the raw SQLite message rather than a 400. `received_quantity: 0` was accepted with **no error at all**, creating four zero-valued rows and no GL entry.

**HTTP surface is protected** by `purchaseOrderController.ts:373-385` (400) and the Flutter validator. Exposure is limited to non-HTTP callers.

**Fix:** Mirror the controller's bounds inside `addReceipt`; map constraint violations to 400.

---

### PUR-013 · Receipts accept a warehouse different from the PO's, silently
**File:** `server/src/models/PurchaseOrder.ts:951-953`, `:971-973`, `:996-1013`

Batch, movement and stock balance all use the receipt's `warehouse_id`; nothing compares it to `po.warehouse_id`. **Measured:** PO header warehouse 8, receipt warehouse 9 — accepted, no error.

**Fix:** Validate, or record the deviation explicitly on the receipt.

---

### PUR-014 · `purchases.balance_amount` has no floor at zero; the PO equivalent does
**File:** `server/src/models/Purchase.ts:393`, `:491` — no `MAX(0, …)`. Compare `PurchaseOrder.ts:231`, `:310`, which use `MAX(0, po.total_amount - …)`. Over-allocating a payment yields a negative "Amount Due".

---

### PUR-015 · `backfillGlPreposting` re-posts voided purchases, and posts goods receipts to the GL without the supplier-ledger leg
**File:** `server/src/migrations/backfillGlPreposting.ts:133-143` — `WHERE total_cost > 0`, **no `voided_at IS NULL`** — versus `:253-258` for receipts, which *does* filter. One-time, guarded by `schema_migrations`.

**Measured:** Void a 100 purchase, then run the backfill: a fresh `Dr 1200 100 / Cr 2000 100` is posted. `GL 1200 dr 0→130`, `GL 2000 cr 0→130`, with no matching stock or `supplier_ledger` row. `apImbalances()` → `{expected: 0, actual: 130}`. The same asymmetry on the receipts path (`:262-274`) posts `Dr 1200 / Cr 2000` with **no** `supplier_ledger` write, leaving GL AP permanently above the subledger — measured `apImbalances()` → `{expected: 200, actual: 330}`.

**Blast radius today:** the live database has **zero** `GOODS_RECEIPT` journal groups, so the receipts half has never fired. The purchases half is one-shot and already applied.

**Fix:** Add `AND voided_at IS NULL` to the purchases query; write the `supplier_ledger` leg alongside the GL leg in the receipts section.

---

### SALES-014 · Cancelled invoices are terminal: no reinstate path exists
**Sources:** `SALES-FORENSIC-AUDIT.md` SALES-014 · `CONSOLIDATED-AUDIT.md` CODE-07

There is no route or service that moves an invoice out of `'Cancelled'`. Meanwhile `updateInvoice` **does** accept a cancelled invoice (`invoiceController.ts:485-487` explicitly preserves `Cancelled` on edit) and will happily re-post revenue for it — `voidJournalLinesByReference` + `postInvoiceEntry` at `:578-595` with no status guard. That is the inconsistency: a cancelled invoice can be *edited into* an active sale while it cannot be *reinstated*.

**Fix:** Either add `POST /api/invoices/:id/reinstate`, or — cheaper — have `updateInvoice` reject any invoice whose `status === 'Cancelled'`.

---

### SALES-018 · Non-numeric money fields blocked only by accidental `NOT NULL` constraints, surface as HTTP 500
**Sources:** `SALES-FORENSIC-AUDIT.md` SALES-018 · `CONSOLIDATED-AUDIT.md` CODE-03

**Measured:**
```
unit_price: "abc"  → NOT NULL constraint failed: invoice_items.amount
unit_price: null   → NOT NULL constraint failed: invoice_items.unit_price
```
Both roll the whole transaction back; no partial write and no HTTP 201 with NULL money. The accidental backstop is `invoice_items.amount NOT NULL` plus `invoice_items.unit_price NOT NULL`. But `invoices.total_amount/paid_amount/balance_amount` are all **nullable**; if a future migration relaxes `invoice_items.amount`, `better-sqlite3` will bind `NaN` as SQL `NULL` and the SALES-005 failure reappears silently.

**Fix:** Close it with the shared item schema (CODE-005): `unit_price: z.number().min(0)`, `quantity: z.number().positive()`, plus explicit `Number.isFinite()` assertions.

---

### CODE-003 · `glTotals` test helper sums debit and credit separately → blind to credit-side defects
**Sources:** `forensic-audit-full.md` CODE-003 · `CONSOLIDATED-AUDIT.md` TEST-01 · `audit-purchases-ap-report.md` PUR-001 guard gap

`server/src/__tests__/helpers/invoiceReturnSpec.ts:348-358` sums debit and credit separately. This is what let PUR-001's `1200.credit = 500` go unasserted while `1200.debit = 0` passed.

**Fix:** Change `glTotals` to assert the **net** (`debit − credit`) per account, or assert both legs explicitly. Sweep the return suites that depend on it.

---

## INFO

### PUR-016 · Duplicate-PO-commitment bug genuinely fixed in the write path; residual not documented
**Root cause is fixed, not papered over.** `PurchaseOrderModel.updateStatus` (`PurchaseOrder.ts:569-588`) posts no GL and no `supplier_ledger` row — `void status;` at `:583` with the rationale at `:576-582`; `create` documents the removal at `:177-180`. Grep for a `PURCHASE_ORDER` ledger writer across `server/src` (excluding tests) returns only purchase-**return** source types.

**Residual, measured on the live database:** `supplier_ledger` still holds **2 active `PURCHASE_ORDER` debit rows totalling 4000** — exactly the rows `scripts/dedupe-po.js` targets, which is dry-run by default (`dedupe-po.js:20`; `--apply` to write). Those 4000 sit inside the 20150 aging gross debits behind PUR-002's live −4000 figure.

**Neither `known-issues.md` nor `gl-authority-map.md` records this residual** → the *documentation* gap is NEW. `scripts/repair-orphaned-ledger.ts` is **customer**-ledger only (`:32-45`) and offers no remedy for supplier-side orphans.

---

### CODE-004 · Positive observations / non-findings adjudicated (do not remediate)
**Source:** `forensic-audit-full.md` CODE-004

- **`rebuildLedgerBalances` ordering is correct on both sides.** `SupplierLedger.rebuildBalances` uses `ORDER BY id ASC` — required, because the AP consumers read the latest *position*; `rebuildLedgerBalances` for customers uses `transaction_date ASC, id ASC` — correct, because the customer side reads a true as-of running balance and derives its balance from `SUM(debit − credit)`, which is order-independent. The two ledgers genuinely need opposite orderings; this is not an inconsistency.
- **`decomposeLineAmount` header discount vs `postInvoiceEntry` full-line tax** is a defensible trade-discount treatment, balanced by construction. Judgment call, not a defect.
- **`CREDIT_APPLICATION` intentionally writes no customer-ledger row** — the return already credited the ledger, so the row would double-count. The 1,200 GL-vs-subledger AR delta observed on the live DB is this design, not a bug.
- **Flutter sends `due_date` on every create** — it is the unguarded API surface, not the client, that creates ACCT-004's exposure.
- **The 289 `as Map<String,dynamic>` casts in `lib/data/models/*.dart`** are standard JSON decoding, not type-safety violations. Only 3 `print(` calls exist, all genuine PDF `_print()` methods.

---

### SALES-022 · Stale documentation: `models/AGENTS.md` contradicts the return-ledger date actually written
**Source:** `SALES-FORENSIC-AUDIT.md` SALES-022

The **code is correct and the doc is stale**: `ledgerUtils.createLedgerEntry` selects the predecessor *at or before* the insert position (`ledgerUtils.ts:30`) and then calls `rebuildLedgerBalances` (`:59`), which re-derives the entire chain in date order — so a backdated insert cannot corrupt the chain regardless of date choice. Flagged only so the next agent does not "fix" working code to match stale guidance.

---

# Part 4 — Reconciliation Matrix (Live Database, Read-Only)

Computed against a `/tmp` copy of `database/erp.db`. Sign convention per `accountingService.ts:159-161` (balance normalized positive for the account's `normal_balance`).

| Report | Balanced? | Reconciles With | Status | Notes |
|---|---|---|---|---|
| Trial Balance | **Yes** — 460 = 460 | `journal_lines` | ✅ | 0 unbalanced entries across all 18 headers |
| General Ledger | Yes | `journal_entries` | ✅ | `gl:check` passed 4/4 |
| Balance Sheet | **Yes** — A 80 = L+E 80 | Trial Balance | ✅ | balances **only** via `netIncomeYtd` at `Reports.ts:514` |
| Income Statement | Yes — Rev −200, Exp 120, NI −320 | BS retained earnings | ✅ | GL-derived via `getPeriodMovement` |
| AR subledger | **Yes** — diff **0** | GL 1100+1110 | ✅ | `GL 200 = Σ(current_balance − credit_balance)` |
| AP subledger | **Yes** — diff **0** on clean data | GL 2000 | ✅ | but **breaks to −4000 on live data** (PUR-002) and to 100/150 on backdated entries (PUR-004) |
| Inventory | **No** — GL 1200 = −120 vs batch 2,240 | GL 1200 vs batch value | ❌ | scratch placeholder data; the *mechanism* gap is the proven flag-on COGS defect (C-04) |
| Cash | **Yes** on clean data | GL cash vs `cashImbalances` | ✅ | invariant I; representation-only, per `known-issues.md` §5 |

**Live figures:**
- GL 1200 net = **2,433.60**; batch gap = **−1,533.20**
- AP aging reports supplier 1 as **−4,000** where truth is **+1,000** (double-counted reversal credits = 5,000; coded credits 24,150 vs correct 19,150; debits 20,150)
- `purchases.id=38` carries an active `Dr 7200 5000 / Cr 1200 5000` beside a fully voided original group (PUR-001)
- `stock_movements.id=125` posts `Dr 1200 166.79999999999998 / Cr 7100 166.79999999999998` (GL-003)
- Float artefact: `journal_lines.id 297/298` (`journal_entry_id 46`) hold **`166.79999999999998`**

**Verdict:** the engine reconciles. Every reconciliation failure found is in a *void / reversal / negative-amount* path, never in the create path.

**Integer-money migration: NOT IMPLEMENTED — and a first reading of this was WRONG.** `typeof(journal_lines.debit)` returning `integer` is merely SQLite NUMERIC affinity coercing integral JS numbers — it is *not* evidence of a migration. `PRAGMA table_info(journal_lines)` → `debit:DECIMAL(15,4), credit:DECIMAL(15,4)` on both scratch DBs, matching `add-gl-foundation.sql`. `docs/integer-money-migration-plan.md:3` states verbatim: **"Status: DESIGN / PLANNING DOCUMENT — NOT IMPLEMENTED"**.

---

# Part 5 — Transaction Flow Diagrams (Account Codes Verified Against the Live Chart)

```
SALES — invoice
[InvoiceForm] → POST /api/invoices → invoiceController.create
  → InvoiceCreationService (db.transaction, zod NOT enforced: items z.any())
  → consumeFromOldestBatches (FIFO layers; FEFO if has_expiry)
      ↳ FLAG ON + no location coverage ⇒ unitCost = standard_cost, batchId null  [C-04]
  → postEntry: Dr 1100 AR / Cr 4000 Revenue / Cr 2100 Tax
  → postCOGSEntry: Dr 5000 COGS / Cr 1200 Inventory   (at layer cost)
  → customer_ledger DEBIT
  ⇒ balanced at every step; wrong when the cost basis is wrong

SALE RETURN
[ReturnDialog] → invoiceReturnService.processReturn
  → allocateHeaderDiscount → returnedValueNet / returnedTax
  → reverseStockForItems (restock at FIFO cost of the original sale ✓)
  → postInvoiceReturnEntry: Dr 4100 Sales Returns / Dr 2100 Tax / Cr 1100 AR
  → postCOGSReversalEntry: Dr 1200 / Cr 5000        (at true FIFO cost ✓)
VOID RETURN
  → voidJournalLinesByReference(INVOICE_RETURN)  ✓
  → reverseRestock  ✗ missing skipAdjustmentFinancialPosting  [C-05]
  → if refund_expected: supplier_refunds NOT reversed      [C-06 family]
VOID ADJUST SETTLEMENT
  → payment_id is null ⇒ nothing reversed, cap freed  ⇒ double cash out  [C-01]

PURCHASE
[PurchaseForm] → POST /api/purchases → Purchase.create
  → postPurchaseEntry: Dr 1200 / Cr 2000 AP   (or Cr 1000/1010 cash)
  → supplier_ledger DEBIT; stock_batches created — NO location coverage  [C-04]
VOID PURCHASE
  → voidJournalLinesByReference(PURCHASE)  ✓
  → recordMovement('ADJUSTMENT')  ✗ posts Dr 7200 / Cr 1200  ⇒ 1200 → −500  [C-03/PUR-001]

GRN (PO receipt) — THE ACCRUAL EVENT
[ReceiveGoodsDialog] → PurchaseOrder.addReceipt
  → postGoodsReceiptEntry: Dr 1200 / Cr 2000 AP  dated receipt_date
  ⇒ there is NO supplier-invoice entity: `purchases.invoice_no` is unindexed free text.
    No GRNI account exists. No three-way match. No price-variance mechanism.

PURCHASE RETURN
  → postPurchaseReturnEntry: Dr 2000 / Cr 1200   at the layer cost ✓ (verified)
  → credit_note + supplier_ledger CREDIT
  → if refund_expected: SupplierRefund.create ⇒ Dr 1000 / Cr 2000
      ✗ never reversed on void                        [ACCT-007 family]
      ✗ accepted with zero cash collected            [C-02]
  → PO path: layer lookup by the wrong key            [C-06]
```

---

# Part 6 — Edge Case Coverage (Merged, Deduplicated)

Legend: ✅ handled · ⚠️ partial · ❌ not handled · N/A not applicable

| # | Module | Transaction | Edge case | Verdict | Evidence | Finding |
|---|---|---|---|---|---|---|
| 1 | Invoice create | POST /api/invoices | zero/negative quantity | ✅ | `InvoiceCreationService.ts:73`; `Invoice.ts:771` | — |
| 2 | Invoice create | POST /api/invoices | negative unit_price | ✅ | `InvoiceCreationService.ts:74`; `Invoice.ts:772` | — |
| 3 | **Invoice update** | PUT /api/invoices/:id | zero/negative quantity | ❌ | `invoiceController.ts:317` validates only the envelope; bare `Error` → HTTP 500 | SALES-012 |
| 4 | **Invoice update** | PUT /api/invoices/:id | negative unit_price | ❌ | `createInvoiceItem` validates nothing → SALES-005 path | SALES-005 |
| 5 | Line math | all | discount ≥ line total | ❌ | `currency.ts:72` → `net = 0`; header total 0; MEASURED (R): `Dr 5000 50 / Cr 1200 50` with no revenue line | SALES-006 |
| 6 | Tax | POST /api/pos/sale | tax_rate > 100% | ✅ | `validation.ts:181` | — |
| 7 | Tax | POST /api/invoices | tax_rate > 100% | ❌ | MEASURED (D): `Cr 2100 1000` on `Cr 4000 200` | SALES-003 |
| 8 | Tax | POST /api/invoices | negative tax_rate | ❌ | MEASURED (E): `tax_amount = −100` stored, `Cr 4000 100`, no 2100 line | SALES-002 |
| 9 | Tax | all | tax base excludes invoice-scope discount | ⚠️ | MEASURED: same 10% discount → tax 40.00 vs 36.00 | SALES-001 |
| 10 | Numbering | POST /api/invoices | same invoice_no twice | ✅ | `generateDocNo` atomic | — |
| 11 | **Invoice update** | PUT /api/invoices/:id | duplicate invoice_no | ❌ | MEASURED (J): `SQLITE_CONSTRAINT_UNIQUE` → HTTP 500 | SALES-012 |
| 12 | Idempotency | POST /api/invoices | double submit | ⚠️ | Keyed but optional; `assertNoActivePosting` not called | — |
| 13 | **Invoice update** | PUT /api/invoices/:id | double submit of a payment | ❌ | `invoiceController.ts:445-465` bypasses `PaymentRecordingService`; client sends no key on update | SALES-004 |
| 14 | Period | POST /api/invoices | backdated into CLOSED period | ⚠️ | Blocked but HTTP 500 (MEASURED G) | SALES-010 |
| 15 | Period | PUT /api/invoices/:id | closed period | ✅ | `invoiceController.ts:335` → 409 | — |
| 16 | Period | DELETE / PUT cancel | closed period | ✅ | `invoiceController.ts:702`, `:940` → 409 | — |
| 17 | Period | POST /api/pos/sale | closed period | ✅ | `posController.ts:212-218` → 409 | — |
| 18 | Period | POST /api/invoices | future-dated | ❌ | MEASURED (H): `2099-12-31` succeeded, auto-created open period `2099-12` | PUR-005 / SALES-011 |
| 19 | Period | POST /api/inventory/stock-movements | adjustment in closed period | ❌ | MEASURED: posted `1200 {dr:100}, 7100 {cr:100}` into closed `2026-01` | PUR-005 (ACCT-005) |
| 20 | Period | GRN void | closed period | ❌ | MEASURED: `GL 1200 1600 → 1100` inside closed period | PUR-003 |
| 21 | Period | Supplier-refund void | closed period | ❌ | No guard | ACCT-007 |
| 22 | Period | Invoice restore | closed period | ❌ | No guard | SALES-013 |
| 23 | Payment | invoice settlement | partial payment | ✅ | MEASURED (O): `Dr 1000 200 / Cr 1100 200` | — |
| 24 | Payment | invoice settlement | overpayment | ❌ | MEASURED (O): 200 then 400 on a 500 invoice → accepted, `paid_amount = 600`, GL 1100 credit 100 | SALES-008 |
| 25 | Payment | invoice settlement | unapplied payment | ⚠️ | Credits 1100 in full while no `balance_amount` changes | — |
| 26 | Return | POST /:id/return | full return | ✅ | Over-return guard; GL `postInvoiceReturnEntry`; COGS reversal | — |
| 27 | Return | POST /:id/return | partial return | ✅ | Proportional batch restore; `allocateHeaderDiscount` mirrors sale-side discount | — |
| 28 | Cancel | PUT /:id/cancel | cancel-after-post | ✅ | Paid lock + returned lock + "no journal lines voided" guard | — |
| 29 | Edit | PUT /api/invoices/:id | edit-after-finalize | ⚠️ | Closed period blocked; payments/returns NOT locked → SALES-005 | SALES-005 |
| 30 | Void | PUT /:id/cancel | void / reinstate | ❌ | Cancel terminal; no reinstate route | SALES-014 |
| 31 | Restore | POST /:id/restore | soft-delete → restore | ⚠️ | GL un-voided not re-created; no period guard; no COGS re-post; payment zeroing not reversed | SALES-013 |
| 32 | Warehouse | invoice create | multi-warehouse sale | ❌ | MEASURED (Q): 6 units with WH-A=3 / WH-X=5 → refused | SALES-015 |
| 33 | Stock | invoice create | negative inventory reachable? | ✅ | Three independent guards; DB CHECK; not reachable | — |
| 34 | Concurrency | invoice create | concurrent double-sell of last unit | ✅ | MEASURED (P): 2 requests for 1 unit → `created=1 blocked=1` | — |
| 35 | Line math | invoice create | client amount override on packed line | ❌ | MEASURED (N): packed item, qty 1, unit_price 10, amount 999999 → stored inconsistent | SALES-009 |
| 36 | Ingress | invoice create | non-numeric money field | ⚠️ | MEASURED: "abc" → NOT NULL constraint; fails safely but accidentally | SALES-018 |
| 37 | Chain | SO convert | quotation tax dropped | ❌ | `sales_order_items` has no tax_rate column → no Cr 2100 | SALES-016 |
| 38 | Chain | SO convert | due date dropped | ❌ | `SalesOrder.ts:645` passes `null`; default only on `undefined` | SALES-017 |
| 39 | AR | invoice delete | soft-deleted invoice still in AR | ❌ | MEASURED (K): operational AR 3056.00 vs GL 2656.00 → delta = 400.00 | SALES-007 |
| 40 | POS | POST /api/pos/sale | split tender with payments: [] | ⚠️ | `posController.ts:178` selects legs path; cash guard only in `!usesLegs` branch | SALES-019 |
| 41 | Purchase | GRN | over-receipt | ✅ | `PurchaseOrder.ts:886` | — |
| 42 | Purchase | GRN | negative quantity | ✅ | DB CHECK (500 not 400) | PUR-012 |
| 43 | Purchase | GRN | zero quantity | ⚠️ | Model accepts; controller blocks | PUR-012 |
| 44 | Purchase | GRN | future-dated | ❌ | Creates open period `2030-01` | PUR-005 |
| 45 | Purchase | GRN | cross-PO line reference | ❌ | No `poItem.po_id === po_id` check | PUR-007 |
| 46 | Purchase | Void | double inventory reversal | ❌ | GL 1200 → −500, phantom 7200 | PUR-001 |
| 47 | Purchase | Report | AP aging as-of past date | ❌ | No `transaction_date <= asOfDate` | PUR-006 |
| 48 | Purchase | Report | AP aging after a void | ❌ | Live supplier 1: reported −4,000 | PUR-002 |
| 49 | Purch. Returns | Return | PO-source return | ❌ | Layer key mismatch; 100% failure | C-06 |
| 50 | Purch. Returns | Return | refund on zero cash collected | ❌ | 600 cash out, 0 collected | C-02 / H-03 |
| 51 | Purch. Returns | Void | refund not reversed | ❌ | Phantom cash 100, AP 200 | C-02 family |
| 52 | Sales Returns | Settle | void an adjust | ❌ | Nothing reversed, cap freed ⇒ 1,600 double-paid | C-01 |
| 53 | Sales Returns | Void | after units re-sold | ❌ | `MAX(0,…)` absorbs shortfall; stock negative | C-05 family |
| 54 | Sales Returns | Void | phantom 7200 | ❌ | GL 1200 → −200 | C-05 |
| 55 | Valuation | Sale | flag-on COGS | ❌ | 999 vs 100; layer never relieved | C-04 |
| 56 | Balancing | all | unbalanced journal entry | ✅ | None exist; `postEntry` exact integer check | — |
| 57 | Balancing | all | balanced-but-wrong entries | ❌ | Every HIGH+ finding | CODE-003 / GL-002 |

---

# Part 7 — Consolidated Remediation Plan

| Pri | ID | Issue | Effort | Depends on | Live data affected? |
|---|---|---|---|---|---|
| **P0** | PUR-001 | Purchase void double-reverses inventory (live 5,000) | **S** | — | **Yes** — `purchases.id=38` |
| **P0** | PUR-002 | AP aging reads −4,000 on live data | **S** | — | **Yes** — supplier 1 |
| **P0** | C-01 | `adjust` void frees cap ⇒ double cash payment | S | — | No (reachable) |
| **P0** | C-02 | `refund_expected` on unpaid doc fabricates cash | S | — | No (reachable) |
| **P0** | C-05 | Return void books phantom 7200 | **S** | — | No (reachable) |
| **P0** | H-03 | Refunds uncapped by collected cash | S | — | No (reachable) |
| **P1** | C-06 | PO-return layer key mismatch (feature dead) | M | fixture fix | No |
| **P1** | C-04 | Flag-on COGS at standard cost; layer never relieved | M | flag decision | Gated (flag=0) |
| **P1** | PUR-003 | GRN void period guard | S | CODE-001 | No |
| **P1** | PUR-004 | Four AP-position definitions | M | — | **Yes** (backdated) |
| **P1** | SALES-005 | Edit-to-zero total voids revenue | M | CODE-005 | No |
| **P1** | SALES-007 | Soft-deleted invoices in all AR surfaces | S | — | No |
| **P1** | SALES-002 | Negative tax_rate → revenue inflation | S | CODE-005 | No |
| **P1** | SALES-016 | Quotation tax dropped schema-deep | L | migration | No |
| **P1** | SALES-004 | PUT not idempotency-keyed; inline payment bypass | M | — | No |
| **P1** | SALES-008 | INVOICE_SETTLEMENT ceiling ignores payments | S | — | No |
| **P1** | SALES-001 | Header discount never reduces tax base | M | — | No |
| **P1** | CODE-005 | One shared typed invoice-item schema | M | — | No |
| **P1** | GL-002 | Master GL-balance assertion deletable | S | — | No |
| **P2** | PUR-005 | Future-dating opens periods | S | — | No |
| **P2** | PUR-006 | AP aging ignores as-of | S | — | No |
| **P2** | PUR-007 | Cross-PO line receipt | **S** | — | No |
| **P2** | PUR-008 | No price-variance mechanism; no GRNI | L | schema | No |
| **P2** | PUR-009 | `roundQty` on money | **S** | — | No |
| **P2** | PUR-010 | GRN client idempotency key never sent | S | — | No |
| **P2** | SALES-006 | Zero-value invoice relieves stock | S | CODE-006 | No |
| **P2** | SALES-009 | Amount override on packed lines | S | CODE-005 | No |
| **P2** | SALES-010 | Backdated closed period → HTTP 500 | S | — | No |
| **P2** | SALES-012 | Duplicate invoice_no via PUT; no per-item validation | M | CODE-005 | No |
| **P2** | SALES-013 | Restore no period guard; stale COGS | M | CODE-001 | No |
| **P2** | SALES-015 | Multi-warehouse not split | M | — | No |
| **P2** | SALES-017 | SO→invoice drops due date | S | — | No |
| **P2** | SALES-019 | POS WALK-IN unbounded AR | S | — | No |
| **P2** | CODE-001 | Period protection as primitive property | M | — | No |
| **P2** | CODE-003 | `glTotals` helper blind to credit side | S | — | No |
| **P2** | CODE-006 | Client/server discount cap divergence | S | — | No |
| **P2** | ACCT-003 | Zero-cost adjustment batches | S | — | No |
| **P2** | GL-003 | Float artefact + integer migration | L | plan | **Yes** |
| **P2** | GL-004 | Non-calendar period bypass | S | — | No |
| **P2** | GL-006 | Unrounded money outside postEntry | S | — | No |
| **P2** | GL-007 | 5 endpoints no idempotency | M | — | No |
| **P2** | SEC-003 | HTTP response inside DB transaction | S | — | No |
| **P2** | SEC-004 | Raw SQLite errors returned | M | — | No |
| **P2** | DB-001 | `goods_receipt_items` no indexes | S | migration | No |
| **P2** | DB-002 | No DB-level debit==credit | M | migration | No |
| **P2** | DB-003 | Migration checksums skip 74% | M | — | No |
| **P3** | PUR-012 | Model lower-bound guard | S | — | No |
| **P3** | PUR-013 | Receipt warehouse deviation | S | — | No |
| **P3** | PUR-014 | balance_amount no floor | S | — | No |
| **P3** | PUR-015 | backfill re-posts voided | S | — | One-shot |
| **P3** | PUR-016 | dedupe-po residual | S | backup | **Yes** (4,000) |
| **P3** | SALES-014 | Cancel terminal / no reinstate | S | — | No |
| **P3** | SALES-018 | Non-numeric money | S | CODE-005 | No |
| **P3** | SALES-021 | createLedgerEntry predecessor | S | — | No |
| **P3** | CODE-002 | Silent zero-value adjustment | S | — | No |
| **P3** | ACCT-007 | Supplier-refund void period guard | S | CODE-001 | No |
| **P3** | GL-005 | stock-authority-map claim false | S | doc | No |
| **P3** | DB-004 | 12 dead migrations | M | — | No |
| **P3** | DB-005–008 | Financial invariants only in app | M | — | No |
| **P3** | SALES-022 | Stale doc on return-ledger date | S | doc | No |

**Highest-leverage structural fix:** Add one invariant — *per non-cancelled invoice, Σ live 1100 lines == `total_amount`* — which catches the "balanced-but-wrong" class that the current nine invariants structurally cannot see. Pair it with tightening `glTotals`-style assertions to check **credit** as well as debit (CODE-003), and asserting `expectAllInvariantsHold` after every void path.

**Second highest-leverage:** CODE-005 (shared typed invoice-item schema) closes SALES-002, SALES-003, SALES-009, SALES-012, SALES-018 and half of SALES-015 in one commit.

---

# Part 8 — Duplicate-Issue Summary Count

| Category | Count |
|---|---|
| Issues appearing in 2+ source artifacts | **22** |
| Issues appearing in 3 source artifacts | **5** (PUR-001, PUR-002, PUR-003, PUR-005, PUR-009) |
| Issues appearing in 4 source artifacts | **1** (PUR-005 / SALES-011 / ACCT-005 / CODE-05) |
| Issues unique to `audit-purchases-ap-report.md` | 6 (PUR-012, PUR-013, PUR-014, PUR-015, PUR-016, PUR-008's GRNI analysis) |
| Issues unique to `CONSOLIDATED-AUDIT.md` | 12 (C-01, C-02, C-04, C-05, C-06, H-03, SEC-001–004, DB-001–004, GL-004–007, TEST-01) |
| Issues unique to `forensic-audit-full.md` | 5 (ACCT-003, ACCT-004, ACCT-007, CODE-002, CODE-004) |
| Issues unique to `SALES-FORENSIC-AUDIT.md` | 12 (SALES-004, SALES-008, SALES-009, SALES-013, SALES-014, SALES-015, SALES-017, SALES-019, SALES-020, SALES-021, SALES-022, SALES-001) |
| **Total unique canonical findings** | **58** |
| **Total raw finding IDs across all four files** | **89** |
| **Duplicates eliminated** | **31** |

---

# Part 9 — Coverage & Limitations — stated honestly

**Fully audited with execution:** Sales, Purchases, Sales Returns, Purchase Returns, GL substrate & period locking, inventory valuation, DB schema/FK/index/migrations, reports reconciliation, auth/authz, SQL-injection surfaces, transaction atomicity.

**NOT audited — the responsible agents were killed by provider rate limits, and no speculation was substituted for evidence:**
- **Payments** (customer receipts, supplier payments, allocation/overpayment, POS split-tender, `cashService`) — *not audited*
- **Expenses & owner equity** (accrual-vs-cash crediting, the approve→paid double-count) — *not audited*
- **Report layer in depth** (aging day-count basis vs due date, GL-drift table, drill-down traceability) — *not audited*
- **Flutter client** (widget practices, state management, layer violations, client/server calculation parity beyond the discount/tax findings) — *not audited*
- **Concurrency under multi-process deployment** — single-process only; `busy_timeout` behaviour with a second server instance is untested

Per `known-issues.md` §"Whoever writes the next artifact has to read the code first": one headline claim (integer-money migration) survived a first pass and was falsified only by cross-agent disagreement plus direct re-verification. Treat every number here as needing the same treatment.

**Data caveat:** `database/erp.db` and `server/database/erp.db` are untracked placeholder databases. Their numeric divergences (inventory gap −2,360; AP aging −4,000) are reported as *evidence that a code path exists*, never as standalone code defects — consistent with `known-issues.md`'s own warning on this point.

**Reproducibility:** all probe artifacts are outside the repository, under `/tmp`. **The repository working tree was left clean** (`git status --porcelain` empty); two reports an agent wrote into `docs/` were moved to `/tmp/audit-reports/`.

**Verification commands used:**
```bash
cd server
npx jest --silent              # 114 suites / 993 tests passed
npx tsc --noEmit               # clean
npx eslint                     # 0 errors (2 pre-existing any-warnings, none in changed paths)
```

---