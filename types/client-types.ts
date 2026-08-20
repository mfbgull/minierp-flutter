import type React from 'react';

// Core entity types for MiniERP

// ============ User/Auth Types ============
export interface User {
  id: number;
  username: string;
  full_name: string;
  email?: string;
  role: string;
  role_id?: number | string;
  is_active: boolean | number;
  created_at?: string;
}

// ============ Customer Types ============
export interface Customer {
  id: number;
  customer_code: string;
  customer_name: string;
  contact_person?: string;
  email?: string;
  phone?: string;
  billing_address?: string;
  shipping_address?: string;
  payment_terms?: string;
  payment_terms_days?: number;
  credit_limit?: number;
  credit_utilization_percent?: number;
  current_balance: number;
  opening_balance?: number;
  is_active?: boolean;
  created_at?: string;
  updated_at?: string;
}

// ============ Item/Inventory Types ============
export interface Item {
  id: number;
  item_code: string;
  item_name: string;
  description?: string;
  category?: string;
  unit_of_measure: string;
  current_stock: number;
  reorder_level?: number;
  standard_selling_price?: number;
  standard_cost?: number;
  standard_price?: number;
  purchase_price?: number;
  is_raw_material?: boolean;
  is_finished_good?: boolean;
  is_purchased?: boolean;
  is_manufactured?: boolean;
  has_expiry?: boolean;
  near_expiry_threshold_days?: number;
  created_at?: string;
  updated_at?: string;
}

// ============ Invoice Types ============
export type InvoiceStatus =
  | 'Draft'
  | 'Sent'
  | 'Unpaid'
  | 'Partially Paid'
  | 'Paid'
  | 'Overdue'
  | 'Cancelled';

export type DiscountType = 'flat' | 'percentage';

export interface Discount {
  type: DiscountType;
  value: number;
}

export interface InvoiceItem {
  id: number;
  item_id: number | string;
  description: string;
  quantity: number;
  rate: number;
  tax: number;
  discount: Discount;
  expiry_date?: string | null;
  is_expired_at_sale?: boolean;
}

export interface InvoicePayment {
  record_payment: boolean;
  payment_date: string;
  payment_amount: number;
  payment_method: string;
  reference_no?: string;
  payment_notes?: string;
}

export interface Invoice {
  id: number;
  invoice_no: string;
  customer_id: number | string;
  customer_name?: string;
  customer_email?: string;
  customer_phone?: string;
  customer_address?: string;
  customer_current_balance?: number;
  customer_credit_limit?: number;
  customer_credit_utilization?: number;
  invoice_date: string;
  due_date?: string;
  total_amount: number;
  paid_amount: number;
  balance_amount: number;
  status: string;
  discountScope?: 'item' | 'invoice';
  discount?: Discount;
  items?: InvoiceItem[];
  notes?: string;
  terms?: string;
  expiry_notes?: string;
  created_by?: number;
  company?: CompanyInfo;
  payment?: InvoicePayment;
  paymentMethods?: PaymentMethod[];
  updated_at?: string;
  source_type?: 'SALES_ORDER' | 'DIRECT' | null;
  so_id?: number;
  so_no?: string;
  quotation_id?: number;
  quotation_no?: string;
  warehouse_id?: number;
  warehouse_code?: string;
  warehouse_name?: string;
}

export interface CompanyInfo {
  name: string;
  email: string;
  phone: string;
  address: string;
  taxId?: string;
}

export interface PaymentMethod {
  id: number;
  method: string;
  amount: number;
  reference_no?: string;
}

// ============ Payment Types ============
export interface Payment {
  id: number;
  payment_no: string;
  customer_id: number;
  customer_name?: string;
  payment_date: string;
  amount: number;
  payment_method: string;
  reference_no?: string;
  notes?: string;
  created_at?: string;
}

// ============ BOM Types ============
export interface BOMItem {
  id?: number;
  item_id: number | string;
  item_code?: string;
  item_name?: string;
  unit_of_measure?: string;
  current_stock?: number;
  quantity: number;
}

export interface BOM {
  id: number;
  bom_no: string;
  bom_name: string;
  finished_item_id: number;
  finished_item_code?: string;
  finished_item_name?: string;
  finished_uom?: string;
  quantity: number;
  description?: string;
  is_active: boolean;
  items: BOMItem[];
  item_count?: number;
  created_at?: string;
  updated_at?: string;
}

// ============ Production Types ============
export interface Production {
  id: number;
  production_no: string;
  bom_id: number;
  bom_name?: string;
  finished_item_id: number;
  finished_item_name?: string;
  quantity_to_produce: number;
  quantity_produced?: number;
  status: 'Pending' | 'In Progress' | 'Completed' | 'Cancelled';
  production_date: string;
  notes?: string;
  created_at?: string;
}

// ============ Price History Types ============
export interface PriceHistory {
  customer_name: string;
  transaction_count: number;
  lowest_price: number;
  highest_price: number;
  avg_price: number;
  last_price: number;
  last_invoice_id?: string;
  invoice_date: string;
}

// ============ API Response Types ============
export interface ApiResponse<T> {
  success: boolean;
  data: T;
  error?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  pageSize: number;
}

// ============ Form/UI Types ============
export interface SelectOption {
  value: string | number;
  label: string;
  subtitle?: string;
}

export interface TableColumn<T> {
  headerName: string;
  field: keyof T | string;
  sortable?: boolean;
  filter?: boolean | string;
  flex?: number;
  minWidth?: number;
  valueFormatter?: (params: { value: unknown; data: T }) => string;
  cellRenderer?: (params: { value: unknown; data: T }) => React.ReactNode;
}

// ============ Supplier Types ============
export interface Supplier {
  id: number;
  supplier_code: string;
  supplier_name: string;
  email?: string;
  phone?: string;
  address?: string;
  contact_person?: string;
  current_balance?: number;
  payment_terms?: string;
  is_active?: number;
  notes?: string;
  created_at?: string;
  updated_at?: string;
}

export interface SupplierFormData {
  supplier_code: string;
  supplier_name: string;
  contact_person: string;
  email: string;
  phone: string;
  address: string;
  payment_terms: string;
  is_active: number;
}

// ============ Warehouse Types ============
export interface Warehouse {
  id: number;
  warehouse_code: string;
  warehouse_name: string;
  name?: string;
  location?: string;
  description?: string;
  is_active?: boolean;
  created_at?: string;
  updated_at?: string;
}

// ============ Quotation Types ============
export type QuotationStatus = 'Draft' | 'Sent' | 'Accepted' | 'Expired' | 'Converted' | 'Rejected';
export type QuotationSourceType = 'DIRECT' | null;

export interface QuotationItem {
  id?: number;
  item_id: number;
  item_code?: string;
  item_name?: string;
  quantity: number;
  unit_price: number;
  discount_type?: 'none' | 'percentage' | 'amount';
  discount_value?: number;
  tax_rate?: number;
  amount: number;
}

export interface Quotation {
  id: number;
  quotation_no: string;
  customer_id: number;
  customer_name?: string;
  quotation_date: string;
  expiry_date?: string;
  status: QuotationStatus;
  source_type?: QuotationSourceType;
  total_amount: number;
  notes?: string;
  terms?: string;
  warehouse_id?: number;
  warehouse_code?: string;
  warehouse_name?: string;
  created_by: number;
  created_by_username?: string;
  created_at: string;
  updated_at: string;
  items?: QuotationItem[];
}

export interface CreateQuotationItemDTO {
  item_id: number;
  quantity: number;
  unit_price: number;
  discount_type?: 'none' | 'percentage' | 'amount';
  discount_value?: number;
  tax_rate?: number;
}

export interface CreateQuotationDTO {
  customer_id: number;
  customer_name?: string;
  quotation_date: string;
  expiry_date?: string;
  status?: QuotationStatus;
  source_type?: QuotationSourceType;
  notes?: string;
  terms?: string;
  warehouse_id?: number;
  items: CreateQuotationItemDTO[];
}

// ============ Sales Order Types ============
export type SalesOrderStatus = 'Draft' | 'Confirmed' | 'Delivered' | 'Invoiced' | 'Completed' | 'Cancelled';
export type SalesOrderSourceType = 'QUOTATION' | 'DIRECT' | null;

