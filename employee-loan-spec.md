# Employee Loan System — Feature Spec

**Date:** 2026-08-31  
**Status:** Draft  
**Module:** Employee Management → Loans (4th tab)

---

## 1. Overview

Add a **standalone employee loan tracking system** that is completely separate from salary. Loans are cash outflows from the company to employees, tracked with GL journal entries, and repaid either through salary deductions or direct payments.

### Key Decisions (from user interview)

| Decision | Choice |
|----------|--------|
| UI location | 4th tab "Loans" in employee detail dialog |
| Interest | Interest-free (amount borrowed = amount repaid) |
| Fund flow | Cash outflow + GL journal entries on disbursement |
| Repayment type | Flexible — employee can pay any amount each month |
| Repayment modes | Salary deduction + direct cash/bank payment |
| Multiple active loans | Yes — employee can have multiple simultaneous loans |
| Deduction limit | No limit on salary deduction amount |
| Loan statuses | Active / Completed / Overdue / Written-off |
| Loan form | Full form (amount, date, purpose, due date, installment, notes, payment method) |
| Repay button | Both top-level + per-row on each active loan |
| Salary integration | Inline in salary pay dialog (banner + deduction field) |
| GL accounts | New 1300 Loan Receivable + new 6300 Loan Write-off (seeded in migration, not user-configured) |
| Navigation | Employee detail dialog only (4th tab) — no global sidebar |
| Overdue logic | User sets due date; system marks overdue when current date > due date and balance > 0 |

---

## 2. Database Schema

### 2.1 New Table: `employee_loans`

```sql
CREATE TABLE IF NOT EXISTS employee_loans (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id     INTEGER NOT NULL REFERENCES employees(id),
    amount          REAL NOT NULL,                   -- total loan amount disbursed
    balance         REAL NOT NULL,                   -- remaining balance (= amount - sum of repayments)
    purpose         TEXT,                            -- e.g. "Medical", "Personal", "Emergency"
    payment_method  TEXT DEFAULT 'cash',             -- cash | bank
    disbursement_date TEXT NOT NULL,                 -- YYYY-MM-DD
    due_date        TEXT,                            -- YYYY-MM-DD (required, marks overdue)
    monthly_installment REAL DEFAULT 0,              -- suggested monthly amount (for salary deduction default)
    status          TEXT NOT NULL DEFAULT 'active'   -- active | completed | overdue | written_off
        CHECK (status IN ('active', 'completed', 'overdue', 'written_off')),
    written_off_amount REAL DEFAULT 0,              -- amount forgiven (set on write-off)
    notes           TEXT,
    journal_entry_id INTEGER,                        -- GL journal entry for disbursement
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_employee_loans_employee ON employee_loans(employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_loans_status ON employee_loans(status);
```

### 2.2 New Table: `employee_loan_repayments`

```sql
CREATE TABLE IF NOT EXISTS employee_loan_repayments (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id         INTEGER NOT NULL REFERENCES employee_loans(id),
    employee_id     INTEGER NOT NULL REFERENCES employees(id),
    amount          REAL NOT NULL,                   -- repayment amount
    payment_date    TEXT NOT NULL,                   -- YYYY-MM-DD
    payment_method  TEXT DEFAULT 'cash',             -- cash | bank
    reference_no    TEXT,
    notes           TEXT,
    repayment_type  TEXT NOT NULL DEFAULT 'direct'   -- direct | salary_deduction
        CHECK (repayment_type IN ('direct', 'salary_deduction')),
    journal_entry_id INTEGER,                        -- GL journal entry (direct payments only)
    salary_payment_id INTEGER,                       -- linked salary payment (salary deductions only)
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_loan_repayments_loan ON employee_loan_repayments(loan_id);
CREATE INDEX IF NOT EXISTS idx_loan_repayments_employee ON employee_loan_repayments(employee_id);
```

### 2.3 Migration Strategy

```sql
-- Migration file: add-employee-loans.sql
-- Creates both tables above.
-- No new chart_of_accounts entries needed (see §5 for GL logic).
```

---

## 3. Backend API Endpoints

### 3.1 Routes (add to `server/src/routes/employees.ts`)

```typescript
// Employee loans
router.get('/:id/loans',              requirePermission('employees', 'read'),    employeeController.getLoans);
router.post('/:id/loans',             requirePermission('employees', 'update'),  employeeController.createLoan);
router.get('/:id/loans/:loanId',      requirePermission('employees', 'read'),    employeeController.getLoanDetail);
router.put('/:id/loans/:loanId',      requirePermission('employees', 'update'),  employeeController.updateLoan);
router.post('/:id/loans/:loanId/repay', requirePermission('employees', 'update'), employeeController.repayLoan);
router.delete('/:id/loans/:loanId',   requirePermission('employees', 'update'),  employeeController.deleteLoan);
router.post('/:id/loans/:loanId/write-off', requirePermission('employees', 'update'), employeeController.writeOffLoan);
router.delete('/:id/loans/:loanId', requirePermission('employees', 'update'), employeeController.deleteLoan);
router.post('/:id/loans/:loanId/repayments/:repaymentId/void', requirePermission('employees', 'update'), employeeController.voidLoanRepayment);
```

### 3.2 API Contract

#### `POST /employees/:id/loans` — Create Loan

**Request:**
```json
{
  "amount": 50000,
  "disbursement_date": "2026-08-31",
  "due_date": "2026-12-31",
  "purpose": "Medical",
  "payment_method": "bank",
  "monthly_installment": 12500,
  "notes": "Emergency medical expense"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "employee_id": 42,
    "amount": 50000,
    "balance": 50000,
    "purpose": "Medical",
    "disbursement_date": "2026-08-31",
    "due_date": "2026-12-31",
    "monthly_installment": 12500,
    "status": "active",
    "payment_method": "bank",
    "journal_entry_id": 88,
    "created_at": "2026-08-31T10:00:00Z"
  }
}
```

#### `GET /employees/:id/loans` — List All Loans

**Response (200):**
```json
{
  "success": true,
  "data": {
    "loans": [
      {
        "id": 1,
        "amount": 50000,
        "balance": 25000,
        "purpose": "Medical",
        "status": "active",
        "disbursement_date": "2026-08-31",
        "due_date": "2026-12-31",
        "monthly_installment": 12500,
        "repaid_amount": 25000,
        "repayment_count": 3,
        "is_overdue": false
      }
    ],
    "summary": {
      "total_loans": 3,
      "active_loans": 1,
      "total_outstanding": 25000,
      "total_repaid": 75000,
      "overdue_loans": 0
    }
  }
}
```

#### `POST /employees/:id/loans/:loanId/repay` — Record Repayment

**Request:**
```json
{
  "amount": 12500,
  "payment_date": "2026-09-30",
  "payment_method": "bank",
  "reference_no": "LOAN-REP-001",
  "notes": "September repayment",
  "salary_payment_id": null
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "amount": 12500,
    "loan_balance": 12500,
    "loan_status": "active",
    "journal_entry_id": 92
  }
}
```

#### `POST /employees/:id/loans/:loanId/write-off` — Write Off Loan

