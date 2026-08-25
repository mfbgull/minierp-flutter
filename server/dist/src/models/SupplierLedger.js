"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class SupplierLedgerModel {
    static createEntry(data, db) {
        const { supplier_id, transaction_date, transaction_type, reference_no, debit = 0, credit = 0, description } = data;
        // Get current balance
        const currentBalance = this.getBalance(supplier_id, db);
        // Calculate new balance (debit increases liability, credit decreases)
        const newBalance = currentBalance + debit - credit;
        const stmt = db.prepare(`
      INSERT INTO supplier_ledger (
        supplier_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
        const result = stmt.run(supplier_id, transaction_date, transaction_type, reference_no || null, debit, credit, newBalance, description || null);
        return this.getById(result.lastInsertRowid, db);
    }
    static getById(id, db) {
        return db.prepare(`
      SELECT * FROM supplier_ledger WHERE id = ?
    `).get(id);
    }
    static getBalance(supplier_id, db) {
        // ACC-12: chain order is (transaction_date, id); ACC-14: voided rows
        // are excluded so reversals immediately restore the prior position.
        const result = db.prepare(`
      SELECT balance FROM supplier_ledger
      WHERE supplier_id = ? AND voided = 0 AND reversed_by IS NULL
      ORDER BY transaction_date DESC, id DESC
      LIMIT 1
    `).get(supplier_id);
        return result?.balance || 0;
    }
    /**
     * Recompute the running balance for every ledger row of a supplier
     * (balance = previous balance + debit - credit, in id order) and sync
     * suppliers.current_balance to the final row. Fixes chains corrupted by
     * mid-chain deletions or the old MAX(balance) model.
     */
    static rebuildBalances(supplierId, db) {
        const rows = db.prepare(`
      SELECT id, debit, credit FROM supplier_ledger
      WHERE supplier_id = ? AND voided = 0 AND reversed_by IS NULL
      ORDER BY transaction_date ASC, id ASC
    `).all(supplierId);
        let running = 0;
        const update = db.prepare('UPDATE supplier_ledger SET balance = ? WHERE id = ?');
        for (const row of rows) {
            running = running + (row.debit || 0) - (row.credit || 0);
            update.run(running, row.id);
        }
        db.prepare('UPDATE suppliers SET current_balance = ? WHERE id = ?').run(running, supplierId);
        return running;
    }
    static getTransactions(supplier_id, db) {
        return db.prepare(`
      SELECT * FROM supplier_ledger
      WHERE supplier_id = ?
      ORDER BY transaction_date DESC, created_at DESC
    `).all(supplier_id);
    }
    static getAllTransactions(db) {
        return db.prepare(`
      SELECT
        sl.*,
        s.supplier_name
      FROM supplier_ledger sl
      JOIN suppliers s ON sl.supplier_id = s.id
      ORDER BY sl.transaction_date DESC, sl.created_at DESC
    `).all();
    }
    static getSupplierBalances(db) {
        return db.prepare(`
      SELECT
        s.id as supplier_id,
        s.supplier_name,
        COALESCE(sl.balance, 0) as balance
      FROM suppliers s
      LEFT JOIN supplier_ledger sl
        ON s.id = sl.supplier_id
        AND sl.id = (
          SELECT MAX(id) FROM supplier_ledger WHERE supplier_id = s.id
        )
      WHERE s.is_active = 1
      ORDER BY balance DESC
    `).all();
    }
}
exports.default = SupplierLedgerModel;
