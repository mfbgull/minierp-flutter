"use strict";
/**
 * Entity Registry — centralized definition of all data sources
 * available to the ad-hoc report builder.
 *
 * Each entity describes its table, fields with types, and
 * join paths to related entities.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.getEntity = getEntity;
exports.getAllEntities = getAllEntities;
exports.getEntityKeys = getEntityKeys;
// ── Entity Registry ──────────────────────────────────────────
const ENTITY_REGISTRY = {
    invoices: {
        key: 'invoices',
        table: 'invoices',
        label: 'Invoices',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'invoice_no', column: 'invoice_no', type: 'string' },
            { name: 'invoice_date', column: 'invoice_date', type: 'date' },
            { name: 'due_date', column: 'due_date', type: 'date' },
            { name: 'status', column: 'status', type: 'string' },
            { name: 'total_amount', column: 'total_amount', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
            { name: 'paid_amount', column: 'paid_amount', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'balance_amount', column: 'balance_amount', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'discount_scope', column: 'discount_scope', type: 'string' },
            { name: 'discount_type', column: 'discount_type', type: 'string' },
            { name: 'discount_value', column: 'discount_value', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'notes', column: 'notes', type: 'string' },
            { name: 'terms', column: 'terms', type: 'string' },
            { name: 'returned_amount', column: 'returned_amount', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'return_fee', column: 'return_fee', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'created_at', column: 'created_at', type: 'date' },
            { name: 'updated_at', column: 'updated_at', type: 'date' },
            { name: 'customer_name', column: 'customer_name', type: 'string' },
        ],
        joins: [
            { entity: 'customers', type: 'MANY_TO_ONE', localField: 'customer_id', foreignField: 'id' },
            { entity: 'invoice_items', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'invoice_id' },
        ],
    },
    invoice_items: {
        key: 'invoice_items',
        table: 'invoice_items',
        label: 'Invoice Items',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'quantity', column: 'quantity', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
            { name: 'unit_price', column: 'unit_price', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'amount', column: 'amount', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
            { name: 'tax_rate', column: 'tax_rate', type: 'number', aggregateFns: ['AVG'] },
            { name: 'returned_qty', column: 'returned_qty', type: 'number', aggregateFns: ['SUM', 'AVG'] },
        ],
        joins: [
            { entity: 'invoices', type: 'MANY_TO_ONE', localField: 'invoice_id', foreignField: 'id' },
            { entity: 'items', type: 'MANY_TO_ONE', localField: 'item_id', foreignField: 'id' },
        ],
    },
    sales_orders: {
        key: 'sales_orders',
        table: 'sales_orders',
        label: 'Sales Orders',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'so_no', column: 'so_no', type: 'string' },
            { name: 'so_date', column: 'so_date', type: 'date' },
            { name: 'delivery_date', column: 'delivery_date', type: 'date' },
            { name: 'status', column: 'status', type: 'string' },
            { name: 'total_amount', column: 'total_amount', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
            { name: 'notes', column: 'notes', type: 'string' },
            { name: 'source_type', column: 'source_type', type: 'string' },
            { name: 'created_at', column: 'created_at', type: 'date' },
            { name: 'customer_name', column: 'customer_name', type: 'string' },
        ],
        joins: [
            { entity: 'customers', type: 'MANY_TO_ONE', localField: 'customer_id', foreignField: 'id' },
            { entity: 'sales_order_items', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'so_id' },
        ],
    },
    sales_order_items: {
        key: 'sales_order_items',
        table: 'sales_order_items',
        label: 'Sales Order Items',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'quantity', column: 'quantity', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'delivered_quantity', column: 'delivered_quantity', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'unit_price', column: 'unit_price', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'amount', column: 'amount', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
        ],
        joins: [
            { entity: 'sales_orders', type: 'MANY_TO_ONE', localField: 'so_id', foreignField: 'id' },
            { entity: 'items', type: 'MANY_TO_ONE', localField: 'item_id', foreignField: 'id' },
        ],
    },
    purchase_orders: {
        key: 'purchase_orders',
        table: 'purchase_orders',
        label: 'Purchase Orders',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'po_no', column: 'po_no', type: 'string' },
            { name: 'po_date', column: 'po_date', type: 'date' },
            { name: 'expected_delivery_date', column: 'expected_delivery_date', type: 'date' },
            { name: 'status', column: 'status', type: 'string' },
            { name: 'total_amount', column: 'total_amount', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
            { name: 'notes', column: 'notes', type: 'string' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'suppliers', type: 'MANY_TO_ONE', localField: 'supplier_id', foreignField: 'id' },
            { entity: 'purchase_order_items', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'po_id' },
        ],
    },
    purchase_order_items: {
        key: 'purchase_order_items',
        table: 'purchase_order_items',
        label: 'Purchase Order Items',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'quantity', column: 'quantity', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'received_quantity', column: 'received_quantity', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'unit_price', column: 'unit_price', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'amount', column: 'amount', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
        ],
        joins: [
            { entity: 'purchase_orders', type: 'MANY_TO_ONE', localField: 'po_id', foreignField: 'id' },
            { entity: 'items', type: 'MANY_TO_ONE', localField: 'item_id', foreignField: 'id' },
        ],
    },
    items: {
        key: 'items',
        table: 'items',
        label: 'Items (Inventory)',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'item_code', column: 'item_code', type: 'string' },
            { name: 'item_name', column: 'item_name', type: 'string' },
            { name: 'category', column: 'category', type: 'string' },
            { name: 'unit_of_measure', column: 'unit_of_measure', type: 'string' },
            { name: 'current_stock', column: 'current_stock', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'reorder_level', column: 'reorder_level', type: 'number', aggregateFns: ['AVG'] },
            { name: 'standard_cost', column: 'standard_cost', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'standard_selling_price', column: 'standard_selling_price', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'is_raw_material', column: 'is_raw_material', type: 'boolean' },
            { name: 'is_finished_good', column: 'is_finished_good', type: 'boolean' },
            { name: 'is_purchased', column: 'is_purchased', type: 'boolean' },
            { name: 'is_manufactured', column: 'is_manufactured', type: 'boolean' },
            { name: 'is_active', column: 'is_active', type: 'boolean' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'stock_movements', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'item_id' },
            { entity: 'stock_balances', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'item_id' },
        ],
    },
    stock_movements: {
        key: 'stock_movements',
        table: 'stock_movements',
        label: 'Stock Movements',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'movement_no', column: 'movement_no', type: 'string' },
            { name: 'movement_type', column: 'movement_type', type: 'string' },
            { name: 'quantity', column: 'quantity', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'unit_cost', column: 'unit_cost', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'movement_date', column: 'movement_date', type: 'date' },
            { name: 'reference_doctype', column: 'reference_doctype', type: 'string' },
            { name: 'reference_docno', column: 'reference_docno', type: 'string' },
            { name: 'remarks', column: 'remarks', type: 'string' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'items', type: 'MANY_TO_ONE', localField: 'item_id', foreignField: 'id' },
            { entity: 'warehouses', type: 'MANY_TO_ONE', localField: 'warehouse_id', foreignField: 'id' },
        ],
    },
    stock_balances: {
        key: 'stock_balances',
        table: 'stock_balances',
        label: 'Stock Balances',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'quantity', column: 'quantity', type: 'number', aggregateFns: ['SUM', 'AVG'] },
        ],
        joins: [
            { entity: 'items', type: 'MANY_TO_ONE', localField: 'item_id', foreignField: 'id' },
            { entity: 'warehouses', type: 'MANY_TO_ONE', localField: 'warehouse_id', foreignField: 'id' },
        ],
    },
    customers: {
        key: 'customers',
        table: 'customers',
        label: 'Customers',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'customer_code', column: 'customer_code', type: 'string' },
            { name: 'customer_name', column: 'customer_name', type: 'string' },
            { name: 'email', column: 'email', type: 'string' },
            { name: 'phone', column: 'phone', type: 'string' },
            { name: 'billing_address', column: 'billing_address', type: 'string' },
            { name: 'shipping_address', column: 'shipping_address', type: 'string' },
            { name: 'payment_terms', column: 'payment_terms', type: 'string' },
            { name: 'payment_terms_days', column: 'payment_terms_days', type: 'number' },
            { name: 'credit_limit', column: 'credit_limit', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'opening_balance', column: 'opening_balance', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'credit_balance', column: 'credit_balance', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'is_active', column: 'is_active', type: 'boolean' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'invoices', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'customer_id' },
            { entity: 'payments', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'customer_id' },
            { entity: 'sales_orders', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'customer_id' },
        ],
    },
    suppliers: {
        key: 'suppliers',
        table: 'suppliers',
        label: 'Suppliers',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'supplier_code', column: 'supplier_code', type: 'string' },
            { name: 'supplier_name', column: 'supplier_name', type: 'string' },
            { name: 'contact_person', column: 'contact_person', type: 'string' },
            { name: 'email', column: 'email', type: 'string' },
            { name: 'phone', column: 'phone', type: 'string' },
            { name: 'address', column: 'address', type: 'string' },
            { name: 'payment_terms', column: 'payment_terms', type: 'string' },
            { name: 'is_active', column: 'is_active', type: 'boolean' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'purchase_orders', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'supplier_id' },
        ],
    },
    payments: {
        key: 'payments',
        table: 'payments',
        label: 'Payments',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'payment_no', column: 'payment_no', type: 'string' },
            { name: 'payment_date', column: 'payment_date', type: 'date' },
            { name: 'amount', column: 'amount', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
            { name: 'payment_method', column: 'payment_method', type: 'string' },
            { name: 'reference_no', column: 'reference_no', type: 'string' },
            { name: 'notes', column: 'notes', type: 'string' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'customers', type: 'MANY_TO_ONE', localField: 'customer_id', foreignField: 'id' },
            { entity: 'invoices', type: 'MANY_TO_ONE', localField: 'invoice_id', foreignField: 'id' },
        ],
    },
    expenses: {
        key: 'expenses',
        table: 'expenses',
        label: 'Expenses',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'expense_no', column: 'expense_no', type: 'string' },
            { name: 'expense_category', column: 'expense_category', type: 'string' },
            { name: 'description', column: 'description', type: 'string' },
            { name: 'amount', column: 'amount', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
            { name: 'expense_date', column: 'expense_date', type: 'date' },
            { name: 'payment_method', column: 'payment_method', type: 'string' },
            { name: 'reference_no', column: 'reference_no', type: 'string' },
            { name: 'vendor_name', column: 'vendor_name', type: 'string' },
            { name: 'project', column: 'project', type: 'string' },
            { name: 'status', column: 'status', type: 'string' },
        ],
        joins: [],
    },
    employees: {
        key: 'employees',
        table: 'employees',
        label: 'Employees',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'employee_code', column: 'employee_code', type: 'string' },
            { name: 'first_name', column: 'first_name', type: 'string' },
            { name: 'last_name', column: 'last_name', type: 'string' },
            { name: 'email', column: 'email', type: 'string' },
            { name: 'phone', column: 'phone', type: 'string' },
            { name: 'department', column: 'department', type: 'string' },
            { name: 'designation', column: 'designation', type: 'string' },
            { name: 'salary', column: 'salary', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'date_of_joining', column: 'date_of_joining', type: 'date' },
            { name: 'employment_type', column: 'employment_type', type: 'string' },
            { name: 'is_active', column: 'is_active', type: 'boolean' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [],
    },
    productions: {
        key: 'productions',
        table: 'productions',
        label: 'Productions',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'production_no', column: 'production_no', type: 'string' },
            { name: 'production_date', column: 'production_date', type: 'date' },
            { name: 'output_quantity', column: 'output_quantity', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'overhead_cost', column: 'overhead_cost', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'total_material_cost', column: 'total_material_cost', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'total_batch_cost', column: 'total_batch_cost', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'unit_cost', column: 'unit_cost', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'remarks', column: 'remarks', type: 'string' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'items', type: 'MANY_TO_ONE', localField: 'output_item_id', foreignField: 'id' },
        ],
    },
    warehouses: {
        key: 'warehouses',
        table: 'warehouses',
        label: 'Warehouses',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'warehouse_code', column: 'warehouse_code', type: 'string' },
            { name: 'warehouse_name', column: 'warehouse_name', type: 'string' },
            { name: 'location', column: 'location', type: 'string' },
            { name: 'is_active', column: 'is_active', type: 'boolean' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'stock_balances', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'warehouse_id' },
            { entity: 'stock_movements', type: 'ONE_TO_MANY', localField: 'id', foreignField: 'warehouse_id' },
        ],
    },
    boms: {
        key: 'boms',
        table: 'boms',
        label: 'Bill of Materials',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'bom_no', column: 'bom_no', type: 'string' },
            { name: 'bom_name', column: 'bom_name', type: 'string' },
            { name: 'quantity', column: 'quantity', type: 'number', aggregateFns: ['SUM', 'AVG'] },
            { name: 'is_active', column: 'is_active', type: 'boolean' },
            { name: 'notes', column: 'notes', type: 'string' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'items', type: 'MANY_TO_ONE', localField: 'finished_item_id', foreignField: 'id' },
        ],
    },
    quotations: {
        key: 'quotations',
        table: 'quotations',
        label: 'Quotations',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'quotation_no', column: 'quotation_no', type: 'string' },
            { name: 'quotation_date', column: 'quotation_date', type: 'date' },
            { name: 'expiry_date', column: 'expiry_date', type: 'date' },
            { name: 'status', column: 'status', type: 'string' },
            { name: 'source_type', column: 'source_type', type: 'string' },
            { name: 'total_amount', column: 'total_amount', type: 'number', aggregateFns: ['SUM', 'AVG', 'MIN', 'MAX'] },
            { name: 'notes', column: 'notes', type: 'string' },
            { name: 'terms', column: 'terms', type: 'string' },
            { name: 'customer_name', column: 'customer_name', type: 'string' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [
            { entity: 'customers', type: 'MANY_TO_ONE', localField: 'customer_id', foreignField: 'id' },
        ],
    },
    activity_log: {
        key: 'activity_log',
        table: 'activity_log',
        label: 'Activity Log',
        fields: [
            { name: 'id', column: 'id', type: 'number' },
            { name: 'action', column: 'action', type: 'string' },
            { name: 'entity_type', column: 'entity_type', type: 'string' },
            { name: 'entity_id', column: 'entity_id', type: 'number' },
            { name: 'description', column: 'description', type: 'string' },
            { name: 'log_level', column: 'log_level', type: 'string' },
            { name: 'created_at', column: 'created_at', type: 'date' },
        ],
        joins: [],
    },
};
// ── Public API ───────────────────────────────────────────────
function getEntity(entityKey) {
    return ENTITY_REGISTRY[entityKey];
}
function getAllEntities() {
    return Object.values(ENTITY_REGISTRY);
}
function getEntityKeys() {
    return Object.keys(ENTITY_REGISTRY);
}
exports.default = {
    getEntity,
    getAllEntities,
    getEntityKeys,
};
//# sourceMappingURL=entityRegistry.js.map