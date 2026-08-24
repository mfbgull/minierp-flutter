"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BOM_SORT_COLUMNS = exports.EXPENSE_SORT_COLUMNS = exports.PRODUCTION_SORT_COLUMNS = exports.PURCHASE_RETURN_HEADER_SORT_COLUMNS = exports.PURCHASE_SORT_COLUMNS = exports.PURCHASE_ORDER_SORT_COLUMNS = exports.INVOICE_RETURN_SORT_COLUMNS = exports.QUOTATION_SORT_COLUMNS = exports.SALES_ORDER_SORT_COLUMNS = exports.INVOICE_SORT_COLUMNS = exports.PHYSICAL_COUNT_SORT_COLUMNS = exports.STOCK_BALANCE_SORT_COLUMNS = exports.ITEM_SORT_COLUMNS = exports.STOCK_MOVEMENT_SORT_COLUMNS = exports.PAYMENT_SORT_COLUMNS = exports.LEDGER_SORT_COLUMNS = exports.SUPPLIER_SORT_COLUMNS = exports.CUSTOMER_SORT_COLUMNS = void 0;
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
// Whitelisted sort columns for stock movements (the grid's sortable
// columns; mapped to qualified SQL columns in StockMovementModel.getAll)
exports.STOCK_MOVEMENT_SORT_COLUMNS = [
    'movement_no',
    'movement_date',
    'item_name',
    'warehouse_name',
    'movement_type',
    'quantity',
    'reference_docno',
    'created_at'
];
// Whitelisted sort columns for items (`ItemModel.getAll`; unqualified —
// the items table has no joins)
exports.ITEM_SORT_COLUMNS = [
    'item_code',
    'item_name',
    'category',
    'current_stock',
    'reorder_level'
];
// Whitelisted sort columns for stock balances (the stock-by-warehouse
// grid; mapped to qualified SQL columns in StockMovementModel.getStockBalances)
exports.STOCK_BALANCE_SORT_COLUMNS = [
    'item_code',
    'item_name',
    'warehouse_name',
    'quantity'
];
// Whitelisted sort columns for physical counts (mapped to qualified SQL
// columns in PhysicalCountModel.getAll — the users join makes bare
// `created_at` ambiguous)
exports.PHYSICAL_COUNT_SORT_COLUMNS = [
    'count_no',
    'count_date',
    'warehouse_name',
    'status',
    'created_at'
];
// Whitelisted sort columns for invoices (`InvoiceModel.getAll`; mapped to
// qualified SQL columns — the customer/sales-order/quotation/user joins
// make bare names ambiguous)
exports.INVOICE_SORT_COLUMNS = [
    'invoice_no',
    'invoice_date',
    'customer_name',
    'status',
    'total_amount',
    'paid_amount',
    'balance_amount',
    'due_date',
    'created_at'
];
// Whitelisted sort columns for sales orders (`SalesOrderModel.getAll`;
// mapped to qualified SQL columns — the warehouse/user/quotation joins)
exports.SALES_ORDER_SORT_COLUMNS = [
    'so_no',
    'so_date',
    'customer_name',
    'status',
    'total_amount',
    'delivery_date',
    'created_at'
];
// Whitelisted sort columns for quotations (`QuotationModel.getAll`;
// mapped to qualified SQL columns — the warehouse/user joins)
exports.QUOTATION_SORT_COLUMNS = [
    'quotation_no',
    'quotation_date',
    'customer_name',
    'status',
    'total_amount',
    'expiry_date',
    'created_at'
];
// Whitelisted sort columns for invoice-return history
// (`InvoiceModel.getReturnHistory`; mapped to qualified SQL columns — the
// item/warehouse/user/invoice joins)
exports.INVOICE_RETURN_SORT_COLUMNS = [
    'movement_no',
    'return_date',
    'item_name',
    'customer_name',
    'warehouse_name',
    'quantity',
    'unit_cost',
    'created_at'
];
// Whitelisted sort columns for purchase orders (`PurchaseOrderModel.getAll`;
// mapped to qualified SQL columns — the supplier/warehouse/user/allocations
// joins)
exports.PURCHASE_ORDER_SORT_COLUMNS = [
    'po_no',
    'po_date',
    'supplier_name',
    'status',
    'total_amount',
    'balance_amount',
    'expected_delivery_date',
    'created_at'
];
// Whitelisted sort columns for direct purchases (`PurchaseModel.getAll`;
// mapped to qualified SQL columns — the item/warehouse/user joins)
exports.PURCHASE_SORT_COLUMNS = [
    'purchase_no',
    'purchase_date',
    'item_name',
    'supplier_name',
    'quantity',
    'unit_cost',
    'total_cost',
    'paid_amount',
    'balance_amount',
    'warehouse_name',
    'created_at'
];
// Whitelisted sort columns for purchase-return headers
// (`PurchaseReturnModel.getAll`; mapped to qualified SQL columns — the
// warehouse/user/credit-note joins make bare names ambiguous)
exports.PURCHASE_RETURN_HEADER_SORT_COLUMNS = [
    'return_no',
    'return_date',
    'source_no',
    'total_amount',
    'status',
    'warehouse_name',
    'created_at'
];
// Whitelisted sort columns for productions (`ProductionModel.getAll`;
// mapped to qualified SQL columns — the item/warehouse/user joins make
// bare names ambiguous)
exports.PRODUCTION_SORT_COLUMNS = [
    'production_no',
    'production_date',
    'output_item_name',
    'warehouse_name',
    'output_quantity',
    'unit_cost',
    'total_batch_cost',
    'batch_no',
    'created_at'
];
// Whitelisted sort columns for expenses (`ExpenseModel.getAll`; mapped
// to qualified SQL columns — the users join makes bare names ambiguous)
exports.EXPENSE_SORT_COLUMNS = [
    'e.expense_no',
    'e.expense_date',
    'e.expense_category',
    'e.description',
    'e.amount',
    'e.status',
    'e.vendor_name',
    'e.payment_method',
    'e.project',
    'e.created_at'
];
// Whitelisted sort columns for BOMs (`BOMModel.getAll`; mapped to
// qualified SQL columns — the finished-item join)
exports.BOM_SORT_COLUMNS = [
    'bom_no',
    'bom_name',
    'finished_item_name',
    'quantity',
    'item_count',
    'total_material_cost',
    'created_at'
];
//# sourceMappingURL=sqlSanitizer.js.map