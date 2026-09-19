## Returned Invoice — Complete Return, Payment, Refund, Credit & Print History

### Objective

Fix and properly implement the invoice return workflow so that **partial and full returns are handled correctly throughout the system**, including:

* Invoice totals
* Returned quantities and amounts
* Invoice balance
* Refunds
* Customer credits
* Adjustments against other invoices
* Restocking fees
* Payment history
* Customer ledger
* Accounting transactions
* Printed invoice/history

The implementation must preserve the original invoice history. A return must **not rewrite or alter the original sale transaction**.

First inspect the existing implementation, database schema, API/backend logic, frontend calculations, payment/credit logic, and return workflow. Identify the root cause and then implement the fix consistently across the system.

---

# 1. Original Invoice

Example:

**INV-0926-00007**

```text
Item        Qty     Rate     Amount
-------------------------------------
Widget A     3       600      1800
-------------------------------------
Subtotal                     1800
Total                        1800
Paid                         1800
Balance Due                     0
```

The invoice was fully paid.

The original invoice must remain historically accurate even after a return.

Do NOT change the original line from:

```text
Widget A    Qty 3    Rate 600    Amount 1800
```

to Qty 1 simply because 2 units were subsequently returned.

The return is a separate transaction linked to the original invoice.

---

# 2. Partial Return

Customer returns 2 units of Widget A.

Original sale price:

```text
Qty: 3
Rate: 600
```

Returned:

```text
2 × 600 = 1200
```

The return should show:

```text
Return #1

Item        Qty     Rate     Amount
-------------------------------------
Widget A     2       600      1200
-------------------------------------
Total Returned              1200
```

The remaining goods are:

```text
3 originally sold
- 2 returned
----------------
1 remaining
```

Therefore the net value of goods remaining on the invoice is:

```text
1 × 600 = 600
```

---

# 3. Important Balance Logic

Do NOT treat the return simply as a reduction of `Balance Due`.

There are different financial concepts that must remain separate.

### Before return

```text
Original Invoice Total     1800
Paid                       1800
Balance Due                   0
```

### After returning goods worth 1200

The remaining goods are worth:

```text
Current Invoice Value       600
```

The customer has already paid 1800.

Therefore the customer has overpaid the current value of the invoice by:

```text
Paid                       1800
Current Invoice Value       600
--------------------------------
Refund/Credit Due           1200
```

Do NOT display this as:

```text
Balance Due = -1200
```

Instead, clearly distinguish the two concepts.

### Required terminology

**Invoice Balance Due**

How much the customer still owes for the goods currently retained.

**Refund/Credit Due**

How much the business owes the customer because the customer returned goods that had already been paid for.

**Customer Credit Balance**

Credit currently held on the customer's account and available to use against future invoices.

These are different balances and must not be mixed together.

---

# 4. Restocking Fee

The return process must support a **Restocking Fee**.

The fee can be:

* None
* Fixed amount
* Percentage

The fee is deducted from the amount otherwise refundable/creditable to the customer.

The restocking fee must be calculated against the **returned sale value**, not the original invoice total.

### Example: 10% Restocking Fee

Returned goods:

```text
2 × 600 = 1200
```

Restocking fee:

```text
10% of 1200 = 120
```

Therefore:

```text
Returned Value              1200
Restocking Fee               120
--------------------------------
Net Refund/Credit            1080
```

The remaining invoice value is still:

```text
Current Invoice Value         600
```

The restocking fee must NOT reduce the value of the goods remaining on the invoice.

It is a separate financial transaction.

---

# 5. Fixed Restocking Fee

The system must also support a fixed fee.

Example:

```text
Returned Value              1200
Restocking Fee               150
--------------------------------
Net Refund/Credit            1050
```

The fee must be stored separately from the return amount.

---

# 6. Return Financial Summary

The invoice/return screen should clearly show:

```text
Return

Item        Qty     Rate     Amount
-------------------------------------
Widget A     2       600      1200
-------------------------------------
Total Returned              1200
Restocking Fee               120
-------------------------------------
Net Refund/Credit            1080
```

And the invoice's current position should show:

```text
Invoice Summary

Original Invoice Total       1800
Total Returned               1200
--------------------------------
Current Invoice Value         600

Original Payments            1800
Refund/Credit Due             1080
```

The exact display can be adapted to the existing UI, but the underlying values must remain distinct.

---

# 7. Three Possible Return Settlements

The net return amount can be handled in different ways.

## A. Customer Credit

If the customer chooses credit:

```text
Returned Value              1200
Restocking Fee               120
Net Customer Credit          1080
```

The customer's credit balance increases by **1080**.

It must NOT increase by 1200.

The credit transaction must be linked to:

* Original invoice
* Return transaction
* Restocking fee
* Customer

---

## B. Direct Refund

If the customer is refunded:

```text
Returned Value              1200
Restocking Fee               120
Net Refund                   1080
```

Record the actual refund method:

```text
Method: Cash
Reference: REF-0926-00003
Amount: 1080
```

If the refund was through Bank, Card, etc., preserve the actual method.

---

## C. Adjustment Against Another Invoice

The customer may use the return amount against another invoice.

Example:

```text
Returned Value              1200
Restocking Fee               120
Amount Available             1080
```

Then:

```text
Adjusted Against:
INV-0926-00008

Amount: 1080
```

Only 1080 should be applied to the other invoice.

---

# 8. Payment History

The original payments must remain unchanged.

Example:

```text
Payments

Date          Method        Reference          Amount
--------------------------------------------------------
Sep 15, 2026  Cash          PAY-000123          1800
```

If multiple payments were made, show each separately.

A return/refund must NOT overwrite the original payment.

---

# 9. Return Settlement History

Every return must have its own settlement record.

Example:

```text
Return Settlement

Date          Type                Reference          Amount
----------------------------------------------------------------
Sep 16, 2026  Return              RET-0926-00001      1200
Sep 16, 2026  Restocking Fee      RSF-0926-00001       120
Sep 16, 2026  Customer Credit     CR-0926-00005       1080
```

The exact records should reflect what actually happened.

Do not create both a refund and customer credit for the same 1080 unless the user actually performed both transactions.

The same money must never be double-counted.

---

# 10. Multiple Partial Returns

The system must support multiple returns against the same invoice.

Example:

Original:

```text
Widget A    Qty 3    Rate 600    Amount 1800
```

Return #1:

```text
Qty 1 = 600
```

Return #2:

```text
Qty 1 = 600
```

Total returned:

```text
1200
```

Remaining:

```text
Qty 1 = 600
```

Each return must have its own:

* Date
* Reference
* Items
* Quantity
* Amount
* Restocking fee
* Settlement
* Refund/credit/adjustment information

The system must prevent returning more quantity than was originally sold minus quantities already returned.

---

# 11. Full Return

Also support a complete return.

Original:

```text
Widget A    Qty 3    Rate 600    Amount 1800
```

Full return:

```text
Returned Value             1800
```

If restocking fee is 10%:

```text
Returned Value             1800
Restocking Fee              180
--------------------------------
Net Refund/Credit           1620
```

Current invoice value:

```text
0
```

If the original invoice was fully paid:

```text
Original Total             1800
Original Paid              1800
Current Invoice Value         0
Net Refund/Credit           1620
```

The printout should clearly show that the customer paid 1800 originally, returned goods worth 1800, incurred a 180 restocking fee, and therefore received/received as credit 1620.

---

# 12. Complete Invoice Print View

The **Print Invoice** view for an invoice with returns must show the **complete story of the invoice**.

It must not simply show the current invoice state.

A person looking at the printed document should be able to understand:

**What was sold → What was paid → What was returned → What restocking fee was charged → What was refunded/credited/adjusted → What remains on the invoice.**

---

## Original Invoice

Show:

```text
INV-0926-00007

Original Invoice

Item        Qty     Rate     Amount
-------------------------------------
Widget A     3       600      1800
-------------------------------------
Subtotal                     1800
Original Total               1800
```

---

## Original Payments

Show every original payment:

```text
Payments

Date          Method        Reference          Amount
--------------------------------------------------------
Sep 15, 2026  Cash          PAY-000123          1800
```

---

## Return History

Show every return separately:

```text
Returns

Return #1
Date: Sep 16, 2026
Reference: RET-0926-00001

Item        Qty     Rate     Amount
-------------------------------------
Widget A     2       600      1200
-------------------------------------
Total Returned              1200
```

If there are multiple returns, show all of them chronologically.

---

## Restocking Fee

Show the fee separately for each applicable return:

```text
Return #1 Financial Summary

Returned Value              1200
Restocking Fee (10%)         120
--------------------------------
Net Refund/Credit            1080
```

---

## Return Settlement

Show what happened to the net amount:

