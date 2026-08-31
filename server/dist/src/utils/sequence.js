"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getNextSequenceNumber = getNextSequenceNumber;
exports.generateDocNo = generateDocNo;
exports.initializeSequenceFromMax = initializeSequenceFromMax;
/**
 * Atomically get the next number in a sequence, using INSERT ... ON CONFLICT
 * to prevent race conditions under concurrent access.
 *
 * The settings table key is used as the sequence name.
 * First call initializes to 1, subsequent calls increment atomically.
 */
function getNextSequenceNumber(db, settingKey) {
    db.prepare(`
    INSERT INTO settings (key, value, updated_at)
    VALUES (?, '1', CURRENT_TIMESTAMP)
    ON CONFLICT(key) DO UPDATE SET
      value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT),
      updated_at = CURRENT_TIMESTAMP
  `).run(settingKey);
    const setting = db.prepare('SELECT value FROM settings WHERE key = ?').get(settingKey);
    return parseInt(setting.value, 10);
}
/**
 * Generate a year-based document number: PREFIX-YEAR-NNNN
 * e.g., generateDocNo(db, 'INV') → 'INV-2026-0001'
 */
function generateDocNo(db, prefix, padLength = 4) {
    const year = new Date().getFullYear();
    const settingKey = `${prefix}_last_no_${year}`;
    const nextNo = getNextSequenceNumber(db, settingKey);
    return `${prefix}-${year}-${nextNo.toString().padStart(padLength, '0')}`;
}
/**
 * Initialize a sequence from the MAX value already in a table column.
 * Only sets the value if the setting doesn't already exist.
 * The prefixPattern is used to filter existing codes (e.g. 'CUST', 'SUP-%').
 */
function initializeSequenceFromMax(db, settingKey, tableName, columnName, prefixPattern) {
    const allowedTables = new Set(['customers', 'suppliers', 'items', 'purchases', 'invoices', 'payments', 'productions', 'employees']);
    const allowedColumns = new Set(['customer_code', 'supplier_code', 'item_code', 'purchase_no', 'invoice_no', 'payment_no', 'production_no', 'employee_code']);
    if (!allowedTables.has(tableName) || !allowedColumns.has(columnName)) {
        throw new Error(`Invalid table or column name: ${tableName}.${columnName}`);
    }
    const existing = db.prepare('SELECT value FROM settings WHERE key = ?').get(settingKey);
    if (!existing) {
        // For payment_no, use numeric MAX to avoid string comparison bugs where
        // PAY1000 sorts before PAY999 alphabetically ('9' > '1' at position 3).
        // All other codes use fixed-length zero-padded suffixes, so string MAX is fine.
        let query;
        if (columnName === 'payment_no') {
            query = `SELECT MAX(CAST(SUBSTR(${columnName}, ${prefixPattern.length + 1}) AS INTEGER)) as max_val FROM ${tableName} WHERE ${columnName} LIKE ?`;
        }
        else {
            query = `SELECT MAX(${columnName}) as max_val FROM ${tableName} WHERE ${columnName} LIKE ?`;
        }
        const maxResult = db.prepare(query).get(`${prefixPattern}%`);
        const maxNo = maxResult?.max_val ?? 0;
        db.prepare('INSERT INTO settings (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)').run(settingKey, maxNo.toString());
    }
}
