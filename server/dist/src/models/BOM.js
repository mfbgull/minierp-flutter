"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const sequence_1 = require("../utils/sequence");
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
// Whitelisted sort columns → qualified SQL column for the list query (the
// finished-item join makes bare names ambiguous).
const BOM_SORT_COLUMN_MAP = {
    bom_no: 'b.bom_no',
    bom_name: 'b.bom_name',
    finished_item_name: 'i.item_name',
    quantity: 'b.quantity',
    item_count: 'item_count',
    total_material_cost: 'total_material_cost',
    created_at: 'b.created_at',
};
class BOMModel {
    static generateBOMNo(db) {
        const year = new Date().getFullYear();
        const prefix = `BOM-${year}-`;
        const settingKey = `BOM_last_no_${year}`;
        // Seed from existing max on first call
        const existing = db.prepare('SELECT value FROM settings WHERE key = ?').get(settingKey);
        if (!existing) {
            const lastBOM = db.prepare(`
        SELECT bom_no FROM boms
        WHERE bom_no LIKE ?
        ORDER BY id DESC LIMIT 1
      `).get(`${prefix}%`);
            const maxNo = lastBOM ? parseInt(lastBOM.bom_no.split('-')[2], 10) || 0 : 0;
            db.prepare('INSERT INTO settings (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)').run(settingKey, maxNo.toString());
        }
        const nextNo = (0, sequence_1.getNextSequenceNumber)(db, settingKey);
        return `${prefix}${nextNo.toString().padStart(4, '0')}`;
    }
    static create(data, userId, db) {
        const { finished_item_id, quantity, bom_name, description, items } = data;
        const transaction = db.transaction(() => {
            const bomNo = this.generateBOMNo(db);
            const bomInsert = db.prepare(`
        INSERT INTO boms (bom_no, bom_name, finished_item_id, quantity, description, created_by)
        VALUES (?, ?, ?, ?, ?, ?)
      `);
            const result = bomInsert.run(bomNo, bom_name, finished_item_id, quantity, description || null, userId);
            const bomId = result.lastInsertRowid;
            const itemInsert = db.prepare(`
        INSERT INTO bom_items (bom_id, item_id, quantity)
        VALUES (?, ?, ?)
      `);
            for (const item of items) {
                itemInsert.run(bomId, item.item_id, item.quantity);
            }
            return this.getById(bomId, db);
        });
        return transaction();
    }
    static getAll(filters = {}, db) {
        const pageNum = filters.page || 1;
        const limitNum = filters.limit || 10;
        const select = `
      SELECT
        b.id,
        b.bom_no,
        b.bom_name,
        b.finished_item_id,
        i.item_code AS finished_item_code,
        i.item_name AS finished_item_name,
        i.unit_of_measure AS finished_uom,
        b.quantity,
        b.description,
        b.is_active,
        b.created_at,
        b.updated_at,
        (SELECT COUNT(*) FROM bom_items WHERE bom_id = b.id) AS item_count,
        (SELECT COALESCE(SUM(bi.quantity * it.standard_cost), 0)
         FROM bom_items bi
         JOIN items it ON bi.item_id = it.id
         WHERE bi.bom_id = b.id) AS total_material_cost
      FROM boms b
      JOIN items i ON b.finished_item_id = i.id
      WHERE 1=1
    `;
        const conditions = [];
        const params = [];
        if (filters.search) {
            conditions.push('(b.bom_no LIKE ? OR b.bom_name LIKE ? OR i.item_code LIKE ? OR i.item_name LIKE ?)');
            const term = `%${filters.search}%`;
            params.push(term, term, term, term);
        }
        const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';
        // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
        // (default matches the pre-paging behavior: newest BOM first).
        const { column, order } = (0, sqlSanitizer_1.sanitizeSortParams)(filters.sortBy || 'created_at', filters.sortOrder || 'DESC', sqlSanitizer_1.BOM_SORT_COLUMNS, 'created_at', 'DESC');
        const sortColumn = BOM_SORT_COLUMN_MAP[column] || 'b.created_at';
        const offset = (pageNum - 1) * limitNum;
        const rows = db
            .prepare(`${select}${where} ORDER BY ${sortColumn} ${order}, b.id DESC LIMIT ? OFFSET ?`)
            .all(...params, limitNum, offset);
        const countRow = db
            .prepare(`SELECT COUNT(*) as total FROM boms b
        JOIN items i ON b.finished_item_id = i.id
        WHERE 1=1${where}`)
            .get(...params);
        return { rows, total: countRow.total, pageNum, limitNum };
    }
    static getById(id, db) {
        const bom = db.prepare(`
      SELECT
        b.id,
        b.bom_no,
        b.bom_name,
        b.finished_item_id,
        i.item_code AS finished_item_code,
        i.item_name AS finished_item_name,
        i.unit_of_measure AS finished_uom,
        b.quantity,
        b.description,
        b.is_active,
        b.created_at,
        b.updated_at
      FROM boms b
      JOIN items i ON b.finished_item_id = i.id
      WHERE b.id = ?
    `).get(id);
        if (!bom) {
            return null;
        }
        const items = db.prepare(`
      SELECT
        bi.id,
        bi.item_id,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        i.current_stock,
        bi.quantity,
        i.standard_cost,
        (bi.quantity * i.standard_cost) AS line_cost
      FROM bom_items bi
      JOIN items i ON bi.item_id = i.id
      WHERE bi.bom_id = ?
      ORDER BY bi.id
    `).all(id);
        const total_material_cost = items.reduce((sum, item) => sum + (item.line_cost ?? 0), 0);
        return {
            ...bom,
            total_material_cost,
            items
        };
    }
    static getByFinishedItem(finishedItemId, db) {
        return db.prepare(`
      SELECT
        b.id,
        b.bom_no,
        b.bom_name,
        b.finished_item_id,
        i.item_code AS finished_item_code,
        i.item_name AS finished_item_name,
        i.unit_of_measure AS finished_uom,
        b.quantity,
        b.description,
        b.is_active
      FROM boms b
      JOIN items i ON b.finished_item_id = i.id
      WHERE b.finished_item_id = ? AND b.is_active = 1
      ORDER BY b.created_at DESC
    `).all(finishedItemId);
    }
    static update(id, data, userId, db) {
        const { bom_name, finished_item_id, description, quantity, is_active, items } = data;
        const existingBOM = BOMModel.getById(id, db);
        if (!existingBOM) {
            throw new Error('BOM not found');
        }
        const resolvedFinishedItemId = finished_item_id ?? existingBOM.finished_item_id;
        const item = db.prepare('SELECT id FROM items WHERE id = ?').get(resolvedFinishedItemId);
        if (!item) {
            throw new Error(`Item with id ${resolvedFinishedItemId} not found`);
        }
        const transaction = db.transaction(() => {
            const updateBOM = db.prepare(`
        UPDATE boms
        SET bom_name = ?, finished_item_id = ?, description = ?, quantity = ?, is_active = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `);
            updateBOM.run(bom_name, resolvedFinishedItemId, description || null, quantity, is_active !== undefined ? is_active : existingBOM.is_active, id);
            if (items) {
                db.prepare('DELETE FROM bom_items WHERE bom_id = ?').run(id);
                const itemInsert = db.prepare(`
          INSERT INTO bom_items (bom_id, item_id, quantity)
          VALUES (?, ?, ?)
        `);
                for (const item of items) {
                    itemInsert.run(id, item.item_id, item.quantity);
                }
            }
            return this.getById(id, db);
        });
        return transaction();
    }
    static delete(id, db) {
        const usedInProduction = db.prepare(`
      SELECT COUNT(*) as count FROM productions WHERE bom_id = ?
    `).get(id);
        if (usedInProduction.count > 0) {
            throw new Error('Cannot delete BOM: It has been used in production records');
        }
        const transaction = db.transaction(() => {
            db.prepare('DELETE FROM bom_items WHERE bom_id = ?').run(id);
            const result = db.prepare('DELETE FROM boms WHERE id = ?').run(id);
            if (result.changes === 0) {
                throw new Error('BOM not found');
            }
            return true;
        });
        return transaction();
    }
    static toggleActive(id, db) {
        const bom = db.prepare('SELECT is_active FROM boms WHERE id = ?').get(id);
        if (!bom) {
            throw new Error('BOM not found');
        }
        const newStatus = bom.is_active ? 0 : 1;
        db.prepare('UPDATE boms SET is_active = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
            .run(newStatus, id);
        return this.getById(id, db);
    }
}
exports.default = BOMModel;