export interface SalesOrderItem {
  id?: number;
  item_id: number;
  item_code?: string;
  item_name?: string;
  quantity: number;
  delivered_quantity?: number;
  unit_price: number;
  amount: number;
}

export interface SalesOrder {
  id: number;
  so_no: string;
  customer_id: number;
  customer_name?: string;
  so_date: string;
  delivery_date?: string;
  status: SalesOrderStatus;
  source_type?: SalesOrderSourceType;
  source_id?: number; // quotation_id when source_type is 'QUOTATION'
  total_amount: number;
  notes?: string;
  warehouse_id?: number;
  warehouse_code?: string;
  warehouse_name?: string;
  created_by: number;
  created_by_username?: string;
  created_at: string;
  updated_at: string;
  items?: SalesOrderItem[];
  quotation_no?: string; // Joined field when source_type is 'QUOTATION'
}

export interface CreateSalesOrderItemDTO {
  item_id: number;
  quantity: number;
  unit_price: number;
}

export interface CreateSalesOrderDTO {
  customer_id: number;
  customer_name?: string;
  so_date: string;
  delivery_date?: string;
  status?: SalesOrderStatus;
  source_type?: SalesOrderSourceType;
  source_id?: number;
  notes?: string;
  warehouse_id?: number;
  items: CreateSalesOrderItemDTO[];
}

// ============ Enhanced Invoice Types (with source tracking) ============
export interface InvoiceWithSource extends Invoice {
  so_id?: number;
  so_no?: string;
  source_type?: 'SALES_ORDER' | 'DIRECT' | null;
  quotation_id?: number;
  quotation_no?: string;
  warehouse_id?: number;
  warehouse_code?: string;
  warehouse_name?: string;
}

// ============ Sales Cycle Chain Types ============
export interface SalesCycleChain {
  quotation?: Quotation;
  salesOrder?: SalesOrder;
  invoice?: InvoiceWithSource;
}

// ============ Sales Dashboard Types ============
export interface SalesDashboardSummary {
  quotations: {
    total: number;
    draft: number;
    sent: number;
    pending_conversion: number;
  };
  sales_orders: {
    total: number;
    draft: number;
    confirmed: number;
    pending_invoicing: number;
  };
  invoices: {
    total: number;
    unpaid: number;
    paid: number;
    partially_paid: number;
    total_revenue: number;
    outstanding_receivables: number;
  };
}

// ============ Customer Detail Page Types ============
export interface CustomerFormData {
  customer_name: string;
  contact_person?: string;
  email?: string;
  phone: string;
  billing_address?: string;
  shipping_address?: string;
  payment_terms?: string;
  payment_terms_days: number;
  credit_limit: number;
  opening_balance: number;
}

export interface LedgerEntry {
  id: number;
  transaction_date: string;
  transaction_type: string;
  reference_no: string;
  description: string;
  debit: number;
  credit: number;
  balance: number;
  linked_invoice_no?: string;
}

export interface CustomerMetrics {
  currentBalance: number;
  totalDebit: number;
  totalCredit: number;
  totalInvoiced: number;
  totalPaid: number;
  totalOutstanding: number;
  creditUtilization: number;
  overdueInvoicesCount: number;
  paidInvoicesCount: number;
  unpaidInvoicesCount: number;
  overdueInvoicesItemsCount: number;
  avgDaysToPay: number;
}

export type TabId = 'overview' | 'invoices' | 'payments' | 'ledger' | 'pos';

export interface TabConfig {
  id: TabId;
  label: string;
  icon: React.ComponentType<{ size: number }>;
}

// ============ Customer Detail Component Props ============
export interface CustomerHeaderProps {
  customer: {
    customer_name: string;
    contact_person?: string;
    phone?: string;
  };
  currentBalance: number;
  creditLimit: number;
  creditUtilization: number;
  overdueInvoicesCount: number;
  onBack: () => void;
  onRecordPayment: () => void;
  formatCurrency?: (amount: number) => string;
}

export interface CustomerModalsProps {
  id: string | number | undefined;
  customer: Customer | undefined;
  invoiceToDelete: { invoice_no: string; paid_amount?: number } | null;
  paymentToDelete: { payment_no: string } | null;
  paymentToEdit: Payment | null;
  isPaymentModalOpen: boolean;
  deleteInvoicePending: boolean;
  cancelInvoicePending?: boolean;
  deletePaymentPending: boolean;
  onClosePaymentModal: () => void;
  onCloseInvoiceDelete: () => void;
  onClosePaymentDelete: () => void;
  onClosePaymentEdit: () => void;
  onPaymentSuccess: () => void;
  onConfirmDeleteInvoice: () => void;
  onConfirmDeletePayment: () => void;
  navigate?: (path: string) => void;
}

export interface EditPaymentFormProps {
  payment: Payment;
  onClose: () => void;
  onSuccess: () => void;
}

export interface EditPaymentFormData {
  payment_date: string;
  payment_method: string;
  reference_no: string;
  notes: string;
}

export interface InvoicesTabProps {
  invoices: Invoice[];
  loading: boolean;
  onViewInvoice: (id: number) => void;
  onDeleteInvoice: (invoice: Invoice) => void;
  onCancelInvoice: (invoice: Invoice) => void;
}

 
export interface InvoiceColDef extends Record<string, unknown> {
  headerName?: string;
  field?: string;
  colId?: string;
  filter?: unknown;
  width?: number;
  sortable?: boolean;
  flex?: number;
  cellRenderer?: unknown;
  cellClass?: unknown;
  valueFormatter?: unknown;
}

export interface LedgerTabProps {
  ledger: LedgerEntry[];
  loading: boolean;
  customerName: string;
  formatCurrency: (amount: number | string) => string;
  invoices?: Invoice[];
}

 
export interface LedgerColDef extends Record<string, unknown> {
  headerName?: string;
  field?: string;
  filter?: unknown;
  width?: number;
  sortable?: boolean;
  flex?: number;
  cellRenderer?: unknown;
  valueFormatter?: unknown;
}

export interface OverviewTabProps {
  customer: Customer;
  invoices: Invoice[];
  ledger?: LedgerEntry[];
  payments: Payment[];
  formatCurrency?: (amount: number | string) => string;
}

export interface PaymentsTabProps {
  payments: Payment[];
  loading: boolean;
  onEditPayment: (payment: Payment) => void;
  onDeletePayment: (payment: Payment) => void;
  onPrintReceipt?: (payment: Payment) => void;
  onPrintThermal?: (payment: Payment) => void;
}

 
export interface PaymentColDef extends Record<string, unknown> {
  headerName?: string;
  field?: string;
  colId?: string;
  filter?: unknown;
  width?: number;
  sortable?: boolean;
  flex?: number;
  cellRenderer?: unknown;
  valueFormatter?: unknown;
}

// ============ Stock By Warehouse ============
export interface StockByWarehouse {
  id: number;
  item_id: number;
  item_name: string;
  warehouse_id: number;
  warehouse_name: string;
  quantity: number;
}

// ============ Purchase (list page) ============
export interface Purchase {
  id: number;
  purchase_no: string;
  purchase_date: string;
  item_id: number;
  item_name: string;
  item_code?: string;
  quantity: number;
  unit_cost: number;
  total_cost: number;
  supplier_name?: string;
  warehouse_id?: number;
  warehouse_name?: string;
  unit_of_measure?: string;
  invoice_no?: string;
  remarks?: string;
  status?: string;
}

// ============ Purchase Order Item ============
export interface PurchaseOrderItem {
  id?: number;
  item_id: number;
  item_name: string;
  item_code: string;
  quantity: number;
  unit_of_measure: string;
  unit_price: number;
  unit_cost: number;
  total_cost: number;
  received_quantity?: number;
}

// ============ Employee Types ============
export interface Employee {
  id: number;
  employee_code: string;
  first_name: string;
  last_name: string;
  email?: string;
  phone?: string;
  mobile?: string;
  cnic_no?: string;
  address?: string;
  city?: string;
  state?: string;
  postal_code?: string;
  country?: string;
  date_of_birth?: string;
  gender?: string;
  department?: string;
  designation?: string;
  employment_type?: string;
  date_of_joining?: string;
  date_of_leaving?: string;
  salary: number;
  bank_name?: string;
  bank_account_no?: string;
  bank_iban?: string;
  emergency_contact_name?: string;
  emergency_contact_phone?: string;
  profile_photo?: string;
  notes?: string;
  is_active: number;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
}

