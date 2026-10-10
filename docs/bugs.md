# Known Bugs — not yet fixed

Backlog of defects that are **confirmed or suspected but deliberately unfixed**.
Each entry says what was observed, how it was observed, and what is still unknown,
so the next person does not have to re-derive it.

For audit findings and their disposition see [`audit-coverage-ledger.md`](audit-coverage-ledger.md)
(67 rows — 65 canonical Part-0 IDs plus DB-004, DB-005/006/007/008, SALES-020,
PRET-001 and RET-008; counts recounted and verified to foot). This file holds
defects found *outside* that audit pass, plus audit rows whose code fix was
reverted.

Status values: `FIXED` (done, kept for regression context) · `OPEN` (unfixed,
actionable) · `NEEDS-INVESTIGATION` (observed, root cause not established).

> **Concurrency note.** At least one other session was editing
> `sales_invoice_form_page.dart`, `invoice_rules.dart` and
> `extra_calculations_test.dart` while BUG-001 was being fixed. BUG-002 was
> landed by that session, not by the author of BUG-001 — reconcile the diffs
> before committing, and check `git status` for files you did not touch.

---

## BUG-001 · Overpaying at invoice creation saved an unpaid invoice with no warning

**Status:** `FIXED` — `lib/features/sales/sales_invoice_form_page.dart`
**Found:** 2026-10-08 · **Severity:** high (silent data loss)

### Symptom

Entering a payment larger than the invoice grand total on the create form saved
the invoice, recorded **no** payment, left the invoice `Unpaid`, and showed no
warning or error. The user was told "Invoice saved successfully!".

### Root cause — three compounding defects, all client-side

The **server was correct throughout**. Verified directly against the API:

| step | result |
|---|---|
| `POST /invoices` with `record_payment:true`, no `payment` block | `201`, `status=Unpaid`, `paid=0` |
| `POST /payments` 150 against a 100 total | `400` `"Allocation amount (150.00) for invoice 1 exceeds the remaining balance (100.00)"` |
| `POST /payments` exactly 100 | `201`, invoice becomes `Paid` |

1. **Create mode is a two-step flow.** The form sends `record_payment: true`
   with **no `payment` block** (`_buildBody`), so the invoice is created unpaid;
   each payment method is then posted separately to `POST /payments`. The
   rejection therefore only surfaces from the *second* call.
2. **The result was discarded.** `_save()` called
   `await _postPaymentBodies(bodies, stopOnFirstFailure: false)` without using
   its `bool`, so the save reported success no matter what the payment returned.
3. **The error toast was erased.** `_submit()` then popped the page and showed
   "Invoice saved successfully!"; `showAppToast` calls `..hideCurrentSnackBar()`
   first (`lib/widgets/app_toast.dart:18`), so the success toast silently
   replaced the server's rejection message.

Compounding it: `_validatePayment()` already contained the correct
`doesPaymentExceedBalance` check, but its **only** call site was inside
`_recordPayments()`, documented *"Edit mode only"*. Create mode never validated.

### Fix

- Create-mode overpayment guard in `_save()`, before anything is persisted,
  compared against the total **before** the payment is applied.
  `_remainingBalance` is deliberately *not* reused there — it is the balance
  *after* the payment (see BUG-002).
- `_postPaymentBodies` records the first rejection; `_submit()` and
  `_saveAndPrint()` no longer report success or pop when a payment was
  rejected, and show the server's reason instead.
- Added `surfaceErrors` so the message is not shown twice.

### Regression coverage

`test/sales_invoice_form_page_test.dart` → group `overpayment at creation`
(2 tests). Both verified **red before** the fix and green after.

---

## BUG-002 · `_validatePayment()` compared the payment against the balance *after* it

**Status:** `FIXED` — `sales_invoice_form_page.dart:658,749`
**Found:** 2026-10-08 · **Severity:** high — fixed in a concurrent session, not by the author of BUG-001

### The arithmetic

`_validatePayment()` called:

```dart
if (doesPaymentExceedBalance(_paymentSum, _remainingBalance)) { ... }
```

`_remainingBalance` is the balance **after** this payment
(`balance − _paymentSum − _creditOffset`), but the callee's contract is the
opposite — its second argument is the balance **before**:

