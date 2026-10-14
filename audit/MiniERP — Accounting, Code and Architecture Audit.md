# MiniERP — Accounting, Code and Architecture Audit

|  |  |
| --- | --- |
| **Repository** | `github.com/mfbgull/minierp-flutter` (Flutter desktop client + TypeScript/Node server on SQLite) |
| **Commit audited** | `87f1265b` — *fix(server): make inventory invariant E symmetric* |
| **Report date** | 10 October 2026 |
| **Method** | Source reading (file:line cited), plus the real HTTP API run against throwaway SQLite databases (existing test harness) with \~40 purpose-built probes. Every finding marked *verified* was reproduced by running it. |
| **Companion files** | 8 regression test files (78 tests) and 9 candidate patches — see Section 8 |

> **Reading guide.** *Verified* = reproduced by running the code. *By code* = read in the source but not executed. Line numbers prefixed `~` are approximate (the file was re-read after edits to my sandbox copy). Account codes are as seeded in the repo: 1000 Cash, 1010 Bank, 1100 Accounts Receivable, 1110 Customer Credit (contra-asset), 1200 Inventory, 1300 Employee Loans Receivable, 2000 Accounts Payable, 3000 Owner Capital, 4000 Sales Revenue, 4100 Sales Returns (contra-revenue), 4150 Restocking-Fee Income, 5000 COGS, 6000 Operating Expenses, 6100 Wages, 6300 Loan Write-off, 7000 Production Clearing, 7100 Inventory Adjustment, 7201 Expired-Stock Write-off.

---

## 1. Executive summary

**Overall risk rating: HIGH.**

The double-entry core is well built: `postEntry` checks balance in integer minor units with no tolerance (`accountingService.ts:300-311`), the trial balance balanced in **every** scenario I ran, voids reverse rather than delete, and the existing suite (113 suites / 991 tests) is strong. The risk is concentrated in four places: **report assembly** (balance sheet, P&L), **period locking**, **inventory/COGS edge paths** (returns, production), and **authorization around user, role, report and file handling**.

### Top 5 accounting issues

1. **ACCT-001** — The balance sheet stops balancing (off by 2× the amount) after any customer store-credit offset.
2. **PROD-001** — Production never relieves raw-material inventory in the GL: inventory is overstated and balance-sheet profit diverges from the P&L by the material cost.
3. **ACCT-004** — A backdated invoice or purchase can post into a closed period when the closed period has a non-month name; production and stock adjustments bypass the check entirely.
4. **ACCT-003** — Partial sales returns restore the wrong quantity (e.g. 3.003 for a return of 3; **zero** for 1 of 3,000), corrupting batches, stock and inventory value.
5. **PAY-001 / ACCT-013** — A salary overpayment is posted twice (cash and wages overstated by the excess), and reversing a cash inflow (capital edit/void, receipt delete) can drive cash negative.

### Top 5 code / architecture / security issues

1. **AUTHZ-002 (Critical)** — A non-admin holding only `users:update` can reset the admin's password and log in as admin.
2. **REP-001 / REP-002 (High)** — The custom-report engine ignores per-module permissions, and its field whitelist can be bypassed to extract hidden columns (an IBAN was recovered character by character by a reports-only user).
3. **FILE-001 (High)** — A user with only `employees:update` can delete arbitrary files on the server (including backups and the database) via a crafted document `file_path`.
4. **AUTHZ-003 / AUTHZ-004 (High)** — Delegated user/role managers can mint access beyond their own (assign the Admin role; grant their own role every permission).
5. **BK-006 (High, documentation)** — The documented restore procedure deletes the live database *before* copying from a path that does not exist.

### Top 5 edge-case failures

1. Backdated sale/purchase into a closed (custom-named) period is accepted (ACCT-004).
2. Malformed (`2026-13-45`) and far-future (2030/2031) dates are accepted across sales, purchases, payments, production (ACCT-006).
3. Negative tax rate accepted and posted as extra revenue; discounts above 100% silently clamp; price/tax have no upper bound (ACCT-007).
4. Goods-receipt `received_quantity: "abc"` is accepted and **nulls the PO line** (PO-001).
5. Negative production overhead creates a negative-unit-cost batch (PROD-004).

### Recommendation

**Do not rely on the balance sheet, P&L, supplier balances or production costing for decisions or filing until the Critical/High items below are fixed.** All but two (PAY-001 and ACCT-013, which need a design decision from you) have a verified candidate patch (Section 8). **Ship order matters:** the P&L fix (ACCT-002) must not go out without the production fix (PROD-001), or P&L profit will be wrong for any business that uses production (demonstrated: 2,000 instead of 1,000). Section 7 gives the plan and the decisions only you can make.

### By the numbers

|  | Findings | Verified fix + tests | Tests only (decision needed) | Open / no tests |
| --- | --- | --- | --- | --- |
| Accounting & inventory (ACCT, PO, PRET, PROD, PAY, WO) | 29 | 15 | 6 | 8 |
| Code, security & authorization (AUTHZ, REP, FILE, BK, CODE) | 24 | 15 | 0 | 9 |

*Counts are of the finding IDs in Sections 2–3 (BK-001…006 counted individually; REP-003/004 counted individually).*

---

## 2. Accounting findings

### \[ACCT-001\] Balance sheet fails to balance after a store-credit offset — **High** (verified)