export interface EmployeeDocument {
  id: number;
  employee_id: number;
  document_name: string;
  document_type?: string;
  document_number?: string;
  issue_date?: string;
  expiry_date?: string;
  file_path?: string;
  notes?: string;
  created_at?: string;
  updated_at?: string;
}

// ============ Activity Log ============
export interface Activity {
  id: number;
  entity_type: string;
  entity_id: number;
  action: string;
  description: string;
  user_id: number;
  username: string;
  created_at: string;
  metadata?: Record<string, unknown>;
}

// ============ Tax Rate ============
export interface TaxRate {
  id: number;
  tax_name: string;
  tax_rate: number;
  is_active: boolean;
}

// ============ Sales Return ============
export interface SalesReturn {
  id: number;
  return_no: string;
  invoice_id: number;
  invoice_no: string;
  customer_id: number;
  customer_name: string;
  return_date: string;
  total_amount: number;
  reason: string;
  status: string;
}

// ============ API Error ============
export interface ApiError {
  success: false;
  error: string;
  message?: string;
  response?: {
    data?: { error?: string; message?: string };
    status?: number;
  };
}

// ============ Production Order ============
export interface ProductionOrder {
  id: number;
  production_no: string;
  item_id: number;
  item_name: string;
  quantity: number;
  start_date: string;
  end_date?: string;
  status: string;
  notes?: string;
}

export interface WarehouseFormData {
  warehouse_code: string;
  warehouse_name: string;
  location: string;
  description: string;
}

export type SaleType = 'packed' | 'loose';

export interface InventoryItem {
  id: number;
  item_code: string;
  item_name: string;
  description?: string;
  category?: string;
  unit_of_measure: string;
  current_stock: number;
  standard_cost: number;
  standard_selling_price: number;
  reorder_level: number;
  is_raw_material: boolean | number;
  is_finished_good: boolean | number;
  is_purchased: boolean | number;
  is_manufactured: boolean | number;
  warehouse_id?: number;
  warehouse?: string;
  sale_type?: SaleType;
  qty_decimal_precision?: number;
  rounding_step?: number | null;
}

export interface ItemFormData {
  item_code: string;
  item_name: string;
  description: string;
  category: string;
  unit_of_measure: string;
  reorder_level: number;
  standard_cost: number;
  standard_selling_price: number;
  is_raw_material: boolean | number;
  is_finished_good: boolean | number;
  is_purchased: boolean | number;
  is_manufactured: boolean | number;
  sale_type: SaleType;
  qty_decimal_precision: number;
  rounding_step: number | null;
}

export interface ItemStats {
  totalItems: number;
  totalStockValue: number;
  totalStock: number;
  lowStockAlerts: number;
  outOfStock: number;
  categories: number;
  rawMaterials: number;
  finishedGoods: number;
}

export interface StockMovement {
  id: number;
  movement_no: string;
  movement_date: string;
  item_code?: string;
  item_name?: string;
  warehouse_name?: string;
  movement_type: string;
  quantity: number;
  unit_of_measure?: string;
  remarks?: string;
  batch_no?: string;
  unit_cost?: number;
  item_id?: number;
  warehouse_id?: number;
}

export interface StockMovementFormData {
  from_warehouse_id: string;
  to_warehouse_id: string;
  movement_date: string;
  remarks: string;
}

export interface LineItem {
  item_id: string;
  quantity: number;
  available_stock: number;
}

export interface StockBalance {
  item_id: number;
  warehouse_id: number;
  quantity: number;
}

export interface PurchaseFormData {
  item_id: string;
  warehouse_id: string;
  quantity: string;
  unit_cost: string;
  supplier_name: string;
  purchase_date: string;
  invoice_no: string;
  remarks: string;
}

export interface PurchaseStats {
  totalPurchases: number;
  totalValue: number;
  totalQuantity: number;
  uniqueSuppliers: number;
  uniqueItems: number;
  averagePurchaseValue: number;
  largestPurchase: { total_cost: number; purchase_date: string; purchase_no?: string };
  recentPurchases: number;
}

export interface UserFormData {
  username: string;
  email: string;
  full_name: string;
  role_id: string | number;
  is_active: boolean | number;
  password: string;
}

export interface Role {
  id: number;
  role_name: string;
  description?: string;
  is_system_role: boolean | number;
  is_active: boolean | number;
  permission_count?: number;
}

export interface RoleFormData {
  role_name: string;
  description: string;
  is_active: boolean | number;
}

export interface Permission {
  id: number;
  action: string;
  module: string;
  description?: string;
  assigned?: boolean;
}

export interface RolePermissionsData {
  permissionsByModule?: Record<string, Permission[]>;
}

export interface BOMListItem {
  id: number;
  bom_no: string;
  bom_name: string;
  finished_item_id: number;
  finished_item_name: string;
  finished_item_code?: string;
  quantity: number;
  finished_uom: string;
  is_active: boolean | number;
  item_count?: number;
  total_material_cost?: number;
  description?: string;
  items?: BOMItemData[];
  created_at?: string;
  updated_at?: string;
}

export interface BOMItemData {
  id: number;
  item_id?: number;
  item_name: string;
  item_code: string;
  quantity: number;
  unit_of_measure: string;
  standard_cost?: number;
  line_cost?: number;
  current_stock?: number;
}

export interface BOMFormData {
  bom_name: string;
  finished_item_id: string;
  quantity: string | number;
  description: string;
}

export interface BOMItemFormEntry {
  item_id: string;
  quantity: string;
}

export interface BOMStats {
  totalBOMs: number;
  activeBOMs: number;
  uniqueFinishedGoods: number;
}

export interface BOMDetail {
  id: number;
  bom_no: string;
  bom_name: string;
  finished_item_name: string;
  finished_item_code?: string;
  quantity: number;
  finished_uom: string;
  is_active: boolean | number;
  description?: string;
  total_material_cost?: number;
  items: BOMItemData[];
  created_at?: string;
  updated_at?: string;
}

export interface IntegrationConfig {
  enabled: boolean;
}

export interface EmailConfig extends IntegrationConfig {
  apiKey: string;
  fromEmail: string;
  fromName: string;
}

export interface NotificationConfig extends IntegrationConfig {
  apiKey: string;
  accountSid: string;
  phoneNumber: string;
}

export interface WeatherConfig extends IntegrationConfig {
  apiKey: string;
  defaultLocation: string;
}

export interface ValidationConfig extends IntegrationConfig {
  apiKey: string;
}

export interface CurrencyConfig extends IntegrationConfig {
  apiKey: string;
  base: string;
  updateInterval: string;
}

export interface TaxConfig extends IntegrationConfig {
  apiKey: string;
  defaultCountry: string;
  zipCode: string;
}

export interface IntegrationSettings {
  email?: { enabled: boolean; configured: boolean } & Record<string, unknown>;
  notifications?: { enabled: boolean; configured: boolean } & Record<string, unknown>;
  weather?: { enabled: boolean; configured: boolean } & Record<string, unknown>;
  validation?: { enabled: boolean; configured: boolean } & Record<string, unknown>;
  currency?: { enabled: boolean; configured: boolean } & Record<string, unknown>;
  tax?: { enabled: boolean; configured: boolean } & Record<string, unknown>;
}

export type IntegrationService = 'email' | 'notifications' | 'weather' | 'validation' | 'currency' | 'tax';

export interface IntegrationSectionDef {
  service: IntegrationService;
  title: string;
  description: string;
  icon: React.ComponentType<{ size?: number; className?: string }>;
  config: IntegrationConfig;
  testEnabled?: boolean;
  testLabel?: string;
  testPlaceholder?: string;
  fields: IntegrationFieldDef[];
}

export interface IntegrationFieldDef {
  label: string;
  name: string;
  type?: string;
  placeholder?: string;
  helpText?: string;
}

