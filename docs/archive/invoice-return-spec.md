# Spec: Invoice Return — Complete Return, Payment, Refund, Credit & Print History

**Status:** **Final — reviewed end-to-end 2026-09-17, ready for implementation.** Revision history: initial draft (interview decisions D1–D22) → review 1 (D5 fee-always-charged, D20 ACC 4150, D23–D25, "Paid" pinned, voided exclusions) → review 2 (additive tax model pinned to `decomposeLineAmount`, GL tax-imbalance fix, plan added) → review 3 (consistency audit clean; scaffolding cross-checked; 3 test bugs fixed — see §8 note) → GL tax-imbalance patched independently (`glReturnTaxBalance.test.ts` green) and added to acceptance list as 2c.
**Date:** 2026-09-17
**Scope:** Full-stack (SQLite schema, Express/TypeScript backend, Flutter desktop + mobile invoice flows, A4 print, return receipt, reports/dashboards, ledger, GL)

---

## 1. Problem Statement

The invoice return workflow must be reworked so that partial and full returns are handled correctly **as real, linked transactions** — not as edits to the original invoice or as a negative `Balance Due`. Today:

- `calculateInvoiceBalance` (`server/src/utils/ledgerUtils.ts`) computes
  `balance = total − paid − credit_offset − (returned_amount − return_fee)`, which produces **negative Balance Due** after a return on a paid invoice — exactly what the requirement forbids.
- Returns are not first-class documents. They are reconstructed from `stock_movements` (`reference_doctype = 'RETURN'`) plus aggregate columns `invoices.returned_amount` / `invoices.return_fee`. There are no `RET-`/`RSF-`/`CR-` reference numbers, no return header/items/settlement tables.
- The A4 print (`lib/features/sales/invoice_pdf.dart`) shows a single "Returned" total and the payment history, but no return history, per-return restocking fee, settlement records, or transaction timeline.
- Refunds are hardcoded to method `'Cash'`; the excess over what was collected is silently retained as a ledger credit.
- The return value math is tax-exclusive; tax handling must become a proportional mirror of the sale.

**Core principle: Never replace history with the current state.**
`Original Sale → Original Payments → Returns → Restocking Fees → Settlements → Current Invoice Position` must exist as separate, linked, persisted transactions.

---

## 2. Confirmed Decisions (from interview)

| # | Topic | Decision |
|---|-------|----------|
| D1 | Data model | **New return tables**: `invoice_returns` header + `invoice_return_items` + return settlement records, with `RET-`/`RSF-`/`CR-` reference numbers. Stock movements remain for inventory only. |
| D2 | Balance Due | **Clamp stored `balance_amount` to ≥ 0.** The overpayment is surfaced as a separate computed **Refund/Credit Due**. Never a negative Balance Due anywhere. |
| D3 | Refund math (partially paid) | **Position-based formula** (see §3): `Net Position = Paid − Remaining Invoice Value − Restocking Fee`. Positive → Refund/Credit Due; negative → Balance Due (customer still owes). **Not** simply `returned − fee`. |
| D4 | Settlement timing | **Both immediate and deferred**: disposition can be chosen at return time, but a return may also be left **unsettled** and settled later. |
| D5 | Fee on unpaid invoices | **Fee is ALWAYS charged** (revised during review — supersedes the earlier per-return checkbox idea). Even on unpaid invoices with no refund due, the restocking fee is recorded and increases the customer's Balance Due. *(Revised 2026-09-17)* |
| D6 | Multi-return / double-refund | **Current Position + Cumulative Settlement Cap** (see §5). The cap is the hard, backend-level safety rule. |
| D7 | Adjust targets | **Keep auto + manual**: user may pick target invoices; otherwise auto-apply to oldest unpaid/partially-paid invoices of the same customer; leftover continues to next invoice or stays as customer credit. |
| D8 | Refund methods | **Real methods (Cash/Bank/Card) + GL-linked**: the method must debit the matching GL cash/bank account, not just be a label. Cash-funds sufficiency check applies to Cash. |
| D9 | Reports scope | **Full consistency**: dashboards, sales reports, and the customer ledger all use the new formulas. |
| D10 | Print formats | **A4 PDF** (complete story) + **separate Return Receipt** document. Thermal receipt is out of scope. |
| D11 | Legacy data | **New only**: new tables apply to returns processed from now on; legacy returns (existing `returned_amount`/`return_fee`) keep rendering via the stock-movement view. No backfill migration of legacy returns. |
| D12 | Display | **Both lines always**: `Balance Due` and `Refund/Credit Due` shown side by side (one is always zero), plus `Current Invoice Value`. Never merged, never negative. |
| D13 | Tax | **Proportional mirror**: refund the same proportion of tax as the returned portion of the line; fee applied to the tax-inclusive returned value. |
| D14 | Return date | **Hybrid**: user-pickable return date (GL + return documents dated accordingly), but customer ledger entries keep today's date to avoid back-dated balance recomputes. |
| D15 | Mistakes | **Voidable returns**: a return can be voided with full GL/inventory reversal (permission-guarded per existing model — no new granular permissions); voided returns restore returnable quantity. |
| D16 | Credit usage | **Reuse `credit_offset`**: return credits join the same pool the payment dialog draws from. |
| D17 | Mobile | **Include mobile**: `mobileInvoiceController` flow must get the corrected math and dispositions. |
| D18 | Settlement shape | **One or more settlement allocations per return** — a single return may be split (e.g. 600 cash refund + 480 credit of a 1080 net). Sum of allocations ≤ return's net settlement amount; all methods consume the same entitlement. |
| D19 | Numbering | **New RET/RSF/CR series** generated via the existing atomic number generator (e.g. `RET-0926-00001`). |
| D20 | Fee accounting | **Dedicated income account `4150` "Restocking Fee Income"** (already seeded by `add-gl-foundation.sql` — no COA migration needed). The fee posts as its **own journal entry** (`Dr AR / Cr 4150`), never embedded inside the Sales Return entry. |
| D21 | i18n | **English + Urdu**: all new labels in `en.arb` and `ur.arb`. |
| D22 | Testing | Backend unit tests (all acceptance scenarios) + GL balancing tests per settlement type + print-content test. |
| D23 | Closed periods | **Block back-dating into a closed accounting period**: if the picked return date falls in a period with `status = 'closed'`, the return is rejected with a clear error. Locked books are never touched. |
| D24 | Settlement voids | **Individual settlements are voidable** without voiding the return: voiding a settlement reverses its GL/ledger/payment rows and returns the amount to the return's unsettled balance and the invoice's Remaining Refund Due. The return itself stays intact. |
| D25 | Unpaid-invoice settlement | On an unpaid invoice (no refund/credit due): do NOT block the return, do NOT create a refund or credit, do NOT waive the fee; the settlement step is marked **Not Required**. `New Invoice Balance = Remaining Goods Value + Restocking Fee`. |

