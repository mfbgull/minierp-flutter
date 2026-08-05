import Database from 'better-sqlite3';
import { generateDocNo } from '../utils/sequence';
import { QuotationWithWarehouse, InvoiceWithUsername } from '../types';
import InvoiceModel from './Invoice';

export interface SalesOrder {
  id: number;
  so_no: string;
  customer_id: number;
  customer_name?: string;
  so_date: string;
  delivery_date?: string;
  status: 'Draft' | 'Confirmed' | 'Delivered' | 'Invoiced' | 'Completed' | 'Cancelled';
  source_type?: 'QUOTATION' | 'DIRECT' | null;
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

export interface SalesOrderItem {
  id: number;
  so_id: number;
  item_id: number;
  item_code: string;
  item_name: string;
  quantity: number;
  delivered_quantity: number;
  unit_price: number;
  amount: number;
}

export interface CreateSalesOrderDTO {
  customer_id: number;
  customer_name?: string;
  so_date: string;
  delivery_date?: string;
  status?: 'Draft' | 'Confirmed' | 'Delivered' | 'Invoiced' | 'Completed' | 'Cancelled';
  source_type?: 'QUOTATION' | 'DIRECT' | null;
  source_id?: number;
  notes?: string;
  warehouse_id?: number;
  items: CreateSalesOrderItemDTO[];
}

export interface CreateSalesOrderItemDTO {
  item_id: number;
  quantity: number;
  unit_price: number;
}

export interface UpdateSalesOrderDTO {
  customer_id?: number;
  customer_name?: string;
  so_date?: string;
  delivery_date?: string;
  status?: 'Draft' | 'Confirmed' | 'Delivered' | 'Invoiced' | 'Completed' | 'Cancelled';
  notes?: string;
  warehouse_id?: number;
  items?: CreateSalesOrderItemDTO[];
}

export interface SalesOrderFilters {
  status?: string;
  customer_id?: number;
  customer_name?: string;
  start_date?: string;
  end_date?: string;
  warehouse_id?: number;
  source_type?: string;
  limit?: number;
}

class SalesOrderModel {
  /**
   * Create a new sales order with items
   */
  static create(data: CreateSalesOrderDTO, userId: number, db: Database.Database): SalesOrder {
    const { customer_id, customer_name, so_date, delivery_date, status, source_type, source_id, notes, warehouse_id, items } = data;

    const transaction = db.transaction(() => {
      // Validate customer exists
      const customer = db.prepare('SELECT id, customer_name FROM customers WHERE id = ? AND is_active = 1').get(customer_id) as { id: number; customer_name: string } | undefined;
      if (!customer) {
        throw new Error('Customer not found or inactive');
      }

      // Validate warehouse if provided
      if (warehouse_id) {
        const warehouse = db.prepare('SELECT id FROM warehouses WHERE id = ? AND is_active = 1').get(warehouse_id);
        if (!warehouse) {
          throw new Error('Warehouse not found or inactive');
        }
      }

      // Validate source if provided
      if (source_type === 'QUOTATION' && source_id) {
        const quotation = db.prepare('SELECT id, status FROM quotations WHERE id = ?').get(source_id) as { id: number; status: string } | undefined;
        if (!quotation) {
          throw new Error('Source quotation not found');
        }
        if (quotation.status !== 'Accepted' && quotation.status !== 'Sent') {
          throw new Error('Source quotation must be in Accepted or Sent status');
        }
      }

      // Validate items
      if (!items || items.length === 0) {
        throw new Error('Sales order must have at least one item');
      }

      for (const item of items) {
        const dbItem = db.prepare('SELECT id, is_active FROM items WHERE id = ?').get(item.item_id) as { id: number; is_active: number } | undefined;
        if (!dbItem) {
          throw new Error(`Item ${item.item_id} not found`);
        }
        if (!dbItem.is_active) {
          throw new Error(`Item ${item.item_id} is inactive`);
        }
        if (item.quantity <= 0) {
          throw new Error('Item quantity must be positive');
        }
        if (item.unit_price < 0) {
          throw new Error('Item unit price cannot be negative');
        }
      }

      // Generate sales order number
      const soNo = this.generateSalesOrderNo(db);

      // Calculate total amount
      const totalAmount = items.reduce((sum, item) => sum + (item.quantity * item.unit_price), 0);

      // Insert sales order header
      const soStmt = db.prepare(`
        INSERT INTO sales_orders (
          so_no, customer_id, customer_name, so_date, delivery_date,
          status, source_type, source_id, total_amount, notes, warehouse_id, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      const result = soStmt.run(
        soNo,
        customer_id,
        customer_name || customer.customer_name,
        so_date,
        delivery_date || null,
        status || 'Draft',
        source_type || 'DIRECT',
        source_id || null,
        totalAmount,
        notes || null,
        warehouse_id || null,
        userId
      );

      const salesOrderId = result.lastInsertRowid as number;

      // Insert sales order items
      const itemStmt = db.prepare(`
        INSERT INTO sales_order_items (so_id, item_id, quantity, unit_price, amount)
        VALUES (?, ?, ?, ?, ?)
      `);

      for (const item of items) {
        const lineAmount = item.quantity * item.unit_price;

        itemStmt.run(
          salesOrderId,
            item.item_id,
            item.quantity,
          item.unit_price,
          lineAmount
        );
      }

      // Log activity
      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'CREATE',
        'SalesOrder',
        salesOrderId,
        `Created sales order ${soNo} for ${customer_name || customer.customer_name}`
      );

      return this.getById(salesOrderId, db) as SalesOrder;
    });

    return transaction();
  }

  /**
   * Get sales order by ID with items
   */
  static getById(id: number, db: Database.Database): SalesOrder | undefined {
    const salesOrder = db.prepare(`
      SELECT
        so.*,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username,
        q.quotation_no
      FROM sales_orders so
      LEFT JOIN warehouses w ON so.warehouse_id = w.id
      LEFT JOIN users u ON so.created_by = u.id
      LEFT JOIN quotations q ON so.source_id = q.id AND so.source_type = 'QUOTATION'
      WHERE so.id = ?
    `).get(id) as SalesOrder | undefined;

    if (!salesOrder) {
      return undefined;
    }

    // Get items
    const items = db.prepare(`
      SELECT
        soi.id, soi.so_id, soi.item_id,
        i.item_code, i.item_name,
        soi.quantity, soi.delivered_quantity, soi.unit_price, soi.amount
      FROM sales_order_items soi
      LEFT JOIN items i ON soi.item_id = i.id
      WHERE soi.so_id = ?
      ORDER BY soi.id
    `).all(id) as SalesOrderItem[];

    return {
      ...salesOrder,
      items
    };
  }

  /**
   * Get all sales orders with filters
   */
  static getAll(filters: SalesOrderFilters = {}, db: Database.Database): SalesOrder[] {
    let query = `
      SELECT
        so.*,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username,
        q.quotation_no
      FROM sales_orders so
      LEFT JOIN warehouses w ON so.warehouse_id = w.id
      LEFT JOIN users u ON so.created_by = u.id
      LEFT JOIN quotations q ON so.source_id = q.id AND so.source_type = 'QUOTATION'
      WHERE 1=1
    `;

    const params: any[] = [];

    if (filters.status) {
      query += ` AND so.status = ?`;
      params.push(filters.status);
    }

    if (filters.customer_id) {
      query += ` AND so.customer_id = ?`;
      params.push(filters.customer_id);
    }

    if (filters.customer_name) {
      query += ` AND so.customer_name LIKE ?`;
      params.push(`%${filters.customer_name}%`);
    }

    if (filters.start_date) {
      query += ` AND so.so_date >= ?`;
      params.push(filters.start_date);
    }

    if (filters.end_date) {
      query += ` AND so.so_date <= ?`;
      params.push(filters.end_date);
    }

    if (filters.warehouse_id) {
      query += ` AND so.warehouse_id = ?`;
      params.push(filters.warehouse_id);
    }

    if (filters.source_type) {
      query += ` AND so.source_type = ?`;
      params.push(filters.source_type);
    }

    query += ` ORDER BY so.so_date DESC, so.created_at DESC`;

    if (filters.limit) {
      query += ` LIMIT ?`;
      params.push(filters.limit);
    }

    const salesOrders = db.prepare(query).all(...params) as SalesOrder[];

    // Get items for each sales order
    return salesOrders.map(so => {
      const items = db.prepare(`
        SELECT
          soi.id, soi.so_id, soi.item_id,
          i.item_code, i.item_name,
          soi.quantity, soi.delivered_quantity, soi.unit_price, soi.amount
        FROM sales_order_items soi
        LEFT JOIN items i ON soi.item_id = i.id
        WHERE soi.so_id = ?
        ORDER BY soi.id
      `).all(so.id) as SalesOrderItem[];

      return {
        ...so,
        items
      };
    });
  }

  /**
   * Update sales order
   */
  static update(id: number, data: UpdateSalesOrderDTO, userId: number, db: Database.Database): SalesOrder {
    const salesOrder = this.getById(id, db);
    if (!salesOrder) {
      throw new Error('Sales order not found');
    }

    if (salesOrder.status === 'Completed' || salesOrder.status === 'Cancelled') {
      throw new Error(`Cannot update a ${salesOrder.status} sales order`);
    }

    const transaction = db.transaction(() => {
      const { customer_id, customer_name, so_date, delivery_date, status, notes, warehouse_id, items } = data;

      // Validate customer if provided
      if (customer_id) {
        const customer = db.prepare('SELECT id, customer_name FROM customers WHERE id = ? AND is_active = 1').get(customer_id) as { id: number; customer_name: string } | undefined;
        if (!customer) {
          throw new Error('Customer not found or inactive');
        }
      }

      // Validate warehouse if provided
      if (warehouse_id) {
        const warehouse = db.prepare('SELECT id FROM warehouses WHERE id = ? AND is_active = 1').get(warehouse_id);
        if (!warehouse) {
          throw new Error('Warehouse not found or inactive');
        }
      }

      // Update header
      const updateFields: string[] = [];
      const updateParams: any[] = [];

      if (customer_id !== undefined) {
        updateFields.push('customer_id = ?');
        updateParams.push(customer_id);
      }
      if (customer_name !== undefined) {
        updateFields.push('customer_name = ?');
        updateParams.push(customer_name);
      }
      if (so_date !== undefined) {
        updateFields.push('so_date = ?');
        updateParams.push(so_date);
      }
      if (delivery_date !== undefined) {
        updateFields.push('delivery_date = ?');
        updateParams.push(delivery_date);
      }
      if (status !== undefined) {
        updateFields.push('status = ?');
        updateParams.push(status);
      }
      if (notes !== undefined) {
        updateFields.push('notes = ?');
        updateParams.push(notes);
      }
      if (warehouse_id !== undefined) {
        updateFields.push('warehouse_id = ?');
        updateParams.push(warehouse_id);
      }

      updateFields.push('updated_at = CURRENT_TIMESTAMP');
      updateParams.push(id);

      db.prepare(`UPDATE sales_orders SET ${updateFields.join(', ')} WHERE id = ?`).run(...updateParams);

      // Update items if provided
      if (items) {
        // Delete existing items
        db.prepare('DELETE FROM sales_order_items WHERE so_id = ?').run(id);

        // Insert new items
        let totalAmount = 0;
        const itemStmt = db.prepare(`
          INSERT INTO sales_order_items (so_id, item_id, quantity, unit_price, amount)
          VALUES (?, ?, ?, ?, ?)
        `);

        for (const item of items) {
          const lineAmount = item.quantity * item.unit_price;
          totalAmount += lineAmount;

          itemStmt.run(
            id,
            item.item_id,
            item.quantity,
            item.unit_price,
            lineAmount
          );
        }

        // Update total amount
        db.prepare('UPDATE sales_orders SET total_amount = ? WHERE id = ?').run(totalAmount, id);
      }

      // Log activity
      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'UPDATE',
        'SalesOrder',
        id,
        `Updated sales order ${salesOrder.so_no}`
      );

      return this.getById(id, db) as SalesOrder;
    });

    return transaction();
  }

  /**
   * Delete sales order (only allowed for Draft/Confirmed — stock may not have been deducted yet).
   */
  static delete(id: number, userId: number, db: Database.Database): boolean {
    const salesOrder = this.getById(id, db);
    if (!salesOrder) {
      throw new Error('Sales order not found');
    }

    if (salesOrder.status === 'Completed' || salesOrder.status === 'Invoiced') {
      throw new Error(`Cannot delete a ${salesOrder.status} sales order`);
    }

    db.transaction(() => {
      db.prepare('DELETE FROM sales_order_items WHERE so_id = ?').run(id);
      db.prepare('DELETE FROM sales_orders WHERE id = ?').run(id);

      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'DELETE',
        'SalesOrder',
        id,
        `Deleted sales order ${salesOrder.so_no}`
      );
    })();

    return true;
  }

  /**
   * Cancel a sales order, reversing any linked invoice stock.
   * Works for Invoiced/Completed SOs — reverses stock and cancels the linked invoice.
   */
  static cancel(id: number, userId: number, db: Database.Database): { invoiceId?: number; invoiceNo?: string } {
    const salesOrder = this.getById(id, db);
    if (!salesOrder) {
      throw new Error('Sales order not found');
    }

    if (salesOrder.status === 'Cancelled') {
      throw new Error('Sales order is already cancelled');
    }

    let linkedInvoice: { id: number; invoice_no: string; status: string } | undefined;

    const transaction = db.transaction(() => {
      if (salesOrder.status === 'Invoiced' || salesOrder.status === 'Completed') {
        // Find the linked invoice
        linkedInvoice = db.prepare(
          `SELECT id, invoice_no, status FROM invoices WHERE so_id = ?`
        ).get(id) as { id: number; invoice_no: string; status: string } | undefined;

        if (linkedInvoice && linkedInvoice.status !== 'Cancelled') {
          // Get items for stock reversal
          const invoiceItems = InvoiceModel.getInvoiceItemsForStockReverse(db, linkedInvoice.id);

          // Reverse stock — restores batch quantity_remaining and creates ADJUSTMENT movement
          InvoiceModel.reverseStockForItems(
            db,
            invoiceItems,
            linkedInvoice.invoice_no,
            userId,
            'SO_CANCEL'
          );

          // Cancel the invoice
          db.prepare(`
            UPDATE invoices SET status = 'Cancelled', updated_at = CURRENT_TIMESTAMP WHERE id = ?
          `).run(linkedInvoice.id);

          // Log activity for invoice cancellation
          db.prepare(`
            INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
            VALUES (?, ?, ?, ?, ?)
          `).run(
            userId,
            'CANCEL',
            'Invoice',
            linkedInvoice.id,
            `Invoice ${linkedInvoice.invoice_no} cancelled due to Sales Order ${salesOrder.so_no} cancellation`
          );
        }
      }

      // Update SO status
      db.prepare(`UPDATE sales_orders SET status = 'Cancelled', updated_at = CURRENT_TIMESTAMP WHERE id = ?`)
        .run(id);

      // Log activity
      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'CANCEL',
        'SalesOrder',
        id,
        `Cancelled sales order ${salesOrder.so_no}`
      );

      return { invoiceId: linkedInvoice?.id, invoiceNo: linkedInvoice?.invoice_no };
    });

    return transaction();
  }

  /**
   * Convert sales order to invoice
   * This creates an invoice and deducts inventory
   */
  static convertToInvoice(id: number, userId: number, db: Database.Database, invoiceData?: {
    invoice_date?: string;
    due_date?: string;
    notes?: string;
  }): { invoiceId: number; invoiceNo: string } {
    const salesOrder = this.getById(id, db);
    if (!salesOrder) {
      throw new Error('Sales order not found');
    }

    if (salesOrder.status === 'Cancelled') {
      throw new Error('Cannot convert cancelled sales order');
    }

    if (salesOrder.status === 'Invoiced' || salesOrder.status === 'Completed') {
      throw new Error(`Sales order already ${salesOrder.status}`);
    }

    const transaction = db.transaction(() => {
      // Validate stock availability
      for (const item of salesOrder.items || []) {
        const stockBalance = db.prepare(`
          SELECT quantity FROM stock_balances
          WHERE item_id = ? AND warehouse_id = ?
        `).get(item.item_id, salesOrder.warehouse_id) as { quantity: number } | undefined;

        const availableStock = stockBalance ? parseFloat(String(stockBalance.quantity)) : 0;

        if (availableStock < item.quantity) {
          throw new Error(`Insufficient stock for item ${item.item_code}. Available: ${availableStock}, Required: ${item.quantity}`);
        }
      }

      // Generate invoice number
      const invoiceNo = this.generateInvoiceNo(db);

      const invoiceDate = invoiceData?.invoice_date || new Date().toISOString().split('T')[0];

      // Create invoice
      const invoiceStmt = db.prepare(`
        INSERT INTO invoices (
          invoice_no, customer_id, customer_name, so_id, source_type, quotation_id,
          invoice_date, due_date, status, total_amount, paid_amount, balance_amount, notes, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      // Get quotation_id if source is quotation
      let quotationId: number | null = null;
      if (salesOrder.source_type === 'QUOTATION' && salesOrder.source_id) {
        const quotation = db.prepare('SELECT id FROM quotations WHERE id = ?').get(salesOrder.source_id) as { id: number } | undefined;
        quotationId = quotation ? quotation.id : null;
      }

      const result = invoiceStmt.run(
        invoiceNo,
        salesOrder.customer_id,
        salesOrder.customer_name,
        id,
        'SALES_ORDER',
        quotationId,
        invoiceDate,
        invoiceData?.due_date || null,
        'Unpaid',
        salesOrder.total_amount,
        0,
        salesOrder.total_amount,
        invoiceData?.notes || salesOrder.notes || null,
        userId
      );

      const invoiceId = result.lastInsertRowid as number;

       // Create invoice items
       const invoiceItemStmt = db.prepare(`
         INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount)
         VALUES (?, ?, ?, ?, ?)
       `);

       for (const item of salesOrder.items || []) {
         invoiceItemStmt.run(
           invoiceId,
           item.item_id,
           item.quantity,
           item.unit_price,
           item.amount
         );
      }

      // Deduct inventory using FIFO batch consumption
      const movementDate = invoiceDate;
      for (const item of salesOrder.items || []) {
        const effectiveWarehouseId = salesOrder.warehouse_id || 1;
        // FIFO consumption from oldest batches
        const consumption = InvoiceModel.consumeFromOldestBatches(
          item.item_id,
          effectiveWarehouseId,
          item.quantity,
          db
        );

        // Create one stock movement per consumed batch for full traceability
        let totalConsumed = 0;
        for (const entry of consumption) {
          const movementNo = this.generateMovementNo(db);
          const batchLabel = entry.batchId ? `(batch ${entry.batchId})` : '(legacy stock)';
          db.prepare(`
            INSERT INTO stock_movements (
              movement_no, item_id, warehouse_id, movement_type,
              quantity, unit_cost, reference_doctype, reference_docno,
              remarks, movement_date, created_by, batch_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `).run(
            movementNo,
            item.item_id,
            effectiveWarehouseId,
            'SALE',
            -entry.consumed,
            entry.unitCost,
            'Invoice',
            invoiceNo,
            `Invoice ${invoiceNo} from SO ${salesOrder.so_no} ${batchLabel}`,
            movementDate,
            userId,
            entry.batchId
          );
          totalConsumed += entry.consumed;
        }

        // Update stock balance once per item (total consumed)
        db.prepare(`
          UPDATE stock_balances
          SET quantity = quantity + ?,
              last_updated = CURRENT_TIMESTAMP
          WHERE item_id = ? AND warehouse_id = ?
        `).run(-totalConsumed, item.item_id, effectiveWarehouseId);

        // Update item current_stock
        db.prepare(`
          UPDATE items
          SET current_stock = (
            SELECT COALESCE(SUM(quantity), 0)
            FROM stock_balances
            WHERE item_id = ?
          )
          WHERE id = ?
        `).run(item.item_id, item.item_id);
      }

      // Update sales order status
      db.prepare('UPDATE sales_orders SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
        .run('Invoiced', id);

      // Update delivered quantity
      for (const item of salesOrder.items || []) {
        db.prepare(`
          UPDATE sales_order_items
          SET delivered_quantity = quantity
          WHERE so_id = ? AND item_id = ?
        `).run(id, item.item_id);
      }

      // Log activity
      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'CREATE',
        'Invoice',
        invoiceId,
        `Created invoice ${invoiceNo} from sales order ${salesOrder.so_no}`
      );

      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'UPDATE',
        'SalesOrder',
        id,
        `Sales order ${salesOrder.so_no} invoiced as ${invoiceNo}`
      );

      return { invoiceId, invoiceNo };
    });

    return transaction();
  }

  /**
   * Get sales cycle chain (quotation -> SO -> invoice)
   */
  static getSalesCycleChain(salesOrderId: number, db: Database.Database): {
    quotation: any | undefined;
    salesOrder: SalesOrder | undefined;
    invoice: any | undefined;
  } {
    const salesOrder = this.getById(salesOrderId, db);

    let quotation = undefined;
    if (salesOrder?.source_type === 'QUOTATION' && salesOrder.source_id) {
      quotation = db.prepare(`
        SELECT
          q.*,
          w.warehouse_code,
          w.warehouse_name,
          u.username as created_by_username
        FROM quotations q
        LEFT JOIN warehouses w ON q.warehouse_id = w.id
        LEFT JOIN users u ON q.created_by = u.id
        WHERE q.id = ?
       `).get(salesOrder.source_id) as QuotationWithWarehouse | undefined;
    }

    const invoice = db.prepare(`
      SELECT
        i.*,
        u.username as created_by_username
      FROM invoices i
      WHERE i.so_id = ?
     `).get(salesOrderId) as InvoiceWithUsername | undefined;

    return {
      quotation,
      salesOrder,
      invoice
    };
  }

  /**
   * Generate sales order number
   */
  private static generateSalesOrderNo(db: Database.Database): string {
    return generateDocNo(db, 'SO');
  }

  private static generateInvoiceNo(db: Database.Database): string {
    return generateDocNo(db, 'INV');
  }

  private static generateMovementNo(db: Database.Database): string {
    return generateDocNo(db, 'MOV', 5);
  }
}

export default SalesOrderModel;
