# Regression-Test Relevance Audit — Final Report

**Repo:** `minierp-flutter` (server, TypeScript/Node + SQLite)
**Scope:** all 87 test files in `server/src/__tests__`
**Method:** 6 parallel domain auditors read every test in full, traced each to production code, checked it against `openspec/specs/*`, `docs/*.md`, and re-ran the suites (all green). **Audit only — read-only.**

---

## 1. Executive Summary

**87 files / 752 test cases** (jest-executed across six domain runs; a static `it(`/`test(` scan finds 717 — the gap is multi-line calls and `test.each`). **Every suite passes.** The headline result is *not* obsolescence — it is **false confidence**.

| Category | Files | Tests (approx.) | Notes |
|---|---|---|---|
| **KEEP** | 45 | ~600 | Solid protection of live, spec-conformant behavior |
| **KEEP — UPDATE NEEDED** | 40 | ~90 | Behavior valid; assertions weak/vacuous/wrong-layer |
| **REPLACE** | 2 files + ~12 tests | ~15 | Purpose matters; current form cannot catch the bug |
| **DUPLICATE** | — | ~25 | A stronger sibling exists |
| **OBSOLETE** | 1 block | 5 | The CSRF block in `security.regression.test.ts` |
| **SUSPICIOUS** | — | ~18 | Passes while not protecting what it claims |

**Zero files should be deleted.** Only 5 individual tests are genuinely obsolete (the CSRF block — that middleware was removed). The dominant defect class is **tests that stay green while the named behavior is unverified**, and the audit surfaced **11 live production defects** the green suite currently passes over.

### The 11 live production defects found (highest audit value)

**P0 — books-corrupting, reproducible today:**

1. **PO `Draft→Submitted` transition posts a supplier-ledger debit**, contradicting `gl-posting-matrix` spec ACC-16 ("submission SHALL NOT create GL entries or supplier-ledger debits"). Reproduced end-to-end: after receive+pay, supplier ledger net **−1000** and `current_balance` **−1000** — a received-and-paid PO shows a spurious supplier credit. *Three suites assert the conflicting model.*
2. **`Production.delete` double-counts batches** — it restores each consumed batch *and* calls `recordMovement`, which mints a second batch. Measured: `stock_balances`=20 but `SUM(batches)`=**28**; GL inventory 140 vs balance value 100; the FG removal posts **no** GL (falls back to `standard_cost`=0).
3. **Multi-batch transfer + void breaks batch coverage** — the OUT leg links only `consumption[0].batchId`; `voidTransfer` restores the full qty to that one batch, so `SUM(batches) ≠ balance`.
4. **Transfer void posts GL** (both reversal legs are ADJUSTMENT movements), contradicting `REVERSAL-RULES §11` ("Transfers have no GL effect").

**P1 — silently wrong or unprotected at the real path:**

5. **`PurchaseReturn.voidReturn` leaves a `refund_expected` auto-refund POSTED** while voiding its credit note → GL and subledger disagree, and the money becomes invisible (`creditNoteRefundable`=0 for a non-POSTED note). **Zero references to `supplier_refunds` in `voidReturn`.**
6. **`mobileInvoiceController.submitInvoice` drops header-discount fields** (`mobileInvoiceController.ts:132` + `MobileInvoice.ts:215`) → mobile-created discounted invoices store `discount_value=0` and **over-credit on return** (the pre-H2 bug class).
7. **`paymentsController.ts:206` maps HTTP status by substring** — the H7 rejection returns 400 only because its message contains "required"; "exceeds the remaining balance" contains none of the three trigger words → **500**.
8. **H1 (float rounding) has no end-to-end test** — the unit suite would stay green if the real sale path reverted to raw `<`.
9. **The `server.ts` boot wiring for the expiry sweep is entirely untested** (every suite imports `app.ts`, never `server.ts`) — deleting the sweep call leaves all expiry tests green.

**P2 — latent behind `feature_batch_locations` (defaults OFF):**

