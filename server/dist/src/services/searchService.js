"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PAGE_ACTIONS = exports.ENTITY_ACTIONS = void 0;
exports.filterActions = filterActions;
exports.searchCustomers = searchCustomers;
exports.searchSuppliers = searchSuppliers;
exports.searchProducts = searchProducts;
exports.searchInvoices = searchInvoices;
exports.searchPurchaseOrders = searchPurchaseOrders;
exports.searchQuotations = searchQuotations;
exports.searchSalesOrders = searchSalesOrders;
exports.searchPayments = searchPayments;
exports.searchExpenses = searchExpenses;
exports.searchWarehouses = searchWarehouses;
exports.searchEmployees = searchEmployees;
exports.searchProductions = searchProductions;
exports.searchBOMs = searchBOMs;
exports.searchPages = searchPages;
exports.search = search;
const database_1 = __importDefault(require("../config/database"));
// ============================================================
// Entity-action registry (spec §4.9)
// ============================================================
exports.ENTITY_ACTIONS = {
    customer: [
        { id: 'open', label: 'Open Customer' },
        { id: 'create_invoice', label: 'Create Sales Invoice', permission: 'invoices:create' },
        { id: 'receive_payment', label: 'Receive Payment', permission: 'payments:create' },
        { id: 'ledger', label: 'View Ledger' },
        { id: 'sales_history', label: 'View Sales History' },
    ],
    supplier: [
        { id: 'open', label: 'Open Supplier' },
        { id: 'create_purchase', label: 'Create Purchase', permission: 'purchases:create' },
        { id: 'make_payment', label: 'Make Payment', permission: 'payments:create' },
        { id: 'ledger', label: 'View Supplier Ledger' },
        { id: 'purchase_history', label: 'View Purchase History' },
    ],
    product: [
        { id: 'open', label: 'Open Product' },
        { id: 'create_sale', label: 'Create Sale', permission: 'invoices:create' },
        { id: 'create_purchase', label: 'Create Purchase', permission: 'purchases:create' },
        { id: 'adjust_stock', label: 'Adjust Stock', permission: 'inventory:update' },
        { id: 'stock_movements', label: 'View Stock Movements' },
    ],
    invoice: [
        { id: 'open', label: 'Open Invoice' },
        {
            id: 'return_items',
            label: 'Return Items',
            permission: 'invoices:update',
            condition: (row) => row.status !== 'Cancelled',
        },
        {
            id: 'record_payment',
            label: 'Record Payment',
            permission: 'payments:create',
            condition: (row) => row.status !== 'Paid' &&
                row.status !== 'Returned' &&
                row.status !== 'Cancelled',
        },
        { id: 'print', label: 'Print Invoice' },
    ],
    purchase_order: [
        { id: 'open', label: 'Open Purchase Order' },
        {
            id: 'receive',
            label: 'Receive Goods',
            permission: 'purchases:create',
            condition: (row) => row.status === 'Submitted' || row.status === 'Partially Received',
        },
    ],
    quotation: [
        { id: 'open', label: 'Open Quotation' },
        {
            id: 'convert_to_so',
            label: 'Convert to Sales Order',
            permission: 'sales_orders:create',
            condition: (row) => row.status === 'Accepted',
        },
    ],
    sales_order: [
        { id: 'open', label: 'Open Sales Order' },
        {
            id: 'create_invoice',
            label: 'Create Invoice',
            permission: 'invoices:create',
            condition: (row) => row.status !== 'Cancelled' &&
                row.status !== 'Invoiced' &&
                row.status !== 'Completed',
        },
    ],
    payment: [
        { id: 'open', label: 'Open Payment' },
        { id: 'print', label: 'Print Receipt' },
    ],
    expense: [
        { id: 'open', label: 'Open Expense' },
    ],
    warehouse: [
        { id: 'open', label: 'Open Warehouse' },
        { id: 'view_stock', label: 'View Stock' },
        { id: 'stock_movements', label: 'View Stock Movements' },
    ],
    employee: [
        { id: 'open', label: 'Open Employee' },
        { id: 'pay_salary', label: 'Pay Salary', permission: 'employees:update' },
    ],
    production: [
        { id: 'open', label: 'Open Production' },
    ],
    bom: [
        { id: 'open', label: 'Open BOM' },
        {
            id: 'produce',
            label: 'Start Production',
            permission: 'production:create',
            condition: (row) => row.is_active === true || row.is_active === 1,
        },
    ],
};
// ============================================================
// Page/action registry (spec §4.11)
// ============================================================
exports.PAGE_ACTIONS = [
    { id: 'dashboard', title: 'Dashboard', path: '/', icon: 'space_dashboard_outlined', keywords: ['home', 'overview'] },
    { id: 'inventory', title: 'Inventory', path: '/inventory', icon: 'inventory_2_outlined', keywords: ['items', 'products', 'stock'] },
    { id: 'customers', title: 'Customers', path: '/customers', icon: 'people_outline', keywords: ['clients', 'accounts'] },
    { id: 'sales', title: 'Sales', path: '/sales', icon: 'point_of_sale_outlined', keywords: ['invoices', 'billing'] },
    { id: 'purchasing', title: 'Purchasing', path: '/purchasing', icon: 'shopping_cart_outlined', keywords: ['buy', 'procurement'] },
    { id: 'suppliers', title: 'Suppliers', path: '/suppliers', icon: 'local_shipping_outlined', keywords: ['vendors', 'buyers'] },
    { id: 'production', title: 'Manufacturing', path: '/production', icon: 'factory_outlined', keywords: ['bom', 'work order', 'manufacturing'] },
    { id: 'payments', title: 'Payments', path: '/payments', icon: 'account_balance_wallet_outlined', keywords: ['receipts', 'transactions'] },
    { id: 'expenses', title: 'Expenses', path: '/expenses', icon: 'receipt_long_outlined', keywords: ['costs', 'spending'] },
    { id: 'employees', title: 'Employees', path: '/hr', icon: 'badge_outlined', keywords: ['hr', 'staff', 'salary'] },
    { id: 'reports', title: 'Reports', path: '/reports', icon: 'assessment_outlined', keywords: ['analytics', 'summary'], permission: 'reports:read' },
    { id: 'forecasts', title: 'Forecasts', path: '/forecasts', icon: 'insights_outlined', keywords: ['demand', 'prediction'] },
    { id: 'activity_log', title: 'Activity Log', path: '/activity-log', icon: 'history', keywords: ['audit', 'history'] },
    { id: 'settings', title: 'Settings', path: '/settings', icon: 'settings_outlined', keywords: ['config', 'preferences'] },
    { id: 'create_invoice', title: 'Create Sales Invoice', path: '/sales/form', icon: 'add_circle_outline', keywords: ['new', 'billing', 'sale'], action: true, permission: 'invoices:create' },
    { id: 'create_purchase', title: 'Create Purchase', path: '/purchasing', icon: 'add_circle_outline', keywords: ['new', 'buy'], action: true, permission: 'purchases:create' },
    { id: 'add_customer', title: 'Add Customer', path: '/customers', icon: 'person_add', keywords: ['new', 'client'], action: true, permission: 'customers:create' },
    { id: 'add_supplier', title: 'Add Supplier', path: '/suppliers', icon: 'business', keywords: ['new', 'vendor'], action: true, permission: 'suppliers:create' },
    { id: 'receive_payment', title: 'Receive Payment', path: '/payments', icon: 'payments', keywords: ['money', 'incoming'], action: true, permission: 'payments:create' },
    { id: 'make_payment', title: 'Make Payment', path: '/payments', icon: 'money_off', keywords: ['outgoing', 'expense'], action: true, permission: 'payments:create' },
];
// ============================================================
// Permission helpers
// ============================================================
/**
 * Get all allowed module:action strings for a user.
 * Admin role (role_name = 'Admin') bypasses all checks.
 */
