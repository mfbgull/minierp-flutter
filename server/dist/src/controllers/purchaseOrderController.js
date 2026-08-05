"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const PurchaseOrder_1 = __importDefault(require("../models/PurchaseOrder"));
const SupplierLedger_1 = __importDefault(require("../models/SupplierLedger"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
function createPurchaseOrder(req, res) {
    try {
        const { supplier_id, po_date, items } = req.body;
        // Validation
        if (!supplier_id || !po_date) {
            res.status(400).json({
                error: 'Supplier and PO date are required'
            });
            return;
        }
        if (!items || items.length === 0) {
            res.status(400).json({
                error: 'At least one item is required'
            });
            return;
        }
        // Validate items
        for (const item of items) {
            if (!item.item_id || !item.quantity || !item.unit_price) {
                res.status(400).json({
                    error: 'Each item must have item_id, quantity, and unit_price'
                });
                return;
            }
            if (item.quantity <= 0) {
                res.status(400).json({
                    error: 'Item quantity must be positive'
                });
                return;
            }
            if (item.unit_price <= 0) {
                res.status(400).json({
                    error: 'Item unit price must be positive'
                });
                return;
            }
        }
        const po = PurchaseOrder_1.default.create(req.body, req.user.id, database_1.default);
        res.status(201).json(po);
    }
    catch (error) {
        logger_1.default.error('Create PO error:', error);
        res.status(500).json({ error: error.message || 'Failed to create purchase order' });
    }
}
function getPurchaseOrders(req, res) {
    try {
        const supplierIdParam = (0, queryUtils_1.getQueryParam)(req.query.supplier_id);
        const statusParam = (0, queryUtils_1.getQueryParam)(req.query.status);
        const startDateParam = (0, queryUtils_1.getQueryParam)(req.query.start_date);
        const endDateParam = (0, queryUtils_1.getQueryParam)(req.query.end_date);
        const limitParam = (0, queryUtils_1.getQueryParam)(req.query.limit);
        const filters = {
            supplier_id: supplierIdParam ? Number(supplierIdParam) : undefined,
            status: statusParam,
            start_date: startDateParam,
            end_date: endDateParam,
            limit: limitParam ? parseInt(String(limitParam)) : undefined
        };
        const pos = PurchaseOrder_1.default.getAll(filters, database_1.default);
        res.json(pos);
    }
    catch (error) {
        logger_1.default.error('Get POs error:', error);
        res.status(500).json({ error: 'Failed to get purchase orders' });
    }
}
function getPurchaseOrder(req, res) {
    try {
        const po = PurchaseOrder_1.default.getById(Number(req.params.id), database_1.default);
        if (!po) {
            res.status(404).json({ error: 'Purchase order not found' });
            return;
        }
        // Get items
        const items = PurchaseOrder_1.default.getItems(po.id, database_1.default);
        res.json({ ...po, items });
    }
    catch (error) {
        logger_1.default.error('Get PO error:', error);
        res.status(500).json({ error: 'Failed to get purchase order' });
    }
}
function updatePurchaseOrder(req, res) {
    try {
        const { supplier_id, po_date, expected_delivery_date, notes, warehouse_id } = req.body;
        const po = PurchaseOrder_1.default.update(Number(req.params.id), {
            supplier_id,
            po_date,
            expected_delivery_date,
            notes,
            warehouse_id
        }, req.user.id, database_1.default);
        res.json(po);
    }
    catch (error) {
        logger_1.default.error('Update PO error:', error);
        res.status(500).json({ error: error.message || 'Failed to update purchase order' });
    }
}
function deletePurchaseOrder(req, res) {
    try {
        PurchaseOrder_1.default.delete(Number(req.params.id), req.user.id, database_1.default);
        res.json({ success: true, message: 'Purchase order deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete PO error:', error);
        res.status(500).json({ error: error.message || 'Failed to delete purchase order' });
    }
}
function addLineItem(req, res) {
    try {
        const { item_id, quantity, unit_price } = req.body;
        if (!item_id || !quantity || !unit_price) {
            res.status(400).json({
                error: 'Item, quantity, and unit price are required'
            });
            return;
        }
        if (quantity <= 0) {
            res.status(400).json({ error: 'Quantity must be positive' });
            return;
        }
        if (unit_price <= 0) {
            res.status(400).json({ error: 'Unit price must be positive' });
            return;
        }
        const item = PurchaseOrder_1.default.addItem(Number(req.params.id), { item_id, quantity, unit_price }, database_1.default);
        res.status(201).json(item);
    }
    catch (error) {
        logger_1.default.error('Add PO item error:', error);
        res.status(500).json({ error: error.message || 'Failed to add line item' });
    }
}
function updateLineItem(req, res) {
    try {
        const { quantity, unit_price } = req.body;
        if (!quantity || !unit_price) {
            res.status(400).json({
                error: 'Quantity and unit price are required'
            });
            return;
        }
        if (quantity <= 0) {
            res.status(400).json({ error: 'Quantity must be positive' });
            return;
        }
        if (unit_price <= 0) {
            res.status(400).json({ error: 'Unit price must be positive' });
            return;
        }
        const item = PurchaseOrder_1.default.updateItem(Number(req.params.itemId), { quantity, unit_price }, database_1.default);
        res.json(item);
    }
    catch (error) {
        logger_1.default.error('Update PO item error:', error);
        res.status(500).json({ error: error.message || 'Failed to update line item' });
    }
}
function deleteLineItem(req, res) {
    try {
        PurchaseOrder_1.default.removeItem(Number(req.params.itemId), database_1.default);
        res.json({ success: true, message: 'Line item deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete PO item error:', error);
        res.status(500).json({ error: error.message || 'Failed to delete line item' });
    }
}
function updateStatus(req, res) {
    try {
        const { status } = req.body;
        if (!status) {
            res.status(400).json({ error: 'Status is required' });
            return;
        }
        const validStatuses = ['Draft', 'Submitted', 'Partially Received', 'Completed', 'Cancelled'];
        if (!validStatuses.includes(status)) {
            res.status(400).json({ error: `Invalid status. Valid statuses: ${validStatuses.join(', ')}` });
            return;
        }
        const po = PurchaseOrder_1.default.updateStatus(Number(req.params.id), status, req.user.id, database_1.default);
        res.json(po);
    }
    catch (error) {
        logger_1.default.error('Update PO status error:', error);
        res.status(500).json({ error: error.message || 'Failed to update purchase order status' });
    }
}
function getGoodsReceipts(req, res) {
    try {
        const receipts = PurchaseOrder_1.default.getReceipts(Number(req.params.id), database_1.default);
        res.json(receipts);
    }
    catch (error) {
        logger_1.default.error('Get goods receipts error:', error);
        res.status(500).json({ error: 'Failed to get goods receipts' });
    }
}
function createGoodsReceipt(req, res) {
    try {
        const { receipt_date, warehouse_id, remarks, items } = req.body;
        // Validation
        if (!receipt_date || !warehouse_id) {
            res.status(400).json({
                error: 'Receipt date and warehouse are required'
            });
            return;
        }
        if (!items || items.length === 0) {
            res.status(400).json({
                error: 'At least one item must be received'
            });
            return;
        }
        // Validate receipt items
        for (const item of items) {
            if (!item.po_item_id || !item.received_quantity) {
                res.status(400).json({
                    error: 'Each receipt item must have po_item_id and received_quantity'
                });
                return;
            }
            if (item.received_quantity <= 0) {
                res.status(400).json({
                    error: 'Received quantity must be positive'
                });
                return;
            }
        }
        const receipt = PurchaseOrder_1.default.addReceipt({
            po_id: Number(req.params.id),
            receipt_date,
            warehouse_id,
            remarks,
            items
        }, req.user.id, database_1.default);
        res.status(201).json(receipt);
    }
    catch (error) {
        logger_1.default.error('Create goods receipt error:', error);
        res.status(500).json({ error: error.message || 'Failed to create goods receipt' });
    }
}
function returnReceiptItems(req, res) {
    try {
        const { id } = req.params;
        const poId = parseInt(id, 10);
        const userId = req.user.id;
        const { items, reason } = req.body;
        if (!items || items.length === 0) {
            res.status(400).json({ error: 'At least one item must be returned' });
            return;
        }
        for (const item of items) {
            if (!item.po_item_id || !item.return_quantity || item.return_quantity <= 0) {
                res.status(400).json({ error: 'Each return item must have po_item_id and a positive return_quantity' });
                return;
            }
        }
        let result;
        database_1.default.transaction(() => {
            result = PurchaseOrder_1.default.returnReceiptItems(poId, items, userId, database_1.default, reason);
            // Post GL reversal — Dr AP, Cr Inventory
            accountingService_1.default.postPurchaseReturnEntry(database_1.default, {
                purchaseId: poId,
                purchaseNo: `PO-${poId}`,
                returnAmount: result.totalAmount,
                returnDate: new Date().toISOString().split('T')[0],
                userId,
            });
        })();
        res.json({ success: true, message: 'Return processed successfully', data: result });
    }
    catch (error) {
        logger_1.default.error('Return receipt items error:', error);
        res.status(400).json({ error: error.message || 'Failed to process return' });
    }
}
function getPendingOrders(req, res) {
    try {
        const pos = PurchaseOrder_1.default.getPendingOrders(database_1.default);
        res.json(pos);
    }
    catch (error) {
        logger_1.default.error('Get pending POs error:', error);
        res.status(500).json({ error: 'Failed to get pending purchase orders' });
    }
}
function getSummaryBySupplier(req, res) {
    try {
        const { supplierId } = req.params;
        if (!supplierId) {
            res.status(400).json({ error: 'Supplier ID is required' });
            return;
        }
        const summary = PurchaseOrder_1.default.getSummaryBySupplier(Number(supplierId), database_1.default);
        // Return default object if no purchase orders exist for this supplier
        res.json(summary || {
            total_pos: 0,
            draft_pos: 0,
            submitted_pos: 0,
            partially_received_pos: 0,
            completed_pos: 0,
            total_value: 0
        });
    }
    catch (error) {
        logger_1.default.error('Get PO summary error:', error);
        res.status(500).json({ error: 'Failed to get purchase order summary' });
    }
}
function getSupplierBalance(req, res) {
    try {
        const { supplierId } = req.params;
        if (!supplierId) {
            res.status(400).json({ error: 'Supplier ID is required' });
            return;
        }
        const balance = SupplierLedger_1.default.getBalance(Number(supplierId), database_1.default);
        // Ensure balance is always a number (0 if no ledger entries exist)
        res.json({ supplier_id: Number(supplierId), balance: balance || 0 });
    }
    catch (error) {
        logger_1.default.error('Get supplier balance error:', error);
        res.status(500).json({ error: 'Failed to get supplier balance' });
    }
}
function getSupplierTransactions(req, res) {
    try {
        const { supplierId } = req.params;
        if (!supplierId) {
            res.status(400).json({ error: 'Supplier ID is required' });
            return;
        }
        const transactions = SupplierLedger_1.default.getTransactions(Number(supplierId), database_1.default);
        res.json(transactions);
    }
    catch (error) {
        logger_1.default.error('Get supplier transactions error:', error);
        res.status(500).json({ error: 'Failed to get supplier transactions' });
    }
}
exports.default = {
    createPurchaseOrder,
    getPurchaseOrders,
    getPurchaseOrder,
    updatePurchaseOrder,
    deletePurchaseOrder,
    addLineItem,
    updateLineItem,
    deleteLineItem,
    updateStatus,
    getGoodsReceipts,
    createGoodsReceipt,
    returnReceiptItems,
    getPendingOrders,
    getSummaryBySupplier,
    getSupplierBalance,
    getSupplierTransactions
};
//# sourceMappingURL=purchaseOrderController.js.map