**Request:**
```json
{
  "reason": "Employee left company, forgiving remaining balance"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "status": "written_off",
    "written_off_amount": 12500,
    "balance": 0,
    "journal_entry_id": 95
  }
}
```

#### `GET /employees/:id/loans/:loanId` — Loan Detail with Repayment History

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "amount": 50000,
    "balance": 12500,
    "purpose": "Medical",
    "status": "active",
    "disbursement_date": "2026-08-31",
    "due_date": "2026-12-31",
    "monthly_installment": 12500,
    "payment_method": "bank",
    "notes": "Emergency medical expense",
    "journal_entry_id": 88,
    "repayments": [
      {
        "id": 1,
        "amount": 12500,
        "payment_date": "2026-09-30",
        "repayment_type": "salary_deduction",
        "salary_payment_id": 42,
        "journal_entry_id": null
      },
      {
        "id": 2,
        "amount": 12500,
        "payment_date": "2026-10-15",
        "repayment_type": "direct",
        "salary_payment_id": null,
        "journal_entry_id": 92
      }
    ]
  }
}
```

---

## 4. Backend Controller Logic

### 4.1 `createLoan`

1. Validate required fields (`amount > 0`, `disbursement_date`, `due_date`)
2. Insert into `employee_loans` with `balance = amount`, `status = 'active'`
3. Post GL journal entry via `AccountingService.postLoanDisbursement()`:
   - **Dr 1300 Employee Loan Receivable** (new account — see §5)
   - **Cr 1000 Cash** or **1010 Bank** (based on `payment_method`)
4. Update `journal_entry_id` on the loan record
5. Return created loan

### 4.2 `repayLoan`

1. Validate loan exists and is `active` (not `completed`, `written_off`)
2. Validate `amount > 0` and `amount <= balance`
3. Insert into `employee_loan_repayments`
4. Update `employee_loans.balance -= amount`
5. If `balance == 0`, set `status = 'completed'`
6. If `balance > 0` and `repayment_type == 'direct'`, post GL journal entry:
   - **Dr 1000/1010 Cash/Bank**
   - **Cr 1300 Employee Loan Receivable**
7. If `repayment_type == 'salary_deduction'`:
   - Store `salary_payment_id` reference
   - **No separate GL entry** (the salary payment already posts Dr 6100 Cr Cash; the loan deduction is a business-layer reduction of the net cash paid to the employee, not a separate GL transaction)
8. Return updated balance and status

### 4.3 `writeOffLoan`

1. Validate loan exists and is `active` (not already `completed` or `written_off`)
2. Record the remaining `balance` as `written_off_amount`
3. Post GL journal entry via `AccountingService.postLoanWriteOff()`:
   - **Dr 6300 Loan Write-off** (expense — forgiveness of debt)
   - **Cr 1300 Employee Loan Receivable** (for the remaining balance)
4. Set `balance = 0`, `status = 'written_off'`
5. Update `journal_entry_id` on the loan record
6. Return updated loan with `written_off_amount`

### 4.4 `getLoans` (list)

1. Query all loans for employee, ordered by `disbursement_date DESC`
2. For each loan, compute `repaid_amount = amount - balance`
3. Compute `repayment_count` from `employee_loan_repayments`
4. Compute `is_overdue` = `(status == 'active' AND due_date < CURRENT_DATE)`
5. Auto-update status: if `status == 'active'` and `due_date < CURRENT_DATE`, update to `'overdue'`
6. Compute summary: total active, total outstanding, total repaid, overdue count

### 4.5 `getLoanDetail`

1. Fetch loan + all repayments ordered by `payment_date ASC`
2. Return combined response

### 4.6 `voidLoanRepayment`

1. Validate repayment exists and belongs to this loan
2. If `repayment_type == 'direct'`: void GL lines via `AccountingService.voidJournalLinesByReference('LOAN_REPAYMENT', repaymentId)`
3. Restore loan balance: `balance += repayment_amount`
4. If loan was `completed`, revert status to `active`
5. Delete the repayment record
6. Return updated loan

### 4.7 `deleteLoan`

1. Validate loan exists
2. If loan has any repayments: reject with "Cannot delete loan with repayment history"
3. Void GL lines via `AccountingService.voidJournalLinesByReference('LOAN_DISBURSEMENT', loanId)`
4. Delete the loan record from `employee_loans`
5. Return success

---

## 5. GL Account Handling

### 5.1 New Accounts (seeded in migration)

Two new accounts are added during the `add-employee-loans.sql` migration. These follow the same pattern as existing seed accounts (e.g., 4150 Restocking Fee Income, 3200 Owner Capital).

```sql
-- Asset: money the company is owed by employees
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description)
VALUES ('1300', 'Employee Loan Receivable', 'asset', 'debit', 'employee_loan_receivable', 'Loans advanced to employees');

-- Expense: forgiven loan balances (write-offs)
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description)
VALUES ('6300', 'Loan Write-off', 'expense', 'debit', 'loan_write_off', 'Employee loans written off / forgiven');
```

**Account rationale:**
- `1300` sits between `1200 Inventory Asset` and `2000 AP` in the chart — a current asset representing receivables from employees
- `6300` sits after `6100 Wages & Salaries` — an operating expense for forgiven debt. Using a dedicated account (not 6000 Operating Expenses) ensures write-offs are separately trackable on the trial balance and P&L

### 5.2 GL Posting Matrix

| Event | Debit | Credit | reference_type | Notes |
|-------|-------|--------|----------------|-------|
| Loan disbursement | 1300 Employee Loan Receivable | 1000/1010/1020/1030/1040 Cash/Bank | `LOAN_DISBURSEMENT` | Cash outflow from company |
| Direct repayment | 1000/1010/1020/1030/1040 Cash/Bank | 1300 Employee Loan Receivable | `LOAN_REPAYMENT` | Cash inflow back to company |
| Salary deduction repayment | *(no GL entry)* | *(no GL entry)* | — | See §5.3 |
| Write-off | 6300 Loan Write-off | 1300 Employee Loan Receivable | `LOAN_WRITE_OFF` | Forgives remaining balance |
| Void disbursement | 1000/1010 Cash/Bank | 1300 Employee Loan Receivable | — | Reverses original entry |
| Void direct repayment | 1300 Employee Loan Receivable | 1000/1010 Cash/Bank | — | Reverses repayment entry |

### 5.3 Salary Deduction GL Handling (detailed)

When a loan is repaid via salary deduction:

1. **Salary payment** posts its own GL entry (existing flow):
   - `Dr 6100 Wages & Salaries → Cr 1000/1010 Cash/Bank` for the **full salary amount**
2. **Loan repayment** record is created with `repayment_type = 'salary_deduction'` and `salary_payment_id` linking to the salary payment
3. **No separate GL entry** is posted for the loan repayment

**Why no GL entry for salary deductions?**
- The salary payment GL entry already reflects the actual cash outflow (`Cr Cash/Bank`)
- The loan deduction is a business-layer allocation of how much cash the employee *receives in hand* vs. how much is *applied to their loan*
- Posting a second entry (`Dr Cash → Cr Loan Receivable`) would double-count the cash movement
- The loan receivable balance is reduced by the business logic (balance -= amount), not by a GL entry
- This matches standard ERP practice: salary deductions are internal allocations, not external cash movements

**Net effect on financial statements:**
- Cash/Bank: reduced by full salary amount (correct — that's what left the company)
- Wages & Salaries expense: full salary amount (correct — that's the employee's compensation)
- Loan Receivable: reduced by deduction amount (correct — employee owes less)
- Employee net take-home: salary - deduction (business logic, not a GL concept)

### 5.4 GL Posting Functions (in `accountingService.ts`)

Three new static methods, following the exact pattern of `postSalaryEntry`, `postOwnerCapitalEntry`, etc.:

```typescript
/**
 * Post loan disbursement. Dr 1300 Loan Receivable, Cr Cash/Bank.
 * Called inside createLoan transaction.
 */