---

## 3. Financial Model (authoritative formulas)

### 3.1 Core quantities

```text
Remaining Invoice Value = Original Invoice Total − Total Returned Value
Current Invoice Value   = Remaining Invoice Value   (same thing; one term in UI)
Total Restocking Fees   = Σ fees across all returns on the invoice
Paid                    = Σ active (non-voided) payment allocations + credit offsets applied
```

### 3.2 Invoice position (computed after every return/settlement)

```text
Net Customer Position = Paid − Remaining Invoice Value − Total Restocking Fees
```

**"Paid" definition (pinned during review):** `Paid` = **gross collections** — the sum of original payment allocations (positive) plus credit offsets applied, **without subtracting refunds**. Refunds/settlements reduce the position only once, through the `Already Settled` term of the cumulative cap (§3.4). Subtracting them from `Paid` too would double-count.

- `Net Position > 0` → **Refund/Credit Due = Net Position**, `Balance Due = 0`
- `Net Position = 0` → both zero
- `Net Position < 0` → **Balance Due = |Net Position|**, `Refund/Credit Due = 0`

All aggregates (`Total Returned Value`, `Total Restocking Fees`, `Paid`, `Already Settled`) **exclude voided returns and voided settlements**.

Worked examples:

| Scenario | Total | Returned | Remaining | Paid | Fee | Refund/Credit Due | Balance Due |
|---|---|---|---|---|---|---|---|
| Fully paid, partial return | 1800 | 1200 | 600 | 1800 | 120 | **1080** | 0 |
| Partially paid | 1800 | 1200 | 600 | 1000 | 200 | **200** (1000−600−200) | 0 |
| Underpaid | 1800 | 1200 | 600 | 500 | 200 | 0 | **300** |
| Unpaid, no fee | 1800 | 1200 | 600 | 0 | 0 | 0 | **1200** |
| Unpaid, fee charged (always) | 1800 | 600 | 1200 | 0 | 100 | 0 | **1300** (Remaining 1200 + Fee 100) |
| Unpaid, FULL return | 1800 | 1800 | 0 | 0 | 100 | 0 | **100** (fee only) |

### 3.3 Per-return settlement entitlement

```text
Return Net Settlement = Returned Value (tax-mirrored) − This Return's Restocking Fee
```

### 3.4 Cumulative cap (hard rule)

```text
Max Customer Refund/Credit Entitlement
    = Total Paid − Remaining Invoice Value − Total Restocking Fees   (floored at 0)

Already Settled = Σ(all settlements of ALL types on this invoice)
                = Direct Refunds + Customer Credits + Invoice Adjustments

Remaining Available = Max Entitlement − Already Settled
```

