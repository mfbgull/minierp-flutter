import { z } from 'zod';

// ── Auth ──────────────────────────────────────────────────────────
export const loginSchema = z.object({
  username: z.string().min(1, 'Username is required'),
  password: z.string().min(1, 'Password is required'),
});

// ── Customers ─────────────────────────────────────────────────────
export const customerSchema = z.object({
  customer_name: z.string().min(1, 'Customer name is required'),
  contact_person: z.string().optional(),
  email: z.string().email('Invalid email format').or(z.literal('')).optional(),
  phone: z.string().min(1, 'Phone number is required'),
  billing_address: z.string().optional(),
  shipping_address: z.string().optional(),
  payment_terms: z.string().optional(),
  payment_terms_days: z.coerce.number().min(0).default(14),
  credit_limit: z.coerce.number().min(0).default(0),
  opening_balance: z.coerce.number().default(0),
});

export const paymentSchema = z.object({
  payment_date: z.string().min(1, 'Payment date is required'),
  amount: z.string().refine(
    val => !isNaN(parseFloat(val)) && parseFloat(val) > 0,
    'Amount must be greater than 0'
  ),
  payment_method: z.string().min(1, 'Payment method is required'),
  reference_no: z.string().optional(),
  notes: z.string().optional(),
});

export const editPaymentSchema = z.object({
  payment_date: z.string().min(1, 'Payment date is required'),
  payment_method: z.string().min(1, 'Payment method is required'),
  reference_no: z.string().optional(),
  notes: z.string().optional(),
});

// ── Inventory ─────────────────────────────────────────────────────
export const itemSchema = z.object({
  item_code: z.string().min(1, 'Item code is required'),
  item_name: z.string().min(1, 'Item name is required'),
  description: z.string().optional(),
  category: z.string().optional(),
  unit_of_measure: z.string().min(1, 'Unit of measure is required'),
  reorder_level: z.coerce.number().min(0).default(0),
  standard_cost: z.coerce.number().min(0).default(0),
  standard_selling_price: z.coerce.number().min(0).default(0),
  is_raw_material: z.union([z.boolean(), z.number()]).transform(v => Boolean(v)).default(false),
  is_finished_good: z.union([z.boolean(), z.number()]).transform(v => Boolean(v)).default(false),
  is_purchased: z.union([z.boolean(), z.number()]).transform(v => Boolean(v)).default(true),
  is_manufactured: z.union([z.boolean(), z.number()]).transform(v => Boolean(v)).default(false),
  sale_type: z.enum(['packed', 'loose']).default('packed'),
  qty_decimal_precision: z.coerce.number().int().min(0).max(6).default(0),
  rounding_step: z.coerce.number().positive().nullable().default(null),
});

export const warehouseSchema = z.object({
  warehouse_code: z.string().min(1, 'Warehouse code is required'),
  warehouse_name: z.string().min(1, 'Warehouse name is required'),
  location: z.string().optional(),
});

export const stockMovementSchema = z.object({
  from_warehouse_id: z.union([z.string(), z.number()]).optional(),
  to_warehouse_id: z.union([z.string(), z.number()]).optional(),
  movement_date: z.string().min(1, 'Movement date is required'),
  remarks: z.string().optional(),
});

export const stockMovementLineSchema = z.object({
  item_id: z.string().min(1, 'Item is required'),
  quantity: z.coerce.number().refine(val => val !== 0, 'Quantity is required'),
});

// ── Suppliers ─────────────────────────────────────────────────────
export const supplierSchema = z.object({
  supplier_code: z.string().min(1, 'Supplier code is required'),
  supplier_name: z.string().min(1, 'Supplier name is required'),
  contact_person: z.string().optional(),
  email: z.string().email('Invalid email format').or(z.literal('')).optional(),
  phone: z.string().optional(),
  address: z.string().optional(),
  payment_terms: z.string().optional(),
  is_active: z.number().default(1),
});

// ── Purchases ─────────────────────────────────────────────────────
export const purchaseSchema = z.object({
  item_id: z.coerce.number().positive('Item is required'),
  warehouse_id: z.coerce.number().positive('Warehouse is required'),
  quantity: z.coerce.number().positive('Quantity must be greater than 0'),
  unit_cost: z.coerce.number().positive('Unit cost must be greater than 0'),
  supplier_name: z.string().optional(),
  purchase_date: z.string().min(1, 'Purchase date is required'),
  invoice_no: z.string().optional(),
  remarks: z.string().optional(),
});

export const purchaseOrderItemSchema = z.object({
  item_id: z.coerce.number().positive('Item is required'),
  quantity: z.coerce.number().positive('Quantity must be greater than 0'),
  unit_price: z.coerce.number().min(0, 'Unit price is required'),
});

export const purchaseOrderSchema = z.object({
  supplier_id: z.coerce.number().positive('Supplier is required'),
  po_date: z.string().min(1, 'PO date is required'),
  expected_delivery_date: z.string().optional(),
  warehouse_id: z.coerce.number().optional().nullable(),
  status: z.string().min(1, 'Status is required'),
  notes: z.string().optional(),
  items: z.array(purchaseOrderItemSchema).min(1, 'At least one item is required'),
});

