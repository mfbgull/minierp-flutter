# ValidatePayment edit-mode fix spec

Spec built from the user's report and a short clarifying interview, then completed with the design decisions below after the first implementation pass. Implementation status is tracked at the end of this file.

## Source report

_user's message (paraphrased):_
`_validatePayment()`'s edit-mode check passes `_remainingBalance` (balance after the in-progress payment) where its own unit-test contract expects the balance before. The test at `test/calculations/extra_calculations_test.dart:308` asserts `doesPaymentExceedBalance(90, 100) == false`. By that arithmetic, recording a full payment on an invoice with balance 100 computes `remaining = 100 - 100 = 0`, then checks `100 > 0` and blocks. So edit-mode "record payment" in full appears broken too. The reporter left it alone because it is a different flow, was not reported, and the decision of whether edit-mode should clamp or allow is the implementer's call. They asked whether to verify and fix it.

## What the code currently does

### The rule being called

`lib/features/sales/calculations/invoice_rules.dart` defines:

```dart
bool doesPaymentExceedBalance(num totalPaymentAmount, num remainingBalance) {
  return totalPaymentAmount > remainingBalance;
}
```

The unit test contract for this function is at `test/calculations/extra_calculations_test.dart:308`:

```dart
expect(doesPaymentExceedBalance(110, 100), true);
expect(doesPaymentExceedBalance(90, 100), false);
```

That is a "payment vs balance-before-this-payment" contract: the second argument is the balance the payment is being compared against, and the test passes `100` as that balance for both calls.

### The form's payment helper

`_SalesInvoiceFormPageState` exposes:

```dart
num get _paymentSum => _paymentMethods.fold<num>(0, (s, m) => s + m.amount);

num get _remainingBalance => _isEdit
    ? (widget.invoice!.balanceAmount - _paymentSum - _creditOffset)
    : (calculateTotal(_filledLines, _scope, _invoiceDiscount) - _paymentSum - _creditOffset);
```

And `_validatePayment()` calls:

```dart
if (doesPaymentExceedBalance(_paymentSum, _remainingBalance)) { ... }
```

### The edit-mode bug path

In edit mode, `_remainingBalance` already subtracts `_paymentSum`. So when a user enters a payment equal to the unpaid balance, the operand passed to `doesPaymentExceedBalance` is the after-payment remaining, not the balance before the new payment.

Concrete example from the report:
- `widget.invoice!.balanceAmount = 100`
- user enters a single payment method of `100`
- `_paymentSum = 100`
- `_remainingBalance = 100 - 100 - _creditOffset = 0` (ignoring credit offset for the moment)
- `doesPaymentExceedBalance(100, 0)` → `100 > 0` → `true`
- edit-mode record payment is blocked even though it should be allowed

That is the mismatch the report describes: the same function is being asked to do two different comparisons depending on mode, and edit mode feeds it the wrong operand.

### The create-mode guard is different

Create mode does not use `_validatePayment` for the overpayment check. `_save()` has its own inline guard:

```dart
if (!_isEdit && _recordPayment && _paymentSum > 0) {
  final collectible = calculateTotal(filled, _scope, _invoiceDiscount);
  if (_paymentSum + _creditOffset > collectible) { ... }
}
```

That guard compares `_paymentSum + _creditOffset` against the collectible total **before** the payment is applied. The comment above it notes `_remainingBalance` is the balance after, so it is not the right operand in create mode. In other words, create mode already uses the before-payment operand, and edit mode currently does not.

## Interview outcomes

### Scope
- Cover both edit-mode paths: the "record payment" path and the existing-payment edit path (`_onEditPayment`).

### Balance moment in edit mode
- Undecided. The interview left it open for the spec to reason through and propose. It is not settled whether edit-mode validation should check against the balance before the new payment, or whether the current after-payment operand is intended.

### Create-mode overpayment fix
- In scope: the spec should propose a concrete fix for the noted create-mode duplication risk / overpayment guard, not just diagnose it.