- A new settlement allocation must satisfy `allocation ≤ Remaining Available`, else **rejected** at the backend (validation inside the DB transaction, plus a check constraint where feasible).
- Settlements of different types share one pool: refund 600 + credit 600 + adjust 600 against entitlement 1200 is **rejected**.
- This cap must be enforced server-side even if position math has a bug (defense in depth).

### 3.5 Tax — proportional mirror (ADDITIVE model, pinned to `decomposeLineAmount`)

The system's tax model is **additive** (`server/src/utils/currency.ts::decomposeLineAmount`): `line amount = (gross − discount) + tax`, where `tax = (gross − discount) × taxRate / 100`, and `net_amount + tax_amount = amount` per line. Tax is **never** extracted from a tax-inclusive amount — do not use the `rate / (100 + rate)` extraction form.

For each returned portion of a line:

```text
returnedRatio      = returnQty / originalLineQty
lineNet            = (qty × rate) − lineDiscount        // per decomposeLineAmount rules
lineTax            = lineNet × taxRate / 100            // additive
returnedValueNet   = lineNet × returnedRatio
returnedTax        = lineTax × returnedRatio            // roundCurrency per line
returnedValueGross = returnedValueNet + returnedTax
feeBase            = returnedValueGross                 // tax-inclusive
netReturn          = returnedValueGross − fee
```

**Reconciliation (scenario 13):** 3 units @ 600, 10% tax → line net 1800, tax 180, amount 1980, paid 1980. Return 2/3 → returned net 1200, tax 120, **gross 1320**; fee 10% = **132**; net settlement **1188**. Position: `Paid 1980 − Remaining (1 unit = 660) − Fees 132 = 1188`. ✓ The per-return net settlement (§3.3) and the invoice-level position (§3.2) agree exactly — the fee is subtracted exactly once in each.

**GL correction (fixes a live imbalance bug):** the current `postInvoiceReturnEntry` posts `Dr Sales Returns (tax-exclusive gross) + Dr Tax Payable` while crediting AR by the tax-exclusive net — the entry is **imbalanced by the tax amount** whenever `tax_rate > 0`. The reworked return entry must be:

```text
Dr Sales Returns (4100)       returnedValueNet
Dr Tax Payable (2100)         returnedTax
    Cr Accounts Receivable    returnedValueGross
```

with the fee in its separate `RETURN_FEE` entry (D20).

### 3.6 Restocking fee

- Types: **None**, **Fixed amount**, **Percentage**.
- Base: the **returned sale value (tax-inclusive per §3.5)**, never the original invoice total.
- Stored **separately** per return (`fee_type`, `fee_value`, `fee_amount`) and posted to the dedicated income account **4150** (D20).
- **Must NOT reduce the value of goods remaining on the invoice** — it only affects the customer's money position.
- **Always charged** (D5, revised): it applies even when the invoice is unpaid and there is no Refund/Credit Due. On an unpaid invoice the fee simply increases Balance Due (see D25).
- **Separate GL entry** (never embedded in the Sales Return entry):

```text
Dr Accounts Receivable (1100)   fee amount
    Cr Restocking Fee Income (4150)   fee amount
```

  On a paid invoice this is economically equivalent to deducting the fee from the refund (AR is owed a 1200 credit, fee debits 120 back, net owed 1080); on an unpaid invoice it adds to what the customer owes. Same entry either way.

---

## 4. Data Model

### 4.1 New tables (migration required)

```sql
-- Return header: one row per return event
CREATE TABLE invoice_returns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  return_no TEXT NOT NULL UNIQUE,            -- RET-0926-00001 (atomic generator)
  invoice_id INTEGER NOT NULL REFERENCES invoices(id),
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  return_date TEXT NOT NULL,                 -- user-pickable (D14)
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'Unsettled',  -- Unsettled | Settled | Voided
  fee_type TEXT,                             -- 'none' | 'fixed' | 'percentage'
  fee_value REAL NOT NULL DEFAULT 0,         -- 10 (percent) or 150 (fixed)
  fee_amount REAL NOT NULL DEFAULT 0,        -- resolved amount
  returned_amount REAL NOT NULL DEFAULT 0,   -- tax-mirrored gross returned value
  net_amount REAL NOT NULL DEFAULT 0,        -- returned_amount − fee_amount
  settled_amount REAL NOT NULL DEFAULT 0,    -- Σ allocations (≤ net_amount)
  warehouse_id INTEGER,                      -- restock warehouse (existing behavior)
  created_by INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  voided_at TEXT,
  voided_by INTEGER
);

CREATE TABLE invoice_return_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  return_id INTEGER NOT NULL REFERENCES invoice_returns(id),
  invoice_item_id INTEGER NOT NULL REFERENCES invoice_items(id),
  item_id INTEGER NOT NULL,
  quantity REAL NOT NULL,                    -- > 0, ≤ sold − already returned
  unit_price REAL NOT NULL,                  -- original sale price
  tax_amount REAL NOT NULL DEFAULT 0,        -- proportional mirror (§3.5)
  line_amount REAL NOT NULL,                 -- net of item discount, incl. tax
  UNIQUE (return_id, invoice_item_id)
);

CREATE TABLE return_settlements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  return_id INTEGER NOT NULL REFERENCES invoice_returns(id),
  settlement_no TEXT NOT NULL UNIQUE,        -- CR-… (credit), refund uses payment no, adjust uses its own
  type TEXT NOT NULL,                        -- 'refund' | 'credit' | 'adjust'
  amount REAL NOT NULL,                      -- > 0
  method TEXT,                               -- refund only: Cash | Bank | Card …
  reference TEXT,                            -- payment no / target invoice no
  target_invoice_id INTEGER,                 -- adjust only
  payment_id INTEGER,                        -- links to payments row for refund/adjust
  settled_date TEXT NOT NULL,
  created_by INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  voided_at TEXT
);

CREATE INDEX idx_invoice_returns_invoice ON invoice_returns(invoice_id);
CREATE INDEX idx_invoice_returns_customer ON invoice_returns(customer_id);
CREATE INDEX idx_return_settlements_return ON return_settlements(return_id);
CREATE INDEX idx_return_settlements_invoice ON return_settlements(target_invoice_id);
```

