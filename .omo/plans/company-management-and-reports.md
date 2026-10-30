# company-management-and-reports - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**Who this is for and what changes for them:** Gull and inventory/purchasing staff can maintain companies, see their products and suppliers, and report on company stock, sales, and purchases.

**What you'll get:** An inline Add Company section in the product form, a Manage Companies dialog beside New Item, and a Company Report with Stock, Sales, and Purchases views. Company creation requires only a name.

**Why this approach:** Stable company identities make renaming safe. Manual supplier links and purchase history are shown together while preserving their separate meaning.

**What it will NOT do:** Change loan behavior, create new accounting postings, rewrite historical transaction amounts, or add company contact fields.

**Effort:** Large
<!-- Effort is exactly ONE band, never hours/days. Quick = single edit, minutes of agent work; Short = one focused change, a few files; Medium = multi-file feature in one session; Large = several waves, one long session; XL = multi-session or architectural work. A written duration is rewritten to a band. -->
**Risk:** High — existing manufacturer names need careful migration and report totals must reconcile with existing transaction and valuation rules.
**Decisions to sanity-check:** Approved: name only, both supplier sources, delete unused companies, archive/restore assigned companies, all three report views. Reports classify transactions using the product's company assignment; no new historical company snapshot is introduced.

Your next move: review this plan, then explicitly request implementation. This file does not authorize product-code changes.

---

> TL;DR (machine): Large; high migration/reporting risk; 7 implementation tasks and 4 final verification tasks; implemented and verified, 2026-10-30. Evidence: `.omo/evidence/company-management/final-review.md`.

## Scope
### Affected user and ideal state
<!-- From the draft ledger: who this touches and how they use the result, then one IS row per property with its reason, then one GAP row per difference with its reason. Every todo below closes a GAP row; ## Success criteria proves every IS row. -->
**Affected user:** Gull and staff maintaining products and suppliers and using inventory reports. Today the initial company implementation only supports listing/adding names and a popup; afterwards company maintenance, supplier relationships, and reporting share one stable company identity.

| Row | Statement | Reason |
| --- | --- | --- |
| IS-1 | Add a company inline without losing product edits; newly saved name is selected | Fast product entry |
| IS-2 | Search, rename, delete unused, archive used, and restore companies in one dialog | Safe ongoing maintenance |
| IS-3 | Inspect products and supplier details; distinguish manual links from actual purchase history | Useful supplier discovery |
| IS-4 | Company Report provides current stock/value and period sales/purchases including returns | Reliable company performance reporting |
| IS-5 | Renames, archived companies, permissions, and migration preserve valid existing data | No broken references or misleading totals |
| GAP-1 | Popup add and name-only product storage need inline UI and stable identity | Tasks 1, 4 |
| GAP-2 | Company edit/delete/archive/restore management is absent | Tasks 1, 2, 5 |
| GAP-3 | Manual supplier links and combined history view are absent | Tasks 1, 3, 5 |
| GAP-4 | Company-specific Stock/Sales/Purchases report is absent | Tasks 6, 7 |
| GAP-5 | Initial implementation has only static-check evidence; migration, lifecycle, and reports need behavioral coverage | All tasks and final verification |