export interface ProductionRecord {
  id: number;
  production_no: string;
  production_date: string;
  output_item_id: number;
  output_item_name: string;
  output_quantity: number;
  output_uom: string;
  finished_goods_warehouse_id: number;
  finished_goods_warehouse_name: string;
  raw_materials_warehouse_id?: number;
  raw_materials_warehouse_name?: string;
  bom_id?: number;
  total_material_cost?: number;
  overhead_cost?: number;
  remarks?: string;
  status?: string;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
  inputs?: ProductionInput[];
}

export interface ProductionInput {
  item_id: number;
  item_name: string;
  quantity: number;
  unit_of_measure: string;
  unit_cost?: number;
}

export interface ProductionStub {
  id: number;
  production_no: string;
  production_date: string;
  output_item_name: string;
  output_quantity: number;
  output_uom: string;
  finished_goods_warehouse_name: string;
  remarks?: string;
}

export interface ProductionFormData {
  output_item_id: string;
  output_quantity: string;
  warehouse_id: string;
  raw_materials_warehouse_id: string;
  production_date: string;
  remarks: string;
  overhead_cost: string;
}

export interface CalculatedInputItem {
  item_id: number | string;
  quantity: number;
}

export interface CostPreview {
  materialCost: number;
  overhead: number;
  totalCost: number;
  costPerUnit: number;
}

export interface ProductionSubmitPayload {
  output_item_id: number;
  output_quantity: number;
  warehouse_id: number;
  raw_materials_warehouse_id: number | null;
  production_date: string;
  bom_id: number | null;
  remarks: string | null;
  overhead_cost: number;
  input_items: Array<{ item_id: number; quantity: number }>;
}

export interface BOMRecord {
  id: number;
  bom_name?: string;
  finished_item_id: number;
  finished_item_name?: string;
  is_active?: boolean;
  items?: Array<{
    item_id: number;
    item_name?: string;
    quantity: number;
  }>;
}

export interface StockItem {
  id: number;
  item_name: string;
  item_code: string;
  current_stock?: number;
  unit_of_measure?: string;
  is_raw_material?: boolean;
  is_finished_good?: boolean;
  standard_cost?: number;
  warehouse_balances?: Array<{
    warehouse_id: number;
    quantity: number;
  }>;
}

export interface InsufficientMaterial {
  name: string;
  available: number;
  required: number;
  uom?: string;
}

export interface ARAgingCustomer {
  customer_id: number;
  customer_name: string;
  customer_code?: string;
  total_outstanding: number;
  current_amount: number;
  days_1_30: number;
  days_31_60: number;
  days_61_90: number;
  days_over_90: number;
}

export interface ARAgingSummary {
  totalReceivables?: number;
  current_amount?: number;
  total_1_30?: number;
  total_31_60?: number;
  total_61_90?: number;
  total_over_90?: number;
}

export interface ARAgingData {
  agingBuckets: ARAgingCustomer[];
  summary: ARAgingSummary;
}

export interface ReceivablesSummaryData {
  total_invoices: number;
  total_outstanding: number;
  total_paid: number;
  overdue_count: number;
  overdue_amount: number;
  statusBreakdown: {
    unpaid: { count: number };
    partiallyPaid: { count: number };
    overdue: { count: number };
  };
}

export interface TopDebtor {
  customer_id: number;
  customer_name: string;
  customer_code?: string;
  outstanding_balance: number;
  total_invoiced: number;
  invoice_count: number;
}

export interface DSOData {
  dso: number;
  period: { startDate: string; endDate: string };
  totalSales: number;
  totalAR: number;
  avgInvoiceValue: number;
  calculation?: string;
}

export type ReportType = 'aging' | 'summary' | 'topDebtors' | 'dso';

export interface POSItem {
  id: number;
  item_code: string;
  item_name: string;
  current_stock: number;
  unit_of_measure: string;
  standard_selling_price: number;
  is_active: boolean | number;
  is_raw_material: boolean | number;
  is_finished_good: boolean | number;
  is_purchased: boolean | number;
  category?: string;
}

export interface CartItem {
  id: number;
  item_id: number;
  item_code: string;
  item_name: string;
  unit_of_measure: string;
  quantity: number;
  unit_price: number;
  available_stock: number;
  line_total: number;
}

export interface POSWarehouse {
  id: number;
  warehouse_code: string;
  warehouse_name: string;
}

export interface POSPaymentMethod {
  id: number;
  method: string;
  amount: string;
  reference_no: string;
}

export interface Expense {
  id: number;
  expense_no: string;
  expense_category: string;
  description: string;
  amount: number;
  expense_date: string;
  payment_method: string;
  reference_no: string;
  vendor_name: string;
  project: string;
  status: string;
}

export interface ExpenseFormData {
  expense_category: string;
  description: string;
  amount: string;
  expense_date: string;
  payment_method: string;
  reference_no: string;
  vendor_name: string;
  project: string;
  status: string;
}

export interface ExpenseCategory {
  category_name: string;
}

export interface ExpenseStatusOption {
  value: string;
  label: string;
}

export interface ExpensePaymentMethodOption {
  value: string;
  label: string;
}

export interface LowStockItem {
  id: number;
  item_code: string;
  item_name: string;
  current_stock: number;
  reorder_level: number;
  category: string;
}

export interface StockByCategory {
  category: string;
  total_stock: number;
}

export interface DayTotal {
  date: string;
  total: number;
}

export interface DashboardSummary {
  totalItems: number;
  totalStockValue: number;
  totalSalesRevenue: number;
  totalPurchases: number;
  warehouseStockCount: number;
  lowStockItems: LowStockItem[];
  stockByCategory: StockByCategory[];
  salesByDay: DayTotal[];
  purchasesByDay: DayTotal[];
  recentProductions: number;
}

export interface SettingValue {
  value: string;
  description: string;
}

export interface SettingsApiResponse {
  currency_symbol?: SettingValue;
  currency_code?: SettingValue;
  company_name?: SettingValue;
  date_format?: SettingValue;
  decimal_places?: SettingValue;
  tooltip_timeout?: SettingValue;
  [key: string]: SettingValue | undefined;
}

export interface SettingsFormData {
  currency_symbol: string;
  currency_code: string;
  company_name: string;
  date_format: string;
  decimal_places: string;
  tooltip_timeout: string;
}

export interface POSummary {
  total_pos: number;
  total_value: number;
  draft_pos: number;
  submitted_pos: number;
  partially_received_pos: number;
  completed_pos: number;
}

export interface BalanceData {
  balance: number;
}

export interface SupplierTransaction {
  transaction_date: string;
  transaction_type: string;
  reference_no?: string;
  description?: string;
  debit: number;
  credit: number;
  balance: number;
}

export interface SupplierLedger extends SupplierTransaction {
  id: number;
  created_at?: string;
}

export interface SupplierStatementData {
  supplier: {
    id: number;
    supplier_name: string;
  };
  period: {
    fromDate: string | null;
    toDate: string | null;
  };
  openingBalance: number;
  closingBalance: number;
  transactions: SupplierLedger[];
}

export interface SupplierBalanceData {
  supplierId: number;
  supplierName: string;
  currentBalance: number;
}

export interface SupplierPayment extends Omit<Payment, 'customer_id'> {
  supplier_id?: number;
  allocations?: Array<{ id: number; payment_id: number; po_id: number; po_no: string; amount: number }>;
}

export interface POSummary {
  total_pos: number;
  total_value: number;
  draft_pos: number;
  submitted_pos: number;
  partially_received_pos: number;
  completed_pos: number;
}

export interface SupplierHeaderProps {
  supplier: Supplier;
  currentBalance: number;
  onBack: () => void;
  onRecordPayment: () => void;
  formatCurrency?: (amount: number) => string;
}

export interface SupplierModalsProps {
  id: string | number | undefined;
  supplier: Supplier | undefined;
  paymentToDelete: { payment_no: string } | null;
  paymentToEdit: SupplierPayment | null;
  isPaymentModalOpen: boolean;
  deletePaymentPending: boolean;
  onClosePaymentModal: () => void;
  onClosePaymentDelete: () => void;
  onClosePaymentEdit: () => void;
  onPaymentSuccess: () => void;
  onConfirmDeletePayment: () => void;
}

