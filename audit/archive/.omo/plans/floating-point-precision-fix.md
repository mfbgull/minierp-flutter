# Task 7 — H1: Floating-Point Quantity Precision Fix

## TL;DR

> **Quick Summary**: Fix IEEE 754 floating-point arithmetic causing `0.19999999999999998` residue that rejects valid sales. Create a centralized `roundQty()` utility and apply it at all stock quantity persistence and comparison boundaries.
>
> **Deliverables**:
> - `server/src/utils/quantity.ts` — canonical rounding utility
> - Updates to 7+ files for persistence/comparison rounding
> - Regression test suite for floating-point precision edge cases
> - All existing tests pass
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 3 waves
> **Critical Path**: Utility creation → Model updates → Tests

---

## Context

### Original Request
The audit found that REAL/JavaScript floating-point arithmetic creates residue in weighted inventory:
- Buy 0.3 kg, sell 0.1 kg, sell 0.2 kg
- Second sale sees `0.19999999999999998` instead of `0.2`
- Valid sale gets rejected due to insufficient stock

### Interview Summary
**Key Discussions**:
- `qty_decimal_precision` is per-item (stored in `items` table), default 0
- DB schema uses `DECIMAL(15,3)` but SQLite stores as REAL (IEEE 754)
- Internal calculations should use consistent 3-decimal precision to match DB
- Per-item precision is for display; internal rounding must be uniform
- Existing code uses ad-hoc rounding (ROUND() in SQL, Math.round in JS) with no consistency

**Research Findings**:
- 22 files use `parseFloat(String(...))` for quantity conversion
- 321 matches for quantity-related comparisons
- 124 matches for ROUND/toFixed/Math.round across codebase
- No centralized rounding utility exists
- `consumeFromOldestBatches` is the critical comparison boundary

### Metis Review
**Identified Gaps** (addressed):
- Need to distinguish between display precision (per-item) and calculation precision (fixed 3 decimals)
- Must not break existing stored data — rounding applies to new calculations only
- SQL ROUND() calls already exist but are inconsistent

---

## Work Objectives

### Core Objective
Eliminate floating-point residue in stock quantity calculations by introducing a centralized rounding utility and applying it at all persistence and comparison boundaries.

### Concrete Deliverables
- `server/src/utils/quantity.ts` with `roundQty()` and `qtyEpsilon()` functions
- Updated `StockMovement.ts` — round quantities in recordMovement, consumeFromOldestBatches
- Updated `Invoice.ts` — round in consumeFromOldestBatches wrapper
- Updated `posController.ts` — round in sale validation
- Updated `Production.ts` — round in stock validation
- Updated `PurchaseReturn.ts` — round in return validation
- Updated `SalesOrder.ts` — round in availability check
- New test file `server/src/__tests__/floatingPointPrecision.test.ts`

### Definition of Done
- [ ] `roundQty(0.3 - 0.1, 3) === 0.2` passes
- [ ] `roundQty(1.1 - 0.7 - 0.4, 3) === 0` passes
- [ ] No dust stock (quantities round to 0 when they should)
- [ ] No legitimate sale rejected due to floating-point error
- [ ] All 76 existing test files pass
- [ ] No `as any` or type suppressions added

### Must Have
- Centralized `roundQty(value, precision?)` function
- Apply at ALL comparison boundaries (availableQty < quantity)
- Apply at ALL persistence boundaries (writing to stock tables)
- Regression tests for the exact scenarios from the audit
- No arbitrary epsilon values (1e-9, 0.001) — use precision-based rounding

### Must NOT Have (Guardrails)
- Do NOT change the DB schema or migration
- Do NOT modify stored data — rounding applies to calculations only
- Do NOT change `qty_decimal_precision` semantics (still per-item display)
- Do NOT add new npm dependencies
- Do NOT use `as any` or `@ts-ignore`

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed.

### Test Decision
- **Infrastructure exists**: YES (76 test files in `server/src/__tests__/`)
- **Automated tests**: YES — TDD approach
- **Framework**: vitest (based on test file patterns)

### QA Policy
Every task includes agent-executed QA scenarios.
Evidence saved to `.omo/evidence/task-7-*.json`.

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — foundation):
├── Task 1: Create roundQty utility [quick]

Wave 2 (After Wave 1 — apply to all consumers, PARALLEL):
├── Task 2: StockMovement.ts updates [quick]
├── Task 3: Invoice.ts + posController.ts updates [quick]
├── Task 4: Production.ts + PurchaseReturn.ts + SalesOrder.ts updates [quick]