### Existing-payment edit guard
- The existing payment edit path (`_onEditPayment`) should be validated against the current unpaid balance. The interview selected "validate against unpaid" for that path.

### Credit offset in edit mode
- Undecided. It is not yet settled whether edit-mode credit-offset behavior should match create-mode or be defined separately.

### Toast wording
- Undecided. Whether the edit-mode overpayment toast should reuse `paymentsErrorAmountExceedsBalance` or use a distinct edit-mode message is left for the spec.

### Stop-on-failure behavior for edit-mode record payment
- Undecided. Whether edit-mode should stop on the first failed payment method or attempt all positive methods like create-mode is left for the spec.

### Create-mode operand for the overpayment fix
- Undecided. Whether the create-mode fix should check `payment + creditOffset` against the collectible total, or check payment alone against the invoice total before credit, is left for the spec.

### Server reload for edit-mode balance
- Edit-mode record-payment validation should re-read the invoice's `balanceAmount` from the server before validating, rather than relying on the already-loaded in-memory invoice object. The interview selected "reload balance".

### Where the create-mode guard should live
- Create-mode should reuse `_validatePayment` rather than keeping a separate inline guard in `_save()`. The interview selected "reuse _validatePayment".

### `doesPaymentExceedBalance` call contract
- Undecided. It is not yet settled whether the function should be standardized as `(totalPayment, balanceBeforePayment)`, or whether the function's current meaning should stay and only the call sites should be corrected.

## Resolved design decisions

The interview left several items open. They are now settled, with the reasoning that settles them:

1. **Edit-mode operand semantics — resolved: balance BEFORE the new payment.**
   `_validatePayment` compares `_paymentSum` against `doesPaymentExceedBalance`'s contract operand
   (the balance before this payment), implemented as `_balanceBeforePayment = _remainingBalance +
   _paymentSum`. In edit mode that collapses to the invoice's unpaid `balance_amount`; in create mode
   it collapses to `calculateTotal - _creditOffset`, which is exactly the old inline guard's
   `_paymentSum + _creditOffset > collectible` rearranged.
2. **Credit offset in edit mode — resolved: do NOT subtract it again.**
   The server folds `credit_offset` into `paid_amount` (`paid_amount = cash + credit_offset`, see
   `server/src/models/AGENTS.md` and `customerStoreCredit.test.ts`: 400 credit on a 1,000 invoice
   yields `paid_amount 400, balance_amount 600`). `balance_amount` is therefore already net of the
   offset, so `_remainingBalance`'s edit branch subtracting `_creditOffset` double-counted it: it
   understated the panel's Balance row and capped collectible cash below what the invoice owes.
   Create mode computes its total from the lines (which know nothing about credit), so it keeps the
   subtraction.
3. **Credit-pool check in edit mode — resolved: only credit applied by THIS save.**
   `_creditOffset > _availableCustomerCredit` would block every later payment on an invoice that
   used store credit, because that credit was already consumed from the pool when the offset was
   posted. Edit mode now validates only the delta above the invoice's saved offset; create mode
   still validates the whole offset it is about to apply.
4. **Toast wording — resolved: reuse `paymentsErrorAmountExceedsBalance`.**
   The balance shown in the message is now the correct before-payment balance, so the wording needs
   no edit-mode variant.
5. **Stop-on-failure — resolved: keep the existing behaviour.**
   Edit mode stops at the first failed method; create mode keeps attempting every method. Unchanged
   by this spec.