static postLoanDisbursement(
  db: Database.Database,
  args: {
    loanId: number;
    employeeName: string;
    employeeCode: string;
    amount: number;
    disbursementDate: string;
    paymentMethod?: string;
    userId?: number;
  }
): PostedEntry | null {
  if (!args.amount || args.amount <= 0) return null;

  const loanReceivable = AccountingService.getAccountByCode(db, '1300');
  const cashCode = AccountingService._cashOrBankAccountCode(args.paymentMethod);
  const cashAcct = AccountingService.getAccountByCode(db, cashCode);
  if (!loanReceivable || !cashAcct) {
    throw new Error(
      `Chart of accounts is missing: 1300 (Employee Loan Receivable) or ${cashCode}`
    );
  }

  return AccountingService.postEntry(db, {
    entry_date: args.disbursementDate,
    description: `Loan to ${args.employeeName} (${args.employeeCode}) — ${args.amount.toFixed(2)}`,
    reference_type: 'LOAN_DISBURSEMENT',
    reference_id: args.loanId,
    created_by: args.userId,
    lines: [
      { account_id: loanReceivable.id, debit: args.amount, description: `Loan receivable for ${args.employeeCode}` },
      { account_id: cashAcct.id, credit: args.amount, description: `Cash disbursed to ${args.employeeCode}` },
    ],
  });
}

/**
 * Post direct loan repayment. Dr Cash/Bank, Cr 1300 Loan Receivable.
 * Called inside repayLoan transaction (direct repayments only).
 */
static postLoanRepayment(
  db: Database.Database,
  args: {
    repaymentId: number;
    loanId: number;
    employeeName: string;
    employeeCode: string;
    amount: number;
    paymentDate: string;
    paymentMethod?: string;
    userId?: number;
  }
): PostedEntry | null {
  if (!args.amount || args.amount <= 0) return null;

  const loanReceivable = AccountingService.getAccountByCode(db, '1300');
  const cashCode = AccountingService._cashOrBankAccountCode(args.paymentMethod);
  const cashAcct = AccountingService.getAccountByCode(db, cashCode);
  if (!loanReceivable || !cashAcct) {
    throw new Error(
      `Chart of accounts is missing: 1300 (Employee Loan Receivable) or ${cashCode}`
    );
  }

  return AccountingService.postEntry(db, {
    entry_date: args.paymentDate,
    description: `Loan repayment from ${args.employeeName} (${args.employeeCode}) — ${args.amount.toFixed(2)}`,
    reference_type: 'LOAN_REPAYMENT',
    reference_id: args.repaymentId,
    created_by: args.userId,
    lines: [
      { account_id: cashAcct.id, debit: args.amount, description: `Cash received from ${args.employeeCode}` },
      { account_id: loanReceivable.id, credit: args.amount, description: `Loan receivable reduced for ${args.employeeCode}` },
    ],
  });
}

/**
 * Post loan write-off. Dr 6300 Loan Write-off, Cr 1300 Loan Receivable.
 * Called inside writeOffLoan transaction.
 */
static postLoanWriteOff(
  db: Database.Database,
  args: {
    loanId: number;
    employeeName: string;
    employeeCode: string;
    amount: number;
    writeOffDate: string;
    userId?: number;
  }
): PostedEntry | null {
  if (!args.amount || args.amount <= 0) return null;

  const loanReceivable = AccountingService.getAccountByCode(db, '1300');
  const writeOffAcct = AccountingService.getAccountByCode(db, '6300');
  if (!loanReceivable || !writeOffAcct) {
    throw new Error(
      'Chart of accounts is missing: 1300 (Employee Loan Receivable) or 6300 (Loan Write-off)'
    );
  }

  return AccountingService.postEntry(db, {
    entry_date: args.writeOffDate,
    description: `Loan write-off for ${args.employeeName} (${args.employeeCode}) — ${args.amount.toFixed(2)}`,
    reference_type: 'LOAN_WRITE_OFF',
    reference_id: args.loanId,
    created_by: args.userId,
    lines: [
      { account_id: writeOffAcct.id, debit: args.amount, description: `Loan written off for ${args.employeeCode}` },
      { account_id: loanReceivable.id, credit: args.amount, description: `Loan receivable written off for ${args.employeeCode}` },
    ],
  });
}
```

### 5.5 Void / Reversal Rules

The system uses soft-void (`voided = 1`) via `AccountingService.voidJournalLinesByReference()`. Void rules for loans:

| Void target | Allowed? | Condition | GL effect |
|-------------|----------|-----------|----------|
| Loan disbursement | Yes | Loan has 0 repayments | Void disbursement entry (Dr Cash, Cr Loan Receivable reversed) |
| Loan disbursement | **No** | Loan has ≥1 repayments | Reject: "Cannot delete loan with repayment history" |
| Direct repayment | Yes | Always | Void repayment entry + restore loan balance |
| Salary deduction repayment | Yes | Always | Delete repayment record + restore loan balance (no GL to void) |
| Write-off | Yes | Loan status is `written_off` | Void write-off entry + restore loan balance + set status back to `active` |

**Void implementation pattern** (matching existing `deleteSalaryPayment`):
```typescript
// 1. Void the GL lines
AccountingService.voidJournalLinesByReference(db, referenceType, referenceId, {
  voidedBy: userId,
  voidReason: reason,
});

// 2. Restore loan balance (for repayment voids)
db.prepare(`UPDATE employee_loans SET balance = balance + ?, status = 'active' WHERE id = ?`)
  .run(repaymentAmount, loanId);

// 3. Delete the repayment record
db.prepare(`DELETE FROM employee_loan_repayments WHERE id = ?`).run(repaymentId);
```

### 5.6 Trial Balance Impact

After all loan operations, the trial balance reflects:

| Account | Code | Type | Effect of loan activity |
|---------|------|------|------------------------|
| Employee Loan Receivable | 1300 | Asset (Dr) | Increases on disbursement, decreases on repayment/write-off |
| Cash / Bank | 1000/1010 | Asset (Dr) | Decreases on disbursement, increases on direct repayment |
| Wages & Salaries | 6100 | Expense (Dr) | Increases on salary payment (full amount, unaffected by loan deduction) |
| Loan Write-off | 6300 | Expense (Dr) | Increases on write-off |

**Balance sheet check:** Total assets = Cash decrease + Loan Receivable increase (net zero on disbursement). On repayment: Cash increase + Loan Receivable decrease (net zero). On write-off: Loan Receivable decrease + Expense increase (reduces equity via retained earnings).

---

## 6. Frontend Changes

### 6.1 Employee Detail Dialog — 4th Tab

Add "Loans" tab as index 3 in `_EmployeeDetailDialog`:

```dart
// Tab bar addition
_tabChip(l10n.employeesLoans, 3),

