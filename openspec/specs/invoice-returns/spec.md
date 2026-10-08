# Invoice Returns

## Purpose

Users can process customer returns from the invoice list 3-dot menu and from
the invoice detail/print-preview view. A return restocks the returned goods
into a warehouse chosen by the user, reverses the sale's stock/GL/ledger
effects and applies the disposition (refund, credit or adjust).
## Requirements
### Requirement: invoice-return-menu
An invoice's 3-dot menu SHALL offer a Return option that routes to invoice return creation for that invoice.

#### Scenario: return from invoice list
- **WHEN** a user opens the 3-dot menu on an invoice
- **THEN** a Return option is available and routes to invoice return creation for that invoice

### Requirement: invoice-detail-return
The invoice detail view SHALL offer a return action that routes to invoice return creation for that invoice.

#### Scenario: return from invoice detail
- **WHEN** a user is viewing invoice detail
- **THEN** a return action is available and routes to invoice return creation for that invoice

### Requirement: invoice-return-restock-warehouse
A customer return SHALL require the user to select a restock warehouse, and the server SHALL restock the returned items into that warehouse.

#### Scenario: restock warehouse is required
- **WHEN** a user processes a return on an invoice
- **THEN** the return form requires a restock warehouse and the server restocks the returned items there

### Requirement: A refund settlement is capped by the cash actually collected on the invoice
A refund settlement SHALL NOT pay out more cash than the customer actually paid in
on the invoice being returned. The cap SHALL be computed at the single chokepoint
every refund leg passes through, so no settlement path can bypass it.

The cap is `PaymentModel.refundableOnInvoice(invoiceId)` — the sum of live
`payment_allocations`, which is money that actually arrived. It deliberately
excludes `paid_amount`: an invoice settled entirely by store credit has
`paid_amount > 0` and collected cash of **zero**, and converting it to cash on
return fabricates `Dr Cash / Cr AR` for money the business never received.

Store credit is not cash and must not become cash through a return.

#### Scenario: A store-credit-settled invoice cannot be refunded in cash
- **WHEN** a 400 invoice is settled entirely by `credit_offset`, so `paid_amount` is 400 and collected cash is 0
- **THEN** a refund settlement of 400 is refused with 400
- **AND** the response names the collected amount as the ceiling
- **AND** net cash on account 1000 is unchanged

#### Scenario: A partially cash-settled invoice refunds only its cash portion
- **WHEN** a 400 invoice has 100 collected in cash
- **THEN** a refund settlement of 400 is refused with 400
- **AND** a refund settlement of 100 is accepted

#### Scenario: The legacy and spec-driven paths agree
- **WHEN** the legacy `disposition: 'refund'` path and the spec-driven
      `settlements: [{ type: 'refund' }]` path both settle the same return
- **THEN** neither may exceed the collected cash

### Requirement: Voiding an adjusted settlement reverses the GL group that adjustment actually posted
Voiding an `adjust` settlement SHALL void both the payment allocation it created
and its general-ledger group, and SHALL NOT release the settlement's settled cap
unless both reversals succeed.

A `CREDIT_APPLICATION` moves no cash, so it posts **no** `PAYMENT` group. Its GL
lives under `CREDIT_OFFSET` keyed by the **target invoice id**. Voiding
`('PAYMENT', payment_id)` matches zero rows and silently succeeds, leaving
`Dr 1110` standing for an entitlement that was given back — after which the same
return can be settled a second time and the cash paid out twice.

The two sibling branches key their GL differently: `refund` by payment id,
`adjust` by target invoice. Neither may borrow the other's key.

#### Scenario: Voiding an adjustment reverses its offset and releases its allocation
- **WHEN** a 1600 return is adjusted against a separate unpaid invoice, recording a credit-application payment
- **THEN** the settlement row carries that payment's id
- **AND** `('CREDIT_OFFSET', targetInvoiceId)` is a balanced, non-zero group
- **AND** after voiding, that group reads 0 debit / 0 credit
- **AND** the target invoice has no live payment allocation

#### Scenario: The adjustment must target an unpaid invoice
- **WHEN** an adjust settlement names a fully-paid invoice as its target
- **THEN** `applied` is 0 because it is capped at the target's outstanding balance
- **AND** no payment is recorded, so `payment_id` is legitimately NULL

#### Scenario: A second void is rejected
- **WHEN** an already-voided settlement is voided again
- **THEN** the request is refused
- **AND** no allocation or journal line is reversed a second time
- **AND** cash is unchanged

### Requirement: An invoice edit that cannot be re-posted is refused before any write
`updateInvoice` SHALL reject a recomputed total that is non-positive when the
invoice already carries recorded payments, and SHALL do so before voiding any
journal line.

`updateInvoice` re-posts by voiding the invoice's existing `INVOICE` and `COGS`
groups and posting replacements. `postInvoiceEntry` returns null for a
non-positive total, so a zero-total edit voids `Dr 1100 / Cr 4000` and posts
nothing back, leaving a bare `Cr 1100` — a credit balance on a debit-normal
asset, with the trial balance still balanced so nothing alerts.

The floor is **non-positive**, not "below the amount already paid". Reducing a
paid invoice's total while leaving its payment intact is legitimate: the balance
floors at zero and the invoice stays `Paid`.

#### Scenario: Zeroing a paid invoice is refused and the books are untouched
- **WHEN** a 400 invoice with 400 paid is edited so its lines total 0
- **THEN** the request returns 400
- **AND** the `INVOICE` group retains its original debit and credit magnitude
- **AND** `total_amount` is still 400
- **AND** the trial balance still foots

#### Scenario: Reducing a paid invoice while keeping it positive is allowed
- **WHEN** a 400 invoice with 400 paid is edited down to 200
- **THEN** the request returns 200
- **AND** `total_amount` is 200 while `paid_amount` remains 400

### Requirement: A due date is derived from the customer's payment terms
An invoice created without an explicit due date SHALL derive one from the
customer's `payment_terms_days`, falling back to the active default
`payment_terms` row and then to zero days. The derivation SHALL replace any
hard-coded offset.

A fixed offset ignores the customer's actual terms, so an invoice for a customer
on net-30 aged as if it were due immediately.

#### Scenario: A customer's own terms drive the due date
- **WHEN** an invoice for a customer with `payment_terms_days = 30` is created with no due date
- **THEN** the due date is 30 days after the invoice date

#### Scenario: A customer with no terms falls back to the default terms
- **WHEN** an invoice is created for a customer whose `payment_terms_days` is NULL
- **THEN** the active default `payment_terms` row supplies the number of days

#### Scenario: An explicit due date is never overwritten
- **WHEN** an invoice is created with a due date supplied
- **THEN** that date is stored unchanged

