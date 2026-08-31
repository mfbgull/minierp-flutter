# Owner Personal Loans — Feature Spec

**Date:** 2026-08-31  
**Status:** Draft  
**Module:** Owner Equity → 3rd Tab "Personal Loans"

---

## 1. Overview

Add a **Personal Loans** tab to the Owner Equity screen that lets the owner record personal loans given to anyone — friends, family, neighbours, customers, suppliers, strangers. This is a **personal notes/record-keeping feature** that does **not** affect business flow, accounting, or GL entries in any way.

> **⚠️ This feature is completely independent of business data.**
> - No GL entries, no journal entries, no chart_of_accounts changes
> - No effect on sales, purchases, invoices, payments, or any accounting
> - No effect on financial reports, trial balance, or balance sheet
> - The optional Customer/Supplier link on borrowers is **purely cosmetic** — it just shows a badge in the UI. It does not create any business transaction or accounting entry.

### Key Decisions (from user interview)

| Decision | Choice |
|----------|--------|
| UI location | 3rd tab "Personal Loans" in Owner Equity shell |
| Accounting impact | **None** — no GL entries, no journal entries, no business flow effect. Completely independent of all business data (sales, purchases, invoices, payments, inventory, etc.) |
| Interest | Always interest-free (amount lent = amount expected back) |
| Repayment tracking | Full — individual repayments with dates, amounts, auto-calculated balance |
| Loan statuses | Auto-computed: Pending → Partial → Settled (+ manual Write-off option) |
| Borrower type | Maintained borrower list with Customer/Supplier badges |
| Borrower management | Dropdown + "Add New" inline from loan create form |
| Summary view | 4 summary cards (Total Lent, Total Repaid, Total Pending, Active Count) |
| Detail view | Detail dialog with repayment section |
| Delete behavior | Block delete if repayments exist |
| Document numbers | Auto-generated: PL-2026-0001, PL-2026-0002, etc. (year-based) |
| Currency | Multi-currency (PKR, USD, etc.) per loan |
| CSV export | Yes, same pattern as other Owner Equity tabs |

---

## 2. Database Schema

### 2.1 New Table: `owner_personal_loans`

```sql
-- Owner Personal Loans — purely record-keeping; no GL entries.
-- Matches project conventions: DECIMAL(15,2) for money, VARCHAR for short text,
-- year-based doc numbers via generateDocNo(db, 'PL').

CREATE TABLE IF NOT EXISTS owner_personal_loans (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_no         VARCHAR(50) UNIQUE NOT NULL,        -- auto-generated: PL-2026-0001, PL-2026-0002
    borrower_name   VARCHAR(200) NOT NULL,              -- free-text borrower name
    borrower_id     INTEGER,                            -- nullable FK to customers(id) or suppliers(id)
    borrower_type   TEXT,                                -- 'customer' | 'supplier' | null (random person)
        CHECK (borrower_type IN ('customer', 'supplier') OR borrower_type IS NULL),
    amount          DECIMAL(15,2) NOT NULL CHECK (amount > 0),  -- total loan amount given
    balance         DECIMAL(15,2) NOT NULL,             -- remaining balance (= amount - sum of repayments)
    currency        VARCHAR(3) DEFAULT 'PKR',           -- ISO 4217 currency code (PKR, USD, EUR, GBP)
    loan_date       DATE NOT NULL,                      -- date loan was given
    due_date        DATE,                               -- optional — purely informational, no auto-overdue
    purpose         VARCHAR(100),                       -- e.g. "Medical", "Family emergency", "Personal"
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'partial', 'settled', 'written_off')),
    notes           TEXT,
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_own_personal_loans_borrower ON owner_personal_loans(borrower_name);
CREATE INDEX IF NOT EXISTS idx_own_personal_loans_status ON owner_personal_loans(status);
CREATE INDEX IF NOT EXISTS idx_own_personal_loans_date ON owner_personal_loans(loan_date);
```

### 2.2 New Table: `owner_personal_loan_repayments`

```sql
CREATE TABLE IF NOT EXISTS owner_personal_loan_repayments (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id         INTEGER NOT NULL REFERENCES owner_personal_loans(id),
    amount          DECIMAL(15,2) NOT NULL CHECK (amount > 0),  -- repayment amount received
    payment_date    DATE NOT NULL,                      -- date repayment was received
    notes           TEXT,
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_own_loan_repayments_loan ON owner_personal_loan_repayments(loan_id);
CREATE INDEX IF NOT EXISTS idx_own_loan_repayments_date ON owner_personal_loan_repayments(payment_date);
```

> **Note:** No `ON DELETE CASCADE` — matches the employee loans convention. The backend
> rejects loan deletion when repayments exist, so cascades are never needed. If repayments
> are ever manually cleaned up first, the loan can be hard-deleted safely.

### 2.3 New Table: `owner_personal_loan_borrowers`

```sql
CREATE TABLE IF NOT EXISTS owner_personal_loan_borrowers (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            VARCHAR(200) NOT NULL,              -- borrower name
    phone           VARCHAR(50),                        -- optional phone number
    linked_type     TEXT,                                -- 'customer' | 'supplier' | null
        CHECK (linked_type IN ('customer', 'supplier') OR linked_type IS NULL),
    linked_id       INTEGER,                            -- FK to customers(id) or suppliers(id)
    is_active       INTEGER NOT NULL DEFAULT 1,          -- soft-delete: 0 = deactivated
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(name, linked_type, linked_id)
);

CREATE INDEX IF NOT EXISTS idx_own_loan_borrowers_name ON owner_personal_loan_borrowers(name);
CREATE INDEX IF NOT EXISTS idx_own_loan_borrowers_active ON owner_personal_loan_borrowers(is_active);
```

### 2.4 Migration Strategy

**Migration file:** `server/src/migrations/add-owner-personal-loans.sql`

Creates all 3 tables above. Idempotent (`CREATE TABLE IF NOT EXISTS`), safe to re-run.
No `chart_of_accounts` seeds (no accounting impact). No GL posting functions needed.