// ── BOM ───────────────────────────────────────────────────────────
export const bomSchema = z.object({
  bom_name: z.string().min(1, 'BOM name is required'),
  finished_item_id: z.union([z.string(), z.number()]).refine(
    val => val !== '' && val !== null && val !== undefined && val !== 0,
    'Finished product is required'
  ),
  quantity: z.coerce.number().positive('Quantity must be greater than 0').default(1),
  description: z.string().optional(),
});

export const bomItemSchema = z.object({
  item_id: z.string().min(1, 'Item is required'),
  quantity: z.string().refine(
    val => !isNaN(parseFloat(val)) && parseFloat(val) > 0,
    'Quantity must be greater than 0'
  ),
});

// ── Production ────────────────────────────────────────────────────
export const productionSchema = z.object({
  output_item_id: z.union([z.string(), z.number()]).transform(val => String(val)).refine(val => val && val !== '', 'Output product is required'),
  output_quantity: z.union([z.string(), z.number()]).transform(val => String(val)).refine(
    val => !isNaN(parseFloat(val)) && parseFloat(val) > 0,
    'Output quantity must be greater than 0'
  ),
  warehouse_id: z.union([z.string(), z.number()]).transform(val => String(val)).refine(val => val && val !== '', 'Finished goods warehouse is required'),
  raw_materials_warehouse_id: z.union([z.string(), z.number()]).optional(),
  production_date: z.string().min(1, 'Production date is required'),
  remarks: z.string().optional(),
});

// ── Expenses ──────────────────────────────────────────────────────
export const expenseSchema = z.object({
  expense_category: z.string().min(1, 'Expense category is required'),
  description: z.string().optional(),
  amount: z.string().refine(
    val => !isNaN(parseFloat(val)) && parseFloat(val) > 0,
    'Amount must be greater than 0'
  ),
  expense_date: z.string().min(1, 'Expense date is required'),
  payment_method: z.string().optional(),
  reference_no: z.string().optional(),
  vendor_name: z.string().optional(),
  project: z.string().optional(),
  status: z.string().default('Approved'),
});

// ── Invoice ───────────────────────────────────────────────────────
export const invoiceItemSchema = z.object({
  item_id: z.coerce.number().positive('Item is required'),
  quantity: z.coerce.number().positive('Quantity must be greater than 0'),
  rate: z.coerce.number().min(0, 'Rate must be 0 or greater'),
  description: z.string().optional(),
  tax: z.coerce.number().min(0).default(0),
  discount_type: z.enum(['none', 'percent', 'fixed', 'flat']).optional(),
  discount_value: z.coerce.number().min(0).default(0),
});

export const invoiceSchema = z.object({
  customer_id: z.coerce.number().positive('Customer is required'),
  invoice_date: z.string().min(1, 'Invoice date is required'),
  due_date: z.string().optional(),
  notes: z.string().optional(),
  terms: z.string().optional(),
  discount_type: z.enum(['none', 'percent', 'fixed', 'flat']).optional(),
  discount_value: z.coerce.number().min(0).default(0),
  items: z.array(invoiceItemSchema).min(1, 'At least one item is required'),
});

export const invoiceReturnItemSchema = z.object({
  return_quantity: z.coerce.number()
    .positive('Return quantity must be greater than 0')
    .min(0.001, 'Return quantity must be greater than 0'),
});

// ── Purchase Returns ──────────────────────────────────────────────
export const purchaseReturnSchema = z.object({
  quantity: z.coerce.number()
    .positive('Return quantity must be greater than 0'),
  reason: z.string().optional(),
});

export const purchaseReturnItemSchema = z.object({
  po_item_id: z.coerce.number().positive('PO item is required'),
  return_quantity: z.coerce.number()
    .positive('Return quantity must be greater than 0'),
});

export const purchaseReturnBatchSchema = z.object({
  items: z.array(purchaseReturnItemSchema).min(1, 'At least one item must be returned'),
  reason: z.string().optional(),
});

// ── Settings ──────────────────────────────────────────────────────
export const settingsSchema = z.object({
  currency_symbol: z.string().min(1, 'Currency symbol is required'),
  currency_code: z.string().min(1, 'Currency code is required'),
  company_name: z.string().min(1, 'Company name is required'),
  date_format: z.string().min(1, 'Date format is required'),
  decimal_places: z.string().refine(
    val => !isNaN(parseInt(val)) && parseInt(val) >= 0 && parseInt(val) <= 4,
    'Decimal places must be 0-4'
  ),
  tooltip_timeout: z.string().refine(
    val => !isNaN(parseFloat(val)) && parseFloat(val) >= 1 && parseFloat(val) <= 10,
    'Tooltip timeout must be 1-10 seconds'
  ),
});

// ── Type exports ──────────────────────────────────────────────────
export type LoginData = z.infer<typeof loginSchema>;
export type CustomerData = z.infer<typeof customerSchema>;
export type PaymentData = z.infer<typeof paymentSchema>;
export type EditPaymentData = z.infer<typeof editPaymentSchema>;
export type ItemData = z.infer<typeof itemSchema>;
export type WarehouseData = z.infer<typeof warehouseSchema>;
export type SupplierData = z.infer<typeof supplierSchema>;
export type PurchaseData = z.infer<typeof purchaseSchema>;
export type BOMData = z.infer<typeof bomSchema>;
export type ProductionData = z.infer<typeof productionSchema>;
export type ExpenseData = z.infer<typeof expenseSchema>;
export type SettingsData = z.infer<typeof settingsSchema>;
