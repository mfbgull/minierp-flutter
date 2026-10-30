import type Database from 'better-sqlite3';
import { BusinessRuleError } from '../utils/businessRuleError';

export interface ItemCompany {
  id: number;
  company_name: string;
  is_active: number;
  product_count: number;
}

export default class ItemCompanyModel {
  static get(id: number, db: Database.Database): ItemCompany {
    const company = db.prepare(`SELECT c.id, c.company_name, c.is_active,
      (SELECT COUNT(*) FROM items i WHERE i.company_id = c.id) AS product_count
      FROM item_companies c WHERE c.id = ?`).get(id) as ItemCompany | undefined;
    if (!company) throw new BusinessRuleError(404, 'Company not found');
    return company;
  }

  static list(search: string, status: string, page: number, limit: number, db: Database.Database) {
    const filter = status === 'all' ? null : status === 'archived' ? 0 : 1;
    const total = db.prepare(`SELECT COUNT(*) AS total FROM item_companies
      WHERE (? IS NULL OR is_active = ?) AND instr(lower(company_name), lower(?)) > 0`)
      .get(filter, filter, search) as { total: number };
    const rows = db.prepare(`SELECT c.id, c.company_name, c.is_active,
      (SELECT COUNT(*) FROM items i WHERE i.company_id = c.id) AS product_count
      FROM item_companies c WHERE (? IS NULL OR c.is_active = ?)
      AND instr(lower(c.company_name), lower(?)) > 0
      ORDER BY c.company_name COLLATE NOCASE, c.id LIMIT ? OFFSET ?`)
      .all(filter, filter, search, limit, (page - 1) * limit) as ItemCompany[];
    return { rows, total: total.total };
  }

  static create(name: string, db: Database.Database): ItemCompany {
    return db.transaction(() => {
      db.prepare('INSERT INTO item_companies(company_name) VALUES (?) ON CONFLICT(company_name) DO NOTHING').run(name);
      const row = db.prepare('SELECT id FROM item_companies WHERE company_name = ? COLLATE NOCASE').get(name) as { id: number };
      const company = this.get(row.id, db);
      if (company.is_active !== 1) {
        throw new BusinessRuleError(409, 'A company with this name is archived; restore it before use');
      }
      return company;
    })();
  }

  static rename(id: number, name: string, db: Database.Database): ItemCompany {
    return db.transaction(() => {
      this.get(id, db);
      const duplicate = db.prepare('SELECT id FROM item_companies WHERE company_name = ? COLLATE NOCASE AND id <> ?').get(name, id);
      if (duplicate) throw new BusinessRuleError(409, 'A company with this name already exists');
      db.prepare('UPDATE item_companies SET company_name = ? WHERE id = ?').run(name, id);
      db.prepare('UPDATE items SET manufacturer_name = ? WHERE company_id = ?').run(name, id);
      return this.get(id, db);
    })();
  }

  static setActive(id: number, active: boolean, db: Database.Database): ItemCompany {
    return db.transaction(() => {
      this.get(id, db);
      db.prepare('UPDATE item_companies SET is_active = ? WHERE id = ?').run(active ? 1 : 0, id);
      return this.get(id, db);
    })();
  }

  static delete(id: number, db: Database.Database): void {
    db.transaction(() => {
      if (this.get(id, db).product_count > 0) {
        throw new BusinessRuleError(409, 'Company is assigned to products; archive it instead');
      }
      db.prepare('DELETE FROM item_companies WHERE id = ?').run(id);
    })();
  }

  static products(id: number, page: number, limit: number, db: Database.Database) {
    const company = this.get(id, db);
    const rows = db.prepare(`SELECT id, item_code, item_name, category, unit_of_measure, is_active,
      company_id FROM items WHERE company_id = ? ORDER BY item_name, id LIMIT ? OFFSET ?`)
      .all(id, limit, (page - 1) * limit);
    return { rows, total: company.product_count };
  }
}
