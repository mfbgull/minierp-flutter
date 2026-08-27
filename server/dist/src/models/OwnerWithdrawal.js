"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateWithdrawalNo = generateWithdrawalNo;
const accountingService_1 = __importDefault(require("../services/accountingService"));
const sequence_1 = require("../utils/sequence");
const StockMovement_1 = __importDefault(require("./StockMovement"));
const round2 = (n) => parseFloat(n.toFixed(2));
function generateWithdrawalNo(db, withdrawalDate) {
    const date = new Date(withdrawalDate);
    const year = date.getFullYear().toString().slice(-2);
    const month = String(date.getMonth() + 1).padStart(2, '0');
    // Shared atomic counter allocated inside the caller's INSERT transaction
    // (EXP-05 pattern); UNIQUE(withdrawal_no) backstops it.
    const nextNo = (0, sequence_1.getNextSequenceNumber)(db, `WD_last_no_${year}${month}`);
    return `WD-${year}${month}-${String(nextNo).padStart(4, '0')}`;
}
/**
 * Server-side FIFO/FEFO costing for the given user-entered lines.
 * Delegates to the SAME consumer sales COGS uses (FEFO when the item
 * tracks expiry, else FIFO by receipt order); availability is validated
 * against stock_balances and batches are decremented as they are
 * consumed. MUST run inside the caller's write transaction so the
 * decrements persist or roll back atomically with everything else.
 */
function consumeForLines(db, lines) {
    const consumption = [];
    let totalCost = 0;
    for (const line of lines) {
        const entries = StockMovement_1.default.consumeFromOldestBatches(line.item_id, line.warehouse_id, line.quantity, db);
        for (const e of entries) {
            consumption.push({
                item_id: line.item_id,
                warehouse_id: line.warehouse_id,
                batchId: e.batchId,
                consumed: e.consumed,
                unitCost: e.unitCost,
            });
            totalCost += e.consumed * e.unitCost;
        }
    }
    return { consumption, totalCost: round2(totalCost) };
}
/** Outbound OWNER_WITHDRAWAL movement rows for a withdrawal document. */
function getOriginalMovements(db, withdrawalNo) {
    return db.prepare(`
    SELECT id, movement_no, item_id, warehouse_id, quantity, unit_cost, batch_id
    FROM stock_movements
    WHERE reference_doctype = 'OWNER_WITHDRAWAL' AND reference_docno = ?
    ORDER BY id ASC
  `).all(withdrawalNo);
}
function nextAdjBatchNo(db) {
    const yy = String(new Date().getFullYear()).slice(-2);
    const nextNo = (0, sequence_1.getNextSequenceNumber)(db, `BATCH_ADJ_last_no_${yy}`);
    return `BATCH-${yy}-ADJ-${String(nextNo).padStart(4, '0')}`;
}
/**
 * Return consumed stock WITHOUT mutating history: every original outbound
 * movement gets an inbound compensating OWNER_WITHDRAWAL_REVERSAL row.
 * Batch-tracked units go back into the exact original batch (hard-block
 * if that batch row no longer exists — no silent adjustments). The only
 * exception is the legacy NULL-batch case (pre-batch-tracking stock
 * consumed at standard_cost), which is restored into a new ADJUSTMENT-
 * sourced batch at the ORIGINAL unit_cost so quantity and value are both
 * preserved faithfully.
 */
