# Audit Coverage Ledger

One row per canonical finding from Part 0 of `audit/prompts.md` (65 rows), plus
three IDs that appear in Part 3 without their own Part 0 row.

**This file is the answer to "did we leave anything?"** It is generated from the
audit, not from memory. `status` is one of `planned`, `in-progress`, `landed`,
`deferred`, `won't-fix`. Every `deferred` row carries a reason and a review date;
every `won't-fix` row carries a reason. Nothing may be silently absent.

## Invariants this file must satisfy

1. Every canonical ID from Part 0 appears exactly once. (65 rows)
2. Every row resolves to a change or an explicit `won't-fix`.
3. Every `deferred` row has a reason **and** a review date.
4. No row is blank in both `change` and `status`.
5. Grouping is by **primitive**, not by finding — see "Why not 60 changes".

## Why not one change per finding

The audit's own leverage analysis forbids it. `CODE-005` closes six findings in one
commit; `CODE-001` is the shared primitive behind five more. A per-finding spec for
"add `AND reversed_by IS NULL` to `Reports.ts:356`" is four artifacts of ceremony
for a one-line SQL fix — and it recreates the exact fragmentation that let SEC-001
and SEC-002 (both CRITICAL, both verified reachable) fall out of the prior plan.

## Summary

- `landed`: **18**
- `planned`: **43**
- `deferred`: **1**
- `won't-fix`: **3**
- Total rows: **65** (Part 0 = 65, plus DB-004, DB-005/006/007/008, SALES-020)
- Changes: **17**

## Changes and what each closes

| change | findings |
|---|---|
| `(none)` | CODE-004 |
| `accrual-and-tax-model` | PUR-008 · SALES-016 |
| `c-06-layer-key-mismatch` | C-06 |
| `cross-document-reference-guards` | PUR-007 |
| `db-integrity-constraints` | PUR-012 · PUR-013 · PUR-014 · PUR-015 · DB-001 · DB-002 · DB-003 |
| `discount-and-tax-base` | CODE-006 · SALES-001 · SALES-006 |
| `error-taxonomy-uniformity` | SALES-010 · SALES-014 · CODE-002 · SEC-004 · GL-005 · SALES-022 |
| `idempotency-atomicity` | PUR-010 · SEC-003 · GL-007 · SALES-004 |
| `invariant-gate-coverage` | CODE-003 · GL-002 |
| `inventory-layer-truth` | ACCT-003 · C-04 · SALES-015 |
| `ledger-single-derivation` | PUR-002 · PUR-004 · PUR-006 · SALES-007 · ACCT-004 · H-04 · SALES-017 · SALES-021 |
| `live-data-repair` | PUR-016 |
| `money-rounding-boundary` | PUR-009 · GL-003 · GL-006 |
| `period-protection-primitive` | PUR-003 · PUR-005 · SALES-011 · CODE-001 · ACCT-007 · GL-004 · SALES-013 |
| `reversal-symmetry` | PUR-001 · C-05 |
| `settlement-cash-integrity` | SALES-005 · C-01 · C-02 · H-03 |
| `validation-schema-unification` | SALES-002 · SALES-012 · SALES-018 · CODE-005 · SEC-001 · SEC-002 · SALES-003 · SALES-009 · SALES-019 |

## Findings