export interface SupplierOverviewTabProps {
  supplier: Supplier;
  poSummary: POSummary | null;
  balanceData: SupplierBalanceData | null;
  formatCurrency?: (amount: number | string) => string;
}

export interface POSTabProps {
  purchaseOrders: PurchaseOrderDetail[];
  loading: boolean;
  onViewPO: (poId: number) => void;
}

export interface SupplierLedgerTabProps {
  ledger: SupplierLedger[];
  loading: boolean;
  supplierName: string;
  formatCurrency: (amount: number | string) => string;
}

export interface SupplierPaymentsTabProps {
  payments: SupplierPayment[];
  loading: boolean;
  onEditPayment: (payment: SupplierPayment) => void;
  onDeletePayment: (payment: SupplierPayment) => void;
  onPrintReceipt?: (payment: SupplierPayment) => void;
  onPrintThermal?: (payment: SupplierPayment) => void;
}

export interface PurchaseOrderDetail {
  id: number;
  po_no: string;
  po_date: string;
  supplier_id: number;
  supplier_name: string;
  warehouse_name?: string;
  total_amount?: number | string;
  balance_amount?: number;
  status: string;
  expected_delivery_date?: string;
  created_by_username?: string;
  notes?: string;
  created_at?: string;
  updated_at?: string;
  items?: PurchaseOrderDetailItem[];
  supplier_address?: string | null;
  supplier_phone?: string | null;
  supplier_email?: string | null;
  warehouse_id?: number;
}

export interface PurchaseOrderDetailItem {
  id: number;
  item_code: string;
  item_name: string;
  description?: string | null;
  quantity: number;
  unit_of_measure: string;
  unit_price: number;
  amount?: number;
  received_quantity?: number;
  returned_quantity?: number;
}

export interface ReceiptItem {
  po_item_id: number;
  received_quantity: number;
}

export interface ReturnItem {
  po_item_id: number;
  return_quantity: number;
}

export interface ReceiptData {
  receipt_date: string;
  warehouse_id: number;
  remarks?: string;
  items: ReceiptItem[];
}

export interface ReturnData {
  items: ReturnItem[];
  reason?: string;
}

export interface PrintPOItem {
  item_name: string | null;
  item_code: string | null;
  description: string | null;
  quantity: number | null;
  unit_price: number | null;
  amount: number | null;
  received_quantity: number | null;
  unit_of_measure: string | null;
}

export interface PODetailWarehouseOption {
  id: number;
  name: string;
}

export interface DateRangeFilter {
  fromDate: string;
  toDate: string;
}

export interface ExportColumn {
  headerName: string;
  field: string;
  width?: number;
  valueFormatter?: (params: { value: unknown; row?: Record<string, unknown> }) => string;
}

export interface ReportsSummary {
  totalItems?: number;
  totalValue?: number;
  totalInvoices?: number;
  totalSales?: number;
  totalItemsSold?: number;
  averageInvoiceValue?: number;
  lowStock?: number;
  inStock?: number;
  outOfStock?: number;
  totalInbound?: number;
  totalOutbound?: number;
  netMovement?: number;
  totalExpenses?: number;
  totalAmount?: number;
  averageAmount?: number;
  totalProductionOrders?: number;
  totalOutput?: number;
  totalCompleted?: number;
  totalScrapped?: number;
  totalCost?: number;
  totalOrders?: number;
  returnCount?: number;
  returnQuantity?: number;
  returnValue?: number;
  averageOrderValue?: number;
}

export interface ChartDataset {
  label: string;
  data: number[];
  backgroundColor: string | string[];
  borderColor?: string | string[];
  borderWidth?: number;
}

export interface ChartData {
  labels: string[];
  datasets: ChartDataset[];
}

export interface QuotationViewItem {
  item_name?: string | null;
  description?: string | null;
  item_code?: string | null;
  quantity?: number | null;
  unit_price?: number | null;
  rate?: number | null;
  tax_rate?: number | null;
  discount_type?: string | null;
  discount_value?: number | null;
  amount?: number | null;
}

export interface QuotationApiItem {
  item_name?: string;
  description?: string;
  item_code?: string;
  quantity?: number;
  unit_price?: number;
  rate?: number;
  tax_rate?: number;
  discount_type?: string;
  discount_value?: number;
  amount?: number;
}

export interface QuotationApiResponse {
  quotation_no?: string;
  status?: string;
  quotation_date?: string;
  expiry_date?: string;
  customer_name?: string;
  customer_address?: string | null;
  customer_phone?: string | null;
  customer_email?: string | null;
  notes?: string | null;
  terms?: string | null;
  total_amount?: number;
  subtotal?: number | null;
  tax_amount?: number | null;
  items?: QuotationApiItem[];
}

export interface QuotationViewSettings {
  [key: string]: { value?: string; description?: string } | undefined;
  company_name?: { value?: string; description?: string };
  company_email?: { value?: string; description?: string };
  company_phone?: { value?: string; description?: string };
  company_address?: { value?: string; description?: string };
  company_tax_id?: { value?: string; description?: string };
}

export interface QuotationList {
  id: number;
  quotation_no: string;
  quotation_date: string;
  customer_name: string;
  expiry_date?: string;
  total_amount: number | string;
  status: string;
}

export interface QuotationTotals {
  count: number;
  total: number;
  draft: number;
  sent: number;
  converted: number;
}

export interface QuotationFormItem {
  id: number;
  item_id: number;
  description: string;
  quantity: number;
  rate: number;
  tax: number;
  discount: {
    type: 'percentage' | 'flat';
    value: number;
  };
}

export interface CustomerOption {
  id?: number;
  customer_name: string;
  customer_code?: string;
  email?: string;
  phone?: string;
}

export interface InventoryItemOption {
  id: number;
  item_name: string;
  item_code: string;
  current_stock: number;
  standard_selling_price?: number;
  is_purchased?: boolean;
  is_raw_material?: boolean;
  is_manufactured?: boolean;
  standard_cost?: number;
  purchase_price?: number;
  sale_type?: SaleType;
  unit_of_measure?: string;
  qty_decimal_precision?: number;
  rounding_step?: number | null;
}

export interface QuotationSubmitData {
  customer_id: number;
  quotation_date: string;
  expiry_date: string;
  status: string;
  notes: string;
  terms: string;
  items: Array<{
    item_id: number;
    description: string;
    quantity: number;
    rate: number;
    tax: number;
    discount_type: string;
    discount_value: number;
  }>;
}

export interface QuotationEditableCellProps {
  value: string | number;
  itemId: number;
  field: string;
  type?: string;
  isLastItem: boolean;
  items: QuotationFormItem[];
  fieldOrder?: readonly string[];
  editingCell: string | null;
  onEditingCell: (cell: string | null) => void;
  onUpdateItem: (itemId: number, field: string, value: string | number) => void;
  onAddNewItem: () => number;
  getNextField: (field: string) => string | undefined;
}

export interface QuotationFormHeaderProps {
  customer: CustomerOption | null;
  customers: CustomerOption[];
  quotationDate: string;
  expiryDate: string;
  status: string;
  company: { name: string; email: string; phone: string };
  totalAmount: number;
  formatCurrency: (amount: number | string) => string;
  isEditMode: boolean;
  isSaving: boolean;
  id?: number;
  children?: React.ReactNode;
  onSelectCustomer: (customer: CustomerOption) => void;
  onUpdateQuotationDate: (date: string) => void;
  onUpdateExpiryDate: (date: string) => void;
  onUpdateStatus: (status: string) => void;
  onSubmit: () => void;
  onCancel: () => void;
}

export interface QuotationItemsTableProps {
  items: QuotationFormItem[];
  editingCell: string | null;
  inventoryItems: InventoryItemOption[];
  formatCurrency: (amount: number | string) => string;
  getCurrencySymbol: () => string;
  notes: string;
  terms: string;
  calculateSubtotal: () => number;
  calculateDiscount: () => number;
  calculateTax: () => number;
  calculateTotal: () => number;
  calculateItemTotal: (item: QuotationFormItem) => number;
  onUpdateItem: (itemId: number, field: string, value: string | number) => void;
  onRemoveItem: (itemId: number) => void;
  onAddNewItem: () => number;
  onUpdateNotes: (notes: string) => void;
  onUpdateTerms: (terms: string) => void;
  onEditingCell: (cell: string | null) => void;
  tableContainerRef: React.RefObject<HTMLDivElement>;
  lastFocusedCellRef: React.MutableRefObject<string>;
}