Wave 3 (After Wave 2 — tests + verification):
├── Task 5: Regression tests [quick]
├── Task 6: Run full test suite [quick]
```

### Dependency Matrix

| Task | Depends On | Blocks |
|------|-----------|--------|
| 1 | — | 2, 3, 4 |
| 2 | 1 | 5, 6 |
| 3 | 1 | 5, 6 |
| 4 | 1 | 5, 6 |
| 5 | 2, 3, 4 | 6 |
| 6 | 5 | — |

---

## TODOs

- [ ] 1. Create roundQty utility

  **What to do**:
  - Create `server/src/utils/quantity.ts`
  - Implement `roundQty(value: number, precision: number = 3): number`
  - Use `Math.round(value * factor) / factor` pattern (avoid `+ 'e+2'` string tricks)
  - Implement `qtyEpsilon(precision: number = 3): number` for comparison tolerance
  - Export both functions
  - Add JSDoc explaining the precision vs display distinction

  **Must NOT do**:
  - Do NOT use string conversion tricks (Number(v + 'e+2'))
  - Do NOT hardcode precision — make it parameterized

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file creation, well-defined spec
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `superpowers/test-driven-development`: Overkill for utility creation

  **Parallelization**:
  - **Can Run In Parallel**: NO (foundation for all other tasks)
  - **Parallel Group**: Wave 1 (solo)
  - **Blocks**: Tasks 2, 3, 4
  - **Blocked By**: None

  **References**:
  - `server/src/utils/currency.ts` — existing rounding pattern for money (lines 5-10)

  **Acceptance Criteria**:
  - [ ] `roundQty(0.1 + 0.2, 3) === 0.3`
  - [ ] `roundQty(0.3 - 0.1, 3) === 0.2`
  - [ ] `roundQty(1.1 - 0.7 - 0.4, 3) === 0`
  - [ ] `qtyEpsilon(3) === 0.001`
  - [ ] File compiles with no TypeScript errors

  **QA Scenarios**:

  ```
  Scenario: Basic rounding works
    Tool: Bash (vitest)
    Steps:
      1. Create temp test: import roundQty; expect(roundQty(0.3 - 0.1, 3)).toBe(0.2)
      2. Run: npx vitest run --testPathPattern quantity
    Expected Result: Test passes
    Evidence: .omo/evidence/task-1-roundQty-basic.json

  Scenario: Precision parameter respected
    Tool: Bash (vitest)
    Steps:
      1. Test roundQty(1.23456, 2) === 1.23
      2. Test roundQty(1.23456, 4) === 1.2346
    Expected Result: Both assertions pass
    Evidence: .omo/evidence/task-1-roundQty-precision.json
  ```

  **Commit**: YES (message: `feat(quantity): add centralized roundQty utility`)
  - Files: `server/src/utils/quantity.ts`
  - Pre-commit: `npx tsc --noEmit`

---

- [ ] 2. Apply roundQty to StockMovement.ts

  **What to do**:
  - Import `roundQty` from `../utils/quantity`
  - In `recordMovement()`: round `data.quantity` before DB write (line 120)
  - In `consumeFromOldestBatches()`:
    - Round `quantity` parameter at entry (line 706)
    - Round `availableQty` after parseFloat (lines 727-728, 739)
    - Round `consumeFromThis` in batch loop (line 827, 944)
    - Round `batch.qty_avail` / `batch.quantity_remaining` after read
  - In `recordTransfer()`: round qty after parseFloat (line 982)
  - In `getSellableAvailability()`: round sellable_qty in results

  **Must NOT do**:
  - Do NOT change the SQL ROUND() calls in sellableAvailabilitySql — those are correct
  - Do NOT modify the batch consumption logic flow — only add rounding at boundaries

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Targeted edits to existing functions
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `superpowers/systematic-debugging`: Not debugging, applying known fix

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 3, 4 after Wave 1)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 5, 6
  - **Blocked By**: Task 1

  **References**:
  - `server/src/models/StockMovement.ts` lines 103-183 (recordMovement)
  - `server/src/models/StockMovement.ts` lines 700-965 (consumeFromOldestBatches)
  - `server/src/models/StockMovement.ts` lines 974-1057 (recordTransfer)

  **Acceptance Criteria**:
  - [ ] All quantity values rounded before DB writes
  - [ ] All comparison boundaries use rounded values
  - [ ] No existing test regressions

  **QA Scenarios**:

  ```
  Scenario: consumeFromOldestBatches handles 0.3 - 0.1 = 0.2
    Tool: Bash (vitest)
    Steps:
      1. Create batch with qty 0.3
      2. Consume 0.1
      3. Assert remaining === 0.2 (not 0.19999999999999998)
      4. Consume 0.2
      5. Assert remaining === 0
    Expected Result: All assertions pass, no dust stock
    Evidence: .omo/evidence/task-2-consume-rounding.json

  Scenario: recordMovement rounds quantity
    Tool: Bash (vitest)
    Steps:
      1. Call recordMovement with quantity 0.1 + 0.2
      2. Read back from DB
      3. Assert stored quantity === 0.3
    Expected Result: Stored value is rounded
    Evidence: .omo/evidence/task-2-record-rounding.json
  ```

  **Commit**: YES (message: `fix(stock): apply roundQty to stock movement persistence and comparisons`)
  - Files: `server/src/models/StockMovement.ts`
  - Pre-commit: `npx tsc --noEmit`

---

- [ ] 3. Apply roundQty to Invoice.ts and posController.ts

  **What to do**:
  - `Invoice.ts`: Import roundQty, round quantity in `consumeFromOldestBatches` wrapper (line 184-191)
  - `posController.ts`: Import roundQty, round each `item.quantity` before validation (line 96-106) and before stock consumption (line 170-172)

  **Must NOT do**:
  - Do NOT change invoice line item storage — quantities come from user input and should be stored as-is
  - Do NOT modify the total calculation logic

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Two files, targeted edits
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 2, 4)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 5, 6
  - **Blocked By**: Task 1

  **References**:
  - `server/src/models/Invoice.ts` lines 184-191
  - `server/src/controllers/posController.ts` lines 92-106, 169-172

  **Acceptance Criteria**:
  - [ ] POS sale with fractional quantities validates correctly
  - [ ] Invoice stock consumption uses rounded quantities

  **QA Scenarios**:

  ```
  Scenario: POS sale with 0.3 - 0.1 - 0.2 succeeds
    Tool: Bash (vitest)
    Steps:
      1. Create item with qty_decimal_precision=3
      2. Purchase 0.3 units
      3. POS sale 0.1 units → should succeed
      4. POS sale 0.2 units → should succeed (not rejected)
    Expected Result: Both sales complete without insufficient stock error
    Evidence: .omo/evidence/task-3-pos-sale.json
  ```

  **Commit**: YES (message: `fix(invoice): apply roundQty to invoice and POS stock validation`)
  - Files: `server/src/models/Invoice.ts`, `server/src/controllers/posController.ts`
  - Pre-commit: `npx tsc --noEmit`

---

- [ ] 4. Apply roundQty to Production.ts, PurchaseReturn.ts, SalesOrder.ts

  **What to do**:
  - `Production.ts`: Import roundQty, round `availableStock` after parseFloat (line 201), round `input.quantity` (line 203)
  - `PurchaseReturn.ts`: Import roundQty, round `available` (line 415), round `line.quantity` (line 416, 466, 499)
  - `SalesOrder.ts`: Import roundQty, round `availableSellable` and `item.quantity` (line 647)

  **Must NOT do**:
  - Do NOT change the business logic of returns or production
  - Do NOT modify SQL queries that already use ROUND()

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Three files, targeted edits
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 2, 3)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 5, 6
  - **Blocked By**: Task 1

  **References**:
  - `server/src/models/Production.ts` lines 201-205
  - `server/src/models/PurchaseReturn.ts` lines 415-419, 466
  - `server/src/models/SalesOrder.ts` line 647

  **Acceptance Criteria**:
  - [ ] Production validates stock with rounded quantities
  - [ ] Purchase returns validate with rounded quantities
  - [ ] Sales orders check availability with rounded quantities

  **QA Scenarios**:

  ```
  Scenario: Production with fractional inputs
    Tool: Bash (vitest)
    Steps:
      1. Create item with 0.3 stock
      2. Attempt production consuming 0.1
      3. Assert succeeds (not rejected as insufficient)
    Expected Result: Production proceeds
    Evidence: .omo/evidence/task-4-production-rounding.json
  ```

  **Commit**: YES (message: `fix(production): apply roundQty to production, purchase return, sales order validation`)
  - Files: `server/src/models/Production.ts`, `server/src/models/PurchaseReturn.ts`, `server/src/models/SalesOrder.ts`
  - Pre-commit: `npx tsc --noEmit`

---

- [ ] 5. Create regression tests

  **What to do**:
  - Create `server/src/__tests__/floatingPointPrecision.test.ts`
  - Test cases:
    1. `0.3 - 0.1 = 0.2` (exact)
    2. `1.1 - 0.7 - 0.4 = 0` (multi-step)
    3. Repeated fractional purchases/sales (10x 0.1)
    4. Fractional returns (buy 1.0, return 0.3, assert 0.7 remains)
    5. Insufficient stock edge case (have 0.2, try sell 0.2000001 → reject)
    6. Exact stock sale (have 0.2, sell 0.2 → succeed)
    7. Dust stock detection (assert no tiny remainders after full consumption)

  **Must NOT do**:
  - Do NOT test UI or API endpoints — unit tests only
  - Do NOT mock the database — use in-memory SQLite

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single test file creation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Tasks 2, 3, 4)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 6
  - **Blocked By**: Tasks 2, 3, 4

  **References**:
  - `server/src/__tests__/models.test.ts` — existing test patterns
  - `server/src/__tests__/batchLocations.test.ts` — batch consumption tests

  **Acceptance Criteria**:
  - [ ] All 7 test cases pass
  - [ ] No dust stock in any scenario
  - [ ] No legitimate sale rejected

  **QA Scenarios**:

  ```
  Scenario: Full regression suite passes
    Tool: Bash (vitest)
    Steps:
      1. Run: npx vitest run floatingPointPrecision
      2. Assert all tests pass
    Expected Result: 7/7 tests pass
    Evidence: .omo/evidence/task-5-regression-tests.json
  ```

  **Commit**: YES (message: `test(quantity): add floating-point precision regression tests`)
  - Files: `server/src/__tests__/floatingPointPrecision.test.ts`
  - Pre-commit: `npx vitest run floatingPointPrecision`

---

- [ ] 6. Run full test suite

  **What to do**:
  - Run `npx vitest run` in `server/` directory
  - Verify all 76 test files pass
  - If any fail, diagnose and fix (likely rounding side effects)
  - Save test results as evidence

  **Must NOT do**:
  - Do NOT skip failing tests
  - Do NOT modify test expectations to make them pass

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple execution and verification
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (final verification)
  - **Parallel Group**: Wave 3 (after Task 5)
  - **Blocks**: None
  - **Blocked By**: Task 5

  **References**:
  - `server/src/__tests__/` — all test files

  **Acceptance Criteria**:
  - [ ] All tests pass (0 failures)
  - [ ] No TypeScript errors
  - [ ] Evidence saved

  **QA Scenarios**:

  ```
  Scenario: Full suite green
    Tool: Bash (vitest)
    Steps:
      1. Run: cd server && npx vitest run
      2. Assert exit code 0
      3. Count passed/failed
    Expected Result: All tests pass
    Evidence: .omo/evidence/task-6-full-suite.json
  ```

  **Commit**: NO (verification only)

---

## Final Verification Wave

After all tasks complete:
1. Run `npx tsc --noEmit` — zero errors
2. Run `npx vitest run` — all pass
3. Verify no `1e-9` or `0.001` epsilon patterns added
4. Verify `roundQty` imported in all target files

---

## Commit Strategy

| Task | Message | Files |
|------|---------|-------|
| 1 | `feat(quantity): add centralized roundQty utility` | `server/src/utils/quantity.ts` |
| 2 | `fix(stock): apply roundQty to stock movement persistence` | `server/src/models/StockMovement.ts` |
| 3 | `fix(invoice): apply roundQty to invoice and POS validation` | `server/src/models/Invoice.ts`, `server/src/controllers/posController.ts` |
| 4 | `fix(production): apply roundQty to production and returns` | `server/src/models/Production.ts`, `server/src/models/PurchaseReturn.ts`, `server/src/models/SalesOrder.ts` |
| 5 | `test(quantity): add floating-point precision regression tests` | `server/src/__tests__/floatingPointPrecision.test.ts` |

---

## Success Criteria

### Verification Commands
```bash
cd server && npx tsc --noEmit          # Expected: 0 errors
cd server && npx vitest run            # Expected: all pass
grep -r "1e-9\|0\.001" src/utils/quantity.ts  # Expected: only in qtyEpsilon
```

### Final Checklist
- [ ] `roundQty(0.3 - 0.1, 3) === 0.2`
- [ ] `roundQty(1.1 - 0.7 - 0.4, 3) === 0`
- [ ] No dust stock after full consumption
- [ ] No legitimate sale rejected
- [ ] All existing tests pass
- [ ] No `as any` or type suppressions
- [ ] No arbitrary epsilon values added