**Registration in `server/src/config/database.ts`:**

```typescript
function runOwnerPersonalLoansMigration(): void {
  try {
    const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='owner_personal_loans'
    `).get() as { name: string } | undefined;

    if (!tableCheck) {
      logger.info('Running owner personal loans migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-owner-personal-loans.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Owner personal loans migration completed!');
    }
  } catch (error: any) {
    throw new Error('Owner personal loans migration error:: ' + error.message, { cause: error });
  }
}
```

**Add to the migration runner sequence** (after `runEmployeeLoansMigration`):

```typescript
runLedgered('fn.runOwnerPersonalLoansMigration', runOwnerPersonalLoansMigration);
```

---

## 3. Backend API Endpoints

### 3.1 Routes (add to `server/src/routes/ownerEquity.ts`)

```typescript
// Owner personal loans — purely record-keeping, no GL entries
router.get('/personal-loans',              requirePermission('owner_equity', 'read'),    ownerPersonalLoansController.list);
router.post('/personal-loans',             requirePermission('owner_equity', 'update'),  ownerPersonalLoansController.create);
router.get('/personal-loans/:id',          requirePermission('owner_equity', 'read'),    ownerPersonalLoansController.detail);
router.put('/personal-loans/:id',          requirePermission('owner_equity', 'update'),  ownerPersonalLoansController.update);
router.delete('/personal-loans/:id',       requirePermission('owner_equity', 'update'),  ownerPersonalLoansController.delete);
router.post('/personal-loans/:id/repayments', requirePermission('owner_equity', 'update'), ownerPersonalLoansController.addRepayment);
router.delete('/personal-loans/:id/repayments/:repId', requirePermission('owner_equity', 'update'), ownerPersonalLoansController.deleteRepayment);
router.get('/personal-loans/summary',      requirePermission('owner_equity', 'read'),    ownerPersonalLoansController.summary);

// Borrowers (autocomplete + management)
router.get('/borrowers',                   requirePermission('owner_equity', 'read'),    ownerPersonalLoansController.listBorrowers);
router.post('/borrowers',                  requirePermission('owner_equity', 'update'),  ownerPersonalLoansController.createBorrower);
router.put('/borrowers/:id',              requirePermission('owner_equity', 'update'),  ownerPersonalLoansController.updateBorrower);
router.put('/borrowers/:id/deactivate',  requirePermission('owner_equity', 'update'),  ownerPersonalLoansController.deactivateBorrower);
router.put('/borrowers/:id/reactivate',  requirePermission('owner_equity', 'update'),  ownerPersonalLoansController.reactivateBorrower);
router.put('/borrowers/:id/unlink',      requirePermission('owner_equity', 'update'),  ownerPersonalLoansController.unlinkBorrower);
router.post('/borrowers/:id/merge',      requirePermission('owner_equity', 'update'),  ownerPersonalLoansController.mergeBorrowers);
```

### 3.2 API Contract

#### `GET /owner-equity/personal-loans` — List All Personal Loans

**Query params:** `page`, `limit`, `search`, `status`, `from_date`, `to_date`, `sort_by`, `sort_order`

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "loan_no": "PL-2026-0001",
      "borrower_name": "Ali Khan",
      "borrower_type": "customer",
      "borrower_linked_id": 5,
      "amount": 50000,
      "balance": 25000,
      "currency": "PKR",
      "loan_date": "2026-08-01",
      "due_date": "2026-12-31",
      "purpose": "Medical",
      "status": "partial",
      "notes": "Emergency medical",
      "repayment_count": 3,
      "repaid_amount": 25000,
      "created_by_name": "Admin",
      "created_at": "2026-08-01T10:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 10,
    "total": 15,
    "totalPages": 2,
    "hasNext": true,
    "hasPrev": false
  }
}
```

#### `POST /owner-equity/personal-loans` — Create Personal Loan

**Request:**
```json
{
  "borrower_name": "Ali Khan",
  "borrower_id": 5,
  "borrower_type": "customer",
  "amount": 50000,
  "currency": "PKR",
  "loan_date": "2026-08-01",
  "due_date": "2026-12-31",
  "purpose": "Medical",
  "notes": "Emergency medical expense"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "loan_no": "PL-2026-0001",
    "borrower_name": "Ali Khan",
    "amount": 50000,
    "balance": 50000,
    "currency": "PKR",
    "status": "pending",
    "loan_date": "2026-08-01",
    "due_date": "2026-12-31"
  }
}
```

#### `GET /owner-equity/personal-loans/:id` — Loan Detail with Repayments

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "loan_no": "PL-2026-0001",
    "borrower_name": "Ali Khan",
    "borrower_type": "customer",
    "borrower_linked_id": 5,
    "amount": 50000,
    "balance": 25000,
    "currency": "PKR",
    "loan_date": "2026-08-01",
    "due_date": "2026-12-31",
    "purpose": "Medical",
    "status": "partial",
    "notes": "Emergency medical expense",
    "created_by_name": "Admin",
    "created_at": "2026-08-01T10:00:00Z",
    "repayments": [
      {
        "id": 1,
        "amount": 10000,
        "payment_date": "2026-08-15",
        "notes": "Partial return",
        "created_by_name": "Admin",
        "created_at": "2026-08-15T14:00:00Z"
      },
      {
        "id": 2,
        "amount": 15000,
        "payment_date": "2026-09-30",
        "notes": "Second payment",
        "created_by_name": "Admin",
        "created_at": "2026-09-30T09:00:00Z"
      }
    ]
  }
}
```

#### `POST /owner-equity/personal-loans/:id/repayments` — Add Repayment

**Request:**
```json
{
  "amount": 10000,
  "payment_date": "2026-08-15",
  "notes": "Partial return"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "amount": 10000,
    "loan_balance": 40000,
    "loan_status": "partial"
  }
}
```

#### `DELETE /owner-equity/personal-loans/:id` — Delete Personal Loan

**Response (200):**
```json
{
  "success": true,
  "message": "Loan deleted successfully"
}
```

#### `DELETE /owner-equity/personal-loans/:id/repayments/:repId` — Delete Repayment

**Response (200):**
```json
{
  "success": true,
  "data": {
    "loan_balance": 50000,
    "loan_status": "pending"
  }
}
```

#### `GET /owner-equity/personal-loans/summary` — Summary Stats

**Response (200):**
```json
{
  "success": true,
  "data": {
    "total_lent": 150000,
    "total_repaid": 60000,
    "total_pending": 90000,
    "active_count": 5,
    "settled_count": 3,
    "written_off_count": 1,
    "currency_breakdown": [
      { "currency": "PKR", "total_lent": 120000, "total_pending": 70000 },
      { "currency": "USD", "total_lent": 300, "total_pending": 200 }
    ]
  }
}
```

#### `GET /owner-equity/borrowers` — List Borrowers

**Query params:** `search` (autocomplete filter)

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "Ali Khan",
      "phone": "+92-300-1234567",
      "linked_type": "customer",
      "linked_id": 5,
      "loan_count": 2,
      "total_lent": 80000
    },
    {
      "id": 2,
      "name": "Sara Ahmed",
      "phone": null,
      "linked_type": null,
      "linked_id": null,
      "loan_count": 1,
      "total_lent": 30000
    }
  ]
}
```

