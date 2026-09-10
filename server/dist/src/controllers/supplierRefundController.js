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
const queryUtils_1 = require("../utils/queryUtils");
const SupplierRefund_1 = __importStar(require("../models/SupplierRefund"));
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const cashService_1 = require("../services/cashService");
function getSupplierRefunds(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const supplierId = Number(req.query.supplier_id) || undefined;
        const { rows, total, pageNum, limitNum } = SupplierRefund_1.default.getAll({ supplier_id: supplierId, page, limit }, database_1.default);
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: pageNum,
                totalPages: Math.ceil(total / limitNum),
                totalItems: total,
                hasNext: pageNum < Math.ceil(total / limitNum),
                hasPrev: pageNum > 1,
            },
        });
    }
    catch (error) {
        logger_1.default.error('Get supplier refunds error:', error);
        res.status(500).json({ error: 'Failed to get supplier refunds' });
    }
}
function getSupplierRefund(req, res) {
    try {
        const refund = SupplierRefund_1.default.getById(Number(req.params.id), database_1.default);
        if (!refund) {
            res.status(404).json({ error: 'Supplier refund not found' });
            return;
        }
        res.json(refund);
    }
    catch (error) {
        logger_1.default.error('Get supplier refund error:', error);
        res.status(500).json({ error: 'Failed to get supplier refund' });
    }
}
/** Refundable balance of a credit note — for the payout dialog. */
function getCreditNoteRefundable(req, res) {
    try {
        const creditNoteId = Number(req.params.id);
        res.json({ credit_note_id: creditNoteId, refundable: (0, SupplierRefund_1.creditNoteRefundable)(creditNoteId, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Get refundable balance error:', error);
        res.status(500).json({ error: 'Failed to get refundable balance' });
    }
}
function createSupplierRefund(req, res) {
    try {
        const body = req.body;
        if (!body.refund_date)
            return res.status(400).json({ error: 'refund_date is required' });
        if (!body.credit_note_id || body.credit_note_id <= 0) {
            return res.status(400).json({ error: 'A valid credit_note_id is required' });
        }
        if (body.payment_method !== undefined && !(0, cashService_1.isValidPaymentMethod)(body.payment_method)) {
            return res.status(400).json({
                error: `Invalid payment_method "${body.payment_method}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`,
            });
        }
        const created = SupplierRefund_1.default.create({
            refund_date: body.refund_date,
            credit_note_id: body.credit_note_id,
            amount: Number(body.amount),
            payment_method: body.payment_method,
            reference_no: body.reference_no,
        }, req.user.id, database_1.default);
        res.status(201).json({
            success: true,
            message: `Supplier refund ${created.refund_no} issued successfully`,
            data: created,
        });
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        logger_1.default.error('Create supplier refund error:', { error: errorMessage });
        res.status(400).json({ error: errorMessage });
    }
}
function voidSupplierRefund(req, res) {
    try {
        const id = Number(req.params.id);
        const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;
        const voided = SupplierRefund_1.default.void(id, req.user.id, reason || '', database_1.default);
        res.json({
            success: true,
            message: `Supplier refund ${voided.refund_no} voided successfully`,
            data: voided,
        });
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        logger_1.default.error('Void supplier refund error:', { error: errorMessage });
        res.status(400).json({ error: errorMessage });
    }
}
exports.default = {
    getSupplierRefunds,
    getSupplierRefund,
    getCreditNoteRefundable,
    createSupplierRefund,
    voidSupplierRefund,
};