```dart
bool doesPaymentExceedBalance(num totalPaymentAmount, num remainingBalance) =>
    totalPaymentAmount > remainingBalance;
```

confirmed by its unit test (`test/calculations/extra_calculations_test.dart:308`):

```dart
expect(doesPaymentExceedBalance(110, 100), true);
expect(doesPaymentExceedBalance(90, 100), false);
```

So `_paymentSum` was compared against a figure that had already had
`_paymentSum` subtracted — the payment counted twice. For a 1,000 balance:

| payment | `_remainingBalance` | check | expected |
|---|---|---|---|
| 400 | 600 | `400 > 600` → pass | pass |
| 600 | 400 | `600 > 400` → **blocked** | pass |
| 1,000 | 0 | `1000 > 0` → **blocked** | pass |

The threshold sat near **half** the balance instead of the full balance.

### Fix

Add the in-progress payment back before comparing, keeping `_remainingBalance`
for its *display* use where "balance after this payment" is the right figure:

```dart
num get _balanceBeforePayment => _remainingBalance + _paymentSum;
```

`_validatePayment` now calls `doesPaymentExceedBalance(_paymentSum,
_balanceBeforePayment)`. Backed by a doc comment on `doesPaymentExceedBalance`
spelling out the operand contract, and by a regression test (`full payment
against the balance is allowed`).

### Note on the investigation

While diagnosing this, a widget-test probe against `_editInvoice()` (balance
1,000) posted **nothing** for 499, 500, 501 and 999, and showed no error. That
contradicted the arithmetic, which predicts 499 should pass — the probe most
likely never registered the amount on the payment method, leaving
`_paymentBodies()` empty (it filters on `m.amount > 0`).

**That probe result was a harness artefact and was never reproduced as a product
defect.** It is recorded only so the same false alarm is not re-derived.

## BUG-003 · SALES-008 reverted: `INVOICE_SETTLEMENT` ceiling ignores prior payments

**Status:** `OPEN` (recorded `won't-fix` in the audit ledger, guard enforced)
**Severity:** high if it ever becomes reachable

The audit finding is correct as written: the `INVOICE_SETTLEMENT` branch of
`allocationCeiling` (`server/src/services/paymentValidation.ts`) uses the invoice
**gross total**, so it ignores payments already received.

It is **not reachable today**. That mode has exactly one production caller,
`InvoiceCreationService.create`, which records the payment in the same
transaction that creates the invoice — so the row is already stored as settled
when the ceiling is evaluated, and the gross total is correct there. The audit's
prescribed `max(0, balance_amount)` fix would reject **every** fully-paid
invoice at creation. An earlier attempt at
`total − (returned + paid)` broke exactly that and was reverted.

The finding is now enforced rather than merely documented: a source scan in
`settlementCashIntegrity.test.ts` asserts exactly one call site and pins the
ceiling expression, and it was proved non-vacuous by injecting a second caller.

**Open decision:** whether to close it by construction — give invoice creation
its own mode and make `INVOICE_SETTLEMENT` balance-bounded — which would need the
guard test widened to match.

---

## BUG-004 · C-04 blocked on the inventory batch/lot rewrite

**Status:** `OPEN` — blocked · **Severity:** medium
**Depends on:** `openspec/changes/inventory-batch-lot-spec` (breaking rewrite)

C-04 cannot be remediated until the batch/lot model rewrite lands, because the
finding sits on the layer that rewrite replaces. No code has been touched.

---

## BUG-005 · `sales_order_items` has no tax or discount columns

**Status:** `OPEN` — **Severity:** medium-high

SALES-016: a sales order cannot carry per-line tax or discount, so converting one
to an invoice either drops those values or hard-codes `discount_type: 'none'`.
This needs a schema migration, so it is separate work and deliberately not folded
into any behaviour-only change.

---

## Not bugs — deliberate decisions, recorded so they are not re-litigated

- **PUR-016** — the two live `PURCHASE_ORDER` commitment rows (3,000 supplier 1 /
  1,000 supplier 2) are **not** duplicates: different suppliers. Ruled by the
  owner 2026-10-08; no data repair.
- **SALES-005** — an edit that reduces a paid invoice while keeping the total
  positive is intentionally **allowed**; the balance floors at 0 and the invoice
  stays `Paid`. `moneyPaths` scenario 9.3 pins that boundary. Only a non-positive
  total is refused.