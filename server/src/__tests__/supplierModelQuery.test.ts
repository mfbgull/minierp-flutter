import Database from 'better-sqlite3';
import { afterAll, describe, expect, it } from '@jest/globals';
import SupplierModel from '../models/Supplier';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/**
 * Fallow health remediation — `Supplier.getAll` and `Supplier.update`
 * (CRAP 90 each). Covers search, status, invalid sort fallback, pagination,
 * full/partial updates, optional-field nulling, and the is_active default.
 */
function createFixture(): Database.Database {
  const db = createFixtureDb();
  const insert = db.prepare(`
    INSERT INTO suppliers (
      supplier_code, supplier_name, contact_person, email, phone, is_active
    ) VALUES (?, ?, ?, ?, ?, ?)
  `);
  insert.run('SUP-A', 'Acme Traders', 'Alice', 'alice@acme.test', '111', 1);
  insert.run('SUP-B', 'Beta Supplies', 'Bob', 'bob@beta.test', '222', 0);
  insert.run('SUP-C', 'Gamma Co', 'Carol', 'carol@gamma.test', '333', 1);
  return db;
}

describe('Supplier.getAll', () => {
  it('returns all rows with a total count', () => {
    const db = createFixture();
    const result = SupplierModel.getAll({}, 'supplier_name', 'ASC', 1, 10, db);
    expect(result.total).toBe(3);
    expect(result.data.map((row) => row.supplier_code)).toEqual([
      'SUP-A',
      'SUP-B',
      'SUP-C',
    ]);
    db.close();
  });

  it('searches across name, code, email, phone and contact person', () => {
    const db = createFixture();
    for (const term of ['Acme', 'SUP-B', 'carol@gamma', '222', 'Bob']) {
      const result = SupplierModel.getAll(
        { search: term },
        'supplier_name',
        'ASC',
        1,
        10,
        db,
      );
      expect(result.total).toBe(1);
    }
    db.close();
  });

  it('filters active and inactive suppliers', () => {
    const db = createFixture();
    expect(
      SupplierModel.getAll(
        { status: 'active' },
        'supplier_name',
        'ASC',
        1,
        10,
        db,
      ).total,
    ).toBe(2);
    expect(
      SupplierModel.getAll(
        { status: 'inactive' },
        'supplier_name',
        'ASC',
        1,
        10,
        db,
      ).total,
    ).toBe(1);
    db.close();
  });

  it('falls back to a safe sort and paginates', () => {
    const db = createFixture();
    const first = SupplierModel.getAll(
      {},
      'supplier_name; DROP TABLE x',
      'sideways',
      1,
      2,
      db,
    );
    expect(first.total).toBe(3);
    expect(first.data).toHaveLength(2);
    expect(first.data[0].supplier_code).toBe('SUP-A');

    const second = SupplierModel.getAll(
      {},
      'supplier_name',
      'ASC',
      2,
      2,
      db,
    );
    expect(second.data).toHaveLength(1);
    expect(second.data[0].supplier_code).toBe('SUP-C');
    db.close();
  });

  it('returns an empty page when nothing matches', () => {
    const db = createFixture();
    const result = SupplierModel.getAll(
      { search: 'no-such-supplier' },
      'supplier_name',
      'ASC',
      1,
      10,
      db,
    );
    expect(result.total).toBe(0);
    expect(result.data).toEqual([]);
    db.close();
  });
});

describe('Supplier.update', () => {
  function supplierId(db: Database.Database): number {
    return (
      db.prepare(`SELECT id FROM suppliers WHERE supplier_code = 'SUP-A'`).get() as {
        id: number;
      }
    ).id;
  }

  it('updates every optional field', () => {
    const db = createFixture();
    const id = supplierId(db);

    SupplierModel.update(
      id,
      {
        supplier_name: 'Acme Updated',
        contact_person: 'Alicia',
        email: 'alicia@acme.test',
        phone: '999',
        address: 'New address',
        payment_terms: 'Net 60',
        is_active: true,
      },
      db,
    );

    const row = db.prepare('SELECT * FROM suppliers WHERE id = ?').get(id) as {
      supplier_name: string;
      contact_person: string;
      email: string;
      phone: string;
      address: string;
      payment_terms: string;
      is_active: number;
    };
    expect(row).toMatchObject({
      supplier_name: 'Acme Updated',
      contact_person: 'Alicia',
      email: 'alicia@acme.test',
      phone: '999',
      address: 'New address',
      payment_terms: 'Net 60',
      is_active: 1,
    });
    db.close();
  });

  it('nulls empty optional fields and defaults is_active when omitted', () => {
    const db = createFixture();
    const id = supplierId(db);

    SupplierModel.update(
      id,
      {
        supplier_name: 'Acme Minimal',
        contact_person: '',
        email: '',
        phone: '',
        address: '',
        payment_terms: '',
      },
      db,
    );

    const row = db.prepare('SELECT * FROM suppliers WHERE id = ?').get(id) as {
      supplier_name: string;
      contact_person: string | null;
      email: string | null;
      phone: string | null;
      address: string | null;
      payment_terms: string | null;
      is_active: number;
    };
    expect(row).toMatchObject({
      supplier_name: 'Acme Minimal',
      contact_person: null,
      email: null,
      phone: null,
      address: null,
      payment_terms: null,
      is_active: 1,
    });
    db.close();
  });

  it('deactivates a supplier explicitly', () => {
    const db = createFixture();
    const id = supplierId(db);

    SupplierModel.update(
      id,
      { supplier_name: 'Acme Inactive', is_active: false },
      db,
    );

    const row = db
      .prepare('SELECT is_active FROM suppliers WHERE id = ?')
      .get(id) as { is_active: number };
    expect(row.is_active).toBe(0);
    db.close();
  });
});
