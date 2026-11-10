# Period Protection Primitive — Tasks

Closes audit findings: **PUR-003 · PUR-005 · CODE-001 · SALES-013 · ACCT-007 ·
GL-004** (SALES-011 is a Part 0 alias of PUR-005).

Source: `proposal.md` (rescued from `openspec/specs/closed-period-immutability/`,
where it sat unscannable). Its 13-path list was verified against the tree on
2026-10-07: most are now guarded, so the residual gap is smaller than written.
See "Verified state" in the proposal.

Every task below is binary-checkable. A task is done when its named assertion
passes, not when the code looks right.

---

## Phase 0 — Gate the primitives (CODE-001, the structural half)

- [x] 0.1 `assertPeriodNotClosed` called inside `voidJournalLinesByReference`
      before its `UPDATE journal_lines SET voided = 1`. **done-when:** a test
      calls `voidJournalLinesByReference` directly for a closed-period document
      with no caller-side guard, and no row becomes `voided = 1`.
- [x] 0.2 `assertPeriodNotClosed` called inside `postLegacyStockEntry`.
      **done-when:** the audit's ACCT-005 reproduction (adjustment dated
      `2026-01-15` with `2026-01` closed) returns 409 and GL 1200 / 7100 receive
      no lines.
- [x] 0.3 Period guard moved into `models/Purchase.ts` `void` and
      `models/Invoice.ts` `cancel`, so a non-HTTP caller is protected.
      **done-when:** a direct model call (no controller) for a closed-period
      document throws and stock, ledger, and GL are unchanged.

## Phase 1 — Close the residual unguarded paths

- [x] 1.1 `voidGoodsReceipt` (`controllers/purchaseOrderController.ts`) calls
      `assertPeriodNotClosed(db, receipt.receipt_date, …)`.
      **done-when:** the audit’s PUR-003 reproduction (GRN dated `2026-03-05`
      with `2026-03` closed) returns 409; GL 1200 and GL 2000 unchanged.
- [x] 1.2 Supplier-refund void guarded
      (`controllers/supplierRefundController.ts`, `models/SupplierRefund.ts`).
      **done-when:** a refund dated in a closed period returns 409 and no
      `supplier_ledger` row changes.
- [x] 1.3 `restoreInvoice` guards the period.
      **done-when:** restoring an invoice dated in a closed period returns 409;
      no GL line or batch changes.

## Phase 2 — Stop auto-creating future periods (PUR-005)

- [x] 2.1 Reject a document date later than today at the controller, on every
      purchase, receipt, invoice, and adjustment path.
      **done-when:** a receipt dated `2030-01-01` returns 400 and no
      `accounting_periods` row with `period_name = '2030-01'` exists afterward.
- [x] 2.2 `postEntry` no longer auto-creates an open period from a document date.
      **done-when:** a direct `postEntry` with a future date throws rather than
      inserting an open period.
- [x] 2.3 An explicit administrative period-open action replaces the implicit
      creation. **done-when:** opening a period is possible only via that action,
      and it is covered by a test.

## Phase 3 — Non-calendar period names (GL-004)

- [x] 3.1 No code path infers closure from the `period_name` string shape.
      **done-when:** a period with a non-calendar name, once `status = 'closed'`,
      returns 409 for every mutating path.

## Phase 4 — Regression suite

- [x] 4.1 New `server/src/__tests__/closedPeriodImmutability.test.ts` covering,
      for each guarded path: refused in a closed period → 409 + byte-identical
      totals; same operation in an open period → succeeds.
- [x] 4.2 For each refusal, assert **row counts and every GL, ledger and stock
      total are unchanged**, not merely that a 409 was returned.
      This is the `known-issues.md` §“prove the guard can fail” requirement: a
      status-code assertion alone would pass even if a partial write preceded
      the throw.
- [x] 4.3 `expectAllInvariantsHold('after period refusal')` at the end of each
      case.

## Phase 5 — Full verification

- [x] 5.1 `npx tsc --noEmit` clean.
- [x] 5.2 `npx eslint` 0 errors.
- [x] 5.3 `npx jest --silent` — full suite green, no regressions.
- [x] 5.4 `openspec validate --all` → 0 failed.
- [x] 5.5 Update `openspec/specs/closed-period-immutability/spec.md` (created on
      archive) from these ADDED requirements, and delete the `## Known Gaps`
      section if one was added.
- [x] 5.6 Remove the `## Known Gaps` / residual-gap block from this change's
      `proposal.md`, replacing it with the verified final state.
- [x] 5.7 Archive via the gate — every box above ticked:
      `node scripts/openspec-archive-guard period-protection-primitive -- -y`

---

## Sequencing

Phase 0 first: it is the structural fix and it makes every later phase a
defence-in-depth check rather than the only check. Phases 1–3 are independent
of each other and can run in parallel.

## Not in scope

- Reopening closed periods via API (admin DB edit only)
- Period-level audit log (the existing activity log covers who/when)
- UI changes (server enforcement is the goal)