#### `POST /owner-equity/borrowers` — Create Borrower

**Request:**
```json
{
  "name": "Sara Ahmed",
  "phone": "+92-321-7654321",
  "linked_type": null,
  "linked_id": null
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": 2,
    "name": "Sara Ahmed",
    "phone": "+92-321-7654321",
    "linked_type": null,
    "linked_id": null
  }
}
```

---

## 4. Backend Controller Logic

### 4.1 `createLoan`

1. Validate required fields (`borrower_name`, `amount > 0`, `loan_date`)
2. Auto-generate `loan_no` via `generateDocNo(db, 'PL')` → `PL-2026-0001`
3. If `borrower_id` is provided, look up borrower type from customers/suppliers
4. If borrower not in `owner_personal_loan_borrowers`, auto-create entry
5. Insert into `owner_personal_loans` with `balance = amount`, `status = 'pending'`
6. **No GL entry** — this is purely a record-keeping feature
7. Return created loan

### 4.2 `addRepayment`

1. Validate loan exists and status is `pending` or `partial` (not `settled`, not `written_off`)
2. Validate `amount > 0` and `amount <= balance`
3. Insert into `owner_personal_loan_repayments`
4. Update `owner_personal_loans.balance -= amount`
5. Auto-compute status:
   - If `balance == 0`: set `status = 'settled'`
   - If `balance > 0` and at least 1 repayment exists: set `status = 'partial'`
   - Otherwise: keep `status = 'pending'`
6. **No GL entry**
7. Return updated balance and status

### 4.3 `deleteRepayment`

1. Validate repayment exists and belongs to this loan
2. Restore loan balance: `balance += repayment_amount`
3. Auto-recompute status:
   - If `balance == amount`: set `status = 'pending'`
   - If `balance < amount` and `balance > 0`: set `status = 'partial'`
   - If `balance == 0`: set `status = 'settled'`
4. Delete the repayment record
5. Return updated loan balance and status

### 4.4 `deleteLoan`

1. Validate loan exists
2. If loan has any repayments: **reject** with error "Cannot delete loan with repayment history"
3. Delete the loan record from `owner_personal_loans`
4. **No GL voiding needed** (no GL entries were posted)
5. Return success

### 4.5 `list`

1. Query all personal loans, with optional filters (status, date range, search)
2. For each loan, compute `repaid_amount = amount - balance`
3. Compute `repayment_count` from `owner_personal_loan_repayments`
4. Server-side pagination, sorting, and search (by borrower_name, loan_no, purpose)
5. Return paginated list

### 4.6 `summary`

1. Query aggregate stats across all personal loans (posted rows only)
2. Compute: total_lent, total_repaid, total_pending, active_count, settled_count, written_off_count
3. Optional: currency breakdown
4. Return summary object

### 4.7 `listBorrowers`

1. Query borrowers from `owner_personal_loan_borrowers`
2. **Default:** only return `is_active = 1` borrowers (for loan create dropdown)
3. If `search` param is provided, filter by name (LIKE match)
4. If `include_inactive=true` param, also return deactivated borrowers (for the manage borrowers screen)
5. If `status` filter provided: `active`, `inactive`, or `all`
6. Include linked customer/supplier type and ID
7. Include aggregate stats per borrower (loan_count, total_lent, total_pending)
8. Return list sorted by name ASC

### 4.8 `createBorrower`

1. Validate `name` is provided and non-empty
2. If borrower already exists (name + linked_type + linked_id), return existing (upsert)
3. Insert new borrower record with `is_active = 1`
4. Return created borrower

### 4.9 `updateBorrower`

1. Validate borrower exists and is active
2. Validate `name` is provided and non-empty
3. Check for duplicate: if new (name + linked_type + linked_id) matches another active borrower, reject: "A borrower with this name and link already exists"
4. Update `name`, `phone`, `linked_type`, `linked_id`
5. Return updated borrower

### 4.10 `deactivateBorrower`

1. Validate borrower exists and is active
2. Count active loans for this borrower: `SELECT COUNT(*) FROM owner_personal_loans WHERE borrower_id = ?`
3. If loan_count > 0: **reject** with error "Cannot deactivate borrower with existing loans. Close or transfer loans first."
4. If loan_count == 0: set `is_active = 0`
5. Return success

### 4.11 `reactivateBorrower`

1. Validate borrower exists and is currently inactive (`is_active = 0`)
2. Set `is_active = 1`
3. Return updated borrower

### 4.12 `unlinkBorrower`

1. Validate borrower exists and is active
2. Validate borrower has a link (`linked_type IS NOT NULL`)
3. Set `linked_type = NULL`, `linked_id = NULL`
4. Existing loans keep their `borrower_type` snapshot (historical records unaffected)
5. Return updated borrower