// IndexedStack addition
_LoansTab(employeeId: e.id),
```

### 6.2 Loans Tab Layout

```
┌─────────────────────────────────────────┐
│ [Summary Card]                          │
│ 🏦 Active: 1  Outstanding: Rs. 25,000  │
│    Repaid: Rs. 75,000  Overdue: 0      │
├─────────────────────────────────────────┤
│ [+ New Loan]          [Repay Loan]      │
├─────────────────────────────────────────┤
│ ┌─ Loan Row ──────────────────────────┐ │
│ │ Medical Loan              [Active]  │ │
│ │ Rs. 25,000 / Rs. 50,000            │ │
│ │ Due: Dec 31, 2026                  │ │
│ │ [Repay] [View] [⋮]                │ │
│ └─────────────────────────────────────┘ │
│ ┌─ Loan Row ──────────────────────────┐ │
│ │ Personal Loan          [Completed]  │ │
│ │ Rs. 0 / Rs. 30,000                 │ │
│ │ [View]                             │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 6.3 Loan Create Dialog

**Fields:**
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| Loan Amount | Number input | ✅ | Must be > 0 |
| Disbursement Date | Date picker | ✅ | Defaults to today |
| Due Date | Date picker | ✅ | Must be > disbursement date |
| Purpose | Text input | Optional | e.g. "Medical", "Personal" |
| Payment Method | Dropdown | ✅ | Cash / Bank Transfer |
| Monthly Installment | Number input | Optional | Suggested amount for salary deduction |
| Notes | Multi-line text | Optional | |

### 6.4 Loan Detail / Repayment History Dialog

Opens when clicking "View" on a loan row. Shows:
- Loan header: amount, balance, status badge, due date
- Repayment timeline (list of all repayments with date, amount, type badge)
- Footer: "Repay" button (for active loans)

### 6.5 Loan Repayment Dialog

**Fields:**
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| Amount | Number input | ✅ | Default = monthly_installment (or remaining balance if less) |
| Payment Date | Date picker | ✅ | Defaults to today |
| Payment Method | Dropdown | ✅ | Cash / Bank Transfer |
| Reference No | Text input | Optional | |
| Notes | Multi-line text | Optional | |

### 6.6 Salary Pay Dialog — Loan Deduction Integration

Modify the existing `salary_pay_dialog.dart` to show active loans:

```
┌─────────────────────────────────────────┐
│ Pay Salary                              │
│ EMP-001 · John Doe                      │
├─────────────────────────────────────────┤
│ Amount: [20000]  Date: [2026-09-30]    │
│                                         │
│ 🏦 Active Loan: Medical — Rs. 25,000   │
│    Due: Dec 31  Suggested: Rs. 12,500  │
│    Deduct for loan: [12500]             │
│                                         │
│ Already paid: Rs. 8,000 — Remaining: … │
│                                         │
│ Payment Type: [Full ▾]                  │
│ Payment Method: [Bank Transfer ▾]      │
│ Reference: [________]                   │
│ Notes: [________]                       │
├─────────────────────────────────────────┤
│              [Cancel] [Pay Salary]      │
└─────────────────────────────────────────┘
```

**Integration logic:**
1. When salary pay dialog opens, fetch active loans for this employee
2. If active loans exist, show a loan banner section
3. Pre-fill "Deduct for loan" field with `monthly_installment` (or remaining balance if less)
4. User can edit the deduction amount or clear it to 0
5. On submit:
   - Record salary payment for the full amount (existing flow)
   - If loan deduction > 0, automatically create a loan repayment record of type `salary_deduction` linked to this salary payment
   - The employee receives: `salary_amount - loan_deduction` in cash

### 6.7 Localization Keys

New keys needed (English + Urdu):

```json
{
  "employeesLoans": "Loans",
  "employeesNoLoans": "No loans recorded",
  "employeesNewLoan": "New Loan",
  "employeesRepayLoan": "Repay Loan",
  "employeesLoanAmount": "Loan Amount",
  "employeesLoanBalance": "Remaining Balance",
  "employeesLoanPurpose": "Purpose",
  "employeesLoanDisbursementDate": "Disbursement Date",
  "employeesLoanDueDate": "Due Date",
  "employeesLoanMonthlyInstallment": "Monthly Installment",
  "employeesLoanPaymentMethod": "Payment Method",
  "employeesLoanStatusActive": "Active",
  "employeesLoanStatusCompleted": "Completed",
  "employeesLoanStatusOverdue": "Overdue",
  "employeesLoanStatusWrittenOff": "Written Off",
  "employeesLoanCreated": "Loan recorded successfully",
  "employeesLoanRepaid": "Repayment recorded",
  "employeesLoanWrittenOff": "Loan written off",
  "employeesLoanDeleted": "Loan deleted",
  "employeesLoanRepaymentAmount": "Repayment Amount",
  "employeesLoanRepaymentDate": "Repayment Date",
  "employeesLoanRepaymentTypeDirect": "Direct Payment",
  "employeesLoanRepaymentTypeSalary": "Salary Deduction",
  "employeesLoanOutstanding": "Total Outstanding",
  "employeesLoanTotalRepaid": "Total Repaid",
  "employeesLoanActiveCount": "Active Loans",
  "employeesLoanOverdueCount": "Overdue",
  "employeesLoanDeductFromSalary": "Deduct for loan",
  "employeesLoanSuggestedInstallment": "Suggested"
}
```

---

## 7. Flow Diagrams

### 7.1 Loan Disbursement Flow

```
User clicks [+ New Loan]
  → Opens Loan Create Dialog
  → Fills amount, date, due date, purpose, installment, notes
  → Submits
  → Backend: INSERT INTO employee_loans
  → Backend: AccountingService.postLoanDisbursement()
      Dr 1300 Employee Loan Receivable (debit)
      Cr 1000/1010 Cash/Bank (credit)
  → Backend: UPDATE loan SET journal_entry_id = ?
  → Frontend: Refresh Loans tab
```

### 7.2 Salary Deduction Repayment Flow

```
User clicks [Pay Salary] on employee with active loan
  → Salary Pay Dialog opens
  → System fetches active loans → shows loan banner
  → User enters deduction amount (default = monthly_installment)
  → User submits salary payment
  → Backend: Record salary payment (existing flow)
  → Backend: If loan_deduction > 0:
      → INSERT INTO employee_loan_repayments (type='salary_deduction', salary_payment_id=?)
      → UPDATE employee_loans SET balance = balance - amount
      → If balance == 0: SET status = 'completed'
      → NO separate GL entry
  → Frontend: Refresh salary history + loans tab
```

### 7.3 Direct Repayment Flow

```
User clicks [Repay] on a loan row (or top-level [Repay Loan])
  → Repay Loan Dialog opens
  → User enters amount, date, method
  → Submits
  → Backend: INSERT INTO employee_loan_repayments (type='direct')
  → Backend: AccountingService.postLoanRepayment()
      Dr 1000/1010 Cash/Bank (debit)
      Cr 1300 Employee Loan Receivable (credit)
  → Backend: UPDATE loan SET balance = balance - amount
  → If balance == 0: SET status = 'completed'
  → Frontend: Refresh Loans tab
```