Notes:
- All writes in transactions with prepared statements (project DB rules).
- Existing `invoices.returned_amount` / `return_fee` aggregate columns are **kept in sync** for backward compatibility of reports during transition, but the tables above are the source of truth for history.
- Restocking-fee income account: **`4150` "Restocking Fee Income"** — **already seeded** by `server/src/migrations/add-gl-foundation.sql` (revenue, credit). No chart-of-accounts migration needed; only a code lookup guard (`AccountingService.getAccountByCode(db, '4150')`) with a clear error if absent on legacy DBs whose COA predates GL foundation.
- **No legacy backfill** (D11): rows in `invoice_returns` only exist for returns processed after this change. Old invoices continue to render via the stock-movement fallback (§7.4).

### 4.2 Invoice balance changes

- `calculateInvoiceBalance` is reworked: `balance_amount` is **clamped to ≥ 0** and equals `max(0, Net Customer Position)` per §3.2.
- A computed position object (not stored negative) exposes:
  - `originalTotal`, `totalReturned`, `currentInvoiceValue`, `totalPaid`, `totalFees`, `refundCreditDue`, `settledAmount`, `remainingRefundDue`, `balanceDue`.
- `updateInvoiceStatus` semantics preserved (`Returned` / `Partially Returned`), but never driven by a negative balance.

---

## 5. Backend Flow

### 5.1 `POST /invoices/:id/return` (rework of `returnInvoiceItems`)

Inside a single DB transaction:

1. Validate: invoice exists, not cancelled; per line `returnQty ≤ lineQty − alreadyReturned` (fresh read inside transaction; keep the existing race-condition protection and the monetary over-return guard).
2. **Period check (D23)**: if the picked return date falls inside an accounting period with `status = 'closed'`, reject with a clear error (locked books are never modified). Returns dated **today** (the default) are always allowed — only back-dated dates inside closed periods are blocked.
3. Create `invoice_returns` header + `invoice_return_items` rows (RET- number via atomic generator).
4. Mirror tax proportionally (§3.5); compute fee from fee_type/fee_value against tax-mirrored returned value. The fee is **always charged** (D5).
5. Reverse stock (`InvoiceModel.reverseStockForItems`) — unchanged behavior, restock warehouse as today.
6. Post GL, as **separate journal entries** (D20):
   - **Sales Return entry** (`reference_type = 'INVOICE_RETURN'`): `Dr Sales Returns 4100 (returnedValueNet)`, `Dr Tax Payable 2100 (returnedTax)`, `Cr AR (returnedValueGross)` — balanced per §3.5 (this fixes the current tax-imbalance bug).
   - **COGS reversal** (existing `postCOGSReversalEntry`, unchanged).
   - **Restocking Fee entry**: `Dr AR (1100) / Cr Restocking Fee Income (4150)` — its own entry (`reference_type = 'RETURN_FEE'`), never embedded in the return entry.
7. Recompute invoice position; clamp `balance_amount ≥ 0`; update status; sync `returned_amount`/`return_fee` aggregates.
8. Settlement handling (D4/D25):
   - If the invoice has Refund/Credit Due > 0 and disposition(s) were provided, create settlement allocation(s) subject to the cumulative cap (§3.4).
   - If Refund/Credit Due = 0 (unpaid invoice), mark the return's settlement step **Not Required** — no refund, no credit, no adjustment rows; the fee is already inside the new Balance Due.
   - Otherwise (disposition omitted but amount due), leave `status = 'Unsettled'` for later settlement.