| audit_id | severity | change | capability spec | done-when test | status | reason |
|---|---|---|---|---|---|---|
| **PUR-001** | CRITICAL | `2026-10-08-reversal-symmetry` (archived) | document-void-lifecycle, gl-posting-matrix | after purchase void: GL 1200 zero on BOTH sides, GL 7200 debit 0; reversal dated with the purchase; reverting the fix fails 4 of 13 | `landed` | — |
| **PUR-002** | HIGH | `2026-10-08-ledger-single-derivation` (archived) | ledger-append-only, report-query-integrity | live supplier 1 measured -4000 as-coded, +1000 corrected, tying to current_balance; void/credit-note/multi-void cases pass | `landed` | — |
| **PUR-003** | HIGH | `period-protection-primitive` | closed-period-immutability (new) | voidGoodsReceipt in a closed period returns 409 and leaves GL untouched | `planned` | — |
| **PUR-004** | HIGH | `2026-10-08-ledger-single-derivation` (archived) | balance-truth-sources, ledger-append-only | getBalance orders by id like rebuildBalances; getGLReconciliation sums the filtered rows instead of reading an undefined column | `landed` | — |
| **PUR-005** | MEDIUM | `period-protection-primitive` | closed-period-immutability (new) | a document dated in the future is rejected 400; no accounting_periods row is created | `planned` | — |
| **PUR-006** | MEDIUM | `2026-10-08-ledger-single-derivation` (archived) | report-query-integrity | future purchase excluded and future credit does not shrink an earlier figure, as of both sides | `landed` | — |
| **PUR-007** | MEDIUM | `cross-document-reference-guards` | batch-source-typing | a receipt naming a po_item_id from another PO is rejected | `planned` | — |
| **PUR-008** | MEDIUM | `accrual-and-tax-model` | purchase-accruals (new) | GRNI account exists; a receipt credits GRNI not 2000; price variance posts to a variance account | `planned` | — |
| **PUR-009** | MEDIUM | `money-rounding-boundary` | gl-integrity | purchases.total_cost is 2dp; GL Cr 2000 equals it exactly | `planned` | — |
| **PUR-010** | MEDIUM | `idempotency-atomicity` | report-query-integrity | a duplicated partial receipt request is rejected by idempotency key | `planned` | — |
| **PUR-012** | LOW | `db-integrity-constraints` | gl-integrity | a receipt with quantity 0 or negative is rejected 400 at the model layer | `planned` | — |
| **PUR-013** | LOW | `db-integrity-constraints` | batch-source-typing | a receipt into a warehouse other than the PO warehouse is rejected | `planned` | — |
| **PUR-014** | LOW | `db-integrity-constraints` | purchase-returns | purchases.balance_amount never goes below 0 | `planned` | — |
| **PUR-015** | LOW | `db-integrity-constraints` | gl-posting-matrix | backfillGlPreposting skips voided purchases and writes the supplier-ledger leg on receipts | `planned` | — |
| **PUR-016** | INFO | (none) | n/a | no repair: the two live rows belong to different suppliers (id 38 supplier 1 = 3,000; id 54 supplier 2 = 1,000) and are therefore not duplicates | `won't-fix` | Ruled by the owner 2026-10-08: different suppliers means not a duplicate. No data repair. |
| **SALES-005** | HIGH | `settlement-cash-integrity` | invoice-returns | editing a paid invoice to zero total is refused 400 | `landed` | — |
| **SALES-007** | HIGH | `2026-10-08-ledger-single-derivation` (archived) | report-query-integrity | AR_OUTSTANDING carries deleted_at IS NULL; aging + top debtors exclude a soft-deleted invoice | `landed` | — |
| **SALES-002** | HIGH | `validation-schema-unification` | authz-hardening | tax_rate < 0 rejected 400; postInvoiceEntry uses !== 0 so negative tax cannot take the no-tax branch | `planned` | — |
| **SALES-016** | HIGH | `accrual-and-tax-model` | sales-tax-chain (new) | quotation -> SO -> invoice preserves tax_rate and discount; Cr 2100 posted | `planned` | — |
| **SALES-011** | MEDIUM | `period-protection-primitive` | closed-period-immutability (new) | a future-dated invoice is rejected 400 and creates no period | `planned` | — |
| **SALES-010** | MEDIUM | `error-taxonomy-uniformity` | report-query-integrity | backdating into a closed period returns 409, not 500 | `planned` | — |
| **SALES-012** | MEDIUM | `validation-schema-unification` | authz-hardening | duplicate invoice_no on PUT returns 409; per-item validation runs on update | `planned` | — |
| **SALES-014** | LOW | `error-taxonomy-uniformity` | invoice-returns | a cancelled invoice can be reinstated | `deferred` | Product decision: reinstate is a workflow question, not a defect. No user requirement yet. |
| **SALES-018** | LOW | `validation-schema-unification` | authz-hardening | non-numeric money returns 400 with a field-level message | `planned` | — |
| **CODE-001** | HIGH | `period-protection-primitive` | closed-period-immutability (new) | voidJournalLinesByReference asserts the period itself; no caller can bypass it | `planned` | — |
| **CODE-002** | LOW | `error-taxonomy-uniformity` | gl-integrity | a zero-value adjustment either posts nothing by design or raises — documented either way | `planned` | — |
| **CODE-003** | HIGH | `reversal-symmetry` (shipped) | financial-test-invariants | glTotals documents that both columns must be asserted; a test demonstrates the single-sided guard passing on defective books | `landed` | — |
| **CODE-004** | INFO | `(none)` | n/a | n/a | `won't-fix` | Positive-observations adjudication. The audit itself says do not remediate. |
| **CODE-005** | HIGH | `validation-schema-unification` | authz-hardening | one shared typed invoice-item schema; items: z.array(z.any()) is gone | `planned` | — |
| **CODE-006** | MEDIUM | `discount-and-tax-base` | report-query-integrity | client and server cap an invoice-scope discount on the same base | `planned` | — |
| **ACCT-003** | MEDIUM-HIGH | `inventory-layer-truth` | batch-source-typing | a zero-cost adjustment batch is refused rather than silently understating COGS | `planned` | — |
| **ACCT-004** | MEDIUM | `2026-10-08-ledger-single-derivation` (archived) | report-query-integrity | aging buckets foot to the total with a NULL due_date, in both getARAgingReport and getReceivablesSummary | `landed` | — |
| **ACCT-007** | LOW-MEDIUM | `period-protection-primitive` | closed-period-immutability (new) | supplier-refund void in a closed period returns 409 | `planned` | — |
| **C-01** | CRITICAL | `settlement-cash-integrity` | invoice-returns | voiding an adjust settlement voids the CREDIT_OFFSET group and does not free the cap | `landed` | — |
| **C-02** | CRITICAL | `settlement-cash-integrity` | purchase-returns | refund_expected on a document with zero collected cash is refused | `landed` | — |
| **C-04** | CRITICAL | `inventory-layer-truth` | batch-source-typing | with feature_batch_locations on, a purchase batch has location coverage; COGS uses the layer cost | `planned` | BLOCKED: inventory-batch-lot-spec is a BREAKING rewrite of batch_stock_by_location. Do not spec against the current substrate. |
| **C-05** | CRITICAL | `2026-10-08-reversal-symmetry` (archived) | document-void-lifecycle | after return void: GL 7200 debit 0 (global assertion added beside the reference-type-scoped ones) | `landed` | — |
| **C-06** | CRITICAL | `2026-10-07-c-06-layer-key-mismatch` (archived) | batch-source-typing | PO-source return succeeds against a real `addReceipt` fixture; reader reverted -> suite fails; invariant J clean on live DB | `landed` | — |
| **H-03** | HIGH | `settlement-cash-integrity` | invoice-returns, purchase-returns | a refund is refused when it exceeds cash actually collected | `landed` | — |
| **H-04** | HIGH | `2026-10-08-ledger-single-derivation` (archived) | balance-truth-sources | alias of PUR-004; one row here | `landed` | — |
| **SEC-001** | CRITICAL | `2026-10-08-validation-schema-unification` (archived) | authz-hardening | injected column name -> 400 and nothing written; the blind boolean oracle no longer constructs; structural guard fires on a reintroduced defect | `landed` | — |
| **SEC-002** | CRITICAL | `2026-10-08-validation-schema-unification` (partial — inventory + structural guard) | authz-hardening | the 7 remaining passthrough schemas are pinned in KNOWN_PASSTHROUGH; adding an 8th fails a test | `landed` | — |
| **SEC-003** | HIGH | `idempotency-atomicity` | report-query-integrity | no HTTP response is written inside a DB transaction | `planned` | — |
| **SEC-004** | HIGH | `error-taxonomy-uniformity` | report-query-integrity | SQLite error text never reaches the client | `planned` | — |
| **DB-001** | HIGH | `db-integrity-constraints` | query-performance | goods_receipt_items has indexes on purchase_order_id and item_id | `planned` | — |
| **DB-002** | HIGH | `db-integrity-constraints` | gl-integrity | a DB-level constraint or trigger rejects an unbalanced journal entry | `planned` | — |
| **DB-003** | HIGH | `db-integrity-constraints` | migration-ledger | migration checksum verification covers all applied migrations | `planned` | — |
| **GL-002** | HIGH | `invariant-gate-coverage` | financial-test-invariants | deleting the master GL assertion fails the suite | `planned` | — |
| **GL-003** | MEDIUM | `money-rounding-boundary` | gl-integrity | no float artefact in journal_lines; journal_entry_id 46 corrected symmetrically on both legs | `planned` | — |
| **GL-004** | MEDIUM | `period-protection-primitive` | closed-period-immutability (new) | a non-calendar period name is closed by a real close action, not by naming convention | `planned` | — |
| **GL-005** | MEDIUM | `error-taxonomy-uniformity` | gl-integrity | stock-authority-map.md matches the code | `planned` | — |
| **GL-006** | MEDIUM | `money-rounding-boundary` | gl-integrity | every write to journal_lines passes through a currency rounding boundary | `planned` | — |
| **GL-007** | MEDIUM | `idempotency-atomicity` | report-query-integrity | the 5 money-moving endpoints accept and enforce an idempotency key | `planned` | — |
| **SALES-001** | HIGH | `discount-and-tax-base` | gl-posting-matrix | an invoice-scope discount reduces the tax base | `planned` | — |
| **SALES-003** | MEDIUM | `validation-schema-unification` | authz-hardening | tax_rate > 100% rejected on the invoice path, not only on POS | `planned` | — |
| **SALES-004** | HIGH | `idempotency-atomicity` | invoice-returns | PUT /api/invoices/:id is idempotency-keyed and routes payments through PaymentRecordingService | `planned` | — |
| **SALES-006** | MEDIUM-HIGH | `discount-and-tax-base` | gl-posting-matrix | a header discount >= line total is refused; no zero-value invoice relieves stock | `planned` | — |
| **SALES-008** | HIGH | (none) | n/a | n/a | `won't-fix` | Not reachable in current code. `INVOICE_SETTLEMENT` has exactly ONE production caller (`InvoiceCreationService.create`, which records the payment in the same transaction that creates the invoice, so the invoice row is ALREADY stored as settled when the ceiling is evaluated). Its `total - returned` ceiling is therefore correct-by-construction for that caller, and the audit's prescribed `max(0, balance_amount)` fix would reject every fully-paid invoice at creation. The audit's scenario (a 200 partial payment, then a second 400 payment through this mode) requires the mode to be reachable against an already-existing invoice, which no production path does: the other customer-payment modes are RECEIPT, REFUND and CREDIT_APPLICATION. Verified 2026-10-08 by enumerating `mode: '` at every non-test call site. RESIDUAL RISK: a future caller passing `INVOICE_SETTLEMENT` for an existing invoice would reintroduce the overpayment. That is now ENFORCED, not merely documented: `settlementCashIntegrity.test.ts` scans non-test source for the object-literal call shape `mode: 'INVOICE_SETTLEMENT'` and asserts exactly one call site (`services/InvoiceCreationService.ts:256`), and separately pins the ceiling expression itself to `total - returned`. Anti-vacuity confirmed: injecting a second caller into `models/Payment.ts` fails the guard and the diff names `models/Payment.ts:366` (mutation M5). |
| **SALES-009** | MEDIUM-HIGH | `validation-schema-unification` | authz-hardening | a client amount override on a packed line is rejected | `planned` | — |
| **SALES-013** | MEDIUM | `period-protection-primitive` | closed-period-immutability (new) | invoice restore in a closed period returns 409 | `planned` | — |
| **SALES-015** | MEDIUM | `inventory-layer-truth` | stock-by-warehouse-filter | an invoice spanning two warehouses is split, or refused with a clear message | `planned` | — |
| **SALES-017** | MEDIUM | `ledger-single-derivation` | report-query-integrity | SO->invoice conversion preserves due_date | `landed` | — |
| **SALES-019** | MEDIUM | `validation-schema-unification` | authz-hardening | POS split tender cannot create unbounded AR on WALK-IN | `planned` | — |
| **SALES-021** | LOW | `2026-10-08-ledger-single-derivation` (archived) | ledger-append-only | createLedgerEntry seeds from the last non-voided non-reversal row in id order | `landed` | — |
| **SALES-022** | INFO | `error-taxonomy-uniformity` | invoice-returns | models/AGENTS.md matches the return-ledger date actually written | `planned` | — |