6. **Create-mode operand — resolved: `payment + creditOffset` against the collectible total.**
   Achieved by routing the create guard through `_validatePayment` (interview answer: "reuse
   `_validatePayment`") instead of the separate inline check in `_save`. Side benefit: create mode
   gains the credit-pool check the inline guard never had. Edit mode stays excluded from that call —
   its payments are recorded separately via `_recordPayments`, and a zero payment sum must not block
   the invoice PUT.
7. **`doesPaymentExceedBalance` contract — resolved: standardise on (payment, balanceBeforePayment).**
   The unit test at `test/calculations/extra_calculations_test.dart:308` is the source of truth and
   was not changed; the function's doc comment now states the contract explicitly and the call site
   was corrected (`_balanceBeforePayment`).
8. **Existing-payment edit validation — resolved: bounded by the current unpaid balance.**
   The new amount must be `> 0` and must not push the invoice negative. Because `balance_amount`
   already contains this payment, the headroom is `balance_amount + p.amount + sum(payments pending
   deletion)`. Pending deletions buy headroom back because their amounts return to the collectible
   pool when the invoice PUT lands.
9. **Reload failure mode — resolved: fall back to the in-memory balance.**
   A failed refresh (or a response that does not carry this invoice's id) keeps the page-load value;
   the server re-validates the allocation regardless, so a stale read can only cost a clearer error
   message, while aborting would make Record Payment fail silently on a flaky connection.
10. **Round/timing edge cases — resolved: no special rounding.**
    The operand is read once per validation attempt from a single refreshed value, so there is no
    window where the payment sum and the balance come from different reads. Rounding stays with
    `Formatters.currency` on display and the server's own `parseCurrency` on write.
11. **Test updates — resolved: the regression suite is listed under Implementation status.**

## Implementation status

### Done in the first pass (verified)

- `_balanceBeforePayment` getter; `_validatePayment` uses it instead of `_remainingBalance`.
- `_save`'s create-mode inline overpayment guard replaced by a call to `_validatePayment`.
- `doesPaymentExceedBalance` doc comment states the before-payment contract.
- Regression test `full payment against the balance is allowed` in
  `test/calculations/extra_calculations_test.dart`.

### Completed in the second pass (verified)

- `_remainingBalance` edit branch no longer subtracts `_creditOffset` (decision 2), so a settled
  store-credit invoice neither blocks Record Payment nor shows a short Balance.
- Credit-pool check scoped to credit applied by this save (decision 3).
- `_refreshEditBalance()` re-reads the invoice before edit-mode validation (decision 9), before an
  existing-payment edit, and after each successful write so the panel's Balance stays honest.
- `_onEditPayment` validates `> 0` and against `balance_amount + p.amount + pending deletions`
  (decision 8).
- `_onEditPayment`'s dialog controllers moved into a `_PaymentEditFields` state owned by the dialog
  route — disposing them in the caller raced the route's exit animation and threw "A
  TextEditingController was used after being disposed" while the dialog tore down.

### Widget tests (`test/sales_invoice_form_page_test.dart`, group `edit-mode payment validation`)

1. `a payment equal to the full balance is recorded` — the reported bug.
2. `a payment above the unpaid balance is refused` — nothing posted, cap shown is the before-payment
   balance.
3. `validation trusts the balance the server reports now, not the one captured at page load` — both
   the refusal on a stale 1,000 and the acceptance of the refreshed 600.
4. `a settled store-credit offset neither blocks recording nor shrinks the collectible balance` —
   400 credit already applied, 600 cash still collectible.
5. `editing an existing payment is capped at the unpaid balance` — 5,000 refused against a
   1,000 balance + 100 already recorded.
6. `editing an existing payment to zero is refused`.

### Known limitation, out of scope here

`server/src/models/Payment.ts::update` rejects **any** amount change on an existing payment (PAY-04:
"void-and-reissue"), so the client-side guard on `_onEditPayment` is defence in depth rather than
the binding constraint for that path today. Relaxing or surfacing that server policy is a separate
product decision.

### Verification run

- `flutter analyze` (whole project): no issues.
- `flutter test test/sales_invoice_form_page_test.dart`: 58 passed.
- `flutter test test/calculations/ test/features/sales/ test/models_test.dart`: 139 passed.

## Files likely in play

- `lib/features/sales/calculations/invoice_rules.dart`
- `lib/features/sales/sales_invoice_form_page.dart`
- `test/calculations/extra_calculations_test.dart`

## Non-goals for now

- This spec is intentionally limited to the payment-validation operand problem as reported, plus the
  noted create-mode overpayment guard fix.
- Other payment flows are out of scope unless the interview expands them.