### Must have
- User-approved scope from this conversation: name-only company creation; inline + patterned after New Loan borrower; Manage Companies beside New Item on Inventory Items; company list/add/edit/remove, used-company archive and restore; products and suppliers in company details; manual supplier links plus purchase history; Company Report with all three views; archived companies available in historical reports.
- Company details use Products and Suppliers tabs. Suppliers appear once per supplier with Linked supplier and/or Purchased from badges, contact details, product details, last purchase date, and existing detail navigation. Unlinking removes only the manual association.
- Current Stock explicitly ignores the date range. Sales/Purchases use inclusive business dates and show gross quantities/value, returns, and net totals. Quantities are grouped by UOM rather than summed across incompatible units.
- Follow existing permissions, desktop dialogs, repository/ApiResult, Riverpod, report navigation, localization, pagination and error conventions. No new dependencies.
- Preserve in-progress form values on inline cancel/failure. Save immediately persists the company; cancelling the outer product form does not delete it.
- Keep earlier company work; inspect the working tree before execution and adapt it rather than overwriting unrelated changes.
### Must NOT have (guardrails, anti-slop, scope boundaries)
- No company phone/address/notes fields; no borrower/loan behavior changes.
- No deletion of referenced companies, supplier history, products, stock, or transactions; no automatic clearing of archived company assignments.
- No changes to accounting, FIFO/FEFO, reversal logic, or valid integrity checks. Do not repair known dummy historical accounting gaps.
- No historical stock-as-of report, profit report, supplier pricing catalogue, new export system, or company snapshot backfill.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: TDD with Jest/Supertest and Flutter widget tests, following project instructions: reproduce each missing behavior before implementing it. Use clean temporary databases and exact decimal expectations.
- Evidence: `.omo/evidence/company-management/`; each task specifies its exact artifact basename. If execution uses a durable loop, place these artifacts beneath that loop's current attempt directory and record the resolved paths.

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.
Dependency-driven waves: A = task 1; B = tasks 2, 3, 6 (separate owned modules); C = task 4; D = tasks 5 and 7; E = F1–F4. Shared files must have one owner or be edited sequentially. Wave size follows schema/API prerequisites rather than artificial task splitting.

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1 | None | 2, 3, 4, 6 | None |
| 2 | 1 | 4, 5 | 3, 6 with separate modules |
| 3 | 1, company API contract from 2 | 5 | 6 |
| 4 | 1, 2 | 5, 7 | 3, 6 |
| 5 | 2, 3, 4 | Final verification | 7 |
| 6 | 1 | 7 | 2, 3, 4 |
| 7 | 4, 6 | Final verification | 5 |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [x] 1. Establish stable company identity and supplier-link schema
  - Recommended task executor category: unspecified-high
  - Closes: GAP-1, GAP-2, GAP-3, GAP-5. Wave A; blocks 2–4 and 6.
  - References: `server/src/config/database.ts` (`applyPendingMigrations`, existing `fn.runItemCompaniesMigration`); `server/src/models/Item.ts`; `server/src/migrations/`; `docs/DATABASE.md`; `CODING_STANDARDS.md`; `server/STRICT_NULL_CHECKS.md`.
  - Add a NEW registered SQL migration; never modify an already-applied migration/checksum. Extend `item_companies` with active/archive status, add nullable indexed `items.company_id` FK, and create `item_company_suppliers(company_id, supplier_id)` with unique pair and valid FKs. Company names trim whitespace, reject blanks/over 200 characters, and use the existing case-insensitive uniqueness policy.
  - First repair the preliminary runner order: `fn.runItemCompaniesMigration` currently runs near `database.ts:1944`, but reads `manufacturer_name`, introduced only by `122_item_manufacturer_batch_sources.sql` near line 2251. Relocate that existing runner after migration 122, preserving its ledger identity/body, then register the NEW company management migration after it. Verify both fresh boot and upgrade where the preliminary runner is already recorded; do not change migration 122.
  - Backfill distinct nonempty manufacturer names and company IDs, preserving product IDs, amounts, and raw legacy display values. Blank manufacturer remains unassigned. Confirm the deployed initial company schema before choosing the next migration filename. Re-running migrations must be harmless.
  - Make ID authoritative for assigned companies; item read DTOs expose company ID and canonical display name while keeping `manufacturer_name` compatible. Legacy create/update bodies containing only manufacturer_name resolve/upsert a canonical active company transactionally. Explicit company_id validates existence/status. Unrelated edits to products already assigned an archived company are allowed; new assignment to archived companies is rejected.
  - Acceptance: fresh and populated DB migration, duplicate casing/whitespace, rename, missing/invalid company ID, existing archived assignment, and repeated boot fixtures pass without changing stock/GL.
  - QA: `cd server && npm test -- --runInBand companyManagement` (new `src/__tests__/companyManagement.test.ts`); include migration preservation assertions and a forced failure proving transactional rollback. Evidence: `.omo/evidence/company-management/task-1-migration.txt`.
  - Commit: N; keep task changes reviewable without committing until requested.