9. Customer ledger entries dated **today** (D14) even when the return date is back-dated.
10. Activity log + structured JSON response containing the full position object.

### 5.2 Settlement endpoints

- `POST /invoice-returns/:id/settle` — one or more allocations in one call: `{ allocations: [{ type, amount, method?, target_invoice_id? }] }`. Validates:
  - `Σ allocations ≤ return.net_amount − return.settled_amount`
  - invoice-level cumulative cap (§3.4) — the hard rejection rule
  - refund: real method (D8), posts `Dr <Cash/Bank GL account> … Cr AR`, cash-funds sufficiency check for Cash
  - credit: increases customer credit pool (joins `credit_offset` mechanism, D16); CR- number
  - adjust: creates payment-allocation against target invoice(s) (auto-pick oldest unpaid when none supplied, D7), recalculates target invoice balance/status
- `POST /return-settlements/:id/void` — **void a single settlement** (D24): reverses that settlement's GL entry, ledger rows, and payment/allocation rows only; the return stays intact; `return.settled_amount` and the invoice's Remaining Refund Due increase back by the voided amount; the cumulative cap frees up correspondingly. Permission-guarded by the existing invoices permission model.
- `POST /invoice-returns/:id/void` — voids an entire return (and all of its settlements) only when safe: reverses GL entries (return + fee), reverses stock restock, restores returnable quantities, voids ledger rows via the existing reversal mechanism, voids settlements. Permission-guarded by the existing invoices permission model (D15/D22 — no new granular permissions).
- `GET /invoices/:id/position` (or folded into invoice detail) — returns the computed position object (§4.2) including per-return history + settlement history + timeline.

### 5.3 Mobile

`mobileInvoiceController` return flow must use the same service-layer logic (extract shared return service so desktop/mobile cannot diverge) — same formulas, same cap, same dispositions (D17).

### 5.4 Error handling

- All endpoints: try/catch, structured JSON errors, no stack leakage; user-facing messages localized.
- Any validation failure aborts the whole transaction (no partial returns).

---

## 6. Frontend (Flutter desktop + mobile)

### 6.1 Return dialog (`invoice_return_dialog.dart`) rework

- Per-line return qty (existing), **return date picker** (default today, D14).
- Restocking fee selector: None / Fixed / Percentage + value; live preview of fee and net.
- ~~Checkbox: "Apply fee even if no refund"~~ — **removed during review**: the fee is always charged (D5 revised). The dialog instead shows an informational note that on unpaid invoices the fee increases Balance Due.
- Settlement section (D4/D18):
  - Option A: settle now — choose one or more allocations (refund with method picker Cash/Bank/Card, credit, adjust with target invoice picker).
  - Option B: leave unsettled ("Record return only").
- Live position preview panel showing: Returned Value, Restocking Fee, Net, and post-return **Balance Due** and **Refund/Credit Due** (both lines, D12), matching server math exactly (shared formula, mirrored client-side).
- Pluto-grid conventions for lists; loading/error/toast states per frontend rules.

### 6.2 Invoice screens

- Invoice detail/form and print preview show the position block (D12):

```text
Original Invoice Total     1800
Total Returned             1200
Current Invoice Value       600
Original Payments          1800
Restocking Fees             120
Balance Due                   0      ← always shown
Refund/Credit Due          1080      ← always shown
Refunded/Credited          1080      ← when settled
Remaining Refund Due          0
```

- Returns tab / history on the invoice shows each return with its own date, RET- number, items, fee, and settlements.

### 6.3 Print

- **A4 PDF** (`invoice_pdf.dart`) — complete story (D10):
  1. Original invoice (original lines untouched)
  2. Original payments (every payment, unchanged)
  3. Return history (each return: RET- no, date, items, qty at original rate, returned value)
  4. Per-return financial summary (returned value, fee with type, net)
  5. Return settlements (each allocation: date, type, method/reference, amount)
  6. Current invoice position block (D12 formatting)
  7. Chronological **Transaction History** built from persisted rows (invoice → payments → returns → fees → settlements), not reconstructed from totals
  - Fallback for invoices with pre-migration legacy returns: render the old stock-movement-based view (D11).
- **Return Receipt** — standalone printable per return: RET- number, date, items, returned value, fee, net, and settlement allocation(s) (mirrors spec §6/§9).
- Thermal receipt: unchanged (out of scope).

### 6.4 Localization

All new labels ("Current Invoice Value", "Refund/Credit Due", "Restocking Fee", "Settlement", "Return Receipt", "Unsettled", etc.) added to `en.arb` and `ur.arb`, then `flutter gen-l10n`.

---

## 7. Accounting, Ledger, Reports