10. **Incoming-batch writers never seed `batch_stock_by_location`** (`recordPurchase`, `PurchaseOrder`, `Production`, `OwnerWithdrawal`, `completeCount` surplus, the H10 `recordMovement` path). With the flag ON, `getSellableAvailability` returns `[]`, sales fall back to the legacy path pricing at `standard_cost` and never decrement the batch, leaving the item permanently unsellable. `batchLocationIntegration` hand-seeds every location row, so this is invisible to CI.
11. **`stock_balances` extension columns drift** after return create/void (resync happens *before* the bsl consume), and `batch-reconciliation` INNER JOINs bsl so an unlocated batch is **invisible to the drift detector** — the exact case it exists to catch.

### Three spec/implementation contradictions needing a product decision

- **PO commitment** (defect 1): align `updateStatus` to ACC-16, or amend the spec. Until resolved, KEEP–UPDATE is the honest ceiling for the affected suites.
- **Boot expiry sweep writes stock tables** vs `boot-task-gating` Requirement 1 (no exception documented; spec and sweep landed the same day and were never reconciled).
- **Transfer-void GL** vs `REVERSAL-RULES §11` (tests assert no GL; implementation posts GL).

---

## 2. Test-by-Test Audit (file-level)

Full per-test tables with `file:line` evidence live in the six domain reports (`/tmp/audit/*.summary.json`).

