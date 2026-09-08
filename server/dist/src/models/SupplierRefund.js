"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.creditNoteRefundable = creditNoteRefundable;
const SupplierLedger_1 = __importDefault(require("./SupplierLedger"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const logger_1 = __importDefault(require("../utils/logger"));
const sequence_1 = require("../utils/sequence");
const REFUND_SELECT = `
  SELECT sr.*, s.supplier_name, cn.credit_no
  FROM supplier_refunds sr
  LEFT JOIN suppliers s ON s.id = sr.supplier_id
  LEFT JOIN credit_notes cn ON cn.id = sr.credit_note_id
`;
/** Amount of a credit note not yet paid out (excludes voided refunds). */
function creditNoteRefundable(creditNoteId, db) {
    const note = db.prepare(`SELECT amount, status FROM credit_notes WHERE id = ?`)
        .get(creditNoteId);
    if (!note || note.status !== 'POSTED')
        return 0;
    const refunded = db.prepare(`
    SELECT COALESCE(SUM(amount), 0) AS paid FROM supplier_refunds
    WHERE credit_note_id = ? AND status = 'POSTED'
  `).get(creditNoteId);
    return Number(note.amount) - Number(refunded.paid);
}
class SupplierRefundModel {
    static getAll(filters, db) {
        const page = filters.page || 1;
        const limit = filters.limit || 10;
        const offset = (page - 1) * limit;
        let where = ' WHERE 1=1';
        const params = [];
        if (filters.supplier_id) {
            where += ' AND sr.supplier_id = ?';
            params.push(filters.supplier_id);
        }
        const total = db.prepare(`SELECT COUNT(*) AS n FROM supplier_refunds sr${where}`).get(...params).n;
        const rows = db.prepare(`${REFUND_SELECT}${where} ORDER BY sr.refund_date DESC, sr.id DESC LIMIT ? OFFSET ?`).all(...params, limit, offset);
        return { rows, total, pageNum: page, limitNum: limit };
    }
    static getById(id, db) {
        return db.prepare(`${REFUND_SELECT} WHERE sr.id = ?`).get(id);
    }
    static create(data, userId, db) {
        if (!data.refund_date)
            throw new Error('refund_date is required');
        const amount = Number(data.amount);
        if (!amount || amount <= 0)
            throw new Error('Refund amount must be positive');
        const note = db.prepare(`SELECT * FROM credit_notes WHERE id = ?`)
            .get(data.credit_note_id);
        if (!note)
            throw new Error(`Credit note ${data.credit_note_id} not found`);
        if (note.status !== 'POSTED') {
            throw new Error(`Credit note ${note.credit_no} is not POSTED — cannot refund`);
        }
        if (!note.supplier_id) {
            throw new Error(`Credit note ${note.credit_no} has no resolvable supplier — cannot refund`);
        }
        const refundable = creditNoteRefundable(note.id, db);
        if (amount > refundable + 0.005) {
            throw new Error(`Refund amount (${amount.toFixed(2)}) exceeds the refundable credit ` +
                `(${refundable.toFixed(2)}) on ${note.credit_no}`);
        }
        const paymentMethod = data.payment_method || 'cash';
        const refundNo = (0, sequence_1.generateDocNo)(db, 'SR');
        // Funds guard — refunds are cash-out, same primitive expenses use.
        const cashCode = accountingService_1.default._cashOrBankAccountCode(paymentMethod);
        const cashAccount = accountingService_1.default.getAccountByCode(db, cashCode);
        if (!cashAccount) {
            throw new Error(`Chart of accounts is missing required account: ${cashCode}`);
        }
        accountingService_1.default.assertSufficientFunds(db, {
            accountId: cashAccount.id,
            amount,
            asOfDate: data.refund_date,
            label: `supplier refund ${refundNo}`,
        });
        const result = db.prepare(`
      INSERT INTO supplier_refunds (
        refund_no, refund_date, supplier_id, credit_note_id, return_id,
        amount, payment_method, reference_no, status, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'POSTED', ?)
    `).run(refundNo, data.refund_date, note.supplier_id, note.id, note.source_id, amount, paymentMethod, data.reference_no || null, userId);
        const refundId = result.lastInsertRowid;
        // Supplier ledger: debit restores the balance the credit note reduced.
        SupplierLedger_1.default.createEntry({
            supplier_id: note.supplier_id,
            transaction_date: data.refund_date,
            transaction_type: 'SUPPLIER_REFUND',
            reference_no: refundNo,
            debit: amount,
            credit: 0,
            description: `Supplier refund ${refundNo} against credit note ${note.credit_no}`,
        }, db);
        SupplierLedger_1.default.rebuildBalances(note.supplier_id, db);
        // GL: Dr AP (settles the CN's Dr AP leg with cash) / Cr Cash.
        const ap = accountingService_1.default.getAccountByCode(db, '2000');
        if (!ap) {
            throw new Error('Chart of accounts is missing required account: 2000 (AP)');
        }
        accountingService_1.default.postEntry(db, {
            entry_date: data.refund_date,
            description: `Supplier refund ${refundNo} — ${amount.toFixed(2)} (${cashCode})`,
            reference_type: 'SUPPLIER_REFUND',
            reference_id: refundId,
            created_by: userId,
            lines: [
                { account_id: ap.id, debit: amount, description: `AP settled by refund ${refundNo}` },
                { account_id: cashAccount.id, credit: amount, description: `Cash paid via refund ${refundNo}` },
            ],
        });
        db.prepare(`
      INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
      VALUES (?, ?, ?, ?, ?)
    `).run(userId, 'CREATE', 'SupplierRefund', refundId, `Issued supplier refund ${refundNo}: ${amount.toFixed(2)} against credit note ${note.credit_no}`);
        return this.getById(refundId, db);
    }
    static void(id, userId, reason, db) {
        const refund = this.getById(id, db);
        if (!refund)
            throw new Error('Supplier refund not found');
        if (refund.status !== 'POSTED')
            throw new Error('Only POSTED refunds can be voided');
        db.prepare(`
      UPDATE supplier_refunds
      SET status = 'VOIDED', voided_at = datetime('now'), voided_by = ?, voided_reason = ?
      WHERE id = ?
    `).run(userId, reason || null, id);
        // Reverse the ledger debit (credit side) + rebuild the balance chain.
        SupplierLedger_1.default.createEntry({
            supplier_id: refund.supplier_id,
            transaction_date: new Date().toISOString().split('T')[0],
            transaction_type: 'SUPPLIER_REFUND_VOID',
            reference_no: refund.refund_no,
            debit: 0,
            credit: refund.amount,
            description: `Void supplier refund ${refund.refund_no}${reason ? ': ' + reason : ''}`,
        }, db);
        SupplierLedger_1.default.rebuildBalances(refund.supplier_id, db);
        // Reverse the GL entry by reference.
        accountingService_1.default.voidJournalLinesByReference(db, 'SUPPLIER_REFUND', id);
        db.prepare(`
      INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
      VALUES (?, ?, ?, ?, ?)
    `).run(userId, 'VOID', 'SupplierRefund', id, `Voided supplier refund ${refund.refund_no}${reason ? ': ' + reason : ''}`);
        logger_1.default.info(`Supplier refund ${refund.refund_no} voided by user ${userId}`);
        return this.getById(id, db);
    }
}
exports.default = SupplierRefundModel;