### 4.13 `mergeBorrowers`

1. Validate source borrower exists and is active
2. Validate target borrower exists and is active, and is different from source
3. **Reassign all loans:**
   ```sql
   UPDATE owner_personal_loans
   SET borrower_name = (SELECT name FROM owner_personal_loan_borrowers WHERE id = :target_id),
       borrower_id = :target_id,
       borrower_type = (SELECT linked_type FROM owner_personal_loan_borrowers WHERE id = :target_id)
   WHERE borrower_id = :source_id
   ```
4. **Deactivate source:** `UPDATE owner_personal_loan_borrowers SET is_active = 0 WHERE id = :source_id`
5. Keep target's `name`, `phone`, `linked_type`, `linked_id` unchanged
6. Return `{ merged_loans: count, source_deactivated: true }`

### 4.9 `updateLoan`

1. Validate loan exists
2. Only allow updating: `borrower_name`, `amount`, `due_date`, `purpose`, `notes`
3. If `amount` changed and `amount < (original_amount - repaid_amount)`, reject: "Amount cannot be less than repaid amount"
4. Update fields on `owner_personal_loans`
5. **No GL impact**
6. Return updated loan

---

## 5. Frontend Changes

### 5.1 Owner Equity Shell — Add 3rd Tab

Modify `owners_equity_shell.dart` to add the Personal Loans tab:

```dart
// Tab bar addition — 3rd tab
NavigationBar(
  selectedIndex: _index,
  onDestinationSelected: (i) {
    setState(() => _index = i);
    moduleTabRefreshOnVisit['/owners-equity']?[i].call(ref);
  },
  destinations: [
    // Existing tabs
    NavigationDestination(
      icon: const Icon(Icons.savings_outlined),
      selectedIcon: const Icon(Icons.savings),
      label: l10n.equityCapital,
    ),
    NavigationDestination(
      icon: const Icon(Icons.call_made_outlined),
      selectedIcon: const Icon(Icons.call_made),
      label: l10n.equityWithdrawals,
    ),
    // NEW: Personal Loans tab
    NavigationDestination(
      icon: const Icon(Icons.handshake_outlined),
      selectedIcon: const Icon(Icons.handshake),
      label: l10n.equityPersonalLoans,
    ),
  ],
),

// IndexedStack — 3rd child
Expanded(
  child: IndexedStack(
    index: _index,
    children: const [
      OwnerCapitalTab(),
      OwnerWithdrawalsTab(),
      PersonalLoansTab(),
    ],
  ),
),
```

### 5.2 Summary Cards — Extend to 4 Cards

Modify the summary cards area in `owners_equity_shell.dart` to add personal loan stats. The summary provider fetches from `GET /owner-equity/personal-loans/summary`.

```
┌──────────────────────────────────────────────────────────────┐
│ 💰 Total Capital In    │ 📤 Total Withdrawn   │ 📊 Net     │
│ Rs. 500,000            │ Rs. 200,000          │ Rs. 300,000 │
├──────────────────────────────────────────────────────────────┤
│ 🤝 Total Lent    │ ✅ Repaid   │ ⏳ Pending   │ 📋 Active  │
│ Rs. 150,000      │ Rs. 60,000  │ Rs. 90,000   │ 5 loans    │
└──────────────────────────────────────────────────────────────┘
```

### 5.3 Personal Loans Tab Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ [Summary Row: Lent | Repaid | Pending | Active Count]           │
├─────────────────────────────────────────────────────────────────┤
│ [+ New Loan]                                    [Export CSV]    │
├─────────────────────────────────────────────────────────────────┤
│ Search: [________]  Status: [All ▾]  Sort: [Date ▾]            │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ PL-0001    Ali Khan [Customer]       Medical         PKR   │ │
│ │ Lent: Rs. 50,000   Returned: Rs. 25,000   Pending: 25,000 │ │
│ │ Date: Aug 01, 2026  Due: Dec 31, 2026     [Partial]       │ │
│ │ ████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░ 50%           │ │
│ │                                                 [⋮ Actions]│ │
│ └─────────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ PL-0002    Sara Ahmed                 Personal       USD   │ │
│ │ Lent: $300.00    Returned: $0.00       Pending: $300.00    │ │
│ │ Date: Sep 15, 2026                     [Pending]           │ │
│ │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 0%             │ │
│ │                                                 [⋮ Actions]│ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 5.4 Loan Create/Edit Dialog

