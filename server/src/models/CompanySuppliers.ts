import type Database from 'better-sqlite3';
import ItemCompany from './ItemCompany';
import { BusinessRuleError } from '../utils/businessRuleError';

const history = `WITH history AS (
  SELECT p.supplier_id, p.item_id, p.purchase_date AS purchase_date
  FROM purchases p JOIN items i ON i.id = p.item_id
  WHERE i.company_id = @companyId AND p.voided_at IS NULL AND p.supplier_id IS NOT NULL
  UNION ALL
  SELECT po.supplier_id, gri.item_id, gr.receipt_date
  FROM goods_receipts gr JOIN goods_receipt_items gri ON gri.receipt_id = gr.id
  JOIN purchase_orders po ON po.id = gr.po_id JOIN items i ON i.id = gri.item_id
  WHERE i.company_id = @companyId AND gr.voided_at IS NULL
    AND po.status <> 'Cancelled' AND gri.received_quantity > 0
), relationships AS (
  SELECT supplier_id FROM history
  UNION SELECT supplier_id FROM item_company_suppliers WHERE company_id = @companyId
)`;

export default class CompanySuppliers {
  static list(companyId: number, page: number, limit: number, db: Database.Database) {
    ItemCompany.get(companyId, db);
    const params = { companyId, limit, offset: (page - 1) * limit };
    const rows = db.prepare(`${history}
      SELECT s.id AS supplier_id, s.supplier_name, s.contact_person, s.phone, s.email, s.is_active,
        EXISTS(SELECT 1 FROM item_company_suppliers l WHERE l.company_id = @companyId AND l.supplier_id = s.id) AS linked,
        EXISTS(SELECT 1 FROM history h WHERE h.supplier_id = s.id) AS purchased,
        (SELECT COUNT(DISTINCT h.item_id) FROM history h WHERE h.supplier_id = s.id) AS product_count,
        (SELECT MAX(h.purchase_date) FROM history h WHERE h.supplier_id = s.id) AS last_purchase_date
      FROM relationships r JOIN suppliers s ON s.id = r.supplier_id
      ORDER BY s.supplier_name COLLATE NOCASE, s.id LIMIT @limit OFFSET @offset
    `).all(params);
    const total = (db.prepare(`${history} SELECT COUNT(*) AS total FROM relationships`).get({ companyId }) as { total: number }).total;
    return { rows, total };
  }

  static products(companyId: number, supplierId: number, page: number, limit: number, db: Database.Database) {
    ItemCompany.get(companyId, db);
    const rows = db.prepare(`${history}
      SELECT i.id, i.item_code, i.item_name, i.unit_of_measure, MAX(h.purchase_date) AS last_purchase_date
      FROM history h JOIN items i ON i.id = h.item_id WHERE h.supplier_id = @supplierId
      GROUP BY i.id ORDER BY i.item_name, i.id LIMIT @limit OFFSET @offset
    `).all({ companyId, supplierId, limit, offset: (page - 1) * limit });
    const total = (db.prepare(`${history} SELECT COUNT(DISTINCT item_id) AS total FROM history WHERE supplier_id = @supplierId`).get({ companyId, supplierId }) as { total: number }).total;
    return { rows, total };
  }

  static setLinked(companyId: number, supplierId: number, linked: boolean, db: Database.Database): void {
    db.transaction(() => {
      const company = ItemCompany.get(companyId, db);
      const supplier = db.prepare('SELECT is_active FROM suppliers WHERE id = ?').get(supplierId) as { is_active: number } | undefined;
      if (!supplier) throw new BusinessRuleError(404, 'Supplier not found');
      if (linked && (!supplier.is_active || !company.is_active)) throw new BusinessRuleError(409, 'Company and supplier must be active to add a link');
      if (linked) db.prepare('INSERT INTO item_company_suppliers(company_id,supplier_id) VALUES (?,?) ON CONFLICT DO NOTHING').run(companyId, supplierId);
      else db.prepare('DELETE FROM item_company_suppliers WHERE company_id = ? AND supplier_id = ?').run(companyId, supplierId);
    })();
  }
}