### 7.4 Overdue Status Auto-Update

```
On getLoans query:
  → For each active loan:
      IF due_date < CURRENT_DATE AND balance > 0:
          UPDATE status = 'overdue'
  → Return updated status
```

---

## 8. Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Repayment amount > remaining balance | Backend rejects: "Repayment exceeds loan balance" |
| Repayment amount = remaining balance | Allowed — loan auto-marks as 'completed' |
| Delete a loan with repayments | Backend rejects if repayments exist: "Cannot delete loan with repayment history" |
| Delete a loan with no repayments | Allowed — deletes loan + voids GL entry |
| Write off a loan | Sets balance to 0, status to 'written_off', posts GL entry |
| Overdue auto-update | Runs on every `getLoans` query; also cron-safe (idempotent) |
| Multiple loans — salary deduction | Deduction applies to the first active loan (sorted by due_date ASC); user can pick which loan to deduct from in the dialog |
| Employee has no active loans | Salary pay dialog shows normally without loan section |
| Loan due_date is today | Not overdue yet — overdue triggers when `due_date < CURRENT_DATE` |
| Salary deduction + direct payment on same loan | Both allowed; balance decreases from either |
| Loan disbursement on weekend/holiday | Allowed — no date restrictions |
| Void disbursement after partial repayment | Blocked: "Cannot delete loan with repayment history" |
| Void direct repayment | GL voided + balance restored; loan status reverted if was 'completed' |
| Void salary deduction repayment | No GL to void; balance restored + repayment record deleted |
| Void write-off | GL voided (Cr 1300 reversed); loan status → 'active'; balance restored |
| Write-off partial balance | N/A — write-off always clears entire remaining balance |
| Accounting period closed | `postEntry` rejects entries outside open periods (existing behavior) |
| Loan amount = 0 | Backend rejects: "Valid amount is required" |

---

## 9. Files to Create/Modify

### New Files
| File | Purpose |
|------|---------|
| `server/src/migrations/add-employee-loans.sql` | Database migration |
| `server/src/models/EmployeeLoan.ts` | Loan model (CRUD + balance updates + void logic) |
| `lib/features/employees/loan_models.dart` | Flutter models for loans |
| `lib/features/employees/loan_providers.dart` | Riverpod providers |
| `lib/features/employees/loan_repository.dart` | API repository |
| `lib/features/employees/loan_create_dialog.dart` | Create loan dialog |
| `lib/features/employees/loan_detail_dialog.dart` | Loan detail + repayment history |
| `lib/features/employees/loan_repay_dialog.dart` | Repayment dialog |
| `lib/features/employees/loans_tab.dart` | Loans tab widget |
| `lib/features/dashboard/panels/active_loans_panel.dart` | Dashboard panel for active loans |

### Modified Files
| File | Change |
|------|--------|
| `server/src/controllers/employeeController.ts` | Add loan controller functions |
| `server/src/routes/employees.ts` | Add loan routes (CRUD + repay + write-off + void) |
| `server/src/services/accountingService.ts` | Add 3 loan GL posting methods (disbursement, repayment, write-off) |
| `server/src/config/database.ts` | Register migration + seed accounts |
| `server/src/controllers/dashboardController.ts` | Add active-loans endpoint |
| `server/src/models/Dashboard.ts` | Add outstanding_loans KPI metric |
| `lib/features/employees/employee_detail_dialog.dart` | Add 4th tab + LoansTab |
| `lib/features/employees/salary_pay_dialog.dart` | Add loan deduction section |
| `lib/features/employees/employee_repository.dart` | Add loan API methods |
| `lib/features/employees/employee_providers.dart` | Add loan providers |
| `lib/features/dashboard/dashboard_kpi_catalog.dart` | Add kpi_outstanding_loans card |
| `lib/features/dashboard/dashboard_panel_catalog.dart` | Add panel_active_loans panel |
| `lib/features/shell/module_refresh.dart` | Add dashboardActiveLoansProvider to refresh |
| `lib/l10n/en.arb` | Add loan + dashboard localization keys |
| `lib/l10n/ur.arb` | Add Urdu loan + dashboard localization keys |

---

## 10. Dashboard Integration

The dashboard is a customizable layout system with two types of configurable elements: **KPI cards** (stat cards) and **panels** (content blocks). Loan summary integrates into both.

### 10.1 KPI Card: Outstanding Loans

A new KPI card showing total outstanding loan balance across all employees.

**Add to `kpiCardCatalog` in `dashboard_kpi_catalog.dart`:**
```dart
KpiCardDefinition(
  id: 'kpi_outstanding_loans',
  metric: 'outstanding_loans',
  labelKey: 'dashboardcardOutstandingloans',
  icon: Icons.account_balance_wallet_outlined,
  format: KpiCardFormat.currency,
  defaultVisible: false,  // opt-in via dashboard customizer
  hintKey: 'dashboardOutstandingloansHint',
),
```

**Add to `kpiCardLabel` switch:**
```dart
case 'dashboardcardOutstandingloans':
  return l10n.dashboardcardOutstandingloans;
```

**Add to `kpiCardHint` switch:**
```dart
case 'dashboardOutstandingloansHint':
  return l10n.dashboardOutstandingloansHint;
```

**Backend KPI handler — add to `getKPI()` switch in `Dashboard.ts`:**
```typescript
case 'outstanding_loans': {
  const result = db.prepare(`
    SELECT COALESCE(SUM(balance), 0) as total
    FROM employee_loans
    WHERE status IN ('active', 'overdue')
  `).get() as { total: number };
  return { metric, value: result.total, unit: 'currency', label: 'Outstanding Loans' };
}
```

### 10.2 Panel: Active Loans List

A dashboard panel showing active loans across all employees with quick summary.

**Add to `panelCatalog` in `dashboard_panel_catalog.dart`:**
```dart
DashboardPanelDefinition(
  id: 'panel_active_loans',
  labelKey: 'dashboardcardPanelActiveloans',
  row: 3,        // new row below existing panels
  flex: 3,
  icon: Icons.account_balance_wallet_outlined,
  defaultVisible: false,  // opt-in via dashboard customizer
),
```

**Add to `dashboardPanelLabel` switch:**
```dart
case 'dashboardcardPanelActiveloans':
  return l10n.dashboardcardPanelActiveloans;
```

### 10.3 Backend: Active Loans Panel Endpoint

**New endpoint:** `GET /dashboard/active-loans`

**Add to `ApiEndpoints`:**
```dart
static const dashboardActiveLoans = '/dashboard/active-loans';
```

**Response:**
```json
{
  "success": true,
  "data": {
    "total_outstanding": 125000,
    "total_loans": 5,
    "overdue_count": 1,
    "loans": [
      {
        "id": 1,
        "employee_code": "EMP-001",
        "employee_name": "John Doe",
        "amount": 50000,
        "balance": 25000,
        "purpose": "Medical",
        "status": "active",
        "due_date": "2026-12-31",
        "days_until_due": 122
      },
      {
        "id": 2,
        "employee_code": "EMP-003",
        "employee_name": "Jane Smith",
        "amount": 30000,
        "balance": 30000,
        "purpose": "Personal",
        "status": "overdue",
        "due_date": "2026-08-15",
        "days_until_due": -16
      }
    ]
  }
}
```