**Fields:**
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| Borrower | Dropdown (autocomplete) | ✅ | Shows existing borrowers with type badges (Customer/Supplier). "Add New" option at top opens inline borrower form. |
| Borrower Phone | Text input | Optional | Only shown when adding new borrower inline |
| Amount | Number input | ✅ | Must be > 0 |
| Currency | Dropdown | ✅ | PKR, USD, EUR, GBP, etc. (app's configured currencies) |
| Loan Date | Date picker | ✅ | Defaults to today |
| Due Date | Date picker | Optional | Must be > loan_date if provided |
| Purpose | Text input | Optional | e.g. "Medical", "Family", "Personal" |
| Notes | Multi-line text | Optional | |
| Edit mode: Amount | Number input | ✅ | Can only increase, not below repaid amount |

### 5.5 Loan Detail Dialog (with Repayments)

Opens when the owner taps a loan row. Shows:

```
┌─────────────────────────────────────────────────┐
│ Personal Loan Detail                     [Close]│
├─────────────────────────────────────────────────┤
│ Loan No: PL-0001                                │
│ Borrower: Ali Khan [Customer]  📞 +92-300-1234567│
│ Amount: Rs. 50,000                              │
│ Balance: Rs. 25,000                             │
│ Date Given: Aug 01, 2026                        │
│ Due Date: Dec 31, 2026                          │
│ Purpose: Medical                                │
│ Status: Partial (50% repaid)                    │
│ Notes: Emergency medical expense                │
├─────────────────────────────────────────────────┤
│ Repayment History                               │
│ ┌──────────────────────────────────────────────┐│
│ │ Aug 15, 2026    Rs. 10,000   "Partial"  [🗑]││
│ │ Sep 30, 2026    Rs. 15,000   "Second"   [🗑]││
│ └──────────────────────────────────────────────┘│
│                                                 │
│ Total Repaid: Rs. 25,000  Remaining: Rs. 25,000│
├─────────────────────────────────────────────────┤
│          [Delete Loan] [Add Repayment]          │
└─────────────────────────────────────────────────┘
```

### 5.6 Loan Row Actions (⋮ Menu)

| Action | Condition | Behavior |
|--------|-----------|----------|
| View Details | Always | Opens detail dialog |
| Edit | `status != 'settled'` | Opens create dialog in edit mode |
| Write Off | `status == 'pending' || status == 'partial'` | Confirmation dialog → sets status to 'written_off', balance = 0 |
| Delete | Only if no repayments exist | Confirmation dialog → deletes loan |
| Void (if settled/written_off) | `status == 'settled' || status == 'written_off'` | Reverts status back to 'partial', restores balance |

### 5.7 Borrower Management

#### 5.7.1 Inline Creation (from Loan Form)

When the owner opens the loan create form:

1. **Borrower dropdown** shows all active borrowers from `owner_personal_loan_borrowers`
2. Each borrower row shows: **name** + optional **[Customer]** / **[Supplier]** badge + **phone** (if set)
3. Borrowers with existing loans show loan count as a subtitle: `Ali Khan · 2 loans`
4. Inactive (soft-deleted) borrowers are **hidden** from the dropdown
5. At top of dropdown: **"+ Add New Borrower"** option
6. Clicking "+ Add New" opens an **inline form section** below the dropdown:
   - **Name** (required, text input)
   - **Phone** (optional, text input)
   - **Link to** (optional dropdown): Shows existing Customers and Suppliers with their codes
     - e.g., `CUST-0001 — Ali Khan [Customer]`
     - e.g., `SUP-0003 — Ahmed Traders [Supplier]`
     - Default: `— None (personal contact) —`
7. Submitting creates the borrower and **auto-selects it** in the dropdown
8. Duplicate check: if a borrower with the same `name + linked_type + linked_id` already exists, the existing record is returned (upsert)

#### 5.7.2 Borrower List Screen

A dedicated **"Manage Borrowers"** button in the Personal Loans tab toolbar opens a **full-screen dialog** showing all borrowers.

```
┌─────────────────────────────────────────────────────────────────┐
│ Manage Borrowers                                    [Close]    │
├─────────────────────────────────────────────────────────────────┤
│ Search: [________]  Filter: [All ▾]  [+ Add Borrower]         │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Ali Khan              [Customer]  📞 +92-300-1234567       │ │
│ │ 2 loans · Rs. 80,000 lent · Rs. 30,000 pending    [⋮]     │ │
│ ├─────────────────────────────────────────────────────────────┤ │
│ │ Sara Ahmed            [Personal]  📞 +92-321-7654321       │ │
│ │ 1 loan  · Rs. 30,000 lent · Rs. 30,000 pending    [⋮]     │ │
│ ├─────────────────────────────────────────────────────────────┤ │
│ │ Ahmed Traders         [Supplier]                           │ │
│ │ 0 loans · No loans recorded                       [⋮]     │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Filter options:**
- All (default)
- With Active Loans
- Customers Only
- Suppliers Only
- Personal Contacts (no link)

#### 5.7.3 Borrower Row Actions (⋮ Menu)

| Action | Condition | Behavior |
|--------|-----------|----------|
| Edit | Always | Opens edit dialog (name, phone, linked entity) |
| View Loans | Always | Closes borrower list, filters Personal Loans tab to this borrower |
| Unlink Customer/Supplier | `linked_type != null` | Removes the link (sets `linked_type = NULL`, `linked_id = NULL`). Borrower record kept. Confirmation: "Remove link to Customer Ali Khan? The borrower record will remain." |
| Merge Into… | Always | Opens merge dialog to combine this borrower into another. See §5.7.5 |
| Deactivate | `loan_count == 0` | Soft-deletes (`is_active = 0`). Confirmation: "Deactivate borrower Sara Ahmed?" |
| Deactivate (with loans) | `loan_count > 0` | **Blocked** with message: "Cannot deactivate borrower with active loans. Close or transfer loans first." |

#### 5.7.4 Edit Borrower Dialog

```
┌─────────────────────────────────────────────┐
│ Edit Borrower                        [Close]│
├─────────────────────────────────────────────┤
│ Name: [Ali Khan                        ]    │
│ Phone: [+92-300-1234567                  ]   │
│                                              │
│ Link to Customer/Supplier:                   │
│ [CUST-0001 — Ali Khan          ▾]           │
│                                              │
│ ⚠️ 2 loans linked to this borrower           │
├─────────────────────────────────────────────┤
│              [Cancel] [Save Changes]         │
└─────────────────────────────────────────────┘
```

**Validation:**
- Name is required and must not be empty
- If name + linked_type + linked_id matches another borrower, show error: "A borrower with this name and link already exists"
- Changing the linked entity does not affect existing loans (they keep their `borrower_name` snapshot)

#### 5.7.5 Merge Borrowers Dialog

When the owner detects duplicate borrowers (e.g., "Ali Khan" created twice), they can merge them.

```
┌─────────────────────────────────────────────────────────────┐
│ Merge Borrowers                                      [Close]│
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Merge: Ali Khan [Customer]                                  │
│        ↳ 2 loans · Rs. 80,000 lent                         │
│                                                             │
│ INTO:   [Ali Khan (duplicate)   ▾]                          │
│        ↳ 1 loan  · Rs. 30,000 lent                         │
│                                                             │
│ After merge:                                                │
│ • All loans from "Ali Khan" move to the target borrower     │
│ • Source borrower is deactivated (soft-deleted)              │
│ • Target borrower keeps its own phone + link                │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│           [Cancel] [Merge Borrowers]                        │
└─────────────────────────────────────────────────────────────┘
```

**Merge logic (backend):**
1. Validate source and target are different borrowers
2. Validate target is active
3. **Reassign all loans:** `UPDATE owner_personal_loans SET borrower_name = target.name, borrower_id = target.id, borrower_type = target.linked_type WHERE borrower_id = source.id`
4. **Deactivate source:** `UPDATE owner_personal_loan_borrowers SET is_active = 0 WHERE id = source.id`
5. Keep target's `name`, `phone`, `linked_type`, `linked_id` unchanged
6. Return success; frontend refreshes borrower list + loan list

**Backend endpoint:**
```typescript
router.post('/borrowers/:id/merge', requirePermission('owner_equity', 'update'), ownerPersonalLoansController.mergeBorrowers);
```

**Request:**
```json
{
  "target_borrower_id": 5
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "merged_loans": 2,
    "source_deactivated": true
  }
}
```

#### 5.7.6 Deactivate / Reactivate Borrower

**Deactivate:**
- Only allowed when borrower has **zero loans** (any status)
- Sets `is_active = 0`
- Borrower disappears from the loan create dropdown
- Existing loans keep their `borrower_name` text (historical records unaffected)

**Reactivate:**
- From the borrower list, switch filter to show inactive borrowers
- Row shows `[Deactivated]` badge
- ⋮ menu shows **"Reactivate"** instead of "Deactivate"
- Sets `is_active = 1`

**Backend endpoints:**
```typescript
router.put('/borrowers/:id/deactivate', requirePermission('owner_equity', 'update'), ownerPersonalLoansController.deactivateBorrower);
router.put('/borrowers/:id/reactivate', requirePermission('owner_equity', 'update'), ownerPersonalLoansController.reactivateBorrower);
```

#### 5.7.7 Unlink Customer/Supplier

Removes the link between a borrower and a Customer/Supplier record **without** deleting the borrower.

**When to use:** The owner realize the borrower isn't actually a customer/supplier, or the customer/supplier record was deleted from the business modules.

**Logic:**
1. Set `linked_type = NULL`, `linked_id = NULL` on the borrower
2. Existing loans keep their `borrower_type` snapshot (historical records unaffected)
3. Future loans for this borrower will show no badge

**Backend endpoint:**
```typescript
router.put('/borrowers/:id/unlink', requirePermission('owner_equity', 'update'), ownerPersonalLoansController.unlinkBorrower);
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": 3,
    "name": "Ali Khan",
    "linked_type": null,
    "linked_id": null
  }
}
```

### 5.8 Localization Keys

New keys needed (English + Urdu):

```json
{
  "equityPersonalLoans": "Personal Loans",
  "equityPersonalLoansDescription": "Track personal loans given by the owner",
  "equityPersonalLoanNew": "New Loan",
  "equityPersonalLoanEdit": "Edit Loan",
  "equityPersonalLoanBorrower": "Borrower",
  "equityPersonalLoanBorrowerName": "Borrower Name",
  "equityPersonalLoanBorrowerPhone": "Phone",
  "equityPersonalLoanBorrowerLinkTo": "Link to",
  "equityPersonalLoanAddBorrower": "Add New Borrower",
  "equityPersonalLoanManageBorrowers": "Manage Borrowers",
  "equityPersonalLoanEditBorrower": "Edit Borrower",
  "equityPersonalLoanMergeBorrower": "Merge Into…",
  "equityPersonalLoanMergeBorrowerConfirm": "Merge borrowers?",
  "equityPersonalLoanMergeBorrowerBody": "All loans will be moved to the target borrower. The source borrower will be deactivated.",
  "equityPersonalLoanUnlinkBorrower": "Unlink Customer/Supplier",
  "equityPersonalLoanUnlinkBorrowerConfirm": "Remove link?",
  "equityPersonalLoanUnlinkBorrowerBody": "The borrower record will remain but will no longer be linked.",
  "equityPersonalLoanDeactivateBorrower": "Deactivate",
  "equityPersonalLoanDeactivateBorrowerConfirm": "Deactivate this borrower?",
  "equityPersonalLoanDeactivateBorrowerBlocked": "Cannot deactivate borrower with existing loans",
  "equityPersonalLoanReactivateBorrower": "Reactivate",
  "equityPersonalLoanBorrowerMerged": "Borrowers merged successfully",
  "equityPersonalLoanBorrowerUnlinked": "Link removed",
  "equityPersonalLoanBorrowerDeactivated": "Borrower deactivated",
  "equityPersonalLoanBorrowerReactivated": "Borrower reactivated",
  "equityPersonalLoanBorrowerUpdated": "Borrower updated",
  "equityPersonalLoanBorrowerDuplicate": "A borrower with this name and link already exists",
  "equityPersonalLoanFilterAll": "All",
  "equityPersonalLoanFilterWithLoans": "With Active Loans",
  "equityPersonalLoanFilterCustomers": "Customers Only",
  "equityPersonalLoanFilterSuppliers": "Suppliers Only",
  "equityPersonalLoanFilterPersonal": "Personal Contacts",
  "equityPersonalLoanAmount": "Amount",
  "equityPersonalLoanCurrency": "Currency",
  "equityPersonalLoanDateGiven": "Date Given",
  "equityPersonalLoanDueDate": "Due Date",
  "equityPersonalLoanPurpose": "Purpose",
  "equityPersonalLoanNotes": "Notes",
  "equityPersonalLoanStatusPending": "Pending",
  "equityPersonalLoanStatusPartial": "Partial",
  "equityPersonalLoanStatusSettled": "Settled",
  "equityPersonalLoanStatusWrittenOff": "Written Off",
  "equityPersonalLoanTotalLent": "Total Lent",
  "equityPersonalLoanTotalRepaid": "Repaid",
  "equityPersonalLoanTotalPending": "Pending",
  "equityPersonalLoanActiveCount": "Active",
  "equityPersonalLoanNoLoans": "No personal loans recorded",
  "equityPersonalLoanCreated": "Loan recorded successfully",
  "equityPersonalLoanUpdated": "Loan updated successfully",
  "equityPersonalLoanDeleted": "Loan deleted",
  "equityPersonalLoanRepaymentAdded": "Repayment recorded",
  "equityPersonalLoanRepaymentDeleted": "Repayment deleted",
  "equityPersonalLoanWrittenOff": "Loan written off",
  "equityPersonalLoanAddRepayment": "Add Repayment",
  "equityPersonalLoanRepaymentAmount": "Repayment Amount",
  "equityPersonalLoanRepaymentDate": "Date Received",
  "equityPersonalLoanRepaymentNotes": "Notes",
  "equityPersonalLoanDeleteConfirm": "Delete this loan?",
  "equityPersonalLoanDeleteConfirmBody": "This loan has no repayments and can be deleted.",
  "equityPersonalLoanCannotDelete": "Cannot delete loan with repayment history",
  "equityPersonalLoanWriteOffConfirm": "Write off this loan?",
  "equityPersonalLoanWriteOffConfirmBody": "The remaining balance will be marked as written off.",
  "equityPersonalLoanExported": "Exported successfully",
  "equityPersonalLoanExportFailed": "Export failed",
  "equityPersonalLoanAgingCurrent": "Current",
  "equityPersonalLoanAgingDueSoon": "Due Soon",
  "equityPersonalLoanAgingOverdue": "Overdue"
}
```

---

## 6. Flow Diagrams

### 6.1 Create Personal Loan Flow

```
User clicks [+ New Loan]
  → Opens Loan Create Dialog
  → Selects borrower from dropdown (or creates new borrower inline)
  → Fills amount, currency, date, due date, purpose, notes
  → Submits
  → Backend: Auto-generate loan_no via generateDocNo(db, 'PL')
  → Backend: INSERT INTO owner_personal_loan_borrowers (if new)
  → Backend: INSERT INTO owner_personal_loans (balance = amount, status = 'pending')
  → NO GL entry
  → Frontend: Refresh Personal Loans tab + summary cards