- **Flow:** Sales / customer credit. **Files:** `models/Reports.ts:469-482`, `services/accountingService.ts:159-161, 636-646`, `migrations/add-customer-credit-account.sql:6`, `__tests__/helpers/accountingInvariants.ts:~220`.
- **What/why:** Account 1110 is credit-normal but only ever *debited* (`postCreditOffsetEntry`: Dr 1110 / Cr 1100); nothing credits it when store credit is granted (`invoiceReturnService.ts:~1028` moves it to `customers.credit_balance` with no GL entry). `getAccountBalance` signs by the account's own normal side, and the balance sheet sums asset balances unsigned, so a debit balance on 1110 is subtracted from assets instead of added.
- **Impact:** With a 200 offset: total assets 9,800 vs liabilities+equity 10,200 (`balanced:false`), AR shown as −100 and other assets −200 while the customer actually owes +100. Trial balance still balanced.
- **Evidence:** probe + `auditRegression.test.ts`. The AR invariant masks it with `abs(1100+1110)`.
- **Fix (verified):** re-sign balances to the account type's natural side when summing. **Status:** patch `candidate-fixes-ACCT-001-004`.

### \[ACCT-002\] P&L omits accounts the balance sheet includes — **High** (verified)

- **File:** `models/Reports.ts:423-431` (P&L reads only 4000, 4100, 5000, 6000) vs `:496-514` (balance sheet uses all revenue/expense accounts).
- **Impact:** Restocking-fee income (4150) and payroll (6100) are invisible in the P&L: with a 100 fee P&L profit 250 vs balance-sheet 350; with 500 salary 250 vs −150. Wages, shrinkage (7100/7200), loan write-offs (6300) and production clearing (7000) are excluded by the same list.
- **Fix (verified):** drive the P&L by account type. **⚠ Dependency:** only safe together with PROD-001 (see Section 7). **Status:** patch `ACCT-001-004` + `round5`.

### \[ACCT-003\] Partial-return restock quantity is wrong — **High** (verified)

- **File:** `models/Invoice.ts:659` (`ratio = roundQty(returned/sold)` at 3 dp, then multiplied back).
- **Impact:** batch change for returns: 7→3 gives +3.003; 3→1 gives +0.999; 1,500→1 gives +1.5; **3,000→1 gives 0** (the unit is back in `stock_balances` and the GL but in no batch, so it can never be sold). Both stock and inventory-value invariants fail.
- **Fix (verified):** keep the ratio exact. **Status:** patch `ACCT-001-004`.

### \[ACCT-004\] Closed-period bypass on create — **High** (verified)

- **Files:** `accountingService.ts:318-353` (auto-creates a `YYYY-MM` period when none is open), `:328-332` (`ON CONFLICT DO NOTHING` only blocks if the closed period is *named* `YYYY-MM`), `accountingController.ts:~262-278` (custom names/overlap allowed), `closedPeriodImmutability.test.ts:51-222` (tests only void/edit, not create).
- **Impact:** with a closed period `FY-PROBE` covering August, invoices dated 08-15/08-20 and a purchase dated 08-23 returned 201, posted GL lines, and auto-created an overlapping open `2026-08` period. Payments (409), returns (400) and the expense *Recorded* transition are correctly guarded. Closing is only a status flag — no closing entry; the balance sheet's "YTD" net income is cumulative since inception.
- **Fix (verified):** assert not-closed inside `postEntry` and in `postLegacyStockEntry` (covers production, stock adjustments, write-offs). **Status:** patches `ACCT-001-004` + `round5`.

### \[ACCT-005\] Cash purchases bypass the cash-funds guard — **Medium** (verified; policy decision)

- **File:** `models/Purchase.ts:299-304` hard-codes `paymentMethod: supplier ? 'credit' : 'cash'` (client `payment_method` is ignored); `assertSufficientFunds` is used only in `PaymentRecordingService.ts:236`, `SupplierPaymentService.ts:80`, `OwnerWithdrawal.ts:229/463`, `Expense.ts:218`.
- **Impact:** a 10,000,000 supplier-less purchase returned 201 and drove cash negative. Same gap for salary and loans (PAY-003).
- **Fix:** guard exists as a patch but **broke 12 existing suites** whose fixtures seed stock through unfunded cash purchases — hence a *policy* decision (require opening cash). **Status:** `policy-patch-ACCT-005`; test red by design.

### \[ACCT-006\] No date validation on most create endpoints — **Medium** (verified; no tests yet)

- **File:** `middleware/validation.ts:110-119` (`.passthrough()` schemas with only `min(1)` on date strings; owner capital/withdrawal are the exception and are strict).
- **Impact:** `invoice_date: "2026-13-45"` accepted and posted (by code, creates a period named `2026-13`, `accountingService.ts:324-327`); invoices/payments/purchases/production dated 2030–2031 accepted; sale dated before the item's first purchase accepted (COGS against non-existent stock).

### \[ACCT-007\] Pricing and tax bounds — **Medium** (verified; no tests yet)

- **Files:** `accountingService.ts:536` (`if (taxAmount > 0)`), `InvoiceCreationService.ts:74` (zero price allowed).
- **Impact:** negative `tax_rate` accepted and the whole total posts to revenue with no tax line; tax rate 500% accepted; discount >100% silently clamps the total to 0 ("Paid", COGS still posted); negative discount silently ignored; price 1e15 accepted.

### \[ACCT-008\] Duplicate submission without an idempotency key — **Medium** (verified)

- Two identical invoice POSTs created two invoices. Server protection exists only when `Idempotency-Key` is sent (`InvoiceCreationService.ts:124-130`); replay with a key works. See CODE-004 for which client flows send keys.

### \[ACCT-009\] Scope gaps in the accounting model — **Medium**

- Expenses post Dr 6000 / Cr cash only (`accountingService.ts:778-812`): no accrual, prepayment or payable. No supplier-bill document or three-way match; no input tax on purchases; no customer advance payments (`paymentValidation.ts:56-57` requires allocations; probe: 400); payroll is cash-basis with no liability.

### \[ACCT-010\] AR aging ignores the as-of date; null due dates fall out of the buckets — **Medium** (verified; no tests yet)