export interface QuotationMobileWizardProps {
  customer: CustomerOption | null;
  customers: CustomerOption[];
  items: QuotationFormItem[];
  inventoryItems: InventoryItemOption[];
  quotationDate: string;
  expiryDate: string;
  status: string;
  notes: string;
  terms: string;
  currentStep: number;
  isEditMode: boolean;
  isSaving: boolean;
  formatCurrency: (amount: number | string) => string;
  calculateItemTotal: (item: QuotationFormItem) => number;
  calculateSubtotal: () => number;
  calculateDiscount: () => number;
  calculateTax: () => number;
  calculateTotal: () => number;
  onSelectCustomer: (customer: CustomerOption) => void;
  onUpdateQuotationDate: (date: string) => void;
  onUpdateExpiryDate: (date: string) => void;
  onUpdateStatus: (status: string) => void;
  onUpdateNotes: (notes: string) => void;
  onUpdateTerms: (terms: string) => void;
  onAddItem: (item: QuotationFormItem) => void;
  onRemoveItem: (itemId: number) => void;
  onStepChange: (step: number) => void;
  onSubmit: () => void;
  onCancel: () => void;
}

export interface PurchaseOrder {
  id: number;
  po_no: string;
  po_date: string;
  supplier_id: number;
  supplier_name: string;
  warehouse_name?: string;
  total_amount?: number | string;
  balance_amount?: number;
  status: string;
  expected_delivery_date?: string;
  created_by_username?: string;
  notes?: string;
  created_at?: string;
  updated_at?: string;
  items?: PurchaseOrderItem[];
}

export interface PurchaseOrderStats {
  total: number;
  draft: number;
  submitted: number;
  partial: number;
  completed: number;
  totalValue: number;
}

export interface SupplierOption {
  id?: number;
  supplier_name: string;
  supplier_code?: string;
  email?: string;
  phone?: string;
}

export interface WarehouseOption {
  id: number | string;
  warehouse_name?: string;
  warehouse_code?: string;
  name?: string;
}

export interface POFormItem {
  id: number;
  item_id?: number | string;
  itemId?: number;
  name: string;
  quantity: number;
  unit_price: number;
}

export interface POSubmitData {
  supplier_id: number | undefined;
  po_date: string;
  expected_delivery_date: string;
  warehouse_id: number | string | undefined;
  status: string;
  notes: string;
  items: Array<{
    item_id: number;
    quantity: number;
    unit_price: number;
  }>;
}

export interface POEditableCellProps {
  value: string | number;
  itemId: number;
  field: string;
  type?: string;
  isLastItem: boolean;
  items: POFormItem[];
  fieldOrder?: readonly string[];
  editingCell: string | null;
  onEditingCell: (cell: string | null) => void;
  onUpdateItem: (itemId: number, field: string, value: string | number) => void;
  onAddNewItem: () => number;
  getNextField: (field: string) => string | undefined;
}

export interface POFormHeaderProps {
  supplier: SupplierOption | null;
  suppliers: SupplierOption[];
  poDate: string;
  deliveryDate: string;
  status: string;
  warehouseId: string;
  warehouses: WarehouseOption[];
  company: { name: string; email: string; phone: string };
  totalAmount: number;
  formatCurrency: (amount: number | string) => string;
  isEditMode: boolean;
  isSaving: boolean;
  id?: number;
  children?: React.ReactNode;
  onSelectSupplier: (supplier: SupplierOption) => void;
  onUpdatePoDate: (date: string) => void;
  onUpdateDeliveryDate: (date: string) => void;
  onUpdateStatus: (status: string) => void;
  onUpdateWarehouse: (warehouseId: string) => void;
  onSubmit: () => void;
  onCancel: () => void;
}

export interface POItemsTableProps {
  items: POFormItem[];
  editingCell: string | null;
  inventoryItems: InventoryItemOption[];
  formatCurrency: (amount: number | string) => string;
  notes: string;
  calculateSubtotal: () => number;
  calculateTotal: () => number;
  calculateItemTotal: (item: POFormItem) => number;
  onUpdateItem: (itemId: number, field: string, value: string | number) => void;
  onRemoveItem: (itemId: number) => void;
  onAddNewItem: () => number;
  onUpdateNotes: (notes: string) => void;
  onEditingCell: (cell: string | null) => void;
  tableContainerRef: React.RefObject<HTMLDivElement>;
  lastFocusedCellRef: React.MutableRefObject<string>;
}

export interface POMobileFormProps {
  supplier: SupplierOption | null;
  suppliers: SupplierOption[];
  items: POFormItem[];
  inventoryItems: InventoryItemOption[];
  poDate: string;
  deliveryDate: string;
  status: string;
  warehouseId: string;
  warehouses: WarehouseOption[];
  notes: string;
  isEditMode: boolean;
  isSaving: boolean;
  formatCurrency: (amount: number | string) => string;
  calculateItemTotal: (item: POFormItem) => number;
  calculateSubtotal: () => number;
  calculateTotal: () => number;
  onSelectSupplier: (supplier: SupplierOption) => void;
  onUpdatePoDate: (date: string) => void;
  onUpdateDeliveryDate: (date: string) => void;
  onUpdateStatus: (status: string) => void;
  onUpdateWarehouse: (warehouseId: string) => void;
  onUpdateNotes: (notes: string) => void;
  onUpdateItem: (itemId: number, field: string, value: string | number) => void;
  onAddNewItem: () => number;
  onRemoveItem: (itemId: number) => void;
  onSubmit: () => void;
  onCancel: () => void;
}

export interface InvoiceFormItem {
  id: number;
  item_id: number | string;
  description: string;
  quantity: number;
  rate: number;
  tax: number;
  discount: Discount;
}

export interface InvoiceCompany {
  name: string;
  email: string;
  phone: string;
  address: string;
  taxId: string;
}

export interface InvoiceFormPayment {
  record_payment: boolean;
  payment_date: string;
  payment_amount: number;
  payment_method: string;
  reference_no: string;
  payment_notes: string;
}

export interface PaymentMethodEntry {
  id: number;
  method: string;
  amount: number;
  reference_no: string;
}

export interface InvoiceFormState {
  invoice_no: string;
  status: InvoiceStatus | string;
  invoice_date: string;
  due_date: string;
  customer_id: number | string;
  customer_name: string;
  customer_email: string;
  customer_phone: string;
  customer_address: string;
  customer_current_balance?: number;
  customer_credit_limit?: number;
  customer_credit_utilization?: number;
  discountScope: 'item' | 'invoice';
  discount: Discount;
  items: InvoiceFormItem[];
  notes: string;
  terms: string;
  created_by: number | null;
  company: InvoiceCompany;
  payment: InvoiceFormPayment;
  paymentMethods: PaymentMethodEntry[];
  id?: number;
  total_amount?: number;
  paid_amount?: number;
  balance_amount?: number;
}

export interface ExistingPayment {
  id: number;
  payment_date: string;
  payment_method: string;
  amount: number;
  reference_no?: string;
  notes?: string;
}

export interface PriceHintState {
  itemId: number | string;
  rowId: number | string;
  currentPrice: number;
  history: PriceHistory;
}

export interface InvoiceFormHeaderProps {
  invoice: InvoiceFormState;
  customers: Array<{ id: number; customer_name: string; customer_code?: string; email?: string; phone?: string; billing_address?: string; credit_limit?: number }>;
  customersLoading: boolean;
  customersError: boolean;
  errors: Record<string, string>;
  mutationPending: boolean;
  invoiceId: string | undefined;
  onCustomerSelect: (customer: { id: number; customer_name: string; email?: string; phone?: string; billing_address?: string; credit_limit?: number }) => Promise<void>;
  onUpdateInvoice: (updates: Partial<InvoiceFormState>) => void;
  onSubmit: (e: React.FormEvent) => void;
  onBack: () => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  t: (key: string, params?: Record<string, string | number>) => string;
}