**Backend controller:**
```typescript
// GET /api/dashboard/active-loans
function getActiveLoans(req: AuthRequest, res: Response): void {
  try {
    const loans = db.prepare(`
      SELECT
        el.id, el.amount, el.balance, el.purpose, el.status,
        el.due_date, el.disbursement_date,
        e.employee_code, e.first_name, e.last_name,
        CAST(julianday(el.due_date) - julianday('now') AS INTEGER) as days_until_due
      FROM employee_loans el
      JOIN employees e ON e.id = el.employee_id
      WHERE el.status IN ('active', 'overdue')
      ORDER BY el.due_date ASC
    `).all();

    const summary = db.prepare(`
      SELECT
        COALESCE(SUM(balance), 0) as total_outstanding,
        COUNT(*) as total_loans,
        SUM(CASE WHEN status = 'overdue' THEN 1 ELSE 0 END) as overdue_count
      FROM employee_loans
      WHERE status IN ('active', 'overdue')
    `).get();

    res.json({
      success: true,
      data: {
        ...summary,
        loans: loans.map(l => ({
          ...l,
          employee_name: `${l.first_name} ${l.last_name}`,
        })),
      },
    });
  } catch (error) {
    logger.error('Active loans error:', error);
    res.status(500).json({ error: 'Failed to fetch active loans' });
  }
}
```

### 10.4 Frontend: Active Loans Panel Widget

**New file:** `lib/features/dashboard/panels/active_loans_panel.dart`

Follows the exact patterns of `_TopCustomersPanel` and `_LowStockPanel` in `dashboard_screen.dart`.

#### Provider

```dart
// dashboard_providers.dart — add:
final dashboardActiveLoansProvider =
    FutureProvider<ActiveLoansResult>((ref) async {
      final result = await ref
          .watch(dashboardRepositoryProvider)
          .activeLoans();
      return _data(result);
    });
```

```dart
// dashboard_repository.dart — add:
Future<ApiResult<ActiveLoansResult>> activeLoans() =>
    _api.get(ApiEndpoints.dashboardActiveLoans, (json) =>
        ActiveLoansResult.fromJson(json as Map<String, dynamic>));
```

```dart
// dashboard_summary.dart — add model:
class ActiveLoansResult {
  const ActiveLoansResult({
    required this.totalOutstanding,
    required this.totalLoans,
    required this.overdueCount,
    required this.loans,
  });

  factory ActiveLoansResult.fromJson(Map<String, dynamic> json) =>
      ActiveLoansResult(
        totalOutstanding: (json['total_outstanding'] as num?) ?? 0,
        totalLoans: (json['total_loans'] as int?) ?? 0,
        overdueCount: (json['overdue_count'] as int?) ?? 0,
        loans: (json['loans'] as List<dynamic>? ?? [])
            .map((l) => ActiveLoanRow.fromJson(l as Map<String, dynamic>))
            .toList(),
      );

  final num totalOutstanding;
  final int totalLoans;
  final int overdueCount;
  final List<ActiveLoanRow> loans;
}

class ActiveLoanRow {
  const ActiveLoanRow({
    required this.id,
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.amount,
    required this.balance,
    required this.purpose,
    required this.status,
    required this.dueDate,
    required this.daysUntilDue,
  });

  factory ActiveLoanRow.fromJson(Map<String, dynamic> json) =>
      ActiveLoanRow(
        id: asInt(json['id']) ?? 0,
        employeeId: asInt(json['employee_id']) ?? 0,
        employeeCode: asString(json['employee_code']) ?? '',
        employeeName: asString(json['employee_name']) ?? '',
        amount: asNum(json['amount']) ?? 0,
        balance: asNum(json['balance']) ?? 0,
        purpose: asString(json['purpose']),
        status: asString(json['status']) ?? 'active',
        dueDate: asString(json['due_date']) ?? '',
        daysUntilDue: asInt(json['days_until_due']) ?? 0,
      );

  final int id;
  final int employeeId;
  final String employeeCode;
  final String employeeName;
  final num amount;
  final num balance;
  final String? purpose;
  final String status;
  final String dueDate;
  final int daysUntilDue;

  /// Repayment progress (0.0 to 1.0).
  double get progress => amount > 0 ? (1 - balance / amount).clamp(0, 1).toDouble() : 0;
}
```

#### Widget Implementation

```dart
// panels/active_loans_panel.dart

class ActiveLoansPanel extends ConsumerWidget {
  const ActiveLoansPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final loans = ref.watch(dashboardActiveLoansProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Text(
              l10n.dashboardcardPanelActiveloans,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            // ── Body (loading / error / data) ──
            Expanded(
              child: loans.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _PanelError(
                  message: error is ApiError ? error.message : error.toString(),
                  onRetry: () => ref.invalidate(dashboardActiveLoansProvider),
                ),
                data: (data) => _ActiveLoansBody(data: data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

#### Body Widget — Sorting, Filtering, Visual Design

```dart
class _ActiveLoansBody extends StatelessWidget {
  const _ActiveLoansBody({required this.data});

  final ActiveLoansResult data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // ── Empty state ──
    if (data.loans.isEmpty) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: scheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.employeesNoloans,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    // ── Sorting: overdue first (by days_until_due ASC), then active by due_date ASC ──
    final sorted = [...data.loans]..sort((a, b) {
        // Overdue always first
        if (a.status == 'overdue' && b.status != 'overdue') return -1;
        if (a.status != 'overdue' && b.status == 'overdue') return 1;
        // Within same status, earliest due date first
        return a.daysUntilDue.compareTo(b.daysUntilDue);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Summary strip ──
        _SummaryStrip(data: data),
        const SizedBox(height: 10),
        // ── Aging buckets (horizontal bars) ──
        _LoanAgingBuckets(loans: sorted),
        const SizedBox(height: 10),
        // ── Loan list ──
        Expanded(
          child: ListView.separated(
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _LoanRow(loan: sorted[index]),
          ),
        ),
      ],
    );
  }
}
```

#### Summary Strip

```dart
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.data});
  final ActiveLoansResult data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final activeCount = data.totalLoans - data.overdueCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Total outstanding (large)
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.currency(data.totalOutstanding),
              maxLines: 1,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Counts: "5 active · 1 overdue"
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            '${activeCount} ${l10n.dashboardActiveLoansCount}'
            '${data.overdueCount > 0 ? ' · ${data.overdueCount} ${l10n.dashboardOverdueCount}' : ''}',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