- **File:** `Reports.ts:7-31` (uses current `balance_amount`).
- **Impact:** aging "as of 2026-09-01" listed invoices dated 09-10 as current; an invoice with `due_date: null` (accepted by the API) counted in the total but in no bucket (250 vs 200).

### \[ACCT-011\] AP aging ignores the as-of date — **Medium** (verified; no tests yet)

- **File:** `Reports.ts:~333-392` (no date predicate). A purchase unpaid at 09-10 showed 1,001; after a payment dated 09-25 the *same* as-of-09-10 report showed 1.

### \[ACCT-012\] Supplier balance wrong after a backdated purchase followed by a payment — **High** (verified)

- **Files:** `models/SupplierLedger.ts:63-73` (`getBalance` orders by `transaction_date`) vs `:88-102` (`rebuildBalances` chains by `id`); `services/SupplierPaymentService.ts:~63-72` (sets header = `getBalance − amount`). Only this path skips `rebuildBalances`.
- **Impact:** purchase A (09-20, 1,000), backdated purchase B (09-10, 500), payment 200 → supplier shows **800**, ledger and GL say **1,300**. Invariants flag −500 / +500. The customer side handles the same pattern correctly (control).
- **Fix (verified):** rebuild the chain after a payment. **Status:** patch `round2`.

### \[ACCT-013\] Reversing a cash inflow can overdraw cash — **High** (verified; decision needed)

- The funds guard covers only cash-*out*. Lowering owner capital 1,000→100 after 800 was withdrawn left cash at −700; voiding it left −800; deleting a customer receipt after its cash was spent left −900. Likely same class (not tested): supplier-refund void, loan-repayment void.
- **Decision:** guard capital edit/void and receipt delete with an "account stays ≥ 0 across all later postings" check. **Status:** tests only (`auditRegression3`).

### \[PO-001\] Goods receipt accepts a non-numeric quantity and nulls the PO line — **High** (verified, API-level)

- **File:** `controllers/purchaseOrderController.ts:~380` (`'abc' <= 0` is false); schema is `items: z.array(z.any())`.
- **Impact:** `received_quantity: "abc"` → 201, text stored in `goods_receipt_items`, PO line `received_quantity` overwritten with NULL, no stock or GL. **Fix (verified):** validate numeric type. **Status:** patch `round2`.

### \[PRET-001\] Purchase-return amounts are not rounded — **Medium** (verified)

- **File:** `models/PurchaseReturn.ts` (line amount = qty × unit cost, unrounded). Returning 0.333 of a 10.55 item stored 3.51315 on the header, credit note and supplier ledger while the GL posted 3.51. **Fix (verified):** round at line and total. **Status:** patch `round2`.

### \[PRET-002\] Purchase-return behaviours to be aware of — **Medium** (verified; not fixed)

- A supplier-less (cash) purchase cannot be returned ("no linked supplier — cannot post the credit note", `PurchaseReturn.ts:~812`); combined with ACCT-005 cash purchases are effectively unreturnable.
- `disposition: 'refund_expected'` records the supplier refund as **received immediately** in cash (hard-coded `payment_method: 'cash'`, `~575-590`): GL cash rose by 50 with no confirmation any money arrived.
- Returns before the purchase date, receipts before the PO date and 2031-dated receipts are accepted.

### \[PROD-001\] Raw-material consumption is never relieved in the GL — **High–Critical** (verified)

- **File:** `models/StockMovement.ts:~488-520` (output posts Dr 1200 / Cr 7000 for the *whole* batch cost; the code comment calls consumption out of scope); `models/Production.ts` (consumption posts nothing).
- **Impact:** 100 raw units @10 consumed + 50 overhead → 10 units: GL inventory 2,050 vs batch value 1,050 (overstated by 1,000). After selling all 10 for 2,000 the GL still held 1,000 of phantom inventory with zero stock; balance-sheet net income 2,000 vs true profit 950. The original P&L happens to read 950 only because it ignores 7000.
- **Fix (verified):** post Dr 7000 / Cr 1200 at FIFO material cost, keyed to the production id, so 7000 keeps only absorbed overhead; delete voids it. **Assumption to confirm:** overhead is also recorded as an expense when incurred. **Deployment:** historic productions need a one-time backfill. **Status:** patch `round5`.

### \[PROD-002\] Production unit cost rounded with *quantity* precision — **Medium** (verified)

- `Production.ts` uses `roundQty` (3 dp) for money: 7,000 units from 100,000 → 14.286/unit → batch value 100,002 vs 100,000 in the GL. **Status:** patch `round4`.

### \[PROD-004\] Negative overhead accepted — **Medium** (verified)

- Overhead −500 → 201, negative unit-cost batch, GL posting skipped. **Status:** patch `round4`.

### \[PROD-005\] Deleting a production corrupts stock — **High** (verified)