export interface SearchableCellProps {
  value: string;
  itemId: number;
  items: Array<{ id: number; item_name: string; item_code: string; current_stock?: number; standard_selling_price?: number; is_raw_material?: boolean | number; is_finished_good?: boolean | number; is_purchased?: boolean | number }>;
  invoiceItems: InvoiceFormItem[];
  isLastItem: boolean;
  editingCell: string | null;
  onSetEditingCell: (cellId: string | null, options?: { focusNextField?: string; focusRowId?: number }) => void;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onAddNewItem: () => number;
  onSetPendingFocus: (itemId: number) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  getNextField: (field: string) => string | undefined;
  setInvoice?: React.Dispatch<React.SetStateAction<InvoiceFormState>>;
}

export interface EditableCellProps {
  value: string | number;
  displayValue?: string | number;
  itemId: number;
  field: string;
  type?: string;
  isLastItem: boolean;
  editingCell: string | null;
  items: InvoiceFormItem[];
  fieldOrder: readonly string[];
  onSetEditingCell: (cellId: string | null) => void;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onAddNewItem: () => number;
  onSetPendingFocus: (itemId: number) => void;
  getNextField: (field: string, discountScope?: 'item' | 'invoice') => string | undefined;
}

export interface ItemsTableProps {
  getNextField: (field: string, discountScope?: 'item' | 'invoice') => string | undefined;
  invoice: InvoiceFormState;
  items: Array<{ id: number; item_name: string; item_code: string; current_stock?: number; standard_selling_price?: number; is_raw_material?: boolean | number; is_finished_good?: boolean | number; is_purchased?: boolean | number }>;
  editingCell: string | null;
  errors: Record<string, string>;
  priceHint: PriceHintState | null;
  onSetEditingCell: (cellId: string | null, options?: { focusNextField?: string; focusRowId?: number }) => void;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onRemoveItem: (id: number) => void;
  onAddNewItem: () => number;
  onSetPendingFocus: (itemId: number) => void;
  onSetPriceHint: (hint: PriceHintState | null) => void;
  onUpdateInvoice: (updates: Partial<InvoiceFormState>) => void;
  onSetNewItemId: (id: number | null) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  getCurrencySymbol: () => string;
  calculateItemTotal: (item: InvoiceFormItem) => number;
  calculateSubtotal: () => number;
  calculateTax: () => number;
  calculateDiscount: () => number;
  calculateTotal: () => number;
}

export interface PaymentPanelProps {
  invoice: InvoiceFormState;
  invoiceId: string | undefined;
  existingPayments: ExistingPayment[];
  deletedPayments: number[];
  showNewPaymentForm: boolean;
  paymentMutationPending: boolean;
  editingPayment: ExistingPayment | null;
  onUpdateInvoice: (updates: Partial<InvoiceFormState>) => void;
  onAddPaymentMethod: () => void;
  onRemovePaymentMethod: (id: number) => void;
  onUpdatePaymentMethod: (id: number, field: string, value: string) => void;
  onRecordPayment: () => void;
  onSetShowNewPaymentForm: (show: boolean) => void;
  onEditPayment: (payment: ExistingPayment) => void;
  onDeletePayment: (paymentId: number) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  getCurrencySymbol: () => string;
  calculateTotal: () => number;
  t: (key: string, params?: Record<string, string | number>) => string;
}

export interface ExistingPaymentsTableProps {
  existingPayments: ExistingPayment[];
  deletedPayments: number[];
  onEditPayment: (payment: ExistingPayment) => void;
  onDeletePayment: (paymentId: number) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
}

export const INVOICE_STATUSES = ['Draft', 'Sent', 'Unpaid', 'Partially Paid', 'Paid', 'Overdue', 'Cancelled'] as const;
export type InvoiceStatusConst = typeof INVOICE_STATUSES[number];

export const DISCOUNT_TYPES = ['flat', 'percentage'] as const;

export const PAYMENT_METHOD_OPTIONS = ['Cash', 'Check', 'Bank Transfer', 'Credit Card', 'Online Payment'] as const;
export type PaymentMethodOption = typeof PAYMENT_METHOD_OPTIONS[number];

export interface InvoiceFormItem {
  id: number;
  item_id: number | string;
  description: string;
  quantity: number;
  rate: number;
  tax: number;
  discount: Discount;
  /** 'packed' (qty drives amount) or 'loose' (bidirectional). Defaults to packed. */
  sale_type?: SaleType;
  /** Explicit line amount — authoritative only for loose amount-driven lines. */
  amount?: number;
  /** Which field the user last edited, driving loose recalculation. */
  lastEditedField?: 'quantity' | 'amount' | null;
  qty_decimal_precision?: number;
  rounding_step?: number | null;
  /** Unit of measurement for the item (e.g. 'pcs', 'kg', 'box'). */
  unit_of_measure?: string;
}

export interface InvoiceCompany {
  name: string;
  email: string;
  phone: string;
  address: string;
  taxId: string;
}

export interface InvoiceFormPayment {
  record_payment: boolean;
  payment_date: string;
  payment_amount: number;
  payment_method: string;
  reference_no: string;
  payment_notes: string;
}

export interface PaymentMethodEntry {
  id: number;
  method: string;
  amount: number;
  reference_no: string;
}

export interface InvoiceFormState {
  invoice_no: string;
  status: InvoiceStatus | string;
  invoice_date: string;
  due_date: string;
  customer_id: number | string;
  customer_name: string;
  customer_email: string;
  customer_phone: string;
  customer_address: string;
  customer_current_balance?: number;
  customer_credit_limit?: number;
  customer_credit_utilization?: number;
  discountScope: 'item' | 'invoice';
  discount: Discount;
  items: InvoiceFormItem[];
  notes: string;
  terms: string;
  created_by: number | null;
  company: InvoiceCompany;
  payment: InvoiceFormPayment;
  paymentMethods: PaymentMethodEntry[];
  id?: number;
  total_amount?: number;
  paid_amount?: number;
  balance_amount?: number;
}

export interface ExistingPayment {
  id: number;
  payment_date: string;
  payment_method: string;
  amount: number;
  reference_no?: string;
  notes?: string;
}

export interface PriceHintState {
  itemId: number | string;
  rowId: number | string;
  currentPrice: number;
  history: PriceHistory;
}

export interface InvoiceFormHeaderProps {
  invoice: InvoiceFormState;
  customers: Array<{ id: number; customer_name: string; customer_code?: string; email?: string; phone?: string; billing_address?: string; credit_limit?: number }>;
  customersLoading: boolean;
  customersError: boolean;
  errors: Record<string, string>;
  mutationPending: boolean;
  invoiceId: string | undefined;
  onCustomerSelect: (customer: { id: number; customer_name: string; email?: string; phone?: string; billing_address?: string; credit_limit?: number }) => Promise<void>;
  onUpdateInvoice: (updates: Partial<InvoiceFormState>) => void;
  onSubmit: (e: React.FormEvent) => void;
  onBack: () => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  t: (key: string, params?: Record<string, string | number>) => string;
}

export interface SearchableCellProps {
  value: string;
  itemId: number;
  items: Array<{ id: number; item_name: string; item_code: string; current_stock?: number; standard_selling_price?: number; is_raw_material?: boolean | number; is_finished_good?: boolean | number; is_purchased?: boolean | number }>;
  invoiceItems: InvoiceFormItem[];
  isLastItem: boolean;
  editingCell: string | null;
  onSetEditingCell: (cellId: string | null, options?: { focusNextField?: string; focusRowId?: number }) => void;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onAddNewItem: () => number;
  onSetPendingFocus: (itemId: number) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  getNextField: (field: string) => string | undefined;
  setInvoice?: React.Dispatch<React.SetStateAction<InvoiceFormState>>;
}

export interface EditableCellProps {
  value: string | number;
  displayValue?: string | number;
  itemId: number;
  field: string;
  type?: string;
  isLastItem: boolean;
  editingCell: string | null;
  items: InvoiceFormItem[];
  fieldOrder: readonly string[];
  onSetEditingCell: (cellId: string | null) => void;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onAddNewItem: () => number;
  onSetPendingFocus: (itemId: number) => void;
  getNextField: (field: string, discountScope?: 'item' | 'invoice') => string | undefined;
}