```

### 6.2 Record Repayment Flow

```
User taps [⋮] → [View Details] on a loan row
  → Detail dialog opens with repayment history
  → User clicks [Add Repayment]
  → Repayment form: amount, date, notes
  → Submits
  → Backend: INSERT INTO owner_personal_loan_repayments
  → Backend: UPDATE owner_personal_loans SET balance = balance - amount
  → Backend: Auto-compute status (pending → partial → settled)
  → NO GL entry
  → Frontend: Refresh detail dialog + tab + summary cards
```

### 6.3 Delete Loan Flow

```
User taps [⋮] → [Delete] on a loan row
  → IF loan has repayments: reject with "Cannot delete loan with repayment history"
  → IF no repayments: show confirmation dialog
  → Backend: DELETE FROM owner_personal_loans WHERE id = ?
  → NO GL voiding (no GL entries to reverse)
  → Frontend: Refresh tab + summary cards
```

### 6.4 Write Off Flow

```
User taps [⋮] → [Write Off] on a loan row
  → Shows confirmation dialog: "Write off Rs. 25,000 remaining?"
  → Backend: UPDATE owner_personal_loans SET status = 'written_off', balance = 0
  → NO GL entry (no business impact)
  → Frontend: Refresh tab + summary cards
```

### 6.5 Void/Settle Flow

```
User taps [⋮] → [Void] on a settled/written_off loan
  → Shows confirmation dialog
  → Backend: UPDATE owner_personal_loans SET status = 'partial', balance = restored
  → Frontend: Refresh tab + summary cards