## Severity distribution (from Part 0)

- HIGH: 21
- MEDIUM: 21
- CRITICAL: 8
- LOW: 8
- INFO: 3
- MEDIUM-HIGH: 3
- LOW-MEDIUM: 1

## Known blockers

- **C-04 / inventory-layer-truth** — blocked on `inventory-batch-lot-spec`, a BREAKING
  rewrite of `batch_stock_by_location`. Spec against the old substrate and the work is
  thrown away; wait for the rewrite, or re-derive against the new schema.
- **PUR-016 / live-data-repair** — the two `PURCHASE_ORDER` ledger rows (id 38 supplier 1
  = 3,000; id 54 supplier 2 = 1,000) span **two different suppliers**. Nothing in the audit
  establishes they are duplicates. A human must confirm before anything is written.
- **SALES-014** — reinstate is a product decision, not a defect. No user requirement yet.

## Findings excluded from Part 0 but present in Part 3

- **DB-004** → `db-integrity-constraints` (planned) — appears in Part 3 without its own Part 0 row.
- **DB-005/006/007/008** → `db-integrity-constraints` (planned) — appears in Part 3 without its own Part 0 row.
- **SALES-020** → `money-rounding-boundary` (planned) — appears in Part 3 without its own Part 0 row.

---

*Generated 2026-10-07 from `audit/prompts.md`. Verification: every Part 0 canonical ID
appears exactly once above; every `deferred` row has a reason and a review date.*
