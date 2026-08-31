# Salary Payment: Multi-Partial & Advance System

## Bug Fix + Feature Spec

**Date:** 2026-08-29  
**Status:** Draft  
**Priority:** High (currently broken — UNIQUE constraint blocks all payments after first partial)

---

## 1. Problem Statement

### Current Bug
When a partial salary payment is made, the system blocks ALL further payments for that month with:
```
UNIQUE constraint failed: salary_payments.employee_id, salary_payments.pay_period
```

**Root cause:** The `idx_salary_payments_unique_period` UNIQUE index on `(employee_id, pay_period)` allows only ONE row per employee per month. But the advance/partial system requires multiple rows.

### Current Architecture (Broken)
```
salary_payments table:
  UNIQUE INDEX idx_salary_payments_unique_period ON (employee_id, pay_period)
```
- `paySalary` controller checks for `payment_type = 'full'` duplicate → allows advance/partial
- But the UNIQUE index blocks the INSERT regardless of payment_type
- Result: only the first payment (of any type) succeeds; all subsequent ones fail

---

## 2. Requirements

### 2.1 Multiple Payments Per Month
- Allow any number of partial/advance payments per employee per month
- Each payment is a separate row in `salary_payments`
- The UNIQUE constraint on `(employee_id, pay_period)` must be removed

### 2.2 Salary History: Single Row Per Month
- The salary history table shows **one row per month** (not one row per payment)
- Row displays: "Rs. 12,000 / Rs. 20,000" format (paid of salary)
- Status indicator: Paid / Partial / Advance
- Double-clicking a row opens a drill-down dialog showing individual payments

### 2.3 Drill-Down Dialog
- Shows a simplified list of individual payments for that month
- Columns: Date, Amount, Type badge (Full/Advance/Partial)
- Includes a "Pay More" button to add another payment for the same month
- "Pay More" opens the salary pay dialog pre-filled with the remaining balance

### 2.4 Remaining Balance Tracking
- Salary pay dialog shows: "Already paid: Rs. 8,000 this month"
- Shows remaining balance: "Remaining: Rs. 12,000"
- If type is "advance", shows salary amount as context
- Balance is calculated from all payments in the current pay_period

### 2.5 Overpayment Handling
- If total payments exceed salary (e.g., Rs. 22,000 paid on Rs. 20,000 salary):
  - The excess (Rs. 2,000) is automatically treated as advance for next month
  - Next month's remaining balance starts at: salary - advance_carryover
  - The overpayment creates a separate advance record for the next month's pay_period

### 2.6 Advance Carry-Over
- Advances from prior months automatically reduce next month's remaining balance
- Example: Rs. 3,000 advance in August → September remaining = Rs. 20,000 - Rs. 3,000 = Rs. 17,000
- The carry-over is calculated, not stored — it's derived from historical payments

### 2.7 GL Accounting
- **Keep separate journal entries per payment** (current behavior)
- Each partial/advance posts: `Dr Wages & Salaries (6100) → Cr Cash/Bank`
- This ensures the trial balance always reflects actual cash outflows
- Standard ERP practice — no consolidation needed

### 2.8 Duplicate Guard
- "Full" payment still blocked if a full payment already exists for the month
- Advance and partial payments are always allowed (no duplicate check)
- The guard is in the controller, not the database index

---

## 3. Database Changes

### 3.1 Remove UNIQUE Index
```sql
-- Migration: remove-salary-unique-period.sql
DROP INDEX IF EXISTS idx_salary_payments_unique_period;
```

### 3.2 Add Carry-Over Column (Optional Enhancement)
```sql
-- Track advance carry-over per month for audit trail
ALTER TABLE salary_payments ADD COLUMN advance_carryover DECIMAL(15,2) DEFAULT 0;
```
**Decision:** Not needed for v1 — carry-over is derived from historical payments.

---

## 4. Backend Changes

### 4.1 Controller: `paySalary`
- Remove the UNIQUE index conflict (handled by dropping the index)
- Keep the duplicate guard for 'full' payments (application-level check)
- Add validation: if type is 'partial', warn if amount > remaining balance (but allow)
- When overpayment occurs, create an advance record for next month automatically

### 4.2 Controller: New `getSalaryMonthDetail` Endpoint
```
GET /employees/:id/salary/month/:payPeriod
```
Returns all individual payments for a specific month:
```json
{
  "success": true,
  "data": {
    "pay_period": "2026-08",
    "employee_salary": 20000,
    "total_paid": 12000,
    "remaining": 8000,
    "payments": [
      {"id": 1, "amount": 8000, "payment_type": "advance", "payment_date": "2026-08-05", "payment_method": "bank"},
      {"id": 2, "amount": 4000, "payment_type": "partial", "payment_date": "2026-08-15", "payment_method": "cash"}
    ],
    "advance_carryover": 0
  }
}
```

### 4.3 Model: `getSalaryHistory` Aggregation
- Modify to aggregate payments by `pay_period`
- Return one record per month with:
  - `pay_period` (YYYY-MM)
  - `total_paid` (SUM of amounts)
  - `employee_salary` (from employees table)
  - `status` (paid/partial/advance)
  - `payment_count` (number of individual payments)