- [x] 2. Implement company list, rename, delete, archive and restore APIs
  - Recommended task executor category: unspecified-high
  - Closes: GAP-2, GAP-5. Wave B; depends on 1; blocks 4–5.
  - References: `server/src/models/Item.ts` (`getCompanies`, `addCompany`); `server/src/controllers/inventoryController.ts`; `server/src/routes/inventory.ts`; `server/src/middleware/validation.ts`; `audit/DECISIONS.md`; `docs/API.md`.
  - Extract company persistence into `server/src/models/ItemCompany.ts` and handlers into `server/src/controllers/itemCompanyController.ts`; register on the existing inventory router. Evolve `/inventory/item-companies` deliberately with typed DTOs `{id, company_name, is_active, product_count}`; update its existing client consumers together. Add ID-based detail, update, DELETE, archive, restore, and paged products endpoints.
  - List supports search, page/limit, and active/archived/all status. Quick selection defaults active; management can show archived. Detail includes inactive/deleted products so deletion eligibility cannot miss references.
  - DELETE succeeds only if no product references the company, including inactive/soft-deleted products. Referenced DELETE returns 409 with archive guidance. Perform reference check and mutation in one transaction. Manual links of an unused deleted company can be removed with that company; never remove suppliers themselves. Rename conflicts return a safe 409; restore also respects uniqueness.
  - Creation resolves equivalent names to the canonical persisted ID/name, including conflict/concurrent-create cases; never return only an ignored input spelling. Reject duplicate renames to a different company.
  - Use inventory read/create/update/delete permissions matching each operation, shared Zod request validation, prepared statements, bounded pagination, sanitized errors and existing activity logging. Record approved business decisions in `audit/DECISIONS.md` when implementation starts.
  - QA: `cd server && npm test -- --runInBand companyManagement` drives the mounted router with real authenticated POST/PUT/DELETE bodies: create→rename→archive→restore; unused-delete; referenced-delete conflict; duplicate/invalid/unauthorized/missing record cases. Evidence: `.omo/evidence/company-management/task-2-api.txt`.
  - Commit: N.

- [x] 3. Implement manual supplier links and purchase-derived supplier history
  - Recommended task executor category: unspecified-high
  - Closes: GAP-3, GAP-5. Wave B; depends on 1 and contract from 2; blocks 5.
  - References: `server/src/models/Supplier.ts`, `Purchase.ts`, `PurchaseOrder.ts`, `PurchaseReturn.ts`; `server/src/utils/batchSuppliers.ts`; `server/src/__tests__/supplierPurchasesFilter.test.ts`.
  - Add company supplier list and idempotent link/unlink endpoints under `/inventory/item-companies/:id/suppliers`. Use inventory update for changes; enforce supplier-read permission before returning supplier details. Reject missing/inactive suppliers for new links; retain readable historical associations.
  - Derive Purchased from using valid posted purchasing records associated with company products, including direct purchases and received PO products according to existing posting rules. Never infer history only from remaining batches. Exclude cancelled/voided/unreceived commitments; deduplicate source documents and suppliers. Fully returned valid purchases still prove historical dealings.
  - Union manual and historical suppliers into one row per supplier with independent flags, contact fields, product count, last valid purchase date and paged product detail. Unlink changes only the manual flag. Query must work for archived companies and sold-out products.
  - QA: `cd server && npm test -- --runInBand companySuppliers` (new `companySuppliers.test.ts`): manual-only, history-only, both→unlink, repeated link, sold-out, direct/receipt provenance, cancelled PO, returned purchase, duplicate receipt joins, and unauthorized access. Evidence: `.omo/evidence/company-management/task-3-suppliers.txt`.
  - Commit: N.

- [x] 4. Add typed Flutter company contracts and inline product creation
  - Recommended task executor category: unspecified-high
  - Closes: GAP-1, GAP-5. Wave C; depends on 1–2; blocks 5 and 7.
  - References: `lib/data/models/item.dart`; `lib/core/api/endpoints.dart`; `lib/data/repositories/inventory_repository.dart`; `lib/features/inventory/inventory_providers.dart`; `item_form_dialog.dart`; `lib/features/owner_equity/personal_loan_create_dialog.dart:448`; `test/features/item_company_batch_supplier_test.dart`.
  - Add typed company/lifecycle DTOs and repository methods/providers; product JSON includes company_id while preserving existing manufacturerName readers. Update existing initial companies() callers/fakes in the same task.
  - Replace `_addCompany` popup with expandable name-only inline section using the borrower pattern. Keep product values and previous company selection on cancel; save selects the persisted canonical company. Disable duplicate submission, show field/server errors inline, retain entered name on failure, and prevent Enter in this section from submitting the product.
  - Invalidate company lists/detail/products and item lists/detail as relevant after mutations. Preserve an archived current company as a labelled edit selection without offering it to new products. Company dropdown has loading/error/retry and empty states.
  - QA: `flutter test test/features/item_company_batch_supplier_test.dart` plus new `test/features/company_inline_add_test.dart`: tap +, save name, see selection, cancel, failed/duplicate save, product-submit isolation, archived edit and provider refresh. Evidence: `.omo/evidence/company-management/task-4-inline.txt` and screenshots.
  - Commit: N.

