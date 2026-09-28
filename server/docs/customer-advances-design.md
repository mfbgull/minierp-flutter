# Customer advances / deposits — technical specification

Status: **DESIGN ONLY — NOT IMPLEMENTED.**

Audit task 43 explicitly requires a specification and regression matrix *before*
any implementation. Nothing in this document has been built. Every claim about
current behaviour below was verified against the code, with file references.

---

## 1. Verified current state

| Fact | Evidence |
|---|---|
| Accounts receivable is `1100` | `accountingService.ts` — `getAccountByCode(db, '1100')` |
| `1110 Customer Credit` exists as **asset / credit** (contra-asset) | `src/migrations/add-customer-credit-account.sql` |
| `1110` is consumed by credit offset: **Dr 1110 / Cr 1100** | `accountingService.ts:572` `postCreditOffsetEntry` |
| `customers.credit_balance` is the pool, decremented on invoice create | `InvoiceCreationService.ts` (`UPDATE customers SET credit_balance = MAX(0, credit_balance - ?)`) |
| `customer_ledger.transaction_type` is `VARCHAR(50)` with **no CHECK constraint** | `src/migrations/create-customer-ledger.sql:8` |
| Ledger types in use: `INVOICE, PAYMENT, RETURN, CREDIT_NOTE, CREDIT_NOTE_VOID, REFUND, CANCELLATION, SUPPLIER_REFUND(_VOID), PURCHASE, GOODS_RECEIPT, PURCHASE_ORDER` | grep across `src/` |
| Payment modes: `RECEIPT, INVOICE_SETTLEMENT, CREDIT_APPLICATION, REFUND` | `paymentRecordingTypes.ts:11` |
| `CREDIT_APPLICATION` already applies a credit pool with **no cash and no ledger row**, only Dr 1110 / Cr 1100 | `PaymentRecordingService.ts:142` |
| Cash accounts: `1010` bank, `1020` Easypaisa, `1030` JazzCash, `1040` UPaisa | `add-cash-accounts.sql`, `_cashOrBankAccountCode` |
| Closed-period rule: *"a closed period must not gain new money movements, only lose them"* (H6) | `paymentWriterCore.ts:29` `assertPeriodOpen` |
| Reports that consume AR/ledger: `ar-aging, ap-aging, customer-statements, top-debtors, dso, ar-summary, profit-loss, cash-flow, cash-reconciliation, balance-sheet, trial-balance, general-ledger, income-statement` | `routes/reports.ts:12-30` |
| **Customer advances do not exist.** The only `advance` references are employee salary advances | grep — `Employee.ts` `ADV-%` |
| Idempotency keys are available for new writes (P11) | `utils/idempotency.ts`, applied in invoice/mobile/POS |

---

## 2. The central design decision

A customer advance (cash received *before* any invoice exists) is a **liability
we owe back**, not a discount and not a reduction of receivables. The existing
`1110 Customer Credit` is a **contra-asset** that offsets AR and arises
*systemically* from returns and overpayments.

**Decision: create a separate liability account. Do not reuse `1110`.**

    2120  Customer Advances (Unearned)   type: liability   normal_balance: credit

Rejected alternative — feed advances into the existing `1110` pool:

- It misclassifies a liability as a contra-asset, so the balance sheet would show
  customer advances netting against AR instead of in current liabilities.
- It destroys the distinction the business actually needs: an advance is
  refundable on demand; a return/overpayment credit is not.
- `1110`'s stated purpose is "credit balances from returns/overpayments".
  Widening it silently would contradict the account's own description.

### 2.1 The interaction hazard this creates

`_availableCustomerCredit` in the invoice form is:

    customer.creditBalance + (customer.currentBalance < 0 ? |currentBalance| : 0)

If an advance were ever written into `customer_ledger` as a credit, it would
reduce `currentBalance` and therefore become **silently spendable as the H9
credit pool** — double-counted with `credit_balance` if it also touched 1110.

