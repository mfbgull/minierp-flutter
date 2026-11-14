# Inventory effective dates (ACCT-006)

Why a stock movement carries three dates, and which one the ledger trusts.

This is the canonical rationale for the ACCT-006 rule. It was written when
`server/src/services/inventoryEffectiveDate.ts` existed as a shared guard helper.
That module was never wired into a write path — the rule ended up enforced
directly in the consumption path instead — and was removed as dead code on
2026-10-21. The rationale is kept here because the rule itself is live and
covered by `server/src/__tests__/inventoryEffectiveDate.test.ts`.

## The three dates

An inventory movement carries three different dates, and conflating them is
what allowed financially incorrect documents:

- the **document date** the user typed (`invoice_date`, `purchase_date`, …)
- the **inventory-effective date** the movement is recorded against
  (`stock_movements.movement_date`)
- the **record-creation timestamp** (`stock_movements.created_at`)

Under the adopted approach the first two are held equal and both are
constrained; the third is left alone and is what the ledger already trusts for
ordering ties.

## The rule

> A newly recorded inventory movement may not be effective earlier than the
> latest movement already recorded for that item in that warehouse.

Why that one rule is enough: the ledger is append-only, so `MAX(movement_date)`
is the last point in the recorded history at which stock was known-good. Dating
anything before it would mean inventing a past in which quantities, FIFO order
or expiry differed from what was posted, and the system cannot prove the
alternative without reconstructing history. When history cannot be proven, the
transaction is rejected rather than guessed at.

Per item **and** warehouse rather than per item globally: two warehouses hold
independent stock, so a movement in one does not constrain the other. A sale
that draws lines from several warehouses is checked line by line, and the caller
is inside its own write transaction, so a rejection rolls the whole document
back rather than leaving it half-written.

Same-day transactions are permitted (`<=` is inclusive) because a purchase and
a sale on one date is normal wholesale trading.

## What it prevents

- **D4** — a backdated receipt reordering FIFO beneath an already-posted sale
- **D2** — expiry judged at today's date rather than at the transaction date
- **D1/D3 (sales)** — a sale dated before the item's first purchase receipt
  is no longer refused: decision D19 accepts it with a warning, a
  `backdated_before_receipt` flag and batch-linked actual-cost COGS, so the
  historical as-of position reads negative only as a documented, reportable
  exception. The allocator's oversell refusal and the expiry rules still hold.

## Where it is enforced

The as-of filter lives in the consumption path, not in a separate guard:

- `server/src/models/StockMovement.ts` — `consumeFromOldestBatches(itemId,
  warehouseId, quantity, db, asOfDate)`; `asOf` defaults to today when the
  caller does not supply it, and the batch query filters
  `sb.received_date <= @asOf` and `sb.expiry_date >= @asOf`
- `server/src/models/StockMovement.ts` — `consumeForSale(...)` wraps the
  allocator for the invoice path. Before consuming it evaluates the D19
  fallback (`preReceiptFallback`): when every remaining batch was received
  after the sale date, current sellable stock covers the quantity and the
  later stock was already sellable (expiry-wise) on the sale date, those
  later batches are consumed at their recorded cost and the caller flags
  the invoice. Every other refusal (oversell, expired-only stock, as-of
  stock present, blocked locations) stays hard.
- `server/src/models/Invoice.ts` — `consumeFromOldestBatches` forwards
  `asOfDate`
- `server/src/models/Production.ts` — passes `production_date` as the `asOf`
  date so a production cannot consume material that had not yet been received
- `server/src/models/Purchase.ts`, `server/src/models/PurchaseOrder.ts` — the
  receipt-side check against the latest posted movement

## Coverage

`server/src/__tests__/inventoryEffectiveDate.test.ts` exercises the rule
end-to-end through the HTTP API (13 cases): D1 and D3 under the D19 contract,
D2, D4, goods receipt and production, closed periods still winning, and an
unaffected forward-only sequence. `backdatedSaleWarning.test.ts` covers the
accept-with-warning path itself (warnings text, flag, actual-cost COGS,
refusals that still hold, and the exception report).

## Decision history

ACCT-006 sub-item 3 — a sale dated before the item's first purchase receipt —
has moved twice: the original hard refusal was implemented, red-tested, then
removed under D12 (16 tests legitimately purchase stock and then invoice it
with a historical date); decision D19 (2026-11-12) re-introduced a middle
path — accept with warning, flag and exception report, keeping the oversell
refusal hard. See `audit/DECISIONS.md` D12 and D19 and
`audit/FINDINGS-STATUS.md`.
