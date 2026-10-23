import Database from 'better-sqlite3';
import { afterAll, describe, expect, it } from '@jest/globals';
import MobileInvoiceModel from '../models/MobileInvoice';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/**
 * Fallow health remediation — `MobileInvoice.updateDraft` (CRAP 72).
 * Covers populated and empty fields, JSON serialization, and the draft
 * status default.
 */
describe('MobileInvoice.createDraft', () => {
  function draftCustomer(db: Database.Database): number {
    const customer = db.prepare(`
      INSERT INTO customers (customer_code, customer_name)
      VALUES ('DRAFT-CREATE', 'Draft Create Customer')
    `).run();
    return Number(customer.lastInsertRowid);
  }

  it('writes populated fields and JSON items', () => {
    const db = createFixtureDb();
    const customerId = draftCustomer(db);

    const id = MobileInvoiceModel.createDraft(
      db,
      {
        customer_id: customerId,
        invoice_date: '2026-01-01',
        due_date: '2026-01-31',
        terms: 'Net 30',
        notes: 'new draft',
        items_data: [{ item_id: 3, quantity: 1 }],
      },
      'create-session',
    );

    const row = db
      .prepare('SELECT * FROM invoice_drafts WHERE id = ?')
      .get(id) as {
      customer_id: number;
      invoice_date: string;
      due_date: string;
      terms: string;
      notes: string;
      items_data: string;
      status: string;
    };
    expect(row).toMatchObject({
      customer_id: customerId,
      invoice_date: '2026-01-01',
      due_date: '2026-01-31',
      terms: 'Net 30',
      notes: 'new draft',
      items_data: JSON.stringify([{ item_id: 3, quantity: 1 }]),
      status: 'draft',
    });
    db.close();
  });

  it('nulls absent fields', () => {
    const db = createFixtureDb();

    const id = MobileInvoiceModel.createDraft(db, {}, 'empty-session');

    const row = db
      .prepare('SELECT * FROM invoice_drafts WHERE id = ?')
      .get(id) as {
      customer_id: number | null;
      invoice_date: string | null;
      due_date: string | null;
      terms: string | null;
      notes: string | null;
      items_data: string | null;
      status: string;
    };
    expect(row).toMatchObject({
      customer_id: null,
      invoice_date: null,
      due_date: null,
      terms: null,
      notes: null,
      items_data: null,
      status: 'draft',
    });
    db.close();
  });
});

describe('MobileInvoice.updateDraft', () => {
  function fixture(): {
    db: Database.Database;
    draftId: number;
    customerId: number;
  } {
    const db = createFixtureDb();
    const customer = db.prepare(`
      INSERT INTO customers (customer_code, customer_name)
      VALUES ('DRAFT-C', 'Draft Customer')
    `).run();
    const draftId = MobileInvoiceModel.createDraft(
      db,
      { customer_id: Number(customer.lastInsertRowid) },
      'draft-session',
    );
    return { db, draftId, customerId: Number(customer.lastInsertRowid) };
  }

  it('writes populated fields, JSON items and an explicit status', () => {
    const { db, draftId, customerId } = fixture();

    MobileInvoiceModel.updateDraft(db, draftId, {
      customer_id: customerId,
      invoice_date: '2026-02-01',
      due_date: '2026-02-28',
      terms: 'Net 60',
      notes: 'updated draft',
      items_data: [{ item_id: 7, quantity: 2 }],
      status: 'submitted',
    });

    const row = db
      .prepare('SELECT * FROM invoice_drafts WHERE id = ?')
      .get(draftId) as {
      customer_id: number;
      invoice_date: string;
      due_date: string;
      terms: string;
      notes: string;
      items_data: string;
      status: string;
    };
    expect(row).toMatchObject({
      customer_id: customerId,
      invoice_date: '2026-02-01',
      due_date: '2026-02-28',
      terms: 'Net 60',
      notes: 'updated draft',
      items_data: JSON.stringify([{ item_id: 7, quantity: 2 }]),
      status: 'submitted',
    });
    db.close();
  });

  it('nulls absent fields and defaults the status to draft', () => {
    const { db, draftId } = fixture();

    MobileInvoiceModel.updateDraft(db, draftId, {});

    const row = db
      .prepare('SELECT * FROM invoice_drafts WHERE id = ?')
      .get(draftId) as {
      customer_id: number | null;
      invoice_date: string | null;
      due_date: string | null;
      terms: string | null;
      notes: string | null;
      items_data: string | null;
      status: string;
    };
    expect(row).toMatchObject({
      customer_id: null,
      invoice_date: null,
      due_date: null,
      terms: null,
      notes: null,
      items_data: null,
      status: 'draft',
    });
    db.close();
  });

  it('returns the model through the default export', () => {
    expect(typeof MobileInvoiceModel.updateDraft).toBe('function');
  });
});