- **File:** `Production.ts:~590-625`. Raw batches double (200 batches vs 100 balance) because the code restores the batch directly *and* records a positive ADJUSTMENT movement (which creates another batch and posts extra GL); the only guard checks that GL lines exist, so deleting is allowed after part of the output was sold (4 of 10 sold: remaining 6 zeroed, all raw restored, the 4 units' cost left in COGS — stock from nothing).
- **Fix (verified):** refuse unless the output batch is intact; void both postings; restore once with no adjustment GL. **Status:** patch `round5`.

### \[PROD-006\] Production and stock adjustments bypass the closed-period check — **High** (verified)

- `postLegacyStockEntry` does a raw `INSERT INTO journal_lines`, bypassing `postEntry`. A production in a closed custom-named period returned 201. **Status:** patches `round4` + `round5` (central guard).

### \[PROD-007\] An item can be produced from itself — **Low** (verified). Patch `round4`.

### \[PAY-001\] Salary overpayment is posted twice — **High** (verified; decision needed)

- **File:** `employeeController.ts:~318-365`. Paying 1,500 on a 1,000 salary ("full") auto-creates a 500 advance for the excess and posts a second salary entry for it: bank −2,000, wages +2,000 for 1,500 actually paid; history shows 2,000 paid.
- **Decision:** split the payment into current-month and advance rows totalling the amount paid, posted once. **Status:** tests only.

### \[PAY-002\] Voiding the primary salary payment leaves its advance posted — **Medium** (verified; decision needed)

- After voiding the 1,500 payment the 500 advance stayed active (500 of cash-out and wages remained). **Status:** tests only.

### \[PAY-003\] Salary and loan payouts bypass the funds guard — **Medium** (verified; policy decision)

- Unfunded salary accepted; a 99,000,000 loan left cash at −99,000,300. Same decision as ACCT-005.

### \[PAY-004\] Salary-deduction loan repayment posts nothing to the GL — **Medium** (verified; latent)

- **File:** `employeeController.ts:~785` (deliberately skipped when `salary_payment_id` is set). Loan balance 700 vs GL 1300 = 900; after write-off 200 stays stuck in Loan Receivable. The Flutter client appears never to send `salary_payment_id`, so this is reachable only via the API. **Status:** tests only.

### \[WO-001\] Expired-stock write-off value is rounded with the wrong precision — **Medium** (verified)

- **File:** `StockMovement.ts:~1507` (`roundQty` on unit cost and value): 1,000 × 1.23456 posted 1,235.00 instead of 1,234.56; 3 × 0.3333 stored 0.999 in the journal. **Fix (verified):** exact unit cost, round value to 2 dp, round all legacy journal amounts. **Status:** patch `round6`.

### \[WO-002\] Damaged stock cannot be written off — **Medium** (verified; feature decision)

- The endpoint requires a past expiry date; a damaged batch with no expiry returns "not expired", and the damaged-transfer route has no GL effect. No write-off reversal exists either.

### \[WO-003\] Write-off could post into a closed period — **Medium** (verified). Covered by the central guard (`round5`).

---

## 3. Code, architecture and security findings

### \[AUTHZ-002\] Non-admin can take over the administrator account — **Critical** (verified)

- **File:** `controllers/userController.ts` (no check on the target's role in update/delete/reset-password/toggle-status).
- A role holding only `users:read/create/update` called `reset-password` on the admin, then logged in as admin (200 both times); it could also change the admin's e-mail. **Fix (verified):** only admins may modify admin accounts. **Status:** patch `round8`.

### \[AUTHZ-003\] `users:create` / `users:update` can hand out the system Admin role — **High** (verified)

- A manager created a user with the Admin role (201) and promoted another (200); the account then holds every permission in that role. **Fix (verified):** a non-admin may assign only roles whose permissions they hold. **Status:** `round8`.

### \[AUTHZ-004\] `roles:update` lets a role grant itself everything — **High** (verified)

- A role manager gave their own role all 88 permissions (200); same hole when creating a role. **Fix (verified):** a non-admin can grant only permissions they hold. **Status:** `round8`.

### \[AUTHZ-001\] 14 permissions guard routes but do not exist in the permissions table — **Medium** (verified; decision needed)

- `owner_equity:*`, `invoices:void`, `reports:update/delete`, `expenses:delete`, `inventory:write` (the only `write` action), `accounting:update`, `forecasts:delete`, `admin:*` cannot be granted to any non-admin role: non-admins cannot edit/delete their own saved reports, delete expenses or void invoices. Conversely several seeded permissions are used by no route (`expenses:approve`, `production:update`, `purchases:update`, `sales:*`).

### \[REP-001\] Custom reports ignore per-module permissions — **High** (verified)

- **File:** `controllers/customReportsController.ts:~314-339`. A role with only `reports:read` + `reports:create` (403 on `/api/employees`) read an employee's `salary` through a report; `payments` and `activity_log` were open too. **Fix (verified):** entity → module `read` check on run and discovery. **Status:** patch `round7`.

### \[REP-002\] Report field whitelist can be bypassed — **High** (verified)

- Computed-column names are added to the valid-field set and HAVING filters skip validation (`services/reportQueryEngine.ts`). A computed column named `bank_iban` (a real, deliberately hidden column) allowed filtering on it; a reports-only user recovered `PK36SCBL` of an employee's IBAN one character at a time. Other hidden columns include `cnic_no`, `bank_account_no`, `address`. **Fix (verified):** computed names may not collide with real columns; HAVING fields validated. **Status:** `round7`.

### \[REP-003/004\] Report engine defects — **Low / Medium** (verified)

- Two registry fields point at non-existent columns (`stock_balances.id`, `boms.notes`). A HAVING with a bound value always failed (count query lacked the HAVING but received its parameters) and a grouped report's count was a row count. **Status:** `round7`.

### \[REP-005\] Report engine gaps — **Low** (by code/verified)

- `groupBy.aggregates` is declared but never read (grouped reports return one arbitrary row's value for non-grouped columns; the Flutter client has no group-by UI). No default or maximum row cap (a limit of 1e12 is accepted). `contains/starts_with` do not escape `%`/`_`.
- **What held up:** values are bound parameters; aliases and identifiers are quoted; sort direction is forced to ASC/DESC; the expression validator is a real grammar parser; saved reports are isolated per owner (404 for others).

### \[FILE-001\] Arbitrary file deletion through employee documents — **High** (verified)

- **Files:** `employeeController.ts:~527-536` (stores a body-supplied `file_path`), `:~568-575` (`unlinkSync(path.join(uploads/employees, file_path))`). A user with only `employees:update` deleted a file outside the upload folder via `file_path: "../…"`; the same works against backups or the live DB. A document could also be deleted through another employee's URL. **Status:** patch `round9`.

### \[FILE-002\] Uploads can be served as active content — **Medium** (verified)

- **File:** `middleware/upload.ts` (MIME is client-declared; extension kept from the original name). `evil.html` declared as `application/pdf` was stored as `.html` and served as `text/html`. **Fix (verified):** extension must match the type; always serve as attachment + nosniff. **Status:** `round9`.

### \[BK-001…006\] Backup and restore — **Medium–High** (verified)

- **BK-001** a database path containing an apostrophe (e.g. `C:\Users\O'Brien`) makes every backup fail silently (`VACUUM INTO '<path>'` built by concatenation; `backupService.ts:~101`). **BK-002** downloading a backup (a full copy of the DB) leaves no audit row. **BK-003** CLI-named backups (`erp-backup-<ts>.db`) are listed but cannot be downloaded or deleted (404) and are pruned by the in-app retention. **BK-004** two backups in the same second fail with 500. **BK-005** the service ignores `BACKUP_DIR` (the CLI honours it), so scheduled backups cannot go to another drive. **BK-006** the README restore runs `rm -f erp.db …` and *then* `cp ../backups/…`, but backups live in `server/database/backups/` — following it literally deletes the live database and fails the copy. All fixed in patch `round9`.
- **Not fixed:** uploads (employee documents) are not part of any in-app backup although the spec says they must be; backups sit on the same disk as the DB unless `BACKUP_DIR` is set; after >28 days of inactivity only the newest backup survives retention; no integrity check at server start; backups are unencrypted copies (password hashes, salaries, bank details); audit entries are queued and flushed every second so a crash can lose the last second.

### \[CODE-001\] Validation failures surface as HTTP 500 — **Medium** (verified)

- Zero/negative quantity, negative price, unknown customer, invalid payment method, supplier over-allocation, over-receipt, duplicate receipt and most production validations return 500 "Failed to …" (`InvoiceCreationService.ts:67-76` throws plain `Error`). Nothing is written, but clients cannot distinguish bad input from server faults.

### \[CODE-002\] Refresh endpoint trusts token claims — **Medium** (by code)

- `authController.ts:62-83` re-issues an access token from the refresh token's claims with no DB check; admin status comes from the token role. A deactivated user, or a demoted admin, keeps access for up to 7 days; I did not read logout/change-password to see whether they revoke tokens.

### \[CODE-003\] Authentication hygiene — **Low**

- `admin123` default admin password when `DEFAULT_ADMIN_PASSWORD` is unset, with a production guard (`config/database.ts:249-259`). Minimum password length is 6. `users.role` (string) and `users.role_id` are separate and can disagree.
- **Good:** JWT secret required (`auth.ts:8-10`), algorithm/issuer/audience pinned, httpOnly + sameSite-strict cookies, helmet, CORS allow-list, `foreign_keys = ON`, WAL, busy timeout (`database.ts:40-49`).

### \[CODE-004\] Client does not send idempotency keys for several money-moving calls — **Medium** (by code)

- Keys are sent for invoice create, payments, expenses and purchases (`core/utils/idempotency_key.dart`, e.g. `sales_invoice_form_page.dart:1075`, `pos_screen.dart:281`) but not for sales returns/settlements (`invoice_repository.dart:271-310`), owner capital/withdrawal, salary payments or supplier refunds, although the server defines scopes for them (`utils/idempotency.ts:39-44`). Verified server side: replay with a key works; without one, a salary or capital POST duplicates.

### \[CODE-005…007\] Flutter client quality — **Low** (grep-level; `flutter analyze` was **not** run — no SDK in the sandbox)

- 397 Dart files; 101 `Widget _build*()` helper methods; very large files (`sales_invoice_form_page.dart` 2,126 lines, `dashboard_screen.dart` 1,774, `date_range_picker.dart` 1,428, `csv_export.dart` 1,387, `purchase_order_form_dialog.dart` 1,298, `invoice_return_dialog.dart` 1,162, `supplier_payment_modal.dart` 1,024); 28 `catch (_)` sites that discard the error; 155 `late`; 783 `dynamic` (mostly JSON maps, not separated); lints limited to `flutter_lints`. No real `print()` calls. Business logic is mostly in `calculations/` folders. Money totals are authoritative on the server, which rejects a client total that disagrees (`InvoiceCreationService.ts:89-91`).

### Route-level authorization (audit result) — **held up**

344 routes in 32 files were probed as anonymous, zero-permission and read-only users: 0 unauthenticated routes, 0 zero-permission leaks (`/api/search` is intentionally auth-only and filters internally), 0 write routes open to a read-only user. Routes with destructive-looking paths got only the anonymous probe.

---

## 4. Reconciliation matrix

| Report | Balanced? | Reconciles with | Original code | With patches | Notes |
| --- | --- | --- | --- | --- | --- |
| Trial balance | Yes | GL | ✅ (every scenario) | ✅ |  |
| Balance sheet | Yes → **No** | Trial balance | ❌ after a credit offset | ✅ | ACCT-001 (off by 2×offset) |
| P&L vs balance-sheet net income | **No** | BS retained earnings | ❌ with 4150 / 6100 / 7xxx postings | ✅ (needs PROD-001) | ACCT-002; production inflates BS NI by the material cost |
| AR subledger | Yes | GL AR (1100 + 1110) | ⚠️ passes only through `abs()` and netting; 1100 alone misstated | ✅ | ACCT-001 |
| AP subledger / supplier balances | **No** | GL AP | ❌ after a backdated purchase + payment | ✅ | ACCT-012 |
| Inventory (GL vs batches) | **No** | GL 1200 | ❌ after partial returns, production, production delete | ✅ | ACCT-003, PROD-001, PROD-005 |
| Stock summary vs batches | **No** | `stock_balances` | ❌ after partial returns, production delete | ✅ |  |
| Cash | Yes/No | GL cash | ⚠️ can go negative (ACCT-005, 013, PAY-003) | ⚠️ open decisions |  |
| Customer statement | Yes | Customer ledger | ✅ (after cancel: closing 200 = balance 200) | ✅ | payment voids not tested |
| AR / AP aging as-of | **No** | — | ❌ | ❌ | ACCT-010/011, no fix yet |

---

## 5. Transaction flow diagrams

Pattern: **\[UI action\] → \[API\] → \[service/model\] → \[DB write\] → \[journal entry\] → \[report impact\]**. *As-audited* flows are shown; fixes noted in brackets.

**Sales invoice** `Sales form / POS` → `POST /api/invoices` (+`Idempotency-Key`) → `InvoiceCreationService` (FIFO batch consumption, validation) → `invoices`, `invoice_items`, `stock_movements`, `customer_ledger` → **Dr 1100 AR / Cr 4000 Revenue (+ tax payable)**; **Dr 5000 COGS / Cr 1200 Inventory** (batch cost); credit offset: **Dr 1110 / Cr 1100** → Income statement, AR aging, balance sheet. *\[ACCT-001, -004, -006, -007\]*

**Customer receipt** `Payment dialog` → `POST /api/payments {customer_id, invoice_allocations}` → `PaymentRecordingService` → `payments`, allocations, `customer_ledger` → **Dr 1000/1010 / Cr 1100** → AR, cash. Overpayment/advance not supported. *\[ACCT-013 on delete\]*

**Direct purchase / goods receipt** `Purchase form` → `POST /api/purchases` → `Purchase.ts` → `purchases`, `stock_batches` (new batch), `supplier_ledger` → supplier: **Dr 1200 / Cr 2000 AP**; no supplier: **Dr 1200 / Cr 1000 Cash** (forced, no funds check). PO path: `POST /api/purchase-orders/:id/receipts` → **Dr 1200 / Cr 2000**. *\[ACCT-005, PO-001, ACCT-012\]*

**Supplier payment** `POST /api/payments {supplier_id, purchase_allocations}` → `SupplierPaymentService` (funds guard ✅) → `supplier_ledger` → **Dr 2000 / Cr 1000/1010**. *\[ACCT-012 header balance\]*

**Sales return** `Return dialog` → invoice-return endpoint → `invoiceReturnService` → `invoice_returns`, restock to batches, ledger → **Dr 4100 Sales Returns / Cr 1100**; **Dr 1200 / Cr 5000** (COGS reversal); fee: **Cr 4150**; refund via `PaymentRecordingService`; store credit moves to `customers.credit_balance` with **no GL entry**. *\[ACCT-001, -003\]*

**Purchase return** `POST /api/purchase-returns` → `PurchaseReturn.ts` → credit note, supplier ledger, source batch reduced → **Dr 2000 / Cr 1200** (disposition `refund_expected`: immediate cash refund). *\[PRET-001, -002\]*

**Expense** `POST /api/expenses` (Draft) → admin **Recorded** transition (period + funds checks) → **Dr 6000 / Cr cash/bank**. *\[ACCT-009\]*

**Production (as patched)** `POST /api/productions` → `Production.ts` (FIFO consumption) → output batch → **Dr 1200 / Cr 7000** (output value) and **Dr 7000 / Cr 1200** (materials consumed) → 7000 keeps absorbed overhead. *\[PROD-001…007\]*

**Payroll and loans** `POST /api/employees/:id/salary/pay` → **Dr 6100 / Cr cash/bank** (+ auto-advance second entry — PAY-001); loan: **Dr 1300 / Cr cash**; repayment: **Dr cash / Cr 1300** (none for salary-deduction — PAY-004); write-off: **Dr 6300 / Cr 1300**.

**Owner equity** Capital **Dr cash/bank / Cr 3000**; cash drawing **Dr Drawings / Cr cash** (funds guard ✅); goods drawing **Dr Drawings / Cr 1200** at FIFO batch cost. *\[ACCT-013 on capital edit/void\]*

**Expired stock write-off** `POST /api/inventory/expired/write-off` → auto-transfer to EXPIRED warehouse → **Dr 7201 / Cr 1200** (value = qty × batch cost). *\[WO-001…003\]*

---

## 6. Edge-case findings

✅ handled · ⚠️ partial · ❌ not handled · ❓ not probed. All rows except where marked *(code)* were run through the real API.

| Module | Transaction | Edge case | Result | Evidence | Severity | Fix |
| --- | --- | --- | --- | --- | --- | --- |
| Sales | Invoice | Zero quantity | ✅ rejected (HTTP 500) | `InvoiceCreationService.ts:67-76` | Low | map to 400 |
| Sales | Invoice | Negative quantity / price | ✅ rejected (500) | same | Low | map to 400 |
| Sales | Invoice | Zero price | ⚠️ accepted, status Paid, COGS posted | `:74` | Medium | require override |
| Sales | Invoice | Discount > 100% / negative discount | ⚠️ clamped / ignored | probe | Medium | reject |
| Sales | Invoice | Negative tax rate | ❌ posted as revenue, no tax line | `accountingService.ts:536` | Medium | reject \<0 |
| Sales | Invoice | Tax 500% / price 1e15 | ⚠️ accepted | probe | Low | bounds |
| Sales | Invoice | Oversell | ✅ 400 | probe | — | — |
| Sales | Invoice | Unknown customer / empty items | ✅ rejected | probe | Low | 400 |
| Sales | Invoice | Malformed date `2026-13-45` | ❌ accepted | `validation.ts:110-119` | Medium | strict date |
| Sales | Invoice | Future date 2030 / before stock existed | ⚠️ accepted | probe | Medium | policy |
| Sales | Invoice | Closed period (custom-named) | ❌ posts | `accountingService.ts:318-353` | High | `postEntry` guard |
| Sales | Invoice | Duplicate submit, no key | ⚠️ two invoices | probe | Medium | client keys |
| Sales | Invoice | Null `due_date` | ⚠️ falls out of aging buckets | `Reports.ts:7-31` | Medium | default due date |
| Purchases | Direct | Zero/negative qty, negative cost | ✅ rejected | probe | — | — |
| Purchases | Direct | Zero cost | ⚠️ rejected as "required" (free goods unrecordable) | probe | Low | — |
| Purchases | Direct | Cash overdraw (no supplier) | ❌ cash negative | `Purchase.ts:299-304` | Medium | policy |
| Purchases | Direct | Closed period / future date | ❌ / ⚠️ | probe | High / Medium | — |
| Purchases | PO receipt | Non-numeric quantity | ❌ nulls PO line | `purchaseOrderController.ts:~380` | High | validate type |
| Purchases | PO receipt | Over-receipt / duplicate / status jump / void after sold | ✅ rejected | probe | — | — |
| Purchases | PO receipt | Closed period / before PO date / 2031 | ❌ / ⚠️ | probe | High | — |
| Sales returns | Return | Qty > sold, cumulative over-return, zero/negative | ✅ | probe | — | — |
| Sales returns | Return | Closed period | ✅ 400 | probe | — | — |
| Sales returns | Return | Fee > goods value | ✅ clamped | probe | — | — |
| Sales returns | Return | Partial qty rounding | ❌ | `Invoice.ts:659` | High | exact ratio |
| Sales returns | Return | Dated before invoice | ⚠️ accepted | probe | Low | — |
| Purchase returns | Return | Over-return, zero/negative, goods already sold | ✅ | probe | — | — |
| Purchase returns | Return | Fractional qty amounts | ❌ unrounded | `PurchaseReturn.ts` | Medium | round |
| Purchase returns | Return | Supplier-less purchase | ⚠️ unreturnable | `:~812` | Medium | decision |
| Purchase returns | Return | Closed period / before purchase date | ❌ / ⚠️ | probe | High | — |
| Warehouses | Transfer | Same warehouse, negative, zero, > stock | ✅ | probe | — | — |
| Warehouses | FIFO | Backdated purchase reorders layers | ⚠️ design note | probe | Low | — |
| Warehouses | Write-off | Value precision | ❌ | `StockMovement.ts:~1507` | Medium | fixed |
| Warehouses | Write-off | Duplicate ids, not expired, zero remaining | ✅ | probe | — | — |
| Warehouses | Write-off | Damaged stock | ⚠️ unsupported | probe | Medium | decision |
| Customer payments | Receipt | Zero/negative, over-allocation, other customer's invoice, sum mismatch | ✅ | probe | — | — |
| Customer payments | Receipt | Closed period | ✅ 409 | probe | — | — |
| Customer payments | Receipt | Future date / advance payment | ⚠️ accepted / ❌ unsupported | probe | Medium | — |
| Customer payments | Receipt | Delete after cash spent | ❌ cash negative | probe | High | decision |
| Supplier payments | Payment | Zero/negative, no allocation, over-allocation | ✅ (over-allocation as 500) | probe | Low | — |
| Supplier payments | Payment | Funds guard | ✅ | probe | — | — |
| Supplier payments | Payment | After backdated purchase | ❌ header ≠ ledger | `SupplierPaymentService.ts:~63-72` | High | fixed |
| Supplier payments | Payment | Closed period | ❓ | — | — | — |
| Expenses | Expense | Zero/negative, unknown category | ✅ | probe | — | — |
| Expenses | Expense | Closed period | ✅ (Recorded transition, *code* `expenseController.ts:204`) | code | — | — |
| Expenses | Expense | Future date | ⚠️ Draft accepted | probe | Low | — |
| Production | Output | Negative overhead / self-production | ❌ | probe | Medium / Low | fixed |
| Production | Output | Delete after sale / delete unsold | ❌ | `Production.ts:~590-625` | High | fixed |
| Production | Output | Closed period | ❌ | `postLegacyStockEntry` | High | fixed |
| Production | Output | Duplicate input lines, insufficient stock | ✅ | probe | — | — |
| Payroll | Salary | Overpayment | ❌ double-posted | `employeeController.ts:~318-365` | High | decision |
| Payroll | Salary | Unfunded / amount as string / garbage date | ❌ / ✅(500, rolled back) / ✅ | probe | Medium | — |
| Payroll | Salary | Duplicate "full" month | ✅ | probe | — | — |
| Payroll | Loan | Over-repayment | ✅ 422 | probe | — | — |
| Payroll | Loan | Salary-deduction repayment | ❌ no GL | `:~785` | Medium | decision |
| Owner equity | Capital/withdrawal | Zero/negative/non-numeric, over-funds | ✅ | probe | — | — |
| Owner equity | Capital/withdrawal | Goods > stock, duplicate lines, void twice | ✅ | probe | — | — |
| Owner equity | Capital | Edit/void after spent | ❌ | probe | High | decision |
| Reports | All | Empty database | ✅ | probe | — | — |
| Reports | Aging | As-of date | ❌ | `Reports.ts:7-31, ~333-392` | Medium | — |
| Concurrency | — | Two writers | ❓ — single synchronous connection per `accountingService.ts:1035` | code | — | — |
| Currency | — | Multi-currency / UoM conversion | ❓ not audited | — | — | — |

---

## 7. Prioritized remediation plan

### Decisions only you can make

| # | Decision | Affects |
| --- | --- | --- |
| D1 | Cash-guard policy: require opening cash before any cash purchase, salary or loan? (the patch breaks 12 fixture suites that seed stock unfunded) | ACCT-005, PAY-003 |
| D2 | Reversal guard: block capital edit/void and receipt delete when later spending depends on the cash? | ACCT-013 |
| D3 | Overpayment model: split into month + advance rows posted once, linked so void removes both | PAY-001, PAY-002 |
| D4 | Salary-deduction repayments: post Dr cash / Cr 1300 like direct repayments? | PAY-004 |
| D5 | Which of the 14 unassignable permissions become grantable vs admin-only | AUTHZ-001 |
| D6 | Is production overhead also expensed when incurred? If not, credit cash/payables instead of 7000 | PROD-001 |
| D7 | Include `server/uploads/` in backups; add a damaged-stock write-off | BK, WO-002 |

### Plan

| Priority | Finding | Effort | Dependencies | Status |
| --- | --- | --- | --- | --- |
| **P0** | AUTHZ-002 admin takeover | S | — | patch `round8` |
| **P0** | ACCT-004 closed periods (+ PROD-006) | S | — | patches `ACCT-001-004`, `round5` |
| **P0** | ACCT-001 balance sheet | S | — | patch `ACCT-001-004` |
| **P0** | ACCT-003 return restock | S | — | patch `ACCT-001-004` |
| **P0** | ACCT-012 supplier balance | S | — | patch `round2` |
| **P0** | PROD-001, PROD-005 | M | D6; backfill for old productions | patch `round5` |
| **P0** | FILE-001 file deletion; BK-006 README | S | — | patch `round9` |
| **P0** | PAY-001, ACCT-013 | M | D3, D2 | tests only |
| **P1** | REP-001, REP-002 | M | — | patch `round7` |
| **P1** | AUTHZ-003, -004 | S | — | patch `round8` |
| **P1** | ACCT-002 P&L | S | **PROD-001 first** | patches `ACCT-001-004` + `round5` |
| **P1** | PO-001, PRET-001, PROD-002/-004/-007, WO-001, FILE-002, BK-001…005 | S | — | patches `round2/4/6/9` |
| **P1** | ACCT-005, PAY-003 | S | D1 | policy patch + tests |
| **P1** | PAY-002, PAY-004 | S–M | D3, D4 | tests only |
| **P1** | ACCT-006, ACCT-007 date / tax / discount bounds | M | — | no tests yet |
| **P1** | CODE-004 client idempotency keys | M | — | no tests yet |
| **P2** | ACCT-010, -011 as-of aging | M | — | no tests yet |
| **P2** | CODE-001 status-code mapping; CODE-002 refresh-token DB check; AUTHZ-001 | M | D5 | open |
| **P2** | WO-002, uploads in backups, REP-005, PRET-002 | M–L | D7 | open |
| **P3** | CODE-005…007 Flutter cleanup; run `flutter analyze` | M | — | open |

### Deployment notes

1. Apply patches **in this order**: `candidate-fixes-ACCT-001-004` → `round2` → `round4` → `round5` → `round6` → `round7` → `round8` → `round9`. Each applies cleanly on the previous (verified by stacking all nine).
2. **Backfill** historic productions with a one-time journal (Dr 7000 / Cr 1200 at each production's material cost), dated in the **current open period** (old periods may be closed). Until then GL inventory and balance-sheet profit stay overstated for old productions.
3. Re-run the repo's `npm run data:integrity` and `npm run gl:check` before and after patching and keep the output.
4. Set `BACKUP_DIR` to a different drive and test a restore with the corrected README procedure.

---

## 8. Evidence and companion files

**Verification state with all nine patches stacked**

| Check | Result |
| --- | --- |
| Existing server suite | **113 / 113 suites, 991 / 991 tests pass** |
| `auditRegression` (ACCT-001–004) | 18 / 18 |
| `auditRegression2` (supplier balance, PO, returns) | 4 / 5 (ACCT-005 red — decision D1) |
| `auditRegression3` (payroll, cash reversals) | 0 / 8 (decisions D2–D4) |
| `auditRegression4` (production) | 11 / 11 |
| `auditRegression5` (write-off) | 4 / 4 |
| `auditRegression6` (custom reports) | 13 / 13 |
| `auditRegression7` (authorization) | 10 / 10 |
| `auditRegression8` (files, backups) | 9 / 9 |

Each regression test encodes correct behaviour and was confirmed to **fail on the original code** for the intended reason (tests that passed for the wrong reason were corrected during the audit). Assertions are fix-agnostic where more than one design is valid.

**Patches** (`candidate-fixes-*.patch`) were applied only in my sandbox clone; the repository was never modified.

---

## 9. Scope and limitations

**Not audited, or only partly:**

- The **Flutter client** beyond a grep-level scan (structure, `print`, `dynamic`, idempotency call sites); `flutter analyze` and widget-level review were not done (no Dart SDK in the sandbox).
- BOM create/update code, quotations/sales orders, dashboard, forecasts, POS and mobile-invoice modules beyond route-level authorization.
- Database index coverage and N+1 queries (performance); migration correctness beyond reading `database.ts`.
- **Concurrency** (two users editing the same record) was not tested; single synchronous SQLite connection makes interleaving unlikely but unproven.
- Multi-currency and unit-of-measure conversion were not examined; tax logic only through `postInvoiceEntry` and the probes above.
- Customer/supplier **statements** were checked for invoice cancel only (not payment voids); supplier-payment closed-period case not probed.
- Routes with destructive-looking paths got only the anonymous probe; their code was read.

**Method caveats.** Probes ran against fresh temporary databases through the app's own routes; where a probe set up state with a direct database insert or a direct posting call (e.g. salary via `postSalaryEntry`, expired batches, opening cash) that is stated in the finding. Line numbers marked `~` are approximate.