export interface ItemsTableProps {
  getNextField: (field: string, discountScope?: 'item' | 'invoice') => string | undefined;
  invoice: InvoiceFormState;
  items: Array<{ id: number; item_name: string; item_code: string; current_stock?: number; standard_selling_price?: number; is_raw_material?: boolean | number; is_finished_good?: boolean | number; is_purchased?: boolean | number }>;
  editingCell: string | null;
  errors: Record<string, string>;
  priceHint: PriceHintState | null;
  onSetEditingCell: (cellId: string | null, options?: { focusNextField?: string; focusRowId?: number }) => void;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onRemoveItem: (id: number) => void;
  onAddNewItem: () => number;
  onSetPendingFocus: (itemId: number) => void;
  onSetPriceHint: (hint: PriceHintState | null) => void;
  onUpdateInvoice: (updates: Partial<InvoiceFormState>) => void;
  onSetNewItemId: (id: number | null) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  getCurrencySymbol: () => string;
  calculateItemTotal: (item: InvoiceFormItem) => number;
  calculateSubtotal: () => number;
  calculateTax: () => number;
  calculateDiscount: () => number;
  calculateTotal: () => number;
}

export interface PaymentPanelProps {
  invoice: InvoiceFormState;
  invoiceId: string | undefined;
  existingPayments: ExistingPayment[];
  deletedPayments: number[];
  showNewPaymentForm: boolean;
  paymentMutationPending: boolean;
  editingPayment: ExistingPayment | null;
  onUpdateInvoice: (updates: Partial<InvoiceFormState>) => void;
  onAddPaymentMethod: () => void;
  onRemovePaymentMethod: (id: number) => void;
  onUpdatePaymentMethod: (id: number, field: string, value: string) => void;
  onRecordPayment: () => void;
  onSetShowNewPaymentForm: (show: boolean) => void;
  onEditPayment: (payment: ExistingPayment) => void;
  onDeletePayment: (paymentId: number) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  getCurrencySymbol: () => string;
  calculateTotal: () => number;
  t: (key: string, params?: Record<string, string | number>) => string;
}

export interface ExistingPaymentsTableProps {
  existingPayments: ExistingPayment[];
  deletedPayments: number[];
  onEditPayment: (payment: ExistingPayment) => void;
  onDeletePayment: (paymentId: number) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
}

export interface InvoiceSubmitItem {
  item_id: number | string;
  description: string;
  quantity: number;
  unit_price: number;
  tax_rate: number;
  discount_type: string;
  discount_value: number;
}

export interface InvoiceSubmitData {
  invoice_no: string;
  customer_id: number | string;
  invoice_date: string;
  due_date: string;
  total_amount: number;
  discount_scope: string;
  discount_type: string;
  discount_value: number;
  notes: string;
  terms: string;
  items: InvoiceSubmitItem[];
  status?: string;
  record_payment?: boolean;
  payment?: {
    payment_date: string;
    amount: number;
    payment_method: string;
    reference_no: string;
    notes: string;
  };
  deleted_payments?: number[];
}

export const SO_STATUSES = ['Draft', 'Confirmed', 'Invoiced', 'Completed', 'Cancelled'] as const;
export type SalesOrderStatusConst = typeof SO_STATUSES[number];

export interface SOFormItem {
  id: number;
  item_id: number | string;
  name: string;
  quantity: number;
  unitPrice: number;
  taxRate: number;
  discount: Discount;
}

export interface SOCompany {
  name: string;
  email: string;
  phone: string;
  address: string;
}

export interface SelectedCustomer {
  id: number;
  customer_name: string;
  email?: string;
  phone?: string;
  billing_address?: string;
}

export interface SOFormHeaderProps {
  customer: SelectedCustomer | null;
  soDate: string;
  deliveryDate: string;
  status: string;
  warehouseId: string;
  customers: Array<{ id: number; customer_name: string; customer_code?: string; email?: string; phone?: string }>;
  warehouses: Array<{ id: number; warehouse_name?: string; name?: string }>;
  company: SOCompany;
  mutationPending: boolean;
  id: string | undefined;
  formatCurrency: (amount: number | string | null | undefined) => string;
  calculateTotal: () => number;
  onSelectCustomer: (customer: SelectedCustomer) => void;
  onSetSoDate: (date: string) => void;
  onSetDeliveryDate: (date: string) => void;
  onSetStatus: (status: string) => void;
  onSetWarehouseId: (id: string) => void;
  onSubmit: (e: React.FormEvent) => void;
  onBack: () => void;
  onPreview?: () => void;
}

export interface SOSearchableCellProps {
  value: string;
  itemId: number;
  inventoryItems: Array<{ id: number; item_name: string; item_code: string; current_stock?: number; standard_selling_price?: number; is_raw_material?: boolean | number; is_finished_good?: boolean | number; is_purchased?: boolean | number }>;
  soItems: SOFormItem[];
  isLastItem: boolean;
  editingCell: string | null;
  onSetEditingCell: (cellId: string | null) => void;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onAddNewItem: () => number;
  onSetPendingFocus: (itemId: number) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  getNextField: (field: string) => string | undefined;
}

export interface SOEditableCellProps {
  value: string | number;
  itemId: number;
  field: string;
  type?: string;
  isLastItem: boolean;
  editingCell: string | null;
  items: SOFormItem[];
  fieldOrder: readonly string[];
  onSetEditingCell: (cellId: string | null) => void;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onAddNewItem: () => number;
  onSetPendingFocus: (itemId: number) => void;
  getNextField: (field: string) => string | undefined;
}

export interface SOItemsTableProps {
  items: SOFormItem[];
  editingCell: string | null;
  inventoryItems: Array<{ id: number; item_name: string; item_code: string; current_stock?: number; standard_selling_price?: number; is_raw_material?: boolean | number; is_finished_good?: boolean | number; is_purchased?: boolean | number }>;
  notes: string;
  onSetNotes: (notes: string) => void;
  onSetEditingCell: (cellId: string | null) => void;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onRemoveItem: (id: number) => void;
  onAddNewItem: () => number;
  onSetPendingFocus: (itemId: number) => void;
  onSetNewItemId: (id: number | null) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  getCurrencySymbol: () => string;
  calculateItemTotal: (item: SOFormItem) => number;
  calculateSubtotal: () => number;
  calculateDiscount: () => number;
  calculateTax: () => number;
  calculateTotal: () => number;
  getNextField: (field: string, discountScope?: 'item' | 'invoice') => string | undefined;
}

export interface SOMobileWizardProps {
  customer: SelectedCustomer | null;
  soDate: string;
  deliveryDate: string;
  status: string;
  warehouseId: string;
  notes: string;
  items: SOFormItem[];
  currentStep: number;
  customers: Array<{ id: number; customer_name: string; customer_code?: string; email?: string; phone?: string }>;
  warehouses: Array<{ id: number; warehouse_name?: string; name?: string }>;
  inventoryItems: Array<{ id: number; item_name: string; item_code: string; current_stock?: number; standard_selling_price?: number }>;
  mutationPending: boolean;
  id: string | undefined;
  formatCurrency: (amount: number | string | null | undefined) => string;
  calculateItemTotal: (item: SOFormItem) => number;
  calculateSubtotal: () => number;
  calculateDiscount: () => number;
  calculateTax: () => number;
  calculateTotal: () => number;
  onSelectCustomer: (customer: SelectedCustomer) => void;
  onSetSoDate: (date: string) => void;
  onSetDeliveryDate: (date: string) => void;
  onSetStatus: (status: string) => void;
  onSetWarehouseId: (id: string) => void;
  onSetNotes: (notes: string) => void;
  onSetCurrentStep: (step: number) => void;
  onAddItem: (item: SOFormItem) => void;
  onRemoveItem: (id: number) => void;
  onSubmit: () => void;
}

export interface SOSubmitItem {
  item_id: number | string;
  description: string;
  quantity: number;
  unit_price: number;
  tax_rate: number;
  discount_type: string;
  discount_value: number;
}

export interface SOSubmitData {
  customer_id: number;
  customer_name: string;
  so_date: string;
  delivery_date?: string;
  status: string;
  notes: string;
  warehouse_id?: string;
  total_amount: number;
  items: SOSubmitItem[];
}