function getUserPermissions(userId) {
    const user = database_1.default.prepare('SELECT role FROM users WHERE id = ?').get(userId);
    if (user?.role === 'admin') {
        // Admin has all permissions
        const all = database_1.default.prepare('SELECT module, action FROM permissions').all();
        return new Set(all.map((p) => `${p.module}:${p.action}`));
    }
    const role = database_1.default.prepare('SELECT role_id FROM users WHERE id = ?').get(userId);
    if (!role?.role_id)
        return new Set();
    const perms = database_1.default.prepare(`
    SELECT p.module, p.action
    FROM role_permissions rp
    JOIN permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = ?
  `).all();
    return new Set(perms.map((p) => `${p.module}:${p.action}`));
}
/**
 * Filter actions for a given result based on user permissions and
 * status-based conditions.
 */
function filterActions(actions, userId, entityRow) {
    const allowed = getUserPermissions(userId);
    const user = database_1.default.prepare('SELECT role FROM users WHERE id = ?').get(userId);
    const isAdmin = user?.role === 'admin';
    return actions
        .filter((action) => {
        // Admin bypasses permission checks
        if (isAdmin)
            return true;
        // If no permission required, action is always shown
        if (!action.permission)
            return true;
        // Check user has the required permission
        const [module, act] = action.permission.split(':');
        return allowed.has(`${module}:${act}`);
    })
        .filter((action) => {
        // Evaluate status-based condition
        if (action.condition && !action.condition(entityRow)) {
            return false;
        }
        return true;
    })
        .map((action) => ({ id: action.id, label: action.label }));
}
// ============================================================
// Per-entity search functions
// ============================================================
function rankClause(field, alias = 'name') {
    return `
    CASE
      WHEN ${field} LIKE ? THEN 1
      WHEN ${field} LIKE ? THEN 2
      WHEN ${field} LIKE ? THEN 3
      ELSE 4
    END
  `;
}
function rankParams(prefix) {
    return [
        `${prefix}%`, // starts-with = 1
        `%${prefix}%`, // contains = 2
        `${prefix}%`, // code starts-with = 3
    ];
}
function searchCustomers(query, limit, userId) {
    const q = `%${query}%`;
    const qs = `${query}%`;
    const rows = database_1.default
        .prepare(`SELECT id, customer_name, customer_code, phone, email,
              COALESCE(current_balance, 0) AS current_balance
       FROM customers
       WHERE is_active = 1
         AND (customer_name LIKE ? OR customer_code LIKE ? OR phone LIKE ? OR email LIKE ? OR contact_person LIKE ?)
       ORDER BY
         CASE
           WHEN customer_name LIKE ? THEN 1
           WHEN customer_name LIKE ? THEN 2
           WHEN customer_code LIKE ? THEN 3
           ELSE 4
         END,
         customer_name ASC
       LIMIT ?`)
        .all(q, q, q, q, q, qs, q, qs, limit);
    return rows.map((r) => {
        const balance = Number(r.current_balance) || 0;
        const subtitle = `${r.customer_code} · Rs. ${balance.toLocaleString()} due`;
        return {
            type: 'customer',
            id: r.id,
            title: r.customer_name,
            subtitle,
            metadata: {
                balance,
                phone: r.phone ?? null,
                email: r.email ?? null,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.customer, userId, r),
        };
    });
}
function searchSuppliers(query, limit, userId) {
    const q = `%${query}%`;
    const qs = `${query}%`;
    const rows = database_1.default
        .prepare(`SELECT id, supplier_name, supplier_code, phone, email,
              COALESCE(current_balance, 0) AS current_balance
       FROM suppliers
       WHERE is_active = 1
         AND (supplier_name LIKE ? OR supplier_code LIKE ? OR phone LIKE ? OR email LIKE ? OR contact_person LIKE ?)
       ORDER BY
         CASE
           WHEN supplier_name LIKE ? THEN 1
           WHEN supplier_name LIKE ? THEN 2
           WHEN supplier_code LIKE ? THEN 3
           ELSE 4
         END,
         supplier_name ASC
       LIMIT ?`)
        .all(q, q, q, q, q, qs, q, qs, limit);
    return rows.map((r) => {
        const balance = Number(r.current_balance) || 0;
        const subtitle = `${r.supplier_code} · Payable: Rs. ${balance.toLocaleString()}`;
        return {
            type: 'supplier',
            id: r.id,
            title: r.supplier_name,
            subtitle,
            metadata: {
                balance,
                phone: r.phone ?? null,
                email: r.email ?? null,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.supplier, userId, r),
        };
    });
}
function searchProducts(query, limit, userId) {
    const q = `%${query}%`;
    const qs = `${query}%`;
    const rows = database_1.default
        .prepare(`SELECT id, item_name, item_code, category, description,
              current_stock, standard_selling_price, unit_of_measure, is_active
       FROM items
       WHERE is_active = 1
         AND (item_name LIKE ? OR item_code LIKE ? OR category LIKE ? OR description LIKE ?)
       ORDER BY
         CASE
           WHEN item_name LIKE ? THEN 1
           WHEN item_name LIKE ? THEN 2
           WHEN item_code LIKE ? THEN 3
           ELSE 4
         END,
         item_name ASC
       LIMIT ?`)
        .all(q, q, q, q, qs, q, qs, limit);
    return rows.map((r) => {
        const stock = Number(r.current_stock) || 0;
        const price = Number(r.standard_selling_price) || 0;
        const subtitle = `${r.item_code} · Stock: ${stock} · Rs. ${price.toLocaleString()}`;
        return {
            type: 'product',
            id: r.id,
            title: r.item_name,
            subtitle,
            metadata: {
                stock,
                price,
                category: r.category ?? null,
                unit: r.unit_of_measure,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.product, userId, r),
        };
    });
}
function searchInvoices(query, limit, userId) {
    const q = `%${query}%`;
    const qs = `${query}%`;
    const rows = database_1.default
        .prepare(`SELECT i.id, i.invoice_no, i.customer_id, i.status, i.total_amount, i.balance_amount, i.invoice_date,
              c.customer_name
       FROM invoices i
       JOIN customers c ON c.id = i.customer_id
       WHERE (i.invoice_no LIKE ? OR c.customer_name LIKE ?)
       ORDER BY
         CASE
           WHEN i.invoice_no LIKE ? THEN 1
           WHEN i.invoice_no LIKE ? THEN 2
           WHEN c.customer_name LIKE ? THEN 3
           ELSE 4
         END,
         i.invoice_date DESC
       LIMIT ?`)
        .all(q, q, qs, q, qs, limit);
    return rows.map((r) => {
        const subtitle = `${r.customer_name} · ${r.status} · Rs. ${Number(r.balance_amount).toLocaleString()}`;
        return {
            type: 'invoice',
            id: r.id,
            title: r.invoice_no,
            subtitle,
            metadata: {
                status: r.status,
                total: Number(r.total_amount),
                balance: Number(r.balance_amount),
                customer_name: r.customer_name,
                invoice_date: r.invoice_date,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.invoice, userId, r),
        };
    });
}
function searchPurchaseOrders(query, limit, userId) {
    const q = `%${query}%`;
    const qs = `${query}%`;
    const rows = database_1.default
        .prepare(`SELECT po.id, po.po_no, po.status, po.total_amount, po.po_date,
              s.supplier_name
       FROM purchase_orders po
       JOIN suppliers s ON s.id = po.supplier_id
       WHERE po.po_no LIKE ?
       ORDER BY po.po_date DESC
       LIMIT ?`)
        .all(qs, limit);
    return rows.map((r) => {
        const subtitle = `${r.supplier_name} · ${r.status} · Rs. ${Number(r.total_amount).toLocaleString()}`;
        return {
            type: 'purchase_order',
            id: r.id,
            title: r.po_no,
            subtitle,
            metadata: {
                status: r.status,
                total: Number(r.total_amount),
                supplier_name: r.supplier_name,
                po_date: r.po_date,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.purchase_order, userId, r),
        };
    });
}
function searchQuotations(query, limit, userId) {
    const q = `%${query}%`;
    const rows = database_1.default
        .prepare(`SELECT q.id, q.quotation_no, q.status, q.total_amount, q.quotation_date,
              c.customer_name
       FROM quotations q
       JOIN customers c ON c.id = q.customer_id
       WHERE q.quotation_no LIKE ? OR c.customer_name LIKE ? OR q.status LIKE ?
       ORDER BY q.quotation_date DESC
       LIMIT ?`)
        .all(q, q, q, limit);
    return rows.map((r) => {
        const subtitle = `${r.customer_name} · ${r.status} · Rs. ${Number(r.total_amount).toLocaleString()}`;
        return {
            type: 'quotation',
            id: r.id,
            title: r.quotation_no,
            subtitle,
            metadata: {
                status: r.status,
                total: Number(r.total_amount),
                customer_name: r.customer_name,
                quotation_date: r.quotation_date,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.quotation, userId, r),
        };
    });
}
function searchSalesOrders(query, limit, userId) {
    const q = `%${query}%`;
    const rows = database_1.default
        .prepare(`SELECT so.id, so.so_no, so.status, so.total_amount, so.so_date,
              c.customer_name
       FROM sales_orders so
       JOIN customers c ON c.id = so.customer_id
       WHERE so.so_no LIKE ?
       ORDER BY so.so_date DESC
       LIMIT ?`)
        .all(q, limit);
    return rows.map((r) => {
        const subtitle = `${r.customer_name} · ${r.status} · Rs. ${Number(r.total_amount).toLocaleString()}`;
        return {
            type: 'sales_order',
            id: r.id,
            title: r.so_no,
            subtitle,
            metadata: {
                status: r.status,
                total: Number(r.total_amount),
                customer_name: r.customer_name,
                so_date: r.so_date,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.sales_order, userId, r),
        };
    });
}
function searchPayments(query, limit, userId) {
    const q = `%${query}%`;
    const rows = database_1.default
        .prepare(`SELECT p.id, p.payment_no, p.amount, p.payment_method, p.payment_date, p.reference_no,
              p.customer_id, p.supplier_id,
              c.customer_name, s.supplier_name
       FROM payments p
       LEFT JOIN customers c ON c.id = p.customer_id
       LEFT JOIN suppliers s ON s.id = p.supplier_id
       WHERE p.payment_no LIKE ? OR p.reference_no LIKE ?
       ORDER BY p.payment_date DESC
       LIMIT ?`)
        .all(q, q, limit);
    return rows.map((r) => {
        const partyName = r.customer_name ?? r.supplier_name ?? '—';
        const subtitle = `${partyName} · Rs. ${Number(r.amount).toLocaleString()} · ${r.payment_method ?? '—'}`;
        return {
            type: 'payment',
            id: r.id,
            title: r.payment_no,
            subtitle,
            metadata: {
                amount: Number(r.amount),
                method: r.payment_method ?? null,
                customer_name: r.customer_name ?? null,
                payment_date: r.payment_date,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.payment, userId, r),
        };
    });
}
function searchExpenses(query, limit, userId) {
    const q = `%${query}%`;
    const rows = database_1.default
        .prepare(`SELECT id, description, expense_category, amount, expense_date, reference_no
       FROM expenses
       WHERE description LIKE ? OR reference_no LIKE ?
       ORDER BY expense_date DESC
       LIMIT ?`)
        .all(q, q, limit);
    return rows.map((r) => {
        const subtitle = `${r.expense_category} · Rs. ${Number(r.amount).toLocaleString()}`;
        return {
            type: 'expense',
            id: r.id,
            title: r.description,
            subtitle,
            metadata: {
                amount: Number(r.amount),
                category: r.expense_category,
                expense_date: r.expense_date,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.expense, userId, r),
        };
    });
}
function searchWarehouses(query, limit, userId) {
    const q = `%${query}%`;
    const qs = `${query}%`;
    const rows = database_1.default
        .prepare(`SELECT id, warehouse_name, warehouse_code, location, is_active
       FROM warehouses
       WHERE warehouse_name LIKE ? OR warehouse_code LIKE ?
       ORDER BY warehouse_name ASC
       LIMIT ?`)
        .all(q, q, limit);
    return rows.map((r) => {
        const subtitle = `${r.warehouse_code} · ${r.location ?? 'No location'}`;
        return {
            type: 'warehouse',
            id: r.id,
            title: r.warehouse_name,
            subtitle,
            metadata: {
                code: r.warehouse_code,
                location: r.location ?? null,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.warehouse, userId, r),
        };
    });
}
function searchEmployees(query, limit, userId) {
    const q = `%${query}%`;
    const qs = `${query}%`;
    const rows = database_1.default
        .prepare(`SELECT id, first_name, last_name, employee_code, department, phone, is_active
       FROM employees
       WHERE first_name LIKE ? OR last_name LIKE ? OR employee_code LIKE ?
       ORDER BY
         CASE
           WHEN first_name LIKE ? THEN 1
           WHEN last_name LIKE ? THEN 2
           WHEN employee_code LIKE ? THEN 3
           ELSE 4
         END,
         first_name ASC, last_name ASC
       LIMIT ?`)
        .all(q, q, q, qs, qs, qs, limit);
    return rows.map((r) => {
        const subtitle = `${r.employee_code} · ${r.department ?? '—'}`;
        return {
            type: 'employee',
            id: r.id,
            title: `${r.first_name} ${r.last_name}`,
            subtitle,
            metadata: {
                code: r.employee_code,
                department: r.department ?? null,
                phone: r.phone ?? null,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.employee, userId, r),
        };
    });
}
function searchProductions(query, limit, userId) {
    const q = `%${query}%`;
    const rows = database_1.default
        .prepare(`SELECT p.id, p.production_no, p.output_quantity, p.production_date, p.remarks,
              i.item_name
       FROM productions p
       JOIN items i ON i.id = p.output_item_id
       WHERE p.production_no LIKE ?
       ORDER BY p.production_date DESC
       LIMIT ?`)
        .all(q, limit);
    return rows.map((r) => {
        const subtitle = `${r.item_name} · Draft · Qty: ${Number(r.output_quantity).toLocaleString()}`;
        return {
            type: 'production',
            id: r.id,
            title: r.production_no,
            subtitle,
            metadata: {
                status: 'Draft',
                planned_quantity: Number(r.output_quantity),
                item_name: r.item_name,
                start_date: r.production_date,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.production, userId, r),
        };
    });
}
function searchBOMs(query, limit, userId) {
    const q = `%${query}%`;
    const rows = database_1.default
        .prepare(`SELECT b.id, b.bom_no, b.bom_name, b.is_active,
              i.item_name,
              (SELECT COUNT(*) FROM bom_items WHERE bom_id = b.id) AS component_count
       FROM boms b
       JOIN items i ON i.id = b.finished_item_id
       WHERE b.bom_no LIKE ? OR b.bom_name LIKE ?
       ORDER BY b.bom_no ASC
       LIMIT ?`)
        .all(q, q, limit);
    return rows.map((r) => {
        const active = r.is_active === 1;
        const subtitle = `${r.bom_name ?? r.item_name} · ${active ? 'Active' : 'Inactive'} · ${r.component_count} components`;
        return {
            type: 'bom',
            id: r.id,
            title: r.bom_no,
            subtitle,
            metadata: {
                is_active: active,
                item_name: r.item_name,
                component_count: r.component_count,
            },
            actions: filterActions(exports.ENTITY_ACTIONS.bom, userId, r),
        };
    });
}
// ============================================================
// Page/action search
// ============================================================
function searchPages(query, userId) {
    const q = query.toLowerCase();
    const user = database_1.default.prepare('SELECT role FROM users WHERE id = ?').get(userId);
    const isAdmin = user?.role === 'admin';
    const allowed = isAdmin ? null : getUserPermissions(userId);
    return exports.PAGE_ACTIONS.filter((page) => {
        // Permission filter
        if (!isAdmin && page.permission) {
            const [module, action] = page.permission.split(':');
            if (!allowed?.has(`${module}:${action}`))
                return false;
        }
        // Keyword match: title + keywords
        const haystack = `${page.title} ${(page.keywords ?? []).join(' ')}`.toLowerCase();
        if (!q || haystack.includes(q))
            return !!q;
        return false;
    }).map((page) => ({
        type: 'page',
        id: page.id,
        title: page.title,
        subtitle: page.action ? 'Action' : 'Module',
        metadata: {
            path: page.path,
            icon: page.icon,
            action: page.action ?? false,
        },
        actions: [], // pages don't have sub-actions in the result list
    }));
}
// ============================================================
// Main search orchestrator
// ============================================================
function search(query, limit, userId) {
    const trimmed = query.trim();
    if (trimmed.length < 2) {
        return { query: trimmed, results: [], total: 0 };
    }
    const results = [
        ...searchCustomers(trimmed, limit, userId),
        ...searchSuppliers(trimmed, limit, userId),
        ...searchProducts(trimmed, limit, userId),
        ...searchInvoices(trimmed, limit, userId),
        ...searchPurchaseOrders(trimmed, limit, userId),
        ...searchQuotations(trimmed, limit, userId),
        ...searchSalesOrders(trimmed, limit, userId),
        ...searchPayments(trimmed, limit, userId),
        ...searchExpenses(trimmed, limit, userId),
        ...searchWarehouses(trimmed, limit, userId),
        ...searchEmployees(trimmed, limit, userId),
        ...searchProductions(trimmed, limit, userId),
        ...searchBOMs(trimmed, limit, userId),
        ...searchPages(trimmed, userId),
    ];
    return {
        query: trimmed,
        results,
        total: results.length,
    };
}
//# sourceMappingURL=searchService.js.map