function restoreConsumption(db, originals, withdrawalNo, userId) {
    for (const m of originals) {
        const qty = Math.abs(Number(m.quantity));
        const cost = m.unit_cost ?? 0;
        let batchId = m.batch_id;
        if (batchId !== null) {
            const res = db.prepare(`
        UPDATE stock_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?
      `).run(qty, batchId);
            if (res.changes === 0) {
                throw new Error(`Cannot reverse withdrawal ${withdrawalNo}: source batch #${batchId} of movement ` +
                    `${m.movement_no} no longer exists. Restore the batch or correct inventory manually first.`);
            }
        }
        else {
            // Legacy NULL-batch consumption — recreate a cost-faithful batch.
            const inserted = db.prepare(`
        INSERT INTO stock_batches (
          batch_no, item_id, warehouse_id, source_type, source_id,
          quantity_original, quantity_remaining, unit_cost, received_date
        ) VALUES (?, ?, ?, 'ADJUSTMENT', ?, ?, ?, ?, date('now'))
      `).run(nextAdjBatchNo(db), m.item_id, m.warehouse_id, withdrawalNo, qty, qty, cost);
            batchId = inserted.lastInsertRowid;
        }
        // Positive (inbound) compensating movement; history untouched.
        StockMovement_1.default.recordMovement({
            item_id: m.item_id,
            warehouse_id: m.warehouse_id,
            movement_type: 'OWNER_WITHDRAWAL_REVERSAL',
            quantity: qty,
            unit_cost: cost,
            reference_doctype: 'OWNER_WITHDRAWAL_REVERSAL',
            reference_docno: withdrawalNo,
            remarks: `Reversal of ${m.movement_no} (withdrawal ${withdrawalNo})`,
            batch_id: batchId,
        }, userId, db);
    }
}
function insertItems(db, withdrawalId, items) {
    const stmt = db.prepare(`
    INSERT INTO owner_withdrawal_items (withdrawal_id, item_id, warehouse_id, quantity)
    VALUES (?, ?, ?, ?)
  `);
    for (const line of items)
        stmt.run(withdrawalId, line.item_id, line.warehouse_id, line.quantity);
}
function create(db, data) {
    return db.transaction(() => {
        if (data.kind === 'cash') {
            const amount = Number(data.amount);
            if (!Number.isFinite(amount) || amount <= 0) {
                throw new Error('Cash withdrawal amount must be a positive number');
            }
            const result = db.prepare(`
        INSERT INTO owner_withdrawals (
          withdrawal_no, withdrawal_date, kind, amount, payment_method, note, status, created_by
        ) VALUES (?, ?, 'cash', ?, ?, ?, 'posted', ?)
      `).run(data.withdrawal_no, data.withdrawal_date, amount, data.payment_method || 'cash', data.note || null, data.created_by);
            const newId = result.lastInsertRowid;
            accountingService_1.default.assertNoActivePosting(db, 'OWNER_WITHDRAWAL', newId);
            const cashCode = accountingService_1.default._cashOrBankAccountCode(data.payment_method || 'cash');
            const cash = accountingService_1.default.getAccountByCode(db, cashCode);
            if (!cash)
                throw new Error(`Chart of accounts is missing required account: ${cashCode}`);
            accountingService_1.default.assertSufficientFunds(db, {
                accountId: cash.id,
                amount,
                asOfDate: data.withdrawal_date,
                label: `owner withdrawal ${data.withdrawal_no}`,
            });
            accountingService_1.default.postOwnerWithdrawalCashEntry(db, {
                withdrawalId: newId,
                withdrawalNo: data.withdrawal_no,
                amount,
                withdrawalDate: data.withdrawal_date,
                paymentMethod: data.payment_method || 'cash',
                userId: data.created_by,
            });
            return { id: newId, amount };
        }
        // ---- goods kind -------------------------------------------------
        const items = data.items ?? [];
        if (items.length === 0) {
            throw new Error('A goods withdrawal requires at least one item line');
        }
        // Consume FIRST (validates availability + costs the withdrawal).
        // Runs inside this transaction, so decrements roll back on any failure.
        const { consumption, totalCost } = consumeForLines(db, items);
        if (totalCost <= 0) {
            throw new Error('Goods withdrawal value computed as zero — item cost data (batches/standard_cost) is missing');
        }
        const result = db.prepare(`
      INSERT INTO owner_withdrawals (
        withdrawal_no, withdrawal_date, kind, amount, note, status, created_by
      ) VALUES (?, ?, 'goods', ?, ?, 'posted', ?)
    `).run(data.withdrawal_no, data.withdrawal_date, totalCost, data.note || null, data.created_by);
        const newId = result.lastInsertRowid;
        insertItems(db, newId, items);
        // One movement row per consumed batch (invoice COGS pattern).
        for (const e of consumption) {
            StockMovement_1.default.recordMovement({
                item_id: e.item_id,
                warehouse_id: e.warehouse_id,
                movement_type: 'OWNER_WITHDRAWAL',
                quantity: -e.consumed,
                unit_cost: e.unitCost,
                reference_doctype: 'OWNER_WITHDRAWAL',
                reference_docno: data.withdrawal_no,
                remarks: `Owner withdrawal ${data.withdrawal_no}`,
                movement_date: data.withdrawal_date,
                batch_id: e.batchId ?? undefined,
            }, data.created_by, db);
        }
        accountingService_1.default.assertNoActivePosting(db, 'OWNER_WITHDRAWAL', newId);
        accountingService_1.default.postOwnerWithdrawalGoodsEntry(db, {
            withdrawalId: newId,
            withdrawalNo: data.withdrawal_no,
            totalCost,
            withdrawalDate: data.withdrawal_date,
            userId: data.created_by,
        });
        return { id: newId, amount: totalCost };
    })();
}
/**
 * Informational costing preview for the form. consumeFromOldestBatches
 * decrements batch quantities while computing, so this runs inside a
 * SAVEPOINT that is always rolled back — strictly read-only effect.
 */
