# F-001 — Sales and supplier returns can precede their source transactions

> Current assessment, 2026-10-26: this report preserves its historical audit snapshot. See [remediation status](../../remediation/STATUS.md) for current source verification, fixes, tests and remaining limits.

**Status:** CONFIRMED current logic, disposable fresh database. **Severity:** High. **Category:** transaction chronology / historical reporting. **Owner:** financial-oracle. No production fix applied.

## Independent rule

A return of goods from a specific invoice cannot economically exist before that invoice, or before the goods were acquired. Reject the request atomically. This is the same historical-stock principle documented in `docs/INVENTORY-EFFECTIVE-DATES.md` and implemented for invoice consumption in `server/src/services/inventoryEffectiveDate.ts:23`. Hybrid customer-ledger dating in invoice-return-spec.md D14 does not permit a return to predate its source document.

## Reproduction and observed financial effect

Invocation: `node accounting-audit/tests/oracle-lifecycle.cjs` (family 7; use `ORACLE_FAMILY=7` for the isolated family).

1. Actual authenticated POST purchase: 10 units @ Rs 10, date 2026-09-10.
2. POST invoice: 1 unit @ Rs 15, date 2026-09-11. Remaining stock 9.
3. GET balance sheet as of September 9 (before the acquisition).
4. POST `/api/invoices/:id/return`, `{return_date:"2026-09-09",items:[{invoice_item_id:<line>,return_quantity:1}]}`.
5. GET balance sheet again and P&L restricted to September 9.

Expected: 4xx, no rows/stock/GL/report changes. Actual: 200; stock restored from 9 to 10; return and canonical GL dated September 9. Historical balance-sheet inventory increases Rs 10. September 9 P&L reports revenue **−15**, COGS **−10**, net profit **−5**, despite neither purchase nor sale yet existing. Every aggregate accounting collector and per-journal balance check still passes: this is a timing defect that reconciliation totals do not detect.

## Exact evidence

- `accounting-audit/evidence/oracle-run-AbsZeT/results.json`: five failing chronology assertions in family7; family1 and all other main families pass.
- Same directory `api-events.json`: exact successful sale and early-return requests, before/after balance sheets, dated P&L.
- Same directory `*early-return.json` and `*early-return-invariants.json`: SQL rows and clean accounting collectors.
- `accounting-audit/findings/F-001/database-proof.json`: readonly SQL joining source invoice, return, GL dates and account debits/credits; integrity_check=ok and no FK violations.
- `accounting-audit/evidence/oracle-console-5.log`: observed mismatches. Older run4 independently reproduced the same acceptance.

## Source and root cause

`server/src/services/invoiceReturnService.ts:333` resolves the requested date. At lines346–350 the transaction rereads the source and checks only whether the requested period is closed. It never compares the date with `fresh.invoice_date`. `resolveReturnDate` at1365–1372 validates only YYYY-MM-DD shape. Lines413–438 pass the impossible date into return/revenue and COGS journals. The stock reversal at393–405 likewise occurs without a source-date lower bound.

Graph discovery and exact-path coverage were checked (no recorded gap, best-effort signal); direct source and execution establish the finding.

## Recommendation and required regression

Validate a real calendar date and require return date >= source invoice date inside the authoritative transaction, before any stock/ledger/GL write. Audit sibling return paths for the same relationship. Add mounted tests for previous-day rejection, same-day acceptance, later-date acceptance, month/year transitions, closed periods, historical P&L/BS neutrality after rejected requests and unchanged economic row hashes. No production changes were made.

## Supplier-side reproduction confirmed after independent review

A second fresh, single-scenario run proves the same missing source-date lower bound in direct purchase returns:

`ORACLE_SUPPLEMENT=1 ORACLE_FAMILY=7c node accounting-audit/tests/oracle-lifecycle.cjs`

Evidence: `accounting-audit/evidence/oracle-run-ZHkdJ8/` (results.json, api-events.json, *supplier-early-return*.json), console `oracle-supplier-chronology.log`, and this finding's `supplier-return-chronology-proof.json`.

Purchase10 units @10 on2026-09-10; POST `/api/purchase-returns` dated2026-09-09 for1 unit with credit_on_account. **Actual201**, stock10→9. Historical September9 balance sheet changes inventory0→−10 and accounts payable0→−10, although the source purchase has not happened. Expected4xx with no change. All aggregate accounting collectors remain clean. Family7c has21 checks,4 chronology failures.

Source: `server/src/models/PurchaseReturn.ts:188–218` validates source identity and quantity but not purchase_date. `create` at561–589 validates header presence/source quantities; lines663–670 stamp the supplied return date on stock movement; lines716–732 post GL and supplier credit note on that date. Add the source-date lower bound for both direct purchase and goods-receipt/PO return paths, and test their historical inventory/AP reports. This extends F-001's affected scope; it is not a third distinct root-domain finding.