- [x] 5. Build Manage Companies and company product/supplier detail dialog
  - Recommended task executor category: unspecified-high
  - Closes: GAP-2, GAP-3, GAP-5. Wave D; depends on 2–4.
  - References: `lib/features/inventory/items_screen.dart:370`; `lib/features/owner_equity/personal_loan_borrower_list_dialog.dart`; `personal_loan_borrower_form_dialog.dart`; `lib/widgets/movable_dialog.dart`; existing supplier detail navigation in supplier features.
  - Add localized Manage Companies beside New Item in the Items toolbar. Build `lib/features/inventory/manage_companies_dialog.dart` with search, paging, active/archived filtering, name-only add/edit, delete/archive confirmation, restore, and product count. Backend remains authoritative for delete eligibility and permission errors.
  - Selected company opens Products/Suppliers detail tabs. Product rows open existing product detail; supplier rows show badges/contact/products/last purchase and open existing supplier detail. Manual links use searchable supplier selection and explicit unlink. Retain selected company through refresh and close detail safely after deletion.
  - Respect permissions in controls, prevent duplicate mutations, show loading/error/empty states, and keep long names and Urdu labels usable. Use existing theme, focus/keyboard and movable dialog conventions.
  - QA: `flutter test test/features/manage_companies_dialog_test.dart` (new): mounted Items screen launch; create/edit/delete conflict/archive/restore; product/supplier navigation; link/unlink with Purchased from preserved; denied mutation; retry; long names. Real desktop or browser run captures both themes at supported desktop width and a narrow layout. Evidence: `.omo/evidence/company-management/task-5-dialog.*`.
  - Commit: N.

- [x] 6. Implement reconciled company stock, sales and purchase report APIs
  - Recommended task executor category: unspecified-high
  - Closes: GAP-4, GAP-5. Wave B; depends on 1; blocks 7.
  - References: `server/src/models/Reports.ts:804` (`getInventoryValuation`); `Invoice.ts`, `InvoiceReturn.ts`, `Purchase.ts`, `PurchaseReturn.ts`; `server/src/routes/reports.ts`; `server/src/controllers/reportsController.ts`; `server/src/__tests__/inventoryValuation.test.ts`, `reportingCoverage.test.ts`; `docs/REVERSAL-RULES.md`.
  - Add focused `server/src/models/CompanyReport.ts` and company report handlers. Register `/reports/company/stock`, `/reports/company/sales`, `/reports/company/purchases`; require reports-read plus inventory/invoices/purchases read for the corresponding view, following existing entity permission conventions. Validate company_id, dates, pagination and sorting; archived company IDs are valid.
  - Stock returns current product quantities/UOM, stock value and totals with explicit current-as-of timestamp. Reuse existing valuation calculation/stock-batch source of truth, including existing special stock buckets and feature-flag behavior; do not silently use standard cost or treat reserved stock as additive physical stock.
  - Sales/Purchases aggregate valid posted item lines once. Reuse existing source-of-truth statuses, amount/discount/tax allocation and currency rounding rules. Count a sale invoice once even where multiple entry paths exist; count a received purchase once even with PO/receipt joins. Return quantities and values are separate columns and reduce net totals. Use return transaction date for return period attribution, including returns whose original document predates the period. Exclude void/cancelled documents and voided returns.
  - Return paged product summaries plus transaction drilldown links and full-filter totals computed before pagination. Products may have several suppliers; do not multiply report totals by supplier links. Use product's assigned company, including inactive products; filter by stable IDs so renames do not detach history. No history snapshots or transaction rewriting.
  - QA: `cd server && npm test -- --runInBand companyReport inventoryValuation reportingCoverage` (new `companyReport.test.ts`): exact multi-company totals, multiple suppliers/receipts, document discounts, partial/full returns, cross-period returns, date boundaries, voids, mixed UOM, sold-out stock, archived/renamed company, empty period, pagination totals and denied access. Record fixture arithmetic and reconciliation with existing reports. Evidence: `.omo/evidence/company-management/task-6-reports.txt`.
  - Include a mixed-company document with a document-level discount and several returned lines; aggregate source lines and returns independently before combining. Assert that neither supplier joins nor return joins multiply totals.
  - Commit: N.