**Therefore: advances must not be written to `customer_ledger` at all.**
`customer_ledger` is the AR subledger; it feeds AR aging, DSO and customer
statements. An advance received is not an AR reduction, and injecting one would
distort every aging bucket and DSO. Advances get their own table and their own
GL account, and the H9 credit path must never see them.

---

## 3. Data model (proposed — not created)

```sql
CREATE TABLE customer_advances (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  advance_no     VARCHAR(50)  NOT NULL UNIQUE,
  customer_id    INTEGER      NOT NULL REFERENCES customers(id),
  advance_date   DATE         NOT NULL,
  amount         DECIMAL(15,2) NOT NULL CHECK (amount > 0),
  applied_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  refunded_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  payment_method VARCHAR(50)  NOT NULL,
  reference_no   VARCHAR(100),
  notes          TEXT,
  status         VARCHAR(20)  NOT NULL DEFAULT 'OPEN',  -- OPEN | APPLIED | VOID
  voided_at      TIMESTAMP,
  voided_by      INTEGER,
  created_by     INTEGER,
  created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  -- available = amount - applied_amount - refunded_amount
  CHECK (applied_amount + refunded_amount <= amount)
);

CREATE TABLE customer_advance_allocations (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  advance_id INTEGER NOT NULL REFERENCES customer_advances(id),
  invoice_id INTEGER NOT NULL REFERENCES invoices(id),
  amount     DECIMAL(15,2) NOT NULL CHECK (amount > 0),
  applied_at DATE NOT NULL,
  created_by INTEGER
);

CREATE INDEX idx_advances_customer  ON customer_advances(customer_id);
CREATE INDEX idx_advances_date      ON customer_advances(advance_date);
CREATE INDEX idx_alloc_advance      ON customer_advance_allocations(advance_id);
CREATE INDEX idx_alloc_invoice      ON customer_advance_allocations(invoice_id);
```

`customer_advance_allocations` is an **event log, not a current-state table**: one
row per application, deliberately *not* unique on `(advance_id, invoice_id)`.
A UNIQUE constraint was considered and rejected — it would forbid applying a
second tranche to an invoice that already has an allocation, which is a routine
occurrence (apply 100 now, 200 more after the next invoice lands). Cumulative
ceilings are enforced in the service, inside the same transaction that writes the
row, so the invariant holds without constraining legitimate history.

---

## 4. GL postings

All follow the existing `AccountingService.postEntry` shape and the
`reference_type` / `reference_id` convention used by `CREDIT_OFFSET`.

### 4.1 Receipt (advance received)

    Dr  <cash code>   (1010 / 1020 / 1030 / 1040, by payment method)
    Cr  2120          Customer Advances (Unearned)
    entry_date = advance_date      reference_type = 'ADVANCE_RECEIPT'

Cash in, no revenue. This is the single most important reporting consequence:
an advance must never reach the income statement.

### 4.2 Application to invoice

    Dr  2120
    Cr  1100          Accounts Receivable
    entry_date = invoice_date      reference_type = 'ADVANCE_APPLICATION'

Entry is dated at the **invoice date**, not today, so it lands in the same
period as the receivable it settles — mirroring how `postCreditOffsetEntry`
dates at `invoiceDate`. The liability is extinguished; AR is reduced.

### 4.3 Refund (unapplied cash returned)

    Dr  2120
    Cr  <cash code>
    entry_date = refund_date       reference_type = 'ADVANCE_REFUND'

Permitted **only** for the unapplied remainder. Must go through the existing cash
method whitelist (`isValidPaymentMethod`) and the same guard refunds already use,
so till/wallet balances cannot silently disagree.

### 4.4 Void

Void is a **reversal, never a delete**. If the advance is voided before any
application, the receipt is reversed:

    Dr  2120
    Cr  <cash code>
    entry_date = void_date         reference_type = 'ADVANCE_VOID'

A partially-applied advance **cannot be voided** — the applications must be
reversed first. Voiding the row while leaving its allocations posted would make
the GL disagree with the allocation table.

---

## 5. Business rules

