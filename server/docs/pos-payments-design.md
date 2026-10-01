# POS payments, discount and tax — technical specification

**Status:** design only. No product code, no migration, no test has been written for this
change. Accounting semantics and the client contract require sign-off before any
implementation (§10).

**Scope:** let the point of sale take any supported payment method (including split
payments), apply discounts and tax, sell on credit, and still post through the one
existing invoice/payment accounting path — with every cash invariant intact.

---

## Contents

1. [Verified current state](#1-verified-current-state)
2. [The blocking finding](#2-the-blocking-finding)
3. [The central design decision](#3-the-central-design-decision)
4. [Data model (proposed — not created)](#4-data-model-proposed--not-created)
5. [GL postings](#5-gl-postings)
6. [Business rules](#6-business-rules)
7. [Reporting impact](#7-reporting-impact)
8. [UI specification](#8-ui-specification)
9. [Regression matrix](#9-regression-matrix)
10. [Open decisions requiring sign-off](#10-open-decisions-requiring-sign-off)
11. [Suggested implementation order](#11-suggested-implementation-order)

---

## 1. Verified current state

### 1.1 Defined terms

Every term the task asks for, grounded in code — this is the vocabulary the rest of
the document uses.

| Term | Definition as this codebase implements it |
|---|---|
| **cash** | Payment method `Cash`; `normalizeCashMethod('cash') → 'cash'` (`cashService.ts:67`), posted to GL `1000` (`accountingService.ts:807`). The till default: the POS hardcodes it (`posController.ts:152`). |
| **bank** | Any bank-like instrument — `bank\|cheque\|check\|card\|transfer\|online\|raast` normalizes to `'bank'` (`cashService.ts:74`), posted to GL `1010` (`accountingService.ts:813`, the fall-through branch). Covers `Bank Transfer`, `Check`, `Credit Card`, `Online Payment`. |
| **Easypaisa** | Mobile wallet method; normalizes to `'easypaisa'`, posted to GL `1020` (`cashService.ts:69`, `accountingService.ts:809`). |
| **JazzCash** | Mobile wallet method; `jazzcash` **or** `jazz` normalizes to `'jazzcash'`, posted to GL `1030` (`cashService.ts:70`, `accountingService.ts:810`). |
| **UPaisa** | Mobile wallet method; normalizes to `'upaisa'`, posted to GL `1040` (`cashService.ts:71`, `accountingService.ts:811`). |
| **split payments** | One invoice settled by ≥ 2 payment legs (different methods and/or amounts) inside a single request: one `payments` row + one `payment_allocations` row per leg, each leg posted Dr its own cash account / Cr `1100`. `payment_allocations` has no `UNIQUE(invoice_id)` (`create-payment-allocations.sql`), so multiple payments per invoice are already supported. |
| **discount** | A price reduction applied **before tax**. Item scope: per-line `invoice_items.discount_type/discount_value`, folded into the line inside `decomposeLineAmount` (`currency.ts:54`). Invoice scope: header `invoices.discount_scope='invoice'` subtracted from Σ line grosses by `computeInvoiceGrandTotal` (`currency.ts:130-155`). A discount never becomes a GL line — it shrinks revenue (`4000`). |
| **tax** | Percentage on the **net** line (`invoice_items.tax_rate` → `taxAmount` in `decomposeLineAmount`), stored as `invoice_items.tax_amount` (`Invoice.ts:792-810`), summed by `getInvoiceTaxTotal` (`Invoice.ts:819-825`), posted Cr `2100 Tax Payable` when the invoice is created (`accountingService.ts:494-510`). |
| **change** | Cash handed back by the till: `cash_tendered − cash actually applied`. Display-only — it is never a payment, never stored, never posted (`pos_screen.dart:503` computes it client-side today). |
| **customer** | The receivable counterparty in `customers`. POS sales attach to the shared `WALK-IN` row, find-or-create by `customer_code='WALK-IN'` (`posController.ts:23-38`); a real `customer_id` routes AR, `customer_ledger`, aging and credit to that customer. |
| **credit** | A sale not fully paid at the till: `balance_amount > 0`, status `Unpaid`/`Partially Paid`, money left standing in `1100 AR` until a later settlement. Distinct from *store credit* (`credit_offset` / `customers.credit_balance`, GL `1110`), which is a separate, already-built mechanism. |

### 1.2 Facts

| Fact | Evidence |
|---|---|
| `POST /api/pos/sale` = `pos:create` permission + zod `posSale` | `routes/pos.ts:10` |
| zod `posSale` validates **only** `warehouse_id` + `items: z.array(z.any()).min(1)`, then `.passthrough()` — every other field (discount, tax, payment) is unvalidated free text | `validation.ts:174-177` |
| Controller computes the total with `computeInvoiceTotal(body.items)` — **line amounts only, header discount ignored** | `posController.ts:122`, `currency.ts:108` |
| Service independently recomputes with `computeInvoiceGrandTotal(...)` (header discount included) and throws `InvoiceCreationTotalMismatchError` if `input.totalAmount` differs by > 0.01 | `InvoiceCreationService.ts:83-89` |
| Controller catch maps only `SellableStockUnavailableError` → 400, `InvoiceCreationPaymentMethodError` → 400, `InvoiceCreationIdempotencyError` → 409 — **everything else → 500** | `posController.ts:166-182` |
| Cash guard: `cashReceived < total` → 400 `Insufficient cash` — blocks partial payment and credit outright | `posController.ts:123-127` |
| `cash_received` defaults via `parseFloat(...) \|\| total` — **explicit `0` also becomes `total`** (0 is falsy) | `posController.ts:123`, replay at `posController.ts:65` |
| `status: 'Paid'` is hardcoded into the service input, overriding the service's own derivation | `posController.ts:146`; derivation at `InvoiceCreationService.ts:104` |
| `payment_method: 'Cash'` is hardcoded; only one leg is ever possible | `posController.ts:152` |
| Customer forced to walk-in; `customer_name` is cosmetic only — no `customer_id` passthrough | `posController.ts:137-143` |
| `InvoiceCreationService.create` contains **zero** period asserts — a POS invoice can post GL entries dated in a closed period | grep `assertPeriod` in `InvoiceCreationService.ts` = 0 hits; posting at `InvoiceCreationService.ts:197` |
| Payment legs **are** period-guarded: `assertPeriodOpen(db, paymentDate)` throws a plain `Error` | `PaymentRecordingService.ts:39`, `paymentWriterCore.ts:30-31` (H6 comment at :29) |
| That plain error falls into the POS catch-all → **500**, while `invoiceController` maps `'inside closed accounting period'` → 409 | `posController.ts:179-181` vs `invoiceController.ts:627-628, 732-733, 940-941` |
| Idempotent replay rebuilds `line_total` as `quantity * unit_price` — ignores stored `amount` (which is the tax- and discount-inclusive server line total) | `posController.ts:56`; stored amount semantics `Invoice.ts:785-793` |
| Replay also returns `subtotal: total` and `change: cashReceived - total` — no discount/tax breakdown | `posController.ts:75-78` |
| The service already accepts everything needed: per-line `tax_rate/discount_type/discount_value`, header `discountScope/discountType/discountValue`, `totalAmount`, `recordPayment`, `payment`, `creditOffset`, typed error classes for mismatch/offset/credit/method/idempotency | `invoiceCreationTypes.ts` (`InvoiceCreationInput`), `InvoiceCreationService.ts:17-50` |
| Leg recording already exists: `PaymentRecordingService.recordCustomerPayment` validates the method, asserts the period, inserts the payment, allocates it, refreshes `paid_amount`/`balance_amount`/status, and posts Dr cash-per-method / Cr `1100` — all inside one transaction | `PaymentRecordingService.ts:33-58, 96-113, 182`; posting `accountingService.ts:532-570` |
| Invoice posting already splits tax: Dr `1100` total / Cr `4000` net / Cr `2100` tax | `accountingService.ts:472-524`, called from `InvoiceCreationService.ts:197` |
| `_cashOrBankAccountCode` maps all five money methods (and any bank-like string) correctly | `accountingService.ts:804-814` |
| Server method whitelist for payments: `'use Cash, Bank, Easypaisa, JazzCash or Upaisa'` — enforced by `assertPaymentMethod` → 400 via existing mapping | `paymentValidation.ts:16-17`, `paymentWriterCore.ts:23-26`, `posController.ts:171-174` |
| Flutter's POS payload sends only `warehouse_id, sale_date, items(item_id, quantity, unit_price), cash_received, customer_name` | `pos_screen.dart:266-276` |
| Flutter POS blocks `cashReceived < _subtotal` client-side too | `pos_screen.dart:240` |
| Flutter invoice form **already** sends `discount_scope/type/value`, per-line `tax_rate/discount_*`, `total_amount` (via `calculateTotal`), `record_payment`, `credit_offset` — the contract this design must mirror | `sales_invoice_form_page.dart:916-945`, `invoice_calculations.dart:122-130` |
| Flutter payment panel already exposes 8 methods: Cash, Bank Transfer, Easypaisa, JazzCash, UPaisa, Check, Credit Card, Online Payment — all pass `isValidPaymentMethod` | `payment_panel.dart:23-32`, `cashService.ts:78-82` |
| Every schema piece already exists: `invoices.discount_scope/type/value`, `invoice_items.tax_rate/discount_type/discount_value/net_amount/tax_amount`, `payments` XOR counterparty check, `payment_allocations`, `tax_rates` table with 0/5/10/15/20 seeds | `add-invoice-discount-tax-fields.sql:4-6,10-12`, `add-invoice-item-tax-columns.sql:5`, `add-payments-counterparty-check.sql:29`, `create-payment-allocations.sql`, `add-mobile-invoice-tables.sql:36,48-66` |
| `tax_rates` is readable today only via the deprecated mobile route under `invoices:read` — no `pos:read`-permissioned endpoint | `MobileInvoice.ts:162-166`, `mobileInvoices.ts:28` |
| `getPOSTransactions` already returns `paid_amount` and `balance_amount` — credit sales are listable with no query change | `posController.ts:199-201` |
| Reconciliation invariants: AR `1100` ← Σ open `balance_amount`; AP `2000` ← Σ `supplier_ledger`; Cash family ← per-method payment sums + openings; method→GL map | `Reports.ts:1240-1244, 1311, 1318, 1324` |
| No dedicated POS test file exists; POS-adjacent paths ride on `glPostingMatrix`, `invoiceCreationMatrix`, `invoiceIdempotency` | grep for `pos/sale` in `src/__tests__/` → those three files only |
| Idempotency scope `pos_sale` + `hashRequestPayload(req.body)` — new body fields are hashed automatically, no key changes needed | `idempotency.ts:18`, `posController.ts:153-155` |

---

## 2. The blocking finding

The POS is not merely missing features — three of its current shortcuts would
**actively corrupt or 500** the moment discount/tax/split support is bolted on:

1. **Two different totals.** The controller validates and stores
   `computeInvoiceTotal(items)` (`posController.ts:122`) while the service
   revalidates against `computeInvoiceGrandTotal(items, header)`
   (`InvoiceCreationService.ts:83-89`). The instant a client sends a header
   discount, `input.totalAmount !== recomputed` → `InvoiceCreationTotalMismatchError`
   → the POS catch has no branch for it → **HTTP 500** on an otherwise valid sale.
2. **Hardcoded paid + hardcoded Cash + cash guard.** `status: 'Paid'`
   (`posController.ts:146`), `payment_method: 'Cash'` (`:152`) and the
   `cashReceived < total → 400` guard (`:124-127`) make every non-cash method, every
   split, every partial payment and every credit sale unreachable — the request is
   rejected before the service ever runs. The same guard blocks Flutter's own
   `cashReceived < _subtotal` (`pos_screen.dart:240`).
3. **Closed-period hole on creation.** Payment legs run `assertPeriodOpen`
   (`PaymentRecordingService.ts:39`), but invoice creation has **no** period guard
   (`InvoiceCreationService.ts` contains zero `assertPeriod*` calls) — a credit sale
   dated in a closed period would post a brand-new GL entry into that period,
   violating H6 (*"a closed period must not gain new money movements"*,
   `paymentWriterCore.ts:29`). And when the payment-leg guard does fire, its plain
   `Error` reaches the POS catch-all → **500**, not the **409** the invoice
   controller returns for the same condition (`invoiceController.ts:627-628`).

Two more defects surface once those are cleared:

4. **Untyped 500s for known failures.** `InvoiceCreationTotalMismatchError`,
   `InvoiceCreationOffsetError`, `InvoiceCreationCreditError` all fall through to 500
   (`posController.ts:179-181`) although they are deterministic client errors →
   must be 400.
5. **Replay lies about money.** The idempotent replay recomputes `line_total` as
   `quantity * unit_price` (`posController.ts:56`) instead of reading the stored
   server-computed `amount`, and returns `subtotal: total` (`:75`) — with discount
   and tax in play, a replayed response would not match the original response, which
   is exactly what P11 idempotency promises (`posController.ts:41-47`).

This is why the task says *specification first*: opening the zod schema and the cash
guard without fixing (1) turns every discounted sale into a 500.

---

## 3. The central design decision

**The POS controller becomes a thin adapter over the two services that already exist
— `InvoiceCreationService.create` and `PaymentRecordingService.recordCustomerPayment`.
No new GL code, no new posting path, no new tables.**

Everything the POS needs is already implemented and already tested — the controller's
job shrinks to *translating its request into the invoice-form contract*: forward the
discount/tax/customer fields it currently drops, compute the total with
`computeInvoiceGrandTotal`, record N legs instead of one hardcoded Cash leg, and map
the service's typed errors to 400/409.

### 3.1 The two candidate routes

| | **A — extend `InvoiceCreationInput` with `payments[]`** (recommended) | **B — leg 1 via `input.payment`, legs 2..n via `afterCreate`** |
|---|---|---|
| Contract change | one new **optional** field `payments?: readonly InvoiceCreationPayment[]` | none — reuses the existing `afterCreate` hook (`invoiceCreationTypes.ts:53`) |
| Validation | inside the service, **before** the transaction, mirroring the existing `paymentAmount + creditOffset > total` check (`InvoiceCreationService.ts:97-98`) → typed `OffsetError`/`PaymentMethodError` → 400 | in the controller, before `service.create` → must hand-roll the same sums, or discover the breach mid-transaction (allocation cap at `PaymentRecordingService.ts:84,115`) as a **plain Error → 500** |
| `paid_amount` / status at insert | correct on the first write — `paidAmount = Σ legs + creditOffset` feeds the insert and the status derivation (`InvoiceCreationService.ts:102-104`) | written from leg 1 only, then fixed up later by `calculateInvoiceBalance` + `updateInvoiceStatus` (`PaymentRecordingService.ts:110-111`) — correct after commit, transiently wrong inside the transaction |
| Where the accounting lives | entirely inside the service (one orchestration point) | split: service records leg 1, **controller callback** orchestrates legs 2..n |
| Atomicity | one `db.transaction` (`InvoiceCreationService.ts:107`) | also atomic — `afterCreate` runs inside that same transaction (`:226`) |
| Risk to other callers | none if the field stays optional: invoice form, mobile and sales-order paths omit it and execute byte-identical code | none |
| Risk to this change | touches the shared service (all callers re-run its test matrix) | misses pre-transaction validation; error mapping must string-match plain `Error`s |

**Recommendation: Route A.** The task's constraint — *reuse the main invoice/payment
service rather than creating another accounting path* — is best honoured by making
the service the single owner of split-payment validation and orchestration. Route B
technically reuses `PaymentRecordingService`, but it relocates payment-loop logic
into a controller-supplied callback and can only fail *after* the invoice row exists
(as a 500 instead of a clean 400). Route A's blast radius is contained by keeping
`payments` optional and by the additive-only change to the pre-transaction checks.

Under Route A the payment recording block at `InvoiceCreationService.ts:200-215`
generalizes from "one payment" to "for each leg": when `payments` is absent the loop
has exactly one iteration (the legacy `payment` field), so existing callers are
unchanged.

### 3.2 Why this mirrors tasks 43–45 — and where it diverges

Same shape as supplier prepayments (43), customer store credit (44) and expense
payables (45): identify the existing posting primitives, extend validation, map
errors to the right status codes, keep the reconciliation invariants the reports
already assert. It diverges in that **this change needs no schema at all** — every
column and table already exists (§4) — and no new GL account; the whole surface is
controller + service-contract + Flutter.

---

## 4. Data model (proposed — not created)

**Zero migrations.** This is purely a request-contract change.

### 4.1 Proposed `posSale` zod schema (`validation.ts:174-177`)

```ts
posSale: z.object({
  warehouse_id: z.union([z.number(), z.string()]).refine(v => String(v).length > 0, { message: 'Required' }),
  sale_date: z.string().min(1),
  items: z.array(z.object({
    item_id: z.number().int().positive(),
    quantity: z.number().positive(),
    unit_price: z.number().min(0),
    tax_rate: z.number().min(0).max(100).optional(),
    discount_type: z.enum(['none', 'percentage', 'flat']).optional(),
    discount_value: z.number().min(0).optional(),
  })).min(1),
  customer_id: z.number().int().positive().optional(),
  customer_name: z.string().optional(),
  discount_scope: z.enum(['item', 'invoice']).optional(),
  discount_type: z.enum(['flat', 'percentage']).optional(),
  discount_value: z.number().min(0).optional(),
  total_amount: z.number().optional(),          // validated against server total (ACC-18 pattern)
  cash_received: z.number().min(0).optional(),  // legacy field — see §6
  payments: z.array(z.object({
    amount: z.number().positive(),
    payment_method: z.string(),
    payment_date: z.string().optional(),        // defaults to sale_date
  })).max(10).optional(),
}).passthrough(),
```

- `items` moves off `z.any()` — the invoice form's line contract, typed.
- `.passthrough()` **stays** until the Flutter client ships the new fields (§10.7).

### 4.2 `InvoiceCreationInput` gains one optional field (`invoiceCreationTypes.ts`)

```ts
readonly payments?: readonly InvoiceCreationPayment[];   // N legs; absent ⇒ legacy `payment` field
```

`InvoiceCreationPayment` (`invoiceCreationTypes.ts:16-22`) already carries
`amount / payment_date / payment_method / reference_no / notes`.

### 4.3 Existing tables consumed, unchanged

| Table | Columns used | Migration evidence |
|---|---|---|
| `invoices` | `discount_scope`, `discount_type`, `discount_value`, `paid_amount`, `balance_amount`, `status` | `add-invoice-discount-tax-fields.sql:4-6` |
| `invoice_items` | `tax_rate`, `discount_type`, `discount_value`, `net_amount`, `tax_amount`, `amount` | `add-invoice-discount-tax-fields.sql:10-12`, `add-invoice-item-tax-columns.sql:5` |
| `payments` | `customer_id`, `payment_date`, `amount`, `payment_method` (XOR counterparty check satisfied — POS always has a customer) | `add-payments-counterparty-check.sql:29` |
| `payment_allocations` | one row per leg per invoice (no `UNIQUE(invoice_id)` → multi-payment supported) | `create-payment-allocations.sql` |
| `tax_rates` | preset selector source (`name, rate, is_default`) | `add-mobile-invoice-tables.sql:36,48-66` |

### 4.4 New endpoint (no table)

`GET /api/pos/tax-rates` under `requirePermission('pos', 'read')`, reusing the query
already written in `MobileInvoice.getTaxRates` (`MobileInvoice.ts:162-166`). The
existing mobile route stays behind `invoices:read` (`mobileInvoices.ts:28`).

---

## 5. GL postings

All postings below are produced by **existing** code; the design only decides *when*
each runs.

### 5.1 Sale invoice — every POS sale (unchanged path)

| | Account | Amount |
|---|---|---|
| Dr | `1100` Accounts Receivable | `total` (after line discounts, header discount, + tax) |
| Cr | `4000` Sales Revenue | `total − tax` |
| Cr | `2100` Tax Payable | `tax` (only when `tax > 0`) |

`accountingService.ts:472-524`, invoked at `InvoiceCreationService.ts:197` with
`taxAmount = getInvoiceTaxTotal(...)`. A discount simply shrinks `4000` — **no
discount account, no discount line**.

### 5.2 Payment legs — one entry per leg, method decides the debit

| Leg | | Account | Amount |
|---|---|---|---|
| Cash leg | Dr | `1000` | leg amount |
| Bank-like leg | Dr | `1010` | leg amount |
| Easypaisa leg | Dr | `1020` | leg amount |
| JazzCash leg | Dr | `1030` | leg amount |
| UPaisa leg | Dr | `1040` | leg amount |
| (every leg) | Cr | `1100` Accounts Receivable | leg amount |

`accountingService.ts:532-570` via `PaymentRecordingService` (method chosen by
`_cashOrBankAccountCode`, `accountingService.ts:804-814`).

**Worked example — split sale.** Invoice total 110 (net 100 + tax 10), settled
60 Cash + 50 Easypaisa:

| Entry | Dr | Cr |
|---|---|---|
| INVOICE | `1100` 110 | `4000` 100, `2100` 10 |
| PAYMENT #1 | `1000` 60 | `1100` 60 |
| PAYMENT #2 | `1020` 50 | `1100` 50 |

After commit: AR for this invoice = 0, status `Paid`, cash family +60/+50.

### 5.3 Credit sale (no legs, or Σ legs < total)

Only the §5.1 entry. The unpaid remainder **stays** as the invoice's
`balance_amount` inside `1100` — no liability account, no accrual entry. Settlement
later is an ordinary customer payment against that invoice (the existing
`PaymentRecordingService` flow, which the invoice form already drives).

### 5.4 Change — never posted

Cash tendered 200 on a total of 110: one Cash leg of **110** is recorded (§5.2), the
**90 change is display-only** (§1.1). It never appears in `payments`, never touches
GL, never enters `collectFlows`.

### 5.5 Store-credit offset — existing behavior, optional passthrough

If `credit_offset` is forwarded (§10.4): Dr `1110` / Cr `1100` via
`postCreditOffsetEntry` (`InvoiceCreationService.ts:218`) plus the pool ledger row
(`:223`) — byte-identical to the invoice form's path today.

---

## 6. Business rules

| Rule | Enforcement |
|---|---|
| **Payload duality:** `payments` present (array, may be `[]`) ⇒ new semantics (legs, credit allowed, no cash guard). `payments` absent ⇒ legacy payload, byte-for-byte current behaviour incl. the cash guard. | adapter branch in `posController.ts` |
| `Σ legs + creditOffset ≤ total + 0.01`, else 400 | pre-transaction in the service, generalizing `InvoiceCreationService.ts:97-98` → `InvoiceCreationOffsetError` → mapped 400 |
| Every leg: `amount > 0` (zod) and `isValidPaymentMethod(payment_method)`, else 400 | zod §4.1 + `InvoiceCreationPaymentMethodError` on each leg (pattern `InvoiceCreationService.ts:95-96`) |
| Each leg recorded through `PaymentRecordingService.recordCustomerPayment` — method whitelist, period guard, allocation, status refresh, GL posting | `PaymentRecordingService.ts:33-58` (no new code) |
| Leg `payment_date` defaults to `sale_date` | adapter fills it before calling the service |
| **`status` is never client-sent and never hardcoded** — derived from `paidAmount` vs `total` | remove `posController.ts:146`; service derives at `InvoiceCreationService.ts:104` |
| Full settlement ⇒ `Paid`; partial ⇒ `Partially Paid`; Σ legs = 0 ⇒ `Unpaid` | `InvoiceCreationService.ts:104`, refreshed per allocation at `PaymentRecordingService.ts:110-111` |
| Total computed by `computeInvoiceGrandTotal(items, header)` in the controller — **the same function the service validates against** | replace `posController.ts:122` |
| `total_amount` (if sent) must match the server total within 0.01, else 400 | ACC-18 pattern, `InvoiceCreationService.ts:88-89` → `TotalMismatchError` → mapped 400 |
| Header discount clamped to the line grosses (never negative) | `currency.ts:152-154` (`Math.min(discount, linesTotal)`) |
| Customer: `customer_id` optional; absent ⇒ `ensureWalkinCustomer()` + `customer_name` fallback | `posController.ts:137, 84-87` |
| Legacy `cash_received` coercion (`\|\| total`, including explicit `0`) is **preserved** in the legacy branch — old clients cannot silently flip to credit | `posController.ts:123` |
| `change = max(0, cash_received − cash-leg amount)`, display only; 0 when no Cash leg | §5.4; client display `pos_screen.dart:502-503` |
| Idempotency: `POS_SALE_SCOPE` + `hashRequestPayload(req.body)` unchanged — new fields are inside the hash | `idempotency.ts:18`, `posController.ts:153-155` |
| Replay must reproduce the original response **byte-for-byte**: `line_total` = stored `ii.amount`, header discount/tax/legs echoed from the request + stored invoice | fix `posController.ts:56, 75-78` |
| Every new error class maps to a client status code — no fall-through 500s for deterministic failures | §6.2 |
| Cash invariants after every row | `Reports.ts:1318` (cash GL == flows), `Reports.ts:1311` (AP), `Reports.ts:1242` (AR) |

### 6.1 Closed-period policy — the subtle one

H6 (*"a closed period must not gain new money movements, only lose them"*,
`paymentWriterCore.ts:29`) resolves as follows.

| Action | Date used for the guard | Verdict |
|---|---|---|
| POS invoice creation, any status (incl. credit sale) | `sale_date` | **blocked → 409** — *currently unguarded*; a new INVOICE entry dated in a closed period gains a movement. Add a pre-check via `AccountingService.getClosedPeriodCovering` (`accountingService.ts:973`) before `service.create`. |
| Payment legs (any method, incl. split legs 2..n) | leg `payment_date` (default `sale_date`) | **blocked** by `assertPeriodOpen` (`PaymentRecordingService.ts:39`) — already enforced; must be **mapped to 409**, not 500 |
| Legacy full-cash POS sale today | — | **currently unguarded** — pre-existing hole this design closes |
| Refund / void / return of a POS sale | existing invoice rules | unchanged — out of scope here |

Fail fast with the pre-check (clear 409 *before* any write) and keep a catch-arm on
`'inside closed accounting period'` → 409 as the backstop, exactly mirroring
`invoiceController.ts:627-628`.

### 6.2 Error mapping additions (`posController.ts:166-182`)

| Error | Status | Precedent |
|---|---|---|
| `SellableStockUnavailableError` | 400 | existing |
| `InvoiceCreationPaymentMethodError` | 400 | existing |
| `InvoiceCreationIdempotencyError` | 409 | existing |
| `InvoiceCreationTotalMismatchError` (**new arm**) | 400 | client sent a wrong total |
| `InvoiceCreationOffsetError` (**new arm**) | 400 | Σ legs + offset > total |
| `InvoiceCreationCreditError` (**new arm**) | 400 | offset exceeds customer pool |
| message contains `'inside closed accounting period'` (**new arm**) | 409 | `invoiceController.ts:627-628` |
| everything else | 500 | genuine server fault |

---

## 7. Reporting impact

| Report | Required change |
|---|---|
| Cash reconciliation / cash flow (`Reports.ts:1244, 1318, 1324`) | **None** — every leg is already a `payments` row with its own `payment_method`; `collectFlows` (`cashService.ts:104`) and the method→GL map pick up Cash/Bank/Easypaisa/JazzCash/UPaisa legs automatically. This is the invariant §9 protects. |
| GL reconciliation doc block (`Reports.ts:1240-1244`) | **None** — AR ← Σ open `balance_amount` already counts credit POS sales; AP untouched. |
| AP reconciliation (`Reports.ts:1311`) | **None** — POS never writes `supplier_ledger` or `2000`. |
| Balance sheet / tax report (`2100 Tax Payable`) | **None** — tax posts at invoice creation through the existing `getInvoiceTaxTotal` path. |
| P&L (`4000 Sales Revenue`) | **None** — revenue is already recorded net of discount and tax. |
| POS transactions endpoint (`posController.ts:192-228`) | **Optional:** expose per-invoice payment methods (join `payments`/`payment_allocations`) so the list can badge split/credit sales. `paid_amount`/`balance_amount` are already returned — credit sales are visible today. |
| Dashboard | **None** — it consumes the invariants above. |

---

## 8. UI specification

**POS screen (`pos_screen.dart`)**

- **Payment section** — method selector seeded from `kPaymentMethods`
  (`payment_panel.dart:23-32`), plus an **`Add payment`** row: each leg shows method
  + amount; a running `Remaining = total − Σ legs` badge. A single leg is just the
  default state (back-compat with today's screen).
- **Cash & change** — `Cash tendered` field visible when a Cash leg exists;
  `Change = tendered − cash leg` computed exactly as today (`pos_screen.dart:503`)
  but against the **cash leg**, not the invoice total.
- **Discount** — header discount control (`flat` / `%`) posting
  `discount_scope='invoice'`, mirroring the invoice form
  (`sales_invoice_form_page.dart:920-925`). Per-line discount/tax columns: out of
  scope for the first cut (§10.7) — items still send no `tax_rate` ⇒ identical
  numbers to today.
- **Tax** — preset chips (0/5/10/15/20) from `GET /pos/tax-rates` (§4.4); selection
  fans out `tax_rate` to the lines (or a future invoice-scope field — §10.7).
- **Customer** — search-and-select, defaulting to `Walk-in Customer`; sends
  `customer_id` when chosen, `customer_name` for display otherwise.
- **Credit toggle** — `Charge later` switch: sends `payments: []` (or legs with
  Σ < total); the cash guard disappears for this payload (§6). Receipt and list badge
  show `Unpaid` / `Partially Paid` with the balance.
- **Remove** the client-side `cashReceived < _subtotal` block (`pos_screen.dart:240`)
  — it is superseded by server-side validation; keeping it would deadlock credit
  sales.

**Transaction list** — unchanged columns, plus optional method badges (§7).
**Receipt / replay** — items show the stored server `amount` (tax- and
discount-inclusive), header discount and tax lines, `subtotal → total` chain, legs
and change, byte-identical on idempotent retry.

---

## 9. Regression matrix

| # | Scenario | GL | Invariants |
|---|---|---|---|
| R1 | Legacy payload: full cash sale (no new fields) | Dr `1000` total / Cr `1100` total (+ invoice entry) | identical to today; cash reconciles |
| R2 | Legacy payload: `cash_received < total` | no entries | still 400 `Insufficient cash` |
| R3 | New payload: single Cash leg, full amount | Dr `1000` / Cr `1100` | status `Paid` (derived, not sent) |
| R4 | Single Easypaisa / JazzCash / UPaisa / Bank leg | Dr `1020`/`1030`/`1040`/`1010` | method→GL map `Reports.ts:1324` |
| R5 | Split: 60 Cash + 50 Easypaisa on 110 | invoice + 2 payment entries (§5.2) | AR = 0; `collectFlows` +60 cash +50 easypaisa; `Reports.ts:1318` holds |
| R6 | Split 3 legs, Σ = total | 3 payment entries | status `Paid` after final allocation |
| R7 | Σ legs > total + 0.01 | **no entries** | 400 `OffsetError` — pre-transaction |
| R8 | Leg with amount ≤ 0 or unknown method | **no entries** | 400 (zod / `PaymentMethodError`) |
| R9 | `payments: []` (credit sale) | invoice entry only | status `Unpaid`; `balance_amount = total`; AR invariant counts it |
| R10 | Legs Σ < total (partial) | invoice + partial payments | status `Partially Paid`; balance = remainder |
| R11 | Header discount invoice-scope | invoice entry on discounted total | `total_amount` matches `computeInvoiceGrandTotal` — **no TotalMismatch 500** |
| R12 | Discount larger than grosses | invoice entry at ≥ 0 | clamped, `currency.ts:152-154` |
| R13 | Tax rate 15% on net 100 | Dr `1100` 115 / Cr `4000` 100 / Cr `2100` 15 | `tax_reporting` matrix holds |
| R14 | Discount **and** tax combined | revenue = net-of-both; tax on discounted net | `sumInvoiceLineTax` = stored `tax_amount` |
| R15 | `customer_id` sent (real customer) | entry against that customer | `customer_ledger` + AR aging include it |
| R16 | No `customer_id` | walk-in row reused | single `WALK-IN` row, no duplicates |
| R17 | Closed-period `sale_date` (incl. credit sale) | **no entries** | 409 from pre-check — H6 |
| R18 | Leg `payment_date` inside closed period | **no entries** | `assertPeriodOpen` → mapped 409, not 500 |
| R19 | Duplicate POST, same Idempotency-Key, same body | one set of entries | replayed response byte-identical (R20) |
| R20 | Replay after discount/tax/split sale | n/a | `line_total` = stored `amount`; legs/echoed fields match original |
| R21 | `total_amount` sent but wrong (>0.01 off) | **no entries** | 400 `TotalMismatchError` |
| R22 | Known failure paths never 500 | n/a | error table §6.2 |
| R23 | `AP(2000) == Σ supplier_ledger` after any POS sale | untouched | `Reports.ts:1311` |
| R24 | Cash GL == `collectFlows` after mixed methods | per-method legs | `Reports.ts:1318` |
| R25 | `status` never client-sent | n/a | service derivation wins (`InvoiceCreationService.ts:104`) |

---

## 10. Open decisions requiring sign-off

### As approved (2026-10-01)

All eight were reviewed one at a time and approved as recommended. Status shows
what actually shipped.

| # | Decision | Approved | Shipped |
|---|---|---|---|
| 10.1 | Route A vs Route B | **Route A** | Yes — `InvoiceCreationInput.payments`, one `recordCustomerPayment` call per leg |
| 10.2 | Closed-period guard on creation | **Add it** | Yes — `getClosedPeriodCovering` pre-check → 409, plus a message-based catch-arm as backstop |
| 10.3 | Legacy `cash_received` coercion | **Preserve** | Yes — legacy branch keeps `parseFloat(x) \|\| total` *and* the cash guard; the legs branch never reads the field |
| 10.4 | Store-credit offset at the POS | **Deferred** | No — out of scope for v1 |
| 10.5 | Tax-presets endpoint permission | **New `GET /pos/tax-rates` under `pos:read`** | Yes — mobile route untouched behind `invoices:read` |
| 10.6 | Replay `line_total` from stored `amount` | **Accept as a bug fix** | Yes — and legs are read back from `payment_allocations` rather than echoed from the request |
| 10.7 | Per-line discount/tax + `z.strict` | **Both deferred** | No — `posSale` keeps `.passthrough()`; per-line discount/tax is a follow-up once Flutter ships those header fields |
| 10.8 | Payment methods offered | **All 8, no filtering** | Yes — server already accepted all 8 via the bank fall-through; no whitelist was narrowed |

**Consequence of 10.3 worth keeping in view:** because the coercion is preserved on
the legacy branch only, the two payload shapes keep different behaviour for blank or
zero cash. That is deliberate, and it is also exactly why 10.4 was deferred — a
future credit-only POS sale has no cash tendered at all, which is the case that
coercion would mask. Revisit 10.3 before adding credit at the till.

1. **Route A vs Route B** (§3.1). Recommendation: **Route A** — service-owned
   `payments[]` with pre-transaction validation. Alternative B (zero contract change
   via `afterCreate`) fails later and dirtier (500s, transient status).
2. **Closed-period guard on POS creation** (§6.1). Recommendation: **add it**
   (`getClosedPeriodCovering` pre-check → 409). Alternative: leave creation
   unguarded as today — rejected, it violates H6 for credit sales and is the audit's
   own finding.
3. **Legacy `cash_received` coercion** (`0 → total` via `||`). Recommendation:
   **preserve** it inside the legacy branch (§6) so old clients cannot silently
   become credit sales; the new branch ignores `cash_received` entirely. Alternative:
   treat explicit `0` as "no cash" — rejected as a silent semantics change.
4. **Store-credit offset (`credit_offset`) at the POS.** Recommendation: **out of
   scope for v1** — the service already supports the passthrough
   (`InvoiceCreationService.ts:122,218`); add UI later if the business wants it at
   the till.
5. **Tax presets endpoint permission.** Recommendation: new `GET /pos/tax-rates`
   under `pos:read` (§4.4). Alternative: reuse the mobile route under `invoices:read`
   — rejected, POS operators should not need invoice-read permission.
6. **Replay response shape** — fixing `line_total` to the stored `amount`
   (`posController.ts:56`) changes the response only where numbers already differed
   (discounted/taxed lines); legacy sales are byte-identical (`qty × price` with 0
   tax/discount stores exactly that). Recommendation: accept the fix as a bug fix.
7. **Per-line discount/tax at the POS** and tightening `posSale` to `z.strict`
   (dropping `.passthrough()`). Recommendation: **both deferred** until the Flutter
   POS ships the header fields — then tighten in a follow-up (§4.1).
8. **Payment methods offered at the POS** — Flutter lists 8
   (`payment_panel.dart:23-32`); server accepts them all via the bank fall-through
   (`cashService.ts:74`). Recommendation: offer all 8, no filtering.

---

## 11. Implementation record

Implemented 2026-10-01 in the order the plan set out. Steps 1–5 shipped; step 6
shipped in part; step 7 is the regression suite.

| Step | Status | Notes |
|---|---|---|
| 1. Service (Route A) | **Done** | `payments[]` added to `InvoiceCreationInput`; validation generalized to Σ legs with a per-leg method check. The leg sum uses `addCurrency`, not `+=` — summing several 2dp legs in floating point can land a cent low and flip a fully-settled invoice to `Partially Paid` |
| 2. Controller adapter | **Done** | Forwards `discount_*`, per-line `tax_rate`, `customer_id` and `payments`; total switched to `computeInvoiceGrandTotal`; `status: 'Paid'` removed so the service derives it; closed-period pre-check and the §6.2 error arms added |
| 3. Replay | **Done** | `line_total` reads `ii.amount`; legs are read back from `payment_allocations` so the replay is server-authoritative |
| 4. zod schema | **Done** | `items` moved off `z.any()` to the typed line contract; `.passthrough()` retained per 10.7 |
| 5. `GET /pos/tax-rates` | **Done** | Reuses the existing `tax_rates` query; registered under `pos:read` |
| 6. Flutter | **Partial** | Payment legs, charge-later, invoice-scope discount, tax preset chips and `customer_id` shipped; the client-side `cashReceived < _subtotal` block was removed because it would deadlock a charge-later sale. Per-line discount/tax columns are 10.7's follow-up |
| 7. Tests | **Done** | 20 tests in `posPayments.test.ts` covering R1–R13, R16–R21 and R25 |

**Verification:** server 108 suites / 926 tests, reversal gate 79/0, typecheck
clean, eslint 0 errors, `flutter analyze` clean, `flutter test` 773 passed.

### Behaviour notes for whoever picks this up

- **`status` for a partial sale.** POS sets `due_date = sale_date`, so a dated sale
  becomes `Overdue` once its day passes rather than staying `Partially Paid`. That
  is the existing overdue rule working, not a POS bug — the test asserts the
  settlement split and accepts either word deliberately.
- **`change` is display-only** and is computed against the cash leg, never posted.
  A credit sale has no cash leg, so change is 0.
- **Credit at the till is still not available** (10.4). The `Charge later` switch
  sends `payments: []`, which is a sale on account, not a store-credit offset.