```

---

## 7. Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Repayment amount > remaining balance | Backend rejects: "Repayment exceeds loan balance" |
| Repayment amount = remaining balance | Allowed — loan auto-marks as 'settled' |
| Delete a loan with repayments | Backend rejects: "Cannot delete loan with repayment history" |
| Delete a loan with no repayments | Allowed — deletes directly |
| Write off a loan | Sets balance to 0, status to 'written_off' |
| Void a settled/written_off loan | Reverts status to 'partial', restores balance from repayments |
| Edit loan amount below repaid amount | Backend rejects: "Amount cannot be less than repaid amount" |
| Due date is today | Not overdue — due date is informational only (no auto-overdue) |
| Borrower from Customers list | Shows "Customer" badge in dropdown and detail |
| Borrower from Suppliers list | Shows "Supplier" badge in dropdown and detail |
| Borrower is random person | No badge — just the name |
| Multiple currencies | Each loan has its own currency; summary shows per-currency breakdown |
| Loan with no due date | Allowed — due date is optional |
| Loan amount = 0 | Backend rejects: "Valid amount is required" |
| Create borrower with duplicate name | Returns existing borrower (upsert by name + type + linked_id) |
| Delete repayment | Restores loan balance; recomputes status |
| Settlement after write-off | User can void write-off, then record repayment to settle normally |
| Deactivate borrower with loans | Blocked: "Cannot deactivate borrower with existing loans" |
| Deactivate borrower with no loans | Allowed — sets is_active = 0, disappears from dropdown |
| Merge borrower into itself | Rejected: source and target must be different |
| Merge into inactive borrower | Rejected: target must be active |
| Unlink borrower with no link | No-op — already unlinked |
| Edit borrower name (loans exist) | Allowed — existing loans keep old borrower_name snapshot |
| Reactivate deactivated borrower | Sets is_active = 1, reappears in dropdown |
| Customer/Supplier deleted from business | Borrower link becomes stale; owner can unlink manually |

---

## 8. Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `server/src/migrations/add-owner-personal-loans.sql` | Database migration (3 tables) |
| `server/src/models/OwnerPersonalLoan.ts` | Loan model (CRUD + balance updates) |
| `server/src/controllers/ownerPersonalLoansController.ts` | Controller (list, create, detail, update, delete, repayments, summary, borrowers + merge/unlink/deactivate) |
| `lib/features/owner_equity/personal_loan_models.dart` | Flutter models for personal loans |
| `lib/features/owner_equity/personal_loan_providers.dart` | Riverpod providers |
| `lib/features/owner_equity/personal_loan_repository.dart` | API repository |
| `lib/features/owner_equity/personal_loan_tab.dart` | Personal Loans tab widget |
| `lib/features/owner_equity/personal_loan_create_dialog.dart` | Create/edit loan dialog (with inline borrower management) |
| `lib/features/owner_equity/personal_loan_detail_dialog.dart` | Loan detail dialog with repayment history |
| `lib/features/owner_equity/personal_loan_repay_dialog.dart` | Repayment add dialog |
| `lib/features/owner_equity/personal_loan_borrower_list_dialog.dart` | Borrower list/management dialog |
| `lib/features/owner_equity/personal_loan_borrower_form_dialog.dart` | Create/edit borrower dialog |
| `lib/features/owner_equity/personal_loan_borrower_merge_dialog.dart` | Merge borrowers dialog |

### Modified Files

| File | Change |
|------|--------|
| `server/src/routes/ownerEquity.ts` | Add personal loans + borrowers routes |
| `server/src/config/database.ts` | Register migration |
| `lib/features/owner_equity/owners_equity_shell.dart` | Add 3rd tab + summary row |
| `lib/features/owner_equity/owner_equity_providers.dart` | Add personal loans + borrowers providers |
| `lib/data/models/owner_equity.dart` | Add PersonalLoan + Borrower models |
| `lib/data/repositories/owner_equity_repository.dart` | Add personal loans + borrowers API methods |
| `lib/l10n/en.arb` | Add personal loan localization keys |
| `lib/l10n/ur.arb` | Add Urdu personal loan localization keys |

---

## 9. Summary Card Design

The summary section is displayed above the tabs in the Owner Equity shell, matching the existing `Card` + `_Stat` widget pattern.

```dart
// Summary cards — extends existing pattern
Widget _summaryCards(AppLocalizations l10n) {
  return Card(
    elevation: 0,
    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
    shape: RoundedRectangleBorder(
      borderRadius: AppBorderRadius.smRadius,
      side: BorderSide(color: scheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        children: [
          // Row 1: Existing capital/withdrawal stats
          Row(/* Capital | Withdrawn | Net */),
          // Row 2: Personal loan stats
          Row(
            children: [
              _Stat(
                icon: Icons.handshake_outlined,
                label: l10n.equityPersonalLoanTotalLent,
                value: Formatters.currency(summary?.totalLent ?? 0),
                color: scheme.primary,
              ),
              _Stat(
                icon: Icons.payments_outlined,
                label: l10n.equityPersonalLoanTotalRepaid,
                value: Formatters.currency(summary?.totalRepaid ?? 0),
                color: scheme.tertiary,
              ),
              _Stat(
                icon: Icons.pending_outlined,
                label: l10n.equityPersonalLoanTotalPending,
                value: Formatters.currency(summary?.totalPending ?? 0),
                color: scheme.error,
              ),
              _Stat(
                icon: Icons.list_alt_outlined,
                label: l10n.equityPersonalLoanActiveCount,
                value: '${summary?.activeCount ?? 0}',
                color: scheme.secondary,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
```

---

## 10. CSV Export

Follows the exact pattern of `buildOwnerWithdrawalsCsv` in `owner_withdrawals_tab.dart`.

```dart
String buildPersonalLoansCsv(AppLocalizations l10n, List<PersonalLoan> loans) {
  final buffer = StringBuffer();
  buffer.writeln([
    l10n.equityPersonalLoanLoanNo,
    l10n.equityPersonalLoanBorrower,
    l10n.equityPersonalLoanAmount,
    l10n.equityPersonalLoanCurrency,
    l10n.equityPersonalLoanTotalRepaid,
    l10n.equityPersonalLoanTotalPending,
    l10n.equityPersonalLoanDateGiven,
    l10n.equityPersonalLoanDueDate,
    l10n.equityPersonalLoanPurpose,
    l10n.equityPersonalLoanStatusPending,  // reused as "Status"
    l10n.equityPersonalLoanNotes,
    l10n.expensesCreatedby,
  ].join(','));

  for (final loan in loans) {
    buffer.writeln([
      loan.loanNo,
      _csvEscape(loan.borrowerName),
      loan.amount,
      loan.currency,
      loan.repaidAmount,
      loan.balance,
      loan.loanDate,
      loan.dueDate ?? '',
      _csvEscape(loan.purpose ?? ''),
      _csvEscape(loan.status),
      _csvEscape(loan.notes ?? ''),
      _csvEscape(loan.createdByName ?? ''),
    ].join(','));
  }
  return buffer.toString();
}
```

---

## 11. Currency Handling

### Multi-Currency Support

Each loan carries its own `currency` field (ISO 4217 code: PKR, USD, EUR, GBP, etc.).

**Frontend:**
- Currency dropdown in the loan create/edit dialog
- Defaults to the app's configured primary currency
- Summary cards show breakdowns by currency
- The tab row shows the loan's currency code next to the amount

**Backend:**
- `currency` field stored on each loan record
- Summary endpoint returns `currency_breakdown` array
- No currency conversion is performed — each loan is tracked in its own currency
- Repayments are in the same currency as the loan

**Summary display:**
```
Total Lent: Rs. 150,000 / $300.00
Pending: Rs. 90,000 / $200.00
```

---

## 12. Migration Notes

The `add-owner-personal-loans.sql` migration:

1. Creates 3 new tables (no existing tables modified)
2. No `chart_of_accounts` entries needed (no accounting)
3. No seed data required
4. The `loan_no` is generated at insert time via `generateDocNo(db, 'PL')` → year-based `PL-2026-0001` format
5. The `borrower_type` / `linked_id` fields are optional — most borrowers will be ad-hoc entries
6. See §2.4 for the full migration registration code in `database.ts`
