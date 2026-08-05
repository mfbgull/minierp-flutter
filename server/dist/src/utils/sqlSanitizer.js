"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PAYMENT_SORT_COLUMNS = exports.LEDGER_SORT_COLUMNS = exports.SUPPLIER_SORT_COLUMNS = exports.CUSTOMER_SORT_COLUMNS = void 0;
exports.sanitizeSortParams = sanitizeSortParams;
/**
 * Sanitize sort parameters to prevent SQL injection.
 * Uses whitelist-based validation for column and order.
 * @param sortBy - The column to sort by (user input)
 * @param sortOrder - The order direction (user input)
 * @param allowedColumns - Array of allowed column names
 * @param defaultColumn - Default column to use if sortBy is not in allowedColumns
 * @param defaultOrder - Default order to use if sortOrder is not ASC or DESC
 * @returns Object with sanitized column and order
 */
function sanitizeSortParams(sortBy, sortOrder, allowedColumns, defaultColumn, defaultOrder) {
    // Default sort column (first allowed column) and order
    const columnDefault = defaultColumn ?? (allowedColumns[0] || 'id');
    const orderDefault = defaultOrder ?? 'ASC';
    // Validate sortBy against allowed columns
    const column = allowedColumns.includes(sortBy) ? sortBy : columnDefault;
    // Validate sortOrder - only allow ASC or DESC (case-insensitive)
    const order = sortOrder.toUpperCase() === 'DESC' ? 'DESC' : orderDefault;
    return { column, order };
}
// Whitelisted sort columns for customers
exports.CUSTOMER_SORT_COLUMNS = [
    'customer_code',
    'customer_name',
    'contact_person',
    'email',
    'phone',
    'billing_address',
    'shipping_address',
    'payment_terms',
    'credit_limit',
    'current_balance',
    'created_at',
    'is_active'
];
// Whitelisted sort columns for suppliers
exports.SUPPLIER_SORT_COLUMNS = [
    'supplier_code',
    'supplier_name',
    'contact_person',
    'email',
    'phone',
    'address',
    'payment_terms',
    'current_balance',
    'created_at',
    'is_active'
];
// Whitelisted sort columns for customer ledger
exports.LEDGER_SORT_COLUMNS = [
    'transaction_date',
    'transaction_type',
    'reference_no',
    'debit',
    'credit',
    'balance',
    'description',
    'created_at'
];
// Whitelisted sort columns for payments
exports.PAYMENT_SORT_COLUMNS = [
    'payment_no',
    'payment_date',
    'amount',
    'payment_method',
    'reference_no',
    'created_at'
];
//# sourceMappingURL=sqlSanitizer.js.map