- **GL**: every return/fee/settlement is a balanced journal entry referencing persisted documents. The return entry credits AR by the **tax-inclusive** returned value (`Dr Sales Returns net + Dr Tax Payable tax / Cr AR gross`) — fixing the current imbalance where tax-rated returns leave the entry short by the tax amount (§3.5). Fee posts to the dedicated income account (D20). Refund posts through the method's actual cash/bank account (D8). Adjust posts through payment allocations. Void reverses exactly.
- **Customer ledger**: RETURN (credit, net), REFUND (debit, refund payment no), PAYMENT (credit, adjust) entries — same money never double-counted; ledger dates = today (D14).
- **Customer credit**: return credits feed the existing `credit_offset` pool usable in the payment dialog (D16).
- **Dashboards/reports**: sales totals use `total − returned` as today, but any refund/fee/position display uses the new formulas; restocking-fee income appears in revenue reports (D9).

---

## 8. Acceptance Tests

Backend (Jest) — must cover, matching the spec's acceptance case (INV-0926-00007: 3 × 600 = 1800, paid 1800, return 2 × 600, fee 10% → returned 1200, fee 120, net 1080):

1. Original invoice lines and payments unchanged after return.
2. Partial return on fully-paid invoice: position = {1800, 1200, 600, paid 1800, fee 120, Refund/Credit Due 1080, Balance Due 0}.
2b. Tax-rated return GL balances: `Dr 4100 (net) + Dr 2100 (tax) = Cr AR (gross)` — the current imbalance-by-tax bug is fixed.
2c. **Regression (already fixed by the independent GL patch, keep covered):** `postInvoiceReturnEntry` credits AR by the tax-inclusive `gross + tax − fee` on every tax/fee combination — tax-rated returns are never imbalanced by the tax amount. Covered by `server/src/__tests__/glReturnTaxBalance.test.ts` (5 cases: no-tax/no-fee, tax repro, tax+fee, no-tax/fee, AR-credit-is-tax-inclusive); the rework must keep these green.
3. Settlement as credit: credit = 1080 exactly; remaining due 0; ledger + GL balanced.
4. Settlement as refund (Cash/Bank/Card): only net refunded; GL debits the method's account; cash-funds check enforced for Cash.
5. Settlement as adjust: only net applied to target invoice; auto-pick works; partial-target carryover works.
6. Mixed settlement: 600 refund + 480 credit = 1080 total, no double count; cumulative cap enforced across types and across multiple returns; over-settlement rejected at backend.
7. Partially paid invoice (paid 1000, returned 1200, fee 200): Refund/Credit Due 200, Balance Due 0.
8. Underpaid invoice (paid 500): Balance Due 300, Refund Due 0, no negative balance persisted.
9. Unpaid invoice: return allowed, settlement **Not Required**; fee always charged → Balance Due = Remaining Goods Value + Fee (1200 + 100 = 1300; full return → 100).
10. Multiple returns (1+1 of 3): quantities, values, per-return documents, cumulative caps.
11. Full return: returned 1800, fee 180, net 1620, Current Invoice Value 0.
12. Fixed vs percentage fee math; fee base = tax-mirrored returned value.
13. Tax proportional mirror vs sale tax.
14. Return-quantity guard (cannot exceed sold − returned, including concurrent requests).
15. Void return: full reversal of GL/stock/ledger/settlements; quantities restorable; voided return excluded from position.
16. Deferred settlement: unsettled return later settled via `/settle` within caps.
17. Void single settlement: refund reversal returns the amount to Remaining Refund Due; cap freed; return intact; GL/ledger/payment rows reversed only for that settlement.
18. Back-dated return into a closed accounting period: rejected with a clear error (D23).
19. GL integrity: Dr == Cr for every posting, per settlement type.
20. Fee GL entry: `Dr AR / Cr 4150` exists as its own journal entry, separate from the Sales Return entry (D20).
21. Print content: A4 PDF (or its data assembly) contains original invoice, payments, each return, fee, settlement, timeline, and position sections; legacy invoice falls back gracefully.

Frontend: manual verification of dialog preview vs server result, both display lines, Urdu + English labels.

**Scaffolding cross-check note:** the test scaffolding (`server/src/__tests__/helpers/invoiceReturnSpec.ts` + 3 spec files, typechecked) is the executable form of this list. The final consistency pass found and fixed scaffolding bugs so it matches this spec exactly:
1. Scenario 4's Cash assertion now reflects §5.2 semantics: a refund **reduces** cash — `Cr Cash (1000)` on the refund settlement's PAYMENT posting — and the entry group balance is asserted via the settlement's `payment_id`.
2. Scenario 15's ledger-restoration check was a tautology (`x − x`); it now compares `customerLedgerNet` after the void against the value recorded after the return+settlement (the invoice is fully paid, so the void must restore it exactly).
3. `settlementsFor` now returns `payment_id`, letting GL assertions target the exact posting group (used by scenarios 4 and 19).

---

## 9. Explicit Non-Goals

