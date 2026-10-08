import Database from 'better-sqlite3';

/**
 * ACCT-005 — every purchase must name an identified supplier.
 *
 * Shared by every purchase creation/update path (direct purchase,
 * multi-item purchase, purchase order, goods receipt) so no code
 * path can bypass the rule. Thrown as a plain Error whose message
 * the business-rule classifier maps to HTTP 400 (see
 * businessRuleError CLASSIFY_PATTERNS — SUPPLIER_REQUIRED_FOR_PURCHASE).
 */

export const SUPPLIER_REQUIRED_ERROR_CODE = 'SUPPLIER_REQUIRED_FOR_PURCHASE';
export const SUPPLIER_REQUIRED_MESSAGE =
  'A supplier is required for all purchases.';

/**
 * Validate that a purchase names an existing, active supplier.
 *
 * `supplierId` may arrive as a number or a numeric string (JSON
 * query/form clients). Anything else — missing, empty, non-numeric —
 * is a rejection. A supplier row that does not exist or is inactive
 * is also a rejection: a purchase must reference a supplier that
 * can actually be billed.
 *
 * Returns the resolved numeric supplier id.
 */
export function requireSupplierForPurchase(
  supplierId: unknown,
  db: Database.Database
): number {
  const numeric =
    typeof supplierId === 'number'
      ? supplierId
      : typeof supplierId === 'string' && supplierId.trim() !== ''
        ? Number(supplierId)
        : NaN;

  if (!Number.isFinite(numeric) || numeric <= 0) {
    throw new Error(
      `${SUPPLIER_REQUIRED_ERROR_CODE}: ${SUPPLIER_REQUIRED_MESSAGE}`
    );
  }

  const supplier = db
    .prepare('SELECT id, is_active FROM suppliers WHERE id = ?')
    .get(numeric) as { id: number; is_active: number | null } | undefined;

  if (!supplier) {
    throw new Error(
      `${SUPPLIER_REQUIRED_ERROR_CODE}: supplier ${numeric} does not exist. ${SUPPLIER_REQUIRED_MESSAGE}`
    );
  }

  if (supplier.is_active !== 1) {
    throw new Error(
      `${SUPPLIER_REQUIRED_ERROR_CODE}: supplier ${numeric} is inactive. ${SUPPLIER_REQUIRED_MESSAGE}`
    );
  }

  return supplier.id;
}
