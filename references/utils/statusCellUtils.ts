/**
 * AG Grid Status Cell Coloring — Shared Utility
 *
 * Provides mapping functions from status values to CSS class names
 * defined in styles/ag-grid-status-cells.css.
 *
 * Use these in AG Grid column definitions via the `cellClass` callback.
 */

/** Handles various status values and returns appropriate CSS class */
export function getStatusCellClass(status: string | null | undefined): string {
  const s = (status || '').toLowerCase().trim();

  // Success/Active group (green)
  if (['paid', 'active', 'completed', 'accepted', 'converted', 'invoiced', 'returned'].includes(s)) {
    return 'cell-status-active';
  }

  // Warning/Pending group (amber)
  if (
    [
      'partial', 'partially paid', 'partially-paid', 'partially_paid',
      'partially received', 'partially_received',
      'partially returned', 'partially-returned', 'partially_returned',
      'pending', 'approved', 'sent', 'confirmed', 'in progress',
    ].includes(s)
  ) {
    return 'cell-status-partial';
  }

  // Draft/Inactive/Expired group (gray)
  if (['draft', 'inactive', 'expired', 'custom'].includes(s)) {
    return 'cell-status-draft';
  }

  // Error/Cancelled group (red)
  if (['cancelled', 'canceled', 'rejected'].includes(s)) {
    return 'cell-status-cancelled';
  }

  // Info/Unpaid/Overdue group (blue)
  if (['unpaid', 'overdue', 'system'].includes(s)) {
    return 'cell-status-overdue';
  }

  // Default fallback — neutral
  return 'cell-status-draft';
}

/** Returns CSS class for balance column (due vs clear) */
export function getBalanceCellClass(balance: number | string | null | undefined): string {
  return (parseFloat(String(balance || 0)) || 0) > 0 ? 'cell-balance-due' : 'cell-balance-clear';
}

/** Returns CSS class for stock quantity column */
export function getStockCellClass(stock: number | string | null | undefined, reorderLevel: number | null = null): string {
  const qty = parseFloat(String(stock || 0)) || 0;
  if (qty <= 0) return 'cell-stock-out';
  if (reorderLevel != null && reorderLevel > 0 && qty <= reorderLevel) return 'cell-stock-low';
  return '';
}

/** Returns CSS class for active/inactive status */
export function getIsActiveCellClass(isActive: boolean | number | null | undefined): string {
  return isActive ? 'cell-status-active' : 'cell-status-inactive';
}

/** Returns CSS class for role type column (is_system_role) */
export function getRoleTypeCellClass(isSystemRole: boolean | number | null | undefined): string {
  return isSystemRole ? 'cell-type-system' : 'cell-type-custom';
}

/** Returns CSS class for on-time delivery rate */
export function getDeliveryRateCellClass(rate: number | string | null | undefined): string {
  const r = parseFloat(String(rate || 0)) || 0;
  if (r >= 95) return 'cell-rate-excellent';
  if (r >= 90) return 'cell-rate-good';
  if (r >= 80) return 'cell-rate-fair';
  return 'cell-rate-poor';
}

/** Returns CSS class for forecast recommendation */
export function getForecastRecommendationClass(recommendation: string | null | undefined): string {
  const r = (recommendation || '').toLowerCase().replace(/\s+/g, '-');
  if (r === 'order_now' || r === 'order-now') return 'cell-rec-order-now';
  if (r === 'order_soon' || r === 'order-soon') return 'cell-rec-order-soon';
  if (r === 'monitor') return 'cell-rec-monitor';
  if (r === 'adequate') return 'cell-rec-adequate';
  return '';
}

/** Returns CSS class for credit utilization */
export function getCreditUtilizationClass(utilizationPercent: number | string | null | undefined, creditLimit: number | null = null): string {
  if (!creditLimit || creditLimit <= 0) return '';
  const u = parseFloat(String(utilizationPercent || 0)) || 0;
  if (u >= 90) return 'cell-credit-high';
  if (u >= 75) return 'cell-credit-warn';
  return '';
}