- No backfill migration of legacy returns (D11).
- Thermal receipt changes (D10).
- New granular permissions (D22 — reuse existing invoices permission model).
- Editing original invoice lines or payments — forbidden, ever.

## 10. Implementation Plan (ordered)

Wiring points verified in the codebase:
- Migrations run through the **ledgered runner** in `server/src/config/database.ts` (`runLedgered('<name>')` — exactly-once per DB, ordered inline where the other `runLedgered` calls live).
- Routes register in `server/src/routes/invoices.ts` (note: `GET /returns` is declared **before** `GET /:id`, so any new literal paths like `/:id/position` are safe; a new `invoiceReturns.ts` router would mount via `app.use('/api/...')` in `server/src/app.ts`).
- Atomic numbering exists as `InvoiceModel.generatePaymentNoAtomic(db)` — the RET- generator follows the same pattern.
- Position consumers today: `ledgerUtils.calculateInvoiceBalance` / `updateInvoiceStatus`, called from invoiceController and several backfills.
- The acceptance scaffolding (§8, 3 files + helpers) defines the target API shape — implementation is done when it turns green.

### Milestone 1 — Migration + shared math (backend, no behavior change yet)

| Step | File(s) | What |
|---|---|---|
| 1.1 | `server/src/migrations/add-invoice-returns.sql` | New tables per §4.1: `invoice_returns`, `invoice_return_items`, `return_settlements` + indexes. Guarded/idempotent (CREATE TABLE IF NOT EXISTS, CHECK on `type`/`status`, `amount > 0`). |
| 1.2 | `server/src/config/database.ts` | `runLedgered('add-invoice-returns.sql')` placed **after** `add-batch-location-model.sql` (FK-free, so position is flexible; keep it near the other invoice migrations). Boot-time guard: `getAccountByCode('4150')` must exist → clear boot error if a legacy COA predates GL foundation. |
| 1.3 | `server/src/services/returnMath.ts` (new) | Pure functions from §3: `computeReturnedLine()` (additive tax mirror via the same rules as `decomposeLineAmount`), `resolveFee()` (none/fixed/percentage, clamped to returned value), `computePosition()` (§3.2–3.4, gross-`Paid`, voided-exclusions, cumulative cap). Unit-testable without HTTP. |
| 1.4 | `server/src/models/InvoiceReturn.ts` (new) | Row model: create header/items/settlements, `generateReturnNoAtomic` (RET-/CR- series, pattern of `generatePaymentNoAtomic`), `getByInvoice`, `getByReturn`, settlement sum helpers. Prepared statements only. |

**Verify:** `npm run typecheck`; migration replay test (`migrationReplay`-style) includes the new file; `returnMath` unit tests for fee clamping + tax mirror + cap.

### Milestone 2 — Return service (core rework, behind the same endpoint)

| Step | File(s) | What |
|---|---|---|
| 2.1 | `server/src/services/invoiceReturnService.ts` (new) | `processReturn()`: the §5.1 transaction (validation, period check D23, header+items, stock reversal, two GL entries per §3.5/D20, aggregate sync, position recompute, optional immediate settlements, ledger dated today, activity log). Extracts logic so desktop/mobile share it (D17). |
| 2.2 | `server/src/services/accountingService.ts` | Rework `postInvoiceReturnEntry` to the balanced §3.5 shape (Dr 4100 net + Dr 2100 tax / Cr AR gross); remove the embedded fee line (fee moves to its own `RETURN_FEE` entry via a new `postReturnFeeEntry`). **Pre-patched already**: the minimal tax-balance fix has landed (AR credited tax-inclusive); the rework must keep `glReturnTaxBalance.test.ts` green while replacing the blended `taxAmount` argument with per-line mirrored tax. |
| 2.3 | `server/src/controllers/invoiceController.ts` | `returnInvoiceItems` becomes a thin adapter: parse/normalize payload (keep legacy field aliases) → call the service → respond with the position object. Delete the inline transaction body. |
| 2.4 | `server/src/utils/ledgerUtils.ts` | Rework `calculateInvoiceBalance` to the §3.2/§4.2 clamped formula; `updateInvoiceStatus` unchanged semantics. Ensure all existing callers compile. |
| 2.5 | `server/src/controllers/mobileInvoiceController.ts` | Route mobile returns through the same service. |

**Verify:** `npm run typecheck` + run `invoiceReturnAcceptance.test.ts` scenarios 1–8 (minus settle-dependent assertions until M3 where noted) + `glReturnTaxBalance.test.ts` (regression — must stay green); existing suites (`creditOffset`, `invoiceCancelReversal`, `glPostingMatrix`, `statusMachine`, `ledgerIntegrity`) still green.

### Milestone 3 — Settlement endpoints + position endpoint