function quote(db, lines) {
    db.exec('SAVEPOINT owner_wd_quote');
    try {
        const out = [];
        let totalCost = 0;
        for (const line of lines) {
            const entries = StockMovement_1.default.consumeFromOldestBatches(line.item_id, line.warehouse_id, line.quantity, db);
            let lineTotal = 0;
            const batches = entries.map((e) => {
                lineTotal += e.consumed * e.unitCost;
                return { batchId: e.batchId, quantity: e.consumed, unitCost: e.unitCost };
            });
            out.push({ item_id: line.item_id, warehouse_id: line.warehouse_id, batches, total: round2(lineTotal) });
            totalCost += lineTotal;
        }
        return { lines: out, totalCost: round2(totalCost) };
    }
    finally {
        db.exec('ROLLBACK TO owner_wd_quote');
        db.exec('RELEASE owner_wd_quote');
    }
}
function getAll(db, filters = {}) {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;
    const offset = (pageNum - 1) * limitNum;
    let query = `
    SELECT ow.id, ow.withdrawal_no, ow.withdrawal_date, ow.kind, ow.amount,
           ow.payment_method, ow.note, ow.status, ow.created_at,
           u.full_name as created_by_name,
           (SELECT COUNT(*) FROM owner_withdrawal_items i WHERE i.withdrawal_id = ow.id) AS item_line_count
    FROM owner_withdrawals ow LEFT JOIN users u ON ow.created_by = u.id WHERE 1=1
  `;
    const params = [];
    if (filters.status && filters.status !== 'all') {
        query += ' AND ow.status = ?';
        params.push(filters.status);
    }
    else if (!filters.status) {
        query += " AND ow.status = 'posted'";
    }
    if (filters.kind && filters.kind !== 'all') {
        query += ' AND ow.kind = ?';
        params.push(filters.kind);
    }
    if (filters.from_date) {
        query += ' AND ow.withdrawal_date >= ?';
        params.push(filters.from_date);
    }
    if (filters.to_date) {
        query += ' AND ow.withdrawal_date <= ?';
        params.push(filters.to_date);
    }
    if (filters.search) {
        const term = `%${filters.search}%`;
        query += ' AND (ow.withdrawal_no LIKE ? OR ow.note LIKE ? OR ow.payment_method LIKE ?)';
        params.push(term, term, term);
    }
    query += ` ORDER BY ${filters.sortBy || 'ow.withdrawal_date'} ${filters.sortOrder || 'DESC'} LIMIT ? OFFSET ?`;
    params.push(limitNum, offset);
    return db.prepare(query).all(...params);
}
function getCount(db, filters = {}) {
    let query = 'SELECT COUNT(*) as count FROM owner_withdrawals ow WHERE 1=1';
    const params = [];
    if (filters.status && filters.status !== 'all') {
        query += ' AND ow.status = ?';
        params.push(filters.status);
    }
    else if (!filters.status) {
        query += " AND ow.status = 'posted'";
    }
    if (filters.kind && filters.kind !== 'all') {
        query += ' AND ow.kind = ?';
        params.push(filters.kind);
    }
    if (filters.from_date) {
        query += ' AND ow.withdrawal_date >= ?';
        params.push(filters.from_date);
    }
    if (filters.to_date) {
        query += ' AND ow.withdrawal_date <= ?';
        params.push(filters.to_date);
    }
    if (filters.search) {
        const term = `%${filters.search}%`;
        query += ' AND (ow.withdrawal_no LIKE ? OR ow.note LIKE ? OR ow.payment_method LIKE ?)';
        params.push(term, term, term);
    }
    return db.prepare(query).get(...params).count;
}
function getById(db, id) {
    return db.prepare(`
    SELECT ow.id, ow.withdrawal_no, ow.withdrawal_date, ow.kind, ow.amount,
           ow.payment_method, ow.note, ow.status, ow.created_at, ow.updated_at,
           u.full_name as created_by_name
    FROM owner_withdrawals ow LEFT JOIN users u ON ow.created_by = u.id WHERE ow.id = ?
  `).get(id);
}
function getItems(db, withdrawalId) {
    return db.prepare(`
    SELECT wi.id, wi.item_id, wi.warehouse_id, wi.quantity,
           i.item_name, i.item_code, w.warehouse_name
    FROM owner_withdrawal_items wi
    JOIN items i ON i.id = wi.item_id
    JOIN warehouses w ON w.id = wi.warehouse_id
    WHERE wi.withdrawal_id = ?
    ORDER BY wi.id ASC
  `).all(withdrawalId);
}
function getMovements(db, withdrawalNo) {
    return db.prepare(`
    SELECT sm.id, sm.movement_no, sm.movement_type, sm.quantity, sm.unit_cost,
           sm.batch_id, sm.remarks, sm.movement_date,
           i.item_name, i.item_code, w.warehouse_name,
           b.batch_no
    FROM stock_movements sm
    JOIN items i ON i.id = sm.item_id
    JOIN warehouses w ON w.id = sm.warehouse_id
    LEFT JOIN stock_batches b ON b.id = sm.batch_id
    WHERE sm.reference_doctype IN ('OWNER_WITHDRAWAL','OWNER_WITHDRAWAL_REVERSAL')
      AND sm.reference_docno = ?
    ORDER BY sm.id ASC
  `).all(withdrawalNo);
}
/**
 * Diff-based edit. Note-only changes touch metadata only. Anything else
 * (cash: date/amount/method; goods: lines/date) runs ONE atomic
 * transaction: restore stock via compensating movements → void old GL →
 * re-consume at current costs → post replacement GL.
 */
