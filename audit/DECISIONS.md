# MiniERP: Finalized Seven Decisions

## D13 — Remaining audit implementation (2026-10-18)

- ACCT-006: the user chose to keep current costing and show a clear warning for backdated sales. Full as-of stock allocation is not selected.
- ACCT-008: the user chose to preserve keyless invoice API compatibility and complete migration telemetry, including the deprecated mobile submit endpoint. Mandatory retry keys remain deferred until external consumers can migrate.
- ACCT-009: the user chose to implement accrual expenses, supplier bills, input tax and advances in this audit pass. Reuse existing accounting and advance-payment flows where present.
- PAY-002: the user chose parent-only voiding. A salary-payment void reverses both linked records; a direct child-advance void remains blocked.
- PRET-002: the user delegated the choice. A refund expected from a supplier remains an outstanding credit until an explicit refund receipt is recorded. Expected money must not increase cash.
- CODE-003 security implementation: new passwords require at least 12 Unicode characters and at most 72 UTF-8 bytes (bcrypt's input limit), with no composition rule. Existing passwords are not rotated. Initial administrator creation requires an explicit password meeting the same policy in every environment; existing installations are not reseeded. The assigned system Admin role is authoritative; custom role names cannot confer the admin bypass, and the legacy role string is used only for unassigned legacy users.
- The standing AGENTS.md restriction on historical dummy-data repairs remains in force; this implementation does not authorise live historical corrections.

Decision record for implementation

The following records the seven decisions agreed for the current MiniERP work. The implementation should follow these decisions and preserve existing accounting, inventory, and authorization integrity.

## D1 — Require funds for cash purchases, salary and loans?

**Reference:** ACCT-005, PAY-003

- Yes. Cash purchases, salaries, loan payments and other cash outflows must validate sufficient available funds before posting.
- Record opening cash or owner capital first when those funds genuinely exist.
- Fix the 12 affected fixture suites using one shared helper that seeds opening cash; do not weaken production validation to make tests pass.

## D2 — Block reversals of cash inflows that would overdraw cash?

**Reference:** ACCT-013

- Yes. Reject capital edits/voids and receipt deletions or reversals when they would make the affected cash/bank account negative on a later date.
- Show the message: “Reverse the later spending first.” Identify the affected later transactions where practical.
- Check chronological account balances, not only the current balance. Do not allow unauthorized negative cash balances; bank overdrafts require explicit configuration and an approved limit.
- Preserve posted financial records through an auditable correction or reversal process.

## D3 — Salary overpayment model

**Reference:** PAY-001 / PAY-002

- Post once. Split one payment into a current-month salary row (up to the remaining earned salary) and an employee-advance row for the excess.
- The two rows must total exactly the amount paid, link the advance to its parent, and be voided together.
- Record the excess as an employee advance/receivable; do not recognize it as salary expense a second time.

## D4 — Salary-deduction loan repayments

**Reference:** PAY-004

- Post Dr Cash / Cr account 1300, following the agreed direct-repayment model.
- This assumes account 1300 is the employee-loan receivable account and the salary row has already been posted at gross cash. Confirm the account mapping in the chart of accounts.
- Ensure the combined salary and repayment entries represent the actual net cash paid and the reduction in the employee loan balance.

## D5 — Permissions that guard routes but do not exist

**Reference:** AUTHZ-001 / AUTHZ-004

- Seed all 14 missing permission codes into the permissions table so roles can be granted them through the roles screen. Grant none by default.
- Rename inventory:write to inventory:update and update all references consistently.
- Seed admin:* and owner_equity:* as sensitive permissions.
- Retain the AUTHZ-004 rule: non-admins must not grant permissions they do not themselves possess.

## D6 — Production overhead accounting

**Reference:** PROD-001

- Include production overhead directly attributable to manufacturing in production cost because it affects unit cost.
- Allocate applicable overhead using a consistent, documented method; include it in work-in-progress/finished-goods valuation and recognize it through COGS as the products are sold.
- General administrative expenses not attributable to production remain period expenses. Do not expense the same overhead twice.
- Allocate joint costs between mustard oil and mustard cake using relative sales value, and keep production records, inventory valuation, the general ledger and COGS consistent.
- Clarified during Phase 1: overhead amounts entered on production records are not recorded separately as expenses. Production must record their accounting offset rather than assuming an existing expense to absorb.
- Production overhead accrues as unpaid overhead payable until settlement; entering production does not imply cash payment.
- The user explicitly approved correcting PROD-001O: remove its separate expense posting, retain the expected 950 profit, and add assertions that production records overhead exactly once.

## D7 — Back up uploads and allow damaged-stock write-offs?

**Reference:** Backup / inventory write-off

- Yes. Include server/uploads/ alongside each corresponding database backup, with a clear association between the database snapshot and uploaded files.
- Yes. Allow damaged-stock write-offs through the existing write-off flow, requiring a reason code and an auditable record.
- Use account 7201 if it is the correct existing write-off expense account; otherwise, define a dedicated account such as 7202 after checking the chart of accounts.

**Implementation note:** The business decisions above are finalized. Verify account mappings and existing-code dependencies before implementation; do not silently change the agreed accounting behavior.

---

## D8 — Remaining audit findings (user, Phase 3 triage)

**Reference:** AUTHZ-001, D7 / WO-002, D6, and the untested source-review findings

- **AUTHZ-001 grants.** The dormant `seedDefaultPermissions` block that granted `reports:create` to
  the Manager role is removed. D5's "grant none by default" stands for every non-Admin role.
- **AUTHZ-001 sensitivity.** `admin:*` and `owner_equity:*` are marked sensitive by their
  description text only. No `is_sensitive` column and no new enforcement are added.
- **Overhead payable.** Account `2200 Accrued Production Overhead`
  (`text_code = production_overhead_payable`) is confirmed as the liability for unpaid production
  overhead. GL 2000 stays reserved for the supplier ledger.
- **D6 joint costs.** Production is extended to multiple output items so joint costs between
  mustard oil and mustard cake are allocated by relative sales value. Schema, API and Flutter
  changes are all in scope.
- **D7 backups.** `server/uploads/` is included in backups, so a restore recovers employee
  document files. The nightly database-only backup is no longer sufficient on its own.
- **WO-002.** A damaged-stock disposition and write-off is added, using the existing
  `7202 Damaged Goods Loss` account and the existing `DAMAGED` system warehouse. No new account
  and no new warehouse are required.
- **Next scope.** ACCT-006 / ACCT-007 / ACCT-008 (date, tax and discount bounds) are addressed
  before CODE-002/003/004, PRET-002, ACCT-013 and PAY-002.

---

## D9 — Two items raised during Phase 3 implementation (not guessed)

**Reference:** ACCT-006 (third sub-item), ACCT-008

- **ACCT-006 backdated sales.** Rejecting an invoice dated before the item's first
  purchase was implemented and tested, then **removed**. 16 tests across
  `expiredStockSaleBlocking`, `paymentEditReposting` and `arPartialReturn` purchase
  stock and then invoice it at an earlier date — an established, deliberate pattern in
  this codebase. A hard 400 broke all three suites. The other two sub-3 items
  (non-calendar dates, implausibly far-future dates) shipped and are green.
  **Needed:** should a sale dated before the item's first receipt be blocked outright,
  allowed with a warning, or left unrestricted? The stock allocator already refuses to
  oversell *current* sellable stock, so the practical risk is limited to backdated
  COGS reporting.

- **ACCT-008 duplicate submissions.** `Idempotency-Key` handling exists and replays
  correctly, but only when the client sends the header. Making it mandatory would break
  the Flutter client (CODE-004); a server-side dedupe heuristic would reject two
  genuinely identical invoices, which are legitimate. **Needed:** either mandate the key
  on all invoice writes (with a client change), or accept no-key duplicates as-is.

---

## D10 — D6 completed on the Flutter client, plus one defect it exposed

**Reference:** D6 / D8 (joint production, "Schema, API and Flutter changes are all in scope")

- **Flutter entry UI.** The record-production dialog keeps its dedicated primary output
  item + quantity fields, and gains repeatable *additional output* lines. With no extra
  line the payload stays the legacy `output_item_id` / `output_quantity` shape, so
  existing single-product productions are byte-for-byte unchanged. With any extra line it
  switches to `outputs: [...]`, primary first — the server validates the BOM's finished
  item against the **first** line, so the primary must stay first.
- **Client guards mirror the server's** (`productionController.ts`): duplicate output
  items and an item that is both output and input are blocked before the round trip. A
  half-filled extra row (item picked, no quantity) is blocked rather than posted as zero.
- **Preview only.** The form previews the relative-sales-value split via a pure
  `allocateJointCost` that mirrors the server's rule (relative sales value, quantity
  fallback when nothing is priced, last line absorbs the rounding remainder). The server
  recomputes the actuals inside its transaction; nothing client-side is trusted.
