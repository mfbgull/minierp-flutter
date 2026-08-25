"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createDraft = createDraft;
exports.updateDraft = updateDraft;
exports.getDraft = getDraft;
exports.deleteDraft = deleteDraft;
exports.searchItems = searchItems;
exports.searchCustomers = searchCustomers;
exports.getTaxRates = getTaxRates;
exports.getPaymentTerms = getPaymentTerms;
exports.submitInvoice = submitInvoice;
const database_1 = __importDefault(require("../config/database"));
const queryUtils_1 = require("../utils/queryUtils");
const logger_1 = __importDefault(require("../utils/logger"));
const MobileInvoice_1 = __importDefault(require("../models/MobileInvoice"));
const queryUtils_2 = require("../utils/queryUtils");
async function createDraft(req, res) {
    try {
        const { session_id, customer_id, invoice_date, due_date, terms, notes, items_data } = req.body;
        const { randomUUID } = await Promise.resolve().then(() => __importStar(require('crypto')));
        const finalSessionId = session_id || `mobile_${Date.now()}_${randomUUID().replace(/-/g, '').slice(0, 9)}`;
        const existingDraft = MobileInvoice_1.default.getDraftBySession(database_1.default, finalSessionId);
        if (existingDraft) {
            MobileInvoice_1.default.updateDraft(database_1.default, existingDraft.id, { customer_id, invoice_date, due_date, terms, notes, items_data });
            return res.json({ success: true, data: { id: existingDraft.id, session_id: finalSessionId }, message: 'Draft updated successfully' });
        }
        const id = MobileInvoice_1.default.createDraft(database_1.default, { customer_id, invoice_date, due_date, terms, notes, items_data }, finalSessionId);
        res.status(201).json({ success: true, data: { id, session_id: finalSessionId }, message: 'Draft created successfully' });
    }
    catch (error) {
        logger_1.default.error('Create draft error:', error);
        res.status(500).json({ error: 'Failed to create draft' });
    }
}
async function updateDraft(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const { customer_id, invoice_date, due_date, terms, notes, items_data, status } = req.body;
        const draft = MobileInvoice_1.default.getDraftById(database_1.default, id);
        if (!draft) {
            return res.status(404).json({ error: 'Draft not found' });
        }
        if (new Date(draft.expires_at) < new Date()) {
            return res.status(410).json({ error: 'Draft has expired' });
        }
        MobileInvoice_1.default.updateDraft(database_1.default, id, { customer_id, invoice_date, due_date, terms, notes, items_data, status });
        res.json({ success: true, message: 'Draft updated successfully' });
    }
    catch (error) {
        logger_1.default.error('Update draft error:', error);
        res.status(500).json({ error: 'Failed to update draft' });
    }
}
async function getDraft(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const draft = MobileInvoice_1.default.getDraftById(database_1.default, id);
        if (!draft) {
            return res.status(404).json({ error: 'Draft not found' });
        }
        if (new Date(draft.expires_at) < new Date()) {
            return res.status(410).json({ error: 'Draft has expired' });
        }
        const parsedDraft = { ...draft, items_data: draft.items_data ? JSON.parse(draft.items_data) : [] };
        res.json({ success: true, data: parsedDraft });
    }
    catch (error) {
        logger_1.default.error('Get draft error:', error);
        res.status(500).json({ error: 'Failed to get draft' });
    }
}
async function deleteDraft(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const deleted = MobileInvoice_1.default.deleteDraft(database_1.default, id);
        if (!deleted) {
            return res.status(404).json({ error: 'Draft not found' });
        }
        res.json({ success: true, message: 'Draft deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete draft error:', error);
        res.status(500).json({ error: 'Failed to delete draft' });
    }
}
async function searchItems(req, res) {
    try {
        const qParam = (0, queryUtils_2.getQueryParam)(req.query.q);
        const limitParam = (0, queryUtils_2.getQueryParam)(req.query.limit);
        const q = qParam || '';
        const limit = parseInt(limitParam || '20', 10);
        const items = MobileInvoice_1.default.searchItems(database_1.default, q, limit);
        res.json({ success: true, data: items, count: items.length });
    }
    catch (error) {
        logger_1.default.error('Search items error:', error);
        res.status(500).json({ error: 'Failed to search items' });
    }
}
async function searchCustomers(req, res) {
    try {
        const qParam = (0, queryUtils_2.getQueryParam)(req.query.q);
        const limitParam = (0, queryUtils_2.getQueryParam)(req.query.limit);
        const q = qParam || '';
        const limit = parseInt(limitParam || '20', 10);
        const customers = MobileInvoice_1.default.searchCustomers(database_1.default, q, limit);
        res.json({ success: true, data: customers, count: customers.length });
    }
    catch (error) {
        logger_1.default.error('Search customers error:', error);
        res.status(500).json({ error: 'Failed to search customers' });
    }
}
async function getTaxRates(req, res) {
    try {
        const taxRates = MobileInvoice_1.default.getTaxRates(database_1.default);
        res.json({ success: true, data: taxRates });
    }
    catch (error) {
        logger_1.default.error('Get tax rates error:', error);
        res.status(500).json({ error: 'Failed to get tax rates' });
    }
}
async function getPaymentTerms(req, res) {
    try {
        const paymentTerms = MobileInvoice_1.default.getPaymentTerms(database_1.default);
        res.json({ success: true, data: paymentTerms });
    }
    catch (error) {
        logger_1.default.error('Get payment terms error:', error);
        res.status(500).json({ error: 'Failed to get payment terms' });
    }
}
async function submitInvoice(req, res) {
    try {
        const { draft_id, invoice_no, customer_id, invoice_date, due_date, status, terms, notes, items, record_payment, payment } = req.body;
        if (!customer_id) {
            return res.status(400).json({ error: 'Customer is required', field: 'customer_id' });
        }
        if (!invoice_date) {
            return res.status(400).json({ error: 'Invoice date is required', field: 'invoice_date' });
        }
        if (!items || items.length === 0) {
            return res.status(400).json({ error: 'At least one item is required', field: 'items' });
        }
        const invoiceId = MobileInvoice_1.default.submitInvoice(database_1.default, {
            draft_id: draft_id ? parseInt(draft_id, 10) : undefined,
            invoice_no, customer_id, invoice_date, due_date, status, terms, notes, items, record_payment, payment,
            userId: req.user.id,
        });
        const createdInvoice = MobileInvoice_1.default.getInvoiceWithCustomer(database_1.default, invoiceId);
        res.status(201).json({ success: true, data: createdInvoice, message: 'Invoice created successfully' });
    }
    catch (error) {
        logger_1.default.error('Submit invoice error:', error);
        res.status(500).json({ success: false, error: 'Failed to create invoice' });
    }
}
exports.default = {
    createDraft,
    updateDraft,
    getDraft,
    deleteDraft,
    searchItems,
    searchCustomers,
    getTaxRates,
    getPaymentTerms,
    submitInvoice,
};
