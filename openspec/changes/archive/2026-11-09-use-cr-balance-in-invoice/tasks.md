## 1. Backend - Credit Balance API

- [x] 1.1 Create API endpoint to fetch customer CR balance by customer ID
  - Done (shipped earlier under the credit-offset and store-credit features).
    The customer API exposes both roles of CR: `customers.credit_balance`
    (store-credit pool) and negative `current_balance` (legacy ledger credit).
    Evidence: `customerStoreCredit.test.ts` "customer API exposes the credit pool".
- [x] 1.2 Add validation to ensure credit balance is sufficient before applying
  - Done. `InvoiceCreationService.assertCreditOffset` enforces offset ≤
    available = `max(0, credit_balance) + |min(0, current_balance)|` (the H9
    sum), rechecked inside the write transaction.
- [x] 1.3 Create transaction wrapper for atomic invoice + credit offset creation
  - Done. Invoice creation runs in one `better-sqlite3` `db.transaction`;
    the credit assert, GL posting and pool draw all happen inside it, so any
    rejection rolls back the whole invoice.

## 2. Backend - Invoice Creation Modification

- [x] 2.1 Modify invoice creation endpoint to accept optional credit offset amount
  - Done. `POST /api/invoices` parses `credit_offset` (non-negative, folded
    into `paid_amount`). Edit mode applies a credit delta guarded by the
    balance; `creditOffsetUpdate.test.ts` covers the edit path.
- [x] 2.2 Add accounting entry generation for credit offset (debit Customer Credit, credit AR)
  - Done. `AccountingService.postCreditOffsetEntry` posts Dr 1110 / Cr AR for
    the ledger share, plus a pool draw. Evidence: `creditOffset.test.ts`
    "posts a balanced Dr Customer Credit / Cr AR journal entry";
    `creditOffsetSubledger.test.ts` pins both pool and ledger paths.
- [x] 2.3 Ensure credit offset is processed within the same transaction as invoice creation
  - Done. Same transaction wrapper as 1.3; GL, subledger and pool moves are
    one atomic unit.

## 3. Backend - Return Integration

- [x] 3.1 Verify return with credit disposition generates CR balance entry
  - Done. A return's credit disposition posts type RETURN/CREDIT customer
    ledger rows and lands in the store-credit pool, not negative AR.
    Evidence: `customerStoreCredit.test.ts` "return settled as credit lands
    in the pool, not in negative AR".
- [x] 3.2 Add reference link between return and CR balance entry
  - Done. Credit ledger notes reference the source return and target invoice
    ("Credit note ... from return ... on Invoice ..."), and
    `store_credit_draws` carries `(settlement_id, invoice_id,
    application_id)` references. F-002 regression: `auditCreditOwnership.test.ts`.

## 4. Frontend - Invoice Creation Form

- [x] 4.1 Add CR balance display field on invoice form (after customer selection)
  - Done. `sales_invoice_form_page.dart` shows available credit
    (`salesAvailablecredit`) derived from the selected customer's
    `creditBalance` plus ledger credit.
- [x] 4.2 Add "Apply Credit" checkbox with amount input field
  - Done. The payment panel supports a credit offset amount with
    clamping; evidence: `payment_panel_credit_test.dart`,
    `invoice_calculations_test.dart` (credit-offset ceiling).
- [x] 4.3 Implement conditional display (hide when no CR balance)
  - Done. The credit section only appears when available credit > 0
    (`_availableCustomerCredit > 0`).
- [x] 4.4 Add validation to prevent applying more than available balance
  - Done. Client guard rejects `creditToApply > _availableCustomerCredit`;
    the server re-enforces the same bound.

## 5. Frontend - Payment Flow

- [x] 5.1 Calculate and display remaining payment amount after credit offset
  - Done. Remaining balance rows in the form show
    available − applied credit; edit mode nets `credit_offset` in
    `paid_amount` exactly once (comment block at the `_remainingDue`
    calculation).
- [x] 5.2 Disable payment section when credit fully covers invoice
  - Done. Zero remaining requires no payment; the create body still passes
    `credit_offset` so the invoice records it as settled.
- [x] 5.3 Pass credit offset amount to invoice creation API
  - Done. Submission includes `'credit_offset': _creditOffset`.

## 6. Testing & Validation

- [x] 6.1 Test invoice creation with no CR balance (existing behavior unchanged)
  - Done. `creditOffset.test.ts` runs with zero credit seeded and the
    existing no-credit creation suite is unchanged.
- [x] 6.2 Test invoice creation with full credit offset
  - Done. `creditOffset.test.ts` "creates the invoice when the customer has
    enough credit"; subledger suite settles the invoice to zero with exactly
    one economic credit event.
- [x] 6.3 Test invoice creation with partial credit offset
  - Done. `customerStoreCredit.test.ts` "applying part of the credit settles
    partially and drains the pool" and the storage-pool path in
    `creditOffsetSubledger.test.ts`.
- [x] 6.4 Test concurrent credit usage (two invoices same credit)
  - Done by construction, noted: `better-sqlite3` is synchronous and
    single-threaded, so requests cannot interleave mid-transaction.
    Sequential double-spend is covered: the availability assert rechecks
    inside the write transaction, and a second invoice asking for
    already-spent credit is rejected (`creditOffset.test.ts` "rejects a
    credit offset larger than the available balance"; store-credit paths
    reject above the remaining pool / above the invoice entitlement).
- [x] 6.5 Verify accounting entries balance correctly
  - Done. `creditOffsetSubledger.test.ts` holds GL AR (1100+1110) equal to
    customer balances with the ledger as subledger authority; invariant
    suites run the shared accounting invariants.

## Disposition note (2026-11-09)

Verification against current `main` shows every task shipped. The work
landed in earlier features: creation-time credit offset (Dr 1110 / Cr AR),
the store-credit pool, store-credit draw ownership (F-002), and apply credit
to existing invoices (`POST /customers/:id/store-credit/apply`). No
production code change was outstanding; the checklist is now marked with
evidence. Pool/ledger overdraw guards remain server-authoritative.