| Rule | Enforcement |
|---|---|
| Advance amount > 0 | DB `CHECK` + service validation |
| Application ceiling | `sum(open invoice balances for customer)` |
| Per-advance ceiling | `amount - applied_amount - refunded_amount` |
| Refund ceiling | `amount - applied_amount` (consumed cash is not refundable) |
| Application requires the advance be `OPEN` | service check |
| No application to a cancelled/voided invoice | reuse existing invoice-state checks |
| Closed period (H6) | `assertPeriodOpen` on every posting date |
| Same customer on advance and invoice | service check |
| Void only when `applied_amount = 0 AND refunded_amount = 0` | service check |
| Idempotency-Key required on all three writes | P11 `normalizeIdempotencyKey` + `claimIdempotencyKey` inside the transaction |

### 5.1 Closed-period policy — the subtle one

An advance is received on date *D₁*; the period containing *D₁* is later closed;
the advance is then applied to an invoice on date *D₂*.

The application entry is dated **D₂** (the invoice date), and it **credits AR**.
Since H6 states a closed period must not gain new money movements, the guard
must be applied to the **invoice's** period, not the date of the application:

- Invoice period open → allowed, posts at `D₂`.
- Invoice period closed → **rejected**. The user must reopen the period, which
  is the correct and auditable behaviour: the AR credit belongs to that period
  and cannot be invented retroactively.

Refunds and voids are dated when they happen, so they only require their own
(necessarily open) period. They debit 2120, whose balance originated in a closed
period — that is fine, because no *movement* is added to a closed period.

---

## 6. Reporting impact

| Report | Required change |
|---|---|
| **Income statement** | Advances received must be **excluded** — they are not revenue. Highest-risk item. |
| **Balance sheet** | `2120` appears as a current liability; must not be netted into AR. |
| **AR aging** | Advances must be **excluded** — they are not receivables. |
| **DSO** | Excluded by the same change; otherwise DSO is understated. |
| **Customer statement** | New section for advances, shown separately from the AR ledger. |
| **Cash flow / cash reconciliation** | Advance receipts and refunds are cash movements, correctly included. |
| **Trial balance / general ledger** | Automatic from `journal_lines`. |
| **New: advances outstanding** | Aging by receipt date, per customer and in total. |

A reconciliation check should exist: sum of open `customer_advances.available`
must equal the `2120` control-account balance. This single assertion catches
almost any future regression in this feature.

---

## 7. UI specification

1. **Customer detail → Advances tab** — list with date, amount, applied,
   refunded, available, status; actions: apply, refund, void.
2. **Record advance** — amount, date, payment method, reference, notes.
3. **Apply to invoices** — pick advance, tick invoices, enter partial amounts;
   show remaining capacity live. Mirrors the task-41 credit affordance so the
   two interactions feel consistent.
4. **Refund** — amount limited to the unapplied remainder, with the ceiling shown.
5. **Guard parity** — client-side ceilings are convenience only; the server
   remains authoritative, exactly as in task 41.
6. **Separation from store credit (task 41).** The H9 credit panel shows
   *Available / Used / Remaining* from `credit_balance`. Advances must render as
   a **distinct, separately labelled** concept. Showing an advance in the store
   credit panel would invite users to apply a liability as if it were a
   contra-asset, and would be wrong in both directions.

---

## 8. Regression matrix

`GL` = expected journal lines. `AV` = advance `available`
(`amount - applied - refunded`). All amounts exact to 2dp.