```

#### Loan Aging Buckets — Horizontal Bar Visualization

Follows the exact pattern of `_ArSummaryBody` in `dashboard_screen.dart`. Each bucket represents loans grouped by how close they are to their due date.

**Aging bucket definitions:**

| Bucket | Condition | Color | Meaning |
|--------|-----------|-------|----------|
| Current | `daysUntilDue > 30` | `#22C55E` (green) | Safe — more than 30 days until due |
| Due Soon | `1 <= daysUntilDue <= 30` | `#EAB308` (yellow) | Warning — due within 30 days |
| Due Today | `daysUntilDue == 0` | `#F97316` (orange) | Due right now |
| Overdue 1-30 | `-30 <= daysUntilDue < 0` | `#EF4444` (red) | Overdue by 1-30 days |
| Overdue 30+ | `daysUntilDue < -30` | `#DC2626` (dark red) | Severely overdue |

**Backend change — add aging buckets to `getActiveLoans()` response:**

```typescript
// Add to the response object:
const aging = db.prepare(`
  SELECT
    COALESCE(SUM(CASE WHEN CAST(julianday(due_date) - julianday('now') AS INTEGER) > 30 THEN balance ELSE 0 END), 0) as current_amount,
    COALESCE(SUM(CASE WHEN CAST(julianday(due_date) - julianday('now') AS INTEGER) BETWEEN 1 AND 30 THEN balance ELSE 0 END), 0) as due_soon_amount,
    COALESCE(SUM(CASE WHEN CAST(julianday(due_date) - julianday('now') AS INTEGER) = 0 THEN balance ELSE 0 END), 0) as due_today_amount,
    COALESCE(SUM(CASE WHEN CAST(julianday(due_date) - julianday('now') AS INTEGER) BETWEEN -30 AND -1 THEN balance ELSE 0 END), 0) as overdue_1_30_amount,
    COALESCE(SUM(CASE WHEN CAST(julianday(due_date) - julianday('now') AS INTEGER) < -30 THEN balance ELSE 0 END), 0) as overdue_30_plus_amount
  FROM employee_loans
  WHERE status IN ('active', 'overdue')
`).get() as AgingBuckets;

// Include in response:
res.json({ success: true, data: { ...summary, aging, loans: ... } });
```

**Frontend model addition:**

```dart
class LoanAgingBuckets {
  const LoanAgingBuckets({
    required this.current,
    required this.dueSoon,
    required this.dueToday,
    required this.overdue1_30,
    required this.overdue30Plus,
  });

  factory LoanAgingBuckets.fromJson(Map<String, dynamic> json) =>
      LoanAgingBuckets(
        current: asNum(json['current_amount']) ?? 0,
        dueSoon: asNum(json['due_soon_amount']) ?? 0,
        dueToday: asNum(json['due_today_amount']) ?? 0,
        overdue1_30: asNum(json['overdue_1_30_amount']) ?? 0,
        overdue30Plus: asNum(json['overdue_30_plus_amount']) ?? 0,
      );

  final num current;
  final num dueSoon;
  final num dueToday;
  final num overdue1_30;
  final num overdue30Plus;

  num get total => current + dueSoon + dueToday + overdue1_30 + overdue30Plus;
}
```

**Widget implementation (matches `_ArSummaryBody` pattern exactly):**

```dart
class _LoanAgingBuckets extends StatelessWidget {
  const _LoanAgingBuckets({required this.loans});
  final List<ActiveLoanRow> loans;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // Compute buckets from loan data
    num current = 0, dueSoon = 0, dueToday = 0, overdue1_30 = 0, overdue30Plus = 0;
    for (final loan in loans) {
      final d = loan.daysUntilDue;
      if (d > 30) {
        current += loan.balance;
      } else if (d >= 1) {
        dueSoon += loan.balance;
      } else if (d == 0) {
        dueToday += loan.balance;
      } else if (d >= -30) {
        overdue1_30 += loan.balance;
      } else {
        overdue30Plus += loan.balance;
      }
    }

    final buckets = [
      (label: l10n.loanAgingCurrent, amount: current, color: const Color(0xFF22C55E)),
      (label: l10n.loanAgingDueSoon, amount: dueSoon, color: const Color(0xFFEAB308)),
      (label: l10n.loanAgingDueToday, amount: dueToday, color: const Color(0xFFF97316)),
      (label: l10n.loanAgingOverdue1_30, amount: overdue1_30, color: const Color(0xFFEF4444)),
      (label: l10n.loanAgingOverdue30Plus, amount: overdue30Plus, color: const Color(0xFFDC2626)),
    ];

    // Hide buckets with zero amount
    final visibleBuckets = buckets.where((b) => b.amount > 0).toList();
    if (visibleBuckets.isEmpty) return const SizedBox.shrink();

    final maxAmount = visibleBuckets.fold<num>(0, (m, b) => b.amount > m ? b.amount : m);
    final safeMax = maxAmount <= 0 ? 1.0 : maxAmount.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final bucket in visibleBuckets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                // Label (fixed width)
                SizedBox(
                  width: 90,
                  child: Text(
                    bucket.label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 6),
                // Bar (flex)
                Expanded(
                  child: ClipRRect(
                    borderRadius: AppBorderRadius.xsRadius,
                    child: LinearProgressIndicator(
                      value: (bucket.amount / safeMax).clamp(0, 1).toDouble(),
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(bucket.color),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Amount (fixed width, right-aligned)
                SizedBox(
                  width: 80,
                  child: Text(
                    Formatters.currency(bucket.amount),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

**Panel visual (with aging bars):**
```
┌──────────────────────────────────────────────┐
│ Active Loans              Rs. 125,000        │
│ 5 active · 1 overdue                        │
│                                              │
│ Current    ████████████████████  Rs. 80,000  │
│ Due Soon   ████████              Rs. 25,000  │
│ Due Today  ██                    Rs. 10,000  │
│ Overdue 1-30 ████               Rs. 10,000  │
│                                              │
├──────────────────────────────────────────────┤
│ EMP-001 John Doe    Rs. 25,000  [Active]     │
│                    Due in 122 days           │
│ EMP-003 Jane Smith  Rs. 30,000  [Overdue]    │
│                    16 days overdue           │
└──────────────────────────────────────────────┘
```

#### Loan Row — Click Behavior

```dart
class _LoanRow extends StatelessWidget {
  const _LoanRow({required this.loan});
  final ActiveLoanRow loan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final isOverdue = loan.status == 'overdue';
    final (statusLabel, statusColor) = isOverdue
        ? (l10n.employeesLoanStatusOverdue, scheme.error)
        : (l10n.employeesLoanStatusActive, scheme.primary);

    // Due date label
    final dueLabel = isOverdue
        ? l10n.dashboardDaysOverdue.replaceFirst('{days}', '${-loan.daysUntilDue}')
        : loan.daysUntilDue == 0
            ? l10n.employeesLoanDueDate
            : l10n.dashboardDaysUntilDue.replaceFirst('{days}', '${loan.daysUntilDue}');