- [x] 7. Integrate Company Report UI, localization, documentation and regression checks
  - Recommended task executor category: unspecified-high
  - Closes: GAP-4, GAP-5. Wave D; depends on 4 and 6.
  - References: `lib/features/reports/reports_dashboard_screen.dart`; `reports_routes.dart:45`; `report_providers.dart`; `inventory_valuation_report.dart`; `lib/data/repositories/report_repository.dart`; `lib/l10n/en.arb`, `ur.arb`; `test/features/accounting_report_regressions_test.dart`; `docs/API.md`, `docs/DATABASE.md`, `scripts/check.sh`.
  - Add report card and `company` route, typed report DTOs/repository/providers, and `company_report_screen.dart`. Include company selector with archived labels, Stock/Sales/Purchases tabs, date range for period views, UOM-aware totals, paging, refresh and existing detail navigation. Stock prominently says Current stock and does not suggest that changing period changes stock valuation.
  - Key requests/cache by company/view/date/page; changing filters resets page and cannot display stale prior-company totals. Preserve selected archived company. Handle loading/error/retry/empty and permissions consistently with other reports.
  - Localize all additions in English/Urdu and regenerate localization output using project tooling. Document companies/lifecycle/manual links/report DTOs, permissions, current-stock and period-return semantics. Update audit decisions with the accepted scope; no fabricated completion claims.
  - QA: `flutter test test/features/company_report_test.dart` (new) plus `test/features/accounting_report_regressions_test.dart`: card→route, all three views, date/selection/paging changes, stale response, archived company, totals and drilldowns; real UI captures Stock and both date-filtered tabs with matching fixture values. Run `node scripts/l10n-drift.js`, then `scripts/check.sh --quick`.
  - At task completion run `scripts/check.sh` because both sides and shared API contracts change. Investigate focused failures first; preserve valid tests. Run applicable accounting invariants A–J per repository guidance for valuation/report consumers; isolate legacy dummy gaps with clean fixtures. Evidence: `.omo/evidence/company-management/task-7-ui.*` and `final-checks.txt` with commands, exit codes and full-suite counts.
  - Commit: N.

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [x] F1. Plan compliance audit
- [x] F2. Code quality review
- [x] F3. Real manual QA
- [x] F4. Ideal-state fidelity
  - F1: Verify every accepted scope item and all seven task acceptance criteria against changes and evidence; report missing behavior explicitly.
  - F2: Review migration safety, prepared SQL, permission checks, canonical identity, archived references, duplicate joins, rounding and maintainability. No new reviewer panel is required; one gate reviewer can audit collected evidence.
  - F3: Agent drives the real UI: inline add→save product→manage rename→supplier link/unlink→archive/restore→all three reports. Capture visible state plus matching API/fixture totals. Screenshots alone do not prove calculated totals.
  - F4: Check every IS row against the success matrix; any gap becomes a concrete follow-up task. Record all verdicts in `.omo/evidence/company-management/final-review.md`. Do not call implementation complete until required checks and real flows pass.

## Commit strategy
No commits, deployment, PR or implementation are authorized by this planning request. During later execution retain unrelated user work; if commits are requested, group schema/API, Flutter management, and reports into coherent verified commits following the git skill.

## Success criteria
> One row per IS row. The plan is complete only when every IS row has a delivering todo and a proving QA scenario; F4 checks the delivered behavior against these rows 1:1, and a shortfall becomes new `- [ ] N.` rows, never a note.
| IS | Delivering todo(s) | Proving QA scenario | Evidence |
| --- | --- | --- | --- |
| IS-1 | 1, 4 | Inline add save/cancel/failure and outer-submit isolation | task-4-inline.txt + captures |
| IS-2 | 1, 2, 5 | Rename, unused-delete, referenced-delete conflict, archive/restore | task-2-api.txt; task-5-dialog.* |
| IS-3 | 3, 5 | Both source flags, sold-out history, unlink preserves history, detail navigation | task-3-suppliers.txt; task-5-dialog.* |
| IS-4 | 6, 7 | Exact company totals including cross-period returns and current stock | task-6-reports.txt; task-7-ui.* |
| IS-5 | All | Migration preserves existing products/stock; permission/archived/duplicate regressions; full checks | task-1-migration.txt; final-checks.txt; final-review.md |