function update(db, id, data, opts) {
    const existing = getById(db, id);
    if (!existing)
        throw new Error('Owner withdrawal not found');
    if (existing.status === 'voided')
        throw new Error('A voided owner withdrawal cannot be edited');
    accountingService_1.default.assertPeriodNotClosed(db, existing.withdrawal_date, `Owner withdrawal ${existing.withdrawal_no}`);
    if (existing.kind === 'cash') {
        const newDate = data.withdrawal_date ?? existing.withdrawal_date;
        const newAmount = data.amount !== undefined ? Number(data.amount) : existing.amount;
        const newMethod = data.payment_method !== undefined ? data.payment_method : existing.payment_method;
        const moneyChanged = String(newDate) !== String(existing.withdrawal_date) ||
            Number(newAmount) !== Number(existing.amount) ||
            String(newMethod ?? '') !== String(existing.payment_method ?? '');
        db.transaction(() => {
            if (moneyChanged) {
                if (!(newAmount > 0))
                    throw new Error('Cash withdrawal amount must be a positive number');
                accountingService_1.default.voidJournalLinesByReference(db, 'OWNER_WITHDRAWAL', id, {
                    voidedBy: opts.userId ?? null,
                    voidReason: 'Re-posted after edit',
                });
                const cashCode = accountingService_1.default._cashOrBankAccountCode(newMethod ?? undefined);
                const cash = accountingService_1.default.getAccountByCode(db, cashCode);
                if (!cash)
                    throw new Error(`Chart of accounts is missing required account: ${cashCode}`);
                accountingService_1.default.assertSufficientFunds(db, {
                    accountId: cash.id,
                    amount: newAmount,
                    asOfDate: newDate,
                    label: `owner withdrawal ${existing.withdrawal_no}`,
                });
                db.prepare(`
          UPDATE owner_withdrawals SET withdrawal_date = ?, amount = ?, payment_method = ?,
            note = COALESCE(?, note), updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `).run(newDate, newAmount, newMethod, data.note ?? null, id);
                accountingService_1.default.postOwnerWithdrawalCashEntry(db, {
                    withdrawalId: id,
                    withdrawalNo: existing.withdrawal_no,
                    amount: newAmount,
                    withdrawalDate: newDate,
                    paymentMethod: newMethod ?? undefined,
                    userId: opts.userId,
                });
            }
            else {
                db.prepare(`
          UPDATE owner_withdrawals SET note = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
        `).run(data.note !== undefined ? data.note : existing.note, id);
            }
        })();
        return { amount: moneyChanged ? Number(data.amount ?? existing.amount) : existing.amount };
    }
    // ---- goods kind ---------------------------------------------------
    const itemsProvided = Array.isArray(data.items);
    const dateChanged = data.withdrawal_date !== undefined &&
        String(data.withdrawal_date) !== String(existing.withdrawal_date);
    const stockAffecting = itemsProvided || dateChanged;
    if (!stockAffecting) {
        db.prepare(`
      UPDATE owner_withdrawals SET note = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
    `).run(data.note !== undefined ? data.note : existing.note, id);
        return { amount: existing.amount };
    }
    return db.transaction(() => {
        const newDate = data.withdrawal_date ?? existing.withdrawal_date;
        const newLines = itemsProvided
            ? data.items
            : getItems(db, id).map((r) => ({ item_id: r.item_id, warehouse_id: r.warehouse_id, quantity: r.quantity }));
        if (newLines.length === 0) {
            throw new Error('A goods withdrawal requires at least one item line');
        }
        // Restore the original consumption (compensating movements only),
        // then void the old GL posting.
        restoreConsumption(db, getOriginalMovements(db, existing.withdrawal_no), existing.withdrawal_no, opts.userId);
        accountingService_1.default.voidJournalLinesByReference(db, 'OWNER_WITHDRAWAL', id, {
            voidedBy: opts.userId ?? null,
            voidReason: 'Re-posted after edit',
        });
        // Fresh consumption at current FEFO/FIFO state.
        const { consumption, totalCost } = consumeForLines(db, newLines);
        if (totalCost <= 0) {
            throw new Error('Goods withdrawal value computed as zero — item cost data (batches/standard_cost) is missing');
        }
        db.prepare('DELETE FROM owner_withdrawal_items WHERE withdrawal_id = ?').run(id);
        insertItems(db, id, newLines);
        for (const e of consumption) {
            StockMovement_1.default.recordMovement({
                item_id: e.item_id,
                warehouse_id: e.warehouse_id,
                movement_type: 'OWNER_WITHDRAWAL',
                quantity: -e.consumed,
                unit_cost: e.unitCost,
                reference_doctype: 'OWNER_WITHDRAWAL',
                reference_docno: existing.withdrawal_no,
                remarks: `Owner withdrawal ${existing.withdrawal_no} (re-posted)`,
                movement_date: newDate,
                batch_id: e.batchId ?? undefined,
            }, opts.userId, db);
        }
        db.prepare(`
      UPDATE owner_withdrawals SET withdrawal_date = ?, amount = ?,
        note = COALESCE(?, note), updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(newDate, totalCost, data.note ?? null, id);
        accountingService_1.default.postOwnerWithdrawalGoodsEntry(db, {
            withdrawalId: id,
            withdrawalNo: existing.withdrawal_no,
            totalCost,
            withdrawalDate: newDate,
            userId: opts.userId,
        });
        return { amount: totalCost };
    })();
}
/**
 * Soft delete: goods stock returns via compensating movements, GL lines
 * are voided (kept with attribution), row marked voided. One transaction.
 */
function softVoid(db, id, opts) {
    const existing = getById(db, id);
    if (!existing)
        throw new Error('Owner withdrawal not found');
    if (existing.status === 'voided')
        throw new Error('Owner withdrawal is already voided');
    accountingService_1.default.assertPeriodNotClosed(db, existing.withdrawal_date, `Owner withdrawal ${existing.withdrawal_no}`);
    db.transaction(() => {
        if (existing.kind === 'goods') {
            restoreConsumption(db, getOriginalMovements(db, existing.withdrawal_no), existing.withdrawal_no, opts.userId);
        }
        accountingService_1.default.voidJournalLinesByReference(db, 'OWNER_WITHDRAWAL', id, {
            voidedBy: opts.userId ?? null,
            voidReason: opts.reason || 'Owner withdrawal voided',
        });
        db.prepare(`
      UPDATE owner_withdrawals SET status = 'voided', voided_at = CURRENT_TIMESTAMP,
        voided_by = ?, void_reason = ?, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(opts.userId ?? null, opts.reason || 'Owner withdrawal voided', id);
    })();
}
exports.default = {
    generateWithdrawalNo,
    create,
    quote,
    getAll,
    getCount,
    getById,
    getItems,
    getMovements,
    update,
    softVoid,
};