| Step | File(s) | What |
|---|---|---|
| 3.1 | `server/src/routes/invoiceReturns.ts` (new) + `app.ts` | `POST /api/invoice-returns/:id/settle` (§5.2 validation order: per-return remainder → invoice cumulative cap → type-specific posting), `POST /api/invoice-returns/:id/void`, `POST /api/return-settlements/:id/void`. Mount under existing auth/permission middleware (`invoices` module). |
| 3.2 | `server/src/routes/invoices.ts` + controller | `GET /invoices/:id/position` → §4.2 position object + per-return history + settlements + timeline (also folded into `getInvoice` detail for the print payload, §6.3/§8 scenario 21). |
| 3.3 | `server/src/services/invoiceReturnService.ts` | Settlement postings: refund (method → GL account, `assertSufficientFunds` for Cash), credit (CR- no, `credit_offset` pool per D16), adjust (payment allocation, auto-pick oldest unpaid per D7, target recompute). Void paths with exact reversals (D24/D15). |

**Verify:** scenarios 1–21 fully green; `glLifecycle`, `cashTruth`, `accountingInvariants` still green.

### Milestone 4 — Frontend (Flutter desktop)

| Step | File(s) | What |
|---|---|---|
| 4.1 | `lib/data/models/sales_return.dart`, `invoice.dart` | Add position, return-document, settlement models (`fromJson` per existing `asNum/asString` conventions). |
| 4.2 | `lib/data/repositories/invoice_repository.dart` | `position()`, updated `processReturn` payload (fee fields, return date, settlements), `settleReturn`, `voidReturn`, `voidSettlement`. |
| 4.3 | `lib/features/sales/invoice_return_dialog.dart` | §6.1 rework: date picker, fee selector, settlement allocations builder, live position preview (client mirror of `returnMath`), informational note for unpaid invoices (checkbox removed per D5). |
| 4.4 | `lib/features/sales/invoice_providers.dart` + sales screens | Position block (both lines, D12) on detail/form/print-preview; returns tab per §6.2. |
| 4.5 | `l10n/en.arb` + `l10n/ur.arb` → `flutter gen-l10n` | All new labels (D21). |

**Verify:** `flutter analyze`; widget tests updated where the dialog shape changed; manual acceptance of §17 both-locale.

### Milestone 5 — Print (A4 + Return Receipt)

| Step | File(s) | What |
|---|---|---|
| 5.1 | `lib/features/sales/invoice_pdf.dart` | §6.3 seven sections; position block; transaction timeline from persisted rows; legacy fallback (stock-movement view) when no `invoice_returns` rows exist (D11). |
| 5.2 | `lib/features/sales/return_receipt_pdf.dart` (new) | Standalone Return Receipt per return (§6/§9 format). |
| 5.3 | `lib/features/sales/invoice_print_preview_page.dart` | Entry point for the Return Receipt (per-return button in the returns history). |

**Verify:** print-content assertions of scenario 21; manual A4 visual check of the §17 invoice.

### Milestone 6 — Reports/dashboards + hardening

| Step | File(s) | What |
|---|---|---|
| 6.1 | `server/src/models/Dashboard.ts`, `utils/reportSql.ts`, reports | Keep `total − returned` sales math; surface fee income (4150) in revenue reports; ensure every refund/fee/position display uses the new formulas (D9). |
| 6.2 | `server/src/utils/sqlSanitizer.ts`, `entityRegistry.ts` | Whitelist new tables/columns for sorting + custom reports (returns grid gains new fields). |
| 6.3 | Full suite | `npm run typecheck && npm run lint && npm test` (backend), `flutter test` (client). |

**Suggested commit boundaries:** M1 (migration+math, inert), M2 (service+endpoint rework), M3 (settlement+position), M4 (desktop UI), M5 (print), M6 (reports). Each keeps the suite green at its boundary except the acceptance scaffolding, which converges red→green across M2–M5.

**Risks / watch-list:**
- `calculateInvoiceBalance` rework touches backfill scripts (`recalcInvoiceBalancesBackfill`, repair-stock) — re-run their expectations.
- Legacy payloads without `fee_type`/`settlements` must keep working (server defaults fee `none`, settlement deferred) — covered by the payload-normalization step in 2.3.
- Concurrent returns: keep the fresh-in-transaction `returned_qty` read (already in the current code) inside the new service.
- `dashboardKpi`/`moneyPaths` tests assert `total − returned_amount` aggregates — keep the sync columns exact.

---

## 11. Out-of-scope Notes / Open Items

- ~~Exact ACC code for "Restocking Fee Income"~~ **Resolved**: account **`4150`** already exists in `add-gl-foundation.sql`. Legacy DBs missing it need only a boot-time guard.
- Whether `returned_amount`/`return_fee` aggregate columns are eventually dropped is a later cleanup; for now they stay synced (excluding voided returns).
- POS quick-return flow (if any) is not covered; the desktop + mobile invoice flows are.
