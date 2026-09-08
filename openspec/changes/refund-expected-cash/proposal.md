## Why

When a purchase return is posted against a fully-paid purchase, the system
currently requires a `disposition` (`credit_on_account` | `refund_expected`)
but only ever posts a supplier credit note — `refund_expected` is a flag with
no real-world effect. The supplier balance goes negative (a receivable owed
to the company) and stays there forever, with no path to pay it back. Users
expecting a cash refund have no way to issue it, so the credit note becomes
an orphan liability on the AP side.

## What Changes

- **New endpoint** `POST /supplier-refunds` that issues a cash refund
  against an existing supplier credit note (or any outstanding supplier
  receivable). It records a payment out, reverses the credit note balance,
  and posts the GL (Dr AP / Cr Cash).
- **Disposition drives real money**: `refund_expected` now means the credit
  note is eligible for a cash payout; `credit_on_account` remains a pure
  credit held against future purchases.
- **Refund lifecycle**: draft → posted → voided, mirroring the existing
  payment/expense void model. Void reverses the payment and the credit note.
- **Supplier statement / AP aging / GL all pick it up automatically** because
  the refund posts through the same `supplier_ledger` and `payments` tables
  the existing flows use.
- **Frontend**: add a Refund action on the purchase return detail and on
  the supplier statement for negative balances, plus wiring of the
  `disposition` field through the return form (currently stripped by the
  controller and missing from the UI).

## Capabilities

### New Capabilities
- `supplier-refund`: Issue and void cash refunds against supplier credit
  notes / outstanding supplier receivables. Covers the endpoint, ledger +
  GL posting, void lifecycle, and the frontend refund action.

### Modified Capabilities
- `purchase-returns`: the `refund_expected` disposition now has a real
  monetary outcome (cash payout) instead of being a silent flag. The
  return create flow also forwards the `disposition` field from request to
  model (currently dropped by the controller and absent from the UI).

## Impact

- **Backend** (server/src): new `SupplierRefund` model + controller +
  route; migration adding `supplier_refunds` table; `PurchaseReturnModel`
  forwards `disposition`; `purchaseReturnController` forwards
  `disposition`; `SupplierLedgerModel` gains a refund entry type.
- **Frontend** (lib): `purchase_repository.dart` adds `disposition` to
  `createReturn` and a `createRefund` method; `purchase_return_form_dialog`
  adds a disposition picker; new refund dialog + supplier statement
  refund action.
- **Reports**: no report changes required — AP aging, supplier statement,
  and general ledger already read `supplier_ledger` / `payments` /
  `journal_lines`, so refunds surface automatically.
- **Permissions**: new `supplier_refunds` resource (read/create/void),
  mirroring the payments permission model.