### 4.4 Model: `getAdvanceCarryover`
```sql
SELECT COALESCE(SUM(amount), 0) as total_advance
FROM salary_payments
WHERE employee_id = ? 
  AND payment_type = 'advance'
  AND pay_period < ?
  AND pay_period >= date(?, '-3 months')  -- Only carry last 3 months
```

---

## 5. Frontend Changes

### 5.1 Salary History Tab (`employee_detail_dialog.dart`)
- Change from individual payment rows to aggregated monthly rows
- Columns: Month | Paid of Salary | Status | Actions
- "Paid of Salary" shows: `Rs. 12,000 / Rs. 20,000`
- Status shows: Paid (green) / Partial (amber) / Advance (blue)
- Actions: View details (eye icon)
- Double-click or eye icon opens drill-down dialog

### 5.2 Drill-Down Dialog (`salary_month_detail_dialog.dart` — NEW)
- Opens when clicking a month row
- Header: "Salary for August 2026 — Rs. 12,000 of Rs. 20,000"
- List of individual payments with: Date | Amount | Type badge
- "Pay More" button → opens salary pay dialog with pre-filled remaining amount
- "Close" button

### 5.3 Salary Pay Dialog (`salary_pay_dialog.dart`)
- Add "Already paid this month: Rs. 8,000" banner
- Add "Remaining balance: Rs. 12,000" banner
- Pre-fill amount field with remaining balance when opened from drill-down
- If overpayment would occur, show warning: "This will create an advance for next month"

### 5.4 Localization
New keys needed:
- `employeesAlreadyPaid`: "Already paid this month"
- `employeesRemainingBalance`: "Remaining balance"
- `employeesPayMore`: "Pay More"
- `employeesMonthDetail`: "Salary Details"
- `employeesOverpaymentWarning`: "This amount exceeds the salary. The excess will be applied as advance for next month."

---

## 6. API Contract

### 6.1 Modified: `POST /employees/:id/salary/pay`
**Request:**
```json
{
  "amount": 8000,
  "payment_date": "2026-08-05",
  "payment_method": "bank",
  "payment_type": "partial",
  "reference_no": "REF-001",
  "notes": "First partial payment"
}
```
**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "journal_entry_id": 42,
    "advance_created": null
  }
}
```
If overpayment occurs, `advance_created` contains the new advance payment ID for next month.

### 6.2 New: `GET /employees/:id/salary/month/:payPeriod`
**Response (200):**
```json
{
  "success": true,
  "data": {
    "pay_period": "2026-08",
    "employee_salary": 20000,
    "total_paid": 12000,
    "remaining": 8000,
    "payments": [...],
    "advance_carryover": 0
  }
}
```

### 6.3 Modified: `GET /employees/:id/salary/history`
Now returns aggregated monthly data instead of individual payments:
```json
{
  "success": true,
  "data": [
    {
      "pay_period": "2026-08",
      "total_paid": 12000,
      "employee_salary": 20000,
      "status": "partial",
      "payment_count": 2
    }
  ]
}
```

---

## 7. Implementation Order

1. **Database:** Drop UNIQUE index (migration)
2. **Backend:** Update `getSalaryHistory` to aggregate by month
3. **Backend:** Add `getSalaryMonthDetail` endpoint
4. **Backend:** Update `paySalary` to handle overpayment → auto-create advance
5. **Frontend:** Update salary history tab to show monthly aggregated rows
6. **Frontend:** Create drill-down dialog for month details
7. **Frontend:** Update salary pay dialog with remaining balance context
8. **Frontend:** Add localization strings
9. **Test:** Verify partial payments work, history shows correctly, drill-down opens

---

## 8. Edge Cases

| Scenario | Expected Behavior |
|---|---|
| First payment of month (any type) | Allowed — creates first row |
| Second partial payment | Allowed — adds another row |
| Advance after partial | Allowed — adds another row |
| Full payment after partial | Blocked — "Full salary already paid for August 2026" (if full exists) |
| Full payment after advance | Allowed — adds a row (different from advance) |
| Overpayment (Rs. 22,000 on Rs. 20,000) | Allowed — excess Rs. 2,000 auto-creates advance for next month |
| Payment in different month | Allowed — different pay_period |
| Delete one payment in a multi-payment month | Allowed — recalculates remaining balance |
| Delete all payments in a month | Allowed — month disappears from history |

---

## 9. Testing Checklist

- [ ] Pay Rs. 8,000 partial → success, shows in history
- [ ] Pay Rs. 4,000 partial again → success, history shows "Rs. 12,000 / Rs. 20,000"
- [ ] Pay Rs. 8,000 advance → success, shows in history
- [ ] Try full payment after partial → blocked with clear message
- [ ] Pay Rs. 22,000 (overpay) → success, Rs. 2,000 advance created for next month
- [ ] Double-click month row → drill-down dialog opens with individual payments
- [ ] Click "Pay More" in drill-down → salary pay dialog opens with remaining amount
- [ ] Salary pay dialog shows "Already paid: Rs. 12,000" and "Remaining: Rs. 8,000"
- [ ] Next month shows remaining balance reduced by advance carry-over
- [ ] GL trial balance shows correct salary expense
- [ ] Delete one payment → remaining balance recalculates