| File | Category | What It Protects | Still Valid? | Quality | Evidence | Recommended Action |
|---|---|---|---|---|---|---|
| security.regression (25t) | MIXED | JWT/SQLi/headers/authz | mostly | C | CSRF block = 5 OBSOLETE; 2 XSS tests vacuous (400 on missing `phone` before assertions); 1 no-op | Delete CSRF; rewrite XSS or document as client's job |
| reportExpressionSecurity (4t) | KEEP–UPDATE | REP-18 expression injection | yes | high | `:145` `not.toThrow(msg)` passes on any different message | Bare `.not.toThrow()` + seed a legit row |
| userSelfRole (3t) | KEEP | SEC-04 self-role guard | yes | high | 400 + DB state | none |
| envHardening (2t) | KEEP | SEC-02 rate limiter (prod NODE_ENV) | yes | high | only 429 test in repo (child process) | none |
| authAsync (6t) | KEEP | async bcrypt + refresh | yes | good | — | add access-token-at-refresh rejection |
| validation (7t) | KEEP–UPDATE | Zod envelope | yes | low→good | `:17` claims `details` but never asserts | assert the details array |
| softDelete (9t) | KEEP | customer/item tombstones | yes | high (cust) / med (item) | item tests status-code only | item: assert `deleted_at` + list filter |
| statusMachine (5t) | KEEP | SO/Quotation transition matrices | yes | high | 400 + DB state | none |
| activityLog (4t) | KEEP | UTC/local day bounds | yes | high | pins invariant without date mocks | none |
| auditTrail (3t) | MIXED | audit row count + purge gate | partial | med / fail | `:52` never reaches the 403 gate (hits retention 400) | REPLACE with a User-role 403 test |
| invoiceReturnAcceptance…VoidsAndPrint (24t) | KEEP | spec §3 position math, settlements, voids, D20 fee entry | yes | A | mobile/desktop parity intentional dup | fix scenario-21 legacy clause (field doesn't exist) |
| returnMath + headerDiscountAllocation (30t) | KEEP | pure math + discount allocation | yes | A | only coverage of the math layer | none |
| headerDiscountPersistence + RepairMigration (16t) | KEEP | H2 persistence + give-back + repair | yes | A | `:346` GL sweep is removable | drop the redundant sweep |
| arPartialReturn (5t) | KEEP | H4 AR visibility | yes | A | 4 surfaces + GL AR cross-foot | assert aging bucket placement |
| mobileReturn (3t) | KEEP | D17 parity | yes | A | — | none |
| reverseStockRestock (2t) | KEEP–UPDATE | repeat-partial restock fix | yes | C | console.log, `global.authCookie`, `as any` | hygiene cleanup |
| invoiceCancelReversal (5t) | KEEP–UPDATE | C1/C4 cancel reversal | yes | B | `:115` tautological INVOICE_RETURN==0 | replace with collision-style check |
| invoiceCancelReturnCollision (3t) | KEEP | cancel spares another invoice's return GL | yes | A | engineered id collision + whole-book invariants | **exemplary** |
| accountingInvariants (7t) | KEEP | 5 whole-DB invariants | yes | high | header docstring for "Invariant B" mismatched | fix docstring or implement B |
| accountingPeriodRoller (3t) | KEEP–UPDATE | ACC-11 rollover | partial | fail on t3 | failure fires *before* the period INSERT → rollback untested | move the failure after period creation |
| closedPeriodImmutability (8t) | KEEP–UPDATE | H6 immutability | yes | high | `#7` return-void = 409 only, no DB state | add return/GL/ledger/stock asserts |
| glLifecycle (3t) | KEEP | ACC-08/PAY-04 | yes | high | — | none |
| glPostingMatrix (5t) | KEEP–UPDATE | posting matrix | partial | fail on t4 | POS payment check fully conditional | assert payment group unconditionally |
| glReturnTaxBalance (5t) | KEEP | return posting primitives | yes | high | t5 duplicates t2 | merge |
| glSoftDelete (2t) | KEEP–UPDATE | AUD-06 orphans | partial | fail on t1 | Draft fixture posts no GL; silent skip | use a posted invoice; assert *voided* |
| glUnification / glBackfill / glPoCommitment (10t) | KEEP | backfill migrations | yes | high | hand-built schemas could drift | build fixtures from real migrations |
| ledgerIntegrity (9t) | KEEP–UPDATE | append-only ledger, reconciliation | yes | high | `#9` asserts only the Inventory pairing | assert **every** pairing delta ≤ 0.01 |
| taxPostingConsistency (9t) | KEEP | H3 stored-tax SOT | yes | A | strongest suite in its domain | none |
| taxGlRepairMigration (6t) | KEEP | H3 repair | yes | A | all exclusions + idempotency | none |
| creditOffset (3t) | KEEP | use-cr-balance | yes | A | — | none |
| paymentEditReposting (12t) | KEEP | H8 date/method repost | yes | A | **hard time-bomb: `:551` hardcodes 2026-09-30** while refunds post at `todayLocal()` | derive dates from the payment row |
| paymentGuards (5t) | MIXED | PAY-04/09, CASH-02 | partial | med | PAY-09 tests a hand-rolled table, not the real migration CHECK; header claims PAY-11 with no test | test the real `add-payments-counterparty-check.sql` |
| paymentDeletion (2t) | KEEP | PAY-01 ownership | yes | strong | sole coverage; 1500 ms sleep | add GL/ledger money-side asserts |
| supplierPaymentAllocation (7t) | KEEP | H7 Σ allocations == amount | yes | strong | sole H7 coverage; name overclaims "GL untouched" | add journal_lines assertion |
| supplierRefund (5t) | KEEP | supplier refund create/void | yes | strong | GL direction not pinned by account | assert Dr on 1000, Cr on 2000 |
| apReporting (4t) | MIXED | PAY-07 AP aging | yes | med | hand-inserted ledger rows; 2 mislabeled buckets; 31–60 never positively asserted | drive through real writers |
| cashTruth (8t) | MIXED | CASH-01/02/03 | partial | **2 are source-text scans** | `:30`/`:92` assert `src.includes(...)`; `:47` inserts no purchase | **REPLACE** with data tests |
| expenseStatusConsistency (5t) | KEEP | H5 P&L excludes cancelled | yes | strong | inline-SQL block trivially true | use a production-derived figure |
| expensePagination (5t) | KEEP | expense paging | yes | strong | only real page-slice assertion in repo | none |
| ownerEquity (17t) | KEEP–UPDATE | owner capital/withdrawal | yes | med | ~5 trivially-satisfiable; zero API tests | exact-value asserts + API matrix |
| ownerPersonalLoans (19t) | MIXED | personal loans CRUD | yes | med | ~6 status-only; `data[0]` ordering fragility | capture IDs; assert outcomes |
| floatingPointPrecision (29t) | MIXED | H1 rounding helpers | partial | B | ~10 tests cover helpers with **zero production callers**; real sale path simulated only | add H1 end-to-end |
| inventoryValuation (5t) | MIXED | bucket semantics | yes | B | reserved/damaged always 0; formula test near-tautological | populate non-zero buckets |
| stockAdjustmentCostedBatch (9t) | MIXED | H10 costed batches | yes | A/B | OPENING-cost premise unreachable via UI | drive POST /api/inventory/items |
| purchaseVoid (7t) | MIXED | PUR-03/02 void guards + batch identity | partial | **1 vacuous** | batch-identity test never calls `PurchaseModel` | **REPLACE**: call recordPurchase, assert the batch |
| purchaseReturn (14t) | MIXED | PRET-01/02/05 | yes | A/B | 4 duplicates of the HTTP suite; PRET-06 hand-rebuilds payments DDL | allocate via the real payment model |
| supplierlessPurchase (5t) | KEEP | H12 cash-vs-AP | yes | A | per-account GL both directions + void | none |
| supplierPurchasesFilter (3t) | KEEP | supplier_id filter | yes | good | only coverage | none |
| stockTransfer (2t) | KEEP | atomic 2-leg transfer | yes | strong | — | none |
| stockTransferVoid (4t) | MIXED | transfer void | yes | B | **no GL assertion** though impl posts GL | assert reversal-leg GL / neutrality |
| goodsReceiptVoid (5t) | MIXED | GRN void | yes | B | global unfiltered count (order-dependent); no GL assertion | scope count; assert GOODS_RECEIPT group voided |
| countCorrection (5t) | MIXED | count correction | yes | A/B | GL reversal unusually well asserted | assert batches-vs-balances coverage |
| systemWarehouseGuard (7t) | MIXED | system warehouse guard | yes | B | trigger test is a weaker twin; `[200,400,500]` permissive | tighten status; drop twin |
| batchLocations (11t) | MIXED | batch-location model | yes | B | `7.1` writes the invariant it verifies; `7.10` has a deleted assertion (`void locRow;`) | let the trigger derive the value; restore assertion |
| batchLocationIntegration (4t) | MIXED | integration through bsl | partial | C | **every fixture bypasses the production write path** | drive via recordPurchase/createInvoice/completeCount |
| physicalCountBatchSync (2t) | MIXED | count batch sync | yes | B | runs the legacy path (fixture omits the migration) | enable the flag; assert the spec-named path |
| expiredStockMigration (7t) | KEEP | expired-stock migration | yes | A | real EXPLAIN QUERY PLAN | candidate SQL duplicated inline — protect the boot query too |
| expiredStockSaleBlocking (10t) | MIXED | expired never sellable | yes | A/B | `7.4` rollback unproven; `7.8` subsumed | assert batch/line state after the 400 |
| expiryDetection (5t) | KEEP | sweep contract | yes | A | — | cover the boot-level log-and-continue policy |
| expiryTransfer (4t) | KEEP | expiry transfer helper | yes | A | most thorough file in its domain | none |
| poReceiptGl (12t) | KEEP | C3 receipt GL | yes | A/B | several scenarios assert the spec-conflicting commitment model | resolve ACC-16 first |
| poCancelReversal (2t) | MIXED | C3 PO cancel | yes | B | case 6 subsumed | keep case 7 (state-machine lock) |
| poCancelPartialReceipt (7t) | MIXED | H11 partial-receipt cancel | yes | B | 3 near-exact duplicates; **file is untracked in git** | fold into poReceiptGl; **commit it** |
| productionDeleteGl (1t) | KEEP–UPDATE | C2 production delete | yes | C | passes while batch coverage drifts | assert SUM(batches) == balance |
| writeOff (6t) | KEEP | write-off contract | yes | A/B | validation branch unreachable | none |
| search (22t) | KEEP–UPDATE | global search | partial | B | **permission filtering — the spec's headline — has zero coverage**; stale fixture DDL | add a non-admin user; delete dead fixture code |
| api.integration (51t) | KEEP | broad HTTP smoke + contracts | yes | B | 7 status-only smokes; `:122`≡`:459` same payload; `:194/523` guard a vestigial `period` | add value asserts; merge duplicates |
| controllers (25t) | KEEP–UPDATE | controller contracts | partial | C | dead CSRF ceremony; `:202` tautology; `:251` no such route (always 404); `:258` always 404 | delete CSRF; assert real outcomes |
| models (63t) | KEEP (repair 11) | real-DB model coverage | yes | B | 11 vacuous (paging smaller than page size; reorder_level 0; `Array.isArray`-only) | fix the 11; keep the unique real-DB value |
| moneyPaths (3t) | **REPLACE** | payment/edit/numbering paths | **no** | **fail** | guards skip every assertion (no item/customer seeded) | rewrite with seeded data |
| adminBackup (6t) | KEEP | backup API | yes | B | 1600 ms sleep; weak count | use `flushLogs()`; assert exact row |
| backupWal (1t) | KEEP–UPDATE | WAL integrity | partial | C | tests raw SQLite, never `runBackup` | add a `runBackup()`-on-app-DB test |
| bootIdempotency (1t) | KEEP | boot is idempotent | yes | good | fingerprint omits boot-seeded `custom_reports` | add it |
| migrationReplay (1t) | KEEP | migration replay | yes | good | complements bootIdempotency (schema vs data) | none |
| dashboardKpi (14t) | KEEP | KPI metrics | yes | good | 6 of ~16 metrics uncovered | add them; PRAGMA-diff the schema |
| dashboardWeek / weekMath (13t) | KEEP | week anchoring | yes | A | — | none |
| dashboardBoot (3t) | KEEP | composite payload | yes | smoke | no endpoint-consistency assertion | assert boot ≡ the 8 endpoints |
| preferences / userPreferences (22t) | KEEP | settings contract | yes | good | permission test negative-only | add a positive permission case |

---

## 3. Tests That Must Be Preserved

These protect business invariants that would silently corrupt the books if regressed, and they are the *only* protection of their rule:

- **`invoiceCancelReturnCollision`** — engineered `invoice_returns.id`↔`invoices.id` collision proving cancellation voids by *return id*, not invoice id. Exemplary.
- **`taxPostingConsistency`** — H3: GL Tax Payable ≡ stored invoice tax, across every discount shape; the strongest suite in its domain.
- **`accountingInvariants`** — five whole-DB invariants (GL balance, GL↔subledger, subledger↔source, stock-vs-batches) across a full lifecycle.
- **`closedPeriodImmutability`** + **`paymentEditReposting`** — H6/H8: no accounting rewrite inside a closed period; date/method edits repost the books.
- **`supplierPaymentAllocation`** — sole protection of H7 (Σ allocations == payment amount).
- **`paymentDeletion`** — sole protection of PAY-01 (`deleted_payments` ownership).
- **`poReceiptGl`** — sole proof that PO goods receipts post Dr 1200 / Cr 2000.
- **`models.test.ts`** — the *only* suite on the real app DB; guards global-`db`-bound paths (purchase clean-void chain, supplier-payment-po-link stamping, legacy FIFO — the current production default).
- **`ledgerIntegrity`** — append-only ledger + counterparty scoping (ACC-14/ACC-20).
- **`floatingPointPrecision`** (the on-path helpers), **`stockAdjustmentCostedBatch`** (H10), **`supplierlessPurchase`** (H12), **`arPartialReturn`** (H4), **`expenseStatusConsistency`** (H5), **`glPoCommitment`** (ACC-16), **`envHardening`** (only 429 test), **`activityLog`** (timezone day bounds).

---

## 4. Tests That Need Updating (highest value first)

1. **`cashTruth:30` / `:92`** — they *are* named after CASH-01/CASH-02 but assert `src.includes(...)` on source text. Replace with data tests: insert an unpaid purchase → assert outflow unchanged; store a payment with method `'Cash on delivery'` → assert a `key==='unclassified'` reconciliation row appears and the bank row excludes it. Also fix `:47`, which seeds a payment with **no purchase row**, so the double-count it claims to guard is untestable.
2. **`paymentEditReposting:511/551`** — hard time-bomb: balances read at hardcoded `'2026-09-30'` while refunds post at `todayLocal()`. **Fails outright if run after 2026-09-30.** Derive `asOf`/`newDate` from the payment row.
3. **`purchaseVoid` batch-identity test** — seeds a decoy batch but then uses a local helper that links its own batch; `PurchaseModel` is never called, so the assertions are trivially true and would pass if the original PUR-02 bug were reintroduced. Rewrite to call `recordPurchase(...)` and assert `purchases.batch_id` / movement batch resolve to the new batch.
4. **`accountingPeriodRoller:3`** — the induced failure (non-existent account ids) throws at `accountingService.ts:210-213`, *before* the period INSERT at `:241`, so the rollback guarantee is untested. Make the failure land after period creation.
5. **`glPostingMatrix:4`** — the POS payment-entry balance check is inside `if (payRow) { if (payLines.length) … }`; it passes while posting nothing. Assert the payment row/group exist unconditionally.
6. **`glSoftDelete:1`** — Draft fixture posts no GL, so "zero orphaned journal_lines" counts nothing; `if (!item) return` can skip the test and still pass. Use a posted invoice and assert lines are *voided*.
7. **`moneyPaths` (all 3)** — REPLACE: no item/customer is seeded, so the guards skip every assertion. Three real scenarios (partial payment allocation, invoice edit after payment, parallel numbering) are currently *uncovered while appearing green*.
8. **`paymentGuards:109` (PAY-09)** — asserts a hand-rolled `payments_new` table, not `add-payments-counterparty-check.sql`. The real CHECK could be dropped with no test failing.
9. **`batchLocations 7.1`** — the test *writes* `quantity_available = physical − reserved` itself right after changing `reserved`, masking a missing update trigger. Drop the manual write; assert the trigger's value. Also restore the deleted assertion at `7.10` (`void locRow;`).
10. **`batchLocationIntegration` (all)** — every fixture hand-seeds batch/location/balance rows, so it never exercises the producers. It currently hides the producers-don't-seed-location-rows defect. Drive via `recordPurchase`/`createInvoice`/`completeCount`.
11. **`ledgerIntegrity:9`** — reconciliation asserts only the Inventory delta; the spec requires *every* pairing ≤ 0.01 (AR, AP, and all five cash accounts).
12. **`controllers:251/258`** — assert routes that don't exist (`/api/sales/summary/item/abc`) or ids that can't exist → always 404, controller never invoked. Replace with real seeded assertions.
13. **`models` (11 vacuous)** — paging fixtures smaller than the page size (`rows=[]`, all assertions tautologies); `reorder_level` defaults to 0 so low-stock loops never run; `Array.isArray`-only smokes.
14. **Permissive status ranges** — `[200,400]`, `[200,403]`, `[200,400,404]`, `[400,500]` across security/validation/controllers/poReceiptGl/systemWarehouseGuard; tighten to the expected code.
15. **Stale names/headers** — `paymentGuards` header claims PAY-11 coverage the file doesn't contain; `apReporting:41` says "both reports" but `getAPSummary` was deleted.
16. **Hygiene** — `console.log` + `global.authCookie` + `as any` (reverseStockRestock); self-rolled `getAuthCookie` in 3 suites; unused imports (AccountingService in countCorrection, accountingInvariants); 1500/1600 ms sleeps replaced with `flushLogs()`.

---

## 5. Potentially Obsolete Tests

**Only one block qualifies, with concrete evidence:**

- **`security.regression.test.ts:119-157` (5 tests, "CSRF block")** — CSRF middleware was removed from `app.ts`; `grep csrf server/src` now hits only this test and `controllers.test.ts`. `getCsrfToken()` always returns `""`, and the "valid token" case asserts `not.toBe(403)` — trivially true. **Evidence:** no CSRF middleware in `app.ts`/routes; the Flutter client uses bearer/cookie auth. Delete the block, or collapse it to one documented guard pinning the deliberate removal.

**Not obsolete, but behavior intentionally changed (do not delete):**

- `expiredStockSaleBlocking 7.5a` correctly tests the removed `expired_batch_overrides` flow *as an assertion that the payload is now inert* — that's the right form for a removed feature.
- `apReporting`'s "both reports" is a stale *name*, not stale behavior — the surviving report is valid.
- `Expense.deleteExpense` (model-only, no route, no controller caller) is **dead production code**, not a dead test — either expose the route or drop the closed-period spec scenario.

---

## 6. Duplicate Tests

| Duplicate | Stronger test | Disposition |
|---|---|---|
| `paymentGuards:133` (CASH-02) vs `cashTruth:11` | near-equivalent; cashTruth asserts more values | merge into cashTruth |
| `mobileReturn:61` vs `invoiceReturnAcceptance:76` | parity is the *point* (D17) | **keep both** (intentional) |
| `headerDiscountAllocation` (unit) vs `headerDiscountPersistence` (integration) | different layers, different failure modes | **keep both** (intentional) |
| `headerDiscountPersistence:346` GL sweep | the 5 preceding tests already assert `glImbalances()` | drop or rename to file-level sweep |
| `api.integration:122` ≡ `:459` | identical SQLi payload, same endpoint | merge into one explicit-400 |
| `api.integration:523` vs `security.regression:250` | same period-SQLi test | consolidate |
| `controllers:194` (deleteItem) vs `softDelete.test.ts` | softDelete asserts list-hiding + DB state | replace the weaker one |
| `models:698` vs `supplierlessPurchase` | superset in the latter | drop the weaker |
| `models:742` vs `supplierPaymentAllocation` | the latter also asserts no partial write | drop the weaker |
| `purchaseReturn` 4 tests vs `api.integration` purchase-returns flow | HTTP suite drives route+zod+permission+model | keep as fast model feedback |
| `poCancelPartialReceipt 1/2/7` vs `poReceiptGl` | near-identical data + ledger asserts | fold in; **and commit the untracked file** |
| `systemWarehouseGuard` trigger test vs `expiredStockMigration:113` | migration test is isolated + positive control | drop the twin |
| `expiredStockSaleBlocking 7.8` vs `7.3`/`7.5a` | subsumed | fold or drop |
| `poCancelReversal case 6` vs `poCancelPartialReceipt`/`poReceiptGl:9` | covered | keep only case 7 |

---

## 7. Missing Regression Coverage (top by risk)

**Scenario:** Voiding a `refund_expected` purchase return must void or refuse the auto-issued supplier refund.
**Why it matters:** `voidReturn` voids the credit note but has zero references to `supplier_refunds` → GL/subledger disagree and the money becomes invisible.
**Current coverage:** none (`purchaseReturn`'s void test uses a return with no auto-refund; `supplierRefund` never voids a return).
**Proposed test:** seed a fully-paid purchase + return with `disposition:'refund_expected'`, call `voidReturn`, assert the refund is VOIDED (or the void refused), its GL lines voided, ledger nets to 0.

**Scenario:** PO `Draft→Submitted` transition must post nothing to the GL or supplier ledger (ACC-16).
**Why it matters:** the transition path posts a debit the spec forbids; a received-and-paid PO currently shows a spurious supplier credit.
**Current coverage:** create-path only (`glPoCommitment`).
**Proposed test:** create PO as Submitted → receive 10 → pay 1000; assert supplier ledger ≡ GL AP and no negative balance. **It fails today.**

**Scenario:** H1 end-to-end — buy 0.3, sell 0.1, sell 0.2; then a genuinely insufficient 0.4 sale → 400.
**Why it matters:** the H1 definition of done ("no legitimate sale rejected due to floating-point error") is protected only by unit tests of helpers.
**Current coverage:** simulated; would stay green if the real path reverted to raw `<`.

**Scenario:** Permission-aware behavior across the API.
**Why it matters:** `requirePermission` and `searchService.resolvePermissionContext` both short-circuit `role==='admin'`, and **every HTTP test logs in as the seeded admin** — so search permission filtering (the spec's headline rule), `/api/auth/me` `permissions` (drives client button authz), the item "cannot delete with existing stock" 400 guard, and the expense controller state machine are all unexercised.
**Proposed test:** one seeded non-admin User role per area; assert 403/filtered results. This single change covers the largest set of platform gaps at once.

**Scenario:** One flag-on (`feature_batch_locations`) end-to-end: `recordPurchase → sale → return → count`, asserting `batch_stock_by_location` + all four `stock_balances` columns + `getSellableAvailability`.
**Why it matters:** exposes the producers-don't-seed-location-rows defect, the extension-column drift, and the surplus asymmetry at once — the highest-leverage single addition in the audit.

**Scenario:** `Production.delete` must not double-count batches and must relieve FG value in the GL.
**Why it matters:** currently `stock_balances`=20 but `SUM(batches)`=28 and the FG removal posts no GL.
**Proposed test:** assert `SUM(stock_batches.quantity_remaining) == stock_balances.quantity` and `GL 1200 ≡ batch value` after delete.

**Scenario:** Multi-batch transfer + void must restore every consumed FIFO layer.
**Why it matters:** the OUT leg links only `consumption[0].batchId`; the void restores the full qty to the primary batch and leaves the others drained.
**Proposed test:** two source batches (6@5, 4@8), transfer 10, void → assert per-batch qty and coverage == balance on both warehouses.

**Scenario:** `server.ts` boot wiring for the expiry sweep must actually run.
**Why it matters:** every suite imports `app.ts`; deleting the `server.ts:79` call leaves all expiry tests green while the sweep silently stops (`PROJECT_PLAN_expired_stock.md §5.2` explicitly asked for this).

**Scenario:** Purchase double-void idempotency (`Purchase.ts:593`), plus the "cannot void a purchase with an open purchase return" guard (distinct from the tested `returned_quantity>0`, since a voided return resets that column), and the HTTP happy-path purchase void.

**Scenario:** Backup scheduler + retention + integrity-failure branch — `startBackupScheduler` is short-circuited by `NODE_ENV==='test'`, so it has 0% coverage everywhere.

**Scenario:** Owner-equity and supplier-refunds at the API layer — 14 routes with `requirePermission`, client-costing-field rejection, and the 400-vs-500 `isClientError` mapping are completely unexercised (model-only today).

---

## 8. Recommended Cleanup Plan

**Ordered by risk-reduction per change:**

1. **Must remain untouched (highest value):** the suites in §3 — they are the sole protection of their invariants.
2. **Fix the tests that are actively misleading (do now):**
   - `moneyPaths` (3 vacuous → rewrite with seeded data)
   - `purchaseVoid` batch-identity (rewrite to call `recordPurchase`)
   - `cashTruth:30/:92/:47` (source-scans → data tests)
   - `paymentEditReposting:511/551` (the 2026-09-30 time-bomb)
   - `accountingPeriodRoller:3`, `glPostingMatrix:4`, `glSoftDelete:1` (vacuous conditionals)
   - `paymentGuards:109` (test the real migration CHECK)
3. **Add the two failing-today tests first** so the conflicts become visible in CI, not just in an audit: PO transition-path ACC-16, and H1 end-to-end.
4. **Decide the three spec questions before writing more tests** — PO commitment (ACC-16), boot-sweep stock writes, transfer-void GL. Several suites encode behavior the current specs prohibit; until that's resolved, KEEP–UPDATE is the honest ceiling.
5. **Trim duplicates** only after confirming the stronger sibling stays; fold `poCancelPartialReceipt` into `poReceiptGl` and **commit that untracked file**.
6. **Delete the obsolete CSRF block** in `security.regression.test.ts` (5 tests) and the dead CSRF ceremony in `controllers.test.ts`.
7. **Tighten the ~14 permissive status-range assertions** and replace the ~7 status-only smokes with value/DB-state assertions.
8. **Add the missing-coverage suites in this order:** permission-aware API tests (one seeded non-admin role) → flag-on batch-location end-to-end → production-delete/transfer-void batch-coverage → `server.ts` boot wiring → owner-equity/supplier-refunds/expense API matrices → purchase double-void + open-return-void.
9. **Hygiene last:** shared `getAuthCookie`, remove `console.log`/`global.authCookie`/`as any`/unused imports, replace sleeps with `flushLogs()`, extend `createInvoice` to express header discounts.

---

**Regression audit complete — no files were modified.**