- **Cost-per-unit tile.** For a joint run the preview's per-unit figure now spreads the
  batch cost over **all** output units, not the primary's quantity alone — the old
  divisor contradicted the allocation table directly beneath it (it showed 150/unit for
  the oil while the table showed the oil's real 100/unit). Single-output behaviour is
  unchanged; both cases are pinned by widget tests.
- **Defect found while wiring this up — fixed.** `recordProduction` applied the request's
  single `expiry_date` to **every** output batch. The boot-time expiry sweep
  (`boot/expiryDetection.ts`) selects batches on `expiry_date < today` alone, with no
  `items.has_expiry` gate — so a joint production would later move a non-expiry
  co-product (mustard cake) to the EXPIRED warehouse. Expiry is now stamped only on
  outputs whose item actually tracks expiry. Regression test:
  `auditRegression9` "stamps the expiry date only on outputs that track expiry".
  Note this is production-specific: purchases set expiry per line, which is user intent.

---

## D11 — D6 post-review: two corrections to D10

**Reference:** D6 verification pass (joint-production cost preview + batch-expiry audit)

D10's two conclusions below were reasoned but not yet verified end to end. Both are
now superseded. Neither changes a server accounting or allocation rule.

- **D10 "cost-per-unit tile" is corrected.** D10 fixed the divisor from *the primary's
  quantity* to *all output units*, which removed one contradiction but introduced a worse
  one: a joint run can mix units of measure, so `totalCost / Σ quantities` is neither
  co-product's unit cost. Measured case — 10 Litre of oil + 50 kg of cake, pool 1,000:
  the tile showed **16.67** while the allocation table beneath it correctly showed oil at
  **100.00** and cake at **0.00**. The tile is now omitted for multi-output runs and the
  allocation table is the sole source of a per-unit figure. Single-output runs are
  unchanged. The allocation **rule** (relative sales value, quantity fallback, last line
  absorbs the remainder) is untouched on both client and server.
- **D10 "purchases set expiry per line, which is user intent" is rejected.** The guard was
  applied to production only, leaving purchase, goods receipt and the batch PATCH endpoint
  free to stamp an expiry date on an item with `has_expiry = 0`. That is not harmless user
  intent, because the sweep's own gate is `has_expiry`: the stray date sits inert until
  someone switches expiry tracking on for that item, at which point **every** such
  historical batch becomes sweep-eligible and is relocated to the EXPIRED warehouse in a
  single boot. `expiryDetection.test.ts` already demonstrates that flip. Until then the
  batches also surface on the expiry report as goods that never expire.
  The invariant now lives in one place — `ItemModel.batchExpiryDate` — and every batch
  write routes through it. A missing item row counts as "does not track expiry" so the
  sweep's LEFT JOIN still surfaces such batches loudly instead of dropping them.
  This is the "fix the source, not the symptom" rule: D10 guarded one caller while three
  others still produced the bad data.

---

## D12 — Two calls that need the user, not a guess (ACCT-006, ACCT-008)

**Reference:** ACCT-006 sub-item 3, ACCT-008 mandatory enforcement

### ACCT-008 — mandatory `Idempotency-Key` on invoice writes

The original finding is **out of date**. Idempotency is already implemented end to end
and locked by 50+ tests (client key per body, claim inside the create transaction,
409 on payload conflict, concurrent-same-key creates one invoice). The open question is
only whether to make the header **mandatory**.

- **In favour now:** every in-repo client (Flutter desktop, POS) already sends it.
- **Blocker:** `/api/mobile-invoices/*` is deprecated but retained for compatibility and
  is consumed by a mobile app **that is not in this repository**. Whether that app sends
  the key cannot be verified from here, so making the header mandatory would break an
  external consumer we cannot see or test.

**Recommendation: staged enforcement.** Release 1 — server logs a warning on any
keyless invoice write and reports the count. Release 2 — reject with 400 once the mobile
consumer is confirmed migrated or the mobile API is retired. A server-side dedupe
heuristic was rejected: two genuinely identical invoices are legitimate and cannot be
distinguished from a retry by content alone.

### ACCT-006 — backdated sales cannot be fixed as a validation rule

Sub-item 3 (reject a sale dated before the item's first purchase) was implemented and
removed because it broke 16 tests. The probe shows the deeper reason it should not simply
be re-added:

- `StockMovement.consumeFromOldestBatches` takes **no date parameter**. Allocation reads
  current `stock_balances` and current batches. A backdated invoice therefore consumes
  goods that had not been received yet, and books them to a date when they did not exist.
- The FEFO expiry filter compares against `date('now')`, not the invoice date, so a
  backdated sale of goods that were **valid at the time** is rejected as expired today.
- `documentDate` sets no lower bound, so `1999-01-01` is accepted and auto-creates a
  1999-01 accounting period.
- Closed periods are correctly enforced (409 through `postEntry`) — that part is sound.

A correct fix is an **as-of-time allocation**: thread the document date into
`consumeFromOldestBatches`, filter `received_date <= asOf` and `expiry_date >= asOf`, and
price COGS from the batches that existed then. That changes historical costing, so it is a
product call, not a bug fix. It also needs a decision on whether `stock_balances` becomes
a time series or whether as-of stock is reconstructed from `stock_movements`.

**Recommendation:** do not implement until the user chooses. Option (b) — allow with a
clear warning and leave costing as-is — preserves today's behaviour and costs nothing;
option (a) — full as-of allocation — is correct but is an accounting-model change with a
performance and migration cost.