| # | Scenario | GL | Ledger | Invariants |
|---|---|---|---|---|
| R1 | Advance 500 received, cash | Dr 1010 500 / Cr 2120 500 | advance OPEN, AV=500 | `2120` = 500; no AR movement |
| R2 | Apply 500 to one invoice of 500 | Dr 2120 500 / Cr 1100 500 | APPLIED, AV=0 | invoice balance → 0 |
| R3 | Apply 200 partial to invoice of 800 | Dr 2120 200 / Cr 1100 200 | OPEN, AV=300 | invoice balance 800→600 |
| R4 | Apply 500 to two invoices (300 + 200) | 2 entries, 300 and 200 | APPLIED, AV=0 | both allocations recorded |
| R5 | Two advances applied to one invoice | separate allocations | both consistent | invoice never over-settled |
| R5b | Same advance applied twice to one invoice (100 then 200) | two allocation rows, 100 and 200 | AV reduced by 300 | legitimate second tranche allowed |
| R6 | Over-apply beyond invoice balance | **rejected** | unchanged | AR never credited beyond invoice |
| R7 | Over-apply beyond `AV` | **rejected** | unchanged | `applied ≤ amount` |
| R8 | Refund 200 of a 500 advance | Dr 2120 200 / Cr 1010 200 | AV=300 | refund ≤ unapplied |
| R9 | Refund a fully applied advance | **rejected** | unchanged | consumed cash not refundable |
| R10 | Refund > `AV` | **rejected** | unchanged | no negative `2120` |
| R11 | Void an unapplied advance | Dr 2120 / Cr 1010 | VOID | `2120` → 0; cash restored |
| R12 | Void a partially applied advance | **rejected** | unchanged | GL would otherwise disagree |
| R13 | Advance in closed period | **rejected** | unchanged | H6 holds |
| R14 | Application to invoice in closed period | **rejected** | unchanged | H6: closed period gains nothing |
| R15 | Apply to a cancelled invoice | **rejected** | unchanged | no AR credit for a dead invoice |
| R16 | Apply advance of customer A to invoice of B | **rejected** | unchanged | customer isolation |
| R17 | Duplicate request, same key + payload | replayed, **no second row** | one advance | one GL entry |
| R18 | Same key, different payload | **409** | unchanged | payload hash enforced |
| R19 | Advance received, then invoice created, then apply | sequence valid | consistent | ordering independent |
| R20 | Full lifecycle 500 → apply 300 → refund 200 | balanced | AV=0 | `2120` nets to 0 |
| R21 | `sum(AV) == 2120 balance` | — | — | **control reconciliation** |
| R22 | Advance never appears in income statement | — | — | not revenue |
| R23 | Advance never appears in AR aging / DSO | — | — | not receivable |
| R24 | H9 credit pool unaffected by advances | — | — | `_availableCustomerCredit` unchanged |
| R25 | Concurrent applications race | one wins, other rejected | consistent | no over-application |

---

## 9. Open decisions requiring sign-off

1. **Account code — resolved.** `2120` is free: the live chart uses `1000, 1010,
   1020, 1030, 1040, 1100, 1110, 1200, 1300, 2000, 2100, 3000, 3100, 3200, 3300,
   4000, 4100, 4150, 5000, 6000, 6100, 6300, 7000, 7100, 7200–7204`. Liabilities
   are `2000` (AP) and `2100` (Tax Payable); equity starts at `3100`, so `2120`
   sits correctly inside the current-liability block.
2. **Void semantics.** Proposed: void reverses the cash. An alternative is to
   treat void as a pure correction that assumes cash never left — acceptable
   only if void is impossible once reconciliation has run.
3. **Application period guard.** Proposed: reject when the *invoice's* period is
   closed. Confirm with finance; some jurisdictions allow the application to be
   dated today instead.
4. **Advance numbering.** Needs a document-number scheme consistent with the
   existing invoice/return series.

## 10. Suggested implementation order (only once approved)

1. Migration: account `2120` + `customer_advances` + allocations (idempotent).
2. `postAdvanceReceipt` / `postAdvanceApplication` / `postAdvanceRefund` /
   `postAdvanceVoid` in `accountingService.ts`, mirroring `postCreditOffsetEntry`.
3. Service with the section-5 rules, inside one transaction, with the key
   claimed inside it.
4. Routes + permissions + rate limiting consistent with `payments.ts`.
5. Server tests driven directly from the R1–R25 matrix.
6. Report changes (section 6), including the section-6 reconciliation check.
7. UI.