```text
Return Settlement

Date          Method              Reference       Amount
-----------------------------------------------------------
Sep 16, 2026  Customer Credit      CR-0926-00005   1080
```

Or:

```text
Sep 16, 2026  Cash Refund          REF-0926-00003   1080
```

Or:

```text
Sep 16, 2026  Invoice Adjustment  INV-0926-00008   1080
```

---

# 13. Current Invoice Position

The printed invoice should clearly distinguish the original invoice from its current position.

Example:

```text
Invoice Summary

Original Invoice Total       1800
Total Returned               1200
--------------------------------
Current Invoice Value         600

Original Payments            1800

Restocking Fees               120

Net Refund/Credit Due        1080
```

If the 1080 has already been credited/refunded:

```text
Net Refund/Credit Due        1080
Refunded/Credited            1080
--------------------------------
Remaining Refund Due            0
```

Do not show a negative `Balance Due` to represent this situation.

---

# 14. Complete Transaction Timeline

The print view should also contain a chronological transaction history.

Example:

```text
Transaction History

Date          Type              Reference        Amount
----------------------------------------------------------
Sep 15, 2026  Invoice           INV-0926-00007    1800
Sep 15, 2026  Payment           PAY-000123        1800
Sep 16, 2026  Return            RET-0926-00001    1200
Sep 16, 2026  Restocking Fee    RSF-0926-00001     120
Sep 16, 2026  Customer Credit   CR-0926-00005     1080
```

This should be based on actual persisted transactions and relationships, not reconstructed from current totals.

---

# 15. Accounting/Data Integrity

Investigate and verify the entire flow across:

* Database
* Backend
* APIs
* Frontend
* Invoice calculations
* Return transactions
* Payment transactions
* Customer credit
* Customer ledger
* Cash/bank accounts
* Invoice adjustments
* Restocking fee accounting
* Reports
* Print view

The return must be represented as an actual transaction.

The restocking fee must be represented separately.

The refund/credit/adjustment must be represented separately.

Do not fix this only by changing the displayed numbers.

---

# 16. Important Accounting Rules

The implementation must guarantee:

1. Original invoice data is never overwritten.
2. Original payments remain historically accurate.
3. Returned quantities are recorded separately.
4. Returned value is calculated from the original sale price.
5. Returned quantity cannot exceed available sold quantity.
6. Restocking fee is calculated from the returned value.
7. Restocking fee is stored separately.
8. Net refund/credit = Returned Value − Restocking Fee.
9. Customer credit increases only by the net credit amount.
10. Direct refund records only the net refund amount.
11. Invoice adjustment applies only the net adjustment amount.
12. The same return amount cannot be refunded, credited, and adjusted more than once.
13. Multiple returns are supported.
14. Multiple payments are supported.
15. Partial returns are supported.
16. Full returns are supported.
17. The current invoice value reflects the goods remaining after returns.
18. `Balance Due` represents money the customer owes for the remaining invoice value.
19. `Refund/Credit Due` represents money owed by the business to the customer because of returned goods already paid for.
20. These two balances must never be combined or confused.
21. Restocking fees must not reduce the value of goods remaining on the invoice.
22. All related transactions must be linked to the original invoice.
23. Refreshing or reopening the invoice must produce the same results.
24. The printed invoice must contain the complete historical trail.

---

# 17. Final Acceptance Test

For this exact test case:

### Original

```text
Invoice: INV-0926-00007

Widget A    Qty 3    Rate 600    Amount 1800

Original Total       1800
Original Paid        1800
Original Balance        0
```

### Return

Customer returns:

```text
Widget A    Qty 2    Rate 600    Amount 1200
```

Restocking fee:

```text
10% = 120
```

Expected:

```text
Original Invoice Total       1800
Returned Value               1200
Restocking Fee                120
Current Invoice Value         600
Original Paid                1800
Net Refund/Credit             1080
```

If credited:

```text
Customer Credit Created      1080
Remaining Refund Due            0
```

If refunded:

```text
Actual Refund                1080
Remaining Refund Due            0
```

If adjusted:

```text
Invoice Adjustment           1080
Remaining Refund Due            0
```

The printed invoice must show the original invoice, original payment, return, restocking fee, settlement, and final/current position in a clear chronological audit trail.

### Core Principle

**Never replace history with the current state.**

The ERP must preserve:

**Original Sale → Original Payments → Returns → Restocking Fees → Refund/Credit/Adjustment → Current Invoice Position**

as separate, linked transactions.