    return InkWell(
      borderRadius: AppBorderRadius.smRadius,
      onTap: () => _openEmployeeDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // Left: employee code + name + purpose + due label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: code + name
                  Text(
                    '${loan.employeeCode} · ${loan.employeeName}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Row 2: purpose + progress bar
                  Row(
                    children: [
                      if (loan.purpose != null) ...[
                        Text(
                          loan.purpose!,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: ClipRRect(
                          borderRadius: AppBorderRadius.xsRadius,
                          child: LinearProgressIndicator(
                            value: loan.progress,
                            minHeight: 4,
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              isOverdue ? scheme.error : scheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Row 3: due date label
                  Text(
                    dueLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isOverdue ? scheme.error : scheme.onSurfaceVariant,
                      fontWeight: isOverdue ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right: balance + status badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Formatters.currency(loan.balance),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Click behavior: open employee detail dialog, pre-navigate to Loans tab.
  void _openEmployeeDetail(BuildContext context) {
    showEmployeeDetailDialog(
      context,
      employeeId: loan.employeeId,
      initialTab: 3,  // Loans tab index
    );
  }
}
```

#### Click Behavior: `showEmployeeDetailDialog` Enhancement

The existing `showEmployeeDetailDialog` needs an optional `initialTab` parameter:

```dart
// employee_detail_dialog.dart — modify:
Future<void> showEmployeeDetailDialog(
  BuildContext context, {
  required int employeeId,
  int initialTab = 0,  // NEW: 0=Overview, 1=Salary, 2=Documents, 3=Loans
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => EmployeeDetailDialog(
      employeeId: employeeId,
      initialTab: initialTab,
    ),
  );
}
```

#### Filtering Behavior

The panel has **no client-side filter chips** — the backend returns only active/overdue loans (completed/written-off are excluded). This keeps the panel focused and avoids UI clutter. If filtering is needed later, it can be added as toggle chips in the summary strip.

#### Sorting Rules

| Priority | Rule | Rationale |
|----------|------|-----------|
| 1 | Overdue first (`status == 'overdue'`) | Draws attention to problems |
| 2 | Within same status: earliest due date first (`daysUntilDue ASC`) | Most urgent first |
| 3 | Ties: by employee code alphabetically | Deterministic |

### 10.5 Dashboard Refresh Integration

**Add to `module_refresh.dart`:**
```dart
import '../dashboard/dashboard_providers.dart' show dashboardActiveLoansProvider;

// In the dashboard invalidation list:
..invalidate(dashboardActiveLoansProvider)
```

### 10.6 Localization Keys for Dashboard

```json
{
  "dashboardcardOutstandingloans": "Outstanding Loans",
  "dashboardOutstandingloansHint": "Total loan balance outstanding across all employees",
  "dashboardcardPanelActiveloans": "Active Loans",
  "dashboardActiveLoansCount": "active",
  "dashboardOverdueCount": "overdue",
  "dashboardDaysUntilDue": "Due in {days} days",
  "dashboardDaysOverdue": "{days} days overdue",
  "loanAgingCurrent": "Current",
  "loanAgingDueSoon": "Due Soon",
  "loanAgingDueToday": "Due Today",
  "loanAgingOverdue1_30": "Overdue 1-30",
  "loanAgingOverdue30Plus": "Overdue 30+"
}
```

---

## 11. Implementation Order

1. **Database migration** — create tables + seed 1300 + 6300 accounts
2. **Backend model** — `EmployeeLoan.ts` with CRUD + balance + void logic
3. **Backend accounting** — 3 loan GL posting methods in `accountingService.ts` (disbursement, repayment, write-off)
4. **Backend controller** — loan endpoints in `employeeController.ts` (CRUD + void + write-off)
5. **Backend routes** — register loan routes
6. **Backend KPI** — add `outstanding_loans` metric to `Dashboard.ts` + active-loans endpoint
7. **Flutter models** — `loan_models.dart`
8. **Flutter repository** — `loan_repository.dart`
9. **Flutter providers** — `loan_providers.dart` + dashboard providers
10. **Flutter UI: Loans tab** — list + summary card
11. **Flutter UI: Loan create dialog** — full form
12. **Flutter UI: Loan detail dialog** — repayment history + void actions
13. **Flutter UI: Repay dialog** — repayment form
14. **Flutter UI: Salary pay integration** — loan deduction section
15. **Dashboard: KPI card** — `kpi_outstanding_loans` in catalog + provider
16. **Dashboard: Panel** — `panel_active_loans` + `ActiveLoansPanel` widget
17. **Dashboard: Refresh** — add to `module_refresh.dart` invalidation list
18. **Localization** — en.arb + ur.arb keys (loan + dashboard)
19. **Test** — verify: create → repay → write-off → void flows + GL integrity + dashboard

---

## 12. Testing Checklist

### Core Flow
- [ ] Create loan → loan appears in Loans tab with correct balance
- [ ] GL trial balance shows Dr 1300 (Loan Receivable) for disbursement amount
- [ ] Cash/Bank account reduced by disbursement amount
- [ ] Repay via salary deduction → balance decreases, no separate GL entry
- [ ] Repay directly → balance decreases, GL entry posts (Dr Cash, Cr 1300)
- [ ] Full repayment → status changes to 'completed', GL balance on 1300 matches
- [ ] Multiple active loans show correctly with independent balances
- [ ] Overdue status auto-applies when due_date passes

### Write-off
- [ ] Write off active loan → balance = 0, status = 'written_off', Dr 6300 / Cr 1300 posted
- [ ] Write-off amount appears in trial balance under 6300 Loan Write-off
- [ ] Cannot write off a completed loan
- [ ] Cannot write off an already written-off loan

### Void / Reversal
- [ ] Void disbursement (no repayments) → GL voided, loan deleted
- [ ] Cannot void disbursement with repayments (rejected)
- [ ] Void direct repayment → GL voided, loan balance restored
- [ ] Void salary deduction repayment → no GL to void, loan balance restored
- [ ] Void write-off → GL voided, loan status reverted to 'active', balance restored
- [ ] Void last repayment on completed loan → status reverts to 'active'

### Salary Integration
- [ ] Salary pay dialog shows active loan with deduction field
- [ ] Salary pay with loan deduction → salary payment + loan repayment both recorded
- [ ] Salary pay without loan deduction → normal salary flow (loan unaffected)
- [ ] Salary deduction repayment has `salary_payment_id` set correctly

### Edge Cases
- [ ] Repayment amount > balance is rejected
- [ ] Repayment amount = balance → loan auto-marks 'completed'
- [ ] Delete loan (no repayments) → loan + GL entry voided
- [ ] Cannot delete loan with repayments
- [ ] Multiple loans — salary deduction applies to user-selected loan
- [ ] Summary card shows correct totals
- [ ] Urdu localization strings display correctly

### GL Integrity
- [ ] After all operations, sum of 1300 debit - credit = total outstanding loan balance
- [ ] Write-off expenses appear separately from operating expenses on P&L
- [ ] Void operations maintain double-entry balance (debits == credits)

### Dashboard
- [ ] KPI card shows total outstanding loans across all employees
- [ ] KPI value updates after creating/repaying/writing off loans
- [ ] Active Loans panel lists all active/overdue loans with employee names
- [ ] Panel shows correct overdue count and days-until-due
- [ ] Aging buckets show correct amounts per bucket (Current/Due Soon/Due Today/Overdue 1-30/Overdue 30+)
- [ ] Aging bucket bars scale proportionally (longest bar = max bucket amount)
- [ ] Zero-amount buckets are hidden from the visualization
- [ ] Clicking a loan row opens employee detail on Loans tab
- [ ] Panel appears in dashboard customizer for opt-in
- [ ] Dashboard refresh invalidates loan